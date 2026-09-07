# Backlog de configuração — viva-erp

Pendências do setup baseado no [vibe-coding-toolkit](https://github.com/soumatheusgomes/vibe-coding-toolkit).
Marque cada item ao concluir. Última revisão: 2026-09-07.

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

## Concluído em 2026-09-07 (parte 2)

- [x] Stack definida (`regras-e-escopo-v2.md` §11) e `CLAUDE.md` preenchido: stack, comandos canônicos, convenções, tabela de agentes do domínio (item 1 abaixo)
- [x] `git init`, branch `main`, commit inicial com specs v2, análise e plano da Fase 2 (item 2 abaixo)
- [x] Nome do software: **Meridiano** (solution `Meridiano.sln`)

## Bloqueador

Nenhum de configuração. Próximo passo: executar `docs/superpowers/plans/2026-09-07-fase-2-esqueleto.md` em ondas. **Docker Desktop** ainda não está instalado nesta máquina — sem ele, os testes de integração (Testcontainers) e o Postgres local só rodam no CI.

## Pendências, em ordem

### 1. Definir a stack e preencher o `CLAUDE.md`

Substituir os `[PLACEHOLDER]` restantes:

- Seção **Stack** — linguagens, frameworks, gerenciador de pacotes.
- Seção **Canonical commands** — os seis comandos (install, lint, typecheck, test, build, run/dev).
- Seção **Conventions** — estilo de import, convenções de teste, formatação, tratamento de erro.
- **Tabela de agentes especialistas** — hoje é o roster genérico do template. Ajustar ao domínio ERP: fiscal, estoque, financeiro, integrações. Roster completo de referência em [`docs/tools/02-subagent-orchestration.md`](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/tools/02-subagent-orchestration.md).

### 2. `git init`

Sem repositório Git, a regra de ondas paralelas não funciona — ela depende de commit por task e de capturar o HEAD antes de cada commit. O `command-proxy.mjs` também só compacta `git status`/`log`/`diff` quando existe um repo (hoje cai em fail-open).

### 3. Quality gates — ESLint + Biome

Só se aplica se a stack for JavaScript/TypeScript. Se for outra linguagem, o equivalente é o linter nativo dela, com a mesma disciplina de warn→error.

Caminho rápido, cola no agente:

```
Leia https://raw.githubusercontent.com/soumatheusgomes/vibe-coding-toolkit/main/docs/prompts/08-eslint-quality-gates-install.md
e execute o prompt que está nesse arquivo neste projeto. Use MAX_LINES=350.
```

Depois, para quebrar arquivos acima do teto: mesmo formato, com [`09-file-size-refactor.md`](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/prompts/09-file-size-refactor.md).

Divisão deliberada: Biome fica com um conjunto pequeno e curado de regras; ESLint cobre o que precisa de informação de tipo e as regras de framework. Sobreposição entre os dois é custo, não segurança.

### 4. Pelo menos uma regra em modo warn→error

Regra nova nasce em `"warn"` para a base inteira, a contagem de violações vira número rastreável, e só sobe para `"error"` quando chega a zero. Para zerar sem virar refactor silencioso, usar o prompt [ESLint warning burndown](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/prompts/02-eslint-warning-burndown.md).

### 5. Sistema de memória leve

`MEMORY.md` na raiz (índice, teto de ~130 linhas) mais uma pasta de arquivos de tópico com frontmatter `type: feedback | architecture | business-rule | reference`. Zero dependência externa.

Critério para salvar: uma sessão futura ficaria surpresa e grata de saber disso antes de começar? Se não, não salva.

Prompt pronto: [Memory bootstrap](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/prompts/06-memory-bootstrap.md). Detalhes: [Sistema de memória do Claude](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/tools/09-claude-memory-system.md).

### 6. Rodar o fluxo completo uma vez, ponta a ponta

brainstorm → plano → implementação em ondas paralelas → revisão multi-agente → commit.

Usar a primeira feature real do ERP como cobaia. É o item que valida se todo o resto foi configurado direito — o playbook trata isso como a parte mais importante, não como formalidade.

## Opcional, adiar até doer

- **Vault Obsidian + servidor MCP** — segunda camada de memória, sem limite de tamanho. Só quando o `MEMORY.md` passar de ~130 linhas e começar a virar ruído. Ver [Obsidian como memória](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/tools/08-obsidian-memory.md).
- **Sanitização de projeto** — passada de limpeza que mede antes de agir. Bom segundo prompt, depois que o fluxo da Parte 4 já for rotina: [`01-project-sanitation.md`](https://github.com/soumatheusgomes/vibe-coding-toolkit/blob/main/docs/prompts/01-project-sanitation.md).
- **Ampliar o `command-proxy.mjs`** — hoje cobre `git status`, `git log`, `git diff` e `git diff --staged/--cached` nus. Adicionar outros comandos de leitura só quando houver evidência de que a saída bruta está custando contexto de verdade. Escape hatch atual: prefixo `command `.
