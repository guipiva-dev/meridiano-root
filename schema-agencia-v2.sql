-- =============================================================================
-- SISTEMA DE GESTÃO DE AGÊNCIA DE VIAGENS — SCHEMA v2
-- Postgres 15+ (Supabase free como Postgres puro, Neon, ou container local)
--
-- Substitui schema-agencia-v1.sql. Decisões em regras-e-escopo-v2.md e
-- docs/analise-arquitetural-v1.md.
--
-- PRINCÍPIOS
--  * Sem dependência de Supabase: nada de auth.*, auth.uid(), security_invoker.
--  * A API é a única porta. Autorização de negócio no C#.
--  * Isolamento de tenant no banco: policy `agencia_id = app.agencia_id` em toda
--    tabela de tenant. A API abre cada transação com:
--      SET LOCAL app.agencia_id = '<uuid>';
--      SET LOCAL app.usuario_id = '<uuid>';
--      SET LOCAL app.motivo    = '<texto ou vazio>';
--    A role da API NÃO é dona das tabelas, então as policies se aplicam a ela.
--  * Enums como text + check (evoluem por migration trivial).
--  * Valores em BRL. numeric(12,2).
--  * Soft delete (excluido_em/excluido_por) em tudo com valor financeiro/histórico.
--    FKs financeiras são RESTRICT; a API propaga a exclusão.
--  * Regra de negócio fica na API. No banco: integridade, colunas derivadas por
--    aritmética pura, código sequencial por agência, atualizado_em, auditoria.
--  * Concorrência otimista: a API lê xmin e usa `where xmin = @xmin` no UPDATE.
--  * Datas de serviço (voo, hotel) são timestamp SEM fuso (hora local do lugar).
--
-- Aplicar com DbUp (scripts embutidos na API). Localmente: docker compose.
-- =============================================================================

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

-- =============================================================================
-- 1. AGÊNCIA (tenant)
-- =============================================================================

create table agencia (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  cnpj       text,
  -- teto_mei, taxa_servico_padrao, retencao_auditoria_meses, ...
  config     jsonb not null default '{"teto_mei": 81000, "retencao_auditoria_meses": 24}',
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

-- =============================================================================
-- 2. USUÁRIOS (auth própria). Perfis fixos em código na v1.
-- =============================================================================

create table usuario (
  id                  uuid primary key default gen_random_uuid(),
  agencia_id          uuid not null references agencia(id),
  nome                text not null,
  email               text not null,
  telefone            text,
  perfil              text not null check (perfil in ('dono','financeiro','agente','vendedor_externo','contador')),
  -- login. senha_hash NULO = usuário sem login (vendedor externo só referenciado).
  senha_hash          text,
  convite_token       text,
  convite_expira_em   timestamptz,
  reset_token         text,
  reset_expira_em     timestamptz,
  ultimo_login_em     timestamptz,
  -- repasse
  gera_repasse        boolean not null default false,
  percentual_padrao   numeric(5,2) not null default 0 check (percentual_padrao between 0 and 100),
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  constraint usuario_email_unico unique (agencia_id, email)
);
create index ix_usuario_agencia on usuario (agencia_id);
create unique index ux_usuario_convite on usuario (convite_token) where convite_token is not null;
create unique index ux_usuario_reset   on usuario (reset_token)   where reset_token   is not null;

create table log_acesso (
  id          bigserial primary key,
  agencia_id  uuid references agencia(id),
  usuario_id  uuid references usuario(id),
  email       text,
  sucesso     boolean not null,
  ip          text,
  criado_em   timestamptz not null default now()
);
create index ix_log_acesso_email on log_acesso (email, criado_em desc);

-- =============================================================================
-- 3. PESSOAS (cliente = responsável e/ou passageiro), DOCUMENTOS, CRM
-- =============================================================================

-- Grupo/empresa: organiza clientes (família, empresa, grupo de amigos). Opcional.
create table grupo_cliente (
  id           uuid primary key default gen_random_uuid(),
  agencia_id   uuid not null references agencia(id),
  nome         text not null,
  tipo         text not null default 'familia' check (tipo in ('familia','empresa','outro')),
  cnpj         text check (cnpj ~ '^[0-9]{14}$'),
  observacoes  text,
  excluido_em  timestamptz,
  excluido_por uuid,
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index ix_grupo_cliente_agencia_nome on grupo_cliente (agencia_id, nome);

create table cliente (
  id               uuid primary key default gen_random_uuid(),
  agencia_id       uuid not null references agencia(id),
  grupo_id         uuid references grupo_cliente(id) on delete set null,
  nome             text not null,
  cpf              text check (cpf ~ '^[0-9]{11}$'),
  email            text,
  telefone         text,
  whatsapp         text,
  data_nascimento  date,
  cidade           text,
  uf               char(2),
  origem_lead      text,
  tags             text[] not null default '{}',
  observacoes      text,
  excluido_em      timestamptz,
  excluido_por     uuid references usuario(id),
  criado_por       uuid references usuario(id),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create unique index ux_cliente_cpf on cliente (agencia_id, cpf) where cpf is not null and excluido_em is null;
create index ix_cliente_agencia_nome on cliente (agencia_id, nome);
create index ix_cliente_nome_trgm    on cliente using gin (nome gin_trgm_ops);
create index ix_cliente_tags         on cliente using gin (tags);
create index ix_cliente_grupo        on cliente (grupo_id) where grupo_id is not null;

create table documento_cliente (
  id            uuid primary key default gen_random_uuid(),
  agencia_id    uuid not null references agencia(id),
  cliente_id    uuid not null references cliente(id) on delete restrict,
  tipo          text not null check (tipo in ('rg','cpf','passaporte','visto','certidao','outro')),
  numero        text,
  emissao       date,
  validade      date,
  pais_emissor  text,
  excluido_em   timestamptz,
  excluido_por  uuid references usuario(id),
  criado_em     timestamptz not null default now()
);
create index ix_documento_cliente          on documento_cliente (cliente_id);
create index ix_documento_agencia_validade on documento_cliente (agencia_id, validade) where excluido_em is null;

-- LGPD: quem viu documento pessoal / anexo sensível e quando. Gravado pela API.
create table log_acesso_documento (
  id             bigserial primary key,
  agencia_id     uuid not null references agencia(id),
  usuario_id     uuid not null references usuario(id),
  documento_id   uuid references documento_cliente(id),
  anexo_id       uuid,                                  -- FK adicionada após anexo
  criado_em      timestamptz not null default now(),
  constraint log_acesso_documento_alvo check (documento_id is not null or anexo_id is not null)
);
create index ix_log_acesso_documento on log_acesso_documento (agencia_id, criado_em desc);

create table interacao (
  id           uuid primary key default gen_random_uuid(),
  agencia_id   uuid not null references agencia(id),
  cliente_id   uuid not null references cliente(id) on delete restrict,
  usuario_id   uuid references usuario(id),
  ocorrido_em  timestamptz not null default now(),
  canal        text,
  resumo       text not null,
  criado_em    timestamptz not null default now()
);
create index ix_interacao_cliente on interacao (cliente_id, ocorrido_em desc);

create table oportunidade (
  id                  uuid primary key default gen_random_uuid(),
  agencia_id          uuid not null references agencia(id),
  cliente_id          uuid not null references cliente(id) on delete restrict,
  usuario_id          uuid references usuario(id),
  destino_pretendido  text,
  periodo_estimado    text,
  num_pax             int,
  valor_estimado      numeric(12,2),
  estagio             text not null default 'novo'
                        check (estagio in ('novo','cotando','orcamento_enviado','negociacao','ganho','perdido')),
  motivo_perda        text,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now()
);
create index ix_oportunidade_cliente on oportunidade (cliente_id, estagio);
create index ix_oportunidade_agencia on oportunidade (agencia_id, estagio);

-- =============================================================================
-- 4. FORNECEDORES E REGRA DE PAGAMENTO DE COMISSÃO
-- =============================================================================

create table fornecedor (
  id                          uuid primary key default gen_random_uuid(),
  agencia_id                  uuid not null references agencia(id),
  nome                        text not null,
  tipo                        text not null default 'operadora'
                                check (tipo in ('operadora','consolidadora','cia_aerea','hotel','seguradora','receptivo','despachante','outro')),
  cnpj                        text,
  site                        text,
  contato                     text,
  telefone                    text,
  telefone_emergencia         text,       -- plantão 24h para o viajante
  -- pré-preenche valor_comissao na tela (velocidade de lançamento)
  percentual_comissao_padrao  numeric(5,2) check (percentual_comissao_padrao between 0 and 100),
  -- previsão de comissão quando não há janela de fechamento
  prazo_comissao_dias         int check (prazo_comissao_dias > 0),
  ativo                       boolean not null default true,
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now()
);
create index ix_fornecedor_agencia_nome on fornecedor (agencia_id, nome);
create index ix_fornecedor_nome_trgm    on fornecedor using gin (nome gin_trgm_ops);

-- Ex.: vendas de 1 a 14 pagam dia 20 do mesmo mês (meses_a_frente = 0);
--      vendas de 15 a 31 pagam dia 05 do mês seguinte (meses_a_frente = 1).
-- Cálculo na API (clamp para o último dia do mês). Aqui só os dados.
create table regra_pagamento_fornecedor (
  id              uuid primary key default gen_random_uuid(),
  agencia_id      uuid not null references agencia(id),
  fornecedor_id   uuid not null references fornecedor(id) on delete cascade,
  dia_inicial     int not null check (dia_inicial between 1 and 31),
  dia_final       int not null check (dia_final between 1 and 31),
  dia_pagamento   int not null check (dia_pagamento between 1 and 31),
  meses_a_frente  int not null default 0 check (meses_a_frente between 0 and 3),
  -- vigência: a API usa o conjunto de janelas vigente na data_compra da reserva.
  -- Alterar a regra = inserir nova versão com outra vigente_desde; reservas antigas mantêm a previsão gravada.
  vigente_desde   date not null default current_date,
  constraint regra_pagamento_faixa check (dia_inicial <= dia_final)
);
create index ix_regra_pagamento_fornecedor on regra_pagamento_fornecedor (fornecedor_id);

-- =============================================================================
-- 5. VIAGEM
-- =============================================================================

-- Código sequencial POR AGÊNCIA e ano. Sequence global vazaria o volume entre agências.
create table contador_viagem (
  agencia_id  uuid not null references agencia(id),
  ano         int not null,
  ultimo      int not null default 0,
  primary key (agencia_id, ano)
);

create table viagem (
  id                    uuid primary key default gen_random_uuid(),
  agencia_id            uuid not null references agencia(id),
  codigo                text not null,
  -- nacional/internacional: corte principal dos relatórios
  tipo                  text not null default 'nacional' check (tipo in ('nacional','internacional')),
  oportunidade_id       uuid references oportunidade(id),
  vendedor_id           uuid not null references usuario(id),   -- quem vendeu (posição)
  agente_id             uuid references usuario(id),            -- quem opera (transferível)
  destino               text not null,
  pais                  text,
  data_ida              date,
  data_volta            date,
  num_pax               int not null default 1 check (num_pax >= 1),
  ocasiao               text,          -- lua de mel, aniversário, bodas
  cancelada             boolean not null default false,
  cancelada_em          timestamptz,
  motivo_cancelamento   text,
  observacoes           text,
  excluido_em           timestamptz,
  excluido_por          uuid references usuario(id),
  criado_por            uuid references usuario(id),
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now(),
  constraint viagem_datas_coerentes check (data_volta is null or data_ida is null or data_volta >= data_ida),
  constraint viagem_cancelamento_coerente check (not cancelada or (cancelada_em is not null and motivo_cancelamento is not null))
);
create unique index ux_viagem_codigo         on viagem (agencia_id, codigo);
create index ix_viagem_agencia_ida           on viagem (agencia_id, data_ida);
create index ix_viagem_agencia_volta         on viagem (agencia_id, data_volta);
create index ix_viagem_vendedor              on viagem (vendedor_id);
create index ix_viagem_agente                on viagem (agente_id);
create index ix_viagem_destino_trgm          on viagem using gin (destino gin_trgm_ops);

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

create trigger trg_viagem_codigo before insert on viagem
  for each row execute function fn_codigo_viagem();

-- Todo passageiro é uma pessoa em `cliente`. Não há "cliente responsável" na viagem:
-- o passageiro `titular` é o contato e identifica a viagem nas listas.
create table viagem_passageiro (
  id          uuid primary key default gen_random_uuid(),
  agencia_id  uuid not null references agencia(id),
  viagem_id   uuid not null references viagem(id) on delete cascade,
  cliente_id  uuid not null references cliente(id) on delete restrict,
  titular     boolean not null default false,
  constraint viagem_passageiro_unico unique (viagem_id, cliente_id)
);
create index ix_viagem_passageiro_cliente on viagem_passageiro (cliente_id);

-- =============================================================================
-- 6. RESERVA — UMA POR PORTAL/COMPRA
-- =============================================================================
-- Fórmulas (regras-e-escopo-v2 §4.2):
--   rav_cliente              = valor_cliente - valor_total
--   valor_esperado_operadora = valor_comissao + rav_operadora + (rav_cliente se via_operadora)
--   receita_prevista         = valor_comissao + rav_operadora + rav_cliente + taxa_servico
--   cancelada sem comissao_mantida -> esperado = prevista = 0
-- receita_recebida = soma dos movimentos (vw_reserva_financeiro).

create table reserva (
  id                        uuid primary key default gen_random_uuid(),
  agencia_id                uuid not null references agencia(id),
  viagem_id                 uuid not null references viagem(id) on delete restrict,
  fornecedor_id             uuid not null references fornecedor(id) on delete restrict,
  localizador               text,
  data_compra               date not null default current_date,
  -- o que foi vendido nesta reserva (relatórios). Detalhe operacional fica em `servico`.
  tipos_servico             text[] not null default '{}' check (tipos_servico <@ array['aereo','hospedagem','seguro','traslado','passeio','ingresso','aluguel_carro','documentacao','outro']),
  status                    text not null default 'pendente' check (status in ('pendente','emitida','cancelada')),

  -- DIGITADOS (BRL)
  valor_total               numeric(12,2) not null default 0 check (valor_total >= 0),    -- cobrado pelo fornecedor, com taxas
  valor_taxas               numeric(12,2) not null default 0 check (valor_taxas >= 0),    -- parte do total que é taxa
  valor_comissao            numeric(12,2) not null default 0 check (valor_comissao >= 0),
  rav_operadora             numeric(12,2) not null default 0 check (rav_operadora >= 0),
  valor_cliente             numeric(12,2) not null default 0 check (valor_cliente >= 0),  -- o que o cliente paga no total
  taxa_servico              numeric(12,2) not null default 0 check (taxa_servico >= 0),
  rav_cliente_modo          text not null default 'retido_agencia' check (rav_cliente_modo in ('retido_agencia','via_operadora')),
  moeda                     char(3) not null default 'BRL',
  cambio                    numeric(10,4) not null default 1 check (cambio > 0),
  valor_total_original      numeric(12,2),    -- na moeda original, informativo

  -- PAGAMENTO DO CLIENTE
  fluxo_pagamento           text not null default 'cliente_paga_operadora'
                              check (fluxo_pagamento in ('cliente_paga_operadora','cliente_paga_agencia')),
  formas_pagamento          text[] not null default '{}' check (formas_pagamento <@ array['pix','boleto','cartao']),

  -- PREVISÃO E CONCILIAÇÃO (calculada pela API, gravada, editável)
  data_prevista_comissao    date,
  conciliacao_encerrada     boolean not null default false,   -- fechada manualmente com divergência
  divergencia_motivo        text,

  -- CANCELAMENTO
  cancelada_em              timestamptz,
  motivo_cancelamento       text,
  desfecho_cancelamento     text check (desfecho_cancelamento in ('sem_reembolso','reembolso','credito')),
  valor_reembolso           numeric(12,2) check (valor_reembolso >= 0),
  comissao_mantida          boolean not null default false,

  -- FISCAL (uma NFSe por reserva)
  nfse_status               text not null default 'nao_precisa' check (nfse_status in ('falta_emitir','emitido','nao_precisa')),
  nfse_tomador              text check (nfse_tomador in ('cliente','operadora')),
  nfse_numero               text,
  nfse_data_emissao         date,

  observacoes               text,
  excluido_em               timestamptz,
  excluido_por              uuid references usuario(id),
  criado_por                uuid references usuario(id),
  criado_em                 timestamptz not null default now(),
  atualizado_em             timestamptz not null default now(),

  -- DERIVADOS (aritmética pura; nunca digitados)
  rav_cliente numeric(12,2) generated always as (valor_cliente - valor_total) stored,
  percentual_comissao numeric(6,2) generated always as (
    case when valor_total > 0 then round(100 * valor_comissao / valor_total, 2) end) stored,
  valor_esperado_operadora numeric(12,2) generated always as (
    case when status = 'cancelada' and not comissao_mantida then 0
         else valor_comissao + rav_operadora
              + case when rav_cliente_modo = 'via_operadora' then valor_cliente - valor_total else 0 end
    end) stored,
  receita_prevista numeric(12,2) generated always as (
    case when status = 'cancelada' and not comissao_mantida then 0
         else valor_comissao + rav_operadora + (valor_cliente - valor_total) + taxa_servico
    end) stored,

  constraint reserva_cancelamento_coerente check (
    status <> 'cancelada' or (cancelada_em is not null and motivo_cancelamento is not null and desfecho_cancelamento is not null)),
  constraint reserva_divergencia_coerente check (not conciliacao_encerrada or divergencia_motivo is not null)
);
create index ix_reserva_viagem              on reserva (viagem_id);
create index ix_reserva_agencia_compra      on reserva (agencia_id, data_compra);
create index ix_reserva_fornecedor_compra   on reserva (fornecedor_id, data_compra);
create index ix_reserva_fornecedor_loc      on reserva (agencia_id, fornecedor_id, localizador) where localizador is not null; -- aviso de duplicada
create index ix_reserva_localizador_trgm    on reserva using gin (localizador gin_trgm_ops);
create index ix_reserva_tipos_servico       on reserva using gin (tipos_servico);
create index ix_reserva_prevista_pendente   on reserva (agencia_id, data_prevista_comissao)
  where excluido_em is null and not conciliacao_encerrada and status <> 'cancelada';

-- histórico de alteração/remarcação (o que mudou comercialmente). Multa é informativa.
create table reserva_alteracao (
  id              uuid primary key default gen_random_uuid(),
  agencia_id      uuid not null references agencia(id),
  reserva_id      uuid not null references reserva(id) on delete restrict,
  data_alteracao  date not null default current_date,
  descricao       text not null,
  valor_anterior  numeric(12,2),
  valor_novo      numeric(12,2),
  multa_cliente   numeric(12,2) not null default 0 check (multa_cliente >= 0),
  usuario_id      uuid references usuario(id),
  criado_em       timestamptz not null default now()
);
create index ix_reserva_alteracao_reserva on reserva_alteracao (reserva_id, data_alteracao desc);

-- =============================================================================
-- 7. MOVIMENTO FINANCEIRO — caixa por reserva
-- =============================================================================
-- Sinal: entradas > 0, saídas < 0. receita_recebida = sum(valor).

create table movimento_financeiro (
  id               uuid primary key default gen_random_uuid(),
  agencia_id       uuid not null references agencia(id),
  reserva_id       uuid not null references reserva(id) on delete restrict,
  tipo             text not null check (tipo in (
                     'recebimento_operadora',   -- comissão / RAV entrou
                     'recebimento_cliente',     -- cliente pagou à agência (taxa, RAV retido, pix/dinheiro)
                     'pagamento_fornecedor',    -- agência pagou o fornecedor
                     'estorno_operadora',       -- operadora cobrou de volta
                     'reembolso_cliente')),     -- agência devolveu ao cliente
  valor            numeric(12,2) not null,
  data_movimento   date not null default current_date,
  forma_pagamento  text,
  observacao       text,
  excluido_em      timestamptz,
  excluido_por     uuid references usuario(id),
  criado_por       uuid references usuario(id),
  criado_em        timestamptz not null default now(),
  constraint movimento_sinal check (
    (tipo in ('recebimento_operadora','recebimento_cliente') and valor > 0) or
    (tipo in ('pagamento_fornecedor','estorno_operadora','reembolso_cliente') and valor < 0))
);
create index ix_movimento_reserva         on movimento_financeiro (reserva_id) where excluido_em is null;
create index ix_movimento_agencia_data    on movimento_financeiro (agencia_id, data_movimento) where excluido_em is null;

-- crédito de cancelamento: dinheiro que fica na operadora e todo mundo esquece
create table credito (
  id                 uuid primary key default gen_random_uuid(),
  agencia_id         uuid not null references agencia(id),
  cliente_id         uuid not null references cliente(id) on delete restrict,
  fornecedor_id      uuid not null references fornecedor(id) on delete restrict,
  reserva_origem_id  uuid references reserva(id),
  valor              numeric(12,2) not null check (valor > 0),
  validade           date,
  status             text not null default 'disponivel' check (status in ('disponivel','utilizado','expirado')),
  reserva_uso_id     uuid references reserva(id),
  observacoes        text,
  excluido_em        timestamptz,
  excluido_por       uuid references usuario(id),
  criado_em          timestamptz not null default now(),
  constraint credito_uso_coerente check (status <> 'utilizado' or reserva_uso_id is not null)
);
create index ix_credito_agencia_validade on credito (agencia_id, validade) where status = 'disponivel';
create index ix_credito_cliente          on credito (cliente_id);

-- =============================================================================
-- 8. REPASSE AO VENDEDOR EXTERNO — valor digitado pelo dono
-- =============================================================================

create table repasse (
  id           uuid primary key default gen_random_uuid(),
  agencia_id   uuid not null references agencia(id),
  viagem_id    uuid not null references viagem(id) on delete restrict,
  usuario_id   uuid not null references usuario(id),
  valor        numeric(12,2) check (valor >= 0),              -- NULO até o dono informar
  status       text not null default 'bloqueado' check (status in ('bloqueado','a_pagar','pago')),
  liberado_em  timestamptz,
  pago_em      date,
  observacao   text,
  excluido_em  timestamptz,
  excluido_por uuid references usuario(id),
  criado_em    timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint repasse_pago_coerente check (status <> 'pago' or (pago_em is not null and valor is not null)),
  constraint repasse_unico unique (viagem_id, usuario_id)
);
create index ix_repasse_usuario_status on repasse (usuario_id, status);
create index ix_repasse_agencia_status on repasse (agencia_id, status);

-- =============================================================================
-- 9. FECHAMENTO DE PERÍODO
-- =============================================================================
-- Mês fechado: reserva com data_compra no mês e movimento com data_movimento
-- no mês só editam com permissão + motivo. Verificação na API.

create table fechamento_periodo (
  agencia_id   uuid not null references agencia(id),
  competencia  date not null check (competencia = date_trunc('month', competencia)::date),
  fechado_em   timestamptz not null default now(),
  fechado_por  uuid references usuario(id),
  primary key (agencia_id, competencia)
);

-- =============================================================================
-- 10. SERVIÇO
-- =============================================================================
-- `detalhe` guarda o que varia por tipo (voo, trechos, bilhete, regime, apólice,
-- bagagem, assento). Estrutura por tipo definida em C# (record por tipo).
-- Datas SEM fuso: hora local do lugar.

create table servico (
  id               uuid primary key default gen_random_uuid(),
  agencia_id       uuid not null references agencia(id),
  reserva_id       uuid not null references reserva(id) on delete restrict,
  tipo             text not null check (tipo in ('aereo','hospedagem','traslado','passeio','seguro','ingresso','aluguel_carro','documentacao','outro')),
  titulo           text not null,
  data_inicio      timestamp,
  data_fim         timestamp,
  localidade       text,
  localizador_cia  text,      -- diferente do localizador da operadora
  numero_bilhete   text,
  detalhe          jsonb not null default '{}',
  observacoes      text,
  ordem            int not null default 0,
  excluido_em      timestamptz,
  excluido_por     uuid references usuario(id),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create index ix_servico_reserva        on servico (reserva_id, ordem);
create index ix_servico_agencia_inicio on servico (agencia_id, data_inicio);

-- =============================================================================
-- 11. ANEXOS
-- =============================================================================
-- Bucket privado (R2), acesso por URL assinada gerada pela API. Path: <agencia_id>/...

create table anexo (
  id             uuid primary key default gen_random_uuid(),
  agencia_id     uuid not null references agencia(id),
  cliente_id     uuid references cliente(id) on delete restrict,
  viagem_id      uuid references viagem(id)  on delete restrict,
  reserva_id     uuid references reserva(id) on delete restrict,
  tipo           text not null default 'outro' check (tipo in ('voucher','comprovante','documento','contrato','extrato','outro')),
  nome_arquivo   text not null,
  caminho        text not null,
  mime_type      text,
  tamanho_bytes  bigint,
  sensivel       boolean not null default false,   -- documento pessoal: acesso logado
  data_descarte  date,                             -- LGPD: expurgo programado (job)
  enviado_por    uuid references usuario(id),
  excluido_em    timestamptz,
  excluido_por   uuid references usuario(id),
  criado_em      timestamptz not null default now(),
  constraint anexo_tem_vinculo check (cliente_id is not null or viagem_id is not null or reserva_id is not null)
);
create index ix_anexo_cliente  on anexo (cliente_id);
create index ix_anexo_viagem   on anexo (viagem_id);
create index ix_anexo_reserva  on anexo (reserva_id);
create index ix_anexo_descarte on anexo (data_descarte) where data_descarte is not null and excluido_em is null;

alter table log_acesso_documento
  add constraint log_acesso_documento_anexo_fk foreign key (anexo_id) references anexo(id);

-- =============================================================================
-- 12. PENDÊNCIAS / AGENDA
-- Uma entidade só (antes "tarefa"): agenda, viagem e pessoa leem daqui. Sempre com data.
-- Pendência da viagem aparece para todos os passageiros; automáticas via job (chave_unica).
-- =============================================================================

create table pendencia (
  id             uuid primary key default gen_random_uuid(),
  agencia_id     uuid not null references agencia(id),
  titulo         text not null,
  descricao      text,
  data_prevista  date not null,
  responsavel_id uuid references usuario(id),
  cliente_id     uuid references cliente(id) on delete restrict,
  viagem_id      uuid references viagem(id)  on delete restrict,
  status         text not null default 'aberta' check (status in ('aberta','concluida','cancelada')),
  origem         text not null default 'manual' check (origem in ('manual','automatica')),
  prioridade     text not null default 'normal' check (prioridade in ('normal','urgente')),
  adiada_de      date,      -- data original, quando adiada
  chave_unica    text,      -- automáticas: '<viagem_id>:checkin', '<documento_id>:validade', 'pendencia:<cliente_id>:<regra>'
  concluida_em   timestamptz,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  constraint pendencia_chave_unica unique (agencia_id, chave_unica)
);
create index ix_pendencia_agencia_data   on pendencia (agencia_id, data_prevista, status);
create index ix_pendencia_responsavel    on pendencia (responsavel_id, status, data_prevista);
create index ix_pendencia_viagem         on pendencia (viagem_id);
create index ix_pendencia_cliente        on pendencia (cliente_id);

-- =============================================================================
-- 12b. CUSTOS (despesa) — só o essencial; DRE na v1.1
-- =============================================================================

create table despesa (
  id             uuid primary key default gen_random_uuid(),
  agencia_id     uuid not null references agencia(id),
  descricao      text not null,
  categoria      text not null check (categoria in ('fixo','imposto','operacional','marketing','outro')),
  valor          numeric(12,2) not null check (valor > 0),
  vencimento     date not null,
  pago           boolean not null default false,
  pago_em        date,
  recorrente     boolean not null default false,
  viagem_id      uuid references viagem(id) on delete restrict,
  fornecedor_id  uuid references fornecedor(id),
  observacao     text,
  excluido_em    timestamptz,
  excluido_por   uuid references usuario(id),
  criado_por     uuid references usuario(id),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  constraint despesa_pago_coerente check (not pago or pago_em is not null)
);
create index ix_despesa_agencia_venc on despesa (agencia_id, vencimento) where excluido_em is null;
create index ix_despesa_viagem on despesa (viagem_id) where viagem_id is not null;

-- =============================================================================
-- 13. JOBS
-- =============================================================================

create table job_execucao (
  id            bigserial primary key,
  nome          text not null,
  iniciado_em   timestamptz not null default now(),
  terminado_em  timestamptz,
  sucesso       boolean,
  detalhe       text
);
create index ix_job_execucao_nome on job_execucao (nome, iniciado_em desc);

-- =============================================================================
-- 14. AUDITORIA — trigger que lê o contexto da sessão definido pela API
-- =============================================================================

create table auditoria (
  id           bigserial primary key,
  agencia_id   uuid,
  tabela       text not null,
  registro_id  uuid not null,
  acao         text not null,            -- INSERT | UPDATE | DELETE
  alteracoes   jsonb not null,           -- {"campo": {"de": ..., "para": ...}}
  motivo       text,
  usuario_id   uuid,
  criado_em    timestamptz not null default now()
);
create index ix_auditoria_registro on auditoria (tabela, registro_id, criado_em desc);
create index ix_auditoria_agencia  on auditoria (agencia_id, criado_em desc);

create or replace function fn_auditoria() returns trigger as $$
declare
  v_old  jsonb := case when tg_op = 'INSERT' then '{}'::jsonb else to_jsonb(old) end;
  v_new  jsonb := case when tg_op = 'DELETE' then '{}'::jsonb else to_jsonb(new) end;
  v_diff jsonb := '{}'::jsonb;
  k text;
  -- derivadas e carimbos: fora do log
  ignorar text[] := array['atualizado_em','rav_cliente','percentual_comissao','valor_esperado_operadora','receita_prevista',
                          'senha_hash','convite_token','reset_token','convite_expira_em','reset_expira_em','ultimo_login_em'];
begin
  for k in select jsonb_object_keys(v_old || v_new) loop
    if not (k = any(ignorar)) and (v_old->k) is distinct from (v_new->k) then
      v_diff := v_diff || jsonb_build_object(k, jsonb_build_object('de', v_old->k, 'para', v_new->k));
    end if;
  end loop;
  if v_diff = '{}'::jsonb then return coalesce(new, old); end if;
  insert into auditoria (agencia_id, tabela, registro_id, acao, alteracoes, motivo, usuario_id)
  values (
    coalesce((v_new->>'agencia_id')::uuid, (v_old->>'agencia_id')::uuid),
    tg_table_name,
    coalesce((v_new->>'id')::uuid, (v_old->>'id')::uuid),
    tg_op,
    v_diff,
    nullif(current_setting('app.motivo', true), ''),
    nullif(current_setting('app.usuario_id', true), '')::uuid
  );
  return coalesce(new, old);
end; $$ language plpgsql security definer;

create trigger aud_viagem     after insert or update or delete on viagem               for each row execute function fn_auditoria();
create trigger aud_reserva    after insert or update or delete on reserva              for each row execute function fn_auditoria();
create trigger aud_servico    after insert or update or delete on servico              for each row execute function fn_auditoria();
create trigger aud_movimento  after insert or update or delete on movimento_financeiro for each row execute function fn_auditoria();
create trigger aud_repasse    after insert or update or delete on repasse              for each row execute function fn_auditoria();
create trigger aud_usuario    after insert or update or delete on usuario              for each row execute function fn_auditoria();
create trigger aud_cliente    after insert or update or delete on cliente              for each row execute function fn_auditoria();
create trigger aud_despesa    after insert or update or delete on despesa              for each row execute function fn_auditoria();

-- atualizado_em
create or replace function set_atualizado_em() returns trigger as $$
begin new.atualizado_em = now(); return new; end;
$$ language plpgsql;

create trigger upd_usuario      before update on usuario      for each row execute function set_atualizado_em();
create trigger upd_cliente      before update on cliente      for each row execute function set_atualizado_em();
create trigger upd_grupo_cliente before update on grupo_cliente for each row execute function set_atualizado_em();
create trigger upd_oportunidade before update on oportunidade for each row execute function set_atualizado_em();
create trigger upd_fornecedor   before update on fornecedor   for each row execute function set_atualizado_em();
create trigger upd_viagem       before update on viagem       for each row execute function set_atualizado_em();
create trigger upd_reserva      before update on reserva      for each row execute function set_atualizado_em();
create trigger upd_servico      before update on servico      for each row execute function set_atualizado_em();
create trigger upd_repasse      before update on repasse      for each row execute function set_atualizado_em();
create trigger upd_pendencia    before update on pendencia    for each row execute function set_atualizado_em();

-- =============================================================================
-- 15. VIEWS — read-models. A API filtra agencia_id; RLS garante.
-- =============================================================================

-- caixa e conciliação por reserva
create view vw_reserva_financeiro as
select
  r.id as reserva_id, r.agencia_id, r.viagem_id, r.status,
  r.valor_esperado_operadora, r.receita_prevista, r.data_prevista_comissao, r.conciliacao_encerrada,
  coalesce(sum(m.valor) filter (where m.tipo in ('recebimento_operadora','estorno_operadora')), 0) as recebido_operadora,
  coalesce(sum(m.valor) filter (where m.tipo = 'recebimento_cliente'), 0)                           as recebido_cliente,
  coalesce(sum(m.valor), 0)                                                                          as receita_recebida,
  (r.valor_esperado_operadora > 0 and not r.conciliacao_encerrada
     and coalesce(sum(m.valor) filter (where m.tipo in ('recebimento_operadora','estorno_operadora')), 0) < r.valor_esperado_operadora)
     as aguardando_operadora,
  (r.valor_esperado_operadora = 0 or r.conciliacao_encerrada
     or coalesce(sum(m.valor) filter (where m.tipo in ('recebimento_operadora','estorno_operadora')), 0) >= r.valor_esperado_operadora)
     as conciliada
from reserva r
left join movimento_financeiro m on m.reserva_id = r.id and m.excluido_em is null
where r.excluido_em is null
group by r.id;

create view vw_fase_viagem as
select v.id as viagem_id, v.agencia_id,
  case
    when v.cancelada                 then 'cancelada'
    when v.data_volta < current_date then 'concluida'
    when v.data_ida  <= current_date then 'em_viagem'
    when exists (select 1 from reserva r where r.viagem_id = v.id and r.excluido_em is null and r.status = 'pendente') then 'em_emissao'
    when exists (select 1 from reserva r where r.viagem_id = v.id and r.excluido_em is null and r.status <> 'cancelada') then 'confirmada'
    else 'sem_reserva' end as fase_operacional,
  case
    when not exists (select 1 from vw_reserva_financeiro f where f.viagem_id = v.id and f.valor_esperado_operadora > 0) then 'nao_prevista'
    when not exists (select 1 from vw_reserva_financeiro f where f.viagem_id = v.id and f.aguardando_operadora) then 'recebida'
    when exists (select 1 from vw_reserva_financeiro f where f.viagem_id = v.id and f.aguardando_operadora
                   and f.data_prevista_comissao < current_date) then 'atrasada'
    when exists (select 1 from vw_reserva_financeiro f where f.viagem_id = v.id and f.valor_esperado_operadora > 0 and f.conciliada) then 'parcial'
    else 'a_receber' end as fase_financeira
from viagem v where v.excluido_em is null;

-- contato da viagem = passageiro titular (ou o primeiro, se nenhum marcado)
create view vw_viagem_titular as
select distinct on (vp.viagem_id) vp.viagem_id, c.id as cliente_id, c.nome
  from viagem_passageiro vp join cliente c on c.id = vp.cliente_id
 order by vp.viagem_id, vp.titular desc, c.nome;

create view vw_resultado_viagem as
select
  v.id as viagem_id, v.agencia_id, v.codigo, v.destino, v.data_ida, v.data_volta, v.cancelada,
  c.nome as cliente, u.nome as vendedor,
  count(f.reserva_id)                                     as qtd_reservas,
  coalesce(sum(r.valor_cliente) filter (where r.status <> 'cancelada'), 0) as volume_vendido,
  coalesce(sum(f.receita_prevista), 0)                    as receita_prevista,
  coalesce(sum(f.receita_recebida), 0)                    as receita_recebida,
  rp.valor                                                as repasse_valor,
  rp.status                                               as repasse_status,
  coalesce(sum(f.receita_recebida), 0) - coalesce(rp.valor, 0) as resultado_agencia
from viagem v
left join vw_viagem_titular c on c.viagem_id = v.id
join usuario u on u.id = v.vendedor_id
left join reserva r on r.viagem_id = v.id and r.excluido_em is null
left join vw_reserva_financeiro f on f.reserva_id = r.id
left join repasse rp on rp.viagem_id = v.id and rp.excluido_em is null
where v.excluido_em is null
group by v.id, c.nome, u.nome, rp.valor, rp.status;

create view vw_comissao_pendente as
select r.agencia_id, r.id as reserva_id, v.codigo, c.nome as cliente, fo.nome as fornecedor,
       r.localizador, r.data_compra, r.data_prevista_comissao,
       f.valor_esperado_operadora, f.recebido_operadora,
       f.valor_esperado_operadora - f.recebido_operadora as saldo,
       current_date - r.data_prevista_comissao as dias_atraso
from vw_reserva_financeiro f
join reserva r on r.id = f.reserva_id
join viagem v on v.id = r.viagem_id
left join vw_viagem_titular c on c.viagem_id = v.id
join fornecedor fo on fo.id = r.fornecedor_id
where f.aguardando_operadora and v.excluido_em is null;

-- clientes que devem à agência (fluxo cliente_paga_agencia)
create view vw_receber_cliente as
select r.agencia_id, r.id as reserva_id, v.codigo, c.nome as cliente, r.valor_cliente,
       f.recebido_cliente, r.valor_cliente - f.recebido_cliente as saldo
from vw_reserva_financeiro f
join reserva r on r.id = f.reserva_id
join viagem v on v.id = r.viagem_id
left join vw_viagem_titular c on c.viagem_id = v.id
where r.fluxo_pagamento = 'cliente_paga_agencia' and r.status <> 'cancelada'
  and f.recebido_cliente < r.valor_cliente and v.excluido_em is null;

create view vw_agenda as
select v.agencia_id, v.id as viagem_id, v.codigo, c.nome as cliente, 'embarque' as evento, v.data_ida as data_evento
  from viagem v left join vw_viagem_titular c on c.viagem_id = v.id
 where not v.cancelada and v.excluido_em is null and v.data_ida >= current_date
union all
select v.agencia_id, v.id, v.codigo, c.nome, 'retorno', v.data_volta
  from viagem v left join vw_viagem_titular c on c.viagem_id = v.id
 where not v.cancelada and v.excluido_em is null and v.data_volta >= current_date
union all
select r.agencia_id, v.id, v.codigo, c.nome, 'comissao_prevista', r.data_prevista_comissao
  from vw_reserva_financeiro f join reserva r on r.id = f.reserva_id
  join viagem v on v.id = r.viagem_id left join vw_viagem_titular c on c.viagem_id = v.id
 where f.aguardando_operadora and r.data_prevista_comissao is not null and v.excluido_em is null
union all
select d.agencia_id, null, null, c.nome, 'passaporte_vence', d.validade
  from documento_cliente d join cliente c on c.id = d.cliente_id
 where d.tipo = 'passaporte' and d.excluido_em is null
   and d.validade between current_date and current_date + 210
union all
select cr.agencia_id, null, null, c.nome, 'credito_vence', cr.validade
  from credito cr join cliente c on c.id = cr.cliente_id
 where cr.status = 'disponivel' and cr.excluido_em is null
   and cr.validade between current_date and current_date + 60;

create view vw_dashboard_mensal as
select r.agencia_id, date_trunc('month', r.data_compra)::date as mes,
       count(distinct r.viagem_id)  as viagens,
       count(*)                      as reservas,
       sum(r.valor_cliente)          as volume_vendido,
       sum(r.receita_prevista)       as receita_prevista
from reserva r
where r.status <> 'cancelada' and r.excluido_em is null
group by 1, 2;

-- caixa por mês (competência financeira)
create view vw_caixa_mensal as
select m.agencia_id, date_trunc('month', m.data_movimento)::date as mes,
       sum(m.valor) as receita_recebida
from movimento_financeiro m
where m.excluido_em is null
group by 1, 2;

-- Receita recebida acumulada no ano — monitor do teto do MEI.
-- Base a confirmar com o contador (regras-e-escopo-v2 §4.9).
create view vw_teto_mei as
select m.agencia_id, extract(year from m.data_movimento)::int as ano,
       sum(m.valor) as receita_ano,
       (a.config->>'teto_mei')::numeric as teto,
       round(100 * sum(m.valor) / nullif((a.config->>'teto_mei')::numeric, 0), 1) as percentual_teto
from movimento_financeiro m
join agencia a on a.id = m.agencia_id
where m.excluido_em is null
group by 1, 2, 4;

create view vw_ranking_fornecedor as
select r.agencia_id, fo.id as fornecedor_id, fo.nome as fornecedor,
       count(*)                     as reservas,
       sum(r.valor_cliente)         as volume,
       sum(r.receita_prevista)      as receita_prevista,
       sum(f.receita_recebida)      as receita_recebida,
       round(100 * sum(r.receita_prevista) / nullif(sum(r.valor_cliente), 0), 2) as margem_pct
from reserva r
join fornecedor fo on fo.id = r.fornecedor_id
join vw_reserva_financeiro f on f.reserva_id = r.id
where r.status <> 'cancelada' and r.excluido_em is null
group by 1, 2, 3;

-- =============================================================================
-- 16. ISOLAMENTO DE TENANT (RLS por app.agencia_id)
-- =============================================================================
-- Role da API: sem ownership, sem BYPASSRLS. As migrations rodam como owner.
--   create role meridiano_api login password '...';
--   grant usage on schema public to meridiano_api;
--   grant select, insert, update, delete on all tables in schema public to meridiano_api;
--   grant usage, select on all sequences in schema public to meridiano_api;
--   alter default privileges in schema public grant select, insert, update, delete on tables to meridiano_api;
--   alter default privileges in schema public grant usage, select on sequences to meridiano_api;
--
-- A policy usa current_setting(..., true): sem GUC definido -> NULL -> nenhuma linha.

create or replace function app_agencia_id() returns uuid as $$
  select nullif(current_setting('app.agencia_id', true), '')::uuid
$$ language sql stable;

do $$
declare t text;
begin
  foreach t in array array[
    'usuario','grupo_cliente','cliente','documento_cliente','log_acesso_documento','interacao','oportunidade',
    'fornecedor','regra_pagamento_fornecedor','contador_viagem','viagem','viagem_passageiro',
    'reserva','reserva_alteracao','movimento_financeiro','credito','repasse','fechamento_periodo',
    'servico','anexo','pendencia','despesa','auditoria'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format('drop policy if exists p_tenant on %I', t);
    execute format('create policy p_tenant on %I for all using (agencia_id = app_agencia_id()) with check (agencia_id = app_agencia_id())', t);
  end loop;
end $$;

-- agencia: a API só enxerga a própria. log_acesso: sem tenant fixo (login falho não tem agência).
alter table agencia enable row level security;
alter table agencia force row level security;
create policy p_agencia on agencia for select using (id = app_agencia_id());

-- Login acontece antes de app.agencia_id existir: a API usa uma função definer
-- para localizar o usuário pelo e-mail sem RLS.
create or replace function localizar_usuario_login(p_email text)
returns table (id uuid, agencia_id uuid, senha_hash text, perfil text, ativo boolean) as $$
  select u.id, u.agencia_id, u.senha_hash, u.perfil, u.ativo
    from usuario u join agencia a on a.id = u.agencia_id
   where lower(u.email) = lower(p_email) and u.senha_hash is not null and a.ativo
$$ language sql stable security definer;

-- =============================================================================
-- FIM. v1.1 (migration futura): dre, metas, checklist_destino.
-- =============================================================================
