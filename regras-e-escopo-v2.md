# Sistema de Gestão de Agência de Viagens — Regras e Escopo v2

Substitui a v1. Incorpora as decisões tomadas em 2026-09-07 sobre a análise
arquitetural (`docs/analise-arquitetural-v1.md`). Referência para o
desenvolvimento e contexto para qualquer sessão futura. O schema
correspondente é `schema-agencia-v2.sql`.

---

## 1. O que o sistema é

Backoffice de **vendas, comissões e operação** de uma agência de viagens de
lazer. Não vende: as vendas acontecem nos portais das operadoras e
consolidadoras e são **lançadas aqui pela agência** para alimentar
conciliação, repasse, dashboard e agenda.

Fronteira explícita: registra o resultado financeiro da agência (o que ela
recebe e paga por reserva). Não é contabilidade — sem plano de contas, sem
conciliação bancária, sem folha.

Piloto: uma agência. **Nasce multiempresa**: `agencia_id` em toda tabela de
tenant, isolamento por policy no Postgres, código de viagem sequencial por
agência, pasta por agência no storage.

## 2. Glossário

| Termo | Definição |
|---|---|
| **Pessoa / cliente** | Registro em `cliente`. Todo viajante é uma pessoa; a viagem não tem "cliente responsável" — o passageiro **titular** é o contato e o nome que identifica a viagem. |
| **Viagem** | O processo: passageiros (um titular), um destino, um período, tipo **nacional** ou **internacional**. Agrupa reservas. |
| **Reserva** | Uma compra num portal/fornecedor. Tem localizador, valores e conciliação própria. |
| **Serviço** | Item entregue ao viajante dentro de uma reserva: aéreo, hotel, seguro, passeio. |
| **Fornecedor** | Quem a agência compra: operadora, consolidadora, cia aérea, hotel, seguradora, receptivo. Sempre existe, mesmo em venda direta. |
| **Valor total** | O que o fornecedor cobra pela reserva, com taxas. Em BRL. |
| **Valor cliente** | O que o cliente paga no total pela reserva. Em BRL. |
| **RAV da operadora** | Incentivo pago pela operadora à agência, somado à comissão. Digitado. |
| **RAV do cliente** | `valor_cliente − valor_total`. Calculado. Negativo = desconto concedido. |
| **Modo do RAV do cliente** | Como esse valor vira caixa: **retido pela agência** (cliente pagou a diferença à agência no ato) ou **via operadora** (a operadora cobra o total e devolve o RAV junto com a comissão). |
| **Valor esperado da operadora** | O que a agência espera receber da operadora por esta reserva: `comissão + RAV operadora + (RAV cliente, se via operadora)`. Calculado. É o alvo da conciliação. |
| **Receita prevista** | Resultado esperado da agência na reserva (competência): `comissão + RAV operadora + RAV cliente + taxa de serviço`. Calculado. |
| **Movimento financeiro** | Um evento de caixa ligado a uma reserva: recebimento da operadora, recebimento do cliente, pagamento ao fornecedor, estorno, reembolso. Com data e valor. |
| **Receita recebida** | Soma dos movimentos da reserva (entradas positivas, saídas negativas). Caixa. |
| **Conciliação** | Comparar o recebido da operadora com o valor esperado. Fecha quando iguala, ou manualmente com motivo de divergência. |
| **Repasse** | Valor pago ao vendedor externo por uma viagem. **Digitado pelo dono**, não calculado. |
| **Competência** | Mês de referência. Comercial: mês da `data_compra` da reserva. Financeira: mês da `data_movimento`. |
| **Período fechado** | Mês cujas reservas e movimentos só podem ser editados com permissão específica e motivo. |

## 3. Modelo central

| Nível | O que é | Quem enxerga |
|---|---|---|
| **Viagem** | O processo | O passageiro titular |
| **Reserva** | Uma por portal/compra | A operadora |
| **Serviço** | Aéreo, hotel, seguro, passeio | O viajante |

Uma viagem que usou 4 portais = 1 viagem, 4 reservas, N serviços.

Regras estruturais:
- Toda reserva tem `fornecedor_id`, escolhido num **select** do cadastro de fornecedores. "Venda direta" é ausência de intermediário, não de fornecedor. Fornecedor novo entra pelo cadastro, não inline.
- Toda reserva marca **o que foi vendido** em `tipos_servico[]` (aéreo, hospedagem, seguro, traslado, passeio, ingresso, aluguel de carro, documentação, outro) — vários por reserva; é o corte dos relatórios. O detalhe operacional (voo, bilhete, quarto) fica em `servico`, opcional.
- `viagem.tipo` é `nacional` ou `internacional` — corte principal dos relatórios.
- Não existe "cliente responsável". Todo passageiro é um registro em `cliente` (pessoa); `viagem_passageiro` liga pessoa à viagem e marca o **titular** (contato, nome nas listas, aviso de viagem duplicada). Documentos e alertas de validade valem para todos os viajantes.
- `viagem.vendedor_id` é obrigatório: quem vendeu. `viagem.agente_id`: quem opera (transferível).
- Horários de serviço (voo, check-in) são **hora local do lugar**, sem fuso (`timestamp`). Carimbos de sistema são `timestamptz`.

## 4. Regras financeiras

### 4.1 Valores digitados por reserva
`valor_total` (o total cobrado pelo fornecedor — **as taxas já estão dentro dele**; `valor_taxas` é só quanto desse total é taxa, informativo), `valor_comissao`, `rav_operadora`, `valor_cliente` (o que o cliente pagou no total), `taxa_servico` (opcional, ver 4.2), `rav_cliente_modo`, `tipos_servico[]`, `formas_pagamento[]` (pix, boleto, cartão — pode marcar mais de uma) e `cartao_de` quando houver cartão. Tudo em **BRL**. Se a compra foi em outra moeda, `moeda`, `cambio` e `valor_total_original` são informativos.

Pré-preenchimento (requisito de velocidade): `valor_comissao` sugerido por `fornecedor.percentual_comissao_padrao × valor_total`; `taxa_servico` sugerida pela configuração da agência. Usuário só corrige.

### 4.2 Como a receita é calculada
Não existe campo "tipo de receita": a fórmula é uma só e o rótulo, quando um relatório precisar, é derivado (`valor_comissao > 0` → comissionada; senão → markup). **Taxa de serviço** é um campo opcional, normalmente zero: valor fixo que a agência cobra do cliente sem custo por trás (assessoria, emissão de passaporte, visto). Se a agência não cobra isso, fica escondido em "mais campos".

```
rav_cliente               = valor_cliente − valor_total
valor_esperado_operadora  = valor_comissao + rav_operadora + (rav_cliente se rav_cliente_modo = via_operadora)
receita_prevista          = valor_comissao + rav_operadora + rav_cliente + taxa_servico
```

Venda com markup (passeio direto, transfer): `valor_comissao = 0`, `rav_operadora = 0`, `valor_total` = custo → receita = o que o cliente pagou acima do custo. **O que o cliente pagou acima do total vira RAV do cliente automaticamente**, sem digitar nada.

Reserva cancelada sem `comissao_mantida`: esperado e prevista valem 0.

### 4.3 Fluxo do dinheiro
Padrão: **cliente paga direto à operadora** (`fluxo_pagamento = cliente_paga_operadora`). Exceção: pix/boleto para a agência, que então paga o fornecedor (`cliente_paga_agencia`). `formas_pagamento[]` registra com o que o cliente pagou (pix, boleto, cartão — multi). O sistema não parcela; registra o que aconteceu.

Movimentos (`movimento_financeiro`), sempre por reserva, com data e valor:

| Tipo | Sinal | Quando |
|---|---|---|
| `recebimento_operadora` | + | Comissão / RAV da operadora entrou |
| `recebimento_cliente` | + | Cliente pagou à agência (taxa de serviço, RAV retido, pix/dinheiro) |
| `pagamento_fornecedor` | − | Agência pagou o fornecedor (fluxo `cliente_paga_agencia`) |
| `estorno_operadora` | − | Operadora cobrou de volta comissão já paga |
| `reembolso_cliente` | − | Agência devolveu dinheiro ao cliente |

`receita_recebida = Σ valor`. Contas a receber do cliente = reservas com `cliente_paga_agencia` cujo `Σ recebimento_cliente < valor_cliente`.

Atalho de tela: "marcar comissão recebida" cria um `recebimento_operadora` com o valor esperado e a data de hoje, num clique. Digitação extra zero no caso comum.

### 4.4 Conciliação
Reserva está **conciliada** quando `Σ (recebimento_operadora + estorno_operadora) ≥ valor_esperado_operadora`, ou quando `conciliacao_encerrada = true` com `divergencia_motivo` (operadora pagou menos e não vai pagar o resto). Reserva com esperado = 0 não entra na conciliação.

### 4.5 Previsão de pagamento da comissão
Por fornecedor, em janelas (`regra_pagamento_fornecedor`: vendas de 1 a 14 pagam dia 20; de 15 a 31 pagam dia 5 do mês seguinte) ou prazo em dias. A API calcula `data_prevista_comissao` ao criar a reserva, **grava** e mantém editável. Dia inexistente no mês → último dia do mês.

### 4.6 Alterações e multa
Remarcação/alteração vira linha em `reserva_alteracao` (data, descrição, valor anterior/novo, multa informativa, quem). Multa é **informativa**: paga pelo cliente à operadora, não afeta receita nem repasse.

### 4.7 Cancelamento
Reserva: `status = cancelada`, `cancelada_em`, `motivo_cancelamento` obrigatório, `desfecho_cancelamento` ∈ {`sem_reembolso`, `reembolso`, `credito`}, `valor_reembolso` quando houver, `comissao_mantida` quando a operadora mantém a comissão. Desfecho `credito` cria linha em `credito` (cliente, fornecedor, valor, validade), que depois é vinculada à reserva que o consumir. Estorno de comissão já recebida = movimento `estorno_operadora`. Devolução ao cliente pela agência = `reembolso_cliente`.

Viagem: `cancelada` é manual. Cancelar a viagem exige que toda reserva ativa seja cancelada antes (ou junto, na mesma ação). Repasse já pago de viagem cancelada: registrado como está; ajuste é decisão do dono, fora do sistema.

### 4.8 NFSe
Por reserva: `nfse_status` ∈ {`falta_emitir`, `emitido`, `nao_precisa`}, `nfse_tomador` ∈ {`cliente`, `operadora`}, `nfse_numero`, `nfse_data_emissao`.

### 4.9 Imposto
MEI: DAS é despesa fixa (v1.1). Dashboard monitora receita recebida acumulada no ano (caixa, por `data_movimento`) contra `agencia.config.teto_mei` (R$ 81.000 em 2026), alerta em 80%.

> **Pendente com o contador:** se a receita bruta do MEI é só a receita da agência (comissão + RAV + taxa) ou o valor total das viagens, e por caixa ou competência. A view usa caixa sobre receita da agência até resposta.

## 5. Repasse ao vendedor externo

- Uma linha em `repasse` por viagem com vendedor que `gera_repasse`. Criada com a viagem.
- **`valor` é digitado pelo dono.** `usuario.percentual_padrao` existe só como sugestão na tela.
- Status: `bloqueado` → `a_pagar` → `pago`. Vai a `a_pagar` quando toda reserva ativa da viagem com esperado > 0 está conciliada (calculado pela API ao registrar movimento). Pagamento: `pago_em`, em lote por vendedor ("pagar todos a_pagar de fulano").
- Entra na DRE (v1.1) como despesa, lido daqui — não há segunda fonte.
- Dono e agentes internos têm `gera_repasse = false`. Pró-labore do dono é despesa fixa (v1.1).

## 6. Status — dois eixos, calculados

**Operacional** (`vw_fase_viagem.fase_operacional`):
`cancelada` (manual) → senão `concluida` se `data_volta < hoje` → `em_viagem` se `data_ida ≤ hoje` → `em_emissao` se alguma reserva ativa `pendente` → `confirmada` se há reserva ativa → `sem_reserva`.

**Financeiro** (`fase_financeira`), sobre reservas ativas com esperado > 0:
`sem_receita` se não há nenhuma → `quitada` se todas conciliadas → `atrasada` se alguma não conciliada com `data_prevista_comissao < hoje` → `parcial` se alguma conciliada → `a_receber`.

## 7. Pessoas, perfis e permissões

### 7.1 Perfis (fixos em código na v1)

| Perfil | Vê | Faz |
|---|---|---|
| **Dono** | Tudo | Tudo |
| **Financeiro** | Viagens, valores, resultado, relatórios | Movimentos, conciliação, repasses, fechamento, NFSe |
| **Agente** | Viagens, valores de reserva (custo/comissão), clientes, documentos | Lança viagens/reservas/serviços, clientes, fornecedores, anexos, tarefas. Não vê resultado da agência nem repasse. |
| **Vendedor externo** | **Somente leitura.** Próprias viagens: código, destino, datas, cliente, valor vendido, status do repasse e **valor do repasse dele**. Clientes: só os que têm viagem dele. | Nada. Não lança. |
| **Contador** | Relatórios financeiros, DRE (v1.1), auditoria. Somente leitura. | Nada. |

Permissões nomeadas (`modulo.acao`) numa matriz `Perfil → Permissao[]` em C#, com teste. Tabelas de perfil/permissão entram quando uma agência precisar de perfil customizado.

### 7.2 Visibilidade de valor
As permissões que importam: `reserva.ver_valores`, `viagem.ver_resultado`, `repasse.ver_todos`, `financeiro.ver_dre`, `cliente.ver_documento`. Enforçadas na **API**: o DTO simplesmente não contém o campo. Esconder na tela não protege; o navegador não acessa o banco.

**Vendedor é posição na viagem; perfil é permissão.** Dono que vende aparece como vendedor e continua vendo tudo.

### 7.3 Usuários e login
- Autenticação **própria** na API: e-mail + senha (hash PBKDF2/Argon2), sessão por cookie HttpOnly. Cadastro público desligado; dono convida por e-mail (token com validade). Reset de senha por token.
- `usuario` pode existir **sem login** (`senha_hash` nulo): vendedor externo que só é referenciado.
- `unique (agencia_id, email)`.
- Vendedor da viagem vem preenchido com o usuário logado; trocar exige `viagem.definir_vendedor`.
- Usuário nunca é excluído, só inativado. Tentativas de login em `log_acesso`; bloqueio progressivo após falhas.

## 8. Auditoria e controles

- **Log campo a campo por trigger** em `viagem`, `reserva`, `servico`, `movimento_financeiro`, `repasse`, `usuario`, `cliente`. O trigger lê `app.usuario_id` e `app.motivo` da sessão (a API define por request). Colunas derivadas ficam fora do log.
- **Timeline legível** na tela da viagem: consulta em `auditoria` por viagem + suas reservas/serviços/movimentos, com frases.
- **Soft delete** (`excluido_em`, `excluido_por`) em tudo que tem valor financeiro ou histórico. FKs financeiras são `restrict`; exclusão propaga pela API.
- **Motivo obrigatório** ao cancelar, excluir, editar reserva conciliada ou de período fechado.
- **Período fechado** (`fechamento_periodo`): mês fechado pelo Financeiro/Dono. Reserva com `data_compra` no mês, ou movimento com `data_movimento` no mês, só edita com `financeiro.editar_periodo_fechado` + motivo. Verificação na API.
- **Concorrência**: `xmin` enviado ao cliente e conferido no UPDATE; conflito devolve 409.
- **LGPD**: `log_acesso_documento` grava quem viu qual documento/anexo sensível e quando. Anexos em bucket privado com URL assinada e `data_descarte`; job apaga arquivo e linha.
- **Retenção** da auditoria: job mensal expurga acima de `agencia.config.retencao_auditoria_meses` (padrão 24), preservando `DELETE`.

Descartado: aprovação em duas etapas, segregação de funções.

## 9. Operacional

- Histórico de alteração/remarcação; crédito com validade; checklist de requisitos do destino (v1.1); dados do aéreo em `servico.detalhe` (bilhete, localizador da cia, voo, horário local, bagagem, assento); contato de emergência do fornecedor; ocasião da viagem; anexo por reserva; transferência de viagem entre agentes.
- **Aviso de viagem duplicada**: ao criar viagem para cliente com viagem não concluída, três saídas — abrir a existente, adicionar a reserva nela, criar assim mesmo. Aviso mais forte se as datas se sobrepõem. Nunca bloqueio.
- **Aviso de reserva duplicada**: mesmo `fornecedor_id + localizador` na agência. Aviso, não bloqueio.
- Vencimento de pagamento à operadora: **fora** (decisão mantida da v1; ver pendências).

### Automações (API, não trigger)
- Ao criar/alterar datas da viagem: tarefas `checkin` (ida − 3), `posviagem` (volta + 3), `recompra` (volta + 330), responsável = agente. Remarcação reabre tarefa concluída se a data mudou. Cancelar viagem cancela as tarefas automáticas.
- Job diário: tarefa de validade de passaporte (180 dias antes) para **toda pessoa** com documento; resumo por e-mail.
- Jobs mensais: expurgo de auditoria; expurgo de anexos vencidos.

## 10. Escopo

### Versão 1 — a operação e o dinheiro
Login, usuários, perfis fixos · clientes/pessoas e CRM básico · fornecedores com regra de pagamento e % padrão · viagem, passageiros, reserva, serviço · movimentos, conciliação, cancelamento com desfecho, crédito · repasse manual com status e lote · fechamento de período · NFSe por reserva · anexos com log de acesso · dashboard, fases, comissões pendentes, ranking, teto MEI · busca global · agenda e tarefas automáticas · resumo diário por e-mail · auditoria e timeline · exportação CSV.

### Versão 1.1 — depois de um mês de uso real
Despesas e DRE simplificada · reembolso com fluxo próprio · checklist de requisitos do destino · metas por vendedor · automações de recompra do CRM · importação da planilha · modelos de mensagem para WhatsApp.

### Fora de escopo
Orçamento e cotação · geração de voucher/contrato · integração com operadoras · gateway de pagamento · API do WhatsApp · emissão de bilhete · parcelamento próprio.

## 11. Infraestrutura e stack

Critério: API na Azure; todo o resto no nível gratuito, sem dado real fora do controle da agência.

| Camada | Escolha | Custo | Observação |
|---|---|---|---|
| API | **ASP.NET Core 10 Minimal API** em **Azure Container Apps** (consumo, `min replicas 0`) | Grátis dentro da cota mensal (180k vCPU-s, 2M req) | Cold start de alguns segundos após ociosidade; subir para `min 1` custa ~US$ 10/mês se incomodar |
| Jobs | **Azure Container Apps Jobs** (cron) rodando a mesma imagem com `job <nome>` | Mesma cota | `BackgroundService` não roda com zero réplicas; por isso jobs separados |
| Banco | **Postgres no Supabase free** (somente Postgres; sem Auth/Storage do Supabase) | Grátis, 500 MB | Conectar pelo **pooler em modo sessão** (IPv4). Pausa após 7 dias sem uso: o job diário impede. Alternativa equivalente: Neon free |
| Migrations | **DbUp** com scripts SQL embutidos, executado no startup da API | — | SQL-first, combina com Dapper |
| Acesso a dados | **Dapper + Npgsql** | — | Toda query filtra `agencia_id` e `excluido_em is null`; policy de tenant no Postgres é a rede de segurança |
| Auth | Própria (hash + cookie + convite/reset) | — | Nada para migrar |
| Frontend | **React + Vite + TypeScript**, build copiado para `wwwroot` e servido pela API | — | Mesma origem: cookie, sem CORS. PWA. Domínio custom com certificado gerenciado do Container Apps |
| Storage | **Cloudflare R2** via SDK S3 | Grátis até 10 GB, sem egress | Interface `IArmazenamentoArquivo` (salvar, URL assinada, excluir) |
| E-mail | **Resend** | Grátis até 3 mil/mês | Resumo diário, convite, reset |
| Logs | Serilog → console JSON → **Log Analytics** do Container Apps | Grátis até 5 GB/mês | `agencia_id`, `usuario_id`, `request_id` em todo log |
| Uptime | UptimeRobot no `/health` | Grátis | — |
| CI/CD | **GitHub Actions** → GHCR → `az containerapp update` | Grátis | Testes com Testcontainers no runner |
| Backup | GitHub Actions cron diário: `pg_dump` → R2, retenção 30 dias; restauração testada trimestral | Grátis | Sem isso o backup não existe |
| Dev local | `docker compose` com Postgres | — | Nada de Supabase local |

Tenant no banco: a API abre cada transação com `SET LOCAL app.agencia_id`, `app.usuario_id`, `app.motivo`. Policies `agencia_id = current_setting('app.agencia_id')::uuid` em toda tabela de tenant, role da API sem ownership das tabelas. Um `where` esquecido no Dapper devolve lista vazia, nunca dado de outra agência.

Sem: Redis, fila, MediatR, CQRS, repository, microserviços, Kubernetes.

## 12. Decisões registradas (2026-09-07)

| # | Decisão | Resposta |
|---|---|---|
| 1 | Stack | Melhor e gratuita: Azure Container Apps + Supabase Postgres + R2 + Resend |
| 2 | Autorização | Negócio no C#; tenant por policy no Postgres |
| 3 | Vendedor externo | Só visualização |
| 4 | Fluxo de pagamento | Cliente paga direto à operadora; pix/dinheiro passa pela agência |
| 5 | RAV | Fica com a agência; repasse é digitado pelo dono |
| 6 | Multa | Informativa, não interfere |
| 7 | Cancelamento | Caso a caso: sem reembolso, reembolso ou crédito — registrado por desfecho |
| 8 | RAV do cliente | Dois modos: retido pela agência ou via operadora |
| 9 | Competência | Mês da data (compra para comercial, movimento para financeiro) |
| 10 | NFSe | Por reserva |
| 11 | Moeda | Tudo em BRL |
| 12 | Passageiro | É pessoa em `cliente` |
| 13 | Acesso a dados | Dapper |
| 14 | Frontend | React |
| 15 | Perfis | Fixos em código na v1 |
| 16 | Clientes visíveis ao vendedor externo | Só os com viagem dele |
| 17 | Vencimento à operadora | Mantido fora (ver pendência) |
| 18 | Infra | API na Azure; resto gratuito |
| 19 | Cliente responsável | Não existe; passageiro titular identifica a viagem |
| 20 | Fornecedor | Select do cadastro; sem criação inline |
| 21 | Viagem nacional/internacional | `viagem.tipo`, obrigatório |
| 22 | Serviços vendidos | `reserva.tipos_servico[]`, multi, para relatórios |
| 23 | Tipo de receita | Removido; derivado |
| 24 | Formas de pagamento | pix, boleto, cartão — multi |
| 25 | Comissão do vendedor externo e NFSe | Na tela de lançamento: `repasse.valor` (quando o vendedor gera repasse) e `nfse_status` |

### Pendências
- **Contador**: base e regime da receita bruta do MEI (4.9).
- **Decisão 17**: "vencimento à operadora" é a data-limite que a operadora dá para pagar/emitir uma reserva antes de cancelá-la automaticamente (ex.: "opção de hotel até 15/03"). Custa uma coluna `vencimento_fornecedor date` nula e um alerta na agenda. Fica fora até você dizer que quer.
- **Piloto**: validar as fórmulas de 4.2 com três viagens reais da planilha antes da Fase 3.

## 13. Exemplos numéricos

**A — Comissionada simples, cliente paga à operadora**
`valor_total 10.000`, `valor_comissao 1.000`, `rav_operadora 100`, `valor_cliente 10.000`, `taxa_servico 0`.
→ `rav_cliente 0`, `esperado_operadora 1.100`, `receita_prevista 1.100`. Recebida = 0 até entrar `recebimento_operadora 1.100`.

**B — Com RAV do cliente via operadora**
Igual a A, mas `valor_cliente 10.500`, `rav_cliente_modo via_operadora`.
→ `rav_cliente 500`, `esperado_operadora 1.600`, `receita_prevista 1.600`. Conciliada ao receber 1.600 da operadora.

**C — Com RAV retido pela agência (cliente pagou a diferença por pix)**
Igual a B, mas `rav_cliente_modo retido_agencia`.
→ `esperado_operadora 1.100`, `receita_prevista 1.600`. No lançamento, movimento `recebimento_cliente 500`. Conciliada ao receber 1.100 da operadora. Recebida total = 1.600.

**D — Markup (passeio direto)**
`valor_total 800` (custo), `valor_cliente 1.000`, `fluxo cliente_paga_agencia`, `tipos_servico {passeio}`, `formas_pagamento {pix}`.
→ `rav_cliente 200`, `esperado_operadora 0`, `receita_prevista 200`. Movimentos: `recebimento_cliente +1.000`, `pagamento_fornecedor −800`. Recebida = 200. Não entra na conciliação.

**E — Cancelamento com crédito**
Reserva A cancelada, operadora não paga comissão, cliente fica com crédito de 9.000 válido por 12 meses.
→ `status cancelada`, `desfecho credito`, `comissao_mantida false` → esperado e prevista = 0. Linha em `credito` (9.000, validade). Se a comissão já tinha entrado e a operadora estornou: movimento `estorno_operadora −1.100`.

## 14. O risco número um

**Tempo de lançamento.** Uma viagem de 4 portais em 20 minutos mata a piloto em três semanas. Medir no primeiro teste real e tratar como requisito: pré-preenchimento (E-22), criação inline de pessoa e fornecedor, teclado sem mouse, salvar parcial, teste E2E cronometrado desde a primeira tela.
