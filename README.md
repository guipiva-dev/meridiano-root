# Meridiano

Backoffice de vendas, comissões e operação para agências de viagem de lazer. Multiempresa desde o início; piloto com uma agência (MEI).

## Repositórios

| Repo | Pasta | Conteúdo |
|---|---|---|
| `guipiva-dev/meridiano-root` | `.` (este) | Especificações, análise, design, planos, harness do Claude Code |
| `guipiva-dev/meridiano-api` | `backend/` | API .NET 10 (Minimal API, Dapper, DbUp, PostgreSQL 17) |
| `guipiva-dev/meridiano-app` | `frontend/` | React + Vite + TypeScript (Fase 3) |

`backend/` e `frontend/` são repositórios independentes, ignorados por este. Clonar os três lado a lado.

## Estado

Ver `docs/BACKLOG.md`. Resumo: especificação v2 e esqueleto do backend concluídos; design v1 congelado em 2026-09-08 (`design-v1-freeze`); Fase 3 (front + módulos) é a próxima.

## Mapa de documentos

- `regras-e-escopo-v2.md` — regras de negócio, perfis, escopo, 50 decisões registradas.
- `schema-agencia-v2.sql` — schema consolidado (as migrations em `backend/` são a versão aplicada).
- `docs/analise-arquitetural-v1.md` — análise da v1 que originou a v2 (histórico; decisões já incorporadas).
- `docs/design-system.md` — tema, paleta e evolução v1→v3.
- `docs/design-system-contrato.md` — contrato de implementação do front (componentes, escalas, estados, freeze).
- `docs/design/prototipo-v1.html` — protótipo clicável com 22 telas; PNG por tela em `docs/design/prototipo-v1/`.
- `docs/superpowers/plans/` — planos de execução por fase.
- `docs/schema-v2-smoke.mjs` — smoke test do schema com pglite.
- `CLAUDE.md` — memória do projeto para o Claude Code (stack, comandos, convenções, agentes).

## Rodar

```
cd backend && docker compose up -d && dotnet run --project src/Meridiano.Api
cd backend && dotnet test
```

Detalhes em `backend/docs/dev.md`.
