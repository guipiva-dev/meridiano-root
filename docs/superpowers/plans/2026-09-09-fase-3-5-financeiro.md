# Meridiano — Fase 3.5 — Financeiro: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execução em ondas:** segue `.claude/rules/parallel-subagent-driven-development.md` **e** o contrato `2026-09-09-fase-3-4-3-5-contrato.md` (Task 0 já commitada; propriedade de arquivos §3; congelados §4; teto de implementadores). Implementadores **não commitam**; o controlador commita uma task por vez, no repo certo, com pathspec. Agentes especialistas da tabela do CLAUDE.md não existem no harness: usar `general-purpose` e `code-reviewer` genérico.

**Goal:** o dinheiro da agência operável: conciliação com os cinco tipos de movimento (lançar, corrigir, excluir com motivo), recebimento individual e em lote atômico, encerrar divergência com motivo; repasses (valor informado, bloqueado → liberado → pago em lote por vendedor, pago preservado); despesas com recorrência idempotente (`GerarProxima`, ao pagar e no job do dia 1) e forma obrigatória ao pagar; fechamento por competência com lock, reabertura auditada com motivo, e validação de competência antiga **e** nova em toda mudança de data. Telas 14–17 do protótipo congelado + tab Financeiro da viagem completa.

**Architecture:** quatro módulos novos (`Modules/Financeiro` = movimentos + conciliação; `Modules/Repasses`; `Modules/Despesas` + job `recorrencia_despesas`; `Modules/Fechamento`) sobre os contratos transversais de 3.0/3.2 (`Guardas.CompetenciaAbertaAsync` → lock da viagem → escrita → `Rotinas.ReavaliarRepasseAsync`). **Nenhuma migration** (contrato C1). Front: `pages/financeiro/{conciliacao,repasses,despesas,fechamento}` com `KpiCard` + `DataTable`, modais de dinheiro em `components/Financeiro/`, `useMutacaoFinanceira` (422 → campo/bloco, 409, `periodo_fechado`/`motivo_obrigatorio` → pede motivo e reenvia com `X-Motivo`), tab Financeiro da viagem ganha movimentos e despesas.

**Tech Stack:** .NET 10 · Dapper · Npgsql · PostgreSQL 17 · xUnit + Testcontainers · React 19 · react-router 8 · TanStack Query 5 · Vitest · Playwright. Nenhuma dependência nova.

**Spec:** `regras-e-escopo-v2.md` §4.3 (cinco movimentos, atalho "marcar comissão recebida"), §4.4 (conciliação e divergência), §5 (repasse: valor digitado, `bloqueado → a_pagar → pago`, lote por vendedor), §6.1 (estados de repasse, período, despesa), §8 (motivo obrigatório ao excluir/editar em período fechado; fechamento congela `data_compra`, `data_movimento`, `vencimento`/`pago_em`, `pago_em` do repasse), decisões 37, 40, 43, 44, 46, 48 · plano-mestre linha 3.5 e "Contratos transversais" (Protocolo transacional, Repasse, Movimentos, Recorrência de despesa, Jobs) · `docs/design-system-contrato.md` §3 (`KpiCard`), §4.1 (laranja: "Marcar recebidas" na conciliação, "Pagar" em repasses), §4.4 (ações repetidas por item = `primary`; campo pré-preenchido editável com helper "Esperado: R$ X") · `docs/design/prototipo-v1.html` `#s-financeiro` `#s-repasses` `#s-custos` `#s-fechamento` · `docs/autorizacao-por-operacao.md` · `docs/BACKLOG.md` ("Deferidas da 3.1": Financeiro invisível ao Contador; "Deferidas da 3.3": `X-Motivo` por header).

## Global Constraints

- Tudo do contrato (§1, §3, §4, §5): branch `feat/fase-3-4-3-5`; só arquivos de que 3.5 é dona; `Endpoints.cs`, `Guardas.cs`, `Rotinas.cs`, `ViagemLeitura.cs`, `PostgresFixture.cs`, `rotasModulos.tsx`, `status.ts`, `datas.ts`, `http.ts`, `ViagemPage.tsx`, `useViagem.ts` **não** são editados; rotas só em `pages/financeiro/*/rotas.tsx`; barrel `components/financeiro.ts`; `navegacao.ts` é de 3.5 (C7).
- Backend: `TreatWarningsAsErrors=true`; `dotnet format` limpo; ≤ ~350 linhas por arquivo. Toda query em `DbSessao`, filtra `agencia_id` e `excluido_em is null`. **Ordem de locks** em toda escrita: `Guardas.CompetenciaAbertaAsync` (cada competência envolvida, antiga **e** nova, em ordem crescente) → `Guardas.TravarViagemAsync`/`TravarViagemDaReservaAsync` (várias viagens: ordem de `id`) → escrita → `Rotinas.ReavaliarRepasseAsync` (quando movimento/conciliação muda) → `Guardas.TocarViagemAsync` **só** quando o campo está no formulário da viagem (`repasse.valor`; ruling 3.3: movimento, divergência e despesa **não** renovam o `xmin`). `podeEditarFechado = u.Pode(FinanceiroEditarPeriodoFechado)`, motivo = `ctx.Motivo` (header `X-Motivo`, C2).
- Erros: `RegraDeNegocioException` → 422; `ConflitoConcorrenciaException` → 409 (`xmin` de movimento/despesa/repasse como `versao`); gates no serviço → `SemPermissaoException` (403). Dinheiro `decimal` 2 casas; `valor` de movimento é **enviado positivo** e gravado com o sinal do tipo (`movimento_sinal`).
- Leitura do financeiro (GETs) aceita `FinanceiroMovimentar` **ou** `FinanceiroConciliar` **ou** `FinanceiroVerDre` (C7: Contador lê); nunca `ViagemVerProprias` (vendedor externo só vê **os próprios repasses**, spec §7.1). Valores sempre presentes nesses DTOs (todos os perfis que entram têm `ReservaVerValores`); `GET /viagens/{id}/movimentos` segue a visibilidade da viagem **e** exige `ReservaVerValores`.
- Listas paginadas (`pagina`, `tamanho ≤ 100`, `total`); arrays nunca `null`; competência sempre `yyyy-MM` (422 `competencia_invalida`).
- Front: CSS Modules + `tokens.css`; sem hex/`font-size`/`@media` fora dos breakpoints; só lucide; ≤ 350 linhas/arquivo; lint/typecheck/test/build verdes; `pode()` só esconde. `business` (laranja) **só** em "Marcar recebidas" (conciliação) e "Pagar R$ X" é `primary` por vendedor (§4.1/§4.4); "+ Nova despesa" = `primary` (o protótipo usa laranja; o contrato lista onde laranja entra e Despesas não está). Toda ação de dinheiro passa por modal de decisão com **data** (e forma quando aplicável; decisão 40). Modal destrutivo (excluir movimento/despesa) com motivo quando exigido.
- Commits Conventional Commits em inglês com rodapé de atribuição da sessão.

---

## Rulings desta fase

| # | Decisão | Motivo |
|---|---|---|
| R1 | **Movimento:** `POST /movimentos` (5 tipos), `PUT` (valor, data, forma, observação; `versao`), `DELETE` soft **sempre com motivo** (`X-Motivo` → `ctx.Motivo`; ausente → 422 `motivo_obrigatorio`). Lock: competência de `data_movimento` (no PUT: antiga e nova) → viagem da reserva (sem conferir `versao` da viagem, sem renovar `xmin`) → escrita → `ReavaliarRepasseAsync`. Reserva cancelada aceita `estorno_operadora`/`reembolso_cliente`; recebimento em cancelada sem `comissao_mantida` é permitido (aviso é do front). | Spec §4.3/§8; contrato "Movimentos"; ruling 3.3 sobre filhos operacionais. |
| R2 | **"Marcar comissão recebida"** (individual) = `POST /movimentos { tipo recebimento_operadora, valor = saldo }` pelo front (sem endpoint próprio). **Lote** = `POST /reservas/receber-lote { reservaIds, dataMovimento, formaPagamento }`: só reservas com `esperado > 0`, `recebido = 0` e não encerradas (decisão 48), senão 422 `lote_invalido` listando ids; tudo ou nada; um movimento por reserva com `valor = esperado`. | Spec §4.3 (atalho) e decisão 48. |
| R3 | **Divergência:** `POST /reservas/{id}/encerrar-divergencia { motivo }` → `conciliacao_encerrada = true, divergencia_motivo`; só reserva aguardando (`esperado > 0`, não encerrada, `recebido < esperado`), senão 422 `divergencia_invalida`; competência = `data_compra` (spec §8 congela reserva pela compra); reavalia repasse; **não** renova `xmin`. Reabrir conciliação **não entra** (BACKLOG). | Spec §4.4. |
| R4 | **Conciliação** `GET /conciliacao?aba&fornecedorId&previsto&mes&pagina`: `pendentes` (aguardando), `atrasadas` (aguardando e `prevista < hoje`), `recebidas` (reservas com `recebimento_operadora` no `mes`, default mês atual), `divergencias` (encerradas). `contadores` + `kpis` na mesma resposta. Situação da linha = mesmo `case` de `SituacaoComissao` (3.3) + `diasAtraso`. | Protótipo `#s-financeiro`. |
| R5 | **Repasses** `GET /repasses[?pagos=yyyy-MM]`: sem `pagos` → `bloqueado`/`a_pagar` agrupados por vendedor + `kpis`; com `pagos` → histórico do mês (`pago_em`). Vendedor externo: `apenasUsuario = usuario_id` (vê o próprio valor, spec §7.1); Agente → 403. `PUT /repasses/{id}/valor` (`RepassePagar`; pago → 422 `repasse_pago`; **renova `xmin` da viagem** — `repasseValor` está no formulário). `POST /repasses/pagar-lote { repasseIds, pagoEm, observacao }`: todos `a_pagar` com `valor` (senão `repasse_nao_liberado`/`repasse_sem_valor`), `pagoEm ≤ hoje`, competência de `pagoEm`, viagens travadas em ordem de `id`, tudo ou nada; pago fica como está em reavaliações (já garantido por `ReavaliarRepasseAsync`). "Ver extrato" do protótipo → BACKLOG. | Spec §5, decisão 40; `ux_repasse_ativo`. |
| R6 | **Despesas:** CRUD + `POST /despesas/{id}/pagar { pagoEm, formaPagamento, versao }`. `pago = true` exige `pago_em` + `forma_pagamento` (constraint + 422 `pagamento_incompleto`). Competências: criar → `vencimento` (+ `pago_em` se pago); editar → `vencimento`/`pago_em` antigos **e** novos; excluir → `vencimento` (+ `pago_em`); pagar → `vencimento` e `pago_em`. `viagem_id` → `ReferenciaAsync(Viagem)` sem lock da viagem (não afeta repasse; `vw_resultado_viagem` lê direto). Situação derivada: `paga` · `vencida` (a pagar e `vencimento < hoje`) · `a_pagar`. | Spec decisões 37/40/46, §6.1. |
| R7 | **Recorrência:** `DespesasService.GerarProximaAsync(s, agenciaId, origemId, usuarioId?)` (static, dentro da transação de quem chama): origem `recorrente`, calcula `Recorrencia.ProximoVencimento(vencimento)` = mês+1 com `least(dia, último dia)` (drift aceito: 31/01 → 28/02 → 28/03; ponytail), respeita `recorrencia_ate`, `insert … on conflict (recorrencia_origem_id) where recorrencia_origem_id is not null do nothing returning id` (idempotente por `ux_despesa_sucessora`). Chamada por `pagar` (e por `POST` com `pago = true`) e pelo job `recorrencia_despesas` (dia 1): candidatas = recorrentes sem sucessora com `vencimento < date_trunc('month', current_date)` — **uma** sucessora por origem por execução (cadeias atrasadas alcançam o presente em execuções seguintes; ponytail). Sucessora excluída não renasce (índice sem filtro de `excluido_em`, 0012). | Contrato "Recorrência de despesa"; decisão 44. |
| R8 | **Fechamento:** `GET /periodos?ano` (meses até o atual), `GET /periodos/{m}/pendentes`, `POST /periodos/{m}/fechar` (`FinanceiroFecharPeriodo`; mês corrente ou futuro → 422 `periodo_em_andamento`; já fechado → `periodo_ja_fechado`), `POST /periodos/{m}/reabrir` (`FinanceiroEditarPeriodoFechado` + `X-Motivo` senão `motivo_obrigatorio`; aberto → `periodo_aberto`) = **`delete` da linha** (trigger `aud_fechamento` grava `DELETE` com `app.motivo`). Ambos sob `Guardas.TravarCompetenciaAsync`. Status do mês: `fechado` · `pendencias` (aberto com comissão atrasada de reserva comprada no mês) · `aberto`. | Spec §8, decisão 43; 0012 deu `id` + auditoria a `fechamento_periodo`. |
| R9 | **Motivo no front:** `useMutacaoFinanceira` trata 422 `motivo_obrigatorio` (Dono/Financeiro escrevendo em período fechado, ou exclusão de movimento) abrindo o campo "Motivo" no próprio modal e reenviando com `X-Motivo`; 422 `periodo_fechado` (sem permissão) vira bloco "Período fechado — peça ao Dono/Financeiro". | C2; spec §8. |
| R10 | **Tab Financeiro da viagem** (arquivo de 3.5): faixa + "Comissões a receber" ganham botão "Receber" por reserva (`financeiro.movimentar`); blocos novos "Movimentos" (`GET /viagens/{id}/movimentos`, lançar/editar/excluir) e "Despesas da viagem" (`GET /despesas?viagemId=`, criar/editar/pagar). Após mutação: `invalidateQueries(chaves.viagem(id))` + queries próprias (o `ViagemDto` é recarregado — `resumo.receitaRecebida` e `repasse.status` vêm da view). | `ViagemPage`/`useViagem` congelados: a tab se vira com `useAuth` e `useQueryClient`. |
| R11 | **Contador** (C7): `navegacao.ts` Financeiro aceita `financeiro.ver_dre`; páginas escondem escrita por `pode()`; backend aceita `FinanceiroVerDre` nos GETs. Sidebar badge de "comissões atrasadas" (contrato §4.2) → 3.6. | Deferida da 3.1. |
| R12 | **Seleção de viagem** na despesa (opcional) = combobox sobre `GET /busca?q` (`buscaApi`, congelado, importável) mostrando só o grupo `viagens`; na tab Financeiro da viagem o campo vem fixo e escondido. | Reuso; sem endpoint novo. |

## Rulings de execução (decididos durante as ondas, 2026-09-09/10)

| # | Decisão | Motivo |
|---|---|---|
| E1 | Aba/contador **`recebidas`** = reservas **conciliadas** (não encerradas) com `recebimento_operadora` no mês; `kpis.recebidoMes` usa o `mes` do filtro (default mês atual). | A letra do brief ("existe movimento no mês") contradiz o cenário do próprio brief. Custo: recebimento parcial do mês aparece em Pendentes, não em Recebidas; o tile muda com o seletor de mês. |
| E2 | **Ordem de locks supersedida** (regra transversal, vale para T1/T2/T4): travar as viagens logo após o advisory de competência e **reler a elegibilidade sob o lock**; ids de viagem ordenados pelo SQL (`order by viagem_id`), nunca por `Guid` em C#. | TOCTOU no lote e na divergência; a ordem de `Guid` em C# não é a ordem de `uuid` do Postgres. |
| E3 | Dinheiro vindo de formulário é **arredondado** (2 casas, `AwayFromZero`) **antes** de validar. | `valor: 0.001` passava do `<= 0`, virava `0.00` no insert e estourava `movimento_sinal` → 500. |
| E4 | **Contador recebe 403 em `GET /repasses`** (o brief dizia 200). | `Permissoes.cs` é congelado (C13) e `ContadorSet` não tem `RepasseVerTodos`. Custo: Contador sem visão de repasses até 3.6 (BACKLOG). |
| E5 | KPIs de despesas falam do **universo do mês** (`mes` + `viagemId` + `soVinculadas`), ignorando `categoria`/`situacao`; a lista e o `Total` usam o recorte completo. | Cartão que muda com filtro secundário mente sobre o mês. Uma ida ao banco (`count(*) filter`). |
| E6 | Subtítulo de Despesas usa **"R$ X a pagar"**, não "{n} a pagar". | `vencidas + vencemAte7Dias` não é a contagem de "a pagar" e o DTO não tem `aPagarQtd`. |
| E7 | `rotasModulos.test.tsx` (congelado de T0) recebe 1 linha em T6: heading "Conciliação" → "Comissões a receber". | Título real da página; custo nenhum. |

---

## Ondas (3.5)

| Onda | Tasks | Motivo |
|---|---|---|
| 1 | T1 (backend movimentos + conciliação) · T2 (backend repasses) · T3 (backend despesas + domínio + job) · T5 (front api + hook + modais) | esqueletos/registro em T0; pastas disjuntas (`Jobs/**` só em T3) |
| 2 | T4 (backend fechamento — usa `ConciliacaoService`/`ConciliacaoItemDto` de T1) · T6 (conciliação page + `navegacao.ts`) · T7 (repasses page) · T8 (despesas page) · T9 (fechamento page) · T10 (tab Financeiro da viagem) | usam T5; pastas/rotas próprias; T9 só depende de T4 em runtime |
| 3 | T11 (E2E) | precisa de tudo |
| 4 | T12 (docs, root) — **serial com o fechamento de 3.4** (contrato §1.8) | fechamento |

Lembrete do contrato: teto de 6 implementadores, 4 no backend (onda 1 tem 3 backend + 1 front; combinar com a onda de 3.4 em curso).

---

## Contrato de API (fonte única para backend e front)

```
GET    /api/v1/conciliacao?aba&fornecedorId&previsto&mes&pagina&tamanho     → 200 ConciliacaoDto
GET    /api/v1/viagens/{id}/movimentos                                       → 200 MovimentoDto[]
POST   /api/v1/movimentos                MovimentoRequest                    → 201 MovimentoDto
PUT    /api/v1/movimentos/{id}           MovimentoRequest (+versao)          → 200 MovimentoDto | 409
DELETE /api/v1/movimentos/{id}           (header X-Motivo obrigatório)       → 204
POST   /api/v1/reservas/{id}/encerrar-divergencia  { motivo }               → 200 ConciliacaoItemDto
POST   /api/v1/reservas/receber-lote     ReceberLoteRequest                  → 200 { movimentos: MovimentoDto[] }
GET    /api/v1/repasses?pagos                                                → 200 RepassesDto
PUT    /api/v1/repasses/{id}/valor       { valor, versao }                   → 200 RepasseItemDto | 409
POST   /api/v1/repasses/pagar-lote       PagarLoteRequest                    → 200 { pagos: RepasseItemDto[] }
GET    /api/v1/despesas?mes&categoria&situacao&viagemId&soVinculadas&pagina&tamanho → 200 DespesasDto
POST   /api/v1/despesas                  DespesaRequest                      → 201 DespesaCriadaDto
PUT    /api/v1/despesas/{id}             DespesaRequest (+versao)            → 200 DespesaDto | 409
DELETE /api/v1/despesas/{id}             (X-Motivo se período fechado)       → 204
POST   /api/v1/despesas/{id}/pagar       PagarDespesaRequest                 → 200 DespesaCriadaDto | 409
GET    /api/v1/periodos?ano                                                  → 200 PeriodoDto[]
GET    /api/v1/periodos/{yyyy-MM}/pendentes                                  → 200 ConciliacaoItemDto[]
POST   /api/v1/periodos/{yyyy-MM}/fechar                                     → 200 PeriodoDto
POST   /api/v1/periodos/{yyyy-MM}/reabrir (header X-Motivo obrigatório)      → 200 PeriodoDto
```

Permissões (acrescentar em `docs/autorizacao-por-operacao.md` na T12):

| Operação | Permissão | Observação |
|---|---|---|
| `GET /conciliacao`, `GET /despesas`, `GET /periodos*` | `FinanceiroMovimentar` ou `FinanceiroConciliar` ou `FinanceiroVerDre` | Contador lê (C7) |
| `GET /viagens/{id}/movimentos` | visibilidade da viagem (`ViagemVer`/`ViagemVerProprias`) **e** `ReservaVerValores` | externo (sem valores) → 403 |
| `POST/PUT/DELETE /movimentos*` | `FinanceiroMovimentar` | `DELETE` exige `X-Motivo` |
| `encerrar-divergencia`, `receber-lote` | `FinanceiroConciliar` | |
| `GET /repasses` | `RepasseVerTodos`; sem ela, `ViagemVerProprias` → só `usuario_id = usuario` | Agente → 403 |
| `PUT /repasses/{id}/valor`, `pagar-lote` | `RepassePagar` | |
| `POST/PUT/DELETE /despesas*`, `pagar` | `FinanceiroMovimentar` | |
| `POST /periodos/{m}/fechar` | `FinanceiroFecharPeriodo` | |
| `POST /periodos/{m}/reabrir` | `FinanceiroEditarPeriodoFechado` + `X-Motivo` | |

```csharp
// ---- Modules/Financeiro/FinanceiroDtos.cs (T1) ----
public sealed record MovimentoRequest(Guid ReservaId, string Tipo, decimal Valor, DateOnly DataMovimento, string? FormaPagamento, string? Observacao, string? Versao);
public sealed record MovimentoDto(Guid Id, string Versao, Guid ReservaId, Guid ViagemId, string CodigoViagem, string? Localizador, string FornecedorNome, string Tipo, decimal Valor,
    DateOnly DataMovimento, string? FormaPagamento, string? Observacao, string? CriadoPorNome, DateTimeOffset CriadoEm);
public sealed record ReceberLoteRequest(Guid[] ReservaIds, DateOnly DataMovimento, string? FormaPagamento);
public sealed record EncerrarDivergenciaRequest(string Motivo);
public sealed record ConciliacaoItemDto(Guid ReservaId, Guid ViagemId, string Codigo, string? Titular, string Destino, string? Localizador, Guid FornecedorId, string FornecedorNome,
    DateOnly DataCompra, DateOnly? DataPrevistaComissao, string SituacaoComissao, int? DiasAtraso, decimal Esperado, decimal Recebido, decimal Saldo, bool ConciliacaoEncerrada, string? DivergenciaMotivo, DateOnly? UltimoRecebimentoEm, bool ElegivelLote);
public sealed record KpiValorDto(decimal Valor, int Reservas, int? Extra);     // Extra: operadoras (aReceber) · piorDias (atrasadas) · null (vencemSemana)
public sealed record KpiRecebidoDto(decimal Valor, decimal? VariacaoPercentual);
public sealed record KpisConciliacaoDto(KpiValorDto AReceber, KpiValorDto Atrasadas, KpiValorDto VencemSemana, KpiRecebidoDto RecebidoMes);
public sealed record ContadoresConciliacaoDto(int Pendentes, int Atrasadas, int RecebidasMes, int Divergencias);
public sealed record ConciliacaoDto(ConciliacaoItemDto[] Itens, int Total, int Pagina, int Tamanho, string Mes, ContadoresConciliacaoDto Contadores, KpisConciliacaoDto Kpis);
public sealed record FiltroConciliacao(string? Aba, Guid? FornecedorId, string? Previsto, string? Mes, int Pagina = 1, int Tamanho = 25);
// Tipo ∈ recebimento_operadora | recebimento_cliente | pagamento_fornecedor | estorno_operadora | reembolso_cliente
// FormaPagamento ∈ pix | boleto | cartao | transferencia | dinheiro | null (lista fechada; coluna é text livre)

// ---- Modules/Repasses/RepasseDtos.cs (T2) ----
public sealed record RepasseItemDto(Guid Id, string Versao, Guid ViagemId, string Codigo, string? Titular, string Destino, Guid UsuarioId, decimal? Valor, string Status,
    DateTimeOffset? LiberadoEm, DateOnly? PagoEm, string? Observacao, int Aguardando, DateOnly? UltimoRecebimentoEm);
public sealed record VendedorRepassesDto(Guid UsuarioId, string Nome, int ViagensAno, decimal APagarValor, int APagarViagens, RepasseItemDto[] Itens);
public sealed record KpisRepassesDto(decimal APagarValor, int APagarVendedores, int APagarViagens, decimal BloqueadoValor, int BloqueadoViagens, int SemValor);
public sealed record RepassesDto(KpisRepassesDto Kpis, VendedorRepassesDto[] Vendedores, string? Pagos, int Ano);
public sealed record ValorRepasseRequest(decimal? Valor, string Versao);
public sealed record PagarLoteRequest(Guid[] RepasseIds, DateOnly PagoEm, string? Observacao);
public sealed record RepassesPagosDto(RepasseItemDto[] Pagos);

// ---- Modules/Despesas/DespesaDtos.cs (T3) ----
public sealed record DespesaRequest(string Descricao, string Categoria, decimal Valor, DateOnly Vencimento, bool Pago, DateOnly? PagoEm, string? FormaPagamento,
    bool Recorrente, DateOnly? RecorrenciaAte, Guid? ViagemId, Guid? FornecedorId, string? Observacao, string? Versao);
public sealed record DespesaDto(Guid Id, string Versao, string Descricao, string Categoria, decimal Valor, DateOnly Vencimento, bool Pago, DateOnly? PagoEm, string? FormaPagamento,
    bool Recorrente, DateOnly? RecorrenciaAte, Guid? RecorrenciaOrigemId, Guid? ViagemId, string? CodigoViagem, string? TituloViagem, Guid? FornecedorId, string? FornecedorNome, string? Observacao, string Situacao);
public sealed record DespesaCriadaDto(DespesaDto Despesa, DespesaDto? Proxima);
public sealed record PagarDespesaRequest(DateOnly PagoEm, string FormaPagamento, string Versao);
public sealed record KpisDespesasDto(decimal LancadoValor, int LancadoQtd, decimal APagarValor, int Vencidas, int VencemAte7Dias, decimal FixosValor, decimal LigadasViagemValor, int LigadasViagemQtd);
public sealed record DespesasDto(DespesaDto[] Itens, int Total, int Pagina, int Tamanho, string? Mes, KpisDespesasDto Kpis);
public sealed record FiltroDespesas(string? Mes, string? Categoria, string? Situacao, Guid? ViagemId, bool SoVinculadas = false, int Pagina = 1, int Tamanho = 25);
// Situacao ∈ a_pagar | vencida | paga · Categoria ∈ fixo | imposto | operacional | marketing | outro · FormaPagamento ∈ pix | boleto | cartao | transferencia | dinheiro

// ---- Modules/Fechamento/FechamentoDtos.cs (T4) ----
public sealed record PeriodoDto(string Competencia, string Status, int Reservas, int ComissoesPendentes, decimal ComissoesPendentesValor, int Despesas, decimal ReceitaPrevista, decimal ReceitaRecebida,
    DateTimeOffset? FechadoEm, string? FechadoPorNome, bool Corrente);
// Status ∈ aberto | pendencias | fechado

// ---- Meridiano.Domain/Financeiro/Recorrencia.cs (T3) ----
public static class Recorrencia { public static DateOnly ProximoVencimento(DateOnly vencimento); }   // mês+1, dia = min(dia, último dia do mês)
```

Códigos 422 novos: `tipo_invalido`, `valor_invalido` (existe), `forma_invalida`, `data_invalida` (futuro > hoje), `motivo_obrigatorio` (existe), `periodo_fechado` (existe), `lote_vazio`, `lote_invalido`, `divergencia_invalida`, `repasse_pago` (existe), `repasse_nao_liberado`, `repasse_sem_valor`, `descricao_obrigatoria`, `categoria_invalida`, `pagamento_incompleto`, `despesa_paga`, `situacao_invalida`, `competencia_invalida`, `periodo_em_andamento`, `periodo_ja_fechado`, `periodo_aberto`, `aba_invalida` (existe), `previsto_invalido`, `versao_obrigatoria`.

---

### Task 1 (backend): `Modules/Financeiro` — movimentos, conciliação, lote, divergência

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Financeiro/FinanceiroDtos.cs`, `backend/src/Meridiano.Api/Modules/Financeiro/ConciliacaoSql.cs` (constantes SQL)
- Modify: `backend/src/Meridiano.Api/Modules/Financeiro/MovimentosService.cs`, `backend/src/Meridiano.Api/Modules/Financeiro/ConciliacaoService.cs`, `backend/src/Meridiano.Api/Modules/Financeiro/FinanceiroEndpoints.cs` (esqueletos de T0)
- Create: `backend/tests/Meridiano.Api.Tests/MovimentosTests.cs`, `backend/tests/Meridiano.Api.Tests/ConciliacaoTests.cs`

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class MovimentosService(DbSessaoFactory sessoes)
{
    public Task<IReadOnlyList<MovimentoDto>> DaViagemAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, CancellationToken ct);
    public Task<MovimentoDto> LancarAsync(ContextoSessao ctx, UsuarioAtual u, MovimentoRequest req, CancellationToken ct);
    public Task<MovimentoDto> CorrigirAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, MovimentoRequest req, CancellationToken ct);
    public Task ExcluirAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, CancellationToken ct);
    public Task<IReadOnlyList<MovimentoDto>> ReceberLoteAsync(ContextoSessao ctx, UsuarioAtual u, ReceberLoteRequest req, CancellationToken ct);
    public static decimal ComSinal(string tipo, decimal valorAbsoluto);   // recebimento_* → +; demais → −
}
public sealed class ConciliacaoService(DbSessaoFactory sessoes)
{
    public Task<ConciliacaoDto> ListarAsync(ContextoSessao ctx, FiltroConciliacao f, CancellationToken ct);
    public Task<ConciliacaoItemDto> EncerrarDivergenciaAsync(ContextoSessao ctx, UsuarioAtual u, Guid reservaId, string motivo, CancellationToken ct);
    public static Task<IReadOnlyList<ConciliacaoItemDto>> PendentesDaCompetenciaAsync(DbSessao s, Guid agenciaId, DateOnly competencia, CancellationToken ct);   // usado por T4
}
public static class FinanceiroEndpoints   // MapFinanceiroEndpoints
// LeituraFinanceira(u) = u.Pode(FinanceiroMovimentar) || u.Pode(FinanceiroConciliar) || u.Pode(FinanceiroVerDre) — senão 403 sem_permissao (padrão Results.Problem de ViagensEndpoints), permissao "financeiro.ver_dre"
```
  - **Validação de movimento:** `Tipo` ∉ 5 → `tipo_invalido`; `Valor <= 0` → `valor_invalido`; `FormaPagamento` fora da lista → `forma_invalida`; `DataMovimento > hoje` → `data_invalida`; `Observacao` `trim`. `ReservaId` → `select viagem_id, data_compra from reserva where id and agencia_id and excluido_em is null` → `nao_encontrado`.
  - **Lançar:** `CompetenciaAbertaAsync(DataMovimento)` → `TravarViagemDaReservaAsync(reservaId, null)` → `insert into movimento_financeiro (agencia_id, reserva_id, tipo, valor, data_movimento, forma_pagamento, observacao, criado_por) … returning id` (`valor = ComSinal`) → `ReavaliarRepasseAsync(viagemId)` → carregar DTO (`join reserva r join viagem v join fornecedor f left join usuario`) → commit.
  - **Corrigir:** `select reserva_id, tipo, data_movimento from movimento_financeiro where id and agencia_id and excluido_em is null` → `nao_encontrado`; `Versao` nula → `versao_obrigatoria`; `Tipo`/`ReservaId` diferentes do gravado → 422 `movimento_imutavel` (tipo e reserva não mudam; excluir e lançar de novo); competências `data_movimento` antiga e nova (ordem crescente, distintas) → lock viagem → `update … set valor, data_movimento, forma_pagamento, observacao where id and agencia_id and excluido_em is null and xmin::text = @versao` → 0 → 409 → reavaliar → carregar.
  - **Excluir:** `ctx.Motivo` vazio → `motivo_obrigatorio`; competência de `data_movimento` → lock → `update set excluido_em = now(), excluido_por` → reavaliar.
  - **Lote:** `ReservaIds` vazio → `lote_vazio`; > 100 → `lote_invalido`; `DataMovimento > hoje` → `data_invalida`; competência; `select r.id, r.viagem_id, f.valor_esperado_operadora, f.recebido_operadora, f.conciliacao_encerrada from reserva r join vw_reserva_financeiro f on f.reserva_id = r.id where r.id = any(@ids) and r.agencia_id and r.excluido_em is null` → faltando → `nao_encontrado`; inelegível (`esperado <= 0 or recebido <> 0 or encerrada`) → `lote_invalido` (mensagem com os ids); viagens `distinct` ordenadas → `TravarViagemAsync` cada; um `insert` por reserva com `valor = esperado`, `tipo recebimento_operadora`; reavaliar cada viagem; devolver os movimentos.
  - **Conciliação (`ConciliacaoSql`):** CTE `base` = `reserva r join viagem v join vw_reserva_financeiro f join fornecedor fo left join vw_viagem_titular t left join lateral (select max(data_movimento) as ultimo from movimento_financeiro m where m.reserva_id = r.id and m.tipo = 'recebimento_operadora' and m.excluido_em is null) u` com `r.agencia_id = @agencia and r.excluido_em is null and v.excluido_em is null and (@fornecedorId::uuid is null or r.fornecedor_id = @fornecedorId)`; colunas: `Esperado = f.valor_esperado_operadora`, `Recebido = f.recebido_operadora`, `Saldo = esperado - recebido`, `Aguardando = f.aguardando_operadora`, `DiasAtraso = case when f.aguardando_operadora and r.data_prevista_comissao < current_date then current_date - r.data_prevista_comissao end`, `SituacaoComissao` (case de 3.3), `ElegivelLote = f.aguardando_operadora and f.recebido_operadora = 0`. Abas: `pendentes → Aguardando` · `atrasadas → Aguardando and DiasAtraso > 0` · `recebidas → exists movimento recebimento_operadora com data_movimento no @mes` · `divergencias → conciliacao_encerrada`; `previsto` (só pendentes/atrasadas): `ate_hoje → prevista <= current_date` · `semana → prevista between current_date and current_date + 7` · `qualquer`/null; outro → `previsto_invalido`. Ordem: pendentes/atrasadas `prevista asc nulls last`; recebidas `ultimo desc`; divergências `data_compra desc`. `Mes` default = mês atual (`yyyy-MM`; inválido → `competencia_invalida`). Contadores = `count(*) filter` sobre `base` (recebidasMes usa o `@mes`). KPIs: `AReceber = sum(Saldo), count, count(distinct fornecedor)` sobre aguardando; `Atrasadas` idem com `DiasAtraso > 0`, `Extra = max(DiasAtraso)`; `VencemSemana` = aguardando com prevista em `[hoje, hoje+7]`; `RecebidoMes = sum(valor) from movimento_financeiro where tipo in ('recebimento_operadora','estorno_operadora') and data_movimento no mês atual`, `VariacaoPercentual = round(100 * (atual - anterior) / anterior, 1)` (null se anterior = 0).
  - **Divergência:** `motivo` vazio → `motivo_obrigatorio`; `select viagem_id, data_compra, esperado, recebido, encerrada` (join view) → `nao_encontrado`; não aguardando → `divergencia_invalida`; `CompetenciaAbertaAsync(data_compra)` → `TravarViagemAsync(viagemId, null)` → `update reserva set conciliacao_encerrada = true, divergencia_motivo = @motivo` → reavaliar → devolver o item (query da `base` filtrada por `reservaId`).
  - Rotas (`FinanceiroEndpoints`): `GET /conciliacao` (`[AsParameters] FiltroConciliacao`, gate `LeituraFinanceira`) · `GET /viagens/{id:guid}/movimentos` (gate: `SemVisibilidade` de viagem **e** `ReservaVerValores`; `apenasVendedor` como em `GET /viagens/{id}` — reutilizar `ViagensEndpoints.SemVisibilidade` (internal, mesmo assembly)) · `POST /movimentos` (`FinanceiroMovimentar`) → 201 `Location /api/v1/movimentos/{id}` · `PUT /movimentos/{id:guid}` · `DELETE /movimentos/{id:guid}` → 204 · `POST /reservas/{id:guid}/encerrar-divergencia` (`FinanceiroConciliar`) · `POST /reservas/receber-lote` (`FinanceiroConciliar`).

- [ ] **Step 1: Testes** (`MovimentosTests.cs`; cenário: dono `dono@`, financeiro `fin@`, agente `ag@`, contador `ct@`, externa `ana@` com senha e `gera_repasse`; Carlos; CVC e Decolar; viagem vendida pela externa via `InserirViagemCompletaAsync` (reserva CVC esperado 100) + `InserirRepasseAsync(valor 30)` + segunda reserva Decolar `InserirReservaAsync(valorComissao 50)`; helper `Fin(pg)` para `select recebido_operadora, conciliada from vw_reserva_financeiro`):
```csharp
[Fact] public async Task Lanca_recebimento_com_sinal_e_libera_repasse_quando_tudo_concilia()
// fin POST /movimentos { reservaId r1, tipo "recebimento_operadora", valor 100, dataMovimento hoje, formaPagamento "transferencia" } → 201 valor 100, codigoViagem, fornecedorNome "CVC"; repasse ainda bloqueado (r2 aguarda)
// POST r2 valor 50 → repasse "a_pagar" com liberado_em; GET /viagens/{id}/movimentos como fin → 2 itens ordenados por data desc, criado desc; como externa → 403 (sem ReservaVerValores); como contador → 200
[Fact] public async Task Estorno_e_reembolso_gravam_negativo_e_rebloqueiam_repasse()
// após conciliar: POST { tipo "estorno_operadora", valor 40 } → 201 valor -40; vw recebido 60; repasse volta a "bloqueado"; POST { tipo "reembolso_cliente", valor 10 } → valor -10; tipo "x" → 422 tipo_invalido; valor 0 → valor_invalido; forma "cheque" → forma_invalida; data amanhã → data_invalida; agente → 403
[Fact] public async Task Corrige_com_versao_e_competencias_e_exclui_so_com_motivo()
// PUT /movimentos/{m} { …valor 90, dataMovimento hoje-1, versao } → 200 valor 90 versao nova; versao velha → 409; tipo diferente → 422 movimento_imutavel
// InserirFechamentoAsync(mês de hoje-1): PUT movendo data para o mês fechado como fin (tem FinanceiroEditarPeriodoFechado) sem X-Motivo → 422 motivo_obrigatorio; com header X-Motivo "ajuste%20extrato" → 200 e auditoria do movimento com motivo "ajuste extrato"
// DELETE sem header → 422 motivo_obrigatorio; com X-Motivo → 204, excluido_em preenchido, repasse reavaliado (bloqueado)
[Fact] public async Task Lote_e_tudo_ou_nada_e_so_para_elegiveis()
// r1 sem recebimento, r2 já com recebimento parcial 20: POST /reservas/receber-lote { [r1, r2], dataMovimento hoje } → 422 lote_invalido (mensagem contém r2) e nenhum movimento novo; { [r1] } → 200 movimentos 1 (valor 100); repetir → 422 lote_invalido; [] → lote_vazio; reserva de outra agência → nao_encontrado; agente → 403
```
`ConciliacaoTests.cs`:
```csharp
[Fact] public async Task Abas_contadores_e_kpis()
// 4 reservas: A prevista hoje-41 (atrasada, esperado 740), B prevista hoje+3 (a receber 1600), C parcial (esperado 1180, recebido 600, prevista hoje-2), D encerrada com divergência (recebido 300 de 500), E recebida no mês atual (esperado 320 recebido 320)
// GET /conciliacao → aba pendentes: A, C, B (ordem prevista); contadores {pendentes 3, atrasadas 2, recebidasMes 1, divergencias 1}; kpis.aReceber {valor 740+1600+580, reservas 3, extra 2 operadoras}; kpis.atrasadas {valor 740+580, reservas 2, extra 41}; kpis.vencemSemana {1600, 1}; kpis.recebidoMes.valor 920 (600+320); A.diasAtraso 41, A.elegivelLote true, C.elegivelLote false
// ?aba=atrasadas → A, C; ?aba=divergencias → D com divergenciaMotivo; ?aba=recebidas → E com ultimoRecebimentoEm; ?previsto=semana → B; ?fornecedorId=cvc → só CVC; ?aba=x → 422 aba_invalida; ?mes=2026-13 → competencia_invalida
[Fact] public async Task Encerra_divergencia_com_motivo_e_libera_repasse()
// viagem com r1 recebido 60 de 100, repasse bloqueado: POST /reservas/{r1}/encerrar-divergencia { motivo "operadora não paga o resto" } → 200 conciliacaoEncerrada true, situacaoComissao "divergente"; repasse "a_pagar"; repetir → 422 divergencia_invalida; motivo "" → motivo_obrigatorio; reserva recebida (100/100) → divergencia_invalida; agente → 403; versao da viagem inalterada
[Fact] public async Task Contador_le_e_externa_nao_entra()
// contador GET /conciliacao → 200; externa → 403; POST movimentos como contador → 403
```
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar** (`MovimentosService.cs` ≤ 300; `ConciliacaoService.cs` + `ConciliacaoSql.cs`; `PendentesDaCompetenciaAsync` = `base` com `data_compra` no mês e `Aguardando`).
- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(financeiro): movimentos (5 tipos) with competencia/trip locks and repasse re-evaluation, atomic receber-lote, divergence closing, conciliation list with tabs/counters/kpis`

---

### Task 2 (backend): `Modules/Repasses`

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Repasses/RepasseDtos.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Repasses/RepassesService.cs`, `backend/src/Meridiano.Api/Modules/Repasses/RepassesEndpoints.cs` (esqueletos)
- Create: `backend/tests/Meridiano.Api.Tests/RepassesTests.cs`

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class RepassesService(DbSessaoFactory sessoes)
{
    public Task<RepassesDto> ListarAsync(ContextoSessao ctx, Guid? apenasUsuario, string? pagos, CancellationToken ct);
    public Task<RepasseItemDto> DefinirValorAsync(ContextoSessao ctx, Guid id, decimal? valor, string versao, CancellationToken ct);
    public Task<IReadOnlyList<RepasseItemDto>> PagarLoteAsync(ContextoSessao ctx, UsuarioAtual u, PagarLoteRequest req, CancellationToken ct);
}
```
  - **Listar:** `pagos` nulo → `status in ('bloqueado','a_pagar')`; `pagos = yyyy-MM` → `status = 'pago' and pago_em no mês` (inválido → `competencia_invalida`). Item: `repasse rp join viagem v join usuario u left join vw_viagem_titular t left join lateral (count aguardando, max(data_movimento) recebimento) `; `Aguardando = count(*) from vw_reserva_financeiro f where f.viagem_id = v.id and f.aguardando_operadora`. Agrupar por vendedor em C# (`order by u.nome, v.data_ida desc nulls last`); `ViagensAno = count(viagem where vendedor_id = u and extract(year from coalesce(data_ida, criado_em)) = ano)`; `APagarValor = sum(valor) filter (status = 'a_pagar' and valor is not null)`. KPIs sobre a agência (respeitando `apenasUsuario`): `APagar` (valor, vendedores distintos, viagens), `Bloqueado` (valor de `coalesce(valor,0)`, viagens), `SemValor` (não pagos com `valor is null`).
  - **Valor:** `valor < 0` → `valor_invalido`; `select viagem_id, status from repasse where id and agencia_id and excluido_em is null` → `nao_encontrado`; `pago` → `repasse_pago`; `TravarViagemAsync(viagemId, null)`; `update repasse set valor where id and xmin::text = @versao` → 0 → 409; `TocarViagemAsync`; devolver item.
  - **Pagar lote:** ids vazio → `lote_vazio`; `PagoEm > hoje` → `data_invalida`; `CompetenciaAbertaAsync(PagoEm)`; `select id, viagem_id, status, valor from repasse where id = any(@ids) and agencia_id and excluido_em is null` (faltando → `nao_encontrado`; `status <> 'a_pagar'` → `repasse_nao_liberado`; `valor is null` → `repasse_sem_valor`); viagens distintas ordenadas → `TravarViagemAsync`; `update repasse set status = 'pago', pago_em, observacao where id = any(@ids)`; `TocarViagemAsync` cada (status do repasse aparece no formulário via `repasse.status`); devolver itens.
  - Rotas (`/repasses`): `GET /` (gate: `RepasseVerTodos` → `apenasUsuario = null`; senão `ViagemVerProprias` → `u.UsuarioId`; senão 403) · `PUT /{id:guid}/valor` (`RepassePagar`) · `POST /pagar-lote` (`RepassePagar`).

- [ ] **Step 1: Testes** (cenário: dono, financeiro, agente, externa `ana@` (gera_repasse) e externo `marcos@`; viagens: V1 Ana liberada (todas conciliadas, valor 250), V2 Ana bloqueada (valor 300, 2 reservas aguardando), V3 Ana sem valor (bloqueada), V4 Marcos liberada (valor 180); montar com fixture + `InserirMovimentoAsync` e `InserirRepasseAsync`; **atenção**: `InserirRepasseAsync` grava `status` direto; para "liberada" gravar `a_pagar` com `liberado_em`):
```csharp
[Fact] public async Task Lista_agrupa_por_vendedor_com_kpis_e_externa_ve_so_o_seu()
// fin GET /repasses → kpis {aPagarValor 430, aPagarVendedores 2, aPagarViagens 2, bloqueadoValor 300, bloqueadoViagens 2, semValor 1}; vendedores[Ana].itens 3 (V1 status a_pagar aguardando 0; V2 bloqueado aguardando 2; V3 valor null), aPagarValor 250; Marcos 1 item
// externa Ana GET → só Ana, kpis dela (aPagarValor 250, aPagarVendedores 1); agente → 403; contador (RepasseVerTodos) → 200
[Fact] public async Task Define_valor_com_versao_renova_viagem_e_recusa_pago()
// dono PUT /repasses/{V3}/valor { valor 120, versao } → 200 valor 120; versão da viagem (GET /viagens/{V3}) mudou; versao velha → 409; valor -1 → 422 valor_invalido; pagar V1 depois PUT valor → 422 repasse_pago; financeiro (RepassePagar) → 200; externa → 403
[Fact] public async Task Paga_lote_tudo_ou_nada_com_data_e_competencia()
// POST /repasses/pagar-lote { [V1, V2], pagoEm hoje } → 422 repasse_nao_liberado, nada pago; { [V1, V4], pagoEm hoje, observacao "PIX ref. março" } → 200 pagos 2 (status pago, pagoEm, observacao); GET /repasses?pagos=<mês atual> → 2 itens; sem pagos → não aparecem; pagoEm amanhã → data_invalida; [V3 com valor null e a_pagar forçado] → repasse_sem_valor; InserirFechamentoAsync(mês passado) + pagoEm no mês passado como financeiro sem X-Motivo → motivo_obrigatorio
[Fact] public async Task Pago_nao_muda_em_reavaliacao()
// V4 paga; InserirMovimentoAsync estorno na reserva de V4 (via POST /movimentos como fin) → repasse continua pago com o mesmo valor
```
- [ ] **Step 2–4:** RED → implementar → testes, format. Commit sugerido: `feat(repasses): per-seller grouping with kpis and own-only view for external sellers, value entry bumping trip version, atomic batch payment`

---

### Task 3 (backend): `Modules/Despesas`, `Recorrencia`, job `recorrencia_despesas`

**Files:**
- Create: `backend/src/Meridiano.Domain/Financeiro/Recorrencia.cs`, `backend/tests/Meridiano.Domain.Tests/RecorrenciaTests.cs`
- Create: `backend/src/Meridiano.Api/Modules/Despesas/DespesaDtos.cs`, `backend/src/Meridiano.Api/Modules/Despesas/DespesasSql.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Despesas/DespesasService.cs`, `backend/src/Meridiano.Api/Modules/Despesas/DespesasEndpoints.cs` (esqueletos)
- Create: `backend/src/Meridiano.Api/Jobs/RecorrenciaDespesasJob.cs`; Modify: `backend/src/Meridiano.Api/Jobs/JobsExtensions.cs` (+ `AddScoped<IJob, RecorrenciaDespesasJob>()`)
- Create: `backend/tests/Meridiano.Api.Tests/DespesasTests.cs`; Modify: `backend/tests/Meridiano.Api.Tests/JobsTests.cs` (+1)

**Depends-on:** T0

**Interfaces:**
```csharp
public static class Recorrencia
{
    public static DateOnly ProximoVencimento(DateOnly vencimento)
    { var m = new DateOnly(vencimento.Year, vencimento.Month, 1).AddMonths(1); return new DateOnly(m.Year, m.Month, Math.Min(vencimento.Day, DateTime.DaysInMonth(m.Year, m.Month))); }
}
public sealed class DespesasService(DbSessaoFactory sessoes)
{
    public Task<DespesasDto> ListarAsync(ContextoSessao ctx, FiltroDespesas f, CancellationToken ct);
    public Task<DespesaCriadaDto> CriarAsync(ContextoSessao ctx, UsuarioAtual u, DespesaRequest req, CancellationToken ct);
    public Task<DespesaDto> AtualizarAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, DespesaRequest req, CancellationToken ct);
    public Task ExcluirAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, CancellationToken ct);
    public Task<DespesaCriadaDto> PagarAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, PagarDespesaRequest req, CancellationToken ct);
    // dentro da transação do chamador; devolve null quando já existe sucessora ou passou de recorrencia_ate
    public static Task<Guid?> GerarProximaAsync(DbSessao s, Guid agenciaId, Guid origemId, Guid? usuarioId, CancellationToken ct);
}
public sealed class RecorrenciaDespesasJob(DbSessaoFactory sessoes) : IJob   // Nome "recorrencia_despesas", PorAgencia true
```
  - **Validação:** `Descricao` vazia → `descricao_obrigatoria`; `Categoria` ∉ 5 → `categoria_invalida`; `Valor <= 0` → `valor_invalido`; `FormaPagamento` ∉ lista (quando vem) → `forma_invalida`; `Pago && (PagoEm is null || FormaPagamento is null)` → `pagamento_incompleto`; `!Pago` → gravar `pago_em = null` (forma pode ficar); `RecorrenciaAte < Vencimento` → `data_invalida`; `!Recorrente` → `recorrencia_ate = null`; `ViagemId` → `ReferenciaAsync(Viagem)`; `FornecedorId` → `ReferenciaAsync(Fornecedor)` (sem `exigirAtivo`).
  - **Criar:** competências (`Vencimento`, `PagoEm` se pago; distintas, crescentes) → `insert … returning id`; se `Pago && Recorrente` → `GerarProximaAsync`; devolver `{ despesa, proxima }`.
  - **Atualizar:** `Versao` obrigatória; `select vencimento, pago, pago_em` atual → `nao_encontrado`; competências: `{vencimento atual, vencimento novo, pago_em atual, pago_em novo}` não nulos, distintas, crescentes; `update … where id and agencia_id and excluido_em is null and xmin::text = @versao` (edita só esta ocorrência, decisão 44: **não** propaga à sucessora); 0 → 409. Passar de não pago para pago pelo PUT também gera próxima quando recorrente.
  - **Excluir:** competências de `vencimento` (+ `pago_em`); soft.
  - **Pagar:** `Versao`; já paga → `despesa_paga`; `FormaPagamento` ∉ lista → `forma_invalida`; `PagoEm > hoje` → `data_invalida`; competências `vencimento` e `PagoEm`; `update set pago = true, pago_em, forma_pagamento where … xmin::text = @versao` → 0 → 409; recorrente → `GerarProximaAsync`.
  - **`GerarProximaAsync`:** `select descricao, categoria, valor, vencimento, forma_pagamento, recorrencia_ate, viagem_id, fornecedor_id, recorrente from despesa where id and agencia_id and excluido_em is null` → não recorrente → null; `proximo = Recorrencia.ProximoVencimento(vencimento)`; `recorrencia_ate < proximo` → null; `insert into despesa (agencia_id, descricao, categoria, valor, vencimento, recorrente, recorrencia_ate, recorrencia_origem_id, viagem_id, fornecedor_id, forma_pagamento, criado_por) values (…) on conflict (recorrencia_origem_id) where recorrencia_origem_id is not null do nothing returning id` (nulo = já existia). **Não** valida competência da sucessora (é sempre um mês à frente; se cair em mês fechado — improvável — a exceção vem do trigger? Não há trigger; deixamos passar e registramos no BACKLOG).
  - **Listar:** `Mes` (`yyyy-MM`; null **só** quando `ViagemId` vem, senão default mês atual) filtra `vencimento`; `Categoria`; `Situacao ∈ a_pagar | vencida | paga` (`situacao_invalida`); `ViagemId`; `SoVinculadas → viagem_id is not null`; ordem `vencimento asc, criado_em`; `Situacao` calculada no SQL; `TituloViagem = titular || ' · ' || destino`. KPIs do mês (ignorando paginação; com `ViagemId` calculam sobre o mesmo filtro): `Lancado` (sum, count), `APagar` (sum não pagas, `Vencidas` = não pagas com `vencimento < hoje`, `VencemAte7Dias` = não pagas com vencimento em `[hoje, hoje+7]`), `Fixos` (sum categoria fixo), `LigadasViagem` (sum/count `viagem_id is not null`).
  - **Job:** `ExecutarAsync(agenciaId)`: `await using var s = await sessoes.AbrirAsync(new ContextoSessao(agenciaId.Value, null, "job recorrencia_despesas"), ct)`; `select id from despesa d where agencia_id and recorrente and excluido_em is null and vencimento < date_trunc('month', current_date) and (recorrencia_ate is null or vencimento < recorrencia_ate) and not exists (select 1 from despesa s where s.recorrencia_origem_id = d.id) order by vencimento`; para cada → `GerarProximaAsync(s, agenciaId, id, null, ct)`; `ConfirmarAsync`.
  - Rotas (`/despesas`): `GET /` (gate `LeituraFinanceira` — copiar o helper de T1? **Não** (arquivo de T1). Definir `static bool LeFinanceiro(UsuarioAtual u)` local em `DespesasEndpoints` com a mesma regra; T4 idem) · `POST /` → 201 `Location /api/v1/despesas/{id}` · `PUT /{id:guid}` · `DELETE /{id:guid}` → 204 · `POST /{id:guid}/pagar` — escritas `FinanceiroMovimentar`.

- [ ] **Step 1: Testes**

`RecorrenciaTests.cs` (domínio): `2026-01-31 → 2026-02-28`; `2026-01-15 → 2026-02-15`; `2026-12-20 → 2027-01-20`; `2024-01-30 → 2024-02-29` (bissexto).

`DespesasTests.cs`:
```csharp
[Fact] public async Task Cria_lista_por_mes_com_situacao_e_kpis()
// fin POST /despesas { descricao "DAS — MEI", categoria "imposto", valor 75.90, vencimento dia 20 do mês, recorrente true } → 201 despesa.situacao "a_pagar", proxima null
// + "Anúncios" marketing 955.10 vencimento hoje-2 (vencida) + "Motorista" operacional 180 viagemId (paga hoje, pix) + despesa do mês passado
// GET /despesas (mês atual) → 3 itens ordenados por vencimento; kpis {lancadoValor 1211.00, lancadoQtd 3, aPagarValor 1031.00, vencidas 1, fixosValor 0, ligadasViagemValor 180, ligadasViagemQtd 1}; ?situacao=paga → 1; ?categoria=marketing → 1; ?soVinculadas=true → 1; ?viagemId=<v> (sem mes) → 1 com codigoViagem/tituloViagem; ?mes=2026-13 → 422 competencia_invalida; contador GET → 200; agente → 403
[Fact] public async Task Pagar_exige_data_e_forma_e_gera_proxima_uma_vez()
// POST /despesas/{das}/pagar { pagoEm hoje, formaPagamento "pix", versao } → 200 despesa.pago true, proxima.vencimento = dia 20 do mês seguinte, proxima.recorrenciaOrigemId = das, proxima.pago false, mesma categoria/valor/forma; repetir → 422 despesa_paga; PUT da origem mudando valor → sucessora inalterada (decisão 44); pagar sem forma → regra: `forma_invalida`? não — `PagarDespesaRequest.FormaPagamento` é string obrigatória: "" → forma_invalida; pagoEm amanhã → data_invalida; versao velha → 409
// GerarProximaAsync direto (DbSessaoFactory) para a mesma origem → null (idempotente); excluir a sucessora (DELETE) e chamar de novo → null (não renasce, 0012)
[Fact] public async Task Recorrencia_ate_limita_e_pago_no_post_tambem_gera()
// POST { …recorrente true, recorrenciaAte = vencimento + 10 dias, pago true, pagoEm hoje, formaPagamento "boleto" } → 201 proxima null (próximo vencimento > ate); POST { …recorrenciaAte = vencimento + 2 meses, pago true … } → proxima presente; pago true sem forma → 422 pagamento_incompleto; recorrenciaAte < vencimento → data_invalida; categoria "luz" → categoria_invalida
[Fact] public async Task Editar_e_excluir_respeitam_competencia_antiga_e_nova()
// InserirFechamentoAsync(mês passado); despesa com vencimento no mês passado (owner insert): PUT como fin sem X-Motivo → 422 motivo_obrigatorio; com X-Motivo → 200; despesa do mês atual: PUT movendo vencimento para o mês fechado sem motivo → motivo_obrigatorio; DELETE da despesa do mês fechado com X-Motivo → 204; dono sem permissão? (dono tem tudo) — agente PUT → 403
```
`JobsTests.cs` (+):
```csharp
[Fact] public async Task Job_recorrencia_gera_uma_sucessora_por_origem_e_e_idempotente()
// despesa recorrente vencida no mês passado sem sucessora + despesa recorrente do mês atual + despesa não recorrente do mês passado + recorrente do mês passado com recorrencia_ate = vencimento
// `dotnet run -- job recorrencia_despesas` equivalente: resolver JobRunner do app.Services e ExecutarAsync("recorrencia_despesas") → 0; banco: exatamente 1 sucessora (da primeira), com vencimento no mês atual; rodar de novo → 0 e ainda 1 sucessora; job_execucao com sucesso true
```
- [ ] **Step 2–4:** RED → implementar → testes, format. Commit sugerido: `feat(despesas): expenses crud with competencia checks, pay with date/form, idempotent monthly recurrence (on pay and via job recorrencia_despesas)`

---

### Task 4 (backend): `Modules/Fechamento`

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Fechamento/FechamentoDtos.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Fechamento/FechamentoService.cs`, `backend/src/Meridiano.Api/Modules/Fechamento/FechamentoEndpoints.cs` (esqueletos)
- Create: `backend/tests/Meridiano.Api.Tests/FechamentoTests.cs`

**Depends-on:** T1 (`ConciliacaoService.PendentesDaCompetenciaAsync`, `ConciliacaoItemDto`)

**Interfaces:**
```csharp
public sealed class FechamentoService(DbSessaoFactory sessoes)
{
    public Task<IReadOnlyList<PeriodoDto>> ListarAsync(ContextoSessao ctx, int ano, CancellationToken ct);
    public Task<IReadOnlyList<ConciliacaoItemDto>> PendentesAsync(ContextoSessao ctx, string competencia, CancellationToken ct);
    public Task<PeriodoDto> FecharAsync(ContextoSessao ctx, string competencia, CancellationToken ct);
    public Task<PeriodoDto> ReabrirAsync(ContextoSessao ctx, string competencia, CancellationToken ct);
    public static DateOnly Parse(string competencia);   // "yyyy-MM" → dia 1; senão RegraDeNegocioException("competencia_invalida")
}
```
  - **Listar:** meses `1..min(12, mês atual se ano = atual)` do ano (ano futuro → lista vazia; `ano` fora de 2000..2100 → `competencia_invalida`), ordem decrescente. Por mês (uma query com `generate_series` + laterals, ou N queries — N ≤ 12, escolher o simples): `Reservas = count(reserva data_compra no mês, excluido_em null)`, `ComissoesPendentes/Valor = count/sum(saldo) de vw_reserva_financeiro aguardando com data_compra no mês`, `Despesas = count(despesa vencimento no mês)`, `ReceitaPrevista = sum(reserva.receita_prevista)` (compra no mês), `ReceitaRecebida = sum(movimento.valor)` (`data_movimento` no mês), `FechadoEm/FechadoPorNome` de `fechamento_periodo left join usuario`; `Status = fechado | pendencias (exists aguardando com data_prevista_comissao < current_date e compra no mês) | aberto`; `Corrente = mês atual`.
  - **Fechar:** `Parse` → `>= mês atual` → `periodo_em_andamento`; `TravarCompetenciaAsync` → exists → `periodo_ja_fechado`; `insert into fechamento_periodo (agencia_id, competencia, fechado_por)`; devolver o `PeriodoDto` desse mês (reutilizar a consulta de listar filtrada).
  - **Reabrir:** `ctx.Motivo` vazio → `motivo_obrigatorio`; `TravarCompetenciaAsync` → não existe → `periodo_aberto`; `delete from fechamento_periodo where agencia_id and competencia` (trigger `aud_fechamento` grava `DELETE` com `app.motivo`); devolver.
  - Rotas (`/periodos`): `GET /?ano=` (gate `LeFinanceiro` local) · `GET /{competencia}/pendentes` (gate leitura) · `POST /{competencia}/fechar` (`FinanceiroFecharPeriodo`) · `POST /{competencia}/reabrir` (`FinanceiroEditarPeriodoFechado`).

- [ ] **Step 1: Testes**
```csharp
[Fact] public async Task Lista_meses_do_ano_com_status_e_totais()
// reservas: 2 compradas no mês passado (uma aguardando com prevista ontem → pendencias; esperado 740), 1 no mês retrasado recebida (movimento no mês retrasado 320); despesa no mês passado; GET /periodos?ano=<atual> → itens do mês atual até janeiro (desc); mês passado: status "pendencias", reservas 2, comissoesPendentes 1 (740), despesas 1, receitaPrevista soma; mês retrasado: "aberto", receitaRecebida 320; mês atual: corrente true; contador → 200; agente → 403
[Fact] public async Task Fecha_reabre_com_motivo_e_auditoria_e_bloqueia_escrita()
// POST /periodos/<mês atual>/fechar → 422 periodo_em_andamento; POST <mês passado>/fechar como fin → 200 status "fechado", fechadoPorNome; repetir → periodo_ja_fechado; GET /periodos/<mês passado>/pendentes → 1 item (a aguardando)
// POST /movimentos com dataMovimento no mês passado como agente? (403 antes) — como fin sem X-Motivo → 422 motivo_obrigatorio
// POST /periodos/<mês passado>/reabrir sem header → 422 motivo_obrigatorio; com X-Motivo "erro%20de%20lan%C3%A7amento" → 200 status "pendencias"; auditoria: linha tabela 'fechamento_periodo' acao 'DELETE' motivo "erro de lançamento"; reabrir de novo → periodo_aberto; agente fechar → 403; "2026-13" → competencia_invalida
```
- [ ] **Step 2–4:** RED → implementar → testes, format. Commit sugerido: `feat(fechamento): monthly periods with status/totals, close with competencia lock, audited reopen with motivo, pending list`

---

### Task 5 (front): API, tipos, `useMutacaoFinanceira`, modais de dinheiro

**Files:**
- Create: `frontend/src/api/financeiro.ts`, `frontend/src/api/repasses.ts`, `frontend/src/api/despesas.ts`, `frontend/src/api/fechamento.ts`, `frontend/src/api/financeiro.test.ts` (`qsConciliacao`, `qsDespesas`)
- Create: `frontend/src/components/Financeiro/{useMutacaoFinanceira.ts,useMutacaoFinanceira.test.ts,mapaErrosFinanceiro.ts,MotivoField.tsx,ViagemCombobox.tsx,ViagemCombobox.test.tsx,ReceberModal.tsx,ReceberModal.test.tsx,ReceberLoteModal.tsx,ReceberLoteModal.test.tsx,DivergenciaModal.tsx,MovimentoModal.tsx,MovimentoModal.test.tsx,ExcluirMovimentoModal.tsx,DespesaModal.tsx,DespesaModal.test.tsx,PagarDespesaModal.tsx,PagarDespesaModal.test.tsx,PagarRepasseModal.tsx,PagarRepasseModal.test.tsx,FecharPeriodoModal.tsx,ReabrirModal.tsx,Financeiro.module.css}`, `frontend/src/components/financeiro.ts` (barrel)

**Depends-on:** T0

**Interfaces:**
```ts
// src/api/financeiro.ts (nomes espelham o C#)
export type TipoMovimento = "recebimento_operadora" | "recebimento_cliente" | "pagamento_fornecedor" | "estorno_operadora" | "reembolso_cliente";
export type FormaPagamentoFin = "pix" | "boleto" | "cartao" | "transferencia" | "dinheiro";
export const TIPOS_ENTRADA: TipoMovimento[] = ["recebimento_operadora", "recebimento_cliente"];
export interface MovimentoRequest { reservaId: string; tipo: TipoMovimento; valor: number; dataMovimento: string; formaPagamento: FormaPagamentoFin | null; observacao: string | null; versao?: string }
export interface MovimentoDto { id; versao; reservaId; viagemId; codigoViagem; localizador: string | null; fornecedorNome; tipo: TipoMovimento; valor: number; dataMovimento; formaPagamento: FormaPagamentoFin | null; observacao: string | null; criadoPorNome: string | null; criadoEm }
export interface ConciliacaoItemDto { reservaId; viagemId; codigo; titular: string | null; destino; localizador: string | null; fornecedorId; fornecedorNome; dataCompra; dataPrevistaComissao: string | null; situacaoComissao: string; diasAtraso: number | null; esperado: number; recebido: number; saldo: number; conciliacaoEncerrada: boolean; divergenciaMotivo: string | null; ultimoRecebimentoEm: string | null; elegivelLote: boolean }
export interface KpiValorDto { valor: number; reservas: number; extra: number | null }
export interface KpisConciliacaoDto { aReceber: KpiValorDto; atrasadas: KpiValorDto; vencemSemana: KpiValorDto; recebidoMes: { valor: number; variacaoPercentual: number | null } }
export interface ContadoresConciliacaoDto { pendentes; atrasadas; recebidasMes; divergencias: number }
export interface ConciliacaoDto { itens: ConciliacaoItemDto[]; total; pagina; tamanho; mes: string; contadores: ContadoresConciliacaoDto; kpis: KpisConciliacaoDto }
export type AbaConciliacao = "pendentes" | "atrasadas" | "recebidas" | "divergencias";
export interface FiltroConciliacao { aba?: AbaConciliacao; fornecedorId?: string; previsto?: "ate_hoje" | "semana" | "qualquer"; mes?: string; pagina?: number; tamanho?: number }
export function qsConciliacao(f: FiltroConciliacao): string
export const financeiroApi = {
  conciliacao: (f) => api.get<ConciliacaoDto>(`/conciliacao?${qsConciliacao(f)}`),
  movimentosDaViagem: (viagemId) => api.get<MovimentoDto[]>(`/viagens/${viagemId}/movimentos`),
  lancar: (m: MovimentoRequest, motivo?: string) => api.post<MovimentoDto>("/movimentos", m, { motivo }),
  corrigir: (id, m: MovimentoRequest, motivo?: string) => api.put<MovimentoDto>(`/movimentos/${id}`, m, { motivo }),
  excluir: (id, motivo: string) => api.delete(`/movimentos/${id}`, { motivo }),
  encerrarDivergencia: (reservaId, motivo: string) => api.post<ConciliacaoItemDto>(`/reservas/${reservaId}/encerrar-divergencia`, { motivo }),
  receberLote: (reservaIds: string[], dataMovimento: string, formaPagamento: FormaPagamentoFin | null, motivo?: string) => api.post<{ movimentos: MovimentoDto[] }>("/reservas/receber-lote", { reservaIds, dataMovimento, formaPagamento }, { motivo }),
};
export const chavesFinanceiro = { conciliacao: (f) => ["conciliacao", f] as const, movimentosDaViagem: (id) => ["viagens", id, "movimentos"] as const };

// src/api/repasses.ts
export interface RepasseItemDto { id; versao; viagemId; codigo; titular: string | null; destino; usuarioId; valor: number | null; status: "bloqueado" | "a_pagar" | "pago"; liberadoEm: string | null; pagoEm: string | null; observacao: string | null; aguardando: number; ultimoRecebimentoEm: string | null }
export interface VendedorRepassesDto { usuarioId; nome; viagensAno: number; aPagarValor: number; aPagarViagens: number; itens: RepasseItemDto[] }
export interface KpisRepassesDto { aPagarValor; aPagarVendedores; aPagarViagens; bloqueadoValor; bloqueadoViagens; semValor: number }
export interface RepassesDto { kpis: KpisRepassesDto; vendedores: VendedorRepassesDto[]; pagos: string | null; ano: number }
export const repassesApi = { listar: (pagos?: string) => api.get<RepassesDto>(`/repasses${pagos ? `?pagos=${pagos}` : ""}`), definirValor: (id, valor: number | null, versao) => api.put<RepasseItemDto>(`/repasses/${id}/valor`, { valor, versao }), pagarLote: (repasseIds: string[], pagoEm: string, observacao: string | null, motivo?: string) => api.post<{ pagos: RepasseItemDto[] }>("/repasses/pagar-lote", { repasseIds, pagoEm, observacao }, { motivo }) };
export const chavesRepasses = { lista: (pagos?: string) => ["repasses", pagos ?? "abertos"] as const };

// src/api/despesas.ts
export type CategoriaDespesa = "fixo" | "imposto" | "operacional" | "marketing" | "outro";
export interface DespesaRequest { descricao: string; categoria: CategoriaDespesa; valor: number; vencimento: string; pago: boolean; pagoEm: string | null; formaPagamento: FormaPagamentoFin | null; recorrente: boolean; recorrenciaAte: string | null; viagemId: string | null; fornecedorId: string | null; observacao: string | null; versao?: string }
export interface DespesaDto { id; versao; descricao; categoria: CategoriaDespesa; valor; vencimento; pago: boolean; pagoEm: string | null; formaPagamento: FormaPagamentoFin | null; recorrente: boolean; recorrenciaAte: string | null; recorrenciaOrigemId: string | null; viagemId: string | null; codigoViagem: string | null; tituloViagem: string | null; fornecedorId: string | null; fornecedorNome: string | null; observacao: string | null; situacao: "a_pagar" | "vencida" | "paga" }
export interface DespesaCriadaDto { despesa: DespesaDto; proxima: DespesaDto | null }
export interface KpisDespesasDto { lancadoValor; lancadoQtd; aPagarValor; vencidas; vencemAte7Dias; fixosValor; ligadasViagemValor; ligadasViagemQtd: number }
export interface DespesasDto { itens: DespesaDto[]; total; pagina; tamanho; mes: string | null; kpis: KpisDespesasDto }
export interface FiltroDespesas { mes?: string; categoria?: CategoriaDespesa; situacao?: "a_pagar" | "vencida" | "paga"; viagemId?: string; soVinculadas?: boolean; pagina?: number; tamanho?: number }
export function qsDespesas(f: FiltroDespesas): string
export const despesasApi = { listar: (f) => api.get<DespesasDto>(`/despesas?${qsDespesas(f)}`), criar: (d: DespesaRequest, motivo?) => api.post<DespesaCriadaDto>("/despesas", d, { motivo }), atualizar: (id, d: DespesaRequest, motivo?) => api.put<DespesaDto>(`/despesas/${id}`, d, { motivo }), excluir: (id, motivo?) => api.delete(`/despesas/${id}`, { motivo }), pagar: (id, pagoEm: string, formaPagamento: FormaPagamentoFin, versao: string, motivo?) => api.post<DespesaCriadaDto>(`/despesas/${id}/pagar`, { pagoEm, formaPagamento, versao }, { motivo }) };
export const chavesDespesas = { lista: (f) => ["despesas", f] as const, daViagem: (viagemId) => ["despesas", { viagemId }] as const };

// src/api/fechamento.ts
export interface PeriodoDto { competencia: string; status: "aberto" | "pendencias" | "fechado"; reservas: number; comissoesPendentes: number; comissoesPendentesValor: number; despesas: number; receitaPrevista: number; receitaRecebida: number; fechadoEm: string | null; fechadoPorNome: string | null; corrente: boolean }
export const fechamentoApi = { periodos: (ano: number) => api.get<PeriodoDto[]>(`/periodos?ano=${ano}`), pendentes: (competencia) => api.get<ConciliacaoItemDto[]>(`/periodos/${competencia}/pendentes`), fechar: (competencia) => api.post<PeriodoDto>(`/periodos/${competencia}/fechar`), reabrir: (competencia, motivo: string) => api.post<PeriodoDto>(`/periodos/${competencia}/reabrir`, undefined, { motivo }) };
export const chavesFechamento = { periodos: (ano) => ["periodos", ano] as const, pendentes: (c) => ["periodos", c, "pendentes"] as const };

// src/components/Financeiro/useMutacaoFinanceira.ts — receita dos modais de dinheiro (R9)
export function useMutacaoFinanceira<TArgs, TRes>(executar: (args: TArgs, motivo?: string) => Promise<TRes>, mapa: Record<string, string>): {
  salvando: boolean; erros: Record<string, string>; erroBloco: string | null; conflito: boolean;
  precisaMotivo: boolean; motivo: string; setMotivo: (m: string) => void;           // 422 motivo_obrigatorio → precisaMotivo = true; o modal renderiza <MotivoField/>; o próximo enviar() manda `motivo`
  enviar: (args: TArgs) => Promise<TRes | null>; limpar: () => void;
}
//  422 periodo_fechado → erroBloco "Período fechado. Só Dono ou Financeiro alteram com motivo." · 409 → conflito · demais como useOperacao (3.3)
<MotivoField value onChange erro? />   // Field "Motivo" required + Textarea; helper "Período fechado ou exclusão: o motivo vai para a auditoria."
export const CAMPO_POR_CODIGO_FIN: Record<string, string> = { tipo_invalido: "tipo", valor_invalido: "valor", forma_invalida: "formaPagamento", data_invalida: "data", motivo_obrigatorio: "motivo", descricao_obrigatoria: "descricao", categoria_invalida: "categoria", pagamento_incompleto: "formaPagamento", referencia_invalida: "viagemId", repasse_sem_valor: "valor" };
<ViagemCombobox value={{ id, rotulo } | null} onChange />   // busca via buscaApi.buscar(q) (grupo viagens), role=combobox/listbox como PassageirosField; item "{titular} · {destino} · <code>{codigo}</code>"

// Modais (todos: Modal do contrato, Button loading, Alert bloco/conflito, MotivoField quando precisaMotivo)
<ReceberModal open item={ConciliacaoItemDto | { reservaId, fornecedorNome, localizador, esperado, recebido, saldo }} onClose onRecebido={(m: MovimentoDto) => void} />
//  título "Receber comissão · {fornecedor} · {localizador}"; texto "Esperado R$ X · recebido R$ Y"; MoneyInput "Valor recebido" (default saldo; helper "Esperado: R$ X · menor = parcial ou divergência") · DateInput "Data" (hoje) · Select "Forma" (transferência default; lista FormaPagamentoFin); valor < saldo → Alert neutral "Valor menor que o esperado. Registre a diferença como divergência com motivo, ou deixe em aberto para receber o saldo depois."; submit financeiroApi.lancar({ tipo "recebimento_operadora", … }); botão primary "Confirmar recebimento"
<ReceberLoteModal open itens={ConciliacaoItemDto[]} onClose onRecebido={(ms: MovimentoDto[]) => void} />
//  "Marcar {n} comissões como recebidas"; lista "{fornecedor} · {localizador} (R$ esperado)"; DateInput* · Select Forma; botão primary "Confirmar R$ {soma}"
<DivergenciaModal open item onClose onEncerrada={(i: ConciliacaoItemDto) => void} />   // Textarea Motivo*; impacto "A reserva sai da conciliação com R$ {recebido} recebidos (esperado R$ {esperado}). O repasse é reavaliado."; botão primary "Encerrar com divergência"
<MovimentoModal open viagem={ViagemDto} movimento?={MovimentoDto} reservaFixa?={string} onClose onSalvo={(m: MovimentoDto) => void} />
//  Select Reserva (ativas + canceladas com comissão mantida; desabilitado em edição) · Select Tipo (5; desabilitado em edição) · MoneyInput Valor (positivo; helper "Saídas são gravadas como negativo") · DateInput Data · Select Forma · Textarea Observação; 422 → campo
<ExcluirMovimentoModal open movimento onClose onExcluido />   // ConfirmModal-like com MotivoField obrigatório; botão danger "Excluir movimento"; chama financeiroApi.excluir(id, motivo)
<DespesaModal open despesa?={DespesaDto} viagemFixa?={{ id, rotulo }} fornecedores={FornecedorDto[]} onClose onSalva={(d: DespesaDto, proxima: DespesaDto | null) => void} />
//  Descrição* (span 2) · Valor* (MoneyInput) · Categoria* · Vencimento* · Situação (Select "A pagar | Pago"; Pago → DateInput "Pago em"* + Select Forma*) · "Repete todo mês" (Select Não/Sim; tooltip do protótipo como helper) · "Repetir até" (opcional, só se repete) · Forma de pagamento (quando não pago: opcional) · Viagem (ViagemCombobox; escondido quando viagemFixa) · Fornecedor (Select opcional) · Observação; em edição: aviso "Editar afeta só esta ocorrência" quando recorrente
<PagarDespesaModal open despesa onClose onPaga={(d: DespesaDto, proxima: DespesaDto | null) => void} />   // "Marcar paga · {descricao}"; "R$ X · vencimento dd/mm"; DateInput*; Select Forma*; botão primary "Confirmar pagamento"
<PagarRepasseModal open vendedor={VendedorRepassesDto} itens={RepasseItemDto[]} onClose onPagos={(p: RepasseItemDto[]) => void} />   // "Pagar R$ X a {nome}?"; "{n} viagens saem de "a pagar" para "pago" com a data abaixo. O valor pago fica congelado mesmo que a viagem mude depois."; DateInput* · Input Observação; botão primary "Confirmar pagamento"
<FecharPeriodoModal open periodo={PeriodoDto} pendentes={ConciliacaoItemDto[]} onClose onFechado={(p) => void} />   // "Fechar {nomeMes}?"; texto com pendentes (n, valor) "continuam em aberto na conciliação. Depois do fechamento, reservas compradas em {mês}, movimentos, despesas e repasses pagos em {mês} só mudam com permissão e motivo."; lista pendentes; botão primary "Fechar {mês}"
<ReabrirModal open periodo onClose onReaberto />   // Textarea Motivo*; impacto "A reabertura fica na auditoria com o motivo."; botão danger "Reabrir {mês}"
```

- [ ] **Step 1: Testes** — `financeiro.test.ts` (`qsConciliacao({ aba:"atrasadas", fornecedorId:"x" })`, `qsDespesas({ mes:"2026-04", soVinculadas:true })`); `useMutacaoFinanceira.test.ts` (422 `motivo_obrigatorio` → `precisaMotivo`; segundo `enviar` passa `motivo`; `periodo_fechado` → bloco; 409 → conflito); `ViagemCombobox.test.tsx` (digitar chama `/busca?q=` e lista só viagens); `ReceberModal.test.tsx` (default = saldo; valor menor mostra o Alert; submit chama `POST /movimentos` com `tipo recebimento_operadora`, `valor`, `dataMovimento`, `formaPagamento`); `ReceberLoteModal.test.tsx` (botão "Confirmar R$ 1.920,00" com 2 itens; envia `reservaIds`); `MovimentoModal.test.tsx` (edição desabilita reserva/tipo; submit envia positivo); `DespesaModal.test.tsx` (Situação "Pago" exige data/forma local; "Repete" mostra "Repetir até"; submit envia `recorrente`, `viagemId` da combobox); `PagarDespesaModal.test.tsx` (envia `pagoEm`, `formaPagamento`, `versao`; `onPaga` recebe `proxima`); `PagarRepasseModal.test.tsx` (título com soma; envia `repasseIds`).
- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck, tokens.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(api): financeiro/repasses/despesas/fechamento clients, money mutation hook with motivo retry, money modals`

---

### Task 6 (front): `ConciliacaoPage` (+ `navegacao.ts` para o Contador)

**Files:**
- Create: `frontend/src/pages/financeiro/conciliacao/{ConciliacaoPage.tsx,ConciliacaoPage.test.tsx,useConciliacao.ts,useConciliacao.test.ts,TabelaConciliacao.tsx,Conciliacao.module.css}`
- Modify: `frontend/src/pages/financeiro/conciliacao/rotas.tsx`, `frontend/src/shell/navegacao.ts` (Financeiro: `permission: ["financeiro.movimentar","financeiro.conciliar","financeiro.ver_dre"]`), `frontend/src/shell/Sidebar.test.tsx`? (**não** — congelado; a asserção existente não quebra)

**Depends-on:** T5

**Interfaces:**
```ts
export function useConciliacao(): { filtro: FiltroConciliacao; definir; limpar; selecionados: Set<string>; alternar: (id) => void; limparSelecao; modal: null | { tipo: "receber" | "divergencia"; item: ConciliacaoItemDto } | { tipo: "lote" }; abrir; fechar; aplicarMovimento: () => void }
//  filtro na URL (aba default "pendentes", mes default competenciaAtual(), pagina); trocar aba limpa seleção e previsto; aplicarMovimento = invalidateQueries(["conciliacao"]) + ["viagens"]
// ConciliacaoPage: PageHeader "Comissões a receber" subtitle "O que as operadoras ainda devem à agência" · Subnav subnavs["/financeiro"] · KpiCard×4: "A receber" (valor; contexto "{n} reservas · {extra} operadoras") · "Atrasadas" (tone danger quando > 0; actionLabel "{n} reservas · pior: {extra} dias →" → definir({aba:"atrasadas"})) · "Vencem esta semana" (actionLabel "{n} reservas →" → definir({aba:"pendentes", previsto:"semana"})) · "Recebido no mês" (contexto "▲/▼ {v} % vs {mês anterior}" ou "— sem base") · Tabs Pendentes(n) · Atrasadas(n) · Recebidas em {nomeMes curto}(n) · Divergências(n) · filtros: Select "Operadora: todas" (viagensApi.fornecedores) · Select "Previsto: qualquer data | Até hoje | Esta semana" (pendentes/atrasadas) · Input month "Mês" (recebidas) · barra de seleção (pendentes/atrasadas, pode("financeiro.conciliar")): "{n} selecionadas · R$ {soma} · lote só para valor igual ao esperado" + Button business "Marcar recebidas" (disabled sem seleção) · <TabelaConciliacao/> · Paginacao
<TabelaConciliacao itens aba selecionados alternar podeMovimentar podeConciliar onReceber onDivergencia />
//  DataTable colunas: ☐ (Checkbox aria-label "Selecionar {localizador}", só elegivelLote e aba pendentes/atrasadas) · Reserva (primary "{titular} · {destino}"; secondary <code>codigo</code> · <code>localizador</code>) · Operadora · Previsto (DateCell; recebidas → "Recebido em" ultimoRecebimentoEm) · Situação (diasAtraso > 0 → Badge danger "{n} dias de atraso"; senão StatusCell comissao) · Esperado · Recebido (MoneyCell) · ações: "Receber" | "Receber saldo" (secondary sm; podeMovimentar; não em recebidas/divergências) + MenuAcoes ⋯ (Encerrar divergência… (podeConciliar, só aguardando com recebido > 0 ou atrasada) · Ver viagem → /viagens/{viagemId}?reserva={reservaId}); divergências: coluna "Motivo" no lugar de Situação; linha inteira → Ver viagem
//  vazio: EmptyState "Nada pendente" / "Todas as comissões previstas já entraram. Novas reservas aparecem aqui quando lançadas."
```

- [ ] **Step 1: Testes** — `useConciliacao.test.ts` (URL; trocar aba limpa seleção); `ConciliacaoPage.test.tsx` (fetch stub com o cenário do protótipo: 6 itens, contadores, kpis): 4 KpiCards com `R$ 18.420,00`; tabs com contadores; selecionar 2 linhas mostra "2 selecionadas · R$ 1.920,00"; "Marcar recebidas" abre `ReceberLoteModal`; "Receber" abre `ReceberModal` com "Esperado R$ 740,00"; perfil contador (stub `pode` sem movimentar) não mostra "Receber" nem a barra; clicar KPI Atrasadas troca a aba.
- [ ] **Step 2–4:** RED → implementar (`ConciliacaoPage.tsx` ≤ 200) → vitest, lint, typecheck, build.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(financeiro): conciliation page with kpis, tabs, batch receive, individual receive and divergence closing; contador sees Financeiro`

---

### Task 7 (front): `RepassesPage`

**Files:**
- Create: `frontend/src/pages/financeiro/repasses/{RepassesPage.tsx,RepassesPage.test.tsx,VendedorCard.tsx,VendedorCard.test.tsx,Repasses.module.css}`
- Modify: `frontend/src/pages/financeiro/repasses/rotas.tsx`

**Depends-on:** T5

**Interfaces:**
```ts
// RepassesPage: ?pagos=yyyy-MM na URL (histórico); PageHeader "Repasses a vendedores" subtitle "Liberado quando toda comissão da viagem entra · valor definido por você" actions: Button secondary "Histórico" ↔ "Voltar aos abertos" (alterna `pagos` = competenciaAtual()) + Input month quando histórico · Subnav · KpiCard×3 (abertos): "A pagar agora" (valor; actionLabel "{v} vendedores · {n} viagens →" → scroll para o 1º card com a pagar) · "Bloqueado" (contexto "aguardando comissão de {n} viagens") · "Sem valor definido" (tone warning se > 0; actionLabel "viagens esperando você informar →") · lista de <VendedorCard/> (2 colunas ≥ 1366, 1 abaixo) · vazio: EmptyState "Nenhum repasse em aberto" / "Repasses aparecem quando uma viagem tem vendedor externo com repasse."
<VendedorCard vendedor={VendedorRepassesDto} historico={boolean} podePagar={boolean} onPagar={(itens: RepasseItemDto[]) => void} onValorSalvo={() => void} />
//  header: avatar iniciais · nome · "vendedor(a) externo(a) · {viagensAno} viagens em {ano}" · total "R$ {aPagarValor} · a pagar · {n} viagens"
//  itens: "{titular} · {destino}" / <code>codigo</code> · "comissão recebida {dd/mm}" (ultimoRecebimentoEm, a_pagar) | "aguardando {n} comissões" (bloqueado) | "sem valor definido" | "pago em {dd/mm} · {observacao}" · StatusBadge repasse (valor null → Badge warning "informar valor") · valor: MoneyValue, ou MoneyInput inline (aria-label "Valor do repasse de {codigo}") quando valor null e podePagar → blur/Enter → repassesApi.definirValor(id, valor, versao) → toast.success("Valor informado") + onValorSalvo; 409 → toast.error + onValorSalvo
//  rodapé (não histórico, a pagar > 0): "Liberado: R$ X em N viagens" + Button primary "Pagar R$ X" (podePagar) → onPagar(itens a_pagar com valor)
```

- [ ] **Step 1: Testes** — `VendedorCard.test.tsx` (3 itens do protótipo; badge "informar valor"; digitar valor e Enter chama `PUT /repasses/<id>/valor` com `versao`; "Pagar R$ 850,00" chama `onPagar` com 3 itens); `RepassesPage.test.tsx` (stub: 2 vendedores; KPIs `R$ 1.150,00`, "3"; "Pagar" abre `PagarRepasseModal` "Pagar R$ 850,00 a Ana Paula?"; "Histórico" refaz a query com `?pagos=`; perfil externa (stub `pode` sem repasse.pagar) sem botão Pagar nem input).
- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(repasses): per-seller cards with inline value entry, batch pay modal, kpis and paid history`

---

### Task 8 (front): `DespesasPage`

**Files:**
- Create: `frontend/src/pages/financeiro/despesas/{DespesasPage.tsx,DespesasPage.test.tsx,useDespesas.ts,TabelaDespesas.tsx,Despesas.module.css}`
- Modify: `frontend/src/pages/financeiro/despesas/rotas.tsx`

**Depends-on:** T5

**Interfaces:**
```ts
export function useDespesas(): { filtro: FiltroDespesas; definir; modal: null | { tipo: "nova" } | { tipo: "editar" | "pagar" | "excluir"; despesa: DespesaDto }; abrir; fechar; invalidar }   // URL: mes (default competenciaAtual()), categoria, situacao, soVinculadas, pagina
// DespesasPage: PageHeader "Despesas" subtitle "Gastos da agência · {nomeMes} · R$ {lancadoValor} lançados · {aPagarQtd?} a pagar" (usar kpis) actions: Input month "Mês" · Button primary "+ Nova despesa" (pode financeiro.movimentar) · Subnav · KpiCard×4: "Lançado no mês" (contexto "{n} despesas") · "A pagar" (tone warning se vencidas > 0; actionLabel "{vencidas} vencida(s) · {v} vencem até {dd/mm} →" → definir({situacao:"vencida"})) · "Fixos" (contexto "DAS, sistema, telefone") · "Ligadas a viagens" (contexto "{n} despesa(s) · entra no resultado da viagem") · filtros: Select Categoria · Select Situação (todas | A pagar | Vencida | Paga) · Select "Viagem: qualquer | Só ligadas a viagem" · <TabelaDespesas/> · Paginacao
<TabelaDespesas itens podeMovimentar onPagar onEditar onExcluir />
//  DataTable: Despesa (primary descricao; secondary "recorrente · mensal" | tituloViagem | fornecedorNome) · Categoria (Badge neutral apresentacaoStatus despesa_categoria) · Vencimento (DateCell) · Situação (paga → Badge success "pago {dd/mm}"; senão StatusCell despesa) · Viagem (link <code>codigo</code> → /viagens/{id}) · Valor (MoneyCell) · ação: "Marcar pago" (secondary sm; não paga; podeMovimentar) | "Editar" (tertiary sm) + ⋯ Excluir (danger; ConfirmModal com MotivoField opcional — se 422 motivo_obrigatorio, pede)
//  vazio: EmptyState "Nenhuma despesa em {mês}" / "Lance a primeira despesa do mês ou troque o mês."
//  onPaga → toast.success(proxima ? `Paga. Próxima criada para ${formatarData(proxima.vencimento)}` : "Paga") + invalidar
```

- [ ] **Step 1: Testes** — `DespesasPage.test.tsx` (stub com 6 despesas do protótipo + kpis): header "R$ 2.640,00 lançados"; KPI "A pagar" com `R$ 1.180,00` e tone warning; "Marcar pago" abre `PagarDespesaModal` "Marcar paga · Anúncios Instagram — abril"; "+ Nova despesa" abre `DespesaModal`; trocar mês refaz a query com `mes=`; após `onPaga` com `proxima` mostra toast "Próxima criada para".
- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(despesas): expenses page with month filter, kpis, pay/edit/delete flows and recurrence feedback`

---

### Task 9 (front): `FechamentoPage`

**Files:**
- Create: `frontend/src/pages/financeiro/fechamento/{FechamentoPage.tsx,FechamentoPage.test.tsx,LinhaMes.tsx,Fechamento.module.css}`
- Modify: `frontend/src/pages/financeiro/fechamento/rotas.tsx`

**Depends-on:** T5 (runtime: T4)

**Interfaces:**
```ts
// FechamentoPage: ?ano= (default atual); PageHeader "Fechamento de período" subtitle "Mês fechado congela tudo com competência nele: reservas, recebimentos, movimentos, despesas e repasses. Exceção só com permissão + motivo (vai para a auditoria)." · Subnav · bloco "{ano}" (meta "competência = mês da compra (comercial) e do recebimento (financeiro)") com Select de ano (atual e 2 anteriores) · lista de <LinhaMes/> (desc)
<LinhaMes periodo podeFechar podeReabrir onFechar onReabrir />
//  <b>{nomeMes sem ano}</b> · meta: corrente → "em andamento" | fechado → "fechado em {dd/mm} por {nome}" | senão "{reservas} reservas · {comissoesPendentes} comissões pendentes · {despesas} despesas" · "R$ {receitaPrevista} prevista" · "R$ {receitaRecebida} recebida" · StatusBadge periodo (corrente e aberto → Badge info "aberto") · ação: !corrente && status ≠ fechado && podeFechar → Button primary sm "Fechar {mês}…" · fechado && podeReabrir → Button tertiary sm "Reabrir…"
//  onFechar → carrega pendentes (fechamentoApi.pendentes) e abre FecharPeriodoModal; onReabrir → ReabrirModal; sucesso → invalidate chavesFechamento.periodos(ano) + ["conciliacao"]
```

- [ ] **Step 1: Testes** — `FechamentoPage.test.tsx` (stub 4 meses do protótipo): Abril "em andamento" sem botão; Março badge "Pendências" + "Fechar Março…" abre o modal com "3 comissões" e lista de pendentes (stub `/periodos/2026-03/pendentes`); Fevereiro "fechado em 05/03 por Guilherme" + "Reabrir…" abre `ReabrirModal`; perfil sem `financeiro.fechar_periodo` não vê "Fechar"; trocar ano refaz a query.
- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(fechamento): period list per year with close and audited reopen modals`

---

### Task 10 (front): Tab Financeiro da viagem — receber, movimentos e despesas

**Files:**
- Modify: `frontend/src/pages/viagens/detalhe/FinanceiroTab.tsx` (reescrever; ≤ 200 linhas)
- Create: `frontend/src/pages/viagens/detalhe/FinanceiroTab.test.tsx`, `frontend/src/pages/viagens/detalhe/MovimentosViagem.tsx`, `frontend/src/pages/viagens/detalhe/DespesasViagem.tsx`, `frontend/src/pages/viagens/detalhe/FinanceiroTab.module.css`

**Depends-on:** T5

**Interfaces:**
```ts
// FinanceiroTab({ viagem }) — assinatura inalterada (ViagemPage congelada)
//  const { pode } = useAuth(); const qc = useQueryClient(); podeMovimentar = pode("financeiro.movimentar"); verValores = viagem.reservas[0]?.valorTotal !== undefined
//  faixa (igual 3.3) · bloco "Comissões a receber": cada reserva ativa com esperado > 0 → linha de 3.3 + Button secondary sm "Receber" (podeMovimentar e situacaoComissao ∉ recebida) → ReceberModal com { reservaId, fornecedorNome, localizador, esperado: valorEsperadoOperadora, recebido: recebidoOperadora, saldo } · onRecebido → aplicar()
//  <MovimentosViagem viagem podeMovimentar onMudou={aplicar}/>: useQuery(chavesFinanceiro.movimentosDaViagem(id), enabled: verValores); header "Movimentos" + count + Button secondary sm "+ Lançar movimento"; linhas: Badge apresentacaoStatus("movimento_tipo") · MoneyValue (negativo em vermelho pelo MoneyValue) · formatarData · forma · "reserva {localizador}" · observação · ⋯ Editar (MovimentoModal) · Excluir (ExcluirMovimentoModal); vazio "Nenhum movimento ainda"
//  <DespesasViagem viagem podeMovimentar onMudou={aplicar}/>: useQuery(chavesDespesas.daViagem(id)) → despesasApi.listar({ viagemId: id }); header "Despesas da viagem" + total + Button secondary sm "+ Despesa" (DespesaModal com viagemFixa); linhas: descricao · categoria · vencimento · StatusCell despesa · valor · "Marcar pago" (PagarDespesaModal) · ⋯ Editar/Excluir; vazio "Nenhuma despesa ligada a esta viagem"
//  aplicar() = invalidateQueries(chaves.viagem(id)) + movimentosDaViagem + daViagem + ["conciliacao"] + ["repasses"] (a viagem recarrega resumo/repasse pela view)
```

- [ ] **Step 1: Testes** — `FinanceiroTab.test.tsx` (stub viagem do protótipo com 2 reservas a receber, `/viagens/<id>/movimentos` com 1 recebimento, `/despesas?viagemId=` com 1 despesa): mostra "Receber" nas duas reservas quando `pode("financeiro.movimentar")`; esconde para contador; bloco Movimentos lista `+ R$ 1.100,00`; "+ Lançar movimento" abre `MovimentoModal` com Select de reserva com 2 opções; bloco Despesas lista `R$ 180,00`; após `onRecebido` invalida `["viagens", id]`.
- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck, build.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(viagens): trip financial tab with receive shortcut, movimentos and linked expenses`

---

### Task 11 (front): E2E do financeiro

**Files:**
- Create: `frontend/e2e/financeiro.spec.ts`, `frontend/e2e/financeiro.ts` (helper `criarViagemComComissao(request, { destino })`: como `criarViagemViaApi` (congelado), mas com `valorComissao 1000`, `ravOperadora 100`, `status "emitida"`, `dataCompra` hoje; devolve `{ id, codigo, localizador }`)

**Depends-on:** T6–T10 (e seed de T0)

- [ ] **Step 1: Spec**
```ts
import { expect, test } from "@playwright/test";
import { loginUi } from "./api";
import { criarViagemComComissao } from "./financeiro";

test.describe("financeiro", () => {
  test("conciliação: recebe comissão e a reserva sai de pendentes", async ({ page, request }) => {
    await loginUi(page);
    const { localizador } = await criarViagemComComissao(page.request, { destino: "Lisboa FIN" });
    await page.goto("/financeiro");
    const linha = page.getByRole("row", { name: new RegExp(localizador) });
    await expect(linha).toBeVisible();
    await linha.getByRole("button", { name: "Receber" }).click();
    await expect(page.getByText(/Esperado R\$ 1\.100,00/)).toBeVisible();
    await page.getByRole("button", { name: "Confirmar recebimento" }).click();
    await expect(page.getByRole("row", { name: new RegExp(localizador) })).toHaveCount(0);
    await page.getByRole("tab", { name: /Recebidas/ }).click();
    await expect(page.getByRole("row", { name: new RegExp(localizador) })).toBeVisible();
  });

  test("despesas: cria, marca paga e a recorrente gera a próxima", async ({ page }) => {
    await loginUi(page);
    await page.goto("/financeiro/despesas");
    await page.getByRole("button", { name: "+ Nova despesa" }).click();
    const nome = `Sistema E2E ${Date.now() % 10000}`;
    await page.getByLabel("Descrição").fill(nome);
    await page.getByLabel("Valor").fill("149");
    await page.getByLabel("Categoria").selectOption("fixo");
    await page.getByLabel("Repete todo mês").selectOption("sim");
    await page.getByRole("button", { name: "Salvar despesa" }).click();
    const linha = page.getByRole("row", { name: new RegExp(nome) });
    await expect(linha).toBeVisible();
    await linha.getByRole("button", { name: "Marcar pago" }).click();
    await page.getByLabel("Forma").selectOption("pix");
    await page.getByRole("button", { name: "Confirmar pagamento" }).click();
    await expect(page.getByText(/Próxima criada para/)).toBeVisible();
  });
});
```
- [ ] **Step 2: Rodar** com API + seed (`backend/scripts/dev.md`): `npx playwright test e2e/financeiro.spec.ts` → verde nos 2 viewports. Se 3.4 já fechou, rodar também `e2e/nova-viagem.spec.ts` e anotar o tempo (contrato C14).
- [ ] **Step 3: Reportar.** Commit sugerido: `test(e2e): conciliation receive flow and expense pay with recurrence`

---

### Task 12 (root): Docs e fechamento — **serial com o fechamento de 3.4**

**Files:**
- Modify: `docs/BACKLOG.md` (3.5 concluída com contagens; remover: "Financeiro invisível para Contador" (3.1), "`X-Motivo` por header" (3.3); novas deferidas: reabrir conciliação (R3), "Ver extrato" de repasses (R5), drift da recorrência e uma sucessora por execução (R7), sucessora gerada em mês fechado sem checagem (T3), badge de comissões atrasadas na sidebar (3.6), "+ Nova despesa" em `primary` (protótipo laranja), mais o que os reviews levantarem)
- Modify: `docs/autorizacao-por-operacao.md` (tabela "Permissões" deste plano; nota C7 Contador; nota "X-Motivo")
- Modify: `docs/superpowers/plans/2026-09-08-fase-3-master.md` (linha 3.5: "(concluído: 12 tasks, 4 ondas)"; endpoints divergentes; jobs: `recorrencia_despesas` feito)
- Modify: `CLAUDE.md` (linha Estado: 3.5 ✓ com contagens; próximo 3.6 quando 3.4 também fechar)
- Modify: `regras-e-escopo-v2.md` §4.4 (nota: reabrir conciliação fora da v1), §5 (nota: valor editável até pagar; lote por vendedor com data), decisão 44 (nota R7)

**Depends-on:** T11

- [ ] **Step 1–2:** editar; controlador commita no root: `docs: fase 3.5 financeiro done — backlog, authorization table, state line, rulings`

---

## Self-review (feito ao escrever)

- **Spec §4.3** cinco movimentos com sinal, atalho "marcar comissão recebida" (individual = movimento; lote = decisão 48) → T1/T5/T6 ✓. **§4.4** conciliação = `recebido ≥ esperado` ou encerrada com motivo → view existente + T1 `EncerrarDivergenciaAsync` ✓ (reabrir → BACKLOG).
- **§5** repasse digitado pelo dono, `bloqueado → a_pagar → pago` calculado pela API ao registrar movimento (`ReavaliarRepasseAsync` em todo lançamento/correção/exclusão/divergência), pagamento em lote por vendedor com data, pago preservado → T1/T2 ✓; externo vê o próprio valor → T2 `apenasUsuario` ✓.
- **§8** motivo obrigatório ao excluir e em período fechado (`X-Motivo`, C2) → T1/T3/T4/T5 (`useMutacaoFinanceira`) ✓; fechamento congela `data_compra` (divergência, cancelamento de 3.3), `data_movimento`, `vencimento`/`pago_em`, `pago_em` do repasse → competência checada em cada escrita, antiga **e** nova → T1/T2/T3 ✓; reabertura auditada → `delete` + `aud_fechamento` (0012) ✓.
- **Decisões** 37/46 (Despesas, subnav já existe), 40 (data e forma nos diálogos de pagar/receber), 43 (fechamento), 44 (recorrência: ao pagar ou dia 1; até; editar só a atual), 48 (lote só valor = esperado) → T3/T5/T8 ✓.
- **Contratos transversais**: ordem de locks (competência → viagens em ordem de id) em lote de recebimento e de pagamento → T1/T2 ✓; `ux_despesa_sucessora` + `on conflict … do nothing` = idempotência → T3 ✓; job por agência com `DbSessao` → T3 ✓; `TocarViagemAsync` só onde o campo está no formulário (`repasse.valor`, status pago) → T2 ✓, ausente em movimento/divergência/despesa (ruling 3.3) ✓.
- **Contrato 3.4∥3.5**: nenhuma migration; arquivos tocados ⊆ §3 do contrato (`Jobs/JobsExtensions.cs` incluso em `Jobs/**`; `navegacao.ts`; `FinanceiroTab.tsx`); `ViagensEndpoints.SemVisibilidade` só **lido** (internal, mesmo assembly) ✓; helper `LeFinanceiro` duplicado localmente em T3/T4 para não tocar arquivo de T1 (3 linhas; aceito).
- **Contrato §4.1/§4.4**: laranja só "Marcar recebidas"; "Pagar R$ X" por vendedor `primary`; campo pré-preenchido editável com helper "Esperado: R$ X" (ReceberModal) ✓; `KpiCard` informativo/acionável ✓; Contador lê (C7) ✓.
- **Placeholders**: nenhum; DTOs, SQL de conciliação e regras de cada endpoint escritos; `Recorrencia.ProximoVencimento` com código.
- **Tipos**: DTOs C# ↔ TS campo a campo; `ConciliacaoItemDto` (T1) usado por T4 (backend) e T5/T6/T9 (front); `chavesFinanceiro.movimentosDaViagem` usado em T10; `useMutacaoFinanceira` (T5) por todos os modais; `competenciaAtual`/`nomeMes` (T0) por T6/T8/T9 ✓.
- **Ondas**: T1×T2×T3 pastas distintas (T3 inclui `Jobs/**` e `Domain/Financeiro/Recorrencia.cs`); T4 depois de T1; T6–T10 pastas/rotas próprias (T6 também `navegacao.ts`, T10 só `pages/viagens/detalhe/Financeiro*`/`MovimentosViagem`/`DespesasViagem`) ✓.
