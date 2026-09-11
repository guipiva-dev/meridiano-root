# Meridiano — Fase 3.6 — Agenda, Relatórios, Equipe, Auditoria, jobs + piloto: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execução em ondas:** segue `.claude/rules/parallel-subagent-driven-development.md` e as regras de implementador em `.superpowers/sdd/regras-implementador.md` (adaptar branch para `feat/fase-3-6`). Implementadores **não commitam**; o controlador commita uma task por vez, no repo certo, com pathspec. Teto: **6 implementadores simultâneos, 4 no backend**. `--artifacts-path` privado em todo `dotnet build/test`. Agentes especialistas da tabela do CLAUDE.md não existem no harness: usar `general-purpose` para implementar e `code-reviewer` genérico para revisar (Auth/RLS: revisar com foco de `security-reviewer`).

**Goal:** fechar a v1 (spec §10): Agenda com tabs (Pendências · Embarques e retornos · Documentos vencendo · Créditos vencendo) e badges na sidebar; Relatórios do ano com fórmulas documentadas (competência × caixa × previsto separados) e CSV; Equipe e acessos (colaborador sem acesso, convite, reenvio, estados derivados, último dono protegido); Auditoria geral com filtros, cursor, LGPD (`log_acesso_documento`) e CSV; RLS em `log_acesso`; jobs `pendencias_derivadas`, `resumo_diario_email`, `expurgo_auditoria`, `expurgo_anexos`; Contador vê repasses; telas 18–22 do protótipo congelado; E2E; docs de fechamento da Fase 3.

**Architecture:** três módulos novos no backend (`Modules/Agenda`, `Modules/Relatorios`, extensão de `Modules/Auditoria`), `Modules/Admin` vira Equipe (DTO com estado de acesso, criar sem acesso, convite/reenvio via `ConviteService`), quatro jobs em `Jobs/` sobre `IJob`/`JobRunner` já existentes, migration **0016** (RLS `log_acesso`, índices redundantes). Nenhuma view nova: relatórios consultam tabelas com filtro de ano (as `vw_*` de dashboard não filtram ano e não são alteradas). Front: quatro páginas novas (`pages/{agenda,relatorios,equipe,auditoria}`), rotas por página (padrão C3 de 3.4/3.5), badges na `Sidebar`, helper `lib/download.ts` para CSV; `components/Pendencias` ganha escopo `agenda`.

**Tech Stack:** .NET 10 · Dapper · Npgsql · DbUp · PostgreSQL 17 · xUnit + Testcontainers · Resend (`IEnviadorEmail`) · R2/S3 (`IArmazenamentoArquivo`) · React 19 · react-router · TanStack Query 5 · Vitest · Playwright. Nenhuma dependência nova (gráfico de barras é CSS).

**Spec:** `regras-e-escopo-v2.md` §4.2/§4.3 (fórmulas de receita e caixa), §4.9 (teto MEI), §6.1 (estados: pendência, acesso do colaborador), §7.1/§7.3 (perfis, convite, `log_acesso`), §8 (auditoria, retenção, LGPD, expurgo de anexos), §9 "Automações" (pendências derivadas por `chave_unica`, resumo por e-mail, jobs mensais), §10 (dashboard, ranking, teto MEI, CSV, resumo diário), decisões 22, 34, 36, 45 · plano-mestre `2026-09-08-fase-3-master.md` linha 3.6 + "Contratos transversais" (Jobs, Anexos, Autorização por operação) · `docs/design-system-contrato.md` §3, §4.2 (badges da sidebar), §4.3 (pendências → agenda), §7 (teste de UX) · `docs/design/prototipo-v1.html` `#s-agenda` `#s-relatorios` `#s-equipe` `#s-colaborador` `#s-auditoria` · `docs/autorizacao-por-operacao.md` · `docs/BACKLOG.md` (deferidas: badge de comissões atrasadas, Contador 403 em repasses, RLS `log_acesso`, `ix_pendencia_viagem`/`ix_interacao_cliente` redundantes, expurgo de anexos).

**Estado de partida:** `main` nos dois repos (backend `16d9c65`, frontend `f5a4884`), migrations 0001–0015, 226 testes API + 26 domínio, 402 Vitest, Playwright `nova-viagem`/`viagens`/`cadastros`/`financeiro` verdes. Branch de trabalho: `feat/fase-3-6` em `backend/` e `frontend/`; root só docs.

## Global Constraints

- Backend: `TreatWarningsAsErrors=true`; `dotnet format` limpo; ≤ ~350 linhas por arquivo. Toda query em `DbSessao`, filtra `agencia_id` e `excluido_em is null`; `*Proprias` via `apenasVendedor` (`null` = sem restrição, padrão `VisibilidadeCliente`/`PendenciasService.ApenasVendedor`). Erros `RegraDeNegocioException` → 422 com `codigo`; 403 `sem_permissao` no padrão `RequerPermissao`. Listas paginadas `pagina`/`tamanho ≤ 100`/`total` onde o contrato pede; arrays nunca `null`. Dinheiro `decimal` 2 casas. `DateTime.Today`/`current_date` para "hoje" (nunca `UtcNow`, ruling da revisão de 3.5).
- Jobs: `IJob { Nome, PorAgencia, ExecutarAsync(Guid? agenciaId, ct) }`, registrados em `Jobs/JobsExtensions.cs`, sessão por agência via `sessoes.AbrirAsync(new ContextoSessao(agencia, null, "job <nome>"), ct)`, idempotentes (rodar duas vezes = mesmo estado), **nenhuma transação aberta durante chamada ao R2 ou ao Resend**.
- Autorização: `Permissao.RelatorioVer` (Dono, Financeiro, Contador) para Relatórios e CSV; `AuditoriaVer` (Dono, Financeiro, Contador) para Auditoria; `UsuarioGerenciar` (Dono) para Equipe; Agenda = `ViagemVer` ou `ViagemVerProprias` (externo só o próprio universo). Projeção por perfil: `ProjecaoAuditoria` (valores, resultado, **documento**); Agenda omite `numero` de documento sem `ClienteVerDocumento`; Relatórios não precisam projetar (os três perfis com `RelatorioVer` têm `ReservaVerValores` e `ViagemVerResultado` — fixado em teste de domínio).
- Front: CSS Modules + `tokens.css`; sem hex/`font-size`/`@media` fora de 700/1024/1280/1366/1440; só lucide; ≤ 350 linhas/arquivo; `lint`/`typecheck`/`test`/`build` verdes; `pode()` só esconde. Status de domínio por `apresentacaoStatus()` (mapas `pendencia`, `acesso`, `fase_operacional` já existem). Rotas por página (`pages/<x>/rotas.tsx` + `shell/rotas<X>.tsx`). Nada de biblioteca de gráfico: barras em CSS com `aria-label` textual.
- CSV: gerado no backend (`Meridiano.Domain/Comum/Csv.cs`): UTF-8 com BOM, separador `;`, decimal com vírgula, datas `dd/MM/yyyy`, carimbos `dd/MM/yyyy HH:mm`, booleano `Sim`/`Não`, campo com `;`/`"`/quebra de linha entre aspas duplas (aspas dobradas). `Content-Type: text/csv; charset=utf-8`, `Content-Disposition: attachment; filename="..."`. Mesma projeção do DTO da tela.
- Commits Conventional Commits em inglês com rodapé de atribuição da sessão.

---

## Rulings desta fase

| # | Decisão | Motivo |
|---|---|---|
| R1 | **Agenda segue o protótipo** (4 tabs: Pendências com grupos Atrasadas · Hoje · Esta semana; Embarques e retornos; Documentos vencendo; Créditos vencendo), não a linha do mestre ("Hoje · Semana · Atrasadas"). `vw_agenda` **não é usada** (faltam pax, fase, próxima viagem, documento) nem alterada; `AgendaSql` consulta as tabelas. Listas sem paginação, teto 100 por bloco (paginação "1–3 de 6" do protótipo → BACKLOG). | Protótipo congelado vence (ruling 3.3 R3); view seria refeita para nada. |
| R2 | **Janelas:** pendências `semana` = `data_prevista` em `(hoje, hoje+7]`; embarques = `data_ida` em `[hoje, hoje+14]`, viagem não cancelada; retornos = `data_volta` em `[hoje, hoje+14]`; documentos = passaporte com `validade ≤ hoje+210` **ou** cliente sem passaporte com viagem internacional futura; créditos = `status='disponivel'` e `validade ≤ hoje+60`. | Mesmas janelas de `vw_agenda` (0001) e do protótipo ("próximos 14 dias"). |
| R3 | **"+ Nova pendência" na Agenda** = `POST /pendencias` (pendência solta: sem viagem, `clienteIds` opcional) em `Modules/Pendencias` (T1 é dona). Front: `EscopoPendencias` ganha variante `{ agenda: true; responsavelId: string \| null }`. | Spec §9: viagem/pessoa são opcionais. |
| R4 | **Badges** (contrato §4.2) = `GET /agenda/badges` → `{ agenda, financeiro?, clientes? }`: `agenda` = pendências abertas com `data_prevista ≤ hoje` (hoje + atrasadas) no universo do usuário; `financeiro` = reservas `aguardando_operadora` com `data_prevista_comissao < hoje` (só com `FinanceiroMovimentar`/`Conciliar`/`VerDre`, senão `null`); `clientes` = `count(distinct cliente_id)` de pendências abertas (só com `ClienteVer`/`ClienteVerProprios`). `Sidebar` consulta a cada 5 min e no foco da janela. Fecha a deferida de 3.5 (badge de comissões atrasadas). | Um endpoint, três números. |
| R5 | **Aniversários:** sem job. `GET /clientes/aniversarios?dias=7` (derivado de `cliente.data_nascimento`, em `Modules/Agenda`) alimenta o resumo diário; a Agenda não os mostra (não está no protótipo → BACKLOG "aniversariantes na Agenda"). | Estado derivável; job só duplicaria linhas. |
| R6 | **Relatórios: três eixos separados, nunca somados entre si.** *Competência* (`reserva.data_compra`): venda, previsto, fornecedores, serviços, nacional × internacional. *Caixa* (`movimento_financeiro.data_movimento`, os 5 tipos, sinal do banco): receita recebida, receita por mês (barra escura), teto MEI (`vw_teto_mei`). *Despesas* (`despesa.pago_em`, `pago = true`). `vw_resultado_viagem` **não** entra em nenhum número mensal/anual (mistura previsto com caixa por viagem). Fórmulas completas na seção "Fórmulas" abaixo; T12 copia para `docs/relatorios-formulas.md`. | Mestre linha 3.6; spec §4.2/§4.3. |
| R7 | **Filtro de vendedor** (`viagem.vendedor_id`) aplica a venda/previsto/recebido/fornecedores/serviços/nacional×internacional. **Despesas** com vendedor selecionado = só despesas ligadas a viagens do vendedor (fixas = 0; helper na tela); **teto MEI ignora** o filtro (é da agência). `tipos_servico[]`: uma reserva com N tipos conta em N barras ("reservas que incluem cada serviço"); a soma das barras não é o total de reservas (rótulo diz isso). | Sem dupla contagem no total; barras são "quantas reservas incluem X". |
| R8 | **CSV** de Relatórios = uma linha por reserva do universo do ano (inclui canceladas com coluna `Status`); sem coluna de resultado por viagem (a tela também não tem). CSV de Auditoria = os eventos do filtro, sem cursor, teto 5000 linhas. Download no front por `lib/download.ts` (`<a href download>` criado e clicado; cookie same-origin). | Mesma projeção da tela (autorização por operação, linha `GET /relatorios/*`). |
| R9 | **Contador ganha `RepasseVerTodos`** (`Permissoes.cs`, T0): repasse é custo da DRE (spec §5) e Contador é leitura de "relatórios financeiros". `RepassePagar` continua fora. Fecha a deferida E4 de 3.5. | Spec §7.1; único bloqueio era `Permissoes.cs` congelado no paralelo. |
| R10 | **Equipe:** `UsuarioDto` vira `ColaboradorDto` com `acesso` derivado (`inativo` se `!ativo`; `acesso_ativo` se `senha_hash`; `convite_pendente` se `convite_token` e `convite_expira_em > now()`; senão `sem_acesso` — convite expirado = `sem_acesso` com `conviteExpiraEm` no passado, o front mostra "Convite expirado · Reenviar"). `POST /usuarios` cria colaborador **sem acesso** (e-mail obrigatório: `usuario.email not null` e único). `POST /usuarios/{id}/convite` convida ou reenvia (token novo, 72 h, e-mail) — `acesso_ativo` → 422 `ja_tem_acesso`, inativo → 422 `usuario_inativo`. `POST /auth/convites` (criar + convidar) permanece. `GET /usuarios/perfis` devolve a matriz `Permissoes` para o bloco "O que este perfil vê". Inativar = `PUT` com `ativo=false` (guarda `ultimo_dono` já existe). | Spec §6.1/§7.3, decisão 45. |
| R11 | **Auditoria geral** = `GET /auditoria` unindo `auditoria` (9 tabelas auditadas) e `log_acesso_documento` (evento `tabela='log_acesso_documento'`, `acao='ACESSO'`, título "visualizou o passaporte de Lúcia Mendes" / "visualizou o anexo X", subtítulo "documento sensível · LGPD"). Cursor por `antesDe` (carimbo do último item) + `tamanho ≤ 100`, `total` na resposta, "Mais antigas →" no front. Categorias `oque` ∈ `tudo|valores|recebimentos|cancelamentos|acesso_documento` (definição SQL na T4). `ProjecaoAuditoria.Projetar` ganha `verDocumento` (remove `cpf`/`contato_emergencia` de eventos de `cliente`; a timeline da viagem passa `u.Pode(ClienteVerDocumento)`). Eventos LGPD visíveis a qualquer `AuditoriaVer` (não expõem conteúdo). Títulos continuam impessoais ("Valores da reserva alterados"); o front prefixa `usuarioNome`. | Spec §8; timeline de 3.3 reaproveitada, uma projeção só. |
| R12 | **`log_acesso` com RLS** (0016): `select` por `agencia_id = app_agencia_id()`; `insert with check (true)` (login insere antes de haver tenant, via conexão solta — convenção documentada). Ninguém lê `log_acesso` na v1; é rede de segurança. | Deferida da Fase 2. |
| R13 | **Pendências derivadas** (job diário, `origem='automatica'`): regras e chaves na T5. Upsert por `(agencia_id, chave_unica)`: atualiza título/data/prioridade/responsável quando `status='aberta'`, **reabre** se `cancelada`, **nunca** mexe em `concluida`; condição resolvida → pendência aberta vira `cancelada`. Responsável = `viagem.agente_id ?? viagem.vendedor_id`, senão o Dono ativo mais antigo. "Seguro confirmado" = alguma reserva ativa da viagem com `'seguro' = any(tipos_servico)` **ou** `servico.tipo='seguro'` (não existe campo de apólice). Visto/ESTA por destino fica fora (mestre "Fora deste plano"). | Spec §9 + contrato §4.3; concluída manual não renasce (BACKLOG: revisar após 30 dias). |
| R14 | **Resumo diário** (job): um e-mail por usuário ativo **com senha** e perfil `dono`/`financeiro`/`agente`; Dono/Financeiro veem tudo, Agente vê pendências onde é responsável; seções: pendências de hoje, atrasadas, embarques de hoje e amanhã, aniversariantes de hoje, comissões atrasadas (só com permissão financeira). Vazio total → não envia. HTML simples inline, sem template engine. | Spec §9/§10; `IEnviadorEmail` já existe. |
| R15 | **Expurgos** (jobs mensais): `expurgo_auditoria` apaga `auditoria` com `criado_em < now() - retencao meses` (`agencia.config->>'retencao_auditoria_meses'`, default 24) **preservando `acao='DELETE'`**; `expurgo_anexos` apaga objeto no storage e depois a linha (`delete`, não soft) de `anexo` com `data_descarte < hoje` e `excluido_em is null`, uma linha por transação curta, storage fora da transação; `log_acesso_documento.anexo_id` vira `null` pela FK (0012). Falha no storage de um anexo não impede os demais (log + continua). | Spec §8; contrato "Anexos"/"Jobs". |
| R16 | **Rota `/agenda` protegida** por `viagem.ver`/`viagem.ver_proprias` (hoje sem guarda; sidebar já exige). `/equipe/:id` e `/equipe/nova` novas. | Regressão de 3.1. |
| R17 | **Teste de UX §7 e piloto §12** são humanos e ficam como checklist no fechamento (T12 registra "pendente" a menos que o usuário traga os dados). A Fase 3 **não fecha** sem as fórmulas de §4.2 validadas com três viagens reais; o plano entrega o instrumento (Relatórios + detalhe da viagem), não o veredito. | Critério de fechamento do mestre. |

## Rulings de execução (2026-09-11, decididas durante as ondas; ledger em `.superpowers/sdd/2026-09-11-fase-3-6-agenda-relatorios-equipe-auditoria/progress.md`)

| # | Decisão | Motivo |
|---|---|---|
| E1 | `ResponsavelDto` nasce em **T0** (`Modules/Agenda/AgendaDtos.cs` só com esse record); T1 acrescenta o resto. | T2/T4 correm em paralelo com T1 na onda 1 e consomem o tipo. Custo: nenhum. |
| E2 | CSV da Auditoria: valor numérico vindo de `JsonElement` é formatado por `Csv.Campo(decimal)` quando o campo está em `CamposDeValor`; senão `GetRawText()`. | `1000,00 → 1100,00` no CSV com a mesma regra de vírgula do resto. Custo: só estética. |
| E3 | Seed: crédito do Carlos inserido com o mínimo válido do schema de `credito`; se exigir reserva de origem, usa a reserva do seed. | `where not exists`, idempotente. |
| E4 | T3 pôde editar `AuthTests.cs:153` (congelado) — desserialização de `GET /usuarios` passou de array para `EquipeDto`. | Nenhuma task da onda 1 era dona do arquivo; T0 já tinha commitado. Custo: nenhum (só teste). |
| E5 | Teste do resumo de Relatórios usa `valor_total = valor_cliente` (`rav_cliente = 0`) para manter os esperados do brief. | O brief ignorou que `receita_prevista` inclui `rav_cliente` (defeito do plano). O teste cobre o encanamento das fórmulas; RAV está coberto por `CalculoReservaTests` (3.2). Custo: relatório sem teste do caminho com RAV (BACKLOG). |
| E6 | `nao_encontrado` de vendedor em Relatórios via `exists` próprio (não `Guardas.ReferenciaAsync`, que lança `referencia_invalida`). | Contrato do plano pede `nao_encontrado`. |
| E7 | `POST /pendencias` com cliente inválido → 422 **`referencia_invalida`** (padrão de `Guardas.ReferenciaAsync`), não `nao_encontrado` como dizia o comentário do brief. | Front trata 422 genérico. Custo: nenhum. |
| E8 | Correção de causa raiz em `PendenciasService.CarregarBaseAsync` (exigia `viagem_id`): pendências soltas e de pessoa passam a concluir/adiar/editar. | Sem isso a pendência solta de R3 nascia e não fechava. |
| E9 | Filtro `responsavelId` da Agenda filtra **só pendências**; embarques, retornos, documentos e créditos ficam intactos. | O filtro "Responsável" do protótipo é das pendências. |
| E10 | Cabeçalho da Agenda: "Terça, 7 de abril" (protótipo), não "Terça-feira, 7 de abril" (brief). | Protótipo congelado vence (ruling 3.3 R3). |
| E11 | Guarda R16 de `/agenda` vive em `shell/rotasAgenda.tsx` (T0), não em `pages/agenda/rotas.tsx` — reviewer de T7 apontou ausência por engano. | Padrão C3 (rota por página + guarda no shell); testado em `rotasModulos.test.tsx`. |
| E12 | `PorAgencia = true` nos quatro jobs, inclusive expurgos. | Contrato do plano; sessão por agência dá `app.agencia_id` para o RLS. |
| E13 | Responsável e `viagem_id` da pendência derivada de passaporte = viagem internacional futura **mais próxima**. | R13 dizia "viagem que exige"; concretizado. |
| E14 | `Rotinas.GerarPendenciasAsync` (3.2/3.3) **não** cancela pendências `chave_unica like 'pendencia:%'` ao editar datas da viagem. | Cancelava as derivadas com `viagem_id` a cada PUT; renasciam no job seguinte. Load-bearing, corrigido na fase. |
| E15 | **R13 emendada:** o upsert diário **nunca sobrescreve a data de uma pendência adiada** (`adiada_de` preservado). | Senão "adiar" durava até o próximo job. Custo: pendência adiada não acompanha nova validade do documento até ser concluída/cancelada (BACKLOG). |
| E16 | Motivo do **corpo** do cancelamento de viagem/reserva vale como `app.motivo` (mesmo padrão de `FinanceiroEndpoints` e do `encerrar-divergencia` de 3.5); não há `X-Motivo` separado. | `auditoria.motivo` ficava nulo (defeito de 3.3 achado pelo E2E). Spec §8 exige "motivo", não dois. |
| E17 | TZ de produção (`TZ=America/Sao_Paulo` no Dockerfile + `Timezone=` na connection string) é item do piloto/Fase 4, **não bloqueia o merge**. | Só tem efeito com o contêiner de produção; registrado em BACKLOG "antes do piloto". |
| E18 | Cursor da Auditoria por carimbo (`antesDe`) aceito na v1; cursor composto `(criado_em, id)` vai ao BACKLOG. Front chaveia linha por `tabela+id`. | Empates de `criado_em` são raros na operação real; `Id` não é único na união. |
| E19 | Parked de T9 (`useColaborador` duplicava `useFormularioCadastro`) e de T10 (`DetalhesEventoModal` duplicava o De/Para de `TimelineTab`) resolvidos na onda de fix da revisão final, quando os arquivos congelados deixaram de estar em disputa. | Duas máquinas de formulário e dois renderers De/Para eram drift certo. |
| E20 | E2E `operacao.spec.ts` depende do seed (`Cobrar comissão CVC`, Marcos, Bruno "convite expira em 2 dias"), como os E2E anteriores dependem de `SEED`. | Brief manda; custo: reaplicar `seed-dev.sql` antes de rodar. Rate limit de login com suítes encadeadas segue em BACKLOG. |
| E21 | `biome check --write` pelo controlador em dois arquivos de T8 e dois testes de T10 (imports/format) — implementadores reportaram lint limpo sem ter rodado. | Lição de harness: exigir a saída do comando no relatório. |

---

---

## Ondas (3.6)

| Onda | Tasks | Motivo |
|---|---|---|
| 0 | T0 (base: migration 0016, `Permissoes`, `Csv`, esqueletos, rotas por página, `download.ts`, seed) — **serial** | toca arquivos compartilhados |
| 1 | T1 (agenda backend) · T2 (relatórios backend) · T3 (equipe backend) · T4 (auditoria backend) · T7 (agenda front) · T8 (relatórios front) | 4 backend + 2 front = 6; pastas disjuntas; front trabalha pelo contrato de API deste plano |
| 2 | T5 (jobs pendências derivadas + resumo e-mail; usa `AgendaService` de T1) · T6 (jobs expurgos) · T9 (equipe front) · T10 (auditoria front) | T5 depende de T1; T6 só de T0; front restante |
| 3 | T11 (E2E + re-medição do tempo) | precisa de tudo |
| 4 | T12 (docs no root, memória) | fechamento |

Propriedade de arquivos (exclusiva por task, vale dentro da onda):

- T1: `backend/src/Meridiano.Api/Modules/Agenda/**`, `Modules/Pendencias/**`, `tests/Meridiano.Api.Tests/AgendaTests.cs`, `PendenciasTests.cs`.
- T2: `Modules/Relatorios/**`, `tests/…/RelatoriosTests.cs`.
- T3: `Modules/Admin/**`, `Auth/ConviteService.cs`, `Auth/ConviteEndpoints.cs`, `tests/…/{UsuariosTests,ConviteTests,EquipeTests}.cs`.
- T4: `Modules/Auditoria/**`, `tests/…/{AuditoriaTests,AuditoriaProjecaoTests}.cs`.
- T5: `Jobs/PendenciasDerivadasJob.cs`, `Jobs/ResumoDiarioEmailJob.cs`, `Jobs/ResumoDiarioHtml.cs`, `tests/…/JobsDerivadosTests.cs`.
- T6: `Jobs/ExpurgoAuditoriaJob.cs`, `Jobs/ExpurgoAnexosJob.cs`, `tests/…/JobsExpurgoTests.cs`.
- T7: `frontend/src/api/agenda.ts`, `src/pages/agenda/**`, `src/components/Pendencias/**`, `src/components/pendencias.ts`, `src/shell/Sidebar.tsx` (+ `.test.tsx`, `.module.css`), `src/shell/navegacao.ts`.
- T8: `src/api/relatorios.ts`, `src/pages/relatorios/**`.
- T9: `src/api/equipe.ts`, `src/pages/equipe/**`.
- T10: `src/api/auditoria.ts`, `src/pages/auditoria/**`, `src/components/Auditoria/**`, `src/components/auditoria.ts`.
- T11: `frontend/e2e/operacao.spec.ts`, `e2e/operacao.ts`.
- Congelados durante 1–3: `Program.cs`, `Modules/Endpoints.cs`, `Modules/Comum/**`, `Infra/**`, `Auth/**` (exceto os dois arquivos de T3), `Meridiano.Domain/**`, `Meridiano.Data/**`, `Jobs/JobsExtensions.cs`, `Fixtures/**`, `MigrationsTests.cs`; front: `shell/rotasModulos.tsx`, `shell/rotas{Agenda,Relatorios,Equipe,Auditoria}.tsx`, `api/http.ts`, `dominio/**`, `lib/**`, `components/**` fora das pastas listadas, `pages/viagens/**`, `pages/clientes/**`, `pages/financeiro/**`, `e2e/*` existentes. Precisou tocar congelado → BLOCKED, controlador decide.

---

## Contrato de API (fonte única para backend e front)

```
GET    /api/v1/agenda?responsavelId                                → 200 AgendaDto
GET    /api/v1/agenda/badges                                       → 200 BadgesDto
GET    /api/v1/clientes/aniversarios?dias=7                        → 200 AniversarianteDto[]
POST   /api/v1/pendencias                NovaPendenciaRequest      → 201 PendenciaDto[]      (R3: pendência solta)
GET    /api/v1/relatorios/resumo?ano&vendedorId                    → 200 RelatorioResumoDto
GET    /api/v1/relatorios/csv?ano&vendedorId                       → 200 text/csv (reservas do ano)
GET    /api/v1/usuarios                                            → 200 EquipeDto
GET    /api/v1/usuarios/{id}                                       → 200 ColaboradorDto
POST   /api/v1/usuarios                  NovoColaboradorRequest    → 201 ColaboradorDto      (sem acesso)
PUT    /api/v1/usuarios/{id}             AtualizarUsuarioRequest   → 200 ColaboradorDto | 409  (existente; devolve ColaboradorDto)
POST   /api/v1/usuarios/{id}/convite                               → 200 ColaboradorDto      (convidar / reenviar)
GET    /api/v1/usuarios/perfis                                     → 200 PerfilDto[]
POST   /api/v1/auth/convites             ConviteRequest            → 201 { usuarioId }       (existente, inalterado)
GET    /api/v1/auditoria?usuarioId&oque&de&ate&antesDe&tamanho     → 200 AuditoriaDto
GET    /api/v1/auditoria/csv?usuarioId&oque&de&ate                 → 200 text/csv
GET    /api/v1/viagens/{id}/auditoria                              → 200 EventoAuditoriaDto[] (existente; DTO ganha viagemId/codigoViagem)
```

Permissões (T12 acrescenta em `docs/autorizacao-por-operacao.md`):

| Operação | Permissão | Observação |
|---|---|---|
| `GET /agenda`, `GET /agenda/badges`, `GET /clientes/aniversarios` | `ViagemVer` ou `ViagemVerProprias` | externo: `apenasVendedor = usuario_id` em pendências (viagens próprias **ou** `responsavel_id = ele`), embarques/retornos/créditos (viagens próprias), documentos (clientes com viagem própria); `numero` do documento só com `ClienteVerDocumento`; `badges.financeiro` só com permissão financeira; `badges.clientes` só com `ClienteVer*` |
| `POST /pendencias` | `ViagemEditar` | `clienteIds` validados por `ReferenciaAsync(Cliente)`; cria uma pendência por cliente ou uma sem cliente |
| `GET /relatorios/resumo`, `GET /relatorios/csv` | `RelatorioVer` | Dono, Financeiro, Contador; sem projeção adicional (teste de domínio garante `ReservaVerValores` + `ViagemVerResultado` nesses perfis) |
| `GET/POST/PUT /usuarios*`, `POST /usuarios/{id}/convite`, `GET /usuarios/perfis` | `UsuarioGerenciar` | `GET /usuarios/vendedores` continua para qualquer autenticado |
| `GET /auditoria`, `GET /auditoria/csv` | `AuditoriaVer` | projeção `ProjecaoAuditoria(verValores, verResultado, verDocumento)`; eventos `log_acesso_documento` sempre visíveis |
| `GET /repasses` | `RepasseVerTodos` — **Contador passa a ter** (R9) | Agente continua 403 |

```csharp
// ---- Modules/Agenda/AgendaDtos.cs (T1) ----
public sealed record FiltroAgenda(Guid? ResponsavelId);
public sealed record AgendaDto(AgendaCabecalhoDto Cabecalho, AgendaPendenciasDto Pendencias, EmbarqueDto[] Embarques, RetornoDto[] Retornos,
    DocumentoVencendoDto[] Documentos, CreditoVencendoDto[] Creditos, ResponsavelDto[] Responsaveis);
public sealed record AgendaCabecalhoDto(DateOnly Hoje, int PendenciasHoje, int Atrasadas, int EmbarquesSemana);
public sealed record AgendaPendenciasDto(PendenciaDto[] Atrasadas, PendenciaDto[] Hoje, PendenciaDto[] Semana, int Total);   // Total = abertas com data ≤ hoje+7 no universo
public sealed record EmbarqueDto(Guid ViagemId, string Codigo, string? Titular, string Destino, DateOnly DataIda, int NumPax, string FaseOperacional);
public sealed record RetornoDto(Guid ViagemId, string Codigo, string? Titular, string Destino, DateOnly DataVolta, DateOnly? PosViagemEm);   // data da pendência posviagem aberta, se houver
public sealed record DocumentoVencendoDto(Guid ClienteId, string ClienteNome, string Tipo, string? Numero, DateOnly? Validade, int? DiasParaVencer,
    Guid? ProximaViagemId, string? ProximaViagemDestino, DateOnly? ProximaViagemIda, string Situacao, Guid? PendenciaId);   // Situacao ∈ na_agenda | so_cadastro
public sealed record CreditoVencendoDto(Guid CreditoId, Guid ClienteId, string ClienteNome, string FornecedorNome, string Origem, Guid? ViagemOrigemId, DateOnly Validade, int DiasParaVencer, decimal Valor);
public sealed record ResponsavelDto(Guid Id, string Nome);
public sealed record BadgesDto(int Agenda, int? Financeiro, int? Clientes);
public sealed record AniversarianteDto(Guid ClienteId, string Nome, DateOnly DataNascimento, DateOnly Proximo, int Idade);
public sealed record ResumoDiarioDto(PendenciaDto[] Hoje, PendenciaDto[] Atrasadas, EmbarqueDto[] Embarques, AniversarianteDto[] Aniversariantes, int ComissoesAtrasadas, decimal ComissoesAtrasadasValor);   // usado por T5

// ---- Modules/Pendencias/PendenciaDtos.cs (T1) — NovaPendenciaRequest existente serve ao POST /pendencias (ClienteIds pode ser vazio) ----

// ---- Modules/Relatorios/RelatorioDtos.cs (T2) ----
public sealed record FiltroRelatorio(int? Ano, Guid? VendedorId);
public sealed record RelatorioResumoDto(int Ano, int[] Anos, Guid? VendedorId, string Ate, KpisRelatorioDto Kpis, TetoMeiDto? TetoMei,
    ReceitaMesDto[] ReceitaPorMes, TipoViagemDto[] NacionalInternacional, FornecedorRankingDto[] Fornecedores, ServicoVendidoDto[] Servicos, ResponsavelDto[] Vendedores);
public sealed record KpisRelatorioDto(decimal VendaAno, int Reservas, int Viagens, decimal ReceitaRecebida, decimal ReceitaPrevista, decimal RecebidoDeAnosAnteriores,
    decimal DespesasPagas, decimal DespesasFixas, decimal DespesasViagens, decimal ResultadoOperacional, decimal? MargemOperacionalPct, decimal? MargemComercialPct);
public sealed record TetoMeiDto(decimal ReceitaAno, decimal Teto, decimal PercentualTeto, bool Alerta);   // Alerta = PercentualTeto >= 80
public sealed record ReceitaMesDto(int Mes, decimal Prevista, decimal Recebida);                           // 12 itens, Mes 1..12
public sealed record TipoViagemDto(string Tipo, decimal Venda, decimal Pct, decimal? MargemPct);            // Tipo ∈ nacional | internacional (sempre os dois)
public sealed record FornecedorRankingDto(Guid FornecedorId, string Nome, int Reservas, decimal Volume, decimal Receita, decimal? MargemPct);   // top 10 por Receita
public sealed record ServicoVendidoDto(string Tipo, int Reservas);                                          // os 9 tipos, ordem por Reservas desc

// ---- Modules/Admin/UsuarioDtos.cs (T3) — substitui UsuarioDto ----
public sealed record ColaboradorDto(Guid Id, string Nome, string Email, string? Telefone, string Perfil, bool GeraRepasse, decimal PercentualPadrao, bool Ativo,
    string Acesso, DateTimeOffset? UltimoLoginEm, DateTimeOffset? ConviteExpiraEm, string Versao);          // Acesso ∈ acesso_ativo | sem_acesso | convite_pendente | inativo
public sealed record EquipeDto(ColaboradorDto[] Itens, int Total, int ComAcesso, int ConvitesPendentes);
public sealed record NovoColaboradorRequest(string Nome, string Email, string? Telefone, string Perfil, bool GeraRepasse, decimal PercentualPadrao);
public sealed record AtualizarUsuarioRequest(string Nome, string? Telefone, string Perfil, bool GeraRepasse, decimal PercentualPadrao, bool Ativo, string Versao);   // existente
public sealed record VendedorDto(Guid Id, string Nome, string Perfil, bool GeraRepasse, decimal PercentualPadrao);   // existente
public sealed record PerfilDto(string Perfil, string[] Permissoes);   // Permissoes = chaves "modulo.acao" (Permissao.Chave())

// ---- Modules/Auditoria/AuditoriaDtos.cs (T4) ----
public sealed record EventoAuditoriaDto(long Id, string Tabela, Guid RegistroId, string Acao, string Titulo, string? Subtitulo,
    Dictionary<string, AlteracaoDto> Alteracoes, string? Motivo, string? UsuarioNome, DateTimeOffset CriadoEm, Guid? ViagemId = null, string? CodigoViagem = null);
public sealed record FiltroAuditoria(Guid? UsuarioId, string? Oque, DateOnly? De, DateOnly? Ate, DateTimeOffset? AntesDe, int Tamanho = 25);   // Oque ∈ tudo|valores|recebimentos|cancelamentos|acesso_documento
public sealed record AuditoriaDto(EventoAuditoriaDto[] Itens, int Total, DateTimeOffset? ProximoAntesDe, ResponsavelDto[] Usuarios);   // Usuarios = atores distintos da agência (para o filtro "Quem")

// ---- Meridiano.Domain/Comum/Csv.cs (T0) ----
public static class Csv
{
    public const string Bom = "﻿";
    public static string Campo(object? v);                       // regras da seção Global Constraints
    public static string Linha(params object?[] campos);         // join ';' + "\r\n"
    public static string Documento(string[] cabecalho, IEnumerable<object?[]> linhas);   // Bom + cabeçalho + linhas
}

// ---- Jobs (T0 registra esqueletos; T5/T6 implementam) ----
public sealed class PendenciasDerivadasJob(DbSessaoFactory sessoes) : IJob                       // "pendencias_derivadas", PorAgencia true
public sealed class ResumoDiarioEmailJob(DbSessaoFactory sessoes, IEnviadorEmail email) : IJob  // "resumo_diario_email", PorAgencia true
public sealed class ExpurgoAuditoriaJob(DbSessaoFactory sessoes) : IJob                          // "expurgo_auditoria", PorAgencia true
public sealed class ExpurgoAnexosJob(DbSessaoFactory sessoes, IArmazenamentoArquivo storage) : IJob   // "expurgo_anexos", PorAgencia true
```

```ts
// ---- frontend/src/api/agenda.ts (T7) ----
export interface AgendaDto { cabecalho: {hoje: string; pendenciasHoje: number; atrasadas: number; embarquesSemana: number};
  pendencias: {atrasadas: PendenciaDto[]; hoje: PendenciaDto[]; semana: PendenciaDto[]; total: number};
  embarques: EmbarqueDto[]; retornos: RetornoDto[]; documentos: DocumentoVencendoDto[]; creditos: CreditoVencendoDto[]; responsaveis: {id: string; nome: string}[] }
export interface BadgesDto { agenda: number; financeiro: number | null; clientes: number | null }
export const agendaApi = { listar: (responsavelId: string | null) => api.get<AgendaDto>(`/agenda${responsavelId ? `?responsavelId=${responsavelId}` : ""}`),
  badges: () => api.get<BadgesDto>("/agenda/badges") };
export const chavesAgenda = { lista: (r: string | null) => ["agenda", r] as const, badges: () => ["agenda", "badges"] as const };
// api/pendencias.ts (T7): pendenciasApi.criarSolta(r: NovaPendenciaRequest) => api.post<PendenciaDto[]>("/pendencias", r)

// ---- src/api/relatorios.ts (T8) ---- espelho de RelatorioResumoDto; relatoriosApi.resumo(ano, vendedorId); urlCsv(ano, vendedorId) => `/api/v1/relatorios/csv?...`
// ---- src/api/equipe.ts (T9) ---- ColaboradorDto, EquipeDto, NovoColaboradorRequest, AtualizarUsuarioRequest, PerfilDto; equipeApi.listar/obter/criar/atualizar/convidar/perfis; convidarNovo = POST /auth/convites
// ---- src/api/auditoria.ts (T10) ---- + listar(filtro): AuditoriaDto; urlCsv(filtro); FiltroAuditoria { usuarioId?, oque?, de?, ate?, antesDe?, tamanho? }; EventoAuditoriaDto ganha viagemId?: string | null; codigoViagem?: string | null

// ---- src/lib/download.ts (T0) ----
export function baixar(url: string, nomeArquivo?: string): void   // cria <a href download>, click(), remove; sem fetch (cookie same-origin)

// ---- src/components/Pendencias/escopo.ts (T7) ----
export type EscopoPendencias = { viagemId; passageiros } | { clienteId; viagens } | { agenda: true; responsavelId: string | null };
// fontePendencias({agenda}) → chave chavesAgenda.lista(responsavelId), buscar = agendaApi.listar(...).then(a => [...atrasadas, ...hoje, ...semana]), prefixo ["agenda"]
// NovaPendenciaModal com escopo agenda: sem "Para quem" (passageiros), com campo "Pessoa" opcional (combobox viagensApi.buscarClientes de `api/viagens.ts`), grava via pendenciasApi.criarSolta
```

---

## Fórmulas dos Relatórios (R6/R7 — T2 implementa em `RelatoriosSql.cs` com este texto em comentário; T12 copia para `docs/relatorios-formulas.md`)

Universo **U(ano, vendedor)** = reservas `r` com `r.excluido_em is null`, viagem `v` com `v.excluido_em is null`, `extract(year from r.data_compra) = ano`, `[v.vendedor_id = @vendedorId]`. **U_ativo** = U sem `r.status = 'cancelada'`.

| Número | Eixo | Fórmula |
|---|---|---|
| `VendaAno`, `Reservas`, `Viagens` | competência | `sum(r.valor_cliente)`, `count(*)`, `count(distinct r.viagem_id)` sobre U_ativo |
| `ReceitaPrevista` | competência | `sum(r.receita_prevista)` sobre U_ativo (cancelada sem `comissao_mantida` já vale 0 na coluna gerada) |
| `ReceitaRecebida` | caixa | `sum(m.valor)` de `movimento_financeiro m` (`excluido_em is null`, **os 5 tipos**, sinal do banco) com `extract(year from m.data_movimento) = ano`, join `reserva r`/`viagem v` não excluídas, `[v.vendedor_id]`; reserva cancelada **entra** (caixa é caixa) |
| `RecebidoDeAnosAnteriores` | caixa | mesma soma restrita a `extract(year from r.data_compra) < ano` |
| `DespesasPagas`, `DespesasFixas`, `DespesasViagens` | despesas | `sum(valor)` de `despesa` paga (`pago and extract(year from pago_em) = ano`, `excluido_em is null`); fixas = `categoria = 'fixo'`; viagens = `viagem_id is not null`; com `vendedorId`: só `viagem_id in (viagens do vendedor)` e fixas = 0 |
| `ResultadoOperacional` | misto explícito | `ReceitaRecebida − DespesasPagas` (rótulo da tela: "receita recebida − despesas pagas") |
| `MargemOperacionalPct` | — | `round(100 * ResultadoOperacional / VendaAno, 1)`, `null` se `VendaAno = 0` |
| `MargemComercialPct` | — | `round(100 * ReceitaPrevista / VendaAno, 1)`, `null` se `VendaAno = 0` |
| `TetoMei` | caixa | linha de `vw_teto_mei` para `ano` (ignora vendedor); `null` se não há movimentos no ano; `Alerta = PercentualTeto >= 80` |
| `ReceitaPorMes[m]` | competência × caixa | `Prevista` = `sum(r.receita_prevista)` de U_ativo com `extract(month from r.data_compra) = m`; `Recebida` = soma de caixa com `extract(month from m.data_movimento) = m`; 12 linhas sempre |
| `NacionalInternacional` | competência | por `v.tipo`: `Venda = sum(valor_cliente)`, `Pct = round(100 * Venda / VendaAno, 1)` (0 se venda 0), `MargemPct = round(100 * sum(receita_prevista) / Venda, 1)` (`null` se 0); sempre as duas linhas |
| `Fornecedores` | competência | por `r.fornecedor_id` sobre U_ativo: `Reservas`, `Volume = sum(valor_cliente)`, `Receita = sum(receita_prevista)`, `MargemPct = round(100 * Receita / Volume, 1)`; `order by Receita desc limit 10` |
| `Servicos` | competência | `select t, count(*) from U_ativo, unnest(r.tipos_servico) t group by t` — reserva com N tipos conta em N linhas; os 9 tipos sempre presentes (0 quando ausentes), ordem `Reservas desc` |
| `Ate` | — | ano corrente → nome do mês corrente ("abril"); ano passado → "dezembro" |
| `Anos` | — | `distinct extract(year from data_compra)` ∪ ano corrente, desc |

CSV (`/relatorios/csv`): uma linha por reserva de **U** (inclui canceladas): `Código;Cliente;Destino;Tipo;Vendedor;Fornecedor;Localizador;Compra;Status;Venda;Custo;Comissão;RAV operadora;RAV cliente;Taxa de serviço;Receita prevista;Recebido;Previsão comissão;Situação;Serviços` (`Situação` = `SituacaoComissao` da conciliação; `Serviços` = tipos separados por `, `). Ordem `data_compra, codigo`.

---

### Task 0 (serial): migration 0016, `Permissoes`, `Csv`, esqueletos, rotas por página, `download.ts`, seed

**Files:**
- Create: `backend/src/Meridiano.Data/Migrations/0016_log_acesso_rls_e_indices.sql`
- Modify: `backend/src/Meridiano.Domain/Comum/Permissoes.cs` (Contador + `RepasseVerTodos`), `backend/tests/Meridiano.Domain.Tests/PermissoesTests.cs`, `backend/tests/Meridiano.Api.Tests/RepassesTests.cs` (linha 121: contador → `OK`)
- Create: `backend/src/Meridiano.Domain/Comum/Csv.cs`, `backend/tests/Meridiano.Domain.Tests/CsvTests.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Endpoints.cs` (`AddScoped<AgendaService>`, `AddScoped<RelatoriosService>`; `api.MapAgendaEndpoints()`, `api.MapRelatoriosEndpoints()`), `backend/src/Meridiano.Api/Jobs/JobsExtensions.cs` (4 `AddScoped<IJob, …>`)
- Create (esqueletos): `Modules/Agenda/{AgendaService.cs,AgendaEndpoints.cs}`, `Modules/Relatorios/{RelatoriosService.cs,RelatoriosEndpoints.cs}`, `Jobs/{PendenciasDerivadasJob,ResumoDiarioEmailJob,ExpurgoAuditoriaJob,ExpurgoAnexosJob}.cs` (`ExecutarAsync => Task.CompletedTask`)
- Modify: `backend/tests/Meridiano.Api.Tests/MigrationsTests.cs` (+1), `backend/tests/Meridiano.Api.Tests/AuthTests.cs` (+1 RLS), `backend/scripts/seed-dev.sql`
- Modify: `frontend/src/shell/rotasModulos.tsx`, `frontend/src/shell/rotasModulos.test.tsx`
- Create: `frontend/src/shell/{rotasAgenda,rotasRelatorios,rotasEquipe,rotasAuditoria}.tsx`, `frontend/src/pages/{agenda,relatorios,equipe,auditoria}/rotas.tsx` (todas `EmConstrucao`), `frontend/src/lib/download.ts`, `frontend/src/lib/download.test.ts`

**Depends-on:** none

**Interfaces:**

```sql
-- 0016_log_acesso_rls_e_indices.sql
-- Fase 3.6 — RLS de leitura em log_acesso (login insere antes de haver tenant); índices redundantes de 3.3/3.4
alter table log_acesso enable row level security;
alter table log_acesso force row level security;
create policy p_log_acesso_select on log_acesso for select using (agencia_id = app_agencia_id());
create policy p_log_acesso_insert on log_acesso for insert with check (true);
drop index if exists ix_pendencia_viagem;      -- coberto por ix_pendencia_viagem_origem (0014)
drop index if exists ix_interacao_cliente;     -- coberto por ix_interacao_agencia_cliente (0015)
```

```csharp
// Permissoes.cs — ContadorSet += Permissao.RepasseVerTodos (R9)
// Csv.cs — Campo: null → ""; string → aspas se contém ; " \r \n (aspas dobradas); decimal → F2 com vírgula (pt-BR InvariantCulture + Replace); DateOnly → dd/MM/yyyy; DateTime/DateTimeOffset → dd/MM/yyyy HH:mm; bool → Sim/Não; int/long → ToString(); demais → ToString()
// Endpoints.cs — using Meridiano.Api.Modules.Agenda; using Meridiano.Api.Modules.Relatorios;
// esqueletos: public sealed class AgendaService(DbSessaoFactory sessoes); public static class AgendaEndpoints { public static IEndpointRouteBuilder MapAgendaEndpoints(this IEndpointRouteBuilder app) => app; } — idem Relatorios
```

```tsx
// rotasModulos.tsx: substituir os quatro blocos EmConstrucao por {RotasAgenda()}{RotasRelatorios()}{RotasEquipe()}{RotasAuditoria()}
// shell/rotasAgenda.tsx: export function RotasAgenda() { return <Route element={<RotaProtegida permissao={["viagem.ver","viagem.ver_proprias"]} />}>{RotasAgendaPagina()}</Route>; }   (R16)
// pages/agenda/rotas.tsx: export function RotasAgendaPagina() { return <Route path="/agenda" element={<EmConstrucao titulo="Agenda" />} />; }
// shell/rotasRelatorios.tsx: RotaProtegida "relatorio.ver" → pages/relatorios/rotas.tsx: /relatorios
// shell/rotasEquipe.tsx: RotaProtegida "usuario.gerenciar" → pages/equipe/rotas.tsx: /equipe, /equipe/nova, /equipe/:id
// shell/rotasAuditoria.tsx: RotaProtegida "auditoria.ver" → pages/auditoria/rotas.tsx: /auditoria
// lib/download.ts
export function baixar(url: string, nomeArquivo?: string): void {
  const a = document.createElement("a"); a.href = url; if (nomeArquivo) a.download = nomeArquivo; a.rel = "noopener";
  document.body.appendChild(a); a.click(); a.remove();
}
```

Seed (`seed-dev.sql`, idempotente por `where not exists`): usuário `marcos@viva.dev` (Marcos Castro, `vendedor_externo`, sem senha, `gera_repasse = true, percentual_padrao = 8`); usuário `bruno@viva.dev` (Bruno Sales, `agente`, sem senha, `convite_token = 'seed-convite-bruno'`, `convite_expira_em = now() + interval '2 days'`); pendência manual "Cobrar comissão CVC" `data_prevista = current_date - 3`, responsável dono, `origem 'manual'`, sem viagem; crédito `disponivel` para Carlos com `validade = current_date + 40` (só se a tabela `credito` não tiver linha do Carlos).

- [ ] **Step 1: Testes** — `MigrationsTests.cs` + `Log_acesso_0016_tem_rls_e_indices_redundantes_sumiram()` (`pg_policies` tem `p_log_acesso_select`/`p_log_acesso_insert`; `pg_indexes` não tem `ix_pendencia_viagem` nem `ix_interacao_cliente`). `AuthTests.cs` + `Login_insere_log_acesso_e_leitura_respeita_tenant()`: login (ok e falho) continua inserindo (contar como owner); `select count(*) from log_acesso` pela conexão da API **sem** `app.agencia_id` → 0; com `set_config('app.agencia_id', <a>, false)` → só as linhas da agência `a`. `PermissoesTests.cs`: `Contador_e_somente_leitura` passa a exigir `RepasseVerTodos` e continuar sem `RepassePagar`; + `Perfis_com_relatorio_ver_veem_valores_e_resultado()` (Dono, Financeiro, Contador têm `ReservaVerValores` e `ViagemVerResultado`). `RepassesTests.cs:121` → `HttpStatusCode.OK`. `CsvTests.cs`: `Campo("a;b") == "\"a;b\""`, `Campo("x\"y") == "\"x\"\"y\""`, `Campo(1234.5m) == "1234,50"`, `Campo(new DateOnly(2026,4,7)) == "07/04/2026"`, `Campo(true) == "Sim"`, `Campo(null) == ""`, `Documento(["A","B"], [[1, "x"]])` começa com BOM e tem `A;B\r\n1;x\r\n`. Front: `rotasModulos.test.tsx` + 4 casos (`/agenda` com `pode = () => false` → "Sem permissão"; `/relatorios` só com `relatorio.ver` → heading "Relatórios"; `/equipe/abc` sem `usuario.gerenciar` → "Sem permissão"; `/auditoria` com `auditoria.ver` → "Auditoria"). `download.test.ts`: `baixar("/x.csv", "x.csv")` cria e clica um `<a>` com `href`/`download` (spy em `HTMLAnchorElement.prototype.click`) e o remove.
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar** conforme Interfaces (migration, `Permissoes`, `Csv`, esqueletos, registros, rotas, `download.ts`, seed).
- [ ] **Step 4: Rodar tudo** — `cd backend && dotnet build -c Release && dotnet test && dotnet format --verify-no-changes`; `cd frontend && npm run lint && npm run typecheck && npm run test && npm run build`. Zero falhas (226+2 API, 26+8 domínio; 402+5 Vitest).
- [ ] **Step 5: Reportar arquivos.** Commits (controlador): backend `feat(base): migration 0016 log_acesso RLS, Contador reads repasses, Csv helper, skeletons and seed for 3.6`; frontend `feat(base): per-page route files for agenda/relatorios/equipe/auditoria, guarded /agenda, download helper`. Reviewers: `code-reviewer` + foco security (RLS, `Permissoes`).

---

### Task 1 (backend): `Modules/Agenda` + `POST /pendencias`

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Agenda/AgendaDtos.cs`, `backend/src/Meridiano.Api/Modules/Agenda/AgendaSql.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Agenda/AgendaService.cs`, `backend/src/Meridiano.Api/Modules/Agenda/AgendaEndpoints.cs` (esqueletos de T0)
- Modify: `backend/src/Meridiano.Api/Modules/Pendencias/PendenciasService.cs`, `backend/src/Meridiano.Api/Modules/Pendencias/PendenciasEndpoints.cs`
- Create: `backend/tests/Meridiano.Api.Tests/AgendaTests.cs`; Modify: `backend/tests/Meridiano.Api.Tests/PendenciasTests.cs` (+1)

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class AgendaService(DbSessaoFactory sessoes)
{
    public Task<AgendaDto> ListarAsync(ContextoSessao ctx, UsuarioAtual u, FiltroAgenda f, CancellationToken ct);
    public Task<BadgesDto> BadgesAsync(ContextoSessao ctx, UsuarioAtual u, CancellationToken ct);
    public Task<IReadOnlyList<AniversarianteDto>> AniversariosAsync(ContextoSessao ctx, UsuarioAtual u, int dias, CancellationToken ct);
    // dentro da transação do chamador (T5 — job): universo do usuário destinatário
    public static Task<ResumoDiarioDto> ResumoDiarioAsync(DbSessao s, Guid agenciaId, Guid? apenasVendedor, Guid? apenasResponsavel, bool verFinanceiro, CancellationToken ct);
}
public static class AgendaEndpoints   // MapAgendaEndpoints: GET /agenda, GET /agenda/badges, GET /clientes/aniversarios — gate u.Pode(ViagemVer) || u.Pode(ViagemVerProprias), senão 403 sem_permissao (padrão PendenciasEndpoints)
// PendenciasService: public Task<IReadOnlyList<PendenciaDto>> CriarSoltaAsync(ContextoSessao ctx, UsuarioAtual u, NovaPendenciaRequest req, CancellationToken ct);
// PendenciasEndpoints: POST /pendencias (RequerPermissao(ViagemEditar)) → 201
```
  - **Universo:** `apenasVendedor = u.Pode(ViagemVer) ? null : u.UsuarioId`. Pendências: `status = 'aberta'` e `(@apenasVendedor is null or responsavel_id = @apenasVendedor or viagem_id in (select id from viagem where vendedor_id = @apenasVendedor))`; `[responsavel_id = @responsavelId]`. Viagens: `excluido_em is null and not cancelada [and vendedor_id = @apenasVendedor]`. Documentos: clientes com viagem própria quando `apenasVendedor` (`VisibilidadeCliente.FiltroSql`). Créditos: `credito.status = 'disponivel' and excluido_em is null` com viagem de origem própria quando `apenasVendedor`.
  - **Pendências:** `SELECT` do `PendenciasService` (mesmas colunas de `PendenciaDto`, `Atrasada = data_prevista < current_date`) com `data_prevista <= current_date + 7`, ordem `prioridade desc (urgente primeiro), data_prevista, criado_em`; partição em C#: `< hoje` → Atrasadas, `= hoje` → Hoje, resto → Semana; teto 100 por grupo; `Total` = soma.
  - **Embarques:** `viagem v join vw_fase_viagem fv left join vw_viagem_titular t` com `data_ida between current_date and current_date + 14`, ordem `data_ida`; `EmbarquesSemana` (cabeçalho) = os com `data_ida <= current_date + 7`. **Retornos:** `data_volta between current_date and current_date + 14`; `PosViagemEm` = `data_prevista` da pendência aberta com `chave_unica = v.id || ':posviagem'`.
  - **Documentos:** (a) `documento_cliente d` `tipo = 'passaporte'`, `excluido_em is null`, `validade <= current_date + 210` (uma linha por documento; `DiasParaVencer = validade - current_date`, pode ser negativo); (b) clientes passageiros de viagem `internacional` futura (`data_ida >= current_date`) sem passaporte não excluído → linha com `Tipo = 'passaporte'`, `Numero/Validade/Dias = null`. `Numero` só com `u.Pode(ClienteVerDocumento)` (senão `null`; **não** grava `log_acesso_documento` — mesma regra do CPF em lista, ruling 3.4 R2). `ProximaViagem*` = viagem futura mais próxima em que o cliente é passageiro. `Situacao = 'na_agenda'` + `PendenciaId` quando existe pendência aberta `chave_unica = 'pendencia:' || cliente_id || ':passaporte'`, senão `'so_cadastro'`. Ordem `validade nulls first, validade`.
  - **Créditos:** `credito cr join cliente c join fornecedor f left join viagem vo` (origem) com `validade <= current_date + 60`, `Origem = 'cancelamento · ' || coalesce(localizador da reserva de origem, codigo)` (se o schema não guarda a reserva de origem, `Origem = 'cancelamento'`), ordem `validade`.
  - **Responsáveis:** usuários ativos com perfil `dono`/`agente`/`financeiro` (`order by nome`).
  - **Badges (R4):** `Agenda` = pendências abertas do universo com `data_prevista <= current_date`; `Financeiro` = `count(*) from vw_reserva_financeiro f join viagem v … where f.aguardando_operadora and f.data_prevista_comissao < current_date` se `u.Pode(FinanceiroMovimentar) || FinanceiroConciliar || FinanceiroVerDre`, senão `null`; `Clientes` = `count(distinct cliente_id)` de pendências abertas do universo com `cliente_id is not null` se `u.Pode(ClienteVer) || ClienteVerProprios`, senão `null`.
  - **Aniversários:** `dias` em `[0, 60]` (fora → 422 `dias_invalido`); clientes não excluídos com `data_nascimento`, próximo aniversário (`make_date(ano corrente ou seguinte, month, day)`; 29/02 → 28/02 em ano não bissexto) em `[hoje, hoje + dias]`; `Idade` = idade que completa; visibilidade `VisibilidadeCliente.FiltroSql`; ordem `Proximo, nome`.
  - **`ResumoDiarioAsync`:** `Hoje`/`Atrasadas` (pendências abertas com `data_prevista <= current_date`, filtro `apenasResponsavel` quando não nulo, senão universo por `apenasVendedor`), `Embarques` (`data_ida in (hoje, amanhã)`), `Aniversariantes` (hoje), `ComissoesAtrasadas` (+ valor = `sum(esperado - recebido)`) só se `verFinanceiro`, senão 0.
  - **`CriarSoltaAsync`:** validação igual à de viagem (`titulo_obrigatorio`, `prioridade_invalida`, `ResponsavelId` → `ReferenciaAsync(Usuario, exigirAtivo)`); `ClienteIds` vazio → uma pendência sem cliente; senão uma por cliente (`ReferenciaAsync(Cliente)` cada, sem duplicatas); `viagem_id = null`, `origem = 'manual'`; devolve as criadas.

- [ ] **Step 1: Testes** (`AgendaTests.cs`; cenário: dono, agente `ag@`, externa `ana@` com senha; Carlos (titular), Lúcia (passaporte validade hoje+40), Pedro (sem passaporte); viagem V1 internacional Lisboa ida hoje+11 vendida pela externa com Carlos+Pedro, V2 nacional Gramado volta hoje+2 vendida pelo dono (pendência automática `posviagem` via fixture: inserir `pendencia` com `chave_unica = V2||':posviagem'`), V3 cancelada ida hoje+3; pendências: atrasada hoje−3 (resp. dono), hoje (resp. agente), hoje+5 (viagem V1), hoje+20 (fora); crédito disponível do Carlos validade hoje+30):
```csharp
[Fact] public async Task Lista_tabs_com_janelas_e_cabecalho()
// dono GET /agenda → cabecalho {pendenciasHoje 1, atrasadas 1, embarquesSemana 0}; pendencias.atrasadas 1 (atrasada true), hoje 1, semana 1, total 3; embarques 1 (V1, numPax 2, faseOperacional "confirmada"/"em_emissao" conforme reservas; V3 cancelada ausente); retornos 1 (V2, posViagemEm = data da pendência); documentos: Lúcia (validade, diasParaVencer 40, numero presente para dono, situacao "so_cadastro") e Pedro (numero null, validade null, proximaViagemDestino "Lisboa"); creditos 1 (diasParaVencer 30); responsaveis contém dono e agente
// ?responsavelId=<agente> → pendencias só a de hoje; ?responsavelId=<uuid aleatório> → listas vazias (sem 422)
[Fact] public async Task Externa_ve_so_o_proprio_universo_e_sem_numero_de_documento()
// ana GET /agenda → pendencias: só a de V1 (hoje+5) (a atrasada do dono e a do agente somem); embarques: V1; retornos: [] (V2 é do dono); documentos: Pedro e Carlos? (Carlos sem passaporte + viagem internacional → linha) com numero null; creditos: 1 (crédito do Carlos ligado a viagem própria — se a origem for V2 do dono, 0: fixar no cenário); contador (ViagemVer) → 200; agente → 200 com numero (ClienteVerDocumento)
[Fact] public async Task Badges_por_permissao()
// dono → {agenda 2, financeiro n (inserir reserva aguardando com prevista hoje−1 → 1), clientes 1}; ana → {agenda 1, financeiro null, clientes 1 ou 0}; contador → financeiro 1, clientes null (sem ClienteVer)
[Fact] public async Task Aniversarios_proximos()
// Carlos nascido em (hoje+3 dias, ano 1980), Lúcia (hoje−1), Pedro sem data: GET /clientes/aniversarios?dias=7 → só Carlos com idade correta e proximo = hoje+3; ?dias=0 → []; ?dias=61 → 422 dias_invalido; ana → só clientes de viagens próprias
```
`PendenciasTests.cs` (+):
```csharp
[Fact] public async Task Cria_pendencia_solta_sem_viagem_e_por_cliente()
// agente POST /pendencias { titulo "Ligar", dataPrevista hoje, prioridade "normal", clienteIds [] } → 201 1 item viagemId null clienteId null; { clienteIds [carlos, lucia] } → 2 itens com clienteNome; clienteIds [uuid de outra agência] → 422 nao_encontrado; externa → 403; GET /agenda lista as criadas
```
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar** (`AgendaSql.cs` com as consultas nomeadas; `AgendaService.cs` ≤ 300).
- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(agenda): agenda tabs (pendencias/embarques/retornos/documentos/creditos) with per-profile universe, sidebar badges, birthdays, standalone pendencia`

---

### Task 2 (backend): `Modules/Relatorios` + CSV

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Relatorios/RelatorioDtos.cs`, `backend/src/Meridiano.Api/Modules/Relatorios/RelatoriosSql.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Relatorios/RelatoriosService.cs`, `backend/src/Meridiano.Api/Modules/Relatorios/RelatoriosEndpoints.cs`
- Create: `backend/tests/Meridiano.Api.Tests/RelatoriosTests.cs`

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class RelatoriosService(DbSessaoFactory sessoes)
{
    public Task<RelatorioResumoDto> ResumoAsync(ContextoSessao ctx, FiltroRelatorio f, CancellationToken ct);
    public Task<string> CsvAsync(ContextoSessao ctx, FiltroRelatorio f, CancellationToken ct);   // Csv.Documento(...)
}
public static class RelatoriosEndpoints   // MapRelatoriosEndpoints: grupo /relatorios .RequerPermissao(Permissao.RelatorioVer); GET /resumo; GET /csv → Results.Text(csv, "text/csv; charset=utf-8") + header Content-Disposition attachment; filename="relatorio-{ano}.csv"
```
  - `Ano` default = ano corrente; `< 2000` ou `> corrente + 1` → 422 `ano_invalido`; `VendedorId` → `ReferenciaAsync(Usuario)` (sem `exigirAtivo`: vendedor inativo ainda tem histórico) → `nao_encontrado`.
  - Todas as fórmulas da seção "Fórmulas". Uma ida ao banco por bloco (KPIs em uma query com `filter`; caixa em outra; despesas; teto; meses; tipo; fornecedores; serviços; anos; vendedores = `select id, nome from usuario where agencia_id and exists (viagem vendedor_id) order by nome`). Arredondar `decimal` a 2 casas (`Math.Round(…, 2, MidpointRounding.AwayFromZero)`) e percentuais a 1.
  - `RelatoriosSql.cs` começa com o comentário-fonte das fórmulas (tabela acima, texto integral).

- [ ] **Step 1: Testes** (`RelatoriosTests.cs`; cenário determinístico com `data_compra` fixas no ano corrente — usar `var ano = DateTime.Today.Year`: dono, financeiro, contador, agente, externa `ana@` (vendedora) e `marcos@`; fornecedores CVC e Decolar; viagens: A (Ana, internacional, jan) reservas CVC `valor_cliente 10000 valor_total 9000 valor_comissao 1000` tipos `{aereo,hospedagem}` + Decolar `2000/1800/200` tipos `{seguro}`; B (Marcos, nacional, mar) CVC `5000/4500/300` tipos `{hospedagem}`; C (Ana, nacional, ano−1 dez) CVC `4000/3600/400`; reserva cancelada em A `3000/2700/300` sem comissão mantida; movimentos: `recebimento_operadora` 1000 (A, fev, ano), 200 (A, abr), estorno −100 (A, mai), recebimento 400 da reserva de C em jan do ano (ano anterior → `RecebidoDeAnosAnteriores`); despesas pagas no ano: fixo 800 (fev), operacional 150 ligada a B (mar), imposto 75.90 não paga; `agencia.config.teto_mei` 81000):
```csharp
[Fact] public async Task Resumo_do_ano_separa_competencia_caixa_e_despesas()
// dono GET /relatorios/resumo → ano corrente; kpis {vendaAno 17000 (10000+2000+5000; cancelada e C fora), reservas 3, viagens 2, receitaPrevista 1500 (1000+200+300), receitaRecebida 1500 (1000+200−100+400), recebidoDeAnosAnteriores 400, despesasPagas 950, despesasFixas 800, despesasViagens 150, resultadoOperacional 550, margemOperacionalPct 3.2, margemComercialPct 8.8}; tetoMei {receitaAno 1500, teto 81000, percentualTeto 1.9, alerta false}; receitaPorMes.Length 12, [0] prevista 1200 (jan: A) recebida 400, [1] prevista 0 recebida 1000, [2] prevista 300 recebida 0, [4] recebida −100; nacionalInternacional: internacional {venda 12000, pct 70.6, margemPct 10.0}, nacional {5000, 29.4, 6.0}; fornecedores[0] CVC {reservas 2, volume 15000, receita 1300, margemPct 8.7}, [1] Decolar; servicos: hospedagem 2, aereo 1, seguro 1, demais 0 (9 itens); anos contém ano e ano−1; ate = mês corrente por extenso; vendedores contém Ana e Marcos
[Fact] public async Task Filtro_de_vendedor_e_ano()
// ?vendedorId=<ana> → vendaAno 12000, reservas 2, viagens 1, receitaRecebida 1500? (todos os movimentos são de viagens da Ana → 1500), despesasPagas 0 (B é do Marcos), despesasFixas 0, tetoMei igual ao da agência (1500); ?vendedorId=<marcos> → vendaAno 5000, despesasPagas 150, despesasViagens 150
// ?ano=<ano−1> → vendaAno 4000, reservas 1, receitaRecebida 0, recebidoDeAnosAnteriores 0, tetoMei null; ?ano=1999 → 422 ano_invalido; ?vendedorId=<uuid> → 422 nao_encontrado
[Fact] public async Task Csv_do_ano_e_permissoes()
// financeiro GET /relatorios/csv → 200, content-type text/csv, content-disposition attachment, corpo começa com BOM, cabeçalho "Código;Cliente;…;Serviços", 4 linhas de dados (3 ativas + cancelada com Status "cancelada"), linha da reserva CVC de A tem "10000,00" e "aereo, hospedagem"; contador → 200; agente → 403; externa → 403
[Fact] public async Task Ano_sem_dados_devolve_zeros_e_12_meses()
// agência nova: kpis zerados, margens null, tetoMei null, receitaPorMes 12 itens zerados, nacionalInternacional 2 itens pct 0, fornecedores [], servicos 9 itens com 0
```
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar** (`RelatoriosService.cs` ≤ 300; SQL em `RelatoriosSql.cs`).
- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(relatorios): yearly summary with separated accrual/cash/expense axes, MEI ceiling, monthly bars, supplier and service breakdowns, CSV export`

---

### Task 3 (backend): Equipe — `Modules/Admin` + convite/reenvio

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Admin/UsuarioDtos.cs`, `backend/src/Meridiano.Api/Modules/Admin/UsuarioService.cs`, `backend/src/Meridiano.Api/Modules/Admin/AdminEndpoints.cs`
- Modify: `backend/src/Meridiano.Api/Auth/ConviteService.cs` (+ `ReenviarAsync`), `backend/src/Meridiano.Api/Auth/ConviteEndpoints.cs` (só se necessário; preferir não tocar)
- Modify: `backend/tests/Meridiano.Api.Tests/UsuariosTests.cs` (DTO novo), `backend/tests/Meridiano.Api.Tests/ConviteTests.cs` (se o DTO mudou); Create: `backend/tests/Meridiano.Api.Tests/EquipeTests.cs`

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class UsuarioService(DbSessaoFactory sessoes)
{
    public Task<EquipeDto> ListarAsync(ContextoSessao ctx, CancellationToken ct);                       // antes IReadOnlyList<UsuarioDto>
    public Task<ColaboradorDto> ObterAsync(ContextoSessao ctx, Guid id, CancellationToken ct);
    public Task<IReadOnlyList<VendedorDto>> ListarVendedoresAsync(ContextoSessao ctx, CancellationToken ct);   // inalterado
    public Task<ColaboradorDto> CriarAsync(ContextoSessao ctx, NovoColaboradorRequest req, CancellationToken ct);
    public Task<ColaboradorDto> AtualizarAsync(ContextoSessao ctx, Guid id, AtualizarUsuarioRequest req, CancellationToken ct);   // devolve ColaboradorDto
    public static IReadOnlyList<PerfilDto> Perfis();   // Enum.GetValues<Perfil>() → Permissoes.Do(p).Select(x => x.Chave())
}
// ConviteService: public Task ReenviarAsync(ContextoSessao ctx, Guid usuarioId, CancellationToken ct);
//   select nome, email, senha_hash is not null as temAcesso, ativo from usuario where id and agencia_id → nao_encontrado; temAcesso → ja_tem_acesso; !ativo → usuario_inativo;
//   update usuario set convite_token = @token, convite_expira_em = now() + 72h where id (commit) → e-mail (fora da transação, mesmo HTML de ConvidarAsync)
// AdminEndpoints (grupo /usuarios, UsuarioGerenciar): GET / · GET /perfis (declarar ANTES de /{id:guid}) · GET /{id:guid} · POST / → 201 Location /api/v1/usuarios/{id} · PUT /{id:guid} · POST /{id:guid}/convite → 200 ColaboradorDto (chama ConviteService.ReenviarAsync e depois ObterAsync)
```
  - `Colunas` do serviço ganham `acesso` (case da R10), `ultimo_login_em as UltimoLoginEm`, `convite_expira_em as ConviteExpiraEm`. `EquipeDto.ComAcesso` = `acesso = 'acesso_ativo'`; `ConvitesPendentes` = `acesso = 'convite_pendente'`. Ordem `nome`.
  - **Criar:** `Nome` vazio → `nome_obrigatorio`; `Email` inválido (sem `@`) → `email_invalido`; `Perfil` → `PerfilExtensions.DoBanco` (inválido → `perfil_invalido`); percentual 0–100 → `percentual_invalido`; `insert into usuario (agencia_id, nome, email, telefone, perfil, gera_repasse, percentual_padrao) … returning` + `23505` → 422 `email_ja_cadastrado` (mesma mensagem de `ConvidarAsync`). Sem `senha_hash`, sem token → `sem_acesso`.
  - **Atualizar:** lógica existente (lock `donos:`, `ultimo_dono`, `xmin`) devolvendo `ColaboradorDto`.
  - Nenhum log de senha/token em nenhum DTO (só `acesso` e `conviteExpiraEm`).

- [ ] **Step 1: Testes** — `UsuariosTests.cs`: adaptar asserções ao `EquipeDto`/`ColaboradorDto` (contadores, `acesso`). `EquipeTests.cs` (dono `dono@`, agente `ag@`; Ana externa com senha; Marcos externo sem senha; Bruno agente com `convite_token` válido (`InserirUsuarioAsync` + `update` via owner); Cláudia contadora inativa):
```csharp
[Fact] public async Task Lista_com_estados_derivados_e_contadores()
// dono GET /usuarios → total 6, comAcesso 3 (dono, ag, ana), convitesPendentes 1; Marcos acesso "sem_acesso", Bruno "convite_pendente" com conviteExpiraEm futuro, Cláudia "inativo", ana "acesso_ativo" com ultimoLoginEm null (nunca logou) — dono ultimoLoginEm preenchido; agente → 403
[Fact] public async Task Cria_colaborador_sem_acesso_e_recusa_email_repetido()
// POST /usuarios { nome "Marcos Castro 2", email "m2@x.com", perfil "vendedor_externo", geraRepasse true, percentualPadrao 8 } → 201 acesso "sem_acesso", Location; GET /usuarios/{id} → 200; mesmo e-mail → 422 email_ja_cadastrado; email "x" → email_invalido; perfil "rei" → perfil_invalido; percentual 101 → percentual_invalido
[Fact] public async Task Convida_reenvia_e_bloqueia_quem_ja_tem_acesso()
// POST /usuarios/{marcos}/convite → 200 acesso "convite_pendente", conviteExpiraEm ≈ now+72h, e-mail enviado (IEnviadorEmail fake registrado via WithWebHostBuilder: capturar destinatário e link contendo "/definir-senha?token="); token gravado ≠ null; repetir → 200 com token diferente (owner select); POST /usuarios/{ana}/convite → 422 ja_tem_acesso; {claudia} → 422 usuario_inativo; uuid aleatório → 422 nao_encontrado
[Fact] public async Task Perfis_expoe_a_matriz()
// GET /usuarios/perfis → 5 itens; "dono" contém "usuario.gerenciar"; "vendedor_externo" == ["viagem.ver_proprias","cliente.ver_proprios"]; "contador" contém "repasse.ver_todos" (R9); agente → 403
[Fact] public async Task Inativar_ultimo_dono_continua_bloqueado()
// PUT /usuarios/{dono} ativo=false → 422 ultimo_dono (regressão da guarda existente com o DTO novo)
```
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(equipe): team list with derived access state, create collaborator without access, invite/resend via ConviteService, profile matrix endpoint`. Reviewers: `code-reviewer` com foco `security-reviewer` (`Auth/ConviteService.cs`, tokens, e-mail).

---

### Task 4 (backend): Auditoria geral + CSV + projeção de documento

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Auditoria/AuditoriaDtos.cs`, `AuditoriaService.cs`, `AuditoriaEndpoints.cs`, `Frases.cs`, `Projecao.cs`
- Create: `backend/src/Meridiano.Api/Modules/Auditoria/AuditoriaSql.cs`
- Modify: `backend/tests/Meridiano.Api.Tests/AuditoriaTests.cs`, `backend/tests/Meridiano.Api.Tests/AuditoriaProjecaoTests.cs`

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class AuditoriaService(DbSessaoFactory sessoes)
{
    public Task<IReadOnlyList<EventoAuditoriaDto>> DaViagemAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, CancellationToken ct);   // existente; passa verDocumento; preenche ViagemId/CodigoViagem
    public Task<AuditoriaDto> ListarAsync(ContextoSessao ctx, UsuarioAtual u, FiltroAuditoria f, CancellationToken ct);
    public Task<string> CsvAsync(ContextoSessao ctx, UsuarioAtual u, FiltroAuditoria f, CancellationToken ct);
}
public static class ProjecaoAuditoria { public static EventoAuditoriaDto? Projetar(EventoAuditoriaDto e, bool verValores, bool verResultado, bool verDocumento); }
// CamposSensiveis = ["cpf", "contato_emergencia", "numero"] removidos sem verDocumento (tabela cliente; futuro documento_cliente)
// Frases.TituloDe ganha: usuario (INSERT "Colaborador criado"; UPDATE ativo→false "Colaborador inativado"; ativo→true "Colaborador reativado"; perfil "Perfil alterado"; demais "Colaborador alterado"),
//   cliente (INSERT "Cliente criado"; excluido_em "Cliente excluído"; demais "Cliente alterado"), despesa (INSERT "Despesa lançada"; pago→true "Despesa paga"; excluido_em "Despesa excluída"; demais "Despesa alterada"),
//   fechamento_periodo (INSERT "Período fechado"; DELETE "Período reaberto"), log_acesso_documento (ACESSO: "Visualizou o passaporte de Lúcia Mendes" / "Visualizou o anexo <nome_arquivo>"; subtítulo "documento sensível · LGPD")
// EntidadeDe ganha usuario "Colaborador", cliente "Cliente", despesa "Despesa", fechamento_periodo "Período"
// AuditoriaEndpoints: GET /auditoria ([AsParameters] FiltroAuditoria) e GET /auditoria/csv, ambos .RequerPermissao(AuditoriaVer); CSV filename="auditoria-{yyyyMMdd}.csv"
```
  - **Consulta (`AuditoriaSql`):** `union all` de (a) `auditoria a left join usuario u` com `a.agencia_id = @agencia`, colunas do `EventoRow` + `ViagemId` (subquery por tabela: viagem → `registro_id`; reserva/servico/movimento → via `reserva.viagem_id`; repasse → `repasse.viagem_id`; demais `null`) + `CodigoViagem`, `Rotulo` (case existente + `usuario` → nome; `cliente` → nome; `despesa` → descricao; `fechamento_periodo` → `to_char(competencia, 'MM/YYYY')`); (b) `log_acesso_documento l join usuario u left join documento_cliente d left join cliente c left join anexo an` com `Tabela = 'log_acesso_documento'`, `Acao = 'ACESSO'`, `Alteracoes = '{}'`, `Rotulo = coalesce(d.tipo || ' de ' || c.nome, 'anexo ' || an.nome_arquivo, 'documento removido')`, `RegistroId = coalesce(l.documento_id, l.anexo_id, uuid nulo)`, `Id = l.id`. Filtros: `[usuario_id = @usuarioId]`, `[criado_em >= @de]`, `[criado_em < @ate + 1]`, `[criado_em < @antesDe]`; `Oque`: `valores` → (a) `tabela = 'reserva' and acao = 'UPDATE' and alteracoes ?| array['valor_total','valor_comissao','valor_cliente','rav_operadora','taxa_servico']`; `recebimentos` → (a) `tabela = 'movimento_financeiro'`; `cancelamentos` → (a) `(tabela = 'viagem' and alteracoes->'cancelada'->>'para' = 'true') or (tabela = 'reserva' and alteracoes->'status'->>'para' = 'cancelada')`; `acesso_documento` → só (b); `tudo`/null → ambos; outro → 422 `oque_invalido`. `Tamanho` fora de `[1,100]` → 422 `tamanho_invalido`; `De > Ate` → `periodo_invalido`. Ordem `criado_em desc, id desc`, `limit @tamanho + 1` (o extra decide `ProximoAntesDe` = `CriadoEm` do último devolvido). `Total` = `count(*)` da união com os filtros (sem `antesDe`). `Usuarios` = atores distintos (`usuario_id` não nulo) da agência em `auditoria` ∪ `log_acesso_documento`, `order by nome`.
  - Projeção como na timeline (`Projetar(verValores, verResultado, verDocumento)`); evento projetado para `null` some da página (o `Total` não desconta — documentar; front mostra "n eventos" pelo `Total`). Eventos (b) nunca são removidos.
  - **CSV:** mesmos filtros sem cursor, `limit 5000`, colunas `Quando;Quem;Entidade;Evento;Detalhe;Motivo;Viagem;Alterações` (`Alterações` = `campo: de → para` separados por `; ` dentro de aspas).
  - `DaViagemAsync`: reutiliza a mesma consulta (a) filtrada por viagem (`AuditoriaSql.PorViagem`), sem (b); remove o `limit 200` fixo? **Não** — mantém (deferida da 3.3 continua no BACKLOG).

- [ ] **Step 1: Testes** — `AuditoriaProjecaoTests.cs` (+): `Projetar(evento cliente com cpf e nome, verDocumento: false)` remove `cpf`, mantém `nome`; `true` mantém; evento `log_acesso_documento` nunca vira `null`. `AuditoriaTests.cs` (+; cenário: dono, financeiro, contador (sem ClienteVerDocumento), agente; viagem com reserva; sequência real via API para gerar auditoria: `PUT /viagens/{id}` mudando `valor_comissao`; `POST /movimentos`; `POST /reservas/{id}/cancelar`; `PUT /clientes/{id}` mudando `cpf`; `PUT /usuarios/{ag}` `ativo=false`; `GET /clientes/{id}/documentos` como agente (gera `log_acesso_documento` com passaporte inserido pela fixture); `POST /periodos/{m}/fechar` + `reabrir` com `X-Motivo`):
```csharp
[Fact] public async Task Lista_geral_com_categorias_cursor_e_total()
// dono GET /auditoria?tamanho=3 → 3 itens ordem desc, total ≥ 8, proximoAntesDe = criadoEm do 3º, usuarios contém dono e agente; GET ?antesDe=<proximoAntesDe>&tamanho=3 → próximos 3 sem repetir ids; ?oque=valores → só "Valores da reserva alterados" com codigoViagem; ?oque=recebimentos → movimento; ?oque=cancelamentos → "Reserva cancelada"; ?oque=acesso_documento → 1 item tabela log_acesso_documento, acao ACESSO, titulo "Visualizou o passaporte de <nome>", usuarioNome do agente; ?usuarioId=<agente> → só eventos do agente; ?de=<amanhã> → 0, total 0; ?oque=x → 422 oque_invalido; ?tamanho=101 → 422 tamanho_invalido; ?de=hoje&ate=ontem → 422 periodo_invalido
[Fact] public async Task Projecao_por_perfil_na_lista_geral()
// contador GET /auditoria → evento do cliente sem chave "cpf" nas alteracoes (mas presente para o dono); evento de repasse ausente para quem não tem ViagemVerResultado (agente → 403 antes: agente não tem AuditoriaVer — usar financeiro sem… financeiro tem tudo; então cobrir só o contador: tem ViagemVerResultado → repasse presente); "Colaborador inativado" e "Período fechado"/"Período reaberto" (motivo preenchido) aparecem com títulos certos
[Fact] public async Task Csv_e_permissao()
// financeiro GET /auditoria/csv?oque=valores → 200 text/csv, BOM, cabeçalho "Quando;Quem;Entidade;Evento;Detalhe;Motivo;Viagem;Alterações", 1 linha com "valor_comissao: 1000,00 → 1100,00" (formato: numérico com vírgula); agente → 403; externa → 403
[Fact] public async Task Timeline_da_viagem_ganha_viagem_id_e_esconde_cpf()
// GET /viagens/{id}/auditoria → itens com viagemId = id e codigoViagem; (regressão) demais asserções existentes continuam
```
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar** (`AuditoriaService.cs` ≤ 300; SQL em `AuditoriaSql.cs`).
- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(auditoria): agency-wide audit list with categories, cursor, LGPD document-access events, per-profile document projection, CSV export`

---

### Task 5 (backend): jobs `pendencias_derivadas` e `resumo_diario_email`

**Files:**
- Modify: `backend/src/Meridiano.Api/Jobs/PendenciasDerivadasJob.cs`, `backend/src/Meridiano.Api/Jobs/ResumoDiarioEmailJob.cs` (esqueletos de T0)
- Create: `backend/src/Meridiano.Api/Jobs/ResumoDiarioHtml.cs`
- Create: `backend/tests/Meridiano.Api.Tests/JobsDerivadosTests.cs`

**Depends-on:** T0, T1 (`AgendaService.ResumoDiarioAsync`, `AgendaDtos`)

**Interfaces:**
```csharp
public sealed class PendenciasDerivadasJob(DbSessaoFactory sessoes) : IJob   // Nome "pendencias_derivadas", PorAgencia true
public sealed class ResumoDiarioEmailJob(DbSessaoFactory sessoes, IEnviadorEmail email) : IJob   // "resumo_diario_email", PorAgencia true
public static class ResumoDiarioHtml { public static string Montar(string nomeUsuario, DateOnly hoje, ResumoDiarioDto r); public static bool Vazio(ResumoDiarioDto r); }
```
  - **Regras (R13), por agência, uma transação, `ConfirmarAsync` no fim.** Conjunto **desejado** calculado em SQL (uma CTE por regra) com colunas `chave_unica, titulo, data_prevista, prioridade, responsavel_id, cliente_id, viagem_id`:
    - `passaporte` (`'pendencia:' || cliente_id || ':passaporte'`): (a) passaporte não excluído com `validade < current_date + 180` → título `'Renovar passaporte — ' || nome`, `data_prevista = greatest(validade - 180, current_date)`, `prioridade = 'urgente'` se existe viagem internacional futura não cancelada em que é passageiro com `data_ida + 180 > validade` (viagem exige 6 meses), senão `normal`; (b) cliente **sem** passaporte não excluído, passageiro de viagem internacional futura → `'Cadastrar passaporte — ' || nome`, `data_prevista = greatest(data_ida - 30, current_date)`, `urgente`. Um cliente com vários passaportes: considerar o de maior `validade`. Responsável = agente/vendedor da viagem futura mais próxima; sem viagem → Dono ativo mais antigo. `viagem_id` = essa viagem (ou null).
    - `seguro` (`'pendencia:' || viagem_id || ':seguro'`): viagem internacional não cancelada com `data_ida between current_date and current_date + 30` sem `'seguro' = any(tipos_servico)` em reserva ativa e sem `servico.tipo = 'seguro'` não excluído → `'Confirmar seguro — ' || destino`, `data_prevista = greatest(data_ida - 7, current_date)`, `normal`, responsável agente/vendedor, `viagem_id`, `cliente_id` = titular.
    - `contato_emergencia` (`'pendencia:' || cliente_id || ':contato_emergencia'`): titular (`vw_viagem_titular`) de viagem não cancelada com `data_ida between current_date and current_date + 30` e `cliente.contato_emergencia is null` → `'Contato de emergência — ' || nome`, `data_prevista = greatest(data_ida - 7, current_date)`, `normal`, responsável agente/vendedor, `viagem_id`.
    - **Aplicar:** `insert into pendencia (agencia_id, titulo, data_prevista, responsavel_id, cliente_id, viagem_id, origem, prioridade, chave_unica) select … from desejado on conflict (agencia_id, chave_unica) do update set titulo = excluded.titulo, data_prevista = excluded.data_prevista, prioridade = excluded.prioridade, responsavel_id = excluded.responsavel_id, viagem_id = excluded.viagem_id, status = 'aberta' where pendencia.status in ('aberta','cancelada')` (concluída intocada). Depois `update pendencia set status = 'cancelada' where agencia_id and origem = 'automatica' and chave_unica like 'pendencia:%' and status = 'aberta' and chave_unica not in (select chave_unica from desejado)`.
  - **Resumo (R14):** destinatários = `usuario` ativo, `senha_hash is not null`, `perfil in ('dono','financeiro','agente')`; para cada: `apenasResponsavel = perfil = 'agente' ? id : null`, `apenasVendedor = null`, `verFinanceiro = perfil in ('dono','financeiro')`; `ResumoDiarioAsync` dentro de uma sessão da agência (só leitura; `ConfirmarAsync` não necessário); coletar `(email, assunto, html)`; **fechar a sessão**; enviar um a um (falha em um destinatário → log + continua; job falha no fim se algum falhou). `Vazio` → pular. Assunto `"Resumo de {dd/MM} — Meridiano"`. HTML: `<h2>`, seções `<h3>` + `<ul>` (pendência: título · cliente · viagem · "atrasada há n dias"), embarques (código · destino · data), aniversariantes (nome · idade), comissões atrasadas (n reservas · R$ x). Sem template externo.

- [ ] **Step 1: Testes** (`JobsDerivadosTests.cs`; padrão de `JobsTests.cs`: resolver `JobRunner` de um `IServiceScope`, `ExecutarAsync("pendencias_derivadas", ct)`; e-mail com `IEnviadorEmail` fake via `WithWebHostBuilder(w => w.ConfigureServices(s => { s.RemoveAll<IEnviadorEmail>(); s.AddSingleton<IEnviadorEmail>(fake); }))`; cenário: dono, agente `ag@` (com senha), externa sem senha; Carlos titular + Pedro passageiro de V1 internacional ida hoje+20 (agente_id = ag) sem seguro; Lúcia com passaporte validade hoje+100 e V2 internacional ida hoje+200 (exige: 200+180 > 100 → urgente) e V3 nacional; Carlos `contato_emergencia null`, passaporte validade hoje+400; Pedro sem passaporte; Roberto sem viagem com passaporte validade hoje+90):
```csharp
[Fact] public async Task Gera_pendencias_derivadas_por_chave_e_e_idempotente()
// rodar → código 0; pendências (owner select por chave_unica): 'pendencia:<lucia>:passaporte' urgente data hoje (100−180 < hoje), responsável agente/vendedor de V2, viagem V2; 'pendencia:<pedro>:passaporte' "Cadastrar passaporte — Pedro" urgente data hoje (20−30 < hoje), viagem V1; 'pendencia:<roberto>:passaporte' normal, responsável = dono, viagem null; Carlos sem pendência de passaporte (400 > 180); 'pendencia:<V1>:seguro' data hoje+13, responsável ag, cliente Carlos; 'pendencia:<carlos>:contato_emergencia' data hoje+13; total 5, todas origem 'automatica' status 'aberta'
// rodar de novo → mesmas 5 linhas (count igual, ids iguais)
[Fact] public async Task Resolve_reabre_e_respeita_concluida()
// concluir (owner update status concluida) a de seguro; adicionar 'seguro' em tipos_servico de V1 → rodar → seguro continua 'concluida' (intocada) — depois remover seguro de novo → rodar → continua concluida (nunca reabre concluída)
// preencher contato_emergencia do Carlos → rodar → 'contato_emergencia' vira 'cancelada'; limpar de novo → rodar → volta 'aberta' (reabre cancelada)
// Lúcia renova passaporte (validade hoje+800) → rodar → pendência dela 'cancelada'; GET /agenda (dono) documentos: Lúcia some da lista de vencendo
[Fact] public async Task Resumo_diario_envia_um_email_por_usuario_com_acesso_e_pula_vazios()
// pendências: uma hoje resp. agente, uma atrasada resp. dono; embarque amanhã; Carlos aniversário hoje; reserva aguardando com prevista ontem → rodar "resumo_diario_email" → fake recebeu 2 e-mails (dono e agente; externa sem senha não); assunto contém a data; html do dono contém as duas pendências, "Comissões atrasadas" e o aniversariante; html do agente contém só a pendência dele e não contém "Comissões"; agência sem nada → 0 e-mails; fake que lança na 1ª chamada → job devolve 1 (falha) mas o 2º e-mail ainda foi tentado
```
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(jobs): derived pendencias (passport, insurance, emergency contact) upserted by chave_unica, daily summary e-mail per user`

---

### Task 6 (backend): jobs `expurgo_auditoria` e `expurgo_anexos`

**Files:**
- Modify: `backend/src/Meridiano.Api/Jobs/ExpurgoAuditoriaJob.cs`, `backend/src/Meridiano.Api/Jobs/ExpurgoAnexosJob.cs`
- Create: `backend/tests/Meridiano.Api.Tests/JobsExpurgoTests.cs`

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class ExpurgoAuditoriaJob(DbSessaoFactory sessoes) : IJob          // "expurgo_auditoria"
public sealed class ExpurgoAnexosJob(DbSessaoFactory sessoes, IArmazenamentoArquivo storage, ILogger<ExpurgoAnexosJob> log) : IJob   // "expurgo_anexos"
```
  - **Auditoria (R15):** `meses = coalesce((select (config->>'retencao_auditoria_meses')::int from agencia where id = @agencia), 24)`; `delete from auditoria where agencia_id = @agencia and acao <> 'DELETE' and criado_em < now() - make_interval(months => @meses)`; log do total apagado; `ConfirmarAsync`. (RLS de `auditoria` já cobre; o job roda com `app.agencia_id`.)
  - **Anexos (R15):** sessão 1: `select id, caminho from anexo where agencia_id and data_descarte < current_date and excluido_em is null order by data_descarte limit 500` → fechar sessão. Para cada: `storage.ExcluirAsync(caminho)` (fora de transação; exceção → log warning + próximo); depois sessão curta: `delete from anexo where id and agencia_id` + `ConfirmarAsync` (FK `log_acesso_documento.anexo_id` → `set null`, 0012). Falhas acumuladas → lançar no fim (`InvalidOperationException` com contagem) para o `JobRunner` marcar `sucesso = false`.

- [ ] **Step 1: Testes** (`JobsExpurgoTests.cs`; storage fake: `sealed class StorageFake : IArmazenamentoArquivo` gravando `Excluidos` e com `FalharEm` opcional, registrado via `WithWebHostBuilder(w => w.ConfigureServices(s => { s.RemoveAll<IArmazenamentoArquivo>(); s.AddSingleton<IArmazenamentoArquivo>(fake); }))`):
```csharp
[Fact] public async Task Expurga_auditoria_alem_da_retencao_preservando_delete()
// owner insert em auditoria: UPDATE com criado_em now()−25 meses, DELETE −25 meses, UPDATE −23 meses, UPDATE −25 meses em outra agência; config da agência default (24) → rodar → sobram: DELETE antigo, UPDATE −23, o da outra agência; rodar de novo → nada muda; agência com retencao 12 → UPDATE −23 some
[Fact] public async Task Expurga_anexos_vencidos_apagando_objeto_antes_da_linha()
// anexos (owner insert com confirmado_em): A data_descarte ontem, B hoje+1, C ontem já excluido_em, D ontem com log_acesso_documento apontando → rodar → fake.Excluidos == [A.caminho, D.caminho]; linhas A e D removidas (count 0), B e C intactas; log_acesso_documento de D existe com anexo_id null; rodar de novo → fake sem novas exclusões
[Fact] public async Task Falha_no_storage_nao_apaga_a_linha_e_marca_job_com_falha()
// fake.FalharEm = A.caminho → rodar → código 1; linha A continua; D removida; job_execucao.sucesso false
```
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(jobs): monthly purge of audit rows past retention (keeping DELETE) and of expired attachments (object first, then row)`

---

### Task 7 (front): Agenda + badges na sidebar

**Files:**
- Create: `frontend/src/api/agenda.ts`, `frontend/src/api/agenda.test.ts`
- Modify: `frontend/src/api/pendencias.ts` (+ `criarSolta`), `frontend/src/components/Pendencias/escopo.ts`, `NovaPendenciaModal.tsx` (+ `.test.tsx`), `frontend/src/components/pendencias.ts`
- Create: `frontend/src/pages/agenda/{AgendaPage.tsx,AgendaPage.test.tsx,Agenda.module.css,PendenciasAgenda.tsx,EmbarquesTab.tsx,DocumentosTab.tsx,CreditosTab.tsx}`; Modify: `frontend/src/pages/agenda/rotas.tsx`
- Modify: `frontend/src/shell/navegacao.ts`, `frontend/src/shell/Sidebar.tsx`, `frontend/src/shell/Sidebar.test.tsx`, `frontend/src/shell/Sidebar.module.css`

**Depends-on:** T0 (contrato de T1 neste plano; T1 em paralelo)

**Interfaces:** (ver bloco TS do contrato) + `ItemSidebar.badge?: keyof BadgesDto`; `Sidebar` usa `useQuery({ queryKey: chavesAgenda.badges(), queryFn: agendaApi.badges, refetchInterval: 5 * 60_000, refetchOnWindowFocus: true })` e renderiza `<Badge tone="warning">{n}</Badge>` quando `n > 0` (`aria-label` "{n} pendências" etc.).
  - **`AgendaPage`:** `PageHeader` título "Agenda", subtítulo `"{Terça, 7 de abril} · {n} pendências hoje · {m} atrasadas · {k} embarques esta semana"` (data por `Intl.DateTimeFormat("pt-BR", { weekday: "long", day: "numeric", month: "long" })`); ações: `Select` "Responsável: todos" (de `responsaveis`) + botão "+ Nova pendência" (`primary`, só com `pode("viagem.editar")`). `Tabs` com contadores: Pendências (`pendencias.total`), Embarques e retornos (`embarques.length + retornos.length`), Documentos vencendo, Créditos vencendo.
  - **`PendenciasAgenda`:** três `Section` ("Atrasadas n", "Hoje n", "Esta semana n"; seção vazia some; tudo vazio → `EmptyState` "Nada para hoje"); linhas com `LinhaPendencia` (`mostrarViagem`), ações concluir/adiar/editar/excluir reaproveitando os mesmos `useMutation` de `ListaPendencias` (extrair para um hook `usePendenciasAcoes(fonte)` em `components/Pendencias/usePendenciasAcoes.ts` usado pelos dois — refatoração permitida: `ListaPendencias` é de T7). Invalidação: `["agenda"]`.
  - **`EmbarquesTab`:** `Section` "Embarques próximos 14 dias" — linha: titular · destino · `dom 12/04` · `n pax` · `StatusCell fase_operacional` · "Abrir" (link `/viagens/{id}`); `Section` "Retornos" — titular · destino · data · "pós-viagem em {PosViagemEm}".
  - **`DocumentosTab`:** `DataTable` Pessoa · Documento (`Passaporte {numero}` ou "Passaporte não cadastrado") · Validade (`DateCell` + "· n dias" / "vencido há n dias") · Próxima viagem (`destino · dd/MM` ou "—") · Pendência (`Chip` "na agenda" ou "só no cadastro") · Abrir (`/clientes/{id}`).
  - **`CreditosTab`:** `DataTable` Pessoa · Operadora · Origem · Validade (`mm/yyyy · n meses`) · Valor (`MoneyCell`) · Abrir.
  - **`NovaPendenciaModal` (escopo agenda):** sem "Para quem"; campo "Pessoa (opcional)" = combobox `viagensApi.buscarClientes(q)` (existente em `api/viagens.ts`, congelado, só importar) → `clienteIds: [id]` ou `[]`; grava por `pendenciasApi.criarSolta`. Edição de pendência existente continua pelo `PUT`.

- [ ] **Step 1: Testes** — `agenda.test.ts` (monta URLs). `NovaPendenciaModal.test.tsx` (+ escopo agenda: sem "Para quem", envia `POST /pendencias` com `clienteIds []`). `AgendaPage.test.tsx` (fetch stub com um `AgendaDto` do protótipo — 2 atrasadas, 3 hoje, 2 semana, 2 embarques, 1 retorno, 3 documentos, 1 crédito): renderiza subtítulo com contagens; tab Pendências mostra as três seções com contadores; troca para "Embarques e retornos" mostra "Ana Beatriz Souza" e "Retornos"; "Documentos vencendo" mostra "Passaporte não cadastrado" e chip "só no cadastro"; "Créditos vencendo" mostra `R$ 5.100,00`; selecionar responsável refaz a query com `?responsavelId=`; "+ Nova pendência" some sem `viagem.editar`; concluir chama `POST /pendencias/{id}/concluir` e invalida. `Sidebar.test.tsx` (+): com `badges {agenda 7, financeiro 2, clientes null}` renderiza badges em Agenda e Financeiro, nenhum em Clientes; `0` não renderiza.
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar tudo** (`lint`, `typecheck`, `test`, `build`). Commit sugerido: `feat(agenda): agenda page with pendencias/embarques/documentos/creditos tabs, responsible filter, standalone pendencia, sidebar badges`

---

### Task 8 (front): Relatórios

**Files:**
- Create: `frontend/src/api/relatorios.ts`, `frontend/src/api/relatorios.test.ts`
- Create: `frontend/src/pages/relatorios/{RelatoriosPage.tsx,RelatoriosPage.test.tsx,Relatorios.module.css,BarrasMensais.tsx,BarrasMensais.test.tsx,ServicosVendidos.tsx}`; Modify: `frontend/src/pages/relatorios/rotas.tsx`

**Depends-on:** T0 (contrato de T2)

**Interfaces:** `relatoriosApi.resumo(ano: number | null, vendedorId: string | null): Promise<RelatorioResumoDto>`; `urlCsv(ano, vendedorId): string`; `chavesRelatorios.resumo(ano, vendedorId)`.
  - **`RelatoriosPage`:** `PageHeader` "Relatórios", subtítulo `"{ano} até {ate} · \"quanto realmente sobrou?\""`; ações: `Select` ano (`anos`), `Select` "Vendedor: todos" (`vendedores`), botão "Exportar CSV" (`secondary`, `baixar(urlCsv(...), \`relatorio-${ano}.csv\`)`). Seis `KpiCard`: Venda no ano (contexto "{n} reservas · {m} viagens") · Receita recebida ("prevista R$ x · inclui R$ y de {ano−1}" quando `recebidoDeAnosAnteriores > 0`) · Despesas pagas ("fixas R$ x · viagens R$ y"; com vendedor: "só despesas ligadas às viagens do vendedor") · Resultado operacional ("receita recebida − despesas pagas", `emphasis result`) · Margem operacional (`x,x %`, contexto "resultado ÷ venda · comercial y,y %") · Teto MEI {ano} (`x %`, contexto "R$ a de R$ b · alerta em 80 %", `tone="warning"` se `alerta`; ausente quando `tetoMei` null → card "Sem movimentos no ano"; `Tooltip` "Receita recebida no ano (caixa) contra o teto configurado da agência"). Vendedor selecionado esconde o card do teto? **Não**: mostra com helper "da agência".
  - **`BarrasMensais`:** 12 colunas CSS (`height: calc(var(--altura) * 1%)` via style inline **com número**, não cor), duas barras por mês (prevista clara `--color-surface-muted`-like token, recebida escura), rótulos `jan…dez`, `aria-label` por mês "abril: prevista R$ x, recebida R$ y"; máximo = maior valor; valores negativos (estorno) exibidos como 0 com `title` do valor real.
  - Bloco "Nacional × internacional": duas linhas com barra proporcional (`pct`) + "R$ x · y %" + rodapé "Margem: internacional a % · nacional b %".
  - `DataTable` "Fornecedores por receita no ano": Fornecedor · Reservas · Volume (`MoneyCell`) · Receita (`MoneyCell`) · Margem (`x,x %`).
  - **`ServicosVendidos`:** título "Serviços vendidos", descrição "reservas que incluem cada serviço (uma reserva pode contar em mais de um)"; barras horizontais por tipo (rótulos num `Record` local com os 9 tipos — `status.ts` não tem mapa de serviço e é congelado).
  - Estados: `Skeleton` durante carga; `Alert` com "Tentar de novo" em erro; ano sem dados mostra zeros (não `EmptyState`).

- [ ] **Step 1: Testes** — `relatorios.test.ts` (URLs com/sem filtros). `BarrasMensais.test.tsx`: 12 grupos com `aria-label`; maior valor → 100 %. `RelatoriosPage.test.tsx` (stub com o `RelatorioResumoDto` do protótipo — venda 187400, recebida 27630, prevista 24180, anos anteriores 6100, despesas 9840/5800/1200, resultado 17790, margens 9,5/12,9, teto 34 %, CVC 24/98100/12400/12,6 …): KPIs com `R$ 187.400,00`, "62 reservas · 41 viagens", "inclui R$ 6.100,00 de 2025", "9,5 %", "34 %"; tabela com "CVC Operadora" e "12,6 %"; serviços "Aéreo" 48; trocar ano refaz query com `?ano=2025`; trocar vendedor → `vendedorId`; "Exportar CSV" chama `baixar` (mock de `@/lib/download`) com `/api/v1/relatorios/csv?ano=2026`; `tetoMei.alerta true` → card com tone warning; `tetoMei null` → "Sem movimentos no ano".
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar tudo.** Commit sugerido: `feat(relatorios): yearly report page with six kpis, monthly bars, national/international split, supplier ranking, services and CSV export`

---

### Task 9 (front): Equipe e Colaborador

**Files:**
- Create: `frontend/src/api/equipe.ts`, `frontend/src/api/equipe.test.ts`
- Create: `frontend/src/pages/equipe/{EquipePage.tsx,EquipePage.test.tsx,Equipe.module.css,ColaboradorPage.tsx,ColaboradorPage.test.tsx,useColaborador.ts,ConvidarModal.tsx,ConvidarModal.test.tsx,PerfilVe.tsx}`; Modify: `frontend/src/pages/equipe/rotas.tsx` (`/equipe`, `/equipe/nova`, `/equipe/:id`)

**Depends-on:** T0 (contrato de T3)

**Interfaces:** `equipeApi.listar(): EquipeDto`, `obter(id)`, `criar(r: NovoColaboradorRequest)`, `atualizar(id, r: AtualizarUsuarioRequest)`, `convidar(id)` (`POST /usuarios/{id}/convite`), `convidarNovo(r: {nome, email, perfil})` (`POST /auth/convites`), `perfis()`; `chavesEquipe.lista()`, `.item(id)`, `.perfis()`.
  - **`EquipePage`:** `PageHeader` "Equipe e acessos", subtítulo `"{n} pessoas na equipe · {c} com acesso · {p} convite(s) pendente(s)"`; ações "+ Colaborador sem acesso" (`secondary`, → `/equipe/nova`) e "+ Convidar para acessar" (`primary`, abre `ConvidarModal`). `DataTable` Colaborador (nome + e-mail; externo sem acesso: linha de apoio "vendedor externo · aparece nas viagens e repasses; não usa o sistema") · Perfil (rótulo local `ROTULO_PERFIL` em `pages/equipe/perfis.ts` — `status.ts` não tem mapa de perfil e é congelado) · Repasse ("gera · sugestão 10 %" / "—") · Último acesso (`formatarCarimbo` relativo: "hoje 09:12", "ontem 18:40", `dd/MM`) · Acesso (`StatusCell acesso`; `convite_pendente` com "expira em n dias"; `sem_acesso` com `conviteExpiraEm` passado → "convite expirado") · ação: "Editar" (→ `/equipe/{id}`) / "Convidar" (`sem_acesso`) / "Reenviar" (`convite_pendente`) → `equipeApi.convidar(id)` + toast "Convite enviado para {email}" + invalidar.
  - **`ConvidarModal`:** nome, e-mail, perfil (`Select` dos 5); envia `POST /auth/convites`; 422 `email_ja_cadastrado` no campo e-mail.
  - **`ColaboradorPage`** (`/equipe/:id` e `/equipe/nova`): `Page dirty` + `useSalvamento` + `PageHeader` (título nome, subtítulo "{perfil} · {email}", `status` = `StatusCell acesso`, `salvoEm`, ações "Fechar"/"Salvar"); campos Nome · E-mail (só na criação; edição mostra texto — `PUT` não altera e-mail) · Telefone · Perfil (`Select`) · Gera repasse (`Checkbox`/`Select` Sim/Não) · Sugestão de % (`Input` numérico, só quando gera repasse) · Situação (Ativo/Inativo; inativar pede `ConfirmModal` "Inativar {nome}? Perde o acesso na próxima requisição."); 422 `ultimo_dono` → `Alert` "A agência precisa de ao menos um Dono ativo"; 409 → `Alert` "Alguém alterou… Recarregar". Bloco lateral "O que este perfil vê" (`PerfilVe`): a partir de `equipeApi.perfis()` e do perfil selecionado, quatro linhas (Viagens · Clientes · Financeiro · Admin) com ✓/✗ derivados das chaves: Viagens: `viagem.ver` "todas" / `viagem.ver_proprias` "só as próprias"; `reserva.ver_valores` "custo e comissão"; `viagem.ver_resultado` "resultado"; Clientes: `cliente.ver`/`cliente.ver_proprios`; `cliente.ver_documento` "documentos"; Financeiro: `financeiro.conciliar` "conciliação"; `repasse.ver_todos` "repasses" / senão (externo) "o próprio repasse"; Admin: `usuario.gerenciar` "usuários"; `auditoria.ver` "auditoria". Botão "Convidar para acessar"/"Reenviar convite" no header quando aplicável.
  - Criação: `POST /usuarios` → navega para `/equipe/{id}` com toast.

- [ ] **Step 1: Testes** — `equipe.test.ts`. `EquipePage.test.tsx` (stub do `EquipeDto` do protótipo — 5 pessoas): subtítulo "5 pessoas na equipe · 4 com acesso · 1 convite pendente"; linha de Marcos mostra "sem acesso" e botão "Convidar"; Bruno "convite pendente" + "Reenviar" → `POST /usuarios/{bruno}/convite` + toast; "Editar" navega; "+ Convidar para acessar" abre modal e envia `POST /auth/convites`. `ColaboradorPage.test.tsx`: carrega, edita nome → dirty → Ctrl+S/Salvar → `PUT` com `versao` → "Salvo às"; 422 `ultimo_dono` mostra o `Alert`; `/equipe/nova` envia `POST /usuarios`; `PerfilVe` para `vendedor_externo` mostra "só as próprias" ✓ e "resultado" ✗; trocar o `Select` de perfil para "agente" atualiza o bloco. `ConvidarModal.test.tsx`: 422 no e-mail.
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar tudo.** Commit sugerido: `feat(equipe): team list with access states, invite/resend, collaborator page with profile matrix and last-owner guard feedback`

---

### Task 10 (front): Auditoria

**Files:**
- Modify: `frontend/src/api/auditoria.ts`, `frontend/src/api/auditoria.test.ts` (criar se não existir)
- Create: `frontend/src/components/Auditoria/{LinhaEvento.tsx,LinhaEvento.test.tsx,DetalhesEventoModal.tsx,DetalhesEventoModal.test.tsx,Auditoria.module.css}`, `frontend/src/components/auditoria.ts` (barrel)
- Create: `frontend/src/pages/auditoria/{AuditoriaPage.tsx,AuditoriaPage.test.tsx,Auditoria.module.css,FiltrosAuditoria.tsx}`; Modify: `frontend/src/pages/auditoria/rotas.tsx`

**Depends-on:** T0 (contrato de T4)

**Interfaces:** `auditoriaApi.listar(f: FiltroAuditoria): Promise<AuditoriaDto>`; `urlCsv(f)`; `chavesAuditoria.lista(f)`; `EventoAuditoriaDto` + `viagemId?`, `codigoViagem?`. `LinhaEvento({ evento, onDetalhes })` renderiza `"{usuarioNome} — {titulo}"`, subtítulo (`subtitulo` · `motivo: "…"` · link `viagem {codigoViagem}` → `/viagens/{viagemId}`), carimbo relativo ("hoje 16:40", "ontem 15:20", `dd/MM HH:mm`), ícone por classe: `acao = 'ACESSO'` → `Eye`, tabela `movimento_financeiro`/`repasse`/`fechamento_periodo` → `Coins`, título contém "cancel" → `XCircle`, senão `Pencil`; "Ver detalhes" só quando `Object.keys(alteracoes).length > 0`.
  - **`DetalhesEventoModal`:** tabela Campo · De · Para (valores `JSON` → texto: número `formatarDinheiro` quando o campo está numa lista local de campos monetários, `true/false` → Sim/Não, `null` → "—", data ISO → `formatarData`).
  - **`AuditoriaPage`:** `PageHeader` "Auditoria", subtítulo "Toda alteração em viagem, reserva, recebimento, repasse, usuário e cliente · retenção 24 meses" (texto fixo); ação "Exportar CSV" (`baixar(urlCsv(filtros), "auditoria.csv")`). `FiltrosAuditoria`: `Chip` "Quem: todos" + um por `usuarios`; `Chip` "O quê: tudo · Valores de reserva · Recebimentos · Cancelamentos · Acesso a documento"; `DateInput` de/até. Lista de `LinhaEvento`; rodapé `"1–{n} de {total}"` + botão "Mais antigas →" (`useInfiniteQuery` com `antesDe = proximoAntesDe`; some quando `null`). `EmptyState` "Nenhum evento no período". Erro → `Alert`.

- [ ] **Step 1: Testes** — `auditoria.test.ts` (querystring com/sem filtros; `antesDo` codificado). `LinhaEvento.test.tsx`: título prefixado pelo usuário; link da viagem; "Ver detalhes" ausente sem alterações; ícone de acesso para `ACESSO`. `DetalhesEventoModal.test.tsx`: `valor_comissao {de 1000, para 1100}` → "R$ 1.000,00" / "R$ 1.100,00"; booleano → "Sim"/"Não". `AuditoriaPage.test.tsx` (stub com 7 eventos do protótipo, `total 412`, `proximoAntesDe` preenchido): renderiza "Guilherme — Valores da reserva alterados", "Ana Paula — Visualizou o passaporte de Lúcia Mendes", "1–7 de 412"; "Mais antigas →" pede `?antesDe=…` e acrescenta; chip "Recebimentos" → `?oque=recebimentos`; chip "Ana Paula" → `?usuarioId=`; datas → `?de=&ate=`; "Exportar CSV" chama `baixar` com os filtros ativos; `proximoAntesDe null` esconde o botão.
- [ ] **Step 2: Rodar para ver falhar.**
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Rodar tudo.** Commit sugerido: `feat(auditoria): agency-wide audit page with who/what/date filters, LGPD access events, details diff modal, cursor paging and CSV`

---

### Task 11 (front): E2E `operacao.spec.ts` + re-medição do tempo

**Files:**
- Create: `frontend/e2e/operacao.spec.ts`, `frontend/e2e/operacao.ts`

**Depends-on:** T1–T10 commitadas; API de dev de pé com `seed-dev.sql` (T0) aplicado; Docker.

- [ ] **Step 1: Escrever** (padrão de `financeiro.spec.ts`: `loginUi(page)` com `DEV_USER` (dono); helpers em `operacao.ts` chamando a API por `request` contra `E2E_API`):
```ts
test("agenda mostra pendência atrasada do seed, badge e cria pendência solta", …)   // /agenda: seção "Atrasadas" contém "Cobrar comissão CVC"; sidebar tem badge numérico em Agenda; "+ Nova pendência" → título "E2E agenda" data hoje → aparece em "Hoje"; concluir → some
test("relatórios do ano carregam KPIs e CSV responde", …)   // /relatorios: card "Venda no ano" com "R$"; 12 rótulos de mês; request.get(`${E2E_API}/relatorios/csv?ano=${ano}`) com o cookie da página → 200 e content-type text/csv
test("equipe lista estados e reenvia convite", …)   // /equipe: "Marcos Castro" com "sem acesso", "Bruno Sales" com "convite pendente"; clicar "Reenviar" na linha do Bruno → toast "Convite enviado"; abrir "Editar" do Marcos → /equipe/{id} mostra "O que este perfil vê" com "só as próprias"
test("auditoria lista o evento gerado e filtra por categoria", …)   // criar viagem via API (`criarViagemViaApi`), cancelar reserva via API com motivo; /auditoria: chip "Cancelamentos" → linha "Reserva cancelada" com link da viagem; "Ver detalhes" abre modal com "status"
```
- [ ] **Step 2: Rodar** `npx playwright test e2e/operacao.spec.ts` (1280 e 1440) → 8/8. **Re-medir** `npx playwright test e2e/nova-viagem.spec.ts` e anotar `tempo-4-reservas-s` nos dois viewports (C14).
- [ ] **Step 3: Rodar tudo** (`lint`, `typecheck`, `test`, `build`; `styleguide.spec.ts` intocado). Commit sugerido: `test(e2e): operacao spec covering agenda, relatorios, equipe and auditoria against dev stack`. Reportar os tempos no relatório.

---

### Task 12 (docs, root): fechamento da Fase 3.6 e checklist humano

**Files:**
- Modify: `docs/BACKLOG.md` (tabela de fases; item 6 concluído; "Fechadas em 3.6": badge de comissões atrasadas, Contador em repasses, RLS `log_acesso`, índices redundantes, expurgo de anexos, `ResumoClienteDto`? **não** (segue deferida); "Deferidas da 3.6": paginação dos blocos da Agenda, aniversariantes na Agenda, pendência derivada concluída nunca reabre, `Total` da auditoria não desconta projeção, `limit 200` da timeline, tempo humano §7 e piloto §12 se pendentes), `docs/autorizacao-por-operacao.md` (linhas da tabela de permissões deste plano; linha 38 do Contador), `docs/superpowers/plans/2026-09-08-fase-3-master.md` (linha 3.6 concluída; critério de fechamento com o que ficou pendente), `CLAUDE.md` (linha "Estado": 3.6 ✓ com contagens, migrations 0001–0016, tempos), `regras-e-escopo-v2.md` (rulings R6/R7/R9/R13 como notas "Ruling 3.6" nos §4.2, §7.1, §9 — mesmo padrão dos rulings anteriores)
- Create: `docs/relatorios-formulas.md` (cópia da seção "Fórmulas" + exemplo numérico do teste de T2)
- Memória: atualizar `meridiano-estado-2026-09-08.md` (3.6 mergeada, hashes) e `MEMORY.md`

**Depends-on:** T11

- [ ] **Step 1:** Coletar contagens finais (`dotnet test` resumo; `npx vitest run --reporter=dot | tail -5`), hashes de HEAD dos dois repos, tempos de T11.
- [ ] **Step 2:** Editar os arquivos acima. Checklist humano (registrar como pendente se não houver dado): (a) **Teste de UX §7** — alguém que conhece agência e não viu o design executa o roteiro (criar viagem para Carlos Mendes → reserva CVC → informar pagamento → ver quanto deixa → segunda reserva → corrigir a primeira → sair sem salvar); registrar tempo humano e "onde eu clico?"; (b) **Piloto §12** — três viagens reais da planilha lançadas; comparar `receita_prevista`/`valor_esperado_operadora` da tela da viagem e do Relatório com a planilha; sem isso a Fase 3 **não fecha**.
- [ ] **Step 3:** Commit root `docs: fase 3.6 done — agenda, relatorios, equipe, auditoria, jobs; backlog, authorization table, formulas, state line, rulings`. Merge das branches `feat/fase-3-6` em `main` nos dois repos (controlador, após revisão final), atualizar memória com os hashes.

---

## Self-review (feito ao escrever)

- **Cobertura do mestre (linha 3.6):** Agenda tabs ✓ (T1/T7, R1), Relatórios com fórmulas + competência×caixa×previsto + `tipos_servico[]` + caixa sem `vw_resultado_viagem` ✓ (T2, R6/R7), CSV por perfil ✓ (T2/T4, R8), Equipe estados + último dono ✓ (T3, R10), Auditoria contextual por perfil ✓ (T4, R11), RLS `log_acesso` sem quebrar inserção ✓ (T0, R12), jobs `pendencias_derivadas`/`resumo_diario_email`/`expurgo_auditoria`/`expurgo_anexos` ✓ (T5/T6), `aniversarios` ✓ como endpoint (R5, sem job — decisão explícita), `GET /agenda`, `/relatorios/resumo`, `/relatorios/*/csv`, `/auditoria`, `/clientes/aniversarios` ✓, infra Resend já existia ✓, telas 18–22 ✓ (T7–T10), teste de UX §7 ✓ como checklist humano (R17). `GET /relatorios/receita-mensal` do mestre foi absorvido em `resumo.receitaPorMes` (um endpoint).
- **Deferidas fechadas:** badge de comissões atrasadas (R4), Contador 403 em repasses (R9), RLS `log_acesso`, índices redundantes, expurgo de anexos, `/agenda` sem guarda (R16).
- **Placeholders:** nenhum "TBD"; cada task tem testes nomeados com asserções concretas e SQL/regras suficientes.
- **Consistência de tipos:** `ResponsavelDto` definido em `AgendaDtos` e reutilizado por `RelatorioResumoDto.Vendedores` e `AuditoriaDto.Usuarios` (T2/T4 importam `Modules.Agenda` — namespace existe desde T0); `PendenciaDto` de `Modules.Pendencias`; `EventoAuditoriaDto` estendido com parâmetros opcionais (chamadas existentes compilam); `ColaboradorDto` substitui `UsuarioDto` (T3 ajusta `UsuariosTests`/`ConviteTests`); front `chavesAgenda.badges()` usado por `Sidebar` (T7) e `fontePendencias` (T7).
- **Ondas × arquivos:** T1 e T5 compartilham `AgendaService` → ondas distintas; T3 é a única a tocar `Auth/`; `JobsExtensions.cs` só em T0; `Endpoints.cs` só em T0; `components/Pendencias` só em T7; `api/auditoria.ts` só em T10.
