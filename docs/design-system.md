# Meridiano — Design System v1

Tema e padrão visual do software. Tokens em `frontend/src/styles/tokens.css` (fonte da verdade para código). Este documento explica as decisões e as regras de uso.

Direção: **moderno, limpo, agradável; backoffice denso operado o dia todo, com teclado.** Laranja e azul-escuro da marca; neutros puxados para o navy para o cinza parecer escolhido, não herdado.

## 1. Paleta

### Cores da marca (fornecidas) e papel de cada uma

| Cor | Hex | Papel | Onde |
|---|---|---|---|
| Navy | `#29235c` | **Identidade e estrutura.** Sidebar, títulos de página, ink forte | `--heading`, `--sidebar-bg` |
| Azul | `#0672b9` | **Ação primária.** Botões principais, links, foco | `--primary` |
| Azul claro | `#5396d1` | **Informação.** Anel de foco, ícones informativos, status "a receber", gráficos | `--info`, `--focus-ring` |
| Laranja | `#e18334` | **Destaque operacional.** CTA de lançamento, item ativo da sidebar, indicador de atenção | `--accent`, `--sidebar-active` |
| Amarelo | `#f9b233` | **Ênfase sobre navy.** Badges na sidebar, contadores, marcadores em fundo escuro | `--emphasis` |
| Amarelo claro | `#fbf297` | **Realce suave.** Linha selecionada, aviso brando, campo pré-preenchido pendente de confirmação | `--highlight` |

Derivadas (não são da marca, existem por contraste): `#055c95` hover do azul; `#b8631f` laranja para texto; `#1b1740`/`#3b3478` navy escuro/claro; tints `#e3effa`, `#fbe7d5`, `#fefbe4`.

### Regras de contraste (WCAG AA, texto ≥ 4,5:1)

- `#0672b9` sobre branco = 4,9:1 → **pode** ser texto e ícone.
- `#29235c` sobre branco = 12,6:1 → texto sempre.
- `#5396d1` sobre branco = 3,2:1 → **nunca** texto pequeno; só bordas, ícones ≥ 24px, foco, preenchimento de gráfico.
- `#e18334` sobre branco = 2,9:1 → **nunca** texto sobre claro; como fundo de botão use texto branco (2,9:1 — abaixo de AA para texto normal, por isso botão accent é reservado a rótulos curtos em **peso 700 e ≥ 14px**, que atingem AA para texto grande/bold). Para texto laranja use `#b8631f` (5,0:1).
- `#f9b233` e `#fbf297` sobre branco → **nunca** texto. Amarelo `#f9b233` sobre navy `#29235c` = 8,7:1 → excelente para badge na sidebar.
- Texto sobre `#fbf297` usa `--text` (`#1e1b3a`, 13:1).

### Estados (separados da cor de marca)

| Estado | Cor | Fundo suave |
|---|---|---|
| Sucesso / conciliada / quitada | `#1f9d63` | `#dcf5e8` |
| Erro / cancelada / atrasada | `#d64545` | `#fbe2e2` |
| Atenção / a receber (vencendo) | `#e18334` | `#fefbe4` |
| Informação / em emissão | `#5396d1` | `#f1f7fd` |
| Neutro / sem reserva / bloqueado | `#6b6f8a` | `#eef0f6` |

Fases da viagem (spec §6) mapeiam assim: `sem_reserva` neutro · `em_emissao` info · `confirmada` primário · `em_viagem` accent · `concluida` sucesso · `cancelada` erro; `a_receber` info · `parcial` atenção · `atrasada` erro · `quitada` sucesso.

### Modo escuro

Fora da v1. A camada semântica dos tokens já isola as decisões; quando entrar, só a seção "Semânticos" de `tokens.css` ganha um bloco `[data-theme="dark"]`.

## 2. Tipografia

- **UI:** Manrope (Google Fonts), pesos 400/500/600/700. Geométrica, moderna, boa em tamanhos pequenos; algarismos tabulares disponíveis.
- **Códigos:** JetBrains Mono, peso 400/500 — localizadores, códigos de viagem (`VG-2026-0001`), CPF, número de bilhete, tokens. Monospace evita confundir `0`/`O`, `1`/`l` em códigos que a agência digita de portais.
- Fallback: `"Segoe UI", system-ui` (Windows é o desktop da piloto).

Escala (rem sobre 16px):

| Token | Tamanho | Uso |
|---|---|---|
| `--text-xs` | 12 | rótulos de campo, eyebrows em caixa alta com `letter-spacing: 0.04em` |
| `--text-sm` | 13 | células de tabela, formulários densos |
| `--text-md` | 14 | corpo padrão |
| `--text-lg` | 16 | título de seção / card |
| `--text-xl` | 20 | título de página (peso 700, cor navy) |
| `--text-2xl` | 26 | número de destaque em tile |

Dinheiro sempre com `font-variant-numeric: tabular-nums`, alinhado à direita, formato `R$ 10.500,00`. Negativo em `--danger`. Percentual com uma casa (`12,5 %`).

## 3. Espaço, forma, sombra

- Grid de **8px** (`--sp-*`), meio passo de 4px para dentro de componentes.
- Raio: 4px em inputs e badges, 8px em botões e menus, 12px em cards. Nada de "arredondado em tudo".
- Sombra só em elementos flutuantes (menu, popover, modal, toast). Cards e tabelas usam **borda** `--border`, não sombra.
- Densidade: linha de tabela 36px, input 36px, botão 36px (30px na variante pequena). Padding de card 20px.
- Ícones: Lucide, 16px em linha, 20px em navegação, traço 1,75.

## 4. Layout da aplicação

```
┌─ sidebar 232px (navy) ─┬─ topbar 52px: busca global (Ctrl+K) · agência · usuário ─┐
│ logo                   │ título da página · ações à direita                        │
│ Viagens  ◄ ativo       │                                                           │
│ Clientes               │ conteúdo em --bg (#f6f7fb), largura máx. 1440px           │
│ Fornecedores           │ cards e tabelas em --surface (#fff) com borda             │
│ Financeiro             │                                                           │
│ Agenda      ● 3        │                                                           │
│ Relatórios             │                                                           │
│ ─────                  │                                                           │
│ Admin                  │                                                           │
└────────────────────────┴───────────────────────────────────────────────────────────┘
```

- Sidebar navy; item ativo com barra laranja de 3px à esquerda e texto branco; hover `--sidebar-hover`; contador em badge amarelo.
- Topbar branca com borda inferior; busca global sempre visível, atalho `Ctrl+K`.
- Página: título 20px navy à esquerda, ações primárias à direita na mesma linha. Nada de hero.
- Em telas < 1024px a sidebar colapsa para ícones; < 768px (PWA no celular) vira menu inferior com 4 itens: Viagens, Agenda, Busca, Mais.

## 5. Componentes

### Botões

| Variante | Fundo | Texto | Hover | Uso |
|---|---|---|---|---|
| Primário | `--primary` | branco | `--primary-hover` | ação principal da tela (Salvar, Confirmar) |
| Accent | `--accent` | branco, 700 | `--accent-hover` | **um por tela**: "Nova viagem", "Lançar reserva". É o botão laranja. |
| Secundário | `--surface` + borda | `--heading` | `--surface-2` | ações comuns |
| Ghost | transparente | `--heading` | `--surface-2` | ações em tabela, cancelar |
| Perigo | `--surface` + borda `--danger` | `--danger` | `--danger-soft` | excluir, cancelar reserva (sempre com motivo) |

Foco: anel 2px `--focus-ring` com offset 2px. Desabilitado: opacidade 0,5, sem hover. Carregando: spinner no lugar do ícone, texto mantido.

### Inputs

Altura 36px, borda `--border-strong`, raio 4px, rótulo 12px acima em `--text-muted`. Foco: borda `--focus-ring` + anel. Erro: borda `--danger` + mensagem 12px abaixo. **Pré-preenchido pela regra** (comissão sugerida pelo % do fornecedor): fundo `--highlight-soft` até o usuário confirmar ou editar — sinaliza "calculado, confira". Dinheiro: prefixo `R$` fixo, digitação em centavos, `inputmode="decimal"`. Datas: `<input type="date">` nativo. Autocomplete de cliente/fornecedor com criação inline ("+ Criar 'Maria Silva'").

### Tabelas

Cabeçalho `--table-header-bg`, 12px caixa alta, `letter-spacing 0.04em`. Linhas 36px, borda inferior `--table-border`. Hover `--table-row-hover`, selecionada `--table-row-selected`. Dinheiro à direita, tabular. Status como pill (abaixo). Ações da linha aparecem no hover à direita. Ordenação por clique no cabeçalho. Paginação 50 por página.

### Pills de status

Altura 22px, raio 4px, 12px peso 600, fundo suave + texto na cor forte do estado (tabela da seção 1). Ponto de 6px à esquerda do texto.

### Cards e tiles

Card: `--surface`, borda, raio 12px, padding 20px, título 16px navy. Tile de número (dashboard): rótulo 12px caixa alta, número 26px navy tabular, variação com seta e cor de estado.

### Feedback

Toast no canto inferior direito, 4s, sem sombra pesada. Erros de regra (422) aparecem **no campo** quando o `codigo` mapeia para um campo, senão como banner no topo do formulário. 409 (versão): banner "Alguém alterou este registro. Recarregar?".

## 6. Tela de lançamento — princípios (o risco número um)

- **Uma tela**: viagem no topo (passageiros com titular, destino, nacional/internacional, datas, vendedor pré-preenchido, comissão do vendedor externo quando houver), reservas como linhas expansíveis abaixo. Nada de wizard.
- **Teclado**: `Tab` percorre na ordem de digitação do portal (fornecedor [select] → localizador → data → serviços vendidos [multi] → total → taxas → comissão → o que o cliente pagou → formas de pagamento [multi] → NFSe). `Ctrl+Enter` salva a reserva e abre a próxima. `Ctrl+S` salva a viagem. `Esc` fecha o painel.
- **Pré-preenchimento visível**: campos calculados com fundo `--highlight-soft`. Derivados (`RAV cliente`, `esperado da operadora`, `receita prevista`) aparecem ao lado, somente leitura, atualizando ao digitar.
- **Criação inline** só de pessoa (passageiro). Fornecedor é select do cadastro.
- **Cronômetro** discreto no canto durante o piloto (tempo desde "Nova viagem" até salvar) — vira métrica.
- Aviso de viagem duplicada e de localizador duplicado como banner `--highlight`, com as três saídas da spec, nunca bloqueio.

## 7. Não fazer

- Gradiente roxo-azul, hero gigante, tudo centralizado.
- Sombra em card comum, raio grande em input.
- Laranja ou amarelo como texto sobre branco.
- Mais de um botão accent por tela.
- Ícone sem rótulo em ação destrutiva.
- Emoji como marcador de seção.
- Valores em `hex` nos componentes — sempre `var(--token)`.
