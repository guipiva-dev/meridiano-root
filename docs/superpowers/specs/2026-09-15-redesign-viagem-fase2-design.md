# Redesign da viagem — Fase 2: detalhe da viagem

**Data:** 2026-09-15 · **Status:** aprovado em conversa
**Tela:** `/viagens/:id` (`ViagemPage`)
**Base:** Fase 1 (`docs/superpowers/specs/2026-09-14-redesign-viagem-fase1-design.md`) — mesmo vocabulário visual: cabeçalho fixo, lista densa de reservas, painel lateral fixo.
**Fora desta fase (Fase 3):** conteúdo das abas Financeiro, Pendências, Documentos, Timeline e os 6 modais de operação.

## Decisões (dono, 2026-09-15)

1. **Regressão da Fase 1 corrigida dentro desta fase** (primeira tarefa): `ReservaDetalheCard` usa classes removidas de `Reserva.module.css` (`card`, `header`, `numId`, `total`, `receitaSmall`, `body`, `group`, `eyebrow`) e renderiza sem estilo em `develop`.
2. **Estrutura igual ao formulário:** abas à esquerda, painel fixo à direita. **A aba Resumo deixa de existir**; Reservas vira a aba inicial.
3. **"Editar" é a ação principal (laranja, `business`).** "+ Adicionar reserva" vira `secondary`. "Transferir" e "Cancelar viagem…" vão para o menu "Mais ações" (`MenuAcoes`, contrato §4.4 "uma ação visível + menu").

## Diagnóstico (1366×768)

- Ações do cabeçalho em linha própria, longe do título; "Cancelar viagem…" `danger` sólido compete com "Editar".
- `Subnav` com um único item ("Viagens") entre cabeçalho e abas: ruído.
- Resumo: `FaixaResumo` quebra "Receita recebida" em 2ª linha; blocos Reservas e Passageiros repetem a aba Reservas.
- Reservas: card sem estilo (regressão); 6 botões lado a lado por reserva; "+ Adicionar reserva" laranja.
- Detalhe não tem o painel financeiro que o formulário tem.

## 1. Cabeçalho fixo

- Wrapper sticky (mesmo padrão `.topo` da Fase 1: `top: var(--topbar-h)`, fundo `--color-bg-page`, borda inferior; estático em ≤1024 px).
- Trilha `<nav aria-label="Trilha">`: "Viagens" (link `/viagens`) / código.
- `PageHeader`: título "Titular · Destino" (inalterado), meta = código, status = fase (ou "Sem reserva ativa", regra A24) + "Comissão: …" com tooltip (inalterados), subtítulo "período · tipo · N passageiros · Vendedor: X · Agente: Y" (inalterado).
- Ações: `MenuAcoes label="Mais ações"` com "Transferir" (se `viagem.transferir` e não cancelada) e "Cancelar viagem…" `tone: "danger"` (se `viagem.editar` e não cancelada); "Editar" `business` (se `viagem.editar` e não cancelada). Viagem cancelada: nenhuma ação.
- Alerta de viagem cancelada logo abaixo (inalterado).
- `Subnav` sai do detalhe (fica na lista).

## 2. Layout

Grid `minmax(0,1fr) var(--painel-viagem-w)` (≥1440) / `--painel-viagem-w-xl` (1280–1439) / 1 coluna (<1280, painel **acima** das abas, não fixo).
Painel fixo abaixo do cabeçalho: `top: calc(var(--topbar-h) + var(--topo-h, 0px) + var(--space-4))`, `--topo-h` medido por `ResizeObserver` como na Fase 1.

## 3. Painel da viagem (`PainelViagem`)

`<aside aria-label="Resumo da viagem">`, 3 blocos separados por divisor:
- **Viagem** — mesmas regras da antiga `faixaDaViagem`:
  - com `viagem.resumo`: Total cobrado · Custo das reservas · Receita da agência (+ "comissão média X %") · Comissão do vendedor (+ badge de status do repasse) · Despesas da viagem · **Resultado da viagem** (destaque, tooltip) · Receita recebida (tooltip `TOOLTIP_RECEBIDA`);
  - sem resumo e com `verValores`: Total cobrado · Custo das reservas · Receita da agência (soma das reservas ativas), sem resultado;
  - sem resumo e sem `verValores`, com `viagem.repasse` (vendedor externo, P02): "Seu repasse" com valor e status;
  - nenhum dos casos: bloco omitido.
- **Passageiros · N** — nome, "CPF · nasc. dd/mm/aaaa" quando houver (mesma regra de hoje), badge "Titular".
- **Próximas pendências** — as 2 abertas mais próximas (título [— cliente], "até dd/mm/aaaa · automática|manual · responsável", badge urgente); vazio: "Nenhuma pendência aberta nesta viagem."; botão "Ver todas" → aba Pendências.
- Valores alinhados à direita, `tabular-nums`, sem sombra.

## 4. Abas

Reservas · Financeiro (se `verValores`) · Pendências · Documentos · Timeline (se `auditoria.ver`). Contadores inalterados.
`useViagem`: aba padrão `"reservas"`; `?tab=resumo` ou ausente → Reservas; `setTab("reservas")` remove o parâmetro; `?reserva=<id>` inalterado.
`ResumoTab.tsx` e `ResumoTab.test.tsx` saem; `Bloco` e `TOOLTIP_RECEBIDA` vão para `detalhe/Bloco.tsx` (usados por Financeiro, Movimentos, Despesas).

## 5. Aba Reservas

- Aviso de crédito disponível + "Usar crédito…" acima da lista (inalterado).
- Container único (borda, raio de card) com as reservas em linha densa (ativas primeiro, canceladas no fim — inalterado).
- **`ReservaDetalheCard`** (props inalteradas):
  - `<section aria-labelledby>` com nome "Reserva N"; linha com as classes de linha densa de `Reserva.module.css`: nº · Fornecedor + serviços · Localizador · Status · Cobrado + "receita R$ x" (só `verValores`) · botão "Expandir"/"Recolher".
  - Corpo (fundo sutil): linha de leitura (Data da compra · NFSe [badge, número, "emitida em"] · Formas de pagamento · Previsão da comissão · Situação); resultado em texto (`RAV · Total da comissão · Receita da agência`, só `verValores`); bloco de cancelamento (inalterado); Serviços (`ListaServicos`, inalterado); `<details>` "Histórico de alterações" fechado por padrão, consulta só ao abrir.
  - Rodapé de ações (se `podeEditar && !cancelada` ou `onDuplicar`): "Marcar emitida"/"Voltar a em emissão" (`secondary`, loading) · "Editar" (`secondary`) · `MenuAcoes label="Mais ações da reserva"` com "Remarcar…", "NFSe…", "Duplicar" (se `onDuplicar`), "Cancelar reserva…" (`danger`). Alertas de 409/erro do "Marcar emitida" inalterados.
- Duplicar: card do formulário dentro da mesma lista (inalterado no comportamento).
- "+ Adicionar reserva" `secondary` no fim do container.
- Vazio: "Nenhuma reserva ainda. Toda viagem precisa de ao menos uma reserva." + "+ Adicionar reserva" (se pode editar).

## 6. Estados e verificação

- Carregando: skeleton no formato (cabeçalho, abas, 3 linhas, painel). Erro de carga: alerta + "Tentar de novo" (inalterado).
- Testes: `ViagemPage`, `useViagem`, `CabecalhoViagem`, `ReservasTab`, `ReservaDetalheCard`, novo `PainelViagem` (casos migrados de `ResumoTab.test`), `e2e/viagens.spec.ts` ("Cancelar reserva…" vira item do menu).
- Gates: lint, typecheck, Vitest, build, E2E `viagens` + `nova-viagem`, snapshots do styleguide inalterados, **conferência visual** em 1440/1366/1280/1024 do detalhe (Reservas aberta, cancelada, sem valores) **e do formulário da Fase 1**.
