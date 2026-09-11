# Meridiano

> Project memory for Claude Code. Keep this file short and high-signal.

Backoffice de vendas, comissões e operação para agências de viagem de lazer. Multiempresa desde o início. Piloto: uma agência (MEI).

**Especificações (fonte de verdade, nesta ordem):** `regras-e-escopo-v2.md` · `schema-agencia-v2.sql` · `docs/analise-arquitetural-v1.md`. Produção: `docs/deploy.md` (runbook). Design congelado (2026-09-08): `docs/design-system-contrato.md` (regras) · `docs/design/prototipo-v1.html` (22 telas) · `frontend/src/styles/tokens.css` (tokens). Planos em `docs/superpowers/plans/`; estado e pendências em `docs/BACKLOG.md`.

**Estado (2026-09-11):** Fase 1 (spec v2) ✓ · Fase 2 (esqueleto .NET, migrations 0001–0011) ✓ · Design v1 congelado (tag `design-v1-freeze`) ✓ · Fase 3 (3.0–3.6: front + todos os módulos, migrations 0012–0016; Playwright `nova-viagem`/`viagens`/`cadastros`/`financeiro`/`operacao`; E2E 4 reservas 6,2 s @1280 / 7,7 s @1440) ✓ código — **fecha só com** teste de UX §7 e piloto §12 (humanos) · **Fase 4 (piloto) em andamento** — plano `docs/superpowers/plans/2026-09-11-fase-4-piloto.md`: onda 0 ✓ mergeada em `main`=`develop` (migration 0017 fecha PostgREST do Supabase, `scripts/bootstrap-agencia.sql`, `ci.yml` GHCR + `az containerapp update`, `backup.yml` pg_dump → R2). Ruling: **piloto local antes da nuvem** — imagem integrada, bootstrap, jobs e drill de restore validados no compose (achados em `docs/BACKLOG.md` "Achados do piloto local"). **Reviews externos (4 rodadas back + 3 front) aplicados 2026-09-11** — backend `main` `e52d035`, frontend `main` `7de4f73`, root `176f90b`, **sem push**: migration 0018 (`senha_alterada_em`, `sessao_usuario`, `data_protection_key`), `/clientes/busca` por visibilidade, cursor composto da auditoria, expurgo de soft-deleted, HtmlEncoder + timeout Resend, labels OCI na imagem; front: respostas stale, invalidação de listas, `chaveLocal`, ErrorBoundary, filtros/token fora da URL, timeout 30 s, Space/scroll lock. Rejeitados com motivo em BACKLOG "Reviews externos". 265 API + 30 domínio, 498 Vitest. Runbook `docs/deploy.md` escrito (smoke local feito, nuvem não). Pendente: T5 (3 viagens da planilha + tempo humano, templates em `docs/piloto/`), T3 (nuvem), T4 (smoke em produção), T6 (fechamento). Migrations 0001–0018.

## Behavioral guidelines

1. **Think before coding** — state assumptions explicitly. If multiple interpretations exist, present them instead of picking silently. Say so when a simpler approach exists. If something is genuinely unclear, stop and ask.
2. **Simplicity first** — minimum code that solves the problem. No speculative features, no abstractions for single-use code, no unrequested configurability, no error handling for impossible scenarios.
3. **Surgical changes** — touch only what the request requires. Match existing style. Don't refactor, reformat, or "improve" adjacent code that wasn't part of the request.
4. **Goal-driven execution** — turn tasks into verifiable goals (e.g. "fix the bug" becomes "write a test that reproduces it, then make it pass"). For multi-step work, state a brief plan with a verify check per step, then loop until every step is verified.
5. **Orchestrator, not implementer** — the main session plans, decides, and coordinates; it does not implement. Delegable implementation and analysis goes to a specialist subagent, dispatched in parallel when task scopes don't conflict.

## Stack

- **API:** C# / .NET 10 LTS · ASP.NET Core Minimal API · Dapper + Npgsql · DbUp (migrations SQL embutidas) · Serilog · auth própria (cookie HttpOnly + `PasswordHasher`).
- **Banco:** PostgreSQL 17. RLS de tenant por `app.agencia_id`; role da API `meridiano_api` sem ownership/BYPASSRLS.
- **Front (Fase 3):** React + Vite + TypeScript, build servido pela API em `wwwroot/`.
- **Infra:** Azure Container Apps (API + Jobs cron) · Supabase free só como Postgres · Cloudflare R2 · Resend · GitHub Actions.
- **Testes:** xUnit · Testcontainers.PostgreSql (exige Docker) · Playwright (poucos, cronometrados).

Proibido: EF Core, MediatR, CQRS, AutoMapper, Repository pattern, fila, Redis, microserviços.

## Canonical commands

Always use the exact commands here — don't guess.

- **Install:** `cd backend && dotnet restore`
- **Lint:** `cd backend && dotnet format --verify-no-changes`
- **Typecheck:** `cd backend && dotnet build -c Release` (`TreatWarningsAsErrors=true`)
- **Test:** `cd backend && dotnet test` (Docker precisa estar rodando; se o engine pausou, reabrir Docker Desktop e aguardar `docker info`)
- **Build:** `cd backend && dotnet publish src/Meridiano.Api -c Release -o out`
- **Run/Dev:** `cd backend && docker compose up -d && dotnet run --project src/Meridiano.Api`
- **Front (Fase 3, após scaffold):** `cd frontend && npm install` · `npm run dev` · `npm run lint` · `npm run build` · `npx playwright test e2e/styleguide.spec.ts`
- **Smoke do schema:** copiar `docs/schema-v2-smoke.mjs` para uma pasta com `@electric-sql/pglite` e rodar `node test.mjs` (imprime `ALL OK`)
- **Job:** `cd backend && dotnet run --project src/Meridiano.Api -- job <nome>`

## Repositórios

Três repositórios git independentes (não são submodules):

```
viva-erp/            root: specs, docs, harness (.claude), planos — este repo
  backend/           Meridiano.sln (.NET) — repo próprio, ignorado pelo root
  frontend/          React + Vite — repo próprio, ignorado pelo root (Fase 3)
```

## Solution (backend/)

```
src/Meridiano.Api      host: Program.cs (nunca editar; stubs em extension methods), Auth/, Infra/, Jobs/, Modules/<Modulo>/
src/Meridiano.Domain   regras puras (Perfil, Permissao, cálculos). Sem dependência de banco.
src/Meridiano.Data     Migrator (DbUp), Migrations/*.sql, Sessao/DbSessao (contexto de tenant)
tests/Meridiano.Domain.Tests   unidade
tests/Meridiano.Api.Tests      integração (Testcontainers), coleção xUnit "db"
```

## Conventions

- Português nos nomes de domínio, banco, endpoints e mensagens. Inglês só em termos técnicos consagrados.
- Toda query em tabela de tenant roda dentro de `DbSessao` (define `app.agencia_id`, `app.usuario_id`, `app.motivo`). Nunca `NpgsqlConnection` solta, exceto login, migrations e `job_execucao`.
- Toda query Dapper filtra `agencia_id` e `excluido_em is null`; a policy RLS é rede de segurança, não substituto.
- Enums como `text` + `check` no banco; no C#, enum + `ParaBanco()`/`DoBanco()` em snake_case.
- Dinheiro `numeric(12,2)`, sempre BRL. Datas de serviço `timestamp` sem fuso; carimbos `timestamptz`.
- Erros: `RegraDeNegocioException(codigo, mensagem)` → 422; `ConflitoConcorrenciaException` → 409; ProblemDetails com extensão `codigo`.
- Concorrência otimista por `xmin::text` (`versao` no DTO).
- Autorização no C#: `.RequerPermissao(Permissao.X)`; DTO não contém campo que o perfil não pode ver.
- Um módulo = pasta `Modules/<Modulo>/` com `Endpoints.cs`, `Dtos.cs`, `<Modulo>Service.cs`. Vertical slice, não camadas técnicas.
- Testes: unidade para cálculo; integração com Postgres real para tenant/permissão/concorrência. Sem mock de banco.
- Commits: Conventional Commits em inglês (`feat(auth): ...`), com rodapé de atribuição da sessão.

## Specialist agent routing table

When work is delegable, dispatch the specialist that matches the task instead of a generic agent.

| Agent | When to use |
|---|---|
| `backend-specialist` | Endpoints, serviços de módulo, queries Dapper, migrations. Default para tasks de `src/`. |
| `database-architect` | Mudança em `schema-agencia-v2.sql`/migrations, índices, policies RLS, views financeiras. |
| `test-engineer` | Testes de integração com Testcontainers, cobertura de tenant/permissão/concorrência. |
| `security-reviewer` | Qualquer diff em `Auth/`, RLS, tokens, cookies, log de acesso a documento (LGPD). |
| `code-reviewer` | Revisão de toda task antes do commit pelo controlador. |
| `frontend-specialist` | `frontend/` (React) — Fase 3 em diante. Tela de lançamento é o risco número um: teclado, pré-preenchimento, tempo medido. |

## Rules

- @.claude/rules/parallel-subagent-driven-development.md — when dispatching several implementers in the same wave is safe, and who commits.

## Hooks

- `PreToolUse` (Bash) → `.claude/hooks/command-proxy.mjs` — rewrites bare `git status`/`log`/`diff` to compact equivalents. Bypass with `command <cmd>`.
- `SessionStart` → `.claude/hooks/session-banner.mjs` — one-line branch banner.
- Both fail open: any error lets the original command run.
