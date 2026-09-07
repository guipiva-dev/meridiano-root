# Análise arquitetural — regras-e-escopo-v1 + schema-agencia-v1

Data: 2026-09-07. Base: `regras-e-escopo-v1.md` e `schema-agencia-v1.sql`.
Premissa fixa: API em C#/.NET. Todo o resto foi questionado.

Legenda de severidade: **CRÍTICO** (corrigir antes de implementar) · **IMPORTANTE** (corrigir agora, evita retrabalho) · **MELHORIA** (pode ficar para depois) · **OPCIONAL** (depende da estratégia do produto).

Cada achado tem um ID (`E-` escopo, `B-` banco, `X-` cruzamento escopo×banco, `A-` arquitetura, `O-` overengineering) para facilitar a discussão.

---

## 0. Resumo executivo

O documento de escopo é bom: sabe o que o sistema **não** é, fixou multiempresa cedo (correto), separou viagem/reserva/serviço com clareza e identificou o risco número um (tempo de lançamento). O schema é coerente com o escopo e mostra domínio real do negócio.

Os problemas estão em três lugares:

1. **O schema foi desenhado para o navegador falar direto com o Supabase** (RLS por permissão, `auth.uid()`, views por persona, `security_invoker`). Depois entrou uma API em C# na frente, e o documento tenta manter as duas camadas de autorização ao mesmo tempo. Isso é a decisão estrutural mais cara do projeto e precisa ser fechada antes de qualquer linha de código. Recomendação: **autorização de negócio no C#, isolamento de tenant no Postgres**. Detalhe em A-01.

2. **A semântica financeira está ambígua em pontos que mudam número no dashboard**: `receita_realizada` mistura caixa e competência (E-05), multa e cancelamento não têm dono definido (E-07, E-08), o RAV do cliente não diz quem recolhe (E-06), e o repasse é calculado sobre uma base que o texto chama de "lucro" e o SQL chama de "receita" (E-09). Nada disso é problema de código; é pergunta para a agência piloto.

3. **Algumas escolhas de modelagem vão doer em 6 meses**: enums nativos do Postgres (B-02), `mes_fechado` como booleano por linha (B-08), NFSe 1:1 com reserva (B-09), `timestamptz` para horário de voo (B-05), passageiro sem vínculo obrigatório com pessoa (B-06), ausência de CPF no cliente (B-07), sem controle de concorrência (B-10).

Do lado oposto, há **overengineering** que vale cortar: RBAC com grupos e override por usuário para cinco pessoas (O-01), auditoria campo a campo por trigger que loga colunas geradas (O-02), `tem_permissao()` chamada por linha dentro das policies (O-03), tabelas criadas para funcionalidades da v1.1 (O-05).

A arquitetura recomendada é um **monólito modular em .NET 10**, três projetos, EF Core, sem CQRS/MediatR/Repository, jobs como hosted services, frontend React servido pela própria API. Detalhe na seção 5.

---

## 1. Análise do escopo (`regras-e-escopo-v1.md`)

### 1.1 O que está bem resolvido

- Multiempresa desde o início. Correto e barato agora; caríssimo depois.
- Três níveis (viagem → reserva → serviço) com "quem enxerga" definido por nível. Modelo central sólido.
- Valores digitados vs. calculados explicitados. Percentual derivado, data prevista gravada e editável.
- Dois eixos de status, ambos calculados. Evita o estado "concluída mas com comissão pendente" virar gambiarra.
- Vendedor externo como **posição** na viagem, perfil como **permissão**. Separação certa.
- Usuário sem login. Resolve o vendedor externo que não usa o sistema sem criar entidade paralela.
- Risco número um nomeado (tempo de lançamento) e tratado como requisito.
- Descarte explícito de aprovação em duas etapas e segregação de funções. Maturidade.

### 1.2 Regras ambíguas

**E-01 — Vendedor externo lança venda ou só enxerga? — CRÍTICO**
Seção 6 diz que "o vendedor da viagem já vem preenchido com o usuário logado" e que trocar exige `viagem.definir_vendedor`, "que o vendedor externo não tem". Isso implica que o vendedor externo **cria** viagens. Mas a seção 4 diz que ele "não tem acesso às tabelas `viagem` e `reserva`", e no schema o perfil "Vendedor externo" não recebe `viagem.ver`, logo a policy `for all` bloqueia INSERT também. Se ele lança a venda, ele digita `valor_comissao` — e então "não vê comissão" é impossível. Três respostas possíveis, cada uma com modelo diferente:
- (a) vendedor externo só consulta; a agência lança tudo;
- (b) vendedor externo lança dados comerciais (cliente, destino, localizador, valor pago pelo cliente) e o agente completa o financeiro;
- (c) vendedor externo lança tudo, e a restrição de visibilidade vale só para consulta posterior.
A resposta define permissões, telas e o modelo de RLS. Precisa ser respondida pela piloto.

**E-02 — "O que o cliente pagou": pagou a quem? — CRÍTICO**
`valor_cliente` é "o que o cliente pagou", mas não diz se pagou à operadora (fluxo comissionado clássico) ou à agência (que então repassa à operadora). O campo `cartao_de = 'agencia'` revela que o segundo fluxo existe: quando o cartão da agência paga a operadora, **o cliente passa a dever à agência**, e isso é um contas-a-receber real que o schema representa só como um booleano `recebido_do_cliente`. Sem essa distinção, o "status financeiro" só acompanha a comissão da operadora e ignora dinheiro que a agência adiantou. Definir explicitamente um `fluxo_pagamento` por reserva: `cliente_paga_operadora` | `cliente_paga_agencia`.

**E-03 — Regime de caixa vs. competência — CRÍTICO**
O texto usa "prevista" e "realizada", mas não define o que torna uma receita realizada. O SQL responde de um jeito inconsistente (ver E-05). Para MEI, o teto de R$ 81.000 é medido sobre receita bruta **recebida no ano** (regime de caixa). A `vw_teto_mei` agrupa por ano de `data_compra` — competência. Um dos dois está errado; qual, depende da resposta do contador que o próprio documento marca como pendente.

**E-04 — Base do repasse: "lucro" ou "receita"? — IMPORTANTE**
Seção 3: repasse é "percentual sobre o lucro da viagem". O SQL calcula sobre `receita_realizada`. Para venda comissionada, receita ≈ lucro bruto (não há custo). Para markup, `receita_prevista` já desconta o custo. Mas: a taxa de serviço entra na base? O RAV da operadora entra? O RAV do cliente entra? A multa desconta da base do vendedor ou só da agência? O texto não diz; o SQL inclui tudo e desconta a multa. Definir por escrito com um exemplo numérico.

**E-05 — `receita_realizada` não é caixa nem competência — CRÍTICO**
Fórmula atual para `comissao`: `coalesce(comissao_recebida,0) + rav_operadora + rav_cliente + (taxa_servico se recebido_do_cliente) - valor_multa`. A comissão só conta depois de recebida, mas o RAV da operadora conta **no lançamento**, antes de qualquer recebimento, e o RAV do cliente também. Exemplo: pedido R$ 10.000, cliente paga R$ 10.500 diretamente à operadora, comissão R$ 1.000, RAV operadora R$ 100. No dia do lançamento, sem um centavo na conta da agência, `receita_realizada = 0 + 100 + 500 = 600`. Esse número entra no dashboard, no teto do MEI e na base do repasse. Precisa virar: `receita_prevista` (competência, calculada no lançamento) e `receita_recebida` (caixa, soma dos recebimentos efetivos). Ver X-02 para o modelo.

**E-06 — RAV do cliente: quem recolhe? — IMPORTANTE**
No mercado brasileiro, o "RAV" que a agência adiciona em cima do valor da operadora é frequentemente **cobrado pela operadora junto com o pedido e devolvido à agência** junto com a comissão. Nesse caso o RAV do cliente é um valor a receber da operadora, com data prevista, e entra na conciliação. Se em vez disso o cliente paga a diferença direto à agência, é um recebimento do cliente. O documento define o cálculo mas não o fluxo do dinheiro. Isso muda o que a conciliação compara: hoje não existe um "valor esperado da operadora" contra o qual `comissao_recebida` é conferido; `divergencia_motivo` não tem com o que divergir.

**E-07 — Multa: quem absorve? — IMPORTANTE**
`valor_multa` é subtraído da receita da agência. Isso assume que a agência absorve a multa. Nos casos comuns, a multa de remarcação/cancelamento é paga pelo cliente à operadora e a agência não perde nada — ou perde só a comissão proporcional. Há ainda `multa` em `reserva_alteracao` e `valor_multa` em `reserva`: duplicado, sem regra de qual prevalece. Definir: multa é um evento (em `reserva_alteracao`) com um campo "quem paga" (cliente | agência), e só a parte da agência afeta receita.

**E-08 — Cancelamento: efeito financeiro indefinido — CRÍTICO**
Reserva `cancelada` some de todos os somatórios. Mas uma reserva cancelada pode ter comissão **já recebida** (a operadora estorna, cobra de volta em fatura futura, ou não estorna), pode gerar crédito na operadora (tabela `credito`), pode gerar multa retida pela agência. Ao sumir dos somatórios, dinheiro que entrou na conta desaparece do sistema. Também não está definido: cancelar a viagem cancela as reservas? Cancelar todas as reservas cancela a viagem? Repasse já pago de uma viagem cancelada é devolvido pelo vendedor?

**E-09 — Repasse: valor congelado e pagamento em lote — IMPORTANTE**
O repasse é liberado por trigger e pago com `data_pagto_repasse` na viagem. Depois de pago, uma alteração na reserva (multa, correção) muda `receita_realizada` e o repasse "pago" passa a mostrar outro valor. Falta congelar `valor_repasse` no momento do pagamento. Além disso, vendedor externo é pago **por mês, por várias viagens** — o modelo por viagem funciona, mas a operação precisa de "pagar todos os repasses a_pagar do vendedor X" numa ação só. E há duas fontes de verdade para "repasse pago": colunas em `viagem` e `despesa` com `tipo = 'repasse'`. Escolher uma.

**E-10 — Liberação do repasse depende de campo que não existe para venda direta — IMPORTANTE**
`fn_liberar_repasse` libera quando toda reserva com `receita_prevista > 0` tem `data_recebimento`. Para `tipo_receita = markup` ou `taxa_servico`, não há operadora e `data_recebimento` (recebimento de comissão) não faz sentido — o usuário teria que preencher um campo semanticamente errado para destravar o repasse. Resolvido pelo modelo de recebimentos (X-02).

**E-11 — Mês fechado: qual data define a competência? — IMPORTANTE**
"Trava de mês fechado" existe, mas não diz se o mês de uma reserva é o de `data_compra`, `data_recebimento` ou `data_prevista_comissao`. Conciliação é por mês de recebimento; venda é por mês de compra. Provavelmente os dois fecham separados (mês comercial e mês financeiro). Definir.

**E-12 — NFSe: uma por reserva? — IMPORTANTE**
Os campos de NFSe estão na reserva, o que força uma nota por reserva. Na prática, a agência emite frequentemente **uma NFSe mensal para a operadora** (tomador) cobrindo várias reservas. O modelo 1:1 não representa isso. Ver B-09.

**E-13 — Status financeiro tem um estado a mais no SQL — MELHORIA**
Texto: `a_receber → parcial → quitada (+atrasada)`. View: acrescenta `sem_receita`. Alinhar o documento.

### 1.3 Regras conflitantes

**E-14 — Vendedor externo vê todos os clientes — IMPORTANTE**
`p_cliente`, `p_inter`, `p_oport` filtram só por agência. O vendedor externo, que "vê apenas as próprias viagens", enxerga e edita todo o CRM da agência, incluindo data de nascimento e histórico de interações de clientes que nunca atendeu. Conflita com a seção 4 e com LGPD (minimização). Decidir: vendedor externo vê só clientes das próprias viagens?

**E-15 — "Perfil é permissão" mas perfis são globais — IMPORTANTE**
`perfil.nome` é `unique` global e `perfil_permissao` não tem `agencia_id`. Em multiempresa, a agência B que editar o perfil "Agente" altera as permissões da agência A. Ou perfis são de sistema e imutáveis (recomendado para v1, ver O-01), ou ganham `agencia_id`.

**E-16 — Perfil "Contador" sem permissão alguma — MELHORIA**
Seed cria o perfil e não atribui nada. Contador entra e vê tela vazia.

**E-17 — Usuário comum não consegue ver o nome de outros usuários — IMPORTANTE**
`p_usuario_self` só libera a própria linha; `p_usuario_adm` exige `usuario.gerenciar`. Um Agente consultando `vw_resultado_viagem` (que faz `left join usuario`) recebe `vendedor = null` para toda viagem que não é dele. Sintoma de que o RLS está sendo usado para segurança de **coluna** (esconder `percentual_padrao`), coisa que RLS não faz. Precisa de uma policy de leitura básica por agência, e a coluna sensível fica fora do DTO — no C#.

### 1.4 Funcionalidades ausentes

**E-18 — Contas a receber do cliente — IMPORTANTE**
Decorrência de E-02. Quando a agência adianta o pagamento (cartão da agência) ou vende com markup, existe um valor a receber do cliente com data. Sem parcelamento, mas com vencimento. Uma lista "clientes que devem à agência" é operação básica.

**E-19 — Estorno de comissão — IMPORTANTE**
Decorrência de E-08. Precisa existir um lançamento negativo de recebimento, com motivo.

**E-20 — Log de acesso a documento pessoal — IMPORTANTE**
Seção 7 exige (LGPD). O schema não tem a tabela. A API deve registrar quem viu qual documento e quando, no momento em que gera a URL assinada ou entrega o conteúdo.

**E-21 — Expurgo de auditoria — IMPORTANTE**
"Retenção de 12 a 24 meses" sem job de expurgo nem particionamento. Vira tabela infinita. Job mensal em C# resolve.

**E-22 — Percentual padrão de comissão por fornecedor — IMPORTANTE (UX)**
O risco número um é tempo de lançamento. Com percentual padrão por fornecedor, a tela pré-preenche `valor_comissao` a partir de `valor_total` e o usuário só corrige quando diverge. Zero custo de modelo, alto ganho de velocidade. Mesma lógica para `taxa_servico` padrão da agência.

**E-23 — Detecção de reserva duplicada — MELHORIA**
Lançar quatro portais à mão gera reserva dupla. Aviso (não bloqueio) quando `fornecedor_id + localizador` já existe na agência.

**E-24 — Vencimento de pagamento à operadora — MELHORIA (revisar a decisão)**
Foi descartado. Custa uma coluna `vencimento_fornecedor date` nula. Um pagamento perdido cancela a reserva do cliente; é o tipo de alerta que uma agência agradece. Sugiro reincluir como opcional.

**E-25 — Anonimização de cliente (LGPD, direito ao esquecimento) — MELHORIA**
Soft delete mantém os dados. Precisa de um caminho para anonimizar nome/documentos mantendo o histórico financeiro. Não é v1, mas o modelo não pode impedir (não impede).

**E-26 — Notificações in-app — MELHORIA**
"Alertas dentro do sistema" sem tabela. `tarefa` cobre para v1. Uma tabela `notificacao` só quando houver algo além de tarefa.

**E-27 — Usuário em mais de uma agência — OPCIONAL**
Dono com duas agências no futuro. `usuario.auth_user_id unique` global impede. Trocar para `unique (agencia_id, auth_user_id)` agora custa zero.

### 1.5 Casos de borda e fluxos mal definidos

- Viagem com todas as reservas canceladas: status operacional vira `sem_reserva`? Deveria ser `cancelada` ou pelo menos sinalizada.
- Reserva com `receita_prevista` negativa (desconto maior que comissão): excluída da liberação de repasse por `> 0`, mas entra nos somatórios. Ok, mas documentar.
- Remarcação que muda `data_ida`: as tarefas automáticas mudam de data, mas uma tarefa já `concluida` (check-in feito para a data antiga) continua concluída. Deveria reabrir.
- Viagem cancelada depois de criada: `gerar_tarefas_viagem` retorna cedo mas **não cancela** as tarefas já criadas. Ficam pendentes para uma viagem que não existe mais.
- Tarefas automáticas sem `usuario_id`: ninguém é responsável. Deveriam ir para `viagem.agente_id`.
- `regra_pagamento_fornecedor` com `dia_pagamento = 31` e venda em fevereiro: `date_trunc + 30 days` cai em 3 de março. Precisa clamp para o último dia do mês. Faixas de dias podem se sobrepor ou deixar buraco; sem constraint.
- Transferência de viagem entre agentes com tarefas abertas: as tarefas mudam de responsável?
- Viagem sem `vendedor_id` (coluna nula): repasse não se aplica, mas ranking de vendedor perde a venda. Deveria ser obrigatório (default = quem criou).
- `num_pax` digitado e `viagem_passageiro` contado: dois números para a mesma coisa. Aceitável se `num_pax` for "rápido" e passageiros "detalhe opcional", mas documentar qual prevalece.

### 1.6 Responsabilidades que deveriam ser separadas

- **`reserva` concentra quatro assuntos**: comercial (valores), conciliação (recebimento da operadora), fiscal (NFSe) e pagamento do cliente (forma, cartão). 45 colunas. Fiscal deve sair (B-09). Conciliação e pagamento do cliente viram lançamentos (X-02). O que sobra é a reserva comercial/operacional, ~25 colunas.
- **Repasse** está espalhado entre `viagem` (status, data) e `despesa` (valor). Vira entidade própria (X-03).
- **Multa** está em `reserva` e em `reserva_alteracao`. Fica só no evento.

### 1.7 Funcionalidades prováveis num sistema real (não necessariamente v1)

Já cobertas ou decididas fora: cotação (fora), voucher (fora), pagamento (fora), WhatsApp API (fora), metas (v1.1), reembolso (v1.1). Faltam e valem nota para não bloquear:
- Vários vendedores numa viagem (split de repasse). Não construir; só não impedir — a tabela `repasse` (X-03) já permite N linhas por viagem.
- Reserva de grupo compartilhada por várias viagens. Não construir.
- Cliente pessoa jurídica (corporativo). Fora do escopo "lazer"; o modelo não impede (CNPJ em `cliente` no futuro).
- Modelos de mensagem para copiar no WhatsApp (confirmação, lembrete de check-in). Barato e alinhado ao risco número um. MELHORIA.

---

## 2. Análise do schema (`schema-agencia-v1.sql`)

### 2.1 O que está bem

- Nomes consistentes em português, sem abreviações crípticas.
- `uuid` como PK com `gen_random_uuid()`. Adequado para multiempresa e para API pública futura.
- `numeric(12,2)` para dinheiro. Correto (nunca `float`).
- `timestamptz` para carimbos de sistema. Correto.
- `contador_viagem` por agência/ano com `on conflict do update ... returning`. Concorrência tratada.
- `servico.detalhe jsonb` em vez de 40 colunas nulas. Escolha pragmática certa.
- `anexo` polimórfico com check de vínculo. Simples e suficiente.
- Data prevista de comissão gravada, não recalculada. Certo.
- `percentual_vendedor` copiado para `viagem` (snapshot). Certo.
- Índice parcial em `reserva (data_prevista_comissao) where data_recebimento is null`. Boa intuição.

### 2.2 Achados

**B-01 — Acoplamento ao Supabase dentro do schema — CRÍTICO (decisão)**
`usuario.auth_user_id references auth.users(id)`, `auth.uid()` nas funções, `SET LOCAL role authenticated`. Isso amarra o banco ao Supabase: não roda num Postgres comum, não sobe em Testcontainers, não restaura em outro lugar sem editar o dump. O próprio documento diz "migrar o Postgres para infra própria depois é direto" — não é, com essas referências. Tirar a FK para `auth.users` (manter a coluna como `uuid` simples) e não usar `auth.uid()` — a identidade do usuário chega pela API. Independe da decisão de manter ou não o Supabase (A-02).

**B-02 — Enums nativos do Postgres — IMPORTANTE**
14 tipos enum. Adicionar valor exige `ALTER TYPE ... ADD VALUE` (não pode ser usado na mesma transação da migration), remover valor é impossível sem recriar o tipo, renomear é trabalho. `tipo_servico`, `forma_pagamento`, `tipo_fornecedor`, `tipo_anexo` vão crescer com certeza. Trocar por `text` com `check (col in (...))` — a migration que adiciona um valor é `drop constraint / add constraint`, transacional e trivial. No C#, enum mapeado como string. Custo zero agora; economia real depois.

**B-03 — Colunas geradas com regra de negócio — IMPORTANTE (decisão)**
`rav_cliente`, `percentual_comissao`, `receita_prevista`, `receita_realizada` como `generated always ... stored`. Vantagem: consistência garantida, zero código. Desvantagem: a fórmula (que hoje está errada, E-05) vive em DDL, não tem teste unitário, e cada correção é uma migration que reescreve a tabela. Como a API é o único escritor, a alternativa é: **cálculo no C# (testado), persistido em coluna comum** no momento do save. Manter `rav_cliente` e `percentual_comissao` como geradas é aceitável (aritmética pura). `receita_prevista` e `receita_recebida` devem ir para o domínio. Ver A-06.

**B-04 — `agencia_id` só nas tabelas raiz — IMPORTANTE**
`reserva`, `servico`, `anexo`, `tarefa`, `oportunidade`, `interacao`, `documento_cliente`, `credito`, `reserva_alteracao`, `viagem_passageiro`, `auditoria` resolvem a agência por join. Isso obriga policies com subselect (as atuais) e impede um filtro global uniforme na API. Colocar `agencia_id not null` em **toda** tabela de tenant é redundância deliberada: uma policy `agencia_id = current_setting('app.agencia_id')::uuid` idêntica em todas, um filtro global idêntico no EF, índices compostos começando por `agencia_id`. É o padrão que faz multiempresa ser barato de manter.

**B-05 — `timestamptz` para horário de serviço — IMPORTANTE (domínio)**
`servico.data_inicio timestamptz`. Um voo que sai de Lisboa às 08:00 local, gravado como `timestamptz`, é exibido como 04:00 em São Paulo. Horário de voo, check-in de hotel e passeio são **horários locais do lugar**, sem fuso. Usar `timestamp` (sem tz) para datas de serviço, e opcionalmente o IATA/fuso no `detalhe`. Manter `timestamptz` só para carimbos de sistema.

**B-06 — Passageiro desvinculado de pessoa — IMPORTANTE**
`viagem_passageiro` tem `cliente_id` opcional e duplica `nome`, `data_nascimento`, `documento text`. Consequências: passaporte de acompanhante não gera alerta de validade (o job só olha `documento_cliente`); o checklist de requisitos do destino (v1.1) não tem onde ler documentos por passageiro; a mesma pessoa viajando duas vezes é digitada duas vezes. Tornar `cliente_id` obrigatório (cada passageiro é um registro em `cliente`, que na prática é "pessoa") e remover as colunas duplicadas. A tela pode criar a pessoa inline com nome e data de nascimento — mesmo esforço de digitação.

**B-07 — Cliente sem CPF — IMPORTANTE**
`cliente` não tem CPF; ele fica em `documento_cliente` como um tipo entre outros. CPF é a chave natural para deduplicar, para emitir (operadoras exigem) e para NFSe com tomador cliente. Coluna `cpf` nula, `unique (agencia_id, cpf) where cpf is not null`, dígitos apenas, validado no C#.

**B-08 — `mes_fechado` booleano por reserva — IMPORTANTE**
Fechamento é um período, não um atributo de linha. Fechar março = `update reserva set mes_fechado = true where ...` em massa, e uma reserva lançada depois com data em março nasce aberta. Modelo certo: `fechamento_periodo (agencia_id, competencia date, tipo: comercial|financeiro, fechado_em, fechado_por)`, e a trava compara a data relevante da reserva com os períodos fechados. A trava vive no C# (precisa do motivo, E-11), não no trigger.

**B-09 — NFSe dentro da reserva — IMPORTANTE**
Ver E-12. Tabela `nota_fiscal (agencia_id, numero, data_emissao, tomador_tipo, tomador_id, valor, status)` e `reserva.nota_fiscal_id` nulo. Representa 1:1 e N:1 com a mesma estrutura. `status_nfse = 'falta_emitir'` vira "reserva com tipo de receita que exige nota e sem `nota_fiscal_id`".

**B-10 — Sem controle de concorrência — IMPORTANTE**
Dois usuários editando a mesma reserva: o último grava, silenciosamente, em dado financeiro. Postgres tem `xmin`; EF Core + Npgsql mapeia como token de concorrência com uma linha de configuração. Retorna 409 e a tela reexibe.

**B-11 — Soft delete inconsistente e em conflito com `on delete cascade` — IMPORTANTE**
`excluido_em` existe em `cliente`, `viagem`, `reserva`; falta em `despesa` (valor financeiro, o próprio documento exige), `servico`, `credito`, `documento_cliente`. Ao mesmo tempo, `viagem → reserva` é `on delete cascade`: um DELETE físico por engano apaga o financeiro inteiro sem rastro. Regra: em cadeia financeira, `on delete restrict`; soft delete propagado pela aplicação (excluir viagem marca reservas). Cascade só onde o filho não tem sentido sozinho e não é financeiro (`viagem_passageiro`, `perfil_permissao`). `anexo` com cascade orfana arquivos no storage — precisa de job que apague o arquivo.

**B-12 — Views não filtram viagem excluída — MELHORIA (bug)**
`vw_comissao_pendente`, `vw_dashboard_mensal`, `vw_teto_mei`, `vw_ranking_fornecedor` checam `r.excluido_em` mas não `v.excluido_em`. Reservas de viagem soft-deletada continuam como comissão pendente. Filtro global no EF resolve de uma vez.

**B-13 — Moeda e câmbio sem semântica — IMPORTANTE**
`moeda char(3)` e `cambio numeric(10,4)` na reserva, mas nada diz em que moeda estão `valor_total`, `valor_cliente` etc. Se uma reserva em USD guarda valores em USD, toda view soma dólar com real. Regra simples: **todo `valor_*` persistido em BRL**, convertido no lançamento; `moeda` e `cambio` são informativos, com `valor_total_original` opcional. Uma linha de documentação no schema e uma validação no C#.

**B-14 — Índices — IMPORTANTE**
Postgres não indexa FK automaticamente. Faltam: `reserva (fornecedor_id, data_compra)`, `anexo (cliente_id)`, `(viagem_id)`, `(reserva_id)`, `credito (cliente_id)`, `(fornecedor_id)`, `oportunidade (cliente_id, estagio)`, `tarefa (usuario_id, status, data)`, `usuario (agencia_id)`, `auditoria (criado_em)` (para expurgo), `viagem (cliente_id, data_volta)` (aviso de duplicada). Os existentes em `viagem (data_ida)`, `(data_volta)`, `cliente (nome)` deveriam ser compostos com `agencia_id` na frente — toda consulta filtra por agência. **Busca global** (v1) precisa de `pg_trgm` com índice GIN em `cliente.nome`, `viagem.destino`, `reserva.localizador`, ou não vai funcionar com `ilike '%x%'`.

**B-15 — Constraints ausentes — MELHORIA**
`valor_* >= 0` (exceto derivados), `num_pax >= 1`, `percentual between 0 and 100`, `comissao_recebida` e `data_recebimento` ambos nulos ou ambos preenchidos, `credito.utilizado` implica `reserva_uso not null`, `regra_pagamento.dia_inicial <= dia_final`. Também `viagem.vendedor_id not null`.

**B-16 — Nomes que vão incomodar — MELHORIA**
`data` como nome de coluna em três tabelas (`tarefa`, `interacao`, `reserva_alteracao`) — ambíguo e feio em query (`where data < ...`). `servico.local` — palavra não reservada mas confunde com `LOCAL`. Triggers `t1..t4`. Índices sem nome (migrations geram nomes aleatórios). Sugestões: `data_prevista`, `ocorrido_em`, `data_alteracao`; `local` → `localidade`; nomear tudo.

**B-17 — `status_reserva` tem um evento disfarçado de estado — IMPORTANTE (pequeno)**
`alterada` não é estado: depois da remarcação a reserva continua `emitida`. A alteração está em `reserva_alteracao`. Enum fica `pendente | emitida | cancelada`.

**B-18 — `fornecedor_id` nulo = venda direta, mais `fornecedor_avulso` — MELHORIA**
Duas formas de dizer "quem é o fornecedor", e "venda direta" com markup **tem** fornecedor (o hotel, o receptivo). Semântica correta: `fornecedor_id` sempre preenchido; "direta" é ausência de intermediário, não ausência de fornecedor. Criar fornecedor inline na tela é mais rápido que digitar texto avulso toda vez.

**B-19 — `auditoria` loga colunas geradas e `motivo` nunca é preenchido — IMPORTANTE**
`to_jsonb(old)` inclui `receita_prevista`, `rav_cliente` etc.: cada edição gera 4–5 linhas de ruído. `motivo` existe na tabela, mas o trigger não tem como recebê-lo (precisaria de `set_config('app.motivo', ...)` antes de cada UPDATE). O requisito "motivo obrigatório ao alterar valor conciliado" só é implementável na aplicação. Ver A-07.

**B-20 — `usuario.ultimo_acesso` — MELHORIA**
Atualizar a cada request é um UPDATE (e uma linha de auditoria, porque `usuario` é auditado!) por chamada. Atualizar no login, ou no máximo uma vez por hora.

**B-21 — `log_acesso` não será populado com Supabase Auth — MELHORIA**
O login acontece no Supabase; o banco não vê tentativas falhas. Só funciona se a API for quem autentica (A-02).

**B-22 — `cliente.ativo` e `cliente.excluido_em` — MELHORIA**
Dois mecanismos para "não aparece mais". Ou `ativo` significa algo de negócio ("deixou de ser cliente") e fica, ou sai.

**B-23 — `agencia` sem configuração — MELHORIA**
Teto do MEI (R$ 81.000), regime tributário, percentual padrão de taxa de serviço, fuso — tudo isso é por agência num produto. Coluna `config jsonb` ou tabela `agencia_config`. Não hardcodar 81.000 numa view.

**B-24 — Performance das policies — IMPORTANTE (se RLS por permissão for mantido)**
`tem_permissao()` é `security definer`, portanto **não é inlined** pelo planner: roda três subselects por linha avaliada. Numa listagem de 2.000 reservas, 6.000 subselects. Mitigação padrão: `(select tem_permissao('viagem.ver'))` para virar InitPlan e executar uma vez por statement. Irrelevante se a autorização for para o C# (A-01).

**B-25 — `regra_pagamento_fornecedor` e `prever_pagamento` — MELHORIA**
Default de 30 dias escondido dentro da função. Overflow de dia do mês (1.5). Cálculo de data com regra de calendário é mais fácil de testar em C# (`DateOnly`, clamp de fim de mês). Mover.

**B-26 — `on delete set null` em `auth_user_id` — MELHORIA**
Some com B-01.

### 2.3 Dados derivados persistidos

- `rav_cliente`, `percentual_comissao`: derivados, geradas. Ok.
- `receita_prevista`, `receita_realizada`: derivados com regra. Mover para domínio (B-03).
- `viagem.status_repasse`: derivado de recebimentos, mas com transição manual (`pago`). Vira entidade `repasse` (X-03).
- `viagem.num_pax` vs. passageiros: derivado potencial. Decidir (1.5).
- `reserva.mes_fechado`: derivado de período. Vira tabela (B-08).
- `reserva.nfse_status`: derivado de existência de nota (B-09).
- Fases operacional e financeira: corretamente **não** persistidas (dependem de `current_date`). Manter como view/consulta.

### 2.4 Informações que faltam

CPF (B-07), `agencia_id` uniforme (B-04), log de acesso a documento (E-20), períodos fechados (B-08), nota fiscal (B-09), lançamentos financeiros (X-02), repasse (X-03), `fornecedor.cnpj`, `fornecedor.percentual_comissao_padrao` (E-22), `anexo.mime_type`, `viagem.criado_por`, `reserva.vencimento_fornecedor` (E-24), configuração da agência (B-23), `xmin` como concorrência (B-10), extensão `pg_trgm` (B-14).

---

## 3. Cruzamento escopo × banco

| Módulo | Regra do escopo | Banco representa? | Achado |
|---|---|---|---|
| Multiempresa | `agencia_id` em tudo, RLS por agência | Parcial: só tabelas raiz | B-04 |
| Viagem/Reserva/Serviço | 1 viagem, N reservas, N serviços | Sim | — |
| Lançamento financeiro | Digitados total, taxas, comissão, pago pelo cliente | Sim | — |
| Tipos de receita | comissão, markup, taxa de serviço | Sim | — |
| Dois RAVs | operadora somada; cliente calculado | Cálculo sim; fluxo do dinheiro não | E-06 |
| Previsão de comissão | Janelas por fornecedor, gravada, editável | Sim | B-25 |
| Repasse | % sobre lucro, liberado após comissão, entra na DRE | Espalhado em `viagem` + `despesa`, sem valor congelado | E-09, E-10, X-03 |
| Sem parcelamento | Só flags pago/recebido | Sim, mas insuficiente para cartão da agência | E-02, E-18 |
| MEI | Teto monitorado, receita bruta a confirmar | View com base incerta | E-03 |
| Visibilidade do vendedor externo | Só o repasse dele | Views existem; contradição sobre lançar | E-01, E-14 |
| Perfis e permissões | Nomeadas, grupos, override, negar vence | Sim, mas global e não enforçado no banco para a maioria | E-15, O-01 |
| Status dois eixos | Calculados | Sim (`vw_fase_viagem`) | E-13 |
| Usuário sem login | `auth_user_id` nulo | Sim | B-01 |
| Auditoria campo a campo | Trigger nas tabelas que importam | Sim, com ruído e sem motivo | B-19 |
| Timeline legível | Derivada do log | Possível | — |
| Soft delete financeiro | Em tudo com valor | Falta em `despesa`, `credito` | B-11 |
| Motivo obrigatório | Ao alterar conciliado/cancelar/excluir | Coluna existe, mecanismo não | B-19 |
| Trava de mês fechado | Permissão específica | Booleano por linha | B-08 |
| Log de acesso a documento | LGPD | **Não existe** | E-20 |
| Anexos com descarte | Bucket privado, URL assinada, data de descarte | Sim; falta job | B-11 |
| NFSe | status, tomador, número, data | Sim, 1:1 forçado | B-09 |
| Forma de pagamento + de quem é o cartão | Por reserva | Sim | E-02 |
| Aviso de viagem duplicada | Cliente com viagem aberta | Consulta de aplicação; falta índice | B-14 |
| Histórico de remarcação | `reserva_alteracao` | Sim; multa duplicada | E-07 |
| Crédito com validade | v1.1 | Tabela já existe | O-05 |
| Checklist de requisitos | v1.1 | Depende de passageiro = pessoa | B-06 |
| Dados operacionais do aéreo | bilhete, localizador cia, voo, bagagem, assento | `servico` + jsonb | B-05 |
| Contato de emergência | `fornecedor.telefone_emergencia` | Sim | — |
| Ocasião | `viagem.ocasiao` | Sim | — |
| Transferência entre agentes | `agente_id` + permissão | Sim | 1.5 |
| Busca global | v1 | Sem índice de texto | B-14 |
| Resumo diário por e-mail | v1 | Fora do banco (job) | — |
| Exportação CSV | v1 | Fora do banco | — |

### Mudanças de modelo que resolvem vários achados de uma vez

**X-01 — Autorização: negócio no C#, tenant no Postgres**
Ver A-01. Elimina E-14, E-15, E-17, B-24, O-03 e a necessidade de views por persona.

**X-02 — Tabela `movimento_financeiro` — CRÍTICO**
Substitui `comissao_recebida`, `data_recebimento`, `divergencia_motivo`, `recebido_do_cliente`, `pago_ao_fornecedor` e o `valor_multa` da reserva por uma tabela de eventos de caixa:

```
movimento_financeiro
  id, agencia_id, reserva_id,
  tipo          text  -- recebimento_operadora | recebimento_cliente | pagamento_fornecedor | estorno | multa_agencia
  valor         numeric(12,2)   -- negativo para estorno
  data          date
  forma_pagamento text
  observacao    text
  criado_por, criado_em, excluido_em
```

Com isso: `receita_recebida(reserva) = soma dos movimentos de entrada − saídas` (caixa, E-05); conciliação = comparar `valor_esperado_operadora` com a soma dos `recebimento_operadora` (E-06); recebimento parcial da operadora funciona sem status especial; estorno é uma linha negativa (E-08, E-19); contas a receber do cliente = reservas com `fluxo_pagamento = cliente_paga_agencia` cujo `recebimento_cliente` < `valor_cliente` (E-18); liberação de repasse olha "valor esperado da operadora foi recebido" e funciona para markup (E-10). A tela "marcar como recebido" cria a linha com o valor esperado num clique — não aumenta a digitação.

**X-03 — Tabela `repasse` — IMPORTANTE**

```
repasse
  id, agencia_id, viagem_id, usuario_id,
  percentual numeric(5,2), base numeric(12,2), valor numeric(12,2),
  status text  -- bloqueado | a_pagar | pago
  liberado_em, pago_em, criado_em
```

Uma linha por viagem/vendedor. `valor` congelado ao pagar (E-09). Pagamento em lote = `update ... where usuario_id = X and status = 'a_pagar'`. DRE lê daqui, não de `despesa` (elimina a duplicação). Sai de `viagem`: `status_repasse`, `data_pagto_repasse`. Fica `percentual_vendedor` (snapshot) — ou vai para `repasse.percentual` na criação.

**X-04 — `nota_fiscal` (B-09), `fechamento_periodo` (B-08), `log_acesso_documento` (E-20)** — tabelas novas, pequenas.

**X-05 — `reserva` enxuta**
Depois de X-02, X-03, B-09: `reserva` fica com identificação (viagem, fornecedor, localizador, data_compra, status), valores comerciais digitados (`valor_total`, `valor_taxas`, `valor_comissao`, `valor_cliente`, `valor_custo`, `taxa_servico`, `rav_operadora`), `fluxo_pagamento`, `forma_pagamento`, `cartao_de`, `moeda/cambio`, previsão (`data_prevista_comissao`, `valor_esperado_operadora`), derivados persistidos pela API (`receita_prevista`), `nota_fiscal_id`, observações, auditoria de linha.

---

## 4. Arquitetura

### A-01 — Onde vive a autorização — CRÍTICO (decisão)

Situação: o schema implementa RLS por **permissão de negócio** (`tem_permissao('viagem.ver')` em cada policy), views por persona para esconder colunas, e funções `security definer` que leem `auth.uid()`. A API C# entra na frente e o documento propõe `SET LOCAL role authenticated` + claims por request para "manter as duas camadas".

Problemas dessa proposta:
- RLS é segurança de **linha**. As permissões que importam (`reserva.ver_custo`, `viagem.ver_resultado`) são de **coluna**. O schema resolve isso com views por persona — uma para vendedor externo. Para Agente sem `ver_resultado`, Financeiro sem `ver_documento`, Contador só leitura, portal do cliente no futuro… cada combinação vira mais uma view. Não escala.
- A maioria das permissões finas (`financeiro.conciliar`, `financeiro.pagar_repasse`, `despesa.lancar`) **não está enforçada no banco**: quem tem `viagem.ver` pode atualizar qualquer coluna de `reserva`. O banco protege menos do que parece.
- E-17: RLS na tabela `usuario` quebra joins legítimos.
- Custo por request: transação obrigatória, dois `SET LOCAL`, funções não-inlinadas por linha (B-24).
- Duas camadas de autorização = dois lugares para ter bug, e o comportamento observado é a **interseção** dos dois, difícil de depurar.

Recomendação:
1. **A API é a única porta.** O navegador nunca acessa o Postgres. Se o Supabase for mantido, remover `public` dos schemas expostos pelo PostgREST (ou garantir que `anon`/`authenticated` não têm policy alguma — RLS ligado sem policy nega tudo — e testar isso).
2. **Autorização de negócio no C#**: um `IAutorizacao` com `Pode(Permissao)` consultado nos endpoints, e DTOs de saída que simplesmente não têm as colunas sensíveis quando o usuário não tem a permissão. É onde segurança de coluna é natural. Testes de integração cobrem "Agente sem `ver_resultado` não recebe `resultado_agencia`".
3. **Isolamento de tenant no Postgres como rede de segurança**, porque é a classe de vazamento catastrófica e custa quase nada: policy `using (agencia_id = current_setting('app.agencia_id', true)::uuid)` idêntica em todas as tabelas de tenant (B-04), `FORCE ROW LEVEL SECURITY`, API conectando com um role que **não** é dono das tabelas, e um interceptor de conexão no EF que faz `SET LOCAL app.agencia_id = ...` ao abrir cada transação (≈10 linhas). Sem função, sem `security definer`, sem `auth.uid()`. Um `if` esquecido no C# vira "lista vazia", não "dados da outra agência".
4. **Filtro global no EF Core** por `agencia_id` e `excluido_em is null` — a mesma regra, aplicada automaticamente em toda query, sem depender de disciplina.

Alternativa: manter RLS por permissão como está e fazer a API impersonar. Trade-off: preserva o investimento no SQL, mas herda todos os problemas acima e obriga o time C# a raciocinar em PL/pgSQL para cada regra de acesso. Não recomendo.

### A-02 — Supabase ou stack .NET autocontida — CRÍTICO (decisão)

O que o Supabase entrega aqui: Postgres gerenciado, Auth, Storage, Studio, CLI de migration. O que o documento já teme: pausa no free tier, ausência de backup, migrar Auth e Storage depois ("é o que dá trabalho"), infra própria da Build Solutions para a API.

**Opção 1 — Supabase-centric**: Supabase (DB + Auth + Storage) + API C# na Build Solutions.
Prós: começa rápido, Auth com convite/reset/MFA pronto, Studio.
Contras: API e banco em redes diferentes (latência em todo request), free tier inadequado para produção (pausa, sem backup) — na prática Pro (US$ 25/mês); schema acoplado ao `auth.*` (B-01); dois fornecedores para operar; a migração de Auth que o documento quer evitar continua no horizonte.

**Opção 2 — .NET autocontida** (recomendada): Postgres + API + storage S3-compatível, tudo em `docker compose` na infra da Build Solutions. Auth **mínima própria**: tabela `usuario` com `senha_hash` (`PasswordHasher<T>` do pacote `Microsoft.Extensions.Identity.Core` — só o hasher, sem as tabelas do Identity), token de convite, token de reset, sessão por cookie HttpOnly (front servido pela própria API, A-04). ~200 linhas, tudo testável, nada para migrar depois.
Prós: uma linguagem, um deploy, um fornecedor (a própria Build Solutions), banco 100% portátil, `log_acesso` funciona, latência local.
Contras: escrever convite/reset (2–3 dias), operar backup (mas isso já era obrigação no free tier), sem Studio (pgAdmin/DBeaver resolvem), MFA fica para depois (adicionar TOTP é um pacote).

**Opção 2b**: igual à 2, mas com Postgres gerenciado (Supabase Pro, Neon, RDS) em vez de container. Faz sentido se ninguém na Build Solutions quiser cuidar de backup/upgrade de Postgres. O schema não muda entre 2 e 2b — essa é a vantagem de tirar o `auth.*` do banco.

Storage: Cloudflare R2 (S3-compatível, 10 GB grátis, sem egress) ou MinIO no mesmo compose. Uma interface `IArmazenamentoArquivo` com `Salvar`, `GerarUrlAssinada`, `Excluir`. Upload passa pela API (arquivos pequenos: passaporte, voucher) — um caminho de autenticação só, e é onde o log de acesso a documento (E-20) é gravado.

### A-03 — Estilo de arquitetura: monólito modular, sem cerimônia — IMPORTANTE

Escala real: uma agência, cinco usuários, algumas centenas de viagens por ano. Produto futuro: dezenas de agências. Nada disso justifica microserviços, filas ou serviços separados — e o documento já descarta isso corretamente.

O que **não** usar, e por quê:
- **Clean Architecture com 5+ projetos e camada Application separada**: para 10 módulos CRUD com cálculo financeiro, a separação Domain/Application/Infrastructure/Presentation vira 4 arquivos para cada endpoint. Três projetos bastam (abaixo).
- **CQRS/MediatR**: não há leitura e escrita com modelos divergentes o bastante. Endpoints minimal API chamando um serviço de módulo é mais curto e mais rastreável.
- **Repository/Unit of Work sobre EF Core**: `DbContext` já é os dois. Um repositório genérico só esconde `IQueryable` e obriga a reescrever filtros.
- **AutoMapper**: DTOs como `record` com construtor de projeção (`Select(r => new ReservaDto(...))`). Explícito e mais rápido.
- **Domain Events / Outbox**: os "eventos" (liberar repasse ao receber comissão, gerar tarefas ao criar viagem) acontecem na mesma transação, no mesmo processo. Chamada direta de método.
- **Mensageria (RabbitMQ, etc.)**: nenhum consumidor externo, nenhum pico. Não.
- **Cache distribuído (Redis)**: dados cabem em memória de um Postgres pequeno. `IMemoryCache` para permissões do usuário (1 min) se aparecer necessidade. Provavelmente nem isso.
- **Versionamento de API com framework**: front é first-party e deploya junto. Prefixo `/api/v1/` reservado; `Asp.Versioning` só quando existir app mobile em loja.

O que usar:
- **Minimal API** com `MapGroup` por módulo, um arquivo `Endpoints.cs` por módulo.
- **Serviços de módulo** simples (classes com métodos) onde há regra; para CRUD puro, o endpoint usa o `DbContext` direto.
- **Domínio puro** (entidades + cálculos financeiros) num projeto sem dependência de EF, para testes unitários das fórmulas.
- **Vertical slice por módulo**: pasta `Modules/Viagens/` contém endpoints, DTOs e serviço do módulo. Não separar por tipo técnico.

### A-04 — Frontend — IMPORTANTE (decisão)

**Recomendação: React + Vite + TypeScript**, servido como arquivos estáticos **pela própria API** (mesma origem → cookie HttpOnly, sem CORS, sem CSRF cross-site, um deploy). Cloudflare na frente para TLS/CDN se quiser.
Motivo: o requisito dominante é tela de lançamento rápida, com teclado, em PWA no celular. O ecossistema React de formulários (react-hook-form + zod), tabelas (TanStack Table), dados (TanStack Query) e componentes (shadcn/ui ou Mantine) é o mais maduro para isso; payload inicial pequeno.
Alternativa: **Blazor WebAssembly** — mesma linguagem, MudBlazor/Radzen. Vale se ninguém no time escreve TypeScript. Contras: primeiro carregamento pesado (runtime .NET), pior em rede móvel, ecossistema menor, debugging mais chato. Blazor Server **não**: exige WebSocket estável, ruim no celular.
Trade-off honesto: o documento escolheu C# "por fluência". Se a fluência for exclusivamente C#, Blazor WASM é a escolha coerente com esse argumento e o custo é performance de primeiro load. Decisão do time.

### A-05 — Acesso a dados: EF Core + Npgsql — IMPORTANTE (decisão)

O documento propõe Dapper. Para este sistema, **EF Core 10** entrega três coisas que resolvem achados desta análise sem código repetido: **filtros globais** (`agencia_id`, soft delete — B-04, B-11, B-12), **interceptor de SaveChanges** para auditoria com diff e motivo (B-19) e para `atualizado_em`/`criado_por`, e **`xmin` como token de concorrência** (B-10). Também gera migrations a partir do modelo.
Dapper para **relatórios e views** (dashboard, ranking, agenda): SQL escrito à mão, mapeado para DTO. Os dois convivem no mesmo `NpgsqlConnection`.
Trade-off: EF tem curva (tracking, N+1, `AsNoTracking` em leitura). Dapper puro obriga a escrever `where agencia_id = @a and excluido_em is null` em toda query — exatamente o "if esquecido" que o documento teme.
Migrations: EF Core migrations para tabelas; views e a policy de tenant como SQL idempotente em arquivos `.sql` embutidos, aplicados por `migrationBuilder.Sql`. Alternativa SQL-first (grate/DbUp) se o time preferir escrever DDL à mão — funciona, mas perde `xmin`/filtros/auditoria automáticos? Não: esses são do EF em runtime, independem de como a migration é feita. A escolha de ferramenta de migration é secundária; a de ORM não.

### A-06 — Onde ficam os cálculos — IMPORTANTE

Regra única, para não ter fórmula duplicada em SQL e C#:
- **Cálculo de escrita** (valores persistidos: `receita_prevista`, `valor_esperado_operadora`, `repasse.valor`, data prevista de comissão): **C#, no domínio, testado por unidade**, gravado na coluna ao salvar. A API é o único escritor, então a denormalização é segura.
- **Estado de leitura dependente de data** (fase operacional, fase financeira, dias de atraso, teto do MEI acumulado): **SQL, em view ou query de relatório**. Depende de `current_date` e é set-based; não faz sentido persistir.
- Aritmética pura sem regra (`rav_cliente = valor_cliente − valor_total`, `percentual_comissao`): pode continuar como coluna gerada.

### A-07 — Auditoria e timeline — IMPORTANTE

Trocar o trigger genérico por um **interceptor de SaveChanges** que grava, por entidade alterada, uma linha em `auditoria` com `tabela`, `registro_id`, `acao`, `alteracoes jsonb` (campo → {de, para}), `motivo`, `usuario_id`, `agencia_id`, `criado_em`. Ignora colunas derivadas. O `motivo` vem do request (obrigatório quando o endpoint exige — cancelamento, exclusão, edição de conciliado/mês fechado). A timeline da viagem é uma query nessa tabela por `registro_id` ∈ {viagem, suas reservas, seus serviços, seus movimentos}, renderizada com frases ("Fulano alterou valor da comissão de 1.000 para 1.100 — motivo: ...").
Manter um trigger mínimo no banco só se alguém for editar dados fora da API (Studio, script). Se a API é a única porta, não precisa.
Expurgo: job mensal apaga `auditoria` com mais de N meses (config da agência), exceto ações `DELETE`.

### A-08 — Jobs em background — IMPORTANTE

Necessários na v1: resumo diário por e-mail, geração de tarefas de validade de passaporte, expurgo de anexos com `data_descarte`, expurgo de auditoria, (opcional) ping para não pausar o Supabase — irrelevante na opção 2.
Implementação: **`BackgroundService` com `PeriodicTimer`** no próprio host da API, uma classe por job, tabela `job_execucao (nome, iniciado_em, terminado_em, erro)` para visibilidade. Sem Hangfire/Quartz por enquanto.
Teto conhecido: com **duas instâncias** da API os jobs rodam em dobro. Solução quando chegar lá: `pg_try_advisory_lock` no início do job (5 linhas), ou Hangfire com storage Postgres. Uma instância na piloto.

### A-09 — Integrações externas e notificações

E-mail: **Resend** (proposto) é adequado; alternativas Postmark, Amazon SES. Interface `IEnviadorEmail` com um método. Templates em Razor ou string interpolada — resumo diário é uma tabela HTML.
WhatsApp, operadoras, gateway: fora de escopo. Preparação suficiente: `interacao.canal`, `fornecedor.codigo_externo` (futuro), `reserva.origem` (`manual` | futura importação). Nada mais.

### A-10 — Logs, observabilidade, erros

- **Serilog** → console JSON (Docker coleta) + **Seq** (self-hosted, gratuito para uma instância) ou Grafana Loki na Build Solutions. Enriquecer todo log com `agencia_id`, `usuario_id`, `request_id`.
- **Health checks** (`/health`) com verificação de Postgres. Uptime externo (UptimeRobot, gratuito).
- Exceções: `AddProblemDetails()` + `IExceptionHandler` → RFC 9457. Erros de domínio (`RegraDeNegocioException` com código) → 422 com `{ codigo, mensagem }`; concorrência → 409; autorização → 403 sem vazar existência.
- OpenTelemetry/métricas: **depois**, quando houver mais de uma agência. Um `Stopwatch` no log de request já responde "quanto demora o lançamento".
- Sentry (free tier) para agrupar exceções: opcional, barato, útil.

### A-11 — Segurança

- Cookie HttpOnly + SameSite=Lax (mesma origem), antiforgery para mutações se cookie; ou bearer em memória se o front for separado. Preferir cookie.
- `AddRateLimiter` no login (built-in). Bloqueio progressivo após N falhas, registrado em `log_acesso`.
- Segredos por variável de ambiente (`docker compose` + `.env` fora do Git). Nunca em `appsettings`.
- Headers (HSTS, CSP básico) via Caddy/nginx na frente.
- LGPD: log de acesso a documento (E-20), expurgo de anexo, anonimização (E-25, depois), exportação CSV registrada em auditoria.
- Backup: `pg_dump` diário para R2 com retenção 30 dias, **restauração testada** uma vez por trimestre (um script). Sem isso o backup não existe.

### A-12 — Testes

- **Unidade** (`Meridiano.Domain.Tests`, xUnit): fórmulas financeiras com os exemplos numéricos do documento de regras (E-05), previsão de data de comissão (fim de mês, virada de ano), transições de repasse, cálculo de fases. Rápidos, sem banco.
- **Integração** (`Meridiano.Api.Tests`): `WebApplicationFactory` + **Testcontainers.PostgreSql** (Postgres real em Docker). Cobrem: filtro de tenant (agência B não vê A — com e sem RLS), permissões por perfil (Agente não recebe `resultado_agencia`), soft delete propagado, concorrência (409), migrations aplicam do zero.
- **E2E** (Playwright, poucos): o fluxo "lançar viagem com 4 reservas" — com cronômetro. É o teste do risco número um.
- Sem mock de `DbContext`. Sem teste de CRUD trivial.

### A-13 — Deploy e CI/CD

- **Dockerfile** multi-stage para a API (inclui o build do front em `wwwroot`).
- **`docker compose`** na VM da Build Solutions: `api`, `postgres` (volume), `caddy` (TLS automático), `seq` (opcional), `backup` (cron com `pg_dump` → R2).
- **GitHub Actions**: PR → `dotnet build`, `dotnet test` (Testcontainers roda no runner), `npm run build`, lint. `main` → build da imagem, push para GHCR, deploy por SSH (`docker compose pull && up -d`) com migrations aplicadas por `migrations bundle` antes de subir a nova versão.
- Ambientes: `local` (compose), `producao`. Staging só quando houver segunda agência.
- Cloud vs. próprio: infra própria já existe e é a decisão do documento. Alternativas se a operação pesar: Fly.io/Railway (compose-like), Azure Container Apps. Migração é trivial porque tudo é container + Postgres.

### A-14 — Multiempresa: o que fazer agora e o que não fazer

Agora (barato): `agencia_id` em tudo (B-04), filtro global, policy de tenant, código de viagem por agência (já está), pasta por agência no storage (já está), `unique (agencia_id, ...)` em vez de unique global, `agencia.config`.
Não fazer agora: tela de cadastro de agência self-service, planos/billing, subdomínio por agência, perfis customizáveis por agência, catálogo global de fornecedores. Tudo isso encaixa depois sem mudar o modelo.

---

## 5. Domínio de agência de viagens — cobertura

| Conceito | Situação | Comentário |
|---|---|---|
| Clientes | Ok | Falta CPF (B-07). `cliente` funciona como "pessoa". |
| Passageiros | Fraco | Vincular a pessoa (B-06). |
| Responsável financeiro | Implícito | `viagem.cliente_id`. Suficiente. |
| Fornecedores / hotéis / cias / operadoras | Ok | `tipo_fornecedor`. Falta CNPJ e % padrão (E-22). |
| Serviços | Ok | jsonb tipado por tipo, definido em C# (`record` por tipo). |
| Reservas / vendas | Ok | Enxugar (X-05). |
| Cotações / orçamentos | Fora | `oportunidade` acompanha o pipeline. Coerente. |
| Pacotes | Implícito | Reserva com N serviços. Não precisa de entidade. |
| Roteiros | Implícito | Serviços ordenados por data. Não precisa de entidade. |
| Quartos / trechos / voos | jsonb | Suficiente para v1. Sub-tabelas só se houver consulta por trecho (ex.: "quem embarca amanhã"). |
| Transfers / passeios / seguros / ingressos | Ok | `tipo_servico`. |
| Documentação / vistos | Ok | `documento_cliente`; checklist v1.1. |
| Vouchers | Anexo | Geração fora de escopo. |
| Pagamentos / parcelamentos | Decisão: não | Mas contas a receber do cliente é necessário (E-18). |
| Recebimentos | Fraco | `movimento_financeiro` (X-02). |
| Comissões | Ok | Com X-02 fica completo. |
| Repasses | Fraco | `repasse` (X-03). |
| Cancelamentos / estornos | Indefinido | E-08, E-19. |
| Reembolsos / créditos | v1.1 | Tabela existe; criar quando implementar. |
| Multas | Ambíguo | E-07. |
| Alterações | Ok | `reserva_alteracao`. |
| Moedas / câmbio | Fraco | B-13. |
| Custos / margem | Ok | `valor_custo` para markup; views. |
| Vendedores / metas | Ok / v1.1 | — |
| Histórico de atendimento | Ok | `interacao`. |

## 6. Evolução futura — o que a arquitetura proposta suporta

| Evolução | Suporte | O que **bloquearia** (e por isso foi evitado) |
|---|---|---|
| Múltiplas agências | `agencia_id` uniforme + filtro + policy | `agencia_id` só nas raízes; perfis globais |
| Filiais | `filial_id` opcional em `usuario`/`viagem`; tenant continua a agência | Nada no modelo atual bloqueia |
| Perfis e permissões customizáveis | Matriz em código hoje; tabelas depois (O-01) | — |
| Portal do cliente | Mesma API, segunda audiência de autenticação, DTOs restritos | Autorização só por views RLS exigiria um terceiro conjunto de views |
| Integração com operadoras/hotéis/cias | `reserva.origem`, `fornecedor.codigo_externo`, importação criando reservas pelo mesmo serviço de módulo | Lógica de lançamento espalhada em triggers |
| Meios de pagamento | `movimento_financeiro` já é o lugar; gateway cria movimentos | Booleanos `recebido_do_cliente` |
| WhatsApp | `interacao` + job de envio | — |
| Vouchers / contratos (PDF) | QuestPDF no módulo Documentos; grava em `anexo` | — |
| Assinatura eletrônica | Integração externa (Clicksign/ZapSign); `anexo.assinado_em` | — |
| Relatórios / dashboard | Views + Dapper; ou Metabase apontando para réplica de leitura | Fórmulas em colunas geradas divergindo do C# |
| App mobile | Mesma API com bearer token; PWA cobre antes | Cookie-only sem alternativa (por isso a camada de auth emite token também) |

---

## 7. Overengineering identificado

**O-01 — RBAC completo (perfis + grupos + override por usuário + negar vence) para cinco usuários — IMPORTANTE**
Quatro tabelas, uma função de três subselects e um seed, para um cenário em que os perfis são fixos por meses. V1: `enum Perfil { Dono, Financeiro, Agente, VendedorExterno, Contador }` em `usuario.perfil`, e uma matriz `Perfil → Permissao[]` **em código C#**, com teste. Mudar a matriz = deploy, aceitável na piloto. Quando uma agência precisar de perfil customizado, as tabelas entram e a matriz em código vira seed. `usuario_permissao` (override) só se alguém pedir.

**O-02 — Auditoria campo a campo por trigger genérico — IMPORTANTE**
Loga colunas geradas, não recebe motivo, depende de `usuario_atual()`. Ver A-07.

**O-03 — RLS por permissão de negócio com funções `security definer` — CRÍTICO**
Ver A-01. Complexidade alta, cobertura parcial, custo por linha.

**O-04 — Views por persona como mecanismo de segurança de coluna — IMPORTANTE**
`vw_minha_viagem`, `vw_reserva_vendedor`. Uma persona hoje; explode com cada combinação de permissão. DTOs no C#.

**O-05 — Tabelas e enums criados para a v1.1 — MELHORIA**
`despesa`, `credito`, `tipo_despesa`. Criar quando a funcionalidade for implementada; o desenho atual pode ficar num arquivo `docs/` como intenção. Evita drift entre tabela vazia e requisito que muda.

**O-06 — `agencia.plano` — MELHORIA**
Billing não existe. Coluna inofensiva, mas é sinal de pensar produto antes de ter a segunda agência. Manter nula ou tirar.

**O-07 — "Isolar Auth e Storage atrás de interfaces desde o começo" — ajustar**
Storage: sim, uma interface de três métodos. Auth: com auth própria (A-02) não há o que isolar. Se ficar Supabase Auth, a "interface" é só o validador de JWT — não precisa de abstração.

**O-08 — Duas camadas de autorização "para garantir" — CRÍTICO**
É a forma mais cara de ter um bug: cada regra existe duas vezes, e a resposta observada é a interseção. Uma camada de negócio (C#) e uma rede de segurança de tenant (Postgres), com responsabilidades distintas, não sobrepostas.

O que **não** é overengineering, apesar de parecer: multiempresa desde o início; dois RAVs e três tipos de receita (é o negócio); `jsonb` em serviço; soft delete com motivo; auditoria com timeline; código de viagem por agência.

---

## 8. Classificação consolidada

### CRÍTICO — antes de qualquer código
- A-01 / O-03 / O-08 — Autorização: negócio no C#, tenant no Postgres.
- A-02 — Supabase-centric vs. .NET autocontida (recomendado: autocontida).
- B-01 — Tirar `auth.*` do schema.
- E-01 — Vendedor externo lança ou só vê.
- E-02 — Fluxo de pagamento do cliente (a quem paga).
- E-03 / E-05 — Caixa vs. competência; `receita_realizada` errada.
- E-08 — Efeito financeiro do cancelamento.
- X-02 — `movimento_financeiro`.

### IMPORTANTE — agora, evita retrabalho
- E-04, E-06, E-07 — Base do repasse, RAV do cliente, multa: definir por escrito com exemplos.
- E-09, E-10, X-03 — Tabela `repasse`, valor congelado, lote.
- E-11, B-08 — `fechamento_periodo`.
- E-12, B-09 — `nota_fiscal`.
- E-14, E-15, E-17 — Visibilidade de clientes, perfis globais, nome de usuário.
- E-18, E-19, E-20, E-21, E-22 — Contas a receber do cliente, estorno, log de documento, expurgo, % padrão por fornecedor.
- B-02 — Enums → text + check.
- B-03 / A-06 — Cálculos de escrita no C#.
- B-04 / A-14 — `agencia_id` em tudo.
- B-05 — `timestamp` sem tz para serviços.
- B-06 — Passageiro = pessoa.
- B-07 — CPF.
- B-10 — Concorrência (`xmin`).
- B-11 — Soft delete uniforme; `restrict` em cadeia financeira.
- B-13 — Valores em BRL.
- B-14 — Índices compostos, FK, `pg_trgm`.
- B-17 — Tirar `alterada`.
- B-19 / A-07 — Auditoria por interceptor.
- A-03, A-04, A-05, A-08 — Monólito modular, frontend, EF Core, jobs.
- O-01, O-02, O-04 — Simplificações de RBAC, auditoria, views.

### MELHORIA — depois
- E-13, E-16, E-23, E-24, E-25, E-26, casos de borda de 1.5.
- B-12, B-15, B-16, B-18, B-20, B-21, B-22, B-23, B-25.
- O-05, O-06, O-07.
- A-10 (OpenTelemetry), A-11 (MFA, anonimização).

### OPCIONAL — estratégia de produto
- E-27 — Usuário em várias agências (mudar o unique agora custa zero; a funcionalidade, depois).
- Vários vendedores por viagem; reserva de grupo; cliente PJ; catálogo global de fornecedores.
- Blazor vs. React (A-04) — depende do time.
- Postgres em container vs. gerenciado (A-02, 2 vs. 2b).

---

## 9. Proposta consolidada

### 9.1 Principais problemas
1. Duas camadas de autorização, com a camada do banco resolvendo o problema errado (linha vs. coluna).
2. Semântica financeira ambígua em caixa/competência, RAV, multa, cancelamento, base do repasse.
3. Schema acoplado ao Supabase.
4. Modelagem que vai travar: enums nativos, `mes_fechado` por linha, NFSe 1:1, passageiro solto, sem CPF, sem concorrência, `timestamptz` em voo.
5. RBAC, auditoria e views sobredimensionados para a escala.

### 9.2 Principais melhorias
1. Autorização no C# + policy de tenant no Postgres + filtro global no EF.
2. `movimento_financeiro`, `repasse`, `nota_fiscal`, `fechamento_periodo`, `log_acesso_documento`.
3. Cálculos de escrita no domínio C# com testes; estados de leitura em SQL.
4. `agencia_id` em toda tabela; enums como text; `xmin`; índices compostos; `pg_trgm`.
5. Stack autocontida em .NET 10 + Postgres + R2, um compose, um deploy.

### 9.3 Arquitetura sugerida
Monólito modular. Uma API ASP.NET Core (Minimal API) que também serve o front. Postgres como único armazenamento de estado. Jobs como hosted services no mesmo processo. Sem fila, sem cache distribuído, sem serviços separados. Autorização por permissão em C#; isolamento de tenant por RLS simples; auditoria por interceptor; soft delete por filtro global.

### 9.4 Tecnologias sugeridas

| Camada | Recomendação | Motivo | Alternativas | Trade-off |
|---|---|---|---|---|
| Runtime | **.NET 10 LTS** | Suporte até nov/2028; Minimal API madura | .NET 9 (STS) | Nenhum motivo para STS |
| API | ASP.NET Core Minimal API, `MapGroup` por módulo | Menos cerimônia que controllers, mesma capacidade | Controllers | Controllers só se o time preferir atributos/filters |
| Dados | **EF Core 10 + Npgsql**; Dapper em relatórios | Filtros globais, interceptors, `xmin`, migrations | Dapper puro | Dapper puro repete filtro de tenant em cada query |
| Banco | **PostgreSQL 17** | Já decidido; RLS, jsonb, `pg_trgm` | — | — |
| Hospedagem do banco | Container no compose (2) ou gerenciado (2b) | Latência local; portabilidade | Supabase Pro, Neon, RDS | Gerenciado tira backup/upgrade das costas por US$ 20–30/mês |
| Auth | **Própria mínima** (hash + cookie + convite/reset) | Nada para migrar; `log_acesso` funciona | Supabase Auth; ASP.NET Identity completo; Keycloak | Supabase = rápido mas acoplado; Identity completo = 7 tabelas para 5 usuários; Keycloak = mais uma coisa para operar |
| Frontend | **React + Vite + TS** (shadcn/ui, react-hook-form, TanStack Query) servido pela API | Formulários rápidos, PWA leve | Blazor WASM | Blazor se o time não escreve TS |
| Storage | **Cloudflare R2** via S3 SDK; ou MinIO local | Grátis até 10 GB, sem egress, S3-compatível | Supabase Storage, S3 | Supabase Storage acopla ao fornecedor |
| Documentos (PDF) | QuestPDF (quando entrar voucher/contrato) | C# nativo, sem browser headless | Playwright PDF | Não é v1 |
| E-mail | **Resend** | Simples, API limpa | Postmark, SES | Todos equivalentes nesse volume |
| Jobs | `BackgroundService` + `PeriodicTimer` + tabela de execução | Zero dependência | Hangfire, Quartz | Adicionar quando houver 2 instâncias ou retry complexo |
| Cache | Nenhum (talvez `IMemoryCache` para permissões) | Volume mínimo | Redis | Não |
| Mensageria | Nenhuma | Sem consumidores externos | — | — |
| Logs | **Serilog** → console JSON + Seq/Loki | Estruturado, self-hosted | Sentry para exceções (opcional) | — |
| Monitoramento | Health checks + UptimeRobot; OpenTelemetry depois | Suficiente para uma agência | Grafana stack | Depois |
| Testes | xUnit + Testcontainers.PostgreSql + Playwright (poucos) | Banco real nos testes | — | — |
| Containers | Docker + compose; Caddy para TLS | Um arquivo, deploy por SSH | Kubernetes | Não |
| CI/CD | GitHub Actions → GHCR → SSH deploy | Simples, gratuito | — | — |
| Infra | VM da Build Solutions | Já existe | Fly.io, Azure Container Apps | Portável por ser container |
| Backup | `pg_dump` diário → R2, retenção 30d, restauração testada trimestral | Obrigatório em qualquer opção | pgBackRest | pgBackRest quando houver PITR |

### 9.5 Estrutura da solution

```
viva-erp/
├── Meridiano.sln
├── docker-compose.yml
├── Dockerfile
├── src/
│   ├── Meridiano.Api/                    # host
│   │   ├── Program.cs
│   │   ├── Auth/                       # login, cookie, convite, reset, IAutorizacao, matriz Perfil→Permissao
│   │   ├── Modules/
│   │   │   ├── Clientes/               # Endpoints.cs, Dtos.cs, ClienteService.cs
│   │   │   ├── Fornecedores/
│   │   │   ├── Viagens/                # viagem, passageiros, reservas, serviços, alterações
│   │   │   ├── Financeiro/             # movimentos, conciliação, repasses, fechamento, notas fiscais
│   │   │   ├── Agenda/                 # tarefas, automações
│   │   │   ├── Anexos/
│   │   │   ├── Relatorios/             # dashboard, views, CSV, busca global (Dapper)
│   │   │   └── Admin/                  # usuários, agência, auditoria/timeline
│   │   ├── Jobs/                       # ResumoDiarioJob, ValidadeDocumentoJob, ExpurgoJob
│   │   ├── Infra/                      # email, storage, problem details, logging
│   │   └── wwwroot/                    # build do front (gerado)
│   ├── Meridiano.Domain/                 # entidades, enums, cálculos (sem EF)
│   │   ├── Viagens/                    # Viagem, Reserva, Servico, CalculoReceita
│   │   ├── Financeiro/                 # MovimentoFinanceiro, Repasse, CalculoRepasse, PrevisaoComissao
│   │   ├── Pessoas/                    # Cliente, Documento, Usuario
│   │   └── Comum/                      # Permissao, Perfil, RegraDeNegocioException
│   └── Meridiano.Data/                   # AppDbContext, configurações, migrations, interceptors
│       ├── Interceptors/               # TenantConnectionInterceptor, AuditoriaInterceptor
│       ├── Configurations/
│       ├── Migrations/
│       └── Sql/                        # views, policies (idempotente)
├── tests/
│   ├── Meridiano.Domain.Tests/
│   └── Meridiano.Api.Tests/              # Testcontainers
├── web/                                # React + Vite + TS
└── docs/
```

Três projetos de código, dois de teste. Não mais.

### 9.6 Módulos principais
1. **Identidade e acesso** — login, convite, reset, perfis fixos, permissões, log de acesso.
2. **Clientes e CRM** — pessoas (cliente/passageiro), documentos, interações, oportunidades.
3. **Fornecedores** — cadastro, regras de pagamento, % padrão.
4. **Viagens** — viagem, passageiros, reservas, serviços, alterações, aviso de duplicada, transferência.
5. **Financeiro** — movimentos, conciliação, repasses, fechamento de período, notas fiscais; (v1.1) despesas, DRE, créditos.
6. **Agenda** — tarefas manuais e automáticas.
7. **Anexos** — upload, URL assinada, descarte, log de acesso a documento.
8. **Relatórios** — dashboard, fases, comissões pendentes, ranking, teto MEI, CSV, busca global.
9. **Auditoria** — registro por interceptor, timeline, expurgo.
10. **Jobs** — resumo diário, validade de documentos, expurgos.

### 9.7 Alterações necessárias no banco (schema v2)
1. Remover `auth.users` FK e `auth.uid()`; `usuario.auth_user_id` → `senha_hash`, `convite_token`, etc. (ou manter `auth_user_id uuid` simples se Supabase Auth ficar).
2. `agencia_id not null` em todas as tabelas de tenant; índices compostos `(agencia_id, ...)`; policy única de tenant; `FORCE ROW LEVEL SECURITY`; role da API sem ownership.
3. Enums → `text` + `check`.
4. Remover de `reserva`: `comissao_recebida`, `data_recebimento`, `divergencia_motivo`, `recebido_do_cliente`, `pago_ao_fornecedor`, `valor_multa`, `nfse_*`, `mes_fechado`, `receita_realizada`. Adicionar `fluxo_pagamento`, `valor_esperado_operadora`, `nota_fiscal_id`, `vencimento_fornecedor` (opcional), `valor_total_original` (opcional). `receita_prevista` vira coluna comum escrita pela API.
5. Novas: `movimento_financeiro`, `repasse`, `nota_fiscal`, `fechamento_periodo`, `log_acesso_documento`, `job_execucao`.
6. Remover de `viagem`: `status_repasse`, `data_pagto_repasse`. `vendedor_id not null`. Adicionar `criado_por`.
7. `viagem_passageiro.cliente_id not null`; remover `nome`, `data_nascimento`, `documento`.
8. `cliente.cpf` + unique parcial; decidir `ativo` vs `excluido_em`.
9. `fornecedor.cnpj`, `fornecedor.percentual_comissao_padrao`.
10. `servico.data_inicio/data_fim` → `timestamp`; `local` → `localidade`.
11. `status_reserva` sem `alterada`; `reserva_alteracao.multa` ganha `multa_paga_por`.
12. Soft delete (`excluido_em`, `excluido_por`) em `servico`, `despesa`, `credito`, `documento_cliente`; `on delete restrict` na cadeia viagem→reserva→serviço/movimento.
13. Remover triggers de auditoria, trava de mês, liberação de repasse, previsão de comissão, tarefas automáticas (vão para C#). Manter: `set_atualizado_em` (ou interceptor), `fn_codigo_viagem` (aceitável no banco), checks.
14. Remover funções `usuario_atual`, `agencia_atual`, `tem_permissao`, `viagem_da_agencia`, todas as policies por permissão, views por persona.
15. Views mantidas como read-model (`vw_fase_viagem`, `vw_comissao_pendente`, `vw_agenda`, `vw_dashboard_mensal`, `vw_ranking_fornecedor`, `vw_teto_mei`), reescritas sobre `movimento_financeiro` e com `agencia_id`; sem `security_invoker` (a API é o único leitor e já filtra).
16. `pg_trgm` + índices GIN para busca.
17. Renomear `data` → `data_prevista`/`ocorrido_em`; nomear triggers e índices.
18. `agencia.config jsonb` (teto MEI, taxa padrão).
19. `unique (agencia_id, auth_user_id)` em vez de global, se a coluna existir.
20. Remover `plano` ou deixar nulo. Adiar `despesa`, `credito`, `tipo_despesa` para a migration da v1.1.

### 9.8 Funcionalidades que faltam no escopo
Contas a receber do cliente (E-18), estorno de comissão (E-19), log de acesso a documento (E-20), expurgo de auditoria (E-21), % padrão por fornecedor (E-22), aviso de reserva duplicada (E-23), vencimento à operadora opcional (E-24), cancelamento de tarefas ao cancelar viagem (1.5), responsável padrão em tarefa automática (1.5), reabertura de tarefa em remarcação (1.5), anonimização LGPD (E-25, depois), modelos de mensagem (1.7, depois).

### 9.9 Riscos técnicos
1. **Tempo de lançamento** — o documento já sabe. Mitigação técnica: % padrão por fornecedor, criação inline de cliente/fornecedor, atalhos de teclado, salvar rascunho, teste E2E cronometrado desde a primeira versão da tela.
2. **Fórmulas financeiras mudarem após o piloto** — inevitável. Mitigação: cálculos em C# com testes que usam viagens reais da planilha; `receita_prevista` recalculável em massa por um comando.
3. **Vazamento entre agências** — mitigação em duas camadas (filtro EF + policy).
4. **Jobs duplicados ao escalar** — teto conhecido; advisory lock quando chegar.
5. **Backup não testado** — script de restauração no CI ou trimestral.
6. **Dono como único admin** — se o dono se tranca fora (perfil "sistema" ajuda), precisa de um comando CLI de recuperação (`dotnet run -- reset-admin`).
7. **Horário local vs. UTC** em serviços — B-05; erro clássico em sistemas de viagem.
8. **LGPD** — documentos pessoais em storage com URL assinada e log; expurgo funcionando antes de entrar dado real.
9. **PWA no celular com formulário grande** — validar cedo no aparelho da agência, não no desktop.

### 9.10 Decisões antes de implementar
1. **Stack**: Supabase-centric (1), .NET autocontida com Postgres em container (2) ou gerenciado (2b). Recomendo 2 ou 2b.
2. **Autorização**: negócio no C# + tenant no Postgres. Confirmar.
3. **Vendedor externo**: só vê (a), lança parcial (b) ou lança tudo (c).
4. **Fluxo de pagamento**: quem recebe do cliente em cada tipo de venda; o que `cartao_de = agencia` implica.
5. **RAV do cliente**: quem recolhe e quando vira caixa.
6. **Multa**: quem paga; como afeta receita e repasse.
7. **Cancelamento**: estorno, crédito, repasse já pago.
8. **Base do repasse**: receita prevista ou recebida; inclui taxa de serviço, RAVs; desconta multa.
9. **Competência**: data que define mês comercial e mês financeiro; regime do MEI (resposta do contador).
10. **NFSe**: por reserva, por mês/operadora, ou ambos.
11. **Moeda**: tudo em BRL persistido.
12. **Passageiro = pessoa** (registro em `cliente`).
13. **ORM**: EF Core + Dapper em relatórios. Confirmar.
14. **Frontend**: React ou Blazor WASM, servido pela API.
15. **Perfis fixos em código na v1**. Confirmar.
16. **Vendedor externo vê clientes de quem?**
17. **Vencimento à operadora**: reincluir como opcional ou manter descartado.
18. **Infra**: VM da Build Solutions com compose; quem opera backup.

---

## 10. Ordem de execução

**Fase 0 — Fechar o domínio (1 semana, sem código)**
1. Sessão com a agência piloto: pegar **três viagens reais da planilha** (uma comissionada simples, uma com 4 portais e RAV, uma com remarcação/cancelamento) e responder às decisões 3–10 e 16–17 descrevendo, por escrito, o fluxo do dinheiro de cada uma. Isso resolve mais ambiguidade do que qualquer reunião abstrata.
2. Perguntar ao contador (decisão 9).
3. Escrever `regras-e-escopo-v2.md`: glossário (viagem, reserva, serviço, receita prevista, receita recebida, valor esperado da operadora, RAV operadora, RAV cliente, repasse, movimento, fechamento), fórmulas com exemplos numéricos, tabela de permissões por perfil, respostas das decisões.
4. Fechar decisões técnicas 1, 2, 13, 14, 15, 18.

**Fase 1 — Modelo v2 (2–3 dias)**
5. `schema-agencia-v2` como modelo EF (ou SQL, se preferirem SQL-first) aplicando a seção 9.7. Diagrama ER simples em `docs/`.
6. Revisar os exemplos numéricos da Fase 0 contra o modelo: cada viagem real precisa "caber" sem gambiarra.

**Fase 2 — Esqueleto (1 semana)**
7. Solution com três projetos, compose (Postgres + API + Caddy), Dockerfile, GitHub Actions rodando build + testes.
8. Auth mínima, matriz de permissões, interceptor de tenant, filtros globais, `xmin`, interceptor de auditoria, ProblemDetails, Serilog, health check.
9. Testes de integração de tenant e permissão passando antes de qualquer tela.

**Fase 3 — Fluxo de lançamento (2–3 semanas) — o risco número um primeiro**
10. Clientes (com CPF, criação inline), fornecedores (com % padrão), viagem → reservas → serviços, aviso de duplicada, anexos.
11. Tela de lançamento no front com teclado e pré-preenchimento. **Medir o tempo** com a piloto lançando uma viagem de 4 portais. Ajustar antes de seguir.

**Fase 4 — Financeiro (2 semanas)**
12. Movimentos, conciliação, valor esperado, previsão de data, repasses (liberação e pagamento em lote), fechamento de período com motivo, notas fiscais.
13. Testes unitários com as três viagens reais.

**Fase 5 — Agenda, jobs, relatórios (2 semanas)**
14. Tarefas automáticas, resumo diário, validade de documentos, expurgos.
15. Dashboard, fases, comissões pendentes, ranking, teto MEI, CSV, busca global.

**Fase 6 — Auditoria, LGPD, go-live (1 semana)**
16. Timeline, log de acesso a documento, descarte de anexo, backup + restauração testada, deploy de produção, importação dos dados da planilha.

**Fase 7 — v1.1 após um mês de uso real**
17. Despesas e DRE, créditos e reembolsos, checklist de destino, metas, automações de recompra, importação.

Estimativas são ordem de grandeza para uma pessoa em tempo integral; o que não pode mudar é a ordem: domínio → modelo → esqueleto com segurança → lançamento (medido) → financeiro → resto.
