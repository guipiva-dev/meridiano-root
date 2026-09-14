# Redesign da viagem — Fase 1: Nova viagem / Edição

**Data:** 2026-09-14 · **Status:** aprovado em conversa, aguardando revisão da spec escrita
**Telas:** `/viagens/nova` e `/viagens/:id/editar` (mesmo componente `NovaViagemPage`)
**Fora desta fase:** detalhe da viagem (Fase 2: cabeçalho + Resumo + Reservas; Fase 3: Financeiro, Pendências, Documentos, Timeline, 6 modais).

## Decisões (rulings do dono, 2026-09-14)

1. **Design descongelado.** O pedido de redesenho autoriza mudar `docs/design-system-contrato.md` e `tokens.css`. Mudança principal: **laranja (`business`) marca a ação principal da tela**, continua uma vez por tela. No formulário é "Salvar viagem"; "+ Adicionar reserva" vira `secondary`. Ruling registrado no BACKLOG.
2. **Escopo em 3 fases**, cada uma com review e merge próprios.
3. **Labels, textos e nomes acessíveis podem mudar**; Vitest e Playwright atualizados no mesmo passo. Gate: E2E `nova-viagem` cronometrado (4 reservas) sem regressão de tempo (hoje 6,2 s @1280 / 7,7 s @1440).
4. **Regra de negócio nova — viagem só salva completa:** "Salvar viagem" (criar **e** editar) exige **data de ida**, **data de volta** e **ao menos 1 reserva de qualquer status** (cancelada conta). Validado no front e na API. Sem migration: colunas continuam nullable; viagens antigas incompletas só são barradas no próximo salvamento.

## Diagnóstico da tela atual (1366×768)

- Coluna única; 2 reservas com uma aberta ≈ 1950 px de altura.
- Resumo financeiro no fim da página, Salvar no topo — longe de onde se digita.
- "+ Adicionar reserva" é uma barra laranja de largura total: o elemento mais forte da tela sem ser a ação principal.
- RAV e Total da comissão são inputs `readOnly calculated`; o texto sobrepõe o selo ("R$ 0,00CALCULADO").
- Formas de pagamento quebram em 3 linhas numa coluna `span-2`.
- "Resultado desta reserva" é uma tabela vertical de ~250 px em meia largura.
- **Bug:** expandir/recolher reserva marca "Alterações não salvas" — `alternarReserva` (`useNovaViagem.ts:215`) grava `aberta` no form via `setReservas`, que suja o estado.

## Layout: área de trabalho + painel lateral fixo

```
┌ Cabeçalho fixo ────────────────────────────── estado · Fechar · [Salvar viagem] ┐
├───────────────────────────────────────────────┬─────────────────────┤
│ Bloco Viagem                                  │ Painel da viagem    │
│ Reservas (lista densa, expansão no lugar)     │ (sticky)            │
│ + Adicionar reserva                           │                     │
└───────────────────────────────────────────────┴─────────────────────┘
```

### 1. Cabeçalho e ações
- Fixo no topo da área de conteúdo (sticky, abaixo da topbar).
- Esquerda: trilha "Viagens / {código}" (link para `/viagens` e, na edição, para `/viagens/:id`), título ("Nova viagem" ou "Titular · Destino"), `StatusBadge fase_viagem`, código.
- Direita, nesta ordem: estado do salvamento inline (`● Alterações não salvas` · `Salvando…` · `✓ Salvo às HH:MM` · `Erro ao salvar`), **Fechar** (`tertiary`), **Salvar viagem** (`business`, `loading` durante `saving`, tooltip `Ctrl+S`).
- Abaixo do cabeçalho: `Alert` de conflito 409 com "Recarregar" e `Alert` de `erroBloco` — comportamento atual.
- Salvar com erros de validação: junto ao estado aparece "N campos precisam de atenção" (botão-link). Clicar leva o foco ao primeiro campo com erro, abrindo a reserva dele. A abertura automática de reserva com erro (`useNovaViagem.ts:333`) continua.

### 2. Bloco "Viagem"
Sem título de seção com descrição; rótulo discreto "Viagem". Grid de 12 colunas na coluna principal:
- Linha 1: Passageiros (span 7, chips + busca, "+ pessoa") · Destino (span 5).
- Linha 2: Tipo (span 2) · Ida (span 2) · Volta (span 2) + texto calculado "N noites" quando ambas válidas · Vendedor (span 4).
- Linha 3 (só `verResultado && vendedor.geraRepasse`): campo composto "Comissão do vendedor" com % e R$ lado a lado + helper "Sugerido: R$ X". Lógica de âncora de `useRepasseVendedor` inalterada.
- Disclosure "Ocasião e observações" (conteúdo atual).
- **Ida e Volta passam a obrigatórias** (asterisco, erro "Informe a data de ida" / "Informe a data de volta"). Volta < ida continua erro.
- Chip de passageiro em uma linha: nome · nasc. dd/mm/aaaa · N anos · badge Titular · remover. Reatribuição automática do titular inalterada.
- `AvisoViagemSemelhante` fica logo acima do bloco, só na criação (regra A05 inalterada).

### 3. Reservas — lista densa com expansão no lugar
Container único "Reservas · N" (sem card por reserva). Cada reserva é uma `<section aria-labelledby>` com nome "Reserva N" (preserva `getByRole("region", { name: "Reserva N" })`).

**Linha recolhida** (grid alinhado entre linhas):
`nº | Fornecedor (forte) + serviços (secundário) | Localizador (mono) | Status | Cobrado (dir., tabular) | Receita (dir., secundária) | botão Expandir/Recolher`
- Marcador de erro (ícone + texto acessível "com erro") quando a reserva tem erro e está recolhida.
- Cancelada: linha esmaecida, badge Cancelada; ordem atual mantida.

**Corpo expandido** (fundo `--color-bg-subtle`, sob a própria linha):
- A: Fornecedor (span 4, "+ novo") · Localizador (span 3, aviso de duplicado como helper de atenção do campo) · Data da compra (span 2) · NFSe (span 3).
- B: Serviços vendidos — chips em uma linha (quebra só se faltar largura).
- C: Total da reserva · Total cobrado do cliente · Comissão (%) · Comissão (R$) · Taxa de serviço — 5 campos numa linha. Helpers "Sugerido: X %" e o da taxa mantidos (taxa vira tooltip para não quebrar a linha).
- D: linha de resultado **em texto** (não input): `RAV R$ x · Total da comissão R$ y · Receita da agência R$ z`, com tooltips atuais. Remove os dois `MoneyInput calculated` de `FinancialFields`.
- E: Formas de pagamento (chips inline) · disclosure "Mais detalhes" (Do total, quanto é taxa; Observações) · **Remover reserva** alinhado à direita, `tertiary` com texto de perigo. Some em reserva cancelada.
- Lógicas preservadas sem mudança: âncora %/R$ da comissão, venda sugerida = total (A03), `comissaoSugerida`, `fornecedorTocado` (A04), erros ao vivo após primeira tentativa (ALT-01), `readOnly` de cancelada, Tab de "Total da reserva" cai em "Total cobrado do cliente".

**Fim da lista:** "+ Adicionar reserva" (`secondary`, dica `Ctrl+Enter`).
**Vazio:** "Nenhuma reserva ainda. Toda viagem precisa de ao menos uma reserva: fornecedor, localizador e valores." + botão "+ Adicionar reserva". Após tentativa de salvar sem reserva, o texto vira erro (`--color-danger`) e recebe o foco.

`ReservationCard` continua o componente do formulário e continua reutilizado por `ReservasTab` (duplicar reserva no detalhe) — o novo visual precisa funcionar isolado (sem a lista) nesse contexto até a Fase 2.

### 4. Painel lateral fixo
Sticky, largura por breakpoint (§5). Substitui `TripSummary` na página; `somarReservas`/`comissaoMedia` reaproveitados.
- **Viagem:** Total cobrado · Custo das reservas · Receita da agência (+ "comissão média X %") · Comissão do vendedor · Despesas da viagem; divisor; **Resultado da viagem** em destaque (`MoneyValue emphasis="result"`, tooltip atual).
- Incompleta (alguma reserva ativa sem total cobrado): resultado "—" + "Preencha o total cobrado da Reserva N".
- Sem `viagem.ver_resultado`: só Total cobrado, Custo e Receita (regra atual).
- **Reserva aberta:** título "Reserva N · Fornecedor" + `ResultSummary` compacto (mesmo cálculo). Nenhuma aberta: "Abra uma reserva para ver o cálculo".
- Rodapé do painel: atalhos `Ctrl+S` salvar · `Ctrl+Enter` adicionar reserva · `Esc` recolher · `Ctrl+K` buscar. O rodapé `.rodape` da página sai.

### 5. Responsividade
- ≥ 1440: coluna principal até ~1000 px + painel 340 px.
- 1280–1439: painel 300 px.
- < 1280: painel vira **barra fixa inferior** (Total cobrado · Receita · Resultado), mesmo nó do DOM reposicionado por CSS. "Salvar viagem" continua só no cabeçalho, que já é fixo — sem duplicar a ação laranja nem o nome acessível. O cálculo detalhado da reserva fica fora; a linha de resultado em texto do corpo da reserva (§3 D) cobre.
- < 1024 (tablet): grids do bloco e do corpo passam a 6 colunas; linha recolhida esconde Localizador e Receita.

### 6. Estados
- **Carregando (edição):** skeleton no formato do layout (cabeçalho, bloco, 2 linhas de reserva, painel), sem mudança de altura ao chegar o dado.
- **Salvamento:** máquina `useSalvamento` inalterada, apenas reposicionada (§1). Toast não é usado no salvar.
- **Erros:** mapa `codigo`→campo (`mapaErros.ts`) inalterado + novos códigos da §7. 409 = alerta com Recarregar. Demais = `erroBloco`.
- **Guarda de saída suja:** `Page dirty` inalterado — após a correção do bug, expandir/recolher não suja mais.

## 7. Regra "viagem só salva completa"

**Front (`useNovaViagem.validar`, `validarReserva`):**
- `dataIda` vazia → erro `dataIda` "Informe a data de ida"; `dataVolta` vazia → `dataVolta` "Informe a data de volta".
- Nenhuma reserva no form (qualquer status) → erro `reservas` "Adicione ao menos uma reserva", exibido no estado vazio da lista (§3) e contado em "N campos precisam de atenção".

**API (`ViagensService`):**
- `ValidarCabecalho`: `DataIda is null` → `RegraDeNegocioException("data_ida_obrigatoria", "Informe a data de ida")`; `DataVolta is null` → `("data_volta_obrigatoria", "Informe a data de volta")`. Vale para `CriarAsync` e `AtualizarAsync`.
- `CriarAsync`: `req.Reservas` vazio → `("reserva_obrigatoria", "Adicione ao menos uma reserva")`, antes de qualquer insert.
- `AtualizarAsync`: o PUT não envia reservas canceladas, então a checagem é no banco, depois de gravar as reservas do payload e antes de confirmar: `select count(*) from reserva where viagem_id = @id and agencia_id = @agencia and excluido_em is null` = 0 → mesmo `reserva_obrigatoria` (transação desfeita).
- Não se aplica a: operações de reserva (cancelar, remarcar, NFSe, usar crédito), `AdicionarReservaAsync`, cancelar/transferir viagem.
- `mapaErros.ts`: `data_ida_obrigatoria`→`dataIda`, `data_volta_obrigatoria`→`dataVolta`, `reserva_obrigatoria`→`reservas`.
- `regras-e-escopo-v2.md` ganha a regra; BACKLOG registra o ruling.
- Testes de integração existentes que criam/editam viagem sem datas ou sem reserva são ajustados (helpers de teste passam a enviar datas e uma reserva). Novos testes: 422 para cada código, criar e editar; editar viagem com todas as reservas canceladas continua permitido.

## Componentes afetados

| Arquivo | Mudança |
|---|---|
| `pages/viagens/NovaViagemPage.tsx` + `.module.css` | layout 2 colunas, cabeçalho fixo, painel, barra inferior |
| `pages/viagens/DadosViagemSection.tsx` | bloco compacto, Ida/Volta obrigatórias, noites, comissão do vendedor composta |
| `pages/viagens/useNovaViagem.ts` | validação nova, `alternarReserva` sem sujar, foco no primeiro erro |
| `pages/viagens/mapaErros.ts` | 3 códigos novos |
| `components/Reserva/ReservationCard.tsx`, `BookingFields.tsx`, `FinancialFields.tsx`, `Reserva.module.css` | linha densa + corpo expandido; resultado em texto |
| `components/Reserva/ResultSummary.tsx` | variante compacta para o painel (usado também em `ReservaDetalheCard` — não quebrar) |
| `components/Viagem/TripSummary.tsx` → painel lateral | substituído na página; `somarReservas`/`comissaoMedia` mantidos |
| `components/Viagem/PassageirosField.tsx` | chip em uma linha |
| `components/shell/PageHeader` | só se o sticky/trilha exigir; avaliar impacto nas demais telas |
| `docs/design-system-contrato.md`, `styles/tokens.css` | regra do laranja, tokens do painel se necessários |
| `backend/.../ViagensService.cs` + testes | regra §7 |
| `e2e/nova-viagem.spec.ts`, Vitest co-locados | seletores e fluxo |

## Verificação

- `npm run lint`, `npm run build`, Vitest completo verde.
- `dotnet format --verify-no-changes`, `dotnet build -c Release`, `dotnet test` verde.
- Playwright `nova-viagem` (e `viagens` por causa do duplicar no detalhe) verde, tempo ≤ atual @1280 e @1440.
- Revisão visual com screenshot em 1920, 1440, 1366, 1280 e 1024: nova vazia, nova com 4 reservas, edição com cancelada, erro de validação, conflito 409, perfil sem `viagem.ver_resultado`.
- Teclado: Tab order bloco → reservas → adicionar; `Ctrl+S`, `Ctrl+Enter`, `Esc`; foco visível em tudo.
