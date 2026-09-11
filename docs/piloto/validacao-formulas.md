# Piloto §12 — validação das fórmulas (3 viagens reais)

Fonte: planilha da agência, aba/linhas ___ (não copiada para o repo). Fórmulas: `docs/relatorios-formulas.md`, spec §4.2, decisão 49.
Ambiente: stack local (`docker compose` + imagem integrada `meridiano:smoke`), agência criada por `scripts/bootstrap-agencia.sql` (ruling "piloto local", 2026-09-11).

Preencher a primeira tabela **antes** de lançar (R10 do plano da Fase 4).

| Viagem | Reserva | Fornecedor | Venda (planilha) | Custo/valor operadora (planilha) | % comissão | RAV (planilha) | Taxa serviço | Receita prevista (planilha) |
|---|---|---|---|---|---|---|---|---|
| V1 | R1 | | | | | | | |
| V2 | R1 | | | | | | | |
| V2 | R2 | | | | | | | |
| V3 | R1 | | | | | | | |

## Depois de lançar (mesmo dia)

| Viagem | `receita_prevista` tela | `valor_esperado_operadora` tela | Relatório (competência, mês) | Bate? | Divergência / ruling |
|---|---|---|---|---|---|
| V1 | | | | | |
| V2 | | | | | |
| V3 | | | | | |

Regra: divergência nunca se resolve "ajustando a planilha". Ou é defeito (→ BACKLOG, plano 4.1) ou é regra de negócio nova (→ ruling numerado aqui e em `regras-e-escopo-v2.md` §4.2).
