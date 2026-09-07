-- =============================================================================
-- SISTEMA DE GESTÃO DE AGÊNCIA DE VIAGENS — SCHEMA v1
-- Postgres / Supabase
--
-- Rodar via migration:
--   supabase migration new schema_v1   (cola este conteúdo)
--   supabase db reset                  (local)
--   supabase db push                   (produção, depois do link)
--
-- HIERARQUIA: VIAGEM -> RESERVA (uma por portal) -> SERVIÇO
--
-- REGRAS EMBUTIDAS:
--  * Valores digitados: total, taxas e valor da comissão. Percentual é derivado.
--  * RAV da operadora (recebido dela) é diferente de RAV do cliente
--    (diferença entre o que o cliente paga e o que a operadora cobra) — o 2º é calculado.
--  * Repasse ao vendedor = % sobre o LUCRO da viagem, calculado no nível viagem,
--    só liberado depois que a comissão da operadora entra.
--  * Vendedor externo vê apenas o valor do repasse dele — nunca comissão,
--    custo, resultado ou o próprio percentual. Acesso via VIEW, não pela tabela.
--  * Usuário pode existir sem login (vendedor externo que não usa o sistema).
--  * MEI: imposto é despesa, não alíquota. Teto anual monitorado no dashboard.
--  * Sem parcelamento próprio: só flag pago/recebido.
--  * Soft delete em tudo que tem valor financeiro.
--  * MULTIEMPRESA desde o início: agencia_id nas tabelas raiz e RLS por agência.
--    Uma agência na piloto, mas a segunda entra por cadastro, não por refatoração.
--
-- API em C# (ASP.NET Core + Npgsql): para a RLS continuar valendo através da API,
-- cada requisição deve abrir a conexão e executar, dentro da transação:
--    SET LOCAL role authenticated;
--    SET LOCAL request.jwt.claims = '{"sub":"<auth_user_id>"}';
-- Sem isso, a conexão usa credencial de serviço e a autorização passa a depender
-- inteiramente do código C#.
-- =============================================================================

create extension if not exists "pgcrypto";

-- =============================================================================
-- 1. ENUMS
-- =============================================================================

create type tipo_fornecedor  as enum ('operadora','consolidadora','cia_aerea','hotel','seguradora','receptivo','despachante','outro');
create type tipo_receita     as enum ('comissao','markup','taxa_servico');
create type status_reserva   as enum ('pendente','emitida','alterada','cancelada');
create type tipo_servico     as enum ('aereo','hospedagem','traslado','passeio','seguro','ingresso','aluguel_carro','documentacao','outro');
create type estagio_oport    as enum ('novo','cotando','orcamento_enviado','negociacao','ganho','perdido');
create type tipo_documento   as enum ('rg','cpf','passaporte','visto','certidao','outro');
create type status_tarefa    as enum ('aberta','concluida','cancelada');
create type status_nfse      as enum ('falta_emitir','emitido','nao_precisa');
create type tomador_nfse     as enum ('cliente','operadora');
create type forma_pagamento  as enum ('pix','cartao_credito','cartao_debito','boleto','transferencia','dinheiro','link_pagamento','outro');
create type dono_cartao      as enum ('cliente','agencia','nao_se_aplica');
create type status_repasse   as enum ('bloqueado','a_pagar','pago');
create type tipo_anexo       as enum ('voucher','comprovante','documento','contrato','extrato','outro');
create type tipo_despesa     as enum ('fixa','variavel','imposto','repasse');

-- =============================================================================
-- 2. AGÊNCIA (multiempresa)
-- =============================================================================
-- Nasce multiempresa mesmo com uma agência na piloto: incluir agencia_id depois
-- significaria migrar dados reais e reescrever todas as policies.

create table agencia (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null,
  cnpj      text,
  plano     text not null default 'piloto',
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);

-- =============================================================================
-- 3. USUÁRIOS, PERFIS E PERMISSÕES
-- =============================================================================
-- usuario tem id próprio. auth_user_id é NULO para quem não tem login
-- (vendedor externo que só é referenciado nas viagens).

create table usuario (
  id                uuid primary key default gen_random_uuid(),
  agencia_id        uuid not null references agencia(id),
  auth_user_id      uuid unique references auth.users(id) on delete set null,
  nome              text not null,
  email             text,
  telefone          text,
  -- vendedor externo: gera repasse. Dono e agentes internos: não.
  gera_repasse      boolean not null default false,
  percentual_padrao numeric(5,2) not null default 0,
  ativo             boolean not null default true,
  ultimo_acesso     timestamptz,
  criado_em         timestamptz not null default now()
);

create table perfil (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null unique,
  descricao text,
  -- perfis de sistema não podem ser excluídos (evita se trancar para fora)
  sistema   boolean not null default false
);

create table permissao (
  chave     text primary key,          -- formato: modulo.acao
  modulo    text not null,
  descricao text not null
);

create table perfil_permissao (
  perfil_id      uuid references perfil(id) on delete cascade,
  permissao_chave text references permissao(chave) on delete cascade,
  primary key (perfil_id, permissao_chave)
);

create table usuario_perfil (
  usuario_id uuid references usuario(id) on delete cascade,
  perfil_id  uuid references perfil(id)  on delete cascade,
  primary key (usuario_id, perfil_id)
);

-- exceção pontual. negar sempre vence conceder.
create table usuario_permissao (
  usuario_id      uuid references usuario(id) on delete cascade,
  permissao_chave text references permissao(chave) on delete cascade,
  conceder        boolean not null,
  primary key (usuario_id, permissao_chave)
);

create table log_acesso (
  id         bigserial primary key,
  email      text,
  usuario_id uuid references usuario(id),
  sucesso    boolean not null,
  ip         text,
  criado_em  timestamptz not null default now()
);

-- --- helpers de autorização -------------------------------------------------

create or replace function usuario_atual() returns uuid as $$
  select id from usuario where auth_user_id = auth.uid() and ativo;
$$ language sql stable security definer;

-- Toda consulta filtra por agência. Sem exceção.
create or replace function agencia_atual() returns uuid as $$
  select agencia_id from usuario where auth_user_id = auth.uid() and ativo;
$$ language sql stable security definer;

create or replace function tem_permissao(p_chave text) returns boolean as $$
  with u as (select usuario_atual() as id)
  select case
    when exists (select 1 from usuario_permissao up, u
                  where up.usuario_id = u.id and up.permissao_chave = p_chave
                    and not up.conceder) then false
    when exists (select 1 from usuario_permissao up, u
                  where up.usuario_id = u.id and up.permissao_chave = p_chave
                    and up.conceder) then true
    else exists (select 1 from usuario_perfil pu
                   join perfil_permissao pp on pp.perfil_id = pu.perfil_id, u
                  where pu.usuario_id = u.id and pp.permissao_chave = p_chave)
  end;
$$ language sql stable security definer;

-- --- seed --------------------------------------------------------------------

insert into permissao (chave, modulo, descricao) values
  ('viagem.ver',                  'Viagem',     'Ver viagens'),
  ('viagem.criar',                'Viagem',     'Criar viagem'),
  ('viagem.editar',               'Viagem',     'Editar viagem'),
  ('viagem.excluir',              'Viagem',     'Excluir viagem'),
  ('viagem.definir_vendedor',     'Viagem',     'Atribuir a venda a outro vendedor'),
  ('viagem.ver_resultado',        'Viagem',     'Ver o lucro da agência na viagem'),
  ('viagem.transferir',           'Viagem',     'Transferir viagem entre agentes'),
  ('reserva.ver_custo',           'Reserva',    'Ver custo, comissão e RAV da operadora'),
  ('reserva.editar_apos_conciliado','Reserva',   'Alterar valor já conciliado ou de mês fechado'),
  ('cliente.ver_documento',       'Cliente',    'Ver documentos pessoais do cliente'),
  ('financeiro.ver_dre',          'Financeiro', 'Ver a DRE e o resultado da agência'),
  ('financeiro.conciliar',        'Financeiro', 'Registrar recebimento de comissão'),
  ('financeiro.pagar_repasse',    'Financeiro', 'Liberar e pagar repasse de vendedor'),
  ('despesa.lancar',              'Financeiro', 'Lançar despesas'),
  ('usuario.gerenciar',           'Admin',      'Gerenciar usuários e permissões'),
  ('auditoria.ver',               'Admin',      'Consultar o log de auditoria');

insert into perfil (nome, descricao, sistema) values
  ('Dono',             'Acesso total',                                true),
  ('Financeiro',       'Conciliação, despesas e relatórios',          false),
  ('Agente',           'Operação completa, sem administração',        false),
  ('Vendedor externo', 'Vê apenas as próprias viagens e o repasse',   true),
  ('Contador',         'Somente leitura dos relatórios financeiros',  false);

insert into perfil_permissao (perfil_id, permissao_chave)
select p.id, x.chave from perfil p, permissao x where p.nome = 'Dono';

insert into perfil_permissao (perfil_id, permissao_chave)
select p.id, unnest(array['viagem.ver','viagem.criar','viagem.editar',
                          'viagem.definir_vendedor','reserva.ver_custo',
                          'cliente.ver_documento'])
  from perfil p where p.nome = 'Agente';

insert into perfil_permissao (perfil_id, permissao_chave)
select p.id, unnest(array['viagem.ver','viagem.ver_resultado','reserva.ver_custo',
                          'financeiro.ver_dre','financeiro.conciliar',
                          'financeiro.pagar_repasse','despesa.lancar'])
  from perfil p where p.nome = 'Financeiro';

-- Vendedor externo NÃO recebe viagem.ver: ele acessa somente as views próprias.

-- =============================================================================
-- 3. CLIENTES E CRM
-- =============================================================================

create table cliente (
  id              uuid primary key default gen_random_uuid(),
  agencia_id      uuid not null references agencia(id),
  nome            text not null,
  email           text,
  telefone        text,
  whatsapp        text,
  data_nascimento date,
  cidade          text,
  uf              char(2),
  origem_lead     text,
  tags            text[] not null default '{}',
  observacoes     text,
  ativo           boolean not null default true,
  excluido_em     timestamptz,
  excluido_por    uuid references usuario(id),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create index on cliente using gin (tags);
create index on cliente (nome);

create table documento_cliente (
  id           uuid primary key default gen_random_uuid(),
  cliente_id   uuid not null references cliente(id) on delete cascade,
  tipo         tipo_documento not null,
  numero       text,
  emissao      date,
  validade     date,
  pais_emissor text,
  criado_em    timestamptz not null default now()
);
create index on documento_cliente (validade);

create table interacao (
  id         uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references cliente(id) on delete cascade,
  usuario_id uuid references usuario(id),
  data       timestamptz not null default now(),
  canal      text,
  resumo     text not null
);
create index on interacao (cliente_id, data desc);

create table oportunidade (
  id                 uuid primary key default gen_random_uuid(),
  cliente_id         uuid not null references cliente(id) on delete cascade,
  usuario_id         uuid references usuario(id),
  destino_pretendido text,
  periodo_estimado   text,
  num_pax            int,
  valor_estimado     numeric(12,2),
  estagio            estagio_oport not null default 'novo',
  motivo_perda       text,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now()
);

create table tarefa (
  id          uuid primary key default gen_random_uuid(),
  titulo      text not null,
  descricao   text,
  data        date not null,
  usuario_id  uuid references usuario(id),
  cliente_id  uuid references cliente(id) on delete cascade,
  viagem_id   uuid,
  status      status_tarefa not null default 'aberta',
  origem      text not null default 'manual',
  chave_unica text unique,
  criado_em   timestamptz not null default now()
);
create index on tarefa (data, status);

-- =============================================================================
-- 4. FORNECEDORES E REGRA DE PAGAMENTO DE COMISSÃO
-- =============================================================================

create table fornecedor (
  id                  uuid primary key default gen_random_uuid(),
  agencia_id          uuid not null references agencia(id),
  nome                text not null,
  tipo                tipo_fornecedor not null default 'operadora',
  site                text,
  contato             text,
  telefone            text,
  -- plantão 24h para o viajante em viagem
  telefone_emergencia text,
  prazo_comissao_dias int,        -- alternativa quando não há fechamento fixo
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now()
);

-- Ex.: vendas de 1 a 14 pagam dia 20 do mesmo mês;
--      vendas de 15 a 31 pagam dia 05 do mês seguinte.
create table regra_pagamento_fornecedor (
  id            uuid primary key default gen_random_uuid(),
  fornecedor_id uuid not null references fornecedor(id) on delete cascade,
  dia_inicial   int not null check (dia_inicial between 1 and 31),
  dia_final     int not null check (dia_final   between 1 and 31),
  dia_pagamento int not null check (dia_pagamento between 1 and 31),
  meses_a_frente int not null default 0    -- 0 = mesmo mês, 1 = mês seguinte
);

create or replace function prever_pagamento(p_fornecedor uuid, p_data date)
returns date as $$
declare r record; f record;
begin
  select * into r from regra_pagamento_fornecedor
   where fornecedor_id = p_fornecedor
     and extract(day from p_data) between dia_inicial and dia_final
   limit 1;
  if found then
    return (date_trunc('month', p_data) + (r.meses_a_frente || ' month')::interval
            + (r.dia_pagamento - 1 || ' day')::interval)::date;
  end if;
  select prazo_comissao_dias into f from fornecedor where id = p_fornecedor;
  return p_data + coalesce(f.prazo_comissao_dias, 30);
end; $$ language plpgsql stable;

-- =============================================================================
-- 5. VIAGEM
-- =============================================================================

-- Código sequencial POR AGÊNCIA. Uma sequence global entregaria para a agência B
-- quantas viagens a agência A já fez.
create table contador_viagem (
  agencia_id uuid not null references agencia(id),
  ano        int not null,
  ultimo     int not null default 0,
  primary key (agencia_id, ano)
);

create table viagem (
  id                  uuid primary key default gen_random_uuid(),
  agencia_id          uuid not null references agencia(id),
  codigo              text not null,
  cliente_id          uuid not null references cliente(id),
  oportunidade_id     uuid references oportunidade(id),
  vendedor_id         uuid references usuario(id),
  agente_id           uuid references usuario(id),   -- quem opera (pode transferir)
  percentual_vendedor numeric(5,2) not null default 0,
  destino             text not null,
  pais                text,
  data_ida            date,
  data_volta          date,
  num_pax             int not null default 1,
  ocasiao             text,          -- lua de mel, aniversário, bodas
  status_repasse      status_repasse not null default 'bloqueado',
  data_pagto_repasse  date,
  cancelada           boolean not null default false,
  motivo_cancelamento text,
  observacoes         text,
  excluido_em         timestamptz,
  excluido_por        uuid references usuario(id),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  constraint datas_coerentes check (data_volta is null or data_ida is null or data_volta >= data_ida)
);
create unique index on viagem (agencia_id, codigo);
create index on viagem (agencia_id);
create index on viagem (data_ida);
create index on viagem (data_volta);
create index on viagem (cliente_id);
create index on viagem (vendedor_id);

create or replace function fn_codigo_viagem() returns trigger as $$
declare v_ano int := extract(year from now())::int; v_seq int;
begin
  if new.codigo is not null and new.codigo <> '' then return new; end if;
  insert into contador_viagem (agencia_id, ano, ultimo)
  values (new.agencia_id, v_ano, 1)
  on conflict (agencia_id, ano) do update set ultimo = contador_viagem.ultimo + 1
  returning ultimo into v_seq;
  new.codigo := 'VG-' || v_ano || '-' || lpad(v_seq::text, 4, '0');
  return new;
end; $$ language plpgsql;

create trigger trg_codigo_viagem before insert on viagem
  for each row execute function fn_codigo_viagem();

alter table tarefa add constraint tarefa_viagem_fk
  foreign key (viagem_id) references viagem(id) on delete cascade;

create table viagem_passageiro (
  id              uuid primary key default gen_random_uuid(),
  viagem_id       uuid not null references viagem(id) on delete cascade,
  cliente_id      uuid references cliente(id),
  nome            text not null,
  data_nascimento date,
  documento       text,
  titular         boolean not null default false
);

-- =============================================================================
-- 6. RESERVA — UMA POR PORTAL
-- =============================================================================

create table reserva (
  id                  uuid primary key default gen_random_uuid(),
  viagem_id           uuid not null references viagem(id) on delete cascade,
  fornecedor_id       uuid references fornecedor(id),   -- NULO = venda direta
  fornecedor_avulso   text,
  localizador         text,
  data_compra         date not null default current_date,

  tipo_receita        tipo_receita not null default 'comissao',

  -- DIGITADOS PELO USUÁRIO
  valor_total         numeric(12,2) not null default 0,  -- total cobrado pela operadora
  valor_taxas         numeric(12,2) not null default 0,  -- parte do total que é taxa
  valor_comissao      numeric(12,2) not null default 0,  -- valor informado pela operadora
  valor_cliente       numeric(12,2) not null default 0,  -- o que o cliente pagou
  valor_custo         numeric(12,2) not null default 0,  -- venda direta: custo do fornecedor
  taxa_servico        numeric(12,2) not null default 0,

  rav_operadora       numeric(12,2) not null default 0,  -- incentivo pago pela operadora
  valor_multa         numeric(12,2) not null default 0,

  -- DERIVADOS
  -- RAV do cliente: o que se cobrou acima do valor da operadora.
  -- Negativo = desconto concedido (que hoje some na planilha).
  rav_cliente numeric(12,2) generated always as (valor_cliente - valor_total) stored,
  percentual_comissao numeric(6,2) generated always as (
    case when valor_total > 0 then round(100 * valor_comissao / valor_total, 2) end
  ) stored,
  receita_prevista numeric(12,2) generated always as (
    case tipo_receita
      when 'comissao'     then valor_comissao + rav_operadora + (valor_cliente - valor_total) + taxa_servico
      when 'markup'       then (valor_cliente - valor_custo) + taxa_servico
      when 'taxa_servico' then taxa_servico
    end
  ) stored,

  -- conciliação
  comissao_recebida       numeric(12,2),
  data_prevista_comissao  date,
  data_recebimento        date,
  divergencia_motivo      text,

  -- fiscal e pagamento
  nfse_status         status_nfse not null default 'nao_precisa',
  nfse_tomador        tomador_nfse,
  nfse_numero         text,
  nfse_data_emissao   date,
  forma_pagamento     forma_pagamento,
  cartao_de           dono_cartao not null default 'nao_se_aplica',
  recebido_do_cliente boolean not null default false,
  pago_ao_fornecedor  boolean not null default false,

  moeda               char(3) not null default 'BRL',
  cambio              numeric(10,4) not null default 1,
  status              status_reserva not null default 'pendente',
  mes_fechado         boolean not null default false,
  observacoes         text,
  excluido_em         timestamptz,
  excluido_por        uuid references usuario(id),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),

  receita_realizada numeric(12,2) generated always as (
    case tipo_receita
      when 'comissao'     then coalesce(comissao_recebida,0) + rav_operadora
                               + (valor_cliente - valor_total)
                               + case when recebido_do_cliente then taxa_servico else 0 end
      when 'markup'       then case when recebido_do_cliente
                                    then (valor_cliente - valor_custo) + taxa_servico else 0 end
      when 'taxa_servico' then case when recebido_do_cliente then taxa_servico else 0 end
    end - valor_multa
  ) stored
);
create index on reserva (viagem_id);
create index on reserva (fornecedor_id);
create index on reserva (data_prevista_comissao) where data_recebimento is null;

-- preenche a previsão de pagamento a partir da regra do fornecedor.
-- Grava o valor (não calcula em tempo real) para não reescrever o histórico
-- quando a operadora mudar de regra. Continua editável.
create or replace function fn_prever_comissao() returns trigger as $$
begin
  if new.data_prevista_comissao is null and new.fornecedor_id is not null then
    new.data_prevista_comissao := prever_pagamento(new.fornecedor_id, new.data_compra);
  end if;
  return new;
end; $$ language plpgsql;

create trigger trg_prever_comissao before insert on reserva
  for each row execute function fn_prever_comissao();

-- histórico de alteração/remarcação (o que mudou comercialmente, não campo a campo)
create table reserva_alteracao (
  id             uuid primary key default gen_random_uuid(),
  reserva_id     uuid not null references reserva(id) on delete cascade,
  data           date not null default current_date,
  descricao      text not null,
  valor_anterior numeric(12,2),
  valor_novo     numeric(12,2),
  multa          numeric(12,2) not null default 0,
  usuario_id     uuid references usuario(id),
  criado_em      timestamptz not null default now()
);

-- crédito de cancelamento: dinheiro que fica na operadora e todo mundo esquece
create table credito (
  id            uuid primary key default gen_random_uuid(),
  cliente_id    uuid references cliente(id),
  fornecedor_id uuid references fornecedor(id),
  reserva_origem uuid references reserva(id),
  valor         numeric(12,2) not null,
  validade      date,
  utilizado     boolean not null default false,
  reserva_uso   uuid references reserva(id),
  observacoes   text,
  criado_em     timestamptz not null default now()
);
create index on credito (validade) where not utilizado;

-- =============================================================================
-- 7. SERVIÇO
-- =============================================================================
-- `detalhe` guarda o que varia por tipo (voo, bilhete, regime, apólice, bagagem,
-- assento) sem virar 40 colunas nulas.

create table servico (
  id           uuid primary key default gen_random_uuid(),
  reserva_id   uuid not null references reserva(id) on delete cascade,
  tipo         tipo_servico not null,
  titulo       text not null,
  data_inicio  timestamptz,
  data_fim     timestamptz,
  local        text,
  localizador_cia text,      -- diferente do localizador da operadora
  numero_bilhete  text,
  detalhe      jsonb not null default '{}',
  observacoes  text,
  ordem        int not null default 0
);
create index on servico (reserva_id);
create index on servico (data_inicio);

-- =============================================================================
-- 8. ANEXOS
-- =============================================================================
-- Um só lugar para arquivo de cliente, viagem e reserva.
-- Bucket PRIVADO, acesso por URL assinada.

create table anexo (
  id           uuid primary key default gen_random_uuid(),
  cliente_id   uuid references cliente(id) on delete cascade,
  viagem_id    uuid references viagem(id)  on delete cascade,
  reserva_id   uuid references reserva(id) on delete cascade,
  tipo         tipo_anexo not null default 'outro',
  nome_arquivo text not null,
  caminho      text not null,          -- path no storage
  tamanho_bytes bigint,
  sensivel     boolean not null default false,  -- documento pessoal
  data_descarte date,                  -- LGPD: expurgo programado
  enviado_por  uuid references usuario(id),
  criado_em    timestamptz not null default now(),
  constraint anexo_tem_vinculo check (
    cliente_id is not null or viagem_id is not null or reserva_id is not null)
);

-- =============================================================================
-- 9. DESPESAS (base da DRE — construir na v1.1, tabela já criada)
-- =============================================================================

create table despesa (
  id           uuid primary key default gen_random_uuid(),
  agencia_id   uuid not null references agencia(id),
  descricao    text not null,
  categoria    text not null,
  tipo         tipo_despesa not null default 'variavel',
  valor        numeric(12,2) not null,
  competencia  date not null,       -- mês de referência
  vencimento   date,
  pago         boolean not null default false,
  data_pagamento date,
  recorrente   boolean not null default false,
  viagem_id    uuid references viagem(id),   -- repasse vinculado
  usuario_id   uuid references usuario(id),  -- repasse: para quem
  criado_em    timestamptz not null default now()
);
create index on despesa (competencia);

-- =============================================================================
-- 10. AUDITORIA
-- =============================================================================

create table auditoria (
  id             bigserial primary key,
  tabela         text not null,
  registro_id    uuid not null,
  acao           text not null,
  campo          text,
  valor_anterior text,
  valor_novo     text,
  motivo         text,
  usuario_id     uuid,
  criado_em      timestamptz not null default now()
);
create index on auditoria (tabela, registro_id, criado_em desc);

create or replace function fn_auditoria() returns trigger as $$
declare
  v_old jsonb := case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;
  v_new jsonb := case when tg_op='DELETE' then '{}'::jsonb else to_jsonb(new) end;
  k text;
begin
  for k in select jsonb_object_keys(v_old || v_new) loop
    if k not in ('atualizado_em') and (v_old->k) is distinct from (v_new->k) then
      insert into auditoria(tabela, registro_id, acao, campo, valor_anterior, valor_novo, usuario_id)
      values (tg_table_name,
              coalesce((v_new->>'id')::uuid, (v_old->>'id')::uuid),
              tg_op, k, v_old->>k, v_new->>k, usuario_atual());
    end if;
  end loop;
  return coalesce(new, old);
end; $$ language plpgsql security definer;

create trigger aud_viagem  after insert or update or delete on viagem  for each row execute function fn_auditoria();
create trigger aud_reserva after insert or update or delete on reserva for each row execute function fn_auditoria();
create trigger aud_servico after insert or update or delete on servico for each row execute function fn_auditoria();
create trigger aud_despesa after insert or update or delete on despesa for each row execute function fn_auditoria();
create trigger aud_usuario after insert or update or delete on usuario for each row execute function fn_auditoria();

-- trava de mês fechado
create or replace function fn_trava_mes_fechado() returns trigger as $$
begin
  if old.mes_fechado and not tem_permissao('reserva.editar_apos_conciliado') then
    raise exception 'Reserva de mês fechado. Requer permissão específica.';
  end if;
  return new;
end; $$ language plpgsql;

create trigger trg_trava_mes before update on reserva
  for each row execute function fn_trava_mes_fechado();

-- =============================================================================
-- 11. VIEWS
-- =============================================================================

create view vw_resultado_viagem as
select
  v.id, v.codigo, v.destino, v.data_ida, v.data_volta, v.cancelada,
  c.nome as cliente, u.nome as vendedor,
  count(r.id)              as qtd_reservas,
  sum(r.valor_cliente)     as volume_vendido,
  sum(r.receita_prevista)  as receita_prevista,
  sum(r.receita_realizada) as receita_realizada,
  round(sum(r.receita_prevista)  * v.percentual_vendedor / 100, 2) as repasse_previsto,
  round(sum(r.receita_realizada) * v.percentual_vendedor / 100, 2) as repasse_realizado,
  sum(r.receita_realizada)
    - round(sum(r.receita_realizada) * v.percentual_vendedor / 100, 2) as resultado_agencia
from viagem v
join cliente c on c.id = v.cliente_id
left join usuario u on u.id = v.vendedor_id
left join reserva r on r.viagem_id = v.id and r.status <> 'cancelada' and r.excluido_em is null
where v.excluido_em is null
group by v.id, c.nome, u.nome;

-- O QUE O VENDEDOR EXTERNO VÊ. Sem custo, sem comissão, sem percentual.
create view vw_minha_viagem with (security_invoker = true) as
select
  v.id, v.codigo, v.destino, v.data_ida, v.data_volta, v.num_pax,
  c.nome as cliente,
  (select sum(r.valor_cliente) from reserva r
    where r.viagem_id = v.id and r.status <> 'cancelada') as valor_vendido,
  v.status_repasse, v.data_pagto_repasse,
  (select round(sum(r.receita_realizada) * v.percentual_vendedor / 100, 2)
     from reserva r where r.viagem_id = v.id and r.status <> 'cancelada') as meu_repasse
from viagem v
join cliente c on c.id = v.cliente_id
where v.excluido_em is null and v.vendedor_id = usuario_atual();

create view vw_reserva_vendedor with (security_invoker = true) as
select r.id, r.viagem_id, coalesce(f.nome, r.fornecedor_avulso) as fornecedor,
       r.localizador, r.data_compra, r.valor_cliente, r.status
from reserva r
join viagem v on v.id = r.viagem_id
left join fornecedor f on f.id = r.fornecedor_id
where v.vendedor_id = usuario_atual() and r.excluido_em is null;

create view vw_fase_viagem as
select v.id,
  case
    when v.cancelada                 then 'cancelada'
    when v.data_volta < current_date then 'concluida'
    when v.data_ida  <= current_date then 'em_viagem'
    when exists (select 1 from reserva r where r.viagem_id = v.id and r.status='pendente') then 'em_emissao'
    when exists (select 1 from reserva r where r.viagem_id = v.id) then 'confirmada'
    else 'sem_reserva' end as fase_operacional,
  case
    when not exists (select 1 from reserva r where r.viagem_id = v.id and r.receita_prevista > 0) then 'sem_receita'
    when not exists (select 1 from reserva r where r.viagem_id = v.id and r.data_recebimento is null) then 'quitada'
    when exists (select 1 from reserva r where r.viagem_id = v.id
                   and r.data_recebimento is null and r.data_prevista_comissao < current_date) then 'atrasada'
    when exists (select 1 from reserva r where r.viagem_id = v.id and r.data_recebimento is not null) then 'parcial'
    else 'a_receber' end as fase_financeira
from viagem v where v.excluido_em is null;

create view vw_comissao_pendente as
select r.id as reserva_id, v.codigo, c.nome as cliente,
       coalesce(f.nome, r.fornecedor_avulso, 'Venda direta') as fornecedor,
       r.localizador, r.data_compra, r.data_prevista_comissao, r.receita_prevista,
       current_date - r.data_prevista_comissao as dias_atraso
from reserva r
join viagem v on v.id = r.viagem_id
join cliente c on c.id = v.cliente_id
left join fornecedor f on f.id = r.fornecedor_id
where r.data_recebimento is null and r.status <> 'cancelada'
  and r.excluido_em is null and r.receita_prevista > 0;

create view vw_agenda as
select v.id as viagem_id, v.codigo, c.nome as cliente, 'embarque' as evento, v.data_ida as data
  from viagem v join cliente c on c.id = v.cliente_id
 where not v.cancelada and v.excluido_em is null and v.data_ida >= current_date
union all
select v.id, v.codigo, c.nome, 'retorno', v.data_volta
  from viagem v join cliente c on c.id = v.cliente_id
 where not v.cancelada and v.excluido_em is null and v.data_volta >= current_date
union all
select v.id, v.codigo, c.nome, 'comissao_prevista', r.data_prevista_comissao
  from reserva r join viagem v on v.id = r.viagem_id join cliente c on c.id = v.cliente_id
 where r.data_recebimento is null and r.data_prevista_comissao is not null
union all
select null, null, c.nome, 'passaporte_vence', d.validade
  from documento_cliente d join cliente c on c.id = d.cliente_id
 where d.tipo = 'passaporte' and d.validade > current_date;

create view vw_dashboard_mensal as
select date_trunc('month', r.data_compra)::date as mes,
       count(distinct v.id)     as viagens,
       sum(r.valor_cliente)     as volume_vendido,
       sum(r.receita_prevista)  as receita_prevista,
       sum(r.receita_realizada) as receita_realizada
from reserva r join viagem v on v.id = r.viagem_id
where r.status <> 'cancelada' and r.excluido_em is null
group by 1 order by 1 desc;

-- Receita própria acumulada no ano — monitor do teto do MEI.
create view vw_teto_mei as
select extract(year from r.data_compra)::int as ano,
       sum(r.receita_realizada) as receita_ano
from reserva r where r.status <> 'cancelada' and r.excluido_em is null
group by 1;

create view vw_ranking_fornecedor as
select coalesce(f.nome, r.fornecedor_avulso, 'Venda direta') as fornecedor,
       count(*) as reservas, sum(r.valor_cliente) as volume,
       sum(r.receita_realizada) as receita,
       round(100 * sum(r.receita_realizada) / nullif(sum(r.valor_cliente),0), 2) as margem_pct
from reserva r left join fornecedor f on f.id = r.fornecedor_id
where r.status <> 'cancelada' and r.excluido_em is null
group by 1 order by receita desc;

-- =============================================================================
-- 12. AUTOMAÇÕES
-- =============================================================================

create or replace function gerar_tarefas_viagem() returns trigger as $$
begin
  if new.cancelada then return new; end if;
  if new.data_ida is not null then
    insert into tarefa (titulo, data, cliente_id, viagem_id, origem, chave_unica)
    values ('Check-in / envio de documentos — ' || new.destino,
            new.data_ida - 3, new.cliente_id, new.id, 'automatica', new.id::text || ':checkin')
    on conflict (chave_unica) do update set data = excluded.data;
  end if;
  if new.data_volta is not null then
    insert into tarefa (titulo, data, cliente_id, viagem_id, origem, chave_unica)
    values ('Pós-viagem: avaliação e fotos — ' || new.destino,
            new.data_volta + 3, new.cliente_id, new.id, 'automatica', new.id::text || ':posviagem')
    on conflict (chave_unica) do update set data = excluded.data;
    insert into tarefa (titulo, data, cliente_id, viagem_id, origem, chave_unica)
    values ('Retomar contato (11 meses da última viagem)',
            new.data_volta + 330, new.cliente_id, new.id, 'automatica', new.id::text || ':recompra')
    on conflict (chave_unica) do update set data = excluded.data;
  end if;
  return new;
end; $$ language plpgsql;

create trigger trg_tarefas_viagem after insert or update of data_ida, data_volta, cancelada
  on viagem for each row execute function gerar_tarefas_viagem();

-- libera o repasse assim que toda a comissão da viagem entrar
create or replace function fn_liberar_repasse() returns trigger as $$
begin
  update viagem v set status_repasse = 'a_pagar'
   where v.id = new.viagem_id and v.status_repasse = 'bloqueado'
     and v.percentual_vendedor > 0
     and not exists (select 1 from reserva r
                      where r.viagem_id = v.id and r.status <> 'cancelada'
                        and r.receita_prevista > 0 and r.data_recebimento is null);
  return new;
end; $$ language plpgsql;

create trigger trg_liberar_repasse after update of data_recebimento on reserva
  for each row execute function fn_liberar_repasse();

-- job diário: alertas de documento + serve de ping para o projeto free não pausar
create or replace function job_diario() returns void as $$
  insert into tarefa (titulo, data, cliente_id, origem, chave_unica)
  select 'Passaporte vence em ' || to_char(d.validade,'DD/MM/YYYY') || ' — ' || c.nome,
         d.validade - 180, d.cliente_id, 'automatica', d.id::text || ':validade'
    from documento_cliente d join cliente c on c.id = d.cliente_id
   where d.tipo = 'passaporte' and d.validade between current_date and current_date + 210
  on conflict (chave_unica) do nothing;
$$ language sql;

create or replace function set_atualizado_em() returns trigger as $$
begin new.atualizado_em = now(); return new; end;
$$ language plpgsql;

create trigger t1 before update on cliente      for each row execute function set_atualizado_em();
create trigger t2 before update on viagem       for each row execute function set_atualizado_em();
create trigger t3 before update on reserva      for each row execute function set_atualizado_em();
create trigger t4 before update on oportunidade for each row execute function set_atualizado_em();

-- =============================================================================
-- 13. RLS
-- =============================================================================
-- Regra de ouro: esconder campo na tela NÃO protege dado. O vendedor externo
-- não tem acesso às tabelas reserva/viagem — só às views vw_minha_viagem e
-- vw_reserva_vendedor.

alter table usuario           enable row level security;
alter table cliente           enable row level security;
alter table documento_cliente enable row level security;
alter table viagem            enable row level security;
alter table viagem_passageiro enable row level security;
alter table reserva           enable row level security;
alter table reserva_alteracao enable row level security;
alter table servico           enable row level security;
alter table anexo             enable row level security;
alter table credito           enable row level security;
alter table despesa           enable row level security;
alter table tarefa            enable row level security;
alter table oportunidade      enable row level security;
alter table interacao         enable row level security;
alter table fornecedor        enable row level security;
alter table auditoria         enable row level security;

alter table agencia enable row level security;

-- helper: a viagem pertence à agência do usuário logado?
create or replace function viagem_da_agencia(p_viagem uuid) returns boolean as $$
  select exists (select 1 from viagem v
                  where v.id = p_viagem and v.agencia_id = agencia_atual());
$$ language sql stable security definer;

create policy p_agencia on agencia for select using (id = agencia_atual());

create policy p_viagem  on viagem  for all
  using (agencia_id = agencia_atual() and tem_permissao('viagem.ver'));
create policy p_reserva on reserva for all
  using (viagem_da_agencia(viagem_id) and tem_permissao('viagem.ver'));
create policy p_servico on servico for all
  using (tem_permissao('viagem.ver') and exists (
    select 1 from reserva r where r.id = reserva_id and viagem_da_agencia(r.viagem_id)));
create policy p_reserva_alt on reserva_alteracao for all
  using (tem_permissao('viagem.ver') and exists (
    select 1 from reserva r where r.id = reserva_id and viagem_da_agencia(r.viagem_id)));
create policy p_passageiro on viagem_passageiro for all
  using (viagem_da_agencia(viagem_id) and tem_permissao('viagem.ver'));
create policy p_credito on credito for all
  using (tem_permissao('viagem.ver') and exists (
    select 1 from cliente c where c.id = cliente_id and c.agencia_id = agencia_atual()));
create policy p_anexo on anexo for all
  using ((tem_permissao('viagem.ver') or not sensivel) and (
    (viagem_id  is not null and viagem_da_agencia(viagem_id)) or
    (cliente_id is not null and exists (select 1 from cliente c
        where c.id = cliente_id and c.agencia_id = agencia_atual())) or
    (reserva_id is not null and exists (select 1 from reserva r
        where r.id = reserva_id and viagem_da_agencia(r.viagem_id)))));
create policy p_doc on documento_cliente for all
  using (tem_permissao('cliente.ver_documento') and exists (
    select 1 from cliente c where c.id = cliente_id and c.agencia_id = agencia_atual()));
create policy p_despesa on despesa for all
  using (agencia_id = agencia_atual() and tem_permissao('financeiro.ver_dre'));
create policy p_audit on auditoria for select using (tem_permissao('auditoria.ver'));
create policy p_usuario_adm on usuario for all
  using (agencia_id = agencia_atual() and tem_permissao('usuario.gerenciar'));
create policy p_usuario_self on usuario for select using (auth_user_id = auth.uid());
create policy p_cliente on cliente    for all using (agencia_id = agencia_atual());
create policy p_fornec  on fornecedor for all using (agencia_id = agencia_atual());
create policy p_oport   on oportunidade for all using (exists (
    select 1 from cliente c where c.id = cliente_id and c.agencia_id = agencia_atual()));
create policy p_inter   on interacao for all using (exists (
    select 1 from cliente c where c.id = cliente_id and c.agencia_id = agencia_atual()));
create policy p_tarefa  on tarefa for all using (
  (usuario_id = usuario_atual())
  or (viagem_id is not null and viagem_da_agencia(viagem_id) and tem_permissao('viagem.ver'))
  or (cliente_id is not null and tem_permissao('viagem.ver') and exists (
        select 1 from cliente c where c.id = cliente_id and c.agencia_id = agencia_atual())));

-- =============================================================================
-- 14. VIEWS RESPEITAM RLS
-- =============================================================================
-- Por padrão a view roda com os privilégios de quem a criou e IGNORA a RLS das
-- tabelas base — o que vazaria dados entre agências. security_invoker força a
-- view a rodar com o usuário da consulta.

alter view vw_resultado_viagem  set (security_invoker = true);
alter view vw_fase_viagem       set (security_invoker = true);
alter view vw_comissao_pendente set (security_invoker = true);
alter view vw_agenda            set (security_invoker = true);
alter view vw_dashboard_mensal  set (security_invoker = true);
alter view vw_teto_mei          set (security_invoker = true);
alter view vw_ranking_fornecedor set (security_invoker = true);
