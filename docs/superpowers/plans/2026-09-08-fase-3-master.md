# Meridiano — Fase 3 — Front + Módulos: Plano-mestre em ondas

> **Para agentes:** este é o índice. Cada subplano (3.1 … 3.6) é um plano completo próprio, no formato de `superpowers:writing-plans`, escrito **quando o subplano anterior fecha** — o seguinte depende da API de componentes e dos endpoints que o anterior produziu. Executar cada subplano com `superpowers:subagent-driven-development` seguindo `.claude/rules/parallel-subagent-driven-development.md` (implementador não commita; controlador commita por task).

**Goal:** aplicação completa da v1 (spec §10) rodando: React servido pela API, 22 telas do protótipo congelado, módulos com endpoints, testes de integração por módulo, teste E2E cronometrado da tela de lançamento.

**Architecture:** monólito modular já existente (`Meridiano.Api` vertical slice por módulo) + SPA React em `frontend/` buildada para `wwwroot/`. Backend é a autoridade de cálculo; front faz preview. Sessão por cookie; autorização por `Permissao` no C# e por `permissoes[]` do `/auth/me` no front (só para esconder, nunca para proteger).

**Tech Stack:** .NET 10 · Dapper · DbUp · PostgreSQL 17 · React 19 · Vite · TypeScript strict · react-router 7 · TanStack Query · react-hook-form · lucide-react · CSS Modules + `tokens.css` · Vitest + Testing Library · Playwright · ESLint (type-aware) + Biome.

**Spec:** `regras-e-escopo-v2.md` · `schema-agencia-v2.sql` (migrations 0001–0011 aplicadas) · `docs/design-system-contrato.md` (congelado) · `docs/design/prototipo-v1.html` (22 telas) · `docs/BACKLOG.md` (pendências deferidas).

## Restrições globais (valem em todos os subplanos)

- Dois repositórios: `backend/` (`meridiano-api`) e `frontend/` (`meridiano-app`). Task que toca os dois gera **dois commits**, um por repo, pelo controlador. Root (`meridiano-root`) só recebe docs.
- Front: nenhuma cor hex, `font-size` ou `@media` fora de `tokens.css`/breakpoints 1024·1280·1440 (contrato §5). Só ícones Lucide. Componentes recebem intenção (`variant`, `tone`, `calculated`), nunca cor.
- Status de domínio chega da API em português (spec §6.1) e passa por `apresentacaoStatus()`. Front não cria enums em inglês.
- Toda tela que salva usa a máquina `idle → dirty → saving → saved | error` e `versao` (xmin) em PUT.
- Backend: um módulo = `Modules/<Modulo>/{Endpoints,Dtos,<Modulo>Service}.cs`; toda query em `DbSessao`, filtra `agencia_id` e `excluido_em is null`; `.RequerPermissao(...)` em todo grupo; erros por `RegraDeNegocioException` (422) / `ConflitoConcorrenciaException` (409).
- Testes: integração com Postgres real (Testcontainers) para tenant, permissão, concorrência e cada regra financeira; unidade em `Meridiano.Domain` para cálculo; Vitest para componente e util; Playwright poucos e cronometrados.
- Commits Conventional Commits em inglês com rodapé de atribuição.
- Tempo de lançamento (spec §14) é requisito: medir no E2E de 3.2 e reportar no fechamento de cada subplano seguinte.

## Subplanos e ondas

| # | Subplano | Entrega verificável | Backend (endpoints/serviços) | Front (telas do protótipo) | Depende de |
|---|---|---|---|---|---|
| 3.1 | **Scaffold, shell e acesso** — `2026-09-08-fase-3-1-scaffold.md` (escrito) | `npm run build` gera `wwwroot/`; login real contra a API; sidebar por permissão; styleguide em `/styleguide`; lint/CI verdes; regressão visual base | `/auth/me` devolve `permissoes[]`; `AddModules`; API serve SPA com fallback; Dockerfile com estágio Node | 01 login · 02 definir senha · 03 esqueci senha · 04 redefinir senha · AppShell (sidebar, header, subnav, tabs) · primitivos e feedback do contrato §3 até `Section` | Fase 2 |
| 3.2 | **Nova viagem** (risco número um) | Criar viagem com N reservas em uma transação; pré-preenchimento; pessoa/fornecedor inline; teclado; aviso de viagem semelhante; E2E cronometrado (meta ≤ 5 min para 4 reservas) | `Modules/Viagens`: `POST /viagens` (viagem + reservas), `GET /viagens/{id}`, `PUT /viagens/{id}`, `GET /viagens/semelhantes?cliente&data_ida`; `Modules/Pessoas`: `GET /clientes/busca?q`, `POST /clientes` (inline); `Modules/Fornecedores`: `GET /fornecedores?ativo`, `POST /fornecedores` (inline); cálculo de `rav_cliente`, `valor_esperado_operadora`, `receita_prevista` via generated columns + preview em `Meridiano.Domain.Financeiro.CalculoReserva` | 06 nova viagem · `ReservationCard` `TripSummary` `MoneyInput` em uso real · `ServiceChips` · `FinancialFields` · `ResultSummary` | 3.1 |
| 3.3 | **Viagens e reservas** | Lista com filtros recolhidos e `vw_fase_viagem`; detalhe com tabs Reservas · Financeiro · Pendências · Anexos · Auditoria; cancelamento com motivo/desfecho/crédito; edição com 409 | `GET /viagens` (filtros, paginação, `vw_fase_viagem`, `vw_viagem_titular`), `POST /reservas/{id}/cancelar`, `GET /viagens/{id}/auditoria`, `Modules/Pendencias` (CRUD, multi-passageiro), `Modules/Anexos` (R2 presign + `log_acesso` documento) | 05 viagens · 07 viagem · `DataTable` `MoneyCell` `DateCell` `StatusCell` `KpiCard` | 3.2 |
| 3.4 | **Cadastros** | Clientes/Pessoa com tabs (Dados · Viagens · Pendências · Atendimentos · Documentos), Grupos (família/empresa), Fornecedores com regra de pagamento `vigente_desde` | `Modules/Pessoas` completo (`GET/PUT /clientes/{id}`, documentos com LGPD log, atendimentos), `Modules/Grupos`, `Modules/Fornecedores` completo (`regra_pagamento_fornecedor`) | 08 clientes · 09 pessoa · 10 grupos · 11 grupo · 12 fornecedores · 13 fornecedor | 3.3 |
| 3.5 | **Financeiro** | Conciliação (recebimentos; lote só quando recebido = esperado); Repasses (bloqueado/a_pagar/pago, pagamento em lote); Despesas (recorrência gera próxima ao pagar, forma obrigatória ao pagar); Fechamento por competência congela | `Modules/Financeiro`: `POST /movimentos` (recebimento_operadora, recebimento_cliente, estorno), `POST /reservas/receber-lote`, `GET /conciliacao`; `Modules/Repasses`: `GET`, `PUT /{id}/valor`, `POST /pagar-lote`; `Modules/Despesas`: CRUD + `POST /{id}/pagar` (gera recorrência); `Modules/Fechamento`: `POST /periodos/{aaaa-mm}/fechar`, `reabrir` (permissão `FinanceiroEditarPeriodoFechado`); job `recorrencia_despesas` (dia 1) | 14 financeiro · 15 repasses · 16 despesas · 17 fechamento · diálogos de data/forma | 3.3 (3.4 em paralelo é possível: arquivos disjuntos) |
| 3.6 | **Agenda, Relatórios, Equipe, Auditoria + piloto** | Agenda com tabs (Hoje · Semana · Atrasadas); Relatórios (KPIs de resultado, receita por mês, nacional×internacional, fornecedores, serviços, teto MEI); Equipe (lista + convite + edição, já tem endpoint); Auditoria; RLS em `log_acesso`; teste de UX do contrato §7 | `GET /agenda`, `GET /relatorios/resumo?ano&vendedor`, `GET /relatorios/receita-mensal`, `GET /auditoria?entidade&id&periodo`, migration `log_acesso` RLS, `GET /clientes/aniversarios` (job `aniversarios`) | 18 agenda · 19 relatórios · 20 equipe · 21 colaborador · 22 auditoria | 3.4 e 3.5 |

Ondas dentro de cada subplano seguem a regra `Files`/`Depends-on`. Entre subplanos, 3.4 e 3.5 podem correr em paralelo (módulos e telas disjuntos) se houver capacidade; 3.6 espera os dois.

## Critério de fechamento da Fase 3

- Todas as 22 telas do protótipo navegáveis com dados reais.
- `cd backend && dotnet test` e `cd frontend && npm run lint && npm run test && npm run build` verdes; CI dos dois repos verde.
- E2E cronometrado da Nova viagem (4 reservas) abaixo da meta, registrado em `docs/BACKLOG.md`.
- Teste de UX do contrato §7 executado uma vez; achados registrados.
- Fórmulas §4.2 validadas com três viagens reais (pendência da spec §12) — condição para iniciar a Fase 4.

## Fora deste plano

Deploy Azure/Supabase, importação da planilha, tema escuro, mobile completo, autosave, merge de conflito (contrato §9), DRE completa, multiagência por usuário (v1.1).
