# Meridiano — Contrato de implementação do Design System (v3)

Complementa `design-system.md` (decisões visuais). Este documento é regra para o frontend: componente recebe **intenção**, nunca cor, tamanho ou espaço solto. Tokens canônicos em `frontend/src/styles/tokens.css` (`--color-*`, `--type-*`, `--space-*`, `--radius-*`, `--bp-*`). Os nomes de variável usados nos mocks HTML são só do esboço.

## 1. Congelado

Identidade navy + azul + laranja · laranja = ação de negócio (uma por tela) · azul = ação normal · amarelo = só atenção · verde = só estado · sidebar 220 · controles 40px · reserva expandida/recolhida com resumo · painel financeiro por reserva · Salvando → ✓ Salvo local · toast só longe do ponto de ação · cinco estados de campo · modal só para decisão/risco · linha de tabela inteira clicável · KPI com próxima ação · Manrope para interface e valores · mono só para códigos.

Muda só com descoberta em uso real, e via este documento.

## 2. Escalas fechadas

| Escala | Valores | Uso |
|---|---|---|
| Espaço | 4 · 8 · 12 · 16 · 24 · 32 · 48 | ícone↔texto 8 · label↔input 8 · campos do grupo 12–16 · grupos internos 24 · blocos 32 · seções 48. Sem 14, 18, 20, 22, 27. |
| Raio | sm 4 · md 6 · lg 8 · pill | input/botão md · card/menu/modal lg · badge/chip pill. Sem 12, 14, 16 em card. |
| Tipo | display 28/800 · page 24/800 · section 18/700 · component 15/700 · body 14/400 · label 13/600 · helper 12/400 · caption 12/500 caps · code 12 mono | Tela nunca escolhe `font-size`; usa `font: var(--type-*)`. |
| Breakpoints | lg 1024 · xl 1280 · 2xl 1440 | Desktop-first. ≥1440 ideal · 1280–1439 compacta gaps, não controles · 1024–1279 sidebar colapsa, grid reduz colunas · <1024 funcional, sem promessa para lançamento complexo. |
| Ícones | Lucide, e só Lucide | 16 inline · 18 navegação · 20 botão de ícone. |

Grid de formulário: 12 colunas com spans por conteúdo (fornecedor 3 · localizador 2 · data 2 · NFSe 2 · CPF 2 · dinheiro 2), não `repeat(4, 1fr)`.

## 3. Componentes obrigatórios, na ordem de construção

Tokens → tipografia/layout base → `Button` `IconButton` `Field` `Input` `MoneyInput` `Select` `DateInput` `Checkbox` `Radio` → `Chip` `Badge` `Tooltip` → `Alert` `Toast` `Modal` → `PageHeader` `Section` → `ReservationCard` `TripSummary` → **Nova viagem completa** (prova do sistema) → `DataTable` + `MoneyCell` `DateCell` `StatusCell` → Lista de viagens → `Skeleton` `EmptyState` `KpiCard` → estados loading/error/empty → responsividade → styleguide interativo → acessibilidade + regressão visual.

Não construir 40 componentes antes das telas. Não paralelizar tudo: Nova viagem valida o conjunto.

### Regras de API

- `Field` ≠ `Input`. `Field` cuida de label, obrigatório, helper, tooltip, erro (`aria-describedby`). `Input` só do controle. `<Field label="Comissão" tooltip="…" error={…}><MoneyInput/></Field>`.
- Estados de campo são props semânticas, não componentes: `<MoneyInput calculated />`, `readOnly`, `disabled`; `<Field state="error" />`. `calculated` é semântico; o visual pode mudar sem tocar telas.
- `MoneyInput` / `MoneyValue` são componentes próprios: pt-BR, duas casas, prefixo R$, direita, tabular, negativo, vazio, readonly/calculated, máscara que não quebra edição.
- `Button` tem cinco variantes e nenhuma prop de cor: `business` (laranja) · `primary` (azul) · `secondary` (borda) · `tertiary` (texto) · `danger` (vermelho). `business` só para a ação que conclui ou avança o trabalho de negócio naquele contexto. Nunca em salvar, editar, voltar, abrir, exportar.
- `Badge` recebe `tone` (`info` `success` `warning` `danger` `neutral`), nunca cor. Status de domínio passa por um mapa único: `<ReservationStatusBadge status />`, `<TripPhaseBadge fase />`. Nenhuma tela decide a cor de "em emissão".
- Status vem da API em português (`pendente` `emitida` `cancelada`; fases `sem_reserva` … `quitada`). Uma função `apresentacaoStatus(status)` devolve texto, tom e ícone. Não traduzir para enums em inglês no front.
- `ReservationCard` é componente de domínio, não `GenericCollapsibleCard`: header compacto (número, fornecedor, localizador, status, serviços, venda, receita, toggle) + body (`BookingFields` `ServiceChips` `FinancialFields` `ResultSummary` `SecondaryDetails`).
- `KpiCard` tem dois tipos: informativo (número + contexto) e acionável (número + `actionLabel`).
- `DataTable` base: linha clicável, hover, selected, loading, empty, sort, paginação, alinhamento monetário; células `MoneyCell` `DateCell` `StatusCell`. Não virar tabela por JSON com renderers monstruosos.
- `PageHeader`: título, meta (código em badge), status, indicador de sujo, ações. Todo cadastro usa.
- Header global fica global: busca, Nova viagem, notificações, ajuda, perfil. Filtros, breadcrumbs e ações de tela ficam no `PageHeader`.
- Sidebar por configuração `{label, icon, path, section, permission, badge}`; item ativo vem da rota.
- Tooltip só para "como este valor é calculado". Informação necessária à tarefa fica visível.
- Toast com API restrita: `toast.success`, `toast.error`, `toast.undo`. Proibido toast de sucesso para save local.
- Atalhos num registry central (`Ctrl+S` salvar · `Ctrl+Enter` adicionar/confirmar reserva · `Ctrl+K` busca · `Esc` cancelar/fechar). Nenhuma página com `keydown` próprio.
- Skeleton espelha o layout real; não aparece em respostas abaixo de 300 ms.
- EmptyState responde: o que aconteceu, isso é normal, o que posso fazer — com ação.

## 4. Estado, dados e erros

- Cálculo financeiro: o backend é a autoridade. O front faz preview local enquanto digita; ao salvar usa o valor oficial da API. Divergência → backend vence.
- Salvamento é uma máquina de estados: `idle → dirty → saving → saved | error`. Sem booleans soltos.
- Dirty centralizado por página. Navegar, fechar aba ou trocar de registro com `dirty` → modal "Sair sem salvar?" (Continuar editando · Sair sem salvar · Salvar e sair), sempre nomeando o registro.
- Sem autosave na v1.
- Erros da API viram conceitos de UX: `ValidationError` (422, `codigo` → campo ou bloco) · `ConflictError` (409 → "Alguém alterou… Recarregar"; sem merge na v1) · `PermissionError` (403) · `NetworkError`. Usuário nunca lê "HTTP 409".
- Três níveis de erro: campo · bloco · página. Modal nunca para erro de campo.
- Offline: banner "Sem conexão — alterações ainda não foram enviadas"; sem edição silenciosa.
- Concorrência: `versao` (`xmin`) em todo PUT.
- Modal destrutivo: título explícito, impacto, botão vermelho, cancelar como opção segura. Confirmação por digitação só para destruição séria.

## 4.1 Ajustes da revisão do protótipo v1 (2026-09-08)

- **Sugerido ≠ calculado.** Valor pré-preenchido por regra que o usuário pode editar (comissão pelo % do fornecedor) é um input normal com selo `Sugerido: 10 %`. O estado visual `calculated` fica só para valores derivados que a tela não edita (RAV do cliente, esperado, receita).
- **Laranja, uma vez.** Header global "+ Nova viagem" é `secondary`. `business` (laranja) só na ação contextual da página: lista de viagens → "+ Nova viagem"; Nova viagem → "+ Adicionar reserva"; repasses → "Pagar"; conciliação → "Marcar recebidas".
- **Estados de domínio** vêm de um mapa único (`regras-e-escopo-v2` §6.1). Não existe "sem receita"; é "não prevista" ou "a receber".
- **Cadastros em página própria** (pessoa, fornecedor, grupo, usuário). Nada de painel lateral para edição; listas abrem a página ao clicar na linha. Ações da página: `Fechar` (tertiary) e `Salvar` (primary). "Cancelar" só existe como ação de negócio ("Cancelar reserva…", "Cancelar viagem…").
- **Privacidade em listas.** CPF mascarado (`***.456.789-**`); passaporte e documentos nunca em listagem; completo só na página da pessoa com `cliente.ver_documento`, e o acesso vai para `log_acesso_documento`.
- **Responsivo mínimo obrigatório.** Abaixo de `--bp-lg` (1024) a sidebar vira drawer aberto por ☰ no header; abaixo de 700 os formulários ficam em uma coluna. Sem isso, não há navegação em janela reduzida.
- **Recuperar senha ≠ convite.** Fluxos separados: `esqueci-senha` (e-mail → link, resposta sempre neutra) e `redefinir-senha` (token de reset → nova senha); `definir-senha` só para convite.
- **Pendências da pessoa.** Checklist derivado (passaporte/visto pela viagem futura, CPF, contato, emergência, seguro) com ação por item; nunca texto solto.
- **Agenda age.** Toda tarefa tem Concluir · Adiar · Abrir (a viagem/pessoa) na própria linha.
- **Pessoa usa tabs reais** (Dados · Documentos · Viagens · Atendimentos) com resumo lateral fixo; página única só no protótipo.

## 4.2 Navegação em três níveis (2026-09-08)

- **Sidebar global**: só módulos (Viagens, Clientes, Fornecedores, Financeiro, Agenda, Relatórios · Usuários, Auditoria). Sem submenu expansível, nunca mais de um nível. Badge amarelo = contagem acionável (Financeiro: comissões atrasadas; Agenda: tarefas de hoje/atrasadas; Clientes: pessoas com pendência).
- **Subnav do módulo** (`.subnav`, pílulas no topo da página): até 6 itens. Hoje: Clientes → Pessoas · Grupos e empresas; Financeiro → Conciliação · Repasses · Fechamento.
- **Acima de 6 itens**: sub-sidebar interna do módulo, agrupada por seções (Operação / Controle / Configurações), conteúdo à direita. Nunca scroll horizontal para descobrir navegação.
- **Tabs de registro** (`.tabs`, com contadores): dentro de uma página de cadastro, cada aba mostra **só o seu conteúdo** — Pessoa: Dados · Documentos · Pendências · Viagens · Atendimentos; Fornecedor: Dados (inclui comissão padrão) · Financeiro (janelas de pagamento e vigência) · Reservas. Nada de página única com tudo empilhado.
- Ações de navegação entre telas do mesmo módulo nunca ficam como botões no `PageHeader`; ficam na subnav.

## 4.3 Pendências → Agenda

Pendência é **derivada** (calculada a partir de viagens, documentos e cadastro), não gravada. Um job diário avalia as regras por pessoa e faz upsert de `tarefa` com `chave_unica = 'pendencia:<cliente_id>:<regra>'`, responsável = agente da viagem relacionada (ou dono), e cancela a tarefa quando a pendência some. Mesmo mecanismo já usado para validade de passaporte (`<documento_id>:validade`). Só pendências **com prazo ou viagem** viram tarefa (passaporte, visto, seguro, documento faltante para embarque); pendências de cadastro (contato de emergência, CPF) ficam só na aba Pendências, com selo "só aqui". Na aba, cada pendência mostra "na agenda" com link para a tarefa.

## 4.4 Ajustes da quarta revisão (2026-09-08)

- **Título antes do subnav**: `PageHeader` primeiro, subnav do módulo logo abaixo, separado por linha. Nunca subnav acima do título.
- **Filtros**: sempre visíveis só busca + 2 filtros principais; o resto em "Filtros ● N" (painel recolhível). Inputs de filtro também têm 40px.
- **Linha de pendência**: uma ação visível (`✓ Concluir`) + menu `⋯` (Adiar · Editar · Excluir); a linha inteira abre o contexto.
- **Laranja em cards repetidos**: proibido. Ações repetidas por item (Pagar R$ X em cada vendedor) são `primary`.
- **Sem cronômetro** ao lado de "Alterações não salvas". Só `● Alterações não salvas` → `✓ Salvo às 10:32`.
- **Campo pré-preenchido editável** (valor recebido = esperado) é input branco com helper "Esperado: R$ X" — mesmo caso da comissão sugerida.
- **Textarea** para observações/preferências (3–5 linhas).
- **Auditoria**: evento complexo tem "Ver detalhes" com diff campo a campo; a timeline fica curta.
- **Barra do protótipo** (links de teste) não é produto; no app, navegação é sidebar + subnav + tabs.

## 5. Proibido (lint / code review)

hex em componente · margin arbitrária · `font-size` solto · botão com cor custom · modal fora do componente padrão · badge de status fora do mapa · cálculo financeiro duplicado em tela · toast para confirmação simples · `window.alert` · tooltip para informação obrigatória · ícone de outra biblioteca · `@media` com valor fora dos breakpoints.

## 6. Acessibilidade (requisito)

Foco visível · navegação por teclado completa · `label` real em todo controle · `aria-describedby` para erro e helper · contraste AA · estado nunca só por cor (chip selecionado tem ✓) · modal com focus trap e `Esc` · `aria-live` para "Salvo".

## 7. Qualidade

- Styleguide interativo dentro do app (rota `/styleguide`, só em dev) com todos os componentes e estados. Storybook só se isso não bastar — sem dependência antes da necessidade.
- Regressão visual com Playwright: campo normal/erro/calculado, ReservationCard aberta/fechada, modal, tabela, 1280 e 1440.
- Teste de UX antes de fechar a Fase 3: alguém que conhece agência e não viu o design faz, sem explicação: criar viagem para Carlos Mendes → adicionar reserva da CVC → informar o que o cliente pagou → descobrir quanto a reserva deixa → adicionar segunda reserva → corrigir a primeira → sair sem salvar. "Onde eu clico?" repetido = problema.

## 8. Arquitetura visual congelada

```
AppShell
├── Sidebar
├── GlobalHeader
└── Page
    ├── PageHeader (title · meta · status · dirty · actions)
    ├── ContextAlert
    ├── TripDataSection
    ├── ReservationCard[]
    │   ├── ReservationHeader
    │   └── ReservationBody (BookingFields · ServiceChips · FinancialFields · ResultSummary · SecondaryDetails)
    ├── AddReservation
    └── TripSummary
```

## 9. Não fazer agora

Tema escuro · animações sofisticadas · dashboard customizável · drag-and-drop · mobile completo · dezenas de variantes · autosave · command palette complexa · merge de conflito.
