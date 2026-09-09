# Backlog de configuração — Meridiano

Pendências do setup baseado no [vibe-coding-toolkit](https://github.com/soumatheusgomes/vibe-coding-toolkit).
Marque cada item ao concluir. Última revisão: 2026-09-08. Backlog do produto em `docs/BACKLOG.md`.

## Concluído

- [x] Claude Code 2.1.263 instalado e autenticado
- [x] Plugins: superpowers 6.3.0, ponytail 4.9.0, caveman, aia-harness, hookify, pr-review-toolkit, commit-commands, claude-code-setup, feature-dev, code-review, claude-md-management, ui-ux-pro-max
- [x] Graphify 0.9.55 instalado, MCP registrado em `~/.claude.json`
- [x] agent-browser 0.36.0 instalado (`agent-browser install` ok)
- [x] `.claude/settings.json` com hooks reais escritos e testados
- [x] `.claude/hooks/command-proxy.mjs` — proxy RTK self-contained, fail-open, selftest passando
- [x] `.claude/hooks/session-banner.mjs` — banner de branch
- [x] `.claude/rules/parallel-subagent-driven-development.md` copiado e referenciado no `CLAUDE.md`
- [x] `python3.exe` criado em `%LOCALAPPDATA%\Programs\Python\Python314\` — corrige o hookify, que chamava o stub da Microsoft Store
- [x] Stack definida (`regras-e-escopo-v2.md` §11) e `CLAUDE.md` preenchido: stack, comandos canônicos, convenções, tabela de agentes do domínio
- [x] Nome do software: **Meridiano** (solution `Meridiano.sln`)
- [x] Git: três repositórios (root, `backend/`, `frontend/`) com autor `guilhermepiva@hotmail.com`, remotos em `guipiva-dev/meridiano-{root,api,app}`, branches `develop` e `main` mantidas iguais (merge feature→develop, ff main)
- [x] .NET SDK 10.0.400, Docker Desktop 4.90 + WSL instalados. Testcontainers roda localmente (engine pausa quando ocioso: reabrir Docker Desktop e aguardar `docker info` antes de `dotnet test`)
- [x] Fluxo completo rodado ponta a ponta na Fase 2: brainstorm → plano em ondas → implementação por subagentes → revisão por task + revisão final → commits pelo controlador (ledger em `.superpowers/sdd/`, git-ignored)
- [x] Quality gate backend: `dotnet format --verify-no-changes` + `TreatWarningsAsErrors=true` + CI no GitHub Actions (`backend/.github/workflows/ci.yml`)
- [x] Memória persistente do Claude Code em `~/.claude/projects/E--workspace-viva-erp/memory/` (substitui o `MEMORY.md` na raiz proposto pelo playbook)

## Bloqueador

Nenhum. Próximo passo: escrever `docs/superpowers/plans/<data>-fase-3-*.md` em ondas e executar.

## Pendências, em ordem

### 1. Quality gates do frontend (primeira task do scaffold da Fase 3) — concluído 2026-09-08

ESLint strictTypeChecked + jsx-a11y e Biome (formatação), sem sobreposição, mais `scripts/check-tokens.mjs` (proíbe hex/`px` fora de `tokens.css`, valida breakpoints 700/1024/1280/1366/1440). `npm run lint` no CI do `frontend/`. Feito no subplano 3.1 (`frontend/.github/workflows/ci.yml`, `frontend/eslint.config.*`, `frontend/biome.json`).

### 2. CI do frontend e do root — concluído 2026-09-08

`frontend/.github/workflows/ci.yml`: `npm ci`, lint, typecheck, test, build, e Playwright da `/styleguide` (job `e2e`, contra Chromium headless). Root: sem validação de links de docs — adiada, sem evidência de necessidade ainda.

### 3. Playwright — concluído 2026-09-08

`e2e/styleguide.spec.ts` com baseline de regressão visual (win32 local + linux, este último rodando no CI). `e2e/login.spec.ts` escrito mas fora do CI (precisa de API + seed). Tela Nova viagem (risco número um) fica para o subplano 3.2.

## Opcional, adiar até doer

- **Vault Obsidian + servidor MCP** — só quando a memória do Claude passar de ~130 linhas de índice.
- **Sanitização de projeto** — [`01-project-sanitation.md`](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/prompts/01-project-sanitation.md), depois da Fase 3.
- **Ampliar o `command-proxy.mjs`** — hoje cobre `git status`, `git log`, `git diff` nus. Só com evidência de custo de contexto. Escape hatch: prefixo `command `.
