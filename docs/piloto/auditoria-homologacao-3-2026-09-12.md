# Auditoria de homologação — rodada 3 (2026-09-12)

Ambiente: `https://mediterraneo-app.bspdv.com.br` (piloto, via tunnel). Ferramenta: Playwright (Chromium 152). Perfis exercitados: Dono (`dono@viva.dev`, principal), Agente, Vendedor externo, Contador, Financeiro. Viewports: 1920×1080, 1366×768, 1280×720, 1024×768, 768×1024, 390×844.

Dados criados durante a auditoria (podem ser descartados): VG-2026-0018 (cancelada), VG-2026-0019 (divergência encerrada), VG-2026-0020 "QA Duplo clique" (rascunho), pessoa "QA Audit Pessoa 1630", fornecedor "QA Fornecedor Audit" (inativo), colaborador "QA Convidado Audit" (convite pendente), pendência solta "QA pendência solta agenda", Agosto/2026 fechado, movimento de R$ 10 em 15/08 na VG-0001, duas versões novas da regra de pagamento da CVC (1–10→25 vigente hoje; regra original volta em 13/09).

---

## 1. Resumo executivo

O núcleo do produto está sólido: lançamento de viagem em uma tela, cálculo de receita (comissão + RAV + taxa) correto em todos os cenários da spec, conciliação com lote/parcial/divergência, fechamento de período com motivo, auditoria completa, concorrência otimista, guarda de "sair sem salvar", permissões enforçadas na API (403 corretos), lockout de login, cookie HttpOnly/Secure/Strict, XSS escapado em todos os pontos testados. Os relatórios batem centavo a centavo com a exportação CSV.

O que impede a produção hoje não é falta de funcionalidade — é um punhado de furos de validação e de estado que produzem números financeiros errados **sem aviso**, um bug que impede cadastrar CPF em cliente existente, uma tabela de viagens que esconde as colunas financeiras em qualquer notebook, e um ambiente com storage de anexos apontando para `localhost`. Além disso, há um padrão recorrente de **falha silenciosa** (422/502 sem mensagem) que mina a confiança do usuário.

## 2. Quantidade por severidade

| Severidade | Qtd |
|---|---|
| BLOQUEADOR | 1 |
| ALTO | 6 |
| MÉDIO | 24 |
| BAIXO | 27 |
| MELHORIA | 9 |

## 3. Top 10

1. **B01** Anexos: URL assinada aponta para `http://localhost:9000` — upload impossível e falha silenciosa.
2. **A03** Reserva salva com "Venda ao cliente" vazio → receita −R$ 9.000 e resultado negativo sem aviso.
3. **A12** Remarcação com custo > venda gera "esperado da operadora" negativo; reserva vira RECEBIDA sem receber nada, viagem vira NÃO PREVISTA.
4. **A02** Taxa maior que o total da reserva é aceita e salva.
5. **A21** Cliente sem CPF não tem campo CPF na edição (API omite chave nula; front esconde como "sem permissão").
6. **A01** Lista de viagens esconde Fase/Financeiro/Venda/Receita em 1366 px (e Venda/Receita em 1920) por causa de destino longo sem truncamento; sem indicação de scroll.
7. **A06** Vendedor externo acessa `/fornecedores` e a API de fornecedores com % de comissão da agência; e não vê o próprio repasse (spec 7.1).
8. **M01** Três números diferentes com o rótulo "recebido/recebida" no mesmo mês (Conciliação 8.752 · Fechamento 8.952 · Relatório 9.062).
9. **M02** Padrão de falha silenciosa: excedente sem checkbox (422), atendimento com 502, upload de anexo — dialog fica aberto sem mensagem.
10. **M03** Repasse de viagem cancelada continua "Bloqueado · aguardando 0 comissões"; resultado operacional do relatório ignora repasses pagos.

---

## 4. Bugs funcionais

### B01 — Upload de anexo aponta para localhost
- **Severidade:** BLOQUEADOR (neste ambiente) · **Categoria:** Infra/feedback · **Tela:** Viagem › Documentos › Anexar (e Cliente › Documentos › Anexar)
- **Passos:** 1. Abrir VG-2026-0018 › Documentos › "+ Anexar". 2. Selecionar `voucher-qa.pdf`, Anexar.
- **Atual:** `POST /api/v1/anexos` → 201 com URL `http://localhost:9000/meridiano-dev/...` (MinIO local). O `PUT` falha (mixed content + host inexistente). Dialog permanece aberto, sem erro; lista continua "Nenhum anexo".
- **Esperado:** Storage do ambiente configurado (R2) e mensagem de erro clara quando o upload falhar.
- **Impacto:** Módulo de documentos inutilizável; registro de anexo possivelmente órfão no banco.
- **Recomendação:** Corrigir `STORAGE_PUBLIC_ENDPOINT` do piloto; no front, tratar falha do PUT com mensagem e remover o registro pendente.
- **Evidência:** request #250 `PUT http://localhost:9000/meridiano-dev/ff9dfde7-.../voucher-qa.pdf?X-Amz-...`. `.exe` é rejeitado corretamente ("Tipo de arquivo não permitido").

### A21 — Campo CPF some para cliente sem CPF
- **Severidade:** ALTO · **Categoria:** Bug · **Tela:** Clientes › Pessoa (edição)
- **Passos:** 1. Abrir Carlos Mendes (sem CPF). 2. Observar formulário "Dados pessoais".
- **Atual:** Campos: Nome, Nascimento, Grupo, Cidade, UF… — **sem CPF**. `GET /api/v1/clientes/{id}` não devolve a chave `cpf` quando nula; o front interpreta ausência como "sem permissão" e esconde o campo. Pessoa nova com CPF exibe o campo normalmente.
- **Esperado:** Campo CPF sempre presente para quem tem `cliente.ver_documento`.
- **Impacto:** Impossível completar o cadastro de clientes legados; passaporte/CPF ficam sem vínculo.
- **Recomendação:** API devolver `cpf: null` (não omitir) ou front decidir por permissão, não por presença da chave.

### A01 — Tabela de viagens esconde colunas financeiras
- **Severidade:** ALTO · **Categoria:** UI/UX · **Tela:** Viagens (lista)
- **Passos:** 1. Abrir `/viagens` em 1366×768 (ou 1920). 2. Observar colunas.
- **Atual:** Tabela com 1.568 px dentro de contêiner de 1.083 px (1366) / 1.352 px (1920). Em 1366 só aparecem Viagem, Ida e Vendedor; Fase, Financeiro, Venda e Receita ficam fora da tela, sem barra de rolagem visível. Causa: destino de 120 caracteres (VG-2026-0015) sem `text-overflow`/largura máxima na 1ª coluna.
- **Esperado:** 1ª coluna com largura máxima e reticências; tabela cabendo no contêiner.
- **Impacto:** A tela principal do dia a dia perde justamente os status e valores.
- **Evidência:** `table.width=1568, container=1352` (1920); screenshot `v1366-viagens.jpeg`.

### F01 — Falhas silenciosas (padrão)
- **Severidade:** MÉDIO · **Categoria:** Feedback · **Telas:** Receber comissão, Registrar atendimento, Anexar, Nova pessoa (modal)
- **Passos:** Receber comissão com valor acima do esperado sem marcar "Registrar mesmo assim" → Confirmar.
- **Atual:** API 422, nada muda na tela. Mesmo comportamento com 502 (atendimento, 6,5 s) e com falha de upload.
- **Esperado:** Toda resposta ≠ 2xx exibe mensagem no dialog (o 422 com `codigo` já traz texto).
- **Impacto:** Usuário clica repetidas vezes, desiste ou acha que salvou.

### F02 — Nova versão da regra de pagamento não pode ser corrigida no mesmo dia
- **Severidade:** MÉDIO · **Tela:** Fornecedor › Financeiro
- **Atual:** Criei versão errada (só dias 1–10) vigente hoje; tentar outra hoje → "A nova versão precisa começar depois da última vigência". Não existe editar/excluir versão. Versão futura (13/09) aparece em "Versões anteriores". O dialog não pré-carrega a regra atual. Janelas com lacuna (dias 11–31 sem regra) aceitas sem aviso.
- **Impacto:** Erro de digitação fica vigente até o dia seguinte e afeta a previsão de todas as reservas lançadas no dia.

### F03 — "+ Adicionar reserva" no detalhe não abre reserva nova
- **Severidade:** BAIXO · Vai para `/editar` e o usuário precisa clicar de novo.

### F04 — Banner "Encontramos uma viagem semelhante" persiste após salvar e na edição de viagem existente
- **Severidade:** BAIXO · **Tela:** Nova viagem/Editar. Aparece até na VG-0018 já salva (compara com ela mesma? não — com VG-0012) e em `/editar` de qualquer viagem do cliente.

### F05 — Erro "Escolha o fornecedor" aparece antes de qualquer interação ao adicionar reserva
- **Severidade:** BAIXO.

### F06 — Título da aba do navegador é sempre "Meridiano"
- **Severidade:** BAIXO · sem contexto de página no histórico/abas.

### F07 — "Ver detalhes" da auditoria expõe nomes técnicos (`divergencia_motivo`, `conciliacao_encerrada`)
- **Severidade:** BAIXO.

### F08 — Pessoa excluída: "Não foi possível carregar esta pessoa. Tentar de novo"
- **Severidade:** BAIXO · parece erro de rede; deveria dizer "excluída/não encontrada".

---

## 5. Problemas de regra de negócio

### A12 — Remarcação gera esperado negativo e estados contraditórios
- **Severidade:** ALTO · **Tela:** Viagem › Reservas › Remarcar…
- **Passos:** 1. Reserva CVC total 10.000, venda 10.500, RAV do cliente "via operadora" (esperado 1.600). 2. Remarcar: novo valor 12.000, sem alterar venda.
- **Atual:** RAV do cliente −1.500 → "Comissão + RAV op." **−R$ 400** (esperado da operadora negativo), receita −400, situação da reserva **RECEBIDA** (nada foi recebido), header da viagem **COMISSÃO: NÃO PREVISTA**.
- **Esperado:** Bloquear/alertar esperado negativo; nunca marcar "recebida" sem movimento.
- **Impacto:** Reserva some da conciliação como se estivesse quitada; receita distorcida.
- **Evidência:** `POST /reservas/{id}/remarcar` `{valorNovo:12000}`; painel "COMISSÃO + RAV OP. −R$ 400,00".

### A03 — "Venda ao cliente" vazio vira 0
- **Severidade:** ALTO · **Tela:** Nova viagem › Reserva
- **Passos:** Preencher Total 10.000 e comissão; deixar "Venda ao cliente" vazio; salvar.
- **Atual:** RAV do cliente −10.000, receita −9.000, Resultado da viagem −R$ 9.000, lista mostra "−R$ 9.000,00". Salva sem aviso (VG-2026-0018).
- **Esperado:** Pré-preencher venda = total (caso comum) ou exigir o campo; alertar venda < custo.
- **Impacto:** Erro de digitação comum no lançamento diário corrompe receita, resultado e relatórios.

### A02 — Taxa maior que o total
- **Severidade:** ALTO · Taxa 20.000 em total 10.000 aceita e salva. Deveria validar `taxa ≤ total`.

### A23 — Reserva cancelada com comissão já recebida não sinaliza estorno
- **Severidade:** MÉDIO · **Tela:** Cancelar reserva
- **Atual:** Reserva com R$ 2.100 recebidos cancelada sem "comissão mantida": prevista zera, recebida fica, resultado −300, situação "Não prevista". Nenhum alerta/pendência de estorno. Fornecedor › Reservas lista "NÃO PREVISTA · recebido 2.100" sem destaque. Mesmo caso em VG-0014 (150 recebidos).
- **Esperado:** Aviso "há R$ 2.100 recebidos — registrar estorno?" e situação "estorno pendente".

### A24 — Viagem CONFIRMADA volta para RASCUNHO ao cancelar a única reserva
- **Severidade:** MÉDIO · Viagem com NFSe emitida, movimentos e despesa aparece como "Rascunho". Confunde com viagem nunca lançada.

### A07 — Divergência encerrada, mas viagem diz "Recebida" e resultado usa o previsto
- **Severidade:** MÉDIO · **Tela:** VG-0001. Reserva HGBIX3 DIVERGENTE (1.000 de 1.130, encerrada). Header "COMISSÃO: RECEBIDA"; Financeiro "Resultado R$ 1.482" (previsto) com recebido 1.352; seção "Comissões a receber (2)" lista uma RECEBIDA e uma DIVERGENTE; botão "Receber" continua na divergente (spec 3.5: reabrir não existe). Resultado deveria refletir a divergência encerrada ou o rótulo dizer "previsto".

### A35 — Repasse em viagem cancelada / rascunho
- **Severidade:** MÉDIO · **Tela:** Financeiro › Repasses. VG-2026-0005 (cancelada) "BLOQUEADO R$ 500 · aguardando 0 comissões". VG-0017 (rascunho, 0 reservas) pede "informar valor"; após informar não há como editar. KPI "aguardando comissão de 2 viagens" conta as duas. Repasse de viagem cancelada deveria ser zerado.

### A36 — Resultado operacional ignora repasses pagos
- **Severidade:** MÉDIO · **Tela:** Relatórios. "Resultado operacional = receita recebida − despesas pagas". Repasse de R$ 20 pago a Marcos Castro não aparece em nenhum KPI. Para vendedor externo, o resultado fica superestimado.

### A46 — Excedente recebido não sinalizado
- **Severidade:** MÉDIO · VG-0002: esperado 1.300, recebido 2.050, situação "RECEBIDA" sem indicar +750.

### A38 — Reserva divergente ainda oferece "Receber"
- **Severidade:** MÉDIO · Dialog abre com saldo 130 como se estivesse aberta.

### A22 — Crédito/reembolso sem teto
- **Severidade:** MÉDIO · Crédito de R$ 50.000 em reserva de R$ 13.000 e reembolso de R$ 9.999.999 em reserva de R$ 8.000 aceitos sem aviso.

### A27 — CNPJ duplicado em grupos
- **Severidade:** MÉDIO · `11.222.333/0001-81` aceito em dois grupos (CNPJ inválido é bloqueado).

### A16 — NFSe "Emitida" sem número e com data futura (2030)
- **Severidade:** BAIXO.

### A42 — Documentos vencendo aponta viagem nacional
- **Severidade:** BAIXO · Passaporte de Carlos (vence 01/12) mostra "São Cristovão · 13/10" (nacional) em vez da internacional de jan/2027 (spec: internacional futura mais próxima). Coluna "PENDÊNCIA: SÓ NO CADASTRO" sem significado claro.

---

## 6. Problemas financeiros

### M01 — Três "recebidos" diferentes para o mesmo mês
- **Severidade:** MÉDIO · **Telas:** Conciliação (KPI "Recebido no mês" = só `recebimento_operadora`: 8.752), Fechamento ("recebida" = todos os tipos: 8.952), Relatório ("Receita recebida" = todos, ano: 9.062). O KPI da conciliação também não bate com a soma das abas (Recebidas 4.852+500 + Divergências 1.150 = 6.502) porque inclui recebimentos de reservas canceladas que não aparecem em aba nenhuma. Mesmo rótulo, três definições.
- **Recomendação:** rótulos distintos ("Comissões recebidas" vs "Entradas de caixa") e uma aba "Canceladas com recebimento".

### Verificações que bateram (manuais)
- VG-0001: 1.130 + 352 = 1.482 ✓ · VG-0018 caso B da spec: 1.000 + 100 + 500 = 1.600 ✓ · após remarcação (venda 13.000): 2.100 ✓ · despesa 300 → resultado 1.800 ✓ · estorno −400 abate recebido ✓.
- Relatório 2026: venda ativa 100.750 = soma CSV (canceladas excluídas) ✓ · nacional 23.150 + internacional 77.600 ✓ · fornecedores 54.850 + 29.600 + 16.300 ✓ · despesas pagas 948 = fixas 298 + viagens 450 + 200 ✓ · margem 8,05 % ✓ · comercial 8,47 % ✓ · MEI 11,2 % ✓.
- Despesas setembro: 1.078,90 lançado / 130,90 a pagar / 298 fixos / 500 viagens ✓.
- Previsão de comissão CVC: compra 12/09 → 20/09 ✓; após regra 1–10→25: compra dia 12 sem janela (ver F02).

---

## 7. Problemas de UI

- **U01 (BAIXO)** Três CTAs "Nova viagem" na mesma tela (header, botão da página, sub-nav).
- **U02 (BAIXO)** Cores de ação primária: laranja em listas ("+ Nova viagem", "+ Adicionar reserva" enorme) e azul em formulários ("Salvar viagem", "Salvar"). Dois primários competindo.
- **U03 (MÉDIO)** Tipografia: 10,5 px em badges, códigos, rótulos de KPI e contadores (68 ocorrências na lista de viagens); 12,25 px em texto secundário de tabela. Abaixo do confortável para uso diário.
- **U04 (BAIXO)** Filtro "Ida" mostra "Qualquer" sem prefixo quando selecionado (outros mantêm "Vendedor: todos").
- **U05 (BAIXO)** Filtro Fornecedor na lista de viagens é grupo de botões sem título visível; Vendedor lista Contador/Financeiro.
- **U06 (BAIXO)** Resumo da viagem: "Venda 16.150 · Custo 16.150 · Resultado 1.482" — sem linha "Receita prevista" (só na aba Financeiro); usuário faz a conta errada.
- **U07 (BAIXO)** "Comissões a receber (1)" lista itens RECEBIDOS; parcial mostra R$ 2.100 sem "falta R$ 1.100".
- **U08 (BAIXO)** Despesa ligada a viagem exibe "Repete todo mês" + aviso "não repete". KPI "Fixos — DAS, sistema, telefone" mas DAS é Imposto.
- **U09 (BAIXO)** Fornecedores: "5 cadastrados" conta só ativos; com filtro inativos vira "2 cadastrados".
- **U10 (BAIXO)** Lista de clientes mostra contato "abc" (telefones legados) e última viagem "cancelada · dez/2026".
- **U11 (BAIXO)** Copies: "1 viagens", "Hoje prevista para 01/09/2026", "10/2026 · 1 meses", hint "Período fechado ou exclusão" reaproveitado no motivo de divergência.

## 8. Problemas de UX

- **X01 (MÉDIO)** "Usar crédito…": ao escolher crédito CVC, "Aplicar na reserva" fica vazio (reserva ativa é Azul) sem explicar que crédito é por fornecedor; botão aparece em viagem cancelada/sem reserva ativa.
- **X02 (MÉDIO)** Encerrar divergência escondido no kebab "Mais ações" da linha; o dialog "Receber" manda "registrar como divergência" mas não oferece a ação.
- **X03 (MÉDIO)** Equipe: convite não tem cancelar/revogar/excluir (só Reenviar); convites de teste acumulam; linhas "sem acesso"/"convite" sem botão Editar (clicar na linha funciona — inconsistente); sem toast "Convite enviado".
- **X04 (BAIXO)** Validações do cadastro de pessoa aparecem uma por vez (telefone/e-mail, depois nascimento).
- **X05 (BAIXO)** "Excluir cliente" confirma "não pode ser desfeita" e só depois diz que não pode excluir.
- **X06 (BAIXO)** Enter não submete o dialog Remarcar (outros formulários submetem).
- **X07 (BAIXO)** Sem toast de sucesso em Transferir/Receber/Lançar/Convidar — o dialog só fecha.
- **X08 (BAIXO)** Corrigir movimento não pede motivo (Excluir pede).
- **X09 (BAIXO)** Passageiros: duas opções "Carlos Mendes" idênticas sem CPF/telefone para distinguir.
- **X10 (BAIXO)** Valor "0" em campo monetário é revertido silenciosamente ao valor anterior (Despesa).

## 9. Responsividade

- ≥1366: sidebar fixa 220 px; 1280: rail de 66 px; ≤1024: drawer (botão "Menu"). Sem scroll horizontal da página em nenhum desktop.
- **R01 (ALTO = A01)** Tabela de viagens 1.568 px em todas as larguras; em 1366 esconde 4 colunas.
- **R02 (MÉDIO)** 390 px: `/relatorios` (scrollWidth 555) e `/financeiro/despesas` (452) rolam horizontalmente — cards de KPI e barra de ações não quebram; "Exportar CSV" cortado; campo de busca do header vira "Bu Ctrl K" sobreposto.
- **R03 (BAIXO)** 390 px: tablists (Todas/Em emissão/…; Resumo/Reservas/…) transbordam sem rolagem.
- Tabelas de Clientes/Equipe/Despesas em 768/390 rolam dentro do contêiner (ok).

## 10. Acessibilidade

- OK: foco visível (outline 2 px azul) em links, botões, inputs; dialogs com `aria-modal`, foco inicial, trap de Tab e retorno do foco ao gatilho no Esc; `lang="pt-BR"`; selects com `aria-label`; linhas de tabela focáveis com `aria-label`; gráfico com `role=group` e valores em `aria-label`.
- **AC01 (MÉDIO)** Texto de 10,5 px generalizado (ver U03).
- **AC02 (BAIXO)** Botão sem nome acessível junto ao serviço da reserva (`""`).
- **AC03 (BAIXO)** Estado "concluída" da pendência indicado só visualmente (sem texto/badge na lista com "Mostrar concluídas").
- **AC04 (BAIXO)** `<title>` fixo.

## 11. Permissões e segurança

- OK: URL direta bloqueada ("Sem permissão") e API 403 com `permissao` para Agente/Vendedor/Contador/Financeiro em `/usuarios`, `/auditoria`, `/repasses`, `/despesas`, `/clientes/{id}` conforme perfil; Vendedor recebe 422 `nao_encontrado` para viagem/cliente de outro; Agente não consegue `POST /movimentos` (403 `financeiro.movimentar`); DTO do Agente sem resultado/repasse; lockout após 5 tentativas (429, 60 s); cookie `meridiano_sessao` HttpOnly/Secure/SameSite=Strict; mensagens de erro genéricas no login e no "esqueci senha"; token de redefinição inválido tratado; XSS escapado (nomes com `<script>`/`<img onerror>` inertes em listas, CSV e busca).
- **P01 (ALTO)** Vendedor externo acessa `/fornecedores` e `/fornecedores/{id}` (UI e `GET /api/v1/fornecedores` 200) com **% de comissão padrão e regra de pagamento** de cada operadora — informação comercial da agência; spec 7.1 limita o perfil a "próprias viagens e clientes".
- **P02 (MÉDIO)** Vendedor externo não vê "status e valor do repasse dele" em lugar nenhum (spec 7.1): `/financeiro/repasses` dá "Sem permissão" na UI embora `GET /api/v1/repasses` responda 200 com os dados dela; o detalhe da viagem não mostra repasse.
- **P03 (MÉDIO)** HTML servido sem cabeçalhos de segurança (sem HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy); as respostas da API têm alguns.
- **P04 (MÉDIO — a verificar)** Na UI o Dono consegue escolher Situação=Inativo e Perfil=Contador em si mesmo. Não testei o `PUT` por risco de lockout (único Dono); a spec prevê "guarda de último Dono" — confirmar com teste automatizado e desabilitar as opções no próprio usuário.
- **P05 (BAIXO)** Filtro "Vendedor" da lista mostra todos os usuários (nomes da equipe) para o Vendedor externo.
- **P06 (BAIXO)** Vendedor: header de Clientes diz "4 grupos" mas `GET /grupos` responde 403 (erro no console).

## 12. Inconsistências

1. "Recebido/recebida" com três definições (M01).
2. Primário laranja × azul (U02); "Fechar" como link em formulários e como botão em dialogs.
3. Verbos de confirmação: Criar (pessoa, pendência) · Salvar (viagem, NFSe, documento) · Lançar (movimento, despesa) · Adicionar (serviço) · Registrar (atendimento) · Confirmar (recebimento) · Anexar.
4. Criação em modal (pessoa na viagem, pendência, despesa, serviço, convite) × página (pessoa em Clientes, grupo, fornecedor).
5. Reserva "A RECEBER" na viagem × "RECEBIDA" com esperado negativo (A12); viagem "RECEBIDA" com reserva "DIVERGENTE" (A07).
6. Datas: `dd/mm/aaaa` nas tabelas, `10–20/01` no banner de viagem semelhante, `mês/ano` na última viagem, `hoje 14:25` na auditoria, `12/09/2026, 13:55` na timeline.
7. Filtro "Ida: próximos 90 dias" → ao trocar vira só "Qualquer".
8. Botão "Editar" presente em algumas linhas da Equipe e ausente em outras (todas abrem ao clicar na linha).
9. Motivo obrigatório ao excluir movimento, opcional ao corrigir.
10. "Nova pendência" de viagem tem "Para quem" (passageiros); da Agenda tem "Pessoa (opcional)".
11. Caption "Comissões a receber" nas abas Recebidas/Divergências.

## 13. Melhorias recomendadas

1. Pré-preencher "Venda ao cliente" com o total da reserva; alertar venda < custo.
2. Resumo da viagem com "Receita prevista" e "Resultado" rotulado como previsto/realizado.
3. Toast de sucesso padrão para ações que só fecham o dialog.
4. Aba/lista "Canceladas com recebimento" na conciliação e alerta de estorno ao cancelar (A23).
5. Mostrar "falta R$ X" em parciais e "+R$ X excedente" em recebidas acima do esperado.
6. Editar/excluir versão de regra de pagamento no mesmo dia; pré-carregar a regra atual; validar cobertura 1–31.
7. Cancelar/revogar convite e excluir colaborador sem histórico.
8. Truncar destino/localizador nas listas (máx. ~60 caracteres visíveis) e limitar no cadastro.
9. Título da aba por rota ("VG-2026-0018 · Meridiano").

## 14. Telas testadas e cobertura

| Tela | Status |
|---|---|
| Login / Esqueci senha / Redefinir senha (token inválido) | TESTADA |
| Viagens › lista (abas, busca, filtros Vendedor/Ida/Tipo/NFSe/Fornecedor/Emissão, ordenação, paginação, estado vazio, URL) | TESTADA |
| Nova viagem (passageiros, + pessoa modal, viagem semelhante, validações, reserva, atalhos Ctrl+S, duplo clique, sair sem salvar) | TESTADA |
| Editar viagem (concorrência 2 abas, vendedor externo/repasse, localizador duplicado) | TESTADA |
| Viagem › Resumo / Reservas (expandir, marcar emitida, voltar a em emissão, serviço, remarcar, NFSe, cancelar reserva c/ crédito, usar crédito) | TESTADA |
| Viagem › Financeiro (receber parcial/excedente, lançar/corrigir/excluir movimento, despesa, período fechado) | TESTADA |
| Viagem › Pendências (criar por passageiro, concluir, adiar, excluir, mostrar concluídas) | TESTADA |
| Viagem › Documentos (anexar .exe/.pdf) | PARCIALMENTE TESTADA — upload bloqueado por B01 |
| Viagem › Timeline | TESTADA (leitura) |
| Transferir viagem / Cancelar viagem (reembolso) | TESTADA |
| Busca global Ctrl+K | TESTADA |
| Clientes › lista (busca, filtros) | TESTADA |
| Cliente › Dados / Documentos / Pendências / Viagens / Atendimentos / Excluir | TESTADA |
| Nova pessoa (página) / Grupos (lista, novo, vincular, excluir) | TESTADA |
| Fornecedores › lista (situação), Novo, Dados, Financeiro (versões da regra), Reservas, inativar | TESTADA |
| Financeiro › Conciliação (Pendentes/Atrasadas/Recebidas/Divergências, lote, receber, encerrar divergência) | TESTADA |
| Financeiro › Repasses (informar valor, histórico) | PARCIALMENTE TESTADA — nenhum repasse liberado para "pagar" |
| Financeiro › Despesas (nova, editar, marcar pago, excluir, filtros) | TESTADA |
| Financeiro › Fechamento (fechar Agosto, lançar em período fechado) | TESTADA — "Reabrir" não exercitado |
| Agenda (Pendências, Embarques, Documentos vencendo, Créditos vencendo, nova pendência solta, próximos 30 dias) | TESTADA |
| Relatórios (KPIs, filtro vendedor, gráfico, CSV) | TESTADA — só ano 2026 disponível |
| Equipe (lista, editar, convidar, e-mail duplicado, sugestão %) | TESTADA — inativar/rebaixar o próprio Dono NÃO FOI POSSÍVEL TESTAR (risco de lockout) |
| Auditoria (filtros, datas invertidas, ver detalhes) | TESTADA — CSV não exercitado |
| Perfis Agente / Vendedor externo / Contador / Financeiro (menu, rotas diretas, API) | TESTADA |
| Responsividade 1920/1366/1280/1024/768/390 | TESTADA (medição automática + screenshots) |
| Teclado / foco / dialogs | TESTADA |
| Resumo diário por e-mail, jobs de pendências automáticas, e-mail de convite/redefinição | NÃO FOI POSSÍVEL TESTAR — sem acesso à caixa de e-mail/jobs |

## 15. Fluxos não testados e motivo

- Guarda de "último Dono" (inativar/rebaixar a si mesmo): único Dono do ambiente; risco de perder o acesso.
- Reabrir período fechado: não exercitado para não invalidar o teste de "lançar em período fechado".
- Pagamento de repasse: nenhuma viagem com todas as comissões recebidas e vendedor externo com valor definido.
- Upload real de anexo e log LGPD de anexo sensível: B01.
- E-mails (convite, redefinição, resumo diário) e jobs noturnos: sem acesso.
- Anos anteriores em Relatórios: só 2026 existe.

## 16. O que está muito bom e deve ser mantido

- Tela única de lançamento com resultado da reserva ao vivo, comissão sugerida pelo %, detecção de viagem semelhante e de localizador duplicado, atalhos de teclado, guard de sair sem salvar (Fechar e menu lateral).
- Concorrência otimista com mensagem clara ("Alguém alterou esta viagem…").
- Conciliação: lote "Marcar recebidas" só para valor igual, recebimento parcial, excedente com confirmação explícita, divergência com motivo e auditoria.
- Fechamento de período: bloqueio real na API com exigência de motivo; auditoria registra.
- Auditoria e timeline completas, inclusive acesso a documento sensível (LGPD).
- Permissões na API (DTO sem campos, 403 com o nome da permissão), lockout, cookie seguro, mensagens genéricas de login, XSS tratado.
- Relatórios e CSV consistentes entre si; KPIs de despesas corretos.
- Acessibilidade de base (foco, dialogs, labels) acima da média.

---

## Veredito

**EU COLOCARIA EM PRODUÇÃO: NÃO** — ainda não, mas está perto.

Motivo: o sistema aceita e salva silenciosamente dados que produzem receita e resultado errados (A02, A03, A12), esconde as colunas financeiras da tela mais usada em notebook (A01), impede cadastrar CPF em cliente existente (A21), expõe comissões da agência ao vendedor externo (P01) e o ambiente não consegue guardar anexos (B01). Nenhum desses exige redesign; são correções pontuais de validação, DTO, CSS e configuração — mas todos atingem exatamente o que o piloto quer validar: confiança nos números e tempo de lançamento.

### Obrigatório antes da produção
1. B01 — storage de anexos + mensagem de erro no upload.
2. A03 — venda ao cliente: pré-preencher/exigir e bloquear receita negativa sem confirmação.
3. A02 — validar taxa ≤ total.
4. A12 — bloquear esperado negativo na remarcação; nunca "recebida" sem movimento.
5. A21 — campo CPF sempre presente para quem tem permissão.
6. A01 — truncar destino/localizador e conter a tabela de viagens.
7. P01 — fechar `/fornecedores` (UI e API) para vendedor externo.
8. F01 — tratar toda resposta ≠ 2xx nos dialogs (excedente, 5xx, upload).
9. M01 — unificar/rotular "recebido" (conciliação × fechamento × relatório).
10. P04 — confirmar guarda de último Dono e desabilitar autoinativação na UI.

### Backlog pós-lançamento
A07, A22, A23, A24, A35, A36, A38, A46, F02, X01–X03, P02, P03, U03 (tipografia), R02/R03 (mobile), inconsistências de verbos/cores/datas, e todos os BAIXOS.

### O que eu não mudaria
Fluxo de lançamento em tela única; modelo de conciliação (parcial/divergência/lote); fechamento com motivo; auditoria; estrutura de permissões na API; design system (hierarquia, espaçamento, cards de KPI) — só ajustar tamanhos mínimos de fonte.

---

## Status das correções (2026-09-13)

Todos os itens de código foram corrigidos na branch `fix/homologacao-3`, mergeada em `main` (backend `86f0b54`, frontend `a2e0a25`) — ver `docs/BACKLOG.md` "Homologação 2026-09-12 (rodada 3)" para a lista completa, os deferidos com motivo e as deviações do design registradas. Evidências pós-correção (vite dev @1366 contra a API local): `evidencias-2026-09-12/apos-fix-1366-viagens.jpeg` (7 colunas visíveis, tabela = contêiner 1083 px), `apos-fix-1366-relatorios.jpeg` (3 + 3 KPIs); 390 px sem scroll horizontal em Viagens/Financeiro/Despesas/Relatórios.

**Fica com a operação:** B01 (`Armazenamento__Endpoint` do piloto → R2/MinIO acessível pelo navegador; o front agora mostra "Não foi possível enviar o arquivo ao armazenamento (<host>…)" em vez de silêncio) e a aplicação da migration 0023 no banco de piloto (saneia `valor_cliente = 0` → total nas reservas legadas, o que corrige o RAV −total do VG-2026-0018 e similares).

Veredito revisado: com B01 resolvido na configuração, **EU COLOCARIA EM PRODUÇÃO: SIM** (piloto).
