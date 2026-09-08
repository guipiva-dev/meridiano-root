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

### 1. Quality gates do frontend (primeira task do scaffold da Fase 3)

ESLint (type-aware + regras React) e Biome (formatação + conjunto pequeno de regras), sem sobreposição. Teto de 350 linhas por arquivo. Regra nova nasce em `warn`, sobe para `error` ao zerar. Adicionar `npm run lint` ao CI do `frontend/`.

Prompt pronto: [08-eslint-quality-gates-install.md](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/prompts/08-eslint-quality-gates-install.md) com `MAX_LINES=350`. Burndown: [02-eslint-warning-burndown.md](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/prompts/02-eslint-warning-burndown.md).

Lint de design (contrato §5): proibir cor hex e `px` fora de `tokens.css` — regra ESLint/Biome ou grep no CI.

### 2. CI do frontend e do root

- `frontend/.github/workflows/ci.yml`: `npm ci`, lint, typecheck, build, Playwright cronometrado da tela Nova viagem (contrato §7).
- Root: opcional, só validar links dos docs.

### 3. Playwright

Poucos testes, cronometrados, começando pela tela de lançamento (risco número um, spec §14). Instalar junto com o scaffold.

## Opcional, adiar até doer

- **Vault Obsidian + servidor MCP** — só quando a memória do Claude passar de ~130 linhas de índice.
- **Sanitização de projeto** — [`01-project-sanitation.md`](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/prompts/01-project-sanitation.md), depois da Fase 3.
- **Ampliar o `command-proxy.mjs`** — hoje cobre `git status`, `git log`, `git diff` nus. Só com evidência de custo de contexto. Escape hatch: prefixo `command `.
