# Meridiano — Backlog e estado do projeto

Última revisão: 2026-09-08. Fonte de verdade para "o que já foi feito" e "o que falta". Backlog de configuração do harness fica em `.claude/SETUP-BACKLOG.md`.

## Estado por fase

| Fase | Entrega | Estado | Onde |
|---|---|---|---|
| 1 — Especificação | `regras-e-escopo-v2.md`, `schema-agencia-v2.sql`, análise arquitetural, 50 decisões registradas | Concluída (2026-09-07/08) | raiz, `docs/analise-arquitetural-v1.md` |
| 2 — Esqueleto | Solution .NET 10, migrations DbUp 0001–0011, RLS, auth própria, perfis/permissões, ProblemDetails, jobs CLI, CI, endpoint vertical de usuários | Concluída (2026-09-07). 13 testes de domínio + 26 de API, verdes | `backend/` (repo `meridiano-api`), plano em `docs/superpowers/plans/2026-09-07-fase-2-esqueleto.md` |
| Design | Design system v3, contrato de implementação, protótipo clicável v1 com 22 telas, tokens CSS | **Congelado** em 2026-09-08 após 5 revisões externas (tag `design-v1-freeze` no root) | `docs/design-system-contrato.md`, `docs/design/prototipo-v1.html` + `prototipo-v1/*.png`, `frontend/src/styles/tokens.css` |
| 3 — Front + módulos | React/Vite/TS servido pela API; módulos viagem/reserva, pessoas, fornecedores, financeiro, pendências, despesas, repasses, fechamento, relatórios | **Próxima. Plano ainda não escrito** | `frontend/` (repo `meridiano-app`), `backend/src/Meridiano.Api/Modules/` |
| 4 — Piloto | Deploy Azure Container Apps + Supabase, importar planilha, medir tempo de lançamento | Não iniciada | — |

## Fase 3 — escopo previsto (para o plano em ondas)

Ordem sugerida, cada onda com endpoints + tela:

1. **Scaffold** — Vite + React + TS no `frontend/`, tokens já existentes, componentes obrigatórios do contrato (§3 de `design-system-contrato.md`: Button, Field/Input, Select, Chip, Tabs, Subnav, Sidebar, Table, Dialog, Toast, EmptyState, Skeleton), roteamento, cliente HTTP com ProblemDetails (422 no campo, 409, 403), sessão por cookie, build em `wwwroot/`. Mover `UsuarioService` de `AddAuth` para `AddModules` (pendência da Fase 2).
2. **Nova viagem** (risco número um) — endpoint transacional viagem + reservas, pré-preenchimento, criação inline de pessoa/fornecedor, teclado, aviso de viagem semelhante, teste E2E cronometrado.
3. **Viagens** — lista com filtros recolhidos, detalhe com tabs (Reservas · Financeiro · Pendências · Anexos · Auditoria), cancelamento com motivo/desfecho, `vw_fase_viagem`.
4. **Cadastros** — Clientes/Pessoa (tabs, pendências, atendimentos), Grupos, Fornecedores (regra de pagamento com `vigente_desde`).
5. **Financeiro** — Conciliação (recebimentos, lote só igual), Repasses, Despesas (recorrência, forma ao pagar), Fechamento (competência do mês, congela tudo).
6. **Agenda, Relatórios, Equipe, Auditoria** — pendências multi-passageiro, KPIs de resultado, convite/perfis (já existe endpoint), leitura de `auditoria` e `log_acesso` (aplicar RLS em `log_acesso`, deferido da Fase 2).

## Pendências abertas

### De especificação (regras-e-escopo-v2 §12)
- Contador: base e regime da receita bruta do MEI (§4.9).
- Decisão 17: `vencimento_fornecedor` (data-limite da operadora) fora até o usuário pedir.
- Piloto: validar fórmulas de §4.2 e a RAV (decisão 49) com três viagens reais da planilha **antes** de fechar a Fase 3.

### Deferidas da Fase 2 (revisões de task e revisão final)
- `ModulesExtensions.AddModules`: mover registro de `UsuarioService` para fora de `AddAuth` (primeira task da Fase 3).
- RLS em `log_acesso` (nada lê a tabela ainda; login insere sem `app.agencia_id`).
- Login multiagência: e-mail é único global (migration 0004); pessoa em duas agências precisa de dois e-mails.
- `EsqueciSenha` silencioso para usuário convidado sem senha definida; e-mail de convite sai após o commit (falha no Resend gera 500 com linha criada).
- Guarda de "último Dono" ignora `ativo` do alvo (caso de único Dono inativo).
- `ExecutarJob` usa `CancellationToken.None` (sem cancelamento por SIGTERM); sem teste do caminho de falha.
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
