# Meridiano — Backlog e estado do projeto

Última revisão: 2026-09-08. Fonte de verdade para "o que já foi feito" e "o que falta". Backlog de configuração do harness fica em `.claude/SETUP-BACKLOG.md`.

## Estado por fase

| Fase | Entrega | Estado | Onde |
|---|---|---|---|
| 1 — Especificação | `regras-e-escopo-v2.md`, `schema-agencia-v2.sql`, análise arquitetural, 50 decisões registradas | Concluída (2026-09-07/08) | raiz, `docs/analise-arquitetural-v1.md` |
| 2 — Esqueleto | Solution .NET 10, migrations DbUp 0001–0011, RLS, auth própria, perfis/permissões, ProblemDetails, jobs CLI, CI, endpoint vertical de usuários | Concluída (2026-09-07). 13 testes de domínio + 26 de API, verdes | `backend/` (repo `meridiano-api`), plano em `docs/superpowers/plans/2026-09-07-fase-2-esqueleto.md` |
| Design | Design system v3, contrato de implementação, protótipo clicável v1 com 22 telas, tokens CSS | **Congelado** em 2026-09-08 após 5 revisões externas (tag `design-v1-freeze` no root) | `docs/design-system-contrato.md`, `docs/design/prototipo-v1.html` + `prototipo-v1/*.png`, `frontend/src/styles/tokens.css` |
| 3 — Front + módulos | React/Vite/TS servido pela API; módulos viagem/reserva, pessoas, fornecedores, financeiro, pendências, despesas, repasses, fechamento, relatórios | **Próxima.** Plano-mestre `docs/superpowers/plans/2026-09-08-fase-3-master.md` (7 subplanos, 3.0–3.6, revisado 2026-09-08 após review externa; 5 decisões pendentes D1–D5 no mestre); 3.0 detalhado em `2026-09-08-fase-3-0-hardening.md` (7 tasks, 3 ondas); 3.1 em `2026-09-08-fase-3-1-scaffold.md` (12 tasks, 7 ondas) | `frontend/` (repo `meridiano-app`), `backend/src/Meridiano.Api/Modules/` |
| 4 — Piloto | Deploy Azure Container Apps + Supabase, importar planilha, medir tempo de lançamento | Não iniciada | — |

## Fase 3 — subplanos (detalhe no plano-mestre)

Cada item vira um plano próprio quando os de que depende fecham:

0. **Hardening** (só backend) — revalidação de sessão contra o banco, token de convite/reset consumido atomicamente, links `/definir-senha` × `/redefinir-senha`, guarda de último dono com lock, tradução de `PostgresException`, lock de job, helpers de lock de viagem/competência e validação de referência por tenant, migration 0012 (views `security_invoker`, `vw_viagem_titular`/`vw_fase_viagem` corrigidas, índices únicos parciais de repasse/recorrência/titular/job, FK do log documental `set null`, auditoria de `fechamento_periodo`), tabela de autorização por operação. Fecha as pendências da Fase 2 marcadas abaixo com **(3.0)**.
1. **Scaffold** — Vite + React + TS no `frontend/`, tokens já existentes, componentes obrigatórios do contrato (§3 de `design-system-contrato.md`: Button, Field/Input, Select, Chip, Tabs, Subnav, Sidebar, Table, Dialog, Toast, EmptyState, Skeleton), roteamento, cliente HTTP com ProblemDetails (422 no campo, 409, 403), sessão por cookie, build em `wwwroot/`. Mover `UsuarioService` de `AddAuth` para `AddModules` (pendência da Fase 2).
2. **Nova viagem** (risco número um) — endpoint transacional viagem + passageiros + reservas + repasse + pendências automáticas, salvar parcial, adicionar reserva depois, pré-preenchimento, criação inline de pessoa (fornecedor: D1), teclado, aviso de viagem semelhante e reserva duplicada, vigência da regra de pagamento, teste E2E cronometrado.
3. **Viagens** — lista com filtros recolhidos, detalhe com tabs (Reservas · Financeiro · Pendências · Anexos · Auditoria), editar reserva, remarcação, cancelamento com motivo/desfecho/crédito, NFSe, serviços, anexos com `log_acesso_documento`, busca global, `vw_fase_viagem`.
4. **Cadastros** — Clientes/Pessoa (tabs, pendências, atendimentos), Grupos, Fornecedores (regra de pagamento com `vigente_desde`).
5. **Financeiro** — Conciliação com os 5 tipos de movimento, divergência, lote atômico, Repasses, Despesas (recorrência idempotente, forma ao pagar), Fechamento com lock por competência e reabertura auditada.
6. **Agenda, Relatórios, Equipe, Auditoria, jobs** — pendências multi-passageiro, KPIs com fórmulas documentadas, CSV, convite/perfis, auditoria por perfil, RLS em `log_acesso`, jobs (pendências derivadas, resumo e-mail, expurgos, aniversários).

## Pendências abertas

### De especificação (regras-e-escopo-v2 §12)
- Contador: base e regime da receita bruta do MEI (§4.9).
- Decisão 17: `vencimento_fornecedor` (data-limite da operadora) fora até o usuário pedir.
- Piloto: validar fórmulas de §4.2 e a RAV (decisão 49) com três viagens reais da planilha **antes** de fechar a Fase 3.

### Deferidas da Fase 2 (revisões de task e revisão final)
- Sessão: perfil lido do cookie, sem revalidação de `ativo`/`perfil` por request (inativado mantém acesso até 12 h) **(3.0)**.
- `ConviteService.DefinirSenhaAsync`: lookup do token fora da transação e `UPDATE` sem recheck (token consumível duas vezes); link de reset aponta `/definir-senha` **(3.0)**.
- `TratadorDeExcecoes`: `PostgresException` (23505/23503/23514/42501) cai em 500 genérico **(3.0)**.
- Views sem `security_invoker`; owner das migrations é superuser no compose/Testcontainers, então leitura por view ignora RLS; nenhum teste toca `vw_*` **(3.0)**.
- Sem constraint de titular único; `repasse_unico` permite N por viagem e bloqueia recriar após soft delete; `vw_resultado_viagem` duplica linhas com 2 repasses; `ix_despesa_recorrencia` não único; `fechamento_periodo` sem `id`/auditoria; FK de `log_acesso_documento` impede expurgo **(3.0)**.
- `ModulesExtensions.AddModules`: mover registro de `UsuarioService` para fora de `AddAuth` (3.1 T06).
- RLS em `log_acesso` (nada lê a tabela ainda; login insere sem `app.agencia_id`).
- Login multiagência: e-mail é único global (migration 0004); pessoa em duas agências precisa de dois e-mails.
- `EsqueciSenha` silencioso para usuário convidado sem senha definida; e-mail de convite sai após o commit (falha no Resend gera 500 com linha criada).
- Guarda de "último Dono" ignora `ativo` do alvo (caso de único Dono inativo) e não serializa alterações concorrentes **(3.0)**.
- `ExecutarJob` usa `CancellationToken.None` (sem cancelamento por SIGTERM); sem teste do caminho de falha; sem exclusão mútua entre execuções **(3.0)**.
- `PrevisaoComissao`: janelas sobrepostas resolvidas por ordem da lista, sem teste; sem teste de ano bissexto.
- `MigrationsTests`: asserção de grant só cobre INSERT.
- Duas `NpgsqlConnection` soltas em call sites pré-login (aceito pela convenção, documentar); log de e-mail em dev inclui o HTML.
- `NU1510` NoWarn é project-wide em `Meridiano.Api.csproj`.
- `alter default privileges for role meridiano` é específico por ambiente; aplicar no Supabase na Fase 4.

### Versão 1.1 (fora da v1, já registradas)
- RAV com câmbio, imposto e desconto explícito (decisão 49).
- DRE completa (despesa hoje é simples).
- Multiagência por usuário.
- Ver `regras-e-escopo-v2.md` §10 para a lista completa.

## Convenções de manutenção deste arquivo
- Atualizar a tabela de fases ao fechar cada onda da Fase 3.
- Pendência resolvida sai daqui e vira commit; não manter histórico aqui (o git já tem).
