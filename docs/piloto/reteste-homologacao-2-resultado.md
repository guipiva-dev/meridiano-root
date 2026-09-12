# Reteste da homologação — rodada 2 — resultado (2026-09-12)

Ambiente: `http://localhost:5000` (mesma app do túnel). Execução automatizada via Playwright (Chromium 152, viewport 1920×897; mobile 390×844) + `curl` para os itens de API. Dados criados com prefixo `RT2 ` (pessoa `RT2 Pessoa Teste`, viagens VG-2026-0015/0016/0017; grupo, despesa e pessoa `RT2 … Excluir` criados e excluídos no próprio teste). Screenshots em `C:\Users\gpiva\AppData\Local\Temp\claude\E--workspace-viva-erp\a533a653-8e11-42de-964d-fe14561641b3\scratchpad\rt2-*.png`.

**Resumo:** 16 corrigidos → 15 PASS · 1 FAIL (MED-02). 7 já corrigidos → 7 PASS. Perfis: 5 contas, 1 FAIL transversal (link/rotas de edição visíveis a perfis sem `viagem.editar`; servidor bloqueia com 403). Mobile: 3 PASS · 1 FAIL (detalhe da viagem).

## Corrigidos — retestar

| ID | Resultado | Passos | Evidência |
|---|---|---|---|
| ALT-01 | PASS | VG-2026-0002 › Editar › + Adicionar reserva, preencher Total 1000 / Venda 1200 sem fornecedor › Salvar viagem | Erro inline no card: "Escolha o fornecedor", `aria-invalid` no select; nenhum texto "Erro interno"; nenhum request enviado |
| ALT-02 | PASS | Cliente RT2 › Documentos › + Documento: Número vazio e só espaços | Botão Salvar `disabled` em ambos os casos; com número `RT2DOC1` salva. API `POST /clientes/{id}/documentos` com `numero:""` e `"   "` → 422 `numero_obrigatorio` "Informe o número do documento" |
| ALT-04 | PASS | Nova pessoa: WhatsApp `abc123`, Telefone `11abcd` › Salvar; depois `11999998888` / `1133334444` | Inline "Telefone inválido" nos dois campos, `aria-invalid`; após salvar exibe `(11) 99999-8888` e `(11) 3333-4444` |
| ALT-07 | PASS | Novo fornecedor: telefone `11abcd`, emergência `abc`, site `nao-e-url` › Salvar | Três campos `aria-invalid`: "Telefone só pode ter dígitos, espaço, parênteses, +, - e ponto (+ só no início)", "Telefone inválido" (emergência), "Site inválido". Nada enviado |
| ALT-09 | PASS | Abrir VG-2026-0002 | Cabeçalho "Comissão: Recebida" com `title="Situação da comissão dos fornecedores nas reservas ativas"` |
| ALT-10 | PASS | Detalhe › Transferir; `POST /viagens`, `PUT /viagens/{id}`, `POST /viagens/{id}/transferir` com `agenteId` = Ana Vendedora (vendedor_externo) | Lista "Novo agente" só com Ana Agente e Bruno Sales. API: 3× HTTP 422 `perfil_nao_opera` "Só dono ou agente pode ser o agente da viagem" |
| ALT-12 | PASS (desktop) | Nova viagem com destino de exatamente 120 chars (`RT2 DestinoDestino…`, `maxlength=120`, 160 chars digitados → 120) e localizador de 40 (`maxlength=40`) | Detalhe: `documentElement.scrollWidth` 1920 = `innerWidth` 1920; h1 quebra em 3 linhas (`overflow-wrap: anywhere`). Aba Reservas: 1920/1920. Edição: 1905/1920. Na lista a célula quebra (linha 86 px, célula 915 px, sem overflow próprio). **Ver Mobile: o mesmo h1 quebra 1 caractere por linha em 390 px.** |
| ALT-13 | PASS | Em VG-2026-0015 › link "Nova viagem" › passageira Lúcia Mendes, destino `RT2 ALT13 a partir de outra` › Salvar › Fechar | Salvou como VG-2026-0016 (`/viagens/5ae6d3d8…/editar`); Fechar abriu `/viagens/5ae6d3d8…` com o cabeçalho da viagem nova |
| ALT-15 | PASS | Cliente sem viagem: Excluir cliente › modal › Excluir. Cliente com viagem (QA Teste Homolog): idem. Grupo `RT2 Grupo Teste`: Excluir grupo. Despesa `RT2 Despesa teste`: menu "Mais ações" › Excluir | Modais "Excluir X? Esta ação não pode ser desfeita." Sem viagem: removido, volta à lista. Com viagem: "Pessoa tem viagem ou crédito e não pode ser excluída" (banner, sem 500). Grupo: "As pessoas do grupo não são excluídas" → removido. Despesa: "Excluir despesa" com confirmação → removida. Fornecedor tem Situação Ativo/Inativo no form |
| MED-02 | **FAIL** | `/viagens` limpo, com painel Filtros aberto, com filtro Tipo=Internacional aplicado, com painel fechado | Campo "Buscar viagens" com **26 px** de largura em todos os estados; selects Vendedor e Ida com 1352 px cada (100 % do container); `documentElement.scrollWidth` 3218–3323 > 1920 (barra horizontal na página). Ver "Falhas" |
| MED-03 | PASS | Inspeção de `maxlength` + digitação além do limite | destino 120, localizador 40, nome (pessoa/grupo/fornecedor) 150, cidade 80, "O que precisa ser feito" (pendência) 150, descrição da despesa 200, observações 2000 com contador `0/2000` (viagem, pessoa, grupo, fornecedor, despesa). Observações da reserva tem `maxlength=2000` mas sem contador |
| MED-04 | PASS | Relatórios › Exportar CSV; Auditoria › Exportar CSV; repetir os dois após `clearCookies()` | Downloads `relatorio-2026.csv` e `auditoria.csv` concluídos. Sessão expirada: nenhum download, URL inalterada, alerta "Sua sessão expirou. Entre de novo." na tela |
| MED-06 | PASS | Auditoria › "Valores de reserva" | `?oque=valores`, 20 eventos "Dono Dev — Reserva lançada" (ex.: "CVC · RT2LOC… · viagem VG-2026-0015") |
| MED-07 | PASS | `/viagens` com `page.route` atrasando `/api/v1/viagens*` em 2 s | Enquanto carrega: "— viagens · — em emissão · — com comissão atrasada" e abas "Todas —", "Em emissão —" …; depois "5 viagens · 2 em emissão". (Obs.: Clientes e Fornecedores ainda mostram "0 pessoas · 0 grupos" / "0 cadastrados" enquanto carregam — fora do escopo do item) |
| MED-09 | PASS | Abrir VG-2026-0004 (reserva cancelada) | Aba "Reservas Ativas 0 · Total 1"; Resumo "Ativas 0 · Total 1 · clique para abrir" |
| MEL-02 | PASS | Editar › reserva nova (+ mais campos) | Tooltips "?": Comissão ("O que o fornecedor paga à agência…"), Taxa de serviço ("Valor fixo cobrado do cliente sem custo por trás…"), Fluxo ("Quem recebe o pagamento do cliente…"); também Total, Venda ao cliente e RAV |

## Já corrigidos antes — confirmação de passagem

| ID | Resultado | Evidência |
|---|---|---|
| ALT-03 | PASS | CPF `11111111111` → "CPF inválido" inline; CPF duplicado → "Já existe uma pessoa com esse CPF"; válido salva com máscara `390.533.447-05` |
| ALT-05 | PASS | E-mail `rt2@teste.dev` presente após salvar e após `reload()` |
| ALT-06 | PASS | Grupo tipo Empresa, CNPJ `11111111111111` → "CNPJ inválido"; `45723174000110` salva como `45.723.174/0001-10` |
| ALT-08 | PASS | Despesa valor `abc` → campo limpo + "Informe um valor maior que zero"; `123,45` → `R$ 123,45` |
| MED-01 | PASS | Dialog "Editar despesa"; páginas de edição mostram o nome da entidade (não "Nova …") |
| MED-05 | PASS | Reserva salva às 12:06 BRT aparece na Auditoria/Timeline como "hoje 12:06" / "12/09/2026, 12:06" (UTC era 15:06) |
| MED-08 | PASS | Header só com Buscar (Ctrl K), Nova viagem, nome do usuário e Sair — sem Ajuda/Notificações |

## Falhas

### MED-02 — barra de busca/filtros da lista de viagens (FAIL, regressão)
- Onde: `/viagens`, qualquer estado (sem filtro, painel aberto, filtro aplicado). Viewport 1920×897.
- Comportamento: input "Buscar viagens" com 26 px de largura; `select` Vendedor e `select` Ida com 1352 px cada; botão "Filtros" empurrado para fora da viewport; página com scroll horizontal (`scrollWidth` 3218 sem filtro, 3323 com filtro; `innerWidth` 1920). Elementos que estouram: `._linha1_a5pxo_19` (2936 px) → `._filtros`, `._panel`, `main`, `body`.
- Causa (CSS servido): `._linha1_a5pxo_19 { display:flex }`, `._linha1_a5pxo_19 > input { flex:1 1 0%; min-width:0 }`, `._linha1_a5pxo_19 > select, > button { flex: 0 0 auto }` combinado com `._control_15ull_1 { width: 100% }`. Com `flex-basis:auto` cada `select` assume `width:100%` do container; o input, com `flex-shrink` e `min-width:0`, colapsa. (Existe outra regra `_linha1_b1ntz_20` com `flex-wrap:wrap; > select { max-width:280px }`, provavelmente a intenção, mas não é a classe aplicada na lista de viagens.)
- Evidência: `rt2-med02-filtros.png`.
- Em 390 px a mesma barra empilha corretamente (não reproduz).

### Perfis — link "Nova viagem" e rotas `/viagens/nova`, `/viagens/{id}/editar` visíveis para Financeiro, Contador e Vendedor externo (FAIL, baixa)
- A sub-navegação "Seções do módulo" em `/viagens` e no detalhe mostra "Nova viagem" para os três perfis; `/viagens/nova` e `/viagens/{id}/editar` renderizam o formulário completo com "Salvar viagem" (não mostram "Sem permissão" como as outras áreas).
- Servidor bloqueia: `PUT /viagens/{id}` → 403 "Requer viagem.editar" (Financeiro e Vendedor externo testados); UI mostra "Você não tem permissão para isso.". Não há vazamento de dados, só de UI.
- Header "Nova viagem" e botão "Editar" do detalhe estão corretamente ocultos.

### Mobile — detalhe da viagem: título quebra 1 caractere por linha (FAIL)
- 390×844, `/viagens/{id}` (Resumo e Reservas), com título curto ("Carlos Mendes · Teste cancelamento") e longo (120 chars).
- `h1._titulo_13dwx_19` é `display:flex; flex-wrap:nowrap` com o texto como item anônimo + 3 badges (código, fase, comissão = 317 px). Em 343 px o texto fica com 21 px e, com `overflow-wrap:anywhere`, quebra caractere a caractere: h1 com 680 px (curto) e 2468 px (longo) de altura; `scrollWidth` 404–408 > 390.
- Evidência: `rt2-mobile-detalhe.png`, `rt2-mobile-detalhe-curto.png`.

## Perfis

| Conta | Nav principal | Verificações §7.1 | 500 / tela em branco |
|---|---|---|---|
| dono@viva.dev | Viagens, Clientes, Fornecedores, Financeiro, Agenda, Relatórios, Equipe, Auditoria | Tudo; Transferir, Cancelar, Editar, Excluir, Exportar CSV | Nenhum |
| ana.agente@viva.dev (Agente) | Viagens, Clientes, Fornecedores, Agenda | (1) Header e lista com "Nova viagem"; cria/edita viagem. (2) Detalhe VG-0015: Resumo sem "Resultado da viagem/agência", sem "Comissão do vendedor", sem repasse; aba Financeiro só comissões a receber/movimentos/despesas. (3) `/financeiro`, `/relatorios`, `/equipe`, `/auditoria` → "Sem permissão" | Nenhum |
| financeiro@viva.dev (Financeiro) | Viagens, Clientes, Fornecedores, Financeiro, Agenda, Relatórios, Auditoria | (1) Sem "Nova viagem" no header, sem "Editar"/"Transferir"/"Cancelar" no detalhe; sem "Nova pessoa"/"Novo fornecedor". (2) Financeiro completo: Marcar recebidas, Receber, Repasses, Despesas, Fechamento. (3) `/equipe` → "Sem permissão". **Ressalva:** sub-nav "Nova viagem" e rota `/editar` renderizam formulário; salvar → 403 | Nenhum |
| contador@viva.dev (Contador) | Viagens, Fornecedores, Financeiro, Agenda, Relatórios, Auditoria | (1) Relatórios + Exportar CSV e Auditoria completos. (2) Financeiro sem botões de ação (sem Marcar recebidas/Receber/Nova despesa); Agenda sem "+ Nova pendência". (3) `/clientes`, `/clientes/{id}`, `/equipe` → "Sem permissão". Mesma ressalva do sub-nav "Nova viagem"/`/editar` | Nenhum |
| ana@viva.dev (Vendedor externo) | Viagens, Clientes, Agenda | (1) Lista de viagens: só VG-2026-0017 (vendedora = ela); viagem de outro (VG-0015) → "Viagem não encontrada" (API 422, sem 500). (2) Clientes: só `RT2 Pessoa Teste` (passageira da viagem dela); cliente de outro → "Não foi possível carregar esta pessoa" (422). (3) Sem "Nova viagem" no header, sem Editar; `/financeiro`, `/relatorios`, `/equipe`, `/auditoria` → "Sem permissão". `PUT /viagens/{id}` → 403 "Requer viagem.editar". Mesma ressalva do sub-nav/`/editar`. Obs.: `/fornecedores` acessível por URL (lista completa, API 200); em `/clientes` o header diz "3 grupos" mas `GET /grupos` responde 403 (erro no console) | Nenhum |

## Mobile (390×844, dono)

| Tela | `scrollWidth` / `innerWidth` | Resultado | Observação |
|---|---|---|---|
| Lista de viagens `/viagens` | 375 / 390 | PASS | Tabela e abas rolam dentro dos próprios containers; filtros empilhados |
| Detalhe `/viagens/{id}` (Resumo) | 404 / 390 | **FAIL** | Título 1 caractere por linha (ver Falhas); ocorre com título curto (408/390) e longo |
| Detalhe aba Reservas | 390 / 390 | FAIL (mesmo cabeçalho) | Cards ok; h1 idem |
| Nova viagem `/viagens/nova` | 375 / 390 | PASS | Campos em coluna, sem overflow |
| Clientes `/clientes` | 375 / 390 | PASS | Tabela rola dentro do container |

## Observações fora do roteiro (não pontuadas)
- Banner "Encontramos uma viagem semelhante para Carlos Mendes … Adicionar reserva à viagem existente / Abrir viagem / Continuar criando nova" aparece na **edição de viagem já salva** (VG-0015) para todos os perfis, e permanece após salvar a nova viagem.
- Edição de VG-2026-0002 mostra "Venda total R$ 12.000,00" (inclui reserva cancelada de R$ 1.000), enquanto lista/Resumo mostram R$ 11.000,00.
- Abrir cliente legado com dados inválidos (QA Teste Homolog: CPF 123.456.789-00, telefone "abc") já exibe "CPF inválido"/"Telefone inválido" ao carregar.
- Fornecedor: telefone principal usa mensagem longa ("Telefone só pode ter dígitos…") e emergência usa "Telefone inválido" — mensagens diferentes para a mesma regra.
- Vendedor externo: Resumo sem reservas diz "Adicione a primeira reserva pela edição da viagem" (perfil não edita); filtro "Vendedor" lista toda a equipe.
- Clientes/Fornecedores mostram "0 pessoas · 0 grupos" / "0 cadastrados" durante o carregamento (o mesmo padrão corrigido em MED-07 para Viagens).
