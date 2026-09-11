# Meridiano — Backlog e estado do projeto

Última revisão: 2026-09-11 (Fase 4 em andamento). Fonte de verdade para "o que já foi feito" e "o que falta". Backlog de configuração do harness fica em `.claude/SETUP-BACKLOG.md`.

## Estado por fase

| Fase | Entrega | Estado | Onde |
|---|---|---|---|
| 1 — Especificação | `regras-e-escopo-v2.md`, `schema-agencia-v2.sql`, análise arquitetural, 50 decisões registradas | Concluída (2026-09-07/08) | raiz, `docs/analise-arquitetural-v1.md` |
| 2 — Esqueleto | Solution .NET 10, migrations DbUp 0001–0011, RLS, auth própria, perfis/permissões, ProblemDetails, jobs CLI, CI, endpoint vertical de usuários | Concluída (2026-09-07). 13 testes de domínio + 26 de API, verdes | `backend/` (repo `meridiano-api`), plano em `docs/superpowers/plans/2026-09-07-fase-2-esqueleto.md` |
| Design | Design system v3, contrato de implementação, protótipo clicável v1 com 22 telas, tokens CSS | **Congelado** em 2026-09-08 após 5 revisões externas (tag `design-v1-freeze` no root) | `docs/design-system-contrato.md`, `docs/design/prototipo-v1.html` + `prototipo-v1/*.png`, `frontend/src/styles/tokens.css` |
| 3 — Front + módulos | React/Vite/TS servido pela API; módulos viagem/reserva, pessoas, fornecedores, financeiro, pendências, despesas, repasses, fechamento, relatórios | **Em andamento.** Plano-mestre `docs/superpowers/plans/2026-09-08-fase-3-master.md` (7 subplanos, 3.0–3.6, revisado 2026-09-08 após review externa; 5 decisões pendentes D1–D5 no mestre); 3.0 **concluída** (2026-09-08) em `2026-09-08-fase-3-0-hardening.md` (7 tasks, 3 ondas), migrations 0001–0012; 3.1 **concluída** (2026-09-08) em `2026-09-08-fase-3-1-scaffold.md` (12 tasks, 7 ondas), migration 0013, D2/D4 aplicadas; 3.2 **concluída** (2026-09-09) em `2026-09-09-fase-3-2-nova-viagem.md` (10 tasks, 6 ondas), 106 testes API + 21 domínio backend, 123 testes Vitest + Playwright e2e 4/4 front; tempo automatizado (E2E, 4 reservas) 6,0 s @1280 / 6,4 s @1440 (meta ≤ 300 s); 3.3 **concluída** (2026-09-09) em `2026-09-09-fase-3-3-viagens-reservas.md` (16 tasks, 5 ondas), migration 0014, 179 testes API + 22 domínio backend, 237 testes Vitest + Playwright e2e 8/8 front; tempo automatizado (E2E, 4 reservas) 6,0 s @1280 / 7,3 s @1440 (3.2: 6,0 / 6,4); 3.4 e 3.5 **concluídas** (2026-09-10) **em paralelo** sob o contrato `2026-09-09-fase-3-4-3-5-contrato.md` (Task 0 serial e compartilhada) — `2026-09-09-fase-3-4-cadastros.md` (11 tasks, 5 ondas) e `2026-09-09-fase-3-5-financeiro.md` (12 tasks, 4 ondas), migration 0015, 226 testes API + 26 domínio backend, 402 testes Vitest (107 arquivos) + Playwright `cadastros.spec.ts` 4/4 e `financeiro.spec.ts` 4/4 (1280 e 1440), styleguide intocado; tempo automatizado (E2E, 4 reservas) re-medido: 5,8 s @1280 / 6,3 s @1440 (3.3: 6,0 / 7,3); 3.6 **concluída** (2026-09-11) em `2026-09-11-fase-3-6-agenda-relatorios-equipe-auditoria.md` (13 tasks, 5 ondas), migration 0016, 257 testes API + 30 domínio backend, 486 testes Vitest (121 arquivos) + Playwright `operacao.spec.ts` 8/8 (1280 e 1440) e `nova-viagem.spec.ts` 4/4, styleguide intocado; tempo automatizado (E2E, 4 reservas) re-medido: 6,2 s @1280 / 7,7 s @1440 (3.4/3.5: 5,8 / 6,3); branches `feat/fase-3-6` (backend HEAD `04dfba7`, 10 commits sobre `16d9c65`; frontend HEAD `843667a`, 11 commits sobre `f5a4884`; **mergeadas em `main` 2026-09-11** (backend `b949e97`, frontend `f6f0ceb`)). **Próximo:** merge + Fase 4 (piloto). Código da Fase 3 completo; a fase só **fecha** com o checklist humano abaixo | `frontend/` (repo `meridiano-app`), `backend/src/Meridiano.Api/Modules/` |
| 4 — Piloto | Deploy Azure Container Apps + Supabase, três viagens reais lançadas à mão (importador é v1.1), medir tempo de lançamento | **Em andamento** (2026-09-11). Plano `docs/superpowers/plans/2026-09-11-fase-4-piloto.md` (7 tasks, 5 ondas). Onda 0 (código) concluída em `feat/fase-4` do backend (HEAD `b57ab27`, 5 commits sobre `a163992`; **sem merge/push**): migration 0017 (fecha PostgREST do Supabase), `scripts/bootstrap-agencia.sql`, `BootstrapTests` (2), `ci.yml` com push GHCR + `az containerapp update`, `backup.yml`; 260 testes API + 30 domínio. Ruling do usuário: **piloto local antes da nuvem** — feito: imagem integrada, bootstrap, jobs e drill de backup/restore no compose (achados em "Achados do piloto local"). Runbook `docs/deploy.md` escrito, não executado. **Mergeada em `main` = `develop` (`b57ab27`) e pushada 2026-09-11**; CI run 34646141316: `build-test` ✓, `docker` build + push GHCR ✓, `azure/login` ✗ (sem `AZURE_CREDENTIALS` até T3.8 — esperado, fica vermelho até lá). Pendente: T5 (§12/§7 com a planilha, stack local no ar), T3 (nuvem), T4 (smoke em produção), T6 (fechamento) | `docs/deploy.md`, `docs/piloto/`, `backend/scripts/bootstrap-agencia.sql` |

Tempo humano (teste de UX §7, subplanos 3.2 a 3.6): pendente.

### Checklist humano para fechar a Fase 3 (R17 de 3.6) — pendente

- (a) **Teste de UX §7** — alguém que conhece agência e não viu o design executa o roteiro: criar viagem para Carlos Mendes → reserva CVC → informar pagamento → ver quanto deixa → segunda reserva → corrigir a primeira → sair sem salvar. Registrar o tempo humano (linha separada do E2E, aqui) e cada "onde eu clico?".
- (b) **Piloto §12** — três viagens reais da planilha lançadas; comparar `receita_prevista` / `valor_esperado_operadora` da tela da viagem **e** do Relatório (`docs/relatorios-formulas.md`) com a planilha. Sem isso a Fase 3 **não fecha** e a Fase 4 não começa; não declarar validado.
- (c) ~~**TZ de produção**~~ — **feito 2026-09-11**: `ENV TZ=America/Sao_Paulo PGTZ=America/Sao_Paulo` no Dockerfile (PGTZ vira `Timezone` da sessão Npgsql sem tocar na connection string; teste `InfraTests.PGTZ_define_timezone_da_sessao`).

## Fase 3 — subplanos (detalhe no plano-mestre)

Cada item vira um plano próprio quando os de que depende fecham:

0. **Hardening** (só backend, **concluído 2026-09-08**) — revalidação de sessão contra o banco, token de convite/reset consumido atomicamente, links `/definir-senha` × `/redefinir-senha`, guarda de último dono com lock, tradução de `PostgresException`, lock de job, helpers de lock de viagem/competência e validação de referência por tenant, migration 0012 (views `security_invoker`, `vw_viagem_titular` corrigida, `vw_fase_viagem` inalterada — cancelada com `comissao_mantida` segue "a receber" por spec §4.2, fixado em teste —, índices únicos parciais de repasse/recorrência/titular, FK do log documental `set null`, auditoria de `fechamento_periodo`), `JobRunner` com `pg_try_advisory_lock` por nome (sem índice em `job_execucao`), tabela de autorização por operação (`docs/autorizacao-por-operacao.md`). Fechou as pendências da Fase 2 listadas em "Fechadas em 3.0" abaixo.
1. **Scaffold** (**concluído 2026-09-08**) — Vite + React + TS no `frontend/`, tokens já existentes, componentes obrigatórios do contrato (§3 de `design-system-contrato.md`: Button, Field/Input, Select, Chip, Tabs, Subnav, Sidebar, Table, Dialog, Toast, EmptyState, Skeleton), roteamento, cliente HTTP com ProblemDetails (422 no campo, 409, 403), sessão por cookie, build em `wwwroot/`. `UsuarioService` movido de `AddAuth` para `AddModules` (fechou pendência da Fase 2); `/auth/me` retorna `permissoes[]`; `GET /auth/tokens/{token}` criado; migration `0013_localizar_usuario_por_token_dados.sql`; Dockerfile em layout irmão + CI do backend construindo a imagem integrada com dois checkouts (D4); breakpoints 700/1024/1280/1366/1440 no lint de tokens (D2); baseline visual do Playwright (`e2e/styleguide.spec.ts-snapshots/`, win32+linux) é a baseline de regressão da `/styleguide`.
2. **Nova viagem** (risco número um, **concluído 2026-09-09**) — endpoint transacional viagem + passageiros + reservas + repasse + pendências automáticas, salvar parcial, adicionar reserva depois, pré-preenchimento, criação inline de pessoa (fornecedor: D1), teclado, aviso de viagem semelhante e reserva duplicada, vigência da regra de pagamento, teste E2E cronometrado. Backend `feat/fase-3-2-nova-viagem` (HEAD `2dd5c37`, base `66c3fd4`): módulos Pessoas, Fornecedores, Agencia, Admin, Viagens, `Meridiano.Domain/Financeiro/CalculoReserva.cs`; 106 testes API + 21 domínio. Frontend `feat/fase-3-2-nova-viagem` (HEAD `265945c`, base `b1ec8bc`): 123 testes Vitest, Playwright styleguide 18/18 (win32+linux), `e2e/nova-viagem.spec.ts` 4/4. Tempo automatizado (4 reservas): 6,0 s @1280 / 6,4 s @1440 (meta ≤ 300 s); tempo humano pendente (teste de UX §7). Fechou as pendências listadas em "Fechadas em 3.2" abaixo.
3. **Viagens e reservas** — `2026-09-09-fase-3-3-viagens-reservas.md` (**concluído 2026-09-09**: 16 tasks, 5 ondas) — lista com filtros recolhidos e `vw_fase_viagem`; detalhe com tabs Resumo · Reservas · Financeiro · Pendências · Documentos · Timeline (protótipo, R3); editar reserva pelo `PUT /viagens/{id}` existente (R1: `PUT /reservas/{id}` não foi criado); remarcação (`reserva_alteracao`, reabre pendências); cancelamento de viagem/reserva com motivo/desfecho/crédito; consumo de crédito uma única vez (`reserva_uso_id`); NFSe por reserva; serviços operacionais; transferência de agente (`agente_id`, `ViagemTransferir`); busca global; anexos com `log_acesso_documento`. Backend `feat/fase-3-3-viagens-reservas` (HEAD `9edb433`, base `64ef818`, 15 commits): migration 0014; 179 testes API + 22 domínio. Frontend `feat/fase-3-3-viagens-reservas` (HEAD `f488107`, base `e2f0b79`, 17 commits): 237 testes Vitest, Playwright styleguide 24/24 (win32+linux), `e2e/viagens.spec.ts` + `e2e/nova-viagem.spec.ts` 8/8 (1280 e 1440). Tempo automatizado (4 reservas) re-medido: 6,0 s @1280 / 7,3 s @1440 (3.2: 6,0 / 6,4). Tempo humano (teste de UX §7): pendente. Fechou as pendências listadas em "Fechadas em 3.3" abaixo.
4. **Cadastros** — `2026-09-09-fase-3-4-cadastros.md` (**concluído 2026-09-10**: 11 tasks, 5 ondas) — Clientes/Pessoa em página própria com tabs Dados · Documentos · Pendências · Viagens · Atendimentos; lista com filtros recolhidos e contadores; Grupos (família/empresa, vincular/desvincular); Fornecedores com tabs Dados · Financeiro · Reservas e regra de pagamento **versionada** por `vigente_desde` (previsões já gravadas intocadas, teste de invariante). Atendimentos = tabela `interacao` (R5); documentos com `log_acesso_documento` por linha lida; `ClienteVerProprios` em lista, detalhe, viagens, documentos, atendimentos, pendências e anexos. Backend `feat/fase-3-4-3-5` (base `9edb433`, HEAD `aaf784d`, compartilhada com 3.5; **mergeada em main 2026-09-11**, merge `16d9c65`): migration 0015. Frontend `feat/fase-3-4-3-5` (base `f488107`, HEAD `cf450af`; **mergeada em main 2026-09-11**, merge `f5a4884`): `e2e/cadastros.spec.ts` 4/4. Fechou as pendências listadas em "Fechadas em 3.4/3.5" abaixo.
5. **Financeiro** — `2026-09-09-fase-3-5-financeiro.md` (**concluído 2026-09-10**: 12 tasks, 4 ondas) — Conciliação com os 5 tipos de movimento e KPIs, encerrar divergência com motivo, lote atômico de recebimento (decisão 48), Repasses (`bloqueado → a_pagar → pago`, valor editável até pagar, pagamento em lote por vendedor com data), Despesas com recorrência idempotente (`ux_despesa_sucessora`) e job `recorrencia_despesas`, Fechamento por competência com lock e reabertura auditada (`delete` + `aud_fechamento`). `X-Motivo` migrou para header. Contador enxerga o módulo (C7) mas recebia 403 em `GET /repasses` (fechado em 3.6, R9). Sem migration própria (0015 é da Task 0 compartilhada). `e2e/financeiro.spec.ts` 4/4. Fechou as pendências listadas em "Fechadas em 3.4/3.5" abaixo.
6. **Agenda, Relatórios, Equipe, Auditoria, jobs** — `2026-09-11-fase-3-6-agenda-relatorios-equipe-auditoria.md` (**concluído 2026-09-11**: 13 tasks, 5 ondas) — Agenda com tabs Pendências (Atrasadas · Hoje · Esta semana) · Embarques e retornos · Documentos vencendo · Créditos vencendo (R1, protótipo vence o mestre; `vw_agenda` não usada), pendência solta (`POST /pendencias`, R3), badges da sidebar (`GET /agenda/badges`: agenda/financeiro/clientes, R4); Relatórios do ano com três eixos separados (competência × caixa × despesas, R6/R7, fórmulas em `docs/relatorios-formulas.md`), teto MEI, receita por mês, nacional × internacional, ranking de fornecedores, serviços vendidos, CSV por reserva (R8); Equipe com `ColaboradorDto` e estado de acesso derivado, criar sem acesso, convite/reenvio, `GET /usuarios/perfis` (R10); Auditoria geral unindo `auditoria` + `log_acesso_documento` (LGPD), filtros, cursor `antesDe`, projeção `verDocumento`, CSV (R11); RLS em `log_acesso` (R12, migration 0016); jobs `pendencias_derivadas` (R13), `resumo_diario_email` (R14), `expurgo_auditoria`/`expurgo_anexos` (R15); aniversários como endpoint, sem job (R5); Contador lê `GET /repasses` (R9); `/agenda` protegida (R16); E2E `operacao.spec.ts`. Backend `feat/fase-3-6` (base `16d9c65`, HEAD `04dfba7`, 10 commits): migration 0016; 257 testes API + 30 domínio. Frontend `feat/fase-3-6` (base `f5a4884`, HEAD `843667a`, 11 commits): 486 testes Vitest (121 arquivos), Playwright `operacao.spec.ts` 8/8 (1280 e 1440), `nova-viagem.spec.ts` 4/4, styleguide intocado. Tempo automatizado (4 reservas) re-medido: 6,2 s @1280 / 7,7 s @1440 (3.4/3.5: 5,8 / 6,3). Merge em `main`: **pendente** (controlador). Tempo humano (UX §7) e piloto §12: pendentes (checklist acima). Fechou as pendências listadas em "Fechadas em 3.6" abaixo.

## Pendências abertas

### De especificação (regras-e-escopo-v2 §12)
- Contador: base e regime da receita bruta do MEI (§4.9).
- Decisão 17: `vencimento_fornecedor` (data-limite da operadora) fora até o usuário pedir.
- Piloto: validar fórmulas de §4.2 e a RAV (decisão 49) com três viagens reais da planilha **antes** de fechar a Fase 3.

### Fechadas em 3.0 (2026-09-08)
- Sessão: perfil lido do cookie, sem revalidação de `ativo`/`perfil` por request (inativado mantinha acesso até 12h) — `Auth/ValidacaoSessao.cs` (`OnValidatePrincipal`) revalida a cada request.
- `ConviteService.DefinirSenhaAsync`: lookup do token fora da transação e `UPDATE` sem recheck (token consumível duas vezes); link de reset apontava `/definir-senha` — consumo atômico + `/redefinir-senha` separado.
- `TratadorDeExcecoes`: `PostgresException` (23505/23503/23514/42501) caía em 500 genérico — mapeado para 409 `duplicado` / 422 `referencia_invalida` / 422 `regra_banco` / 403 `sem_acesso`.
- Views sem `security_invoker`; owner das migrations é superuser no compose/Testcontainers, então leitura por view ignorava RLS; nenhum teste tocava `vw_*` — migration `0012_hardening.sql` fixa `security_invoker=on` nas 11 views.
- Sem constraint de titular único; `repasse_unico` permitia N por viagem e bloqueava recriar após soft delete; `vw_resultado_viagem` duplicava linhas com 2 repasses; `ix_despesa_recorrencia` não único; `fechamento_periodo` sem `id`/auditoria; FK de `log_acesso_documento` impedia expurgo — corrigido em `0012_hardening.sql`.
- Guarda de "último Dono" não serializava alterações concorrentes — `UsuarioService` ganhou lock advisory por agência.
- `ExecutarJob` sem exclusão mútua entre execuções — `JobRunner` usa `pg_try_advisory_lock` (Pooling=false na conexão do lock).

### Deferidas da 3.0
- `UseStaticFiles` antes de `UseAutenticacao` em 3.1 T06 (senão uma query de sessão por asset).
- `job_execucao.detalhe` grava `ex.ToString()` (DETAIL do Postgres pode conter dado pessoal; LGPD). Npgsql redige o DETAIL por padrão; nunca ativar `Include Error Detail=true` na connection string de produção.
- Índice de titular não é deferrable (trocar titular = 2 statements).
- `ValidacaoSessao`: `Cookies.Delete` sem `CookieOptions` do esquema e sem `CancellationToken`.
- Troca de titular = 2 statements dentro do lock da viagem (índice não deferrable).

### Fechadas em 3.2 (2026-09-09)
- `Guardas.ReferenciaAsync` em `Usuario`/`Fornecedor` não filtrava `ativo` — parâmetro `exigirAtivo` adicionado.
- `DateOnly` sem type map do Dapper — `SqlMapper.AddTypeMap` adicionado em `Api/Data/SessaoExtensions.cs`.
- Ruling 422 vs 404: `Guardas.TravarViagemAsync` (e demais referências inexistentes/inativas/de outro tenant) devolvem 422 `nao_encontrado` na v1, não 404; endpoints não traduzem. Documentado em `docs/autorizacao-por-operacao.md`.
- `MoneyInput`: clamp de negativo movido para `mudar` (não emite mais `-5`/`-50` intermediário durante a digitação).
- Receita de formulário padrão (react-hook-form + `useSalvamento` + `Page` dirty) concretizada em `useNovaViagem`.

### Deferidas da 3.1
- `App.test.tsx` não assegura a chamada de `instalarAtalhos()` no `App` (setup de teste instala por conta própria).
- `destinoSeguro` deve rejeitar `/\` e whitespace no início do destino (`new URL(v, origin).origin` para validar em vez de regex).
- `sair()` deve limpar o cache do `queryClient` em `finally`, não só no caminho feliz.
- Vitest sem CSS carregado no jsdom (`test.css`) impede asserção de visibilidade por estilo em alguns testes.
- `ConfirmModal` não devolve foco ao elemento que abriu o modal (`anterior` é capturado depois do `autoFocus` do conteúdo).
- `Tooltip` não fecha com Escape.
- `ToastHost` sem classe visual distinta para toast de sucesso vs. undo.
- `e2e/login.spec.ts` só roda com a API de pé e seed de dados (`backend/scripts/seed-dev.sql` ainda por criar); não entra no CI.
- `Field.htmlFor` prometido no contrato e ainda ausente.

### Deferidas da 3.2
Backend:
- Path `ativo` omitido em `GET /fornecedores` sem teste.
- Invariante a documentar: toda escrita em reserva renova o xmin da viagem (sustenta a ordem de locks).
- `ix_reserva_fornecedor_loc` não cobre `lower(trim())`.
- 5 códigos de validação sem teste dedicado.

Frontend:
- Erros locais de validação persistem até o próximo save.
- Sem guard de resposta stale em semelhante/duplicadas.
- Esc no combobox de passageiros também recolhe o card.
- `NovaViagemPage.tsx` 194 linhas úteis (brief pedia ≤200; limite ESLint 350 ok) — `useNovaViagem.ts` 308, perto do teto.
- Alert de erro de carga sem "Tentar de novo"; Ctrl+S durante recarregar pisca spinner.
- `Field`: tooltip dentro do `<label>` polui accessible name (componente da 3.1).
- `SecondaryDetails` não é componente próprio; `aria-expanded` sem `aria-controls`.
- `somarReservas` duplica null-coalescing de `paraValoresReserva`.
- E2E: `getByLabel` precisou de `exact: true` (tooltip com aria-label "fornecedor" colide).
- Front envia `repasseValor: null` no PUT quando o usuário não vê resultado (backend ignora sem `ViagemVerResultado`, ver `ViagensService.cs`); omitir o campo no front por defesa em profundidade.
- Cards de reserva sem id usam key por índice (`nova-${i}`): remover do meio pode trocar o nó DOM/foco entre reservas não salvas.
- "Salvar e sair" com erro de validação local só para o spinner do modal; erros ficam na página atrás do modal.

### Fechadas em 3.3 (2026-09-09)
- `ilike '%q%'` sem escape de `%`/`_` em busca de clientes/fornecedores/global — escape aplicado (R8).
- PUT podia ressuscitar reserva cancelada — `ReservaGravacao.AtualizarAsync` agora lança 422 `reserva_cancelada`; front omite canceladas do `reservas[]` (R2).
- `GET /viagens/semelhantes` sem `excetoViagemId` — passa a rodar também em edição.
- `GET /reservas/duplicada` sem escopo por vendedor — agora filtra por `vendedor_id = usuario_id` sem `ViagemVer`.
- PUT que limpa `dataIda`/`dataVolta` deixava pendências automáticas órfãs — `GerarPendenciasAsync` cancela órfãs (R14).
- `sem_permissao_vendedor` respondia 422 — migrado para o padrão geral 403 `sem_permissao`.
- Valor de repasse pago ignorado silenciosamente no PUT — 422 `repasse_pago` (D5 aplicada).
- `paraRequest` reenviava `status: "cancelada"` no PUT (dava 422 `status_invalido`) — front omite reservas canceladas do lote (R2).
- Rota-guard por permissão só escondia item de menu — `RotaProtegida` bloqueia `/viagens*`, `/auditoria`, `/equipe`, `/relatorios`, `/financeiro*` (R15).

### Deferidas da 3.3
Backend:
- `UrlParaBaixar`/`Sanitizar` de anexo aceita `.`/`..`; truncagem 255 em UTF-16 pode partir surrogate pair.
- Limite de 25 MB em anexos é só declaratório (URL assinada não vincula `Content-Length`); objeto do storage só some no job `expurgo_anexos` (existe desde 3.6) — considerar regra de tamanho no bucket ou HEAD após confirmar.
- Requisição abortada pelo cliente vira 500 + log Error (`OperationCanceledException`) em `ViagensLista`/`ViagemLeitura`.
- Rate limit de login (10/min/IP) aperta a suíte E2E.
- `UsuarioAtual u` não usado nas escritas de `ServicosService`/`CriarNaViagemAsync` (contrato do plano); query extra de `agente_id` antes do lock em `CriarNaViagemAsync`.
- `q` da lista de viagens sem mínimo de caracteres; join de fornecedor na busca sem `agencia_id`.
- `BuscaEndpoints` importa `Modules.Viagens` para `SemVisibilidade` (acoplamento); sem teste do branch `ViagemVer` sem `ClienteVer`; sem teste positivo de `ordem=venda` com `ReservaVerValores`.
- `DELETE` repetido em anexo já excluído devolve 422; lock da viagem antes da checagem do uploader em `confirmar`; `enviado_por` nullable no schema.
- `mudouDatas` considera "veio data no payload", não "mudou de fato"; `Protocolo()` morto em `ArmazenamentoS3`; joins de leitura sem `agencia_id`/`excluido_em` explícito (convenção, RLS cobre); perf: join com `vw_reserva_financeiro` no detalhe da viagem — medir no piloto.
- Timeline só renderiza com `auditoria.ver` (Agente não tem — revisar no piloto).
- Quatro variantes do 403 `sem_permissao` (`ViagensEndpoints`/`ViagensOperacoesEndpoints`/`Pendencias`/`Servicos`/`Anexos`) — unificar em `SemPermissaoException`.
- `GET /viagens/{id}/auditoria` usa `limit 200` sem cursor nem sinal de truncagem.
- `ViagensLista` avalia a CTE duas vezes e `vw_resultado_viagem` impede pushdown — medir quando a base crescer.
- `CodigoViagemOrigem` em créditos não escopado por visibilidade.
- `CreditoRow.Status` lido e não usado.
- Cobertura cross-tenant por endpoint fina (só Anexos cria 2ª agência).
- Teste de migration 0014 é textual (backfill coberto por review).

Frontend:
- `DataTable`: linha só ativa com Enter, não Space; `FaixaResumo` usa key por label.
- `listar()` com filtro vazio gera `/viagens?` (querystring vazia); sem teste dedicado de "semelhantes" durante edição.
- `useNovaViagem.ts` 347 linhas e `ViagensPage.tsx` 206 linhas (perto do teto de 350).
- Combobox com opção ativa destacada só por cor (padrão pré-existente de `PassageirosField`) — ticket transversal de acessibilidade.
- Modais de operação: `Motivo`/`Descricao`/mapas de rótulo duplicados entre componentes; `NfseModal`/`RemarcarModal` seedam estado a partir de props só no mount/close.
- `MenuAcoes` sem foco de retorno nem navegação por setas; fora do barrel de componentes.
- Faltam testes de 403 no download de anexo e de falha de upload.
- `?nova=1` na URL de edição (abrir direto em modo "adicionar reserva") não foi implementado — decisão adiada; "+ Adicionar reserva" no fluxo de negócio só navega para a edição hoje (vira correto quando `?nova=1` existir).
- Alert de conflito + "Recarregar" duplicado em 5 modais; `conflito` não limpa depois de "Recarregar".
- `ResumoTab` lista todas as reservas mas conta só as ativas.
- Mapas `nfse_tomador`/`anexo_tipo` sem consumidor.
- `mensagemDeErro` importado de dois caminhos (`@/api/http` e `@/api/errors`).
- Upload envia `Content-Type` vazio para arquivo sem extensão.
- 409 com wording diferente entre modais (Alert) e listas (toast + invalidate).
- `erroArquivo` não limpa ao trocar de arquivo.
- `fixtures.ts` só-teste em `src/`.
- Receita de baselines Linux do Playwright só está no README (config de CI descartada).

### Fechadas em 3.4/3.5 (2026-09-10)
- (3.3) Documentos de passageiro na tab Documentos da viagem — bloco "Documentos dos passageiros" em `DocumentosTab` (R11), leitura; edição na página da pessoa.
- (3.3) `ClienteVerProprios` completo em anexos — `VisibilidadeCliente` aplica o filtro em lista, detalhe, viagens, documentos, atendimentos, pendências **e** anexos da pessoa; pendências de viagem só das viagens do próprio vendedor.
- (3.3) `X-Motivo`/`app.motivo` por corpo da requisição — passou a **header** em toda escrita que exige motivo (excluir movimento, reabrir período, escrita em período fechado).
- (3.1) Módulo Financeiro invisível para o perfil Contador — `navegacao.ts` aceita `financeiro.ver_dre` e os GETs do backend também (C7). Ressalva: o Contador recebe 403 em `GET /repasses` (abaixo).

Fechadas pela revisão final da branch (2026-09-11):
- `documento_cliente.numero` era apagado por um PUT de quem não pode vê-lo — `numero = case when @verNumero then @numero else numero end`, gêmeo da defesa já paga para o CPF. Fecha a nota transversal "campo escondido por permissão volta null num PUT".
- `PagarLoteAsync` lia a elegibilidade antes do lock e o UPDATE não filtrava status — passa a reler sob lock (`status = 'a_pagar' and excluido_em is null`, divergência de contagem → `repasse_nao_liberado`), alinhado à ruling transversal de locks de 3.5.
- `RepassesService` usava `DateTime.UtcNow` onde todo o resto usa `DateTime.Today` (em BRT, `pagoEm = amanhã` passava do check das 21h à meia-noite; o ano virava na noite de 31/12).
- `ExcluirDespesaModal` duplicado byte a byte — unificado em `components/Financeiro/`, exportado no barrel e importado nos dois lugares.

### Deferidas da 3.4
Backend:
- DB local do dev ainda tem `ix_cliente_agencia_cpf` da primeira execução da 0015 (DbUp não reaplica): `drop index` manual ou `docker compose down -v`.
- Padrão transversal "campo escondido por permissão volta `null` num PUT": resolvido para `cliente.cpf` e `documento_cliente.numero`; falta conferir os valores sob `ReservaVerValores`.
- CPF completo no detalhe não grava log (R2) — revisar LGPD no piloto.
- Contador de documentos na tab da pessoa: sem fetch eager (LGPD), então falta o número — campo em `ResumoClienteDto` (não entrou em 3.6; segue deferida).
- Vínculo documento↔anexo não existe no schema (R3); trocar janelas por prazo puro não é suportado (R7, 422 `janelas_obrigatorias`).
- `interacao` sem auditoria por trigger; filtro "só automáticos" de atendimentos fora da v1 (não há automáticos).
- Helpers de visibilidade de pessoa duplicados ×4 (2 nomeados no mesmo namespace, 2 inline) — unificar em `VisibilidadeCliente.cs`; guarda `versao_obrigatoria` duplicada em 7 serviços.
- `AtendimentosService.AtualizarAsync` e `DocumentosService.AtualizarAsync` sem guarda `versao_obrigatoria`: PUT sem `versao` devolve 409 em vez de 422; `referencia_invalida` vs `nao_encontrado` inconsistentes.
- `FornecedoresService.NovaVersaoRegraAsync` faz `select max(vigente_desde)` → `insert` sem lock nem constraint única: duas chamadas concorrentes criam duas versões com a mesma vigência (`pg_advisory_xact_lock` por fornecedor ou unique parcial).
- `GruposService.ListarAsync`: `PessoasResumo` depende de `string_agg` preservar o `order by` da subquery (verdade no PG, não garantido) — usar `string_agg(nome, ', ' order by nome)`.
- POST/PUT de documento devolve `numero` sem gravar `log_acesso_documento` (o brief só pede na leitura).
- Viagem soft-deletada aparece na lista de viagens da pessoa; ramo `SemPermissaoException` morto em `ListarDoClienteAsync`; cast `::uuid[]` redundante.
- `agencia_id` ausente em 2 subqueries/join de clientes (RLS cobre); `ValidarAsync` roda antes da checagem de existência no PUT; CTE avaliada 2×.
- Tags acima de 20 truncadas em silêncio (`Take(20)`, sem código 422); `ClienteDesde` em UTC; recompra com `data_volta` nula; `ordem=""`/`direcao` inválidos aceitos em silêncio.
- Contadores da lista de clientes custam duas varreduras extras de `cliente` (materializar `passaportesVencendo` se a lista ficar lenta).
- Fornecedores: comentário desatualizado sobre `current_date`; `DateTime.Today` vs `current_date`; `VigenteDesde` omitido vira `0001-01-01`; paginação normalizada sem teste.

Frontend:
- Subnav "Grupos" visível ao vendedor externo (a rota mostra "Sem permissão"; `navegacao.ts` é de 3.5).
- `useFormularioCadastro`: `TDto` sem constraint `{ id: string }` (cast), `unknown` contravariante nos casts de criar/atualizar (tipar `TReq`), `eslint-disable exhaustive-deps` no reset do form.
- `GrupoInlineModal`: 422 do servidor sem teste dedicado; `formatarCpf`/`formatarCnpj` no-op em strings curtas.
- `DocumentosDosPassageiros` faz uma query por passageiro: abrir a tab Documentos da viagem grava N linhas de `log_acesso_documento` — revisar volume junto da revisão LGPD do piloto (R2).
- `DocumentoModal`: `escopo={props}` vaza props; sem testes de `ViagensPessoa`.
- `PessoaPage`: Select de Grupo uncontrolled→controlled, `vendedoresQ` sem gate, subtítulo pisca zero, lista não invalidada após salvar; `Origem` é `Input` livre (protótipo usa `Select`).
- Busca de grupos sem cleanup do debounce; filtro client-side de opções não pedido.
- Fornecedor: 409 na `NovaVersaoRegraModal` sem "Recarregar"; subtítulo omite "comissão padrão" nula; casts via `unknown` em `useFornecedor`; `POST /fornecedores` devolve `FornecedorDto` enxuto (`versao` vazia até o GET).
- `qsClientes` duplica a receita de `qsLista` (`api/viagens.ts` é congelado).

### Deferidas da 3.5
Backend:
- Reabrir conciliação encerrada (R3) — fora da v1.
- `GerarProximaAsync` não valida competência da sucessora: a despesa gerada pode nascer em mês já fechado.
- Drift da recorrência aceito (31/01 → 28/02 → 28/03) e **uma** sucessora por origem por execução do job — cadeia atrasada só alcança o presente em execuções seguintes.
- Helper de leitura financeira duplicado ×3 (`LeituraFinanceira`/`LeFinanceiro` em Financeiro/Despesas/Fechamento) — com o paralelo encerrado, unificar numa cópia em `Modules/Comum`.
- `UltimoRecebimentoEm` tem duas definições: em Repasses inclui `recebimento_cliente`, na conciliação só `recebimento_operadora` — alinhar.
- `GET /repasses` não é paginado (o contrato não pede); filtro natural é por vendedor.
- `GET /viagens/{id}/movimentos` devolve 200 `[]` para viagem inexistente com `ViagemVer`; `previsto_invalido` é recusado mesmo em aba que ignora o filtro; `RecebidoMes` ignora `fornecedorId`.
- `FechamentoService.ReceitaRecebida` soma `movimento_financeiro.valor` de todos os tipos, inclusive os negativos (nome enganoso — filtrar ou renomear); contagens de reservas/despesas do mês não excluem reserva cancelada.
- `VencemAte7Dias` usa `between current_date and current_date + 7` = 8 dias — confirmar a intenção com o dono do produto.
- Joins de leitura sem `agencia_id` explícito (RLS cobre); comentários `DateTime`→`DateTimeOffset` desatualizados; caminho `valor: null` de repasse sem teste.
- `RepassesTests` calcula `hoje` com `DateTime.UtcNow` enquanto o serviço usa `DateTime.Today` — possível flakiness 21h–00h BRT; alinhar os testes a `Today`.
- Conciliação não localiza reserva por localizador: não há filtro de texto na tela e o `aria-label` da linha não inclui o localizador.

Frontend:
- "Ver extrato" de repasses (R5) — fora da v1.
- "+ Nova despesa" saiu em `primary`; o protótipo usa o laranja (`business`).
- Quatro modais sem teste (`DivergenciaModal`, `ExcluirMovimentoModal`, `FecharPeriodoModal`, `ReabrirModal`); "Encerrar divergência…" sem teste.
- Modais seedam estado inicial via `useState(props)` e são montados sem `key` (`PagarRepasseModal` e irmãos): a página precisa de `key` ao trocar de item.
- Pluralização "1 comissões"; `FecharPeriodoModal` recomputa n/valor; `DespesaModal` sem check local de Valor e com 250 linhas; combobox sem feedback de zero resultados; cálculo de hoje+7 convoluto.
- `aria-label` do checkbox da conciliação cai em `codigo`; `limpar()` não usado; `TIPOS_ENTRADA` exportado sem consumidor.
- Repasses sem skeleton; branch `bloqueado` sem teste; botões de ação dos KPIs renderizados incondicionalmente.
- Chave de tradução `forma_pagamento_despesa` reusada para a forma de pagamento de movimento.
- `useMutacaoFinanceira`: args não memorizados no reenvio com motivo; `periodo_fechado` só como bloco.
- E2E: cada execução polui o banco de dev (uma pessoa, uma viagem, duas despesas) — mesmo custo que `viagens.spec.ts`; seed continua idempotente.

### Fechadas em 3.6 (2026-09-11)
- (3.5) Badge de comissões atrasadas na sidebar (contrato §4.2) — `GET /agenda/badges` devolve `agenda`/`financeiro`/`clientes`; `Sidebar` consulta a cada 5 min e no foco da janela (R4).
- (3.5) Contador recebia 403 em `GET /repasses` — `ContadorSet` ganhou `RepasseVerTodos` (R9); `RepassePagar` continua fora.
- (Fase 2) RLS em `log_acesso` — migration 0016: `select` por `agencia_id = app_agencia_id()`, `insert with check (true)` (login insere antes de haver tenant, por conexão solta — convenção) (R12).
- (3.3) `ix_pendencia_viagem` e (3.4) `ix_interacao_cliente` redundantes — dropados em 0016.
- (3.3) Objeto do storage só sumiria num job `expurgo_anexos` que não existia — job criado (R15): apaga objeto e depois a linha (`delete`, não soft), uma linha por transação curta, storage fora da transação; `log_acesso_documento.anexo_id` vira `null` pela FK de 0012.
- (3.1) Rota `/agenda` sem guarda — `RotaProtegida` com `viagem.ver`/`viagem.ver_proprias` (R16).
- (3.3) `auditoria.motivo` ficava nulo no cancelamento de viagem/reserva (`ViagensOperacoesEndpoints` chamava `http.Contexto()` sem `req.Motivo`) — o motivo do corpo agora vale como `app.motivo`; achado pelo E2E de 3.6.
- (3.5) "`encerrar-divergencia` usa o motivo da divergência como `app.motivo` — registrar a decisão" — registrada como Ruling 3.6 em `regras-e-escopo-v2.md` §8 (um motivo só para negócio e auditoria; vale também para o cancelamento).

Fechadas pela revisão final das branches (2026-09-11):
- `PendenciasService.CarregarBaseAsync` exigia `viagem_id` — pendências soltas e de pessoa agora concluem/adiam/editam (correção de causa raiz, T1).
- `Rotinas.GerarPendenciasAsync` cancelava as derivadas `pendencia:%` com `viagem_id` ao editar datas da viagem — exclui `chave_unica like 'pendencia:%'` (T5).
- Upsert diário de `pendencias_derivadas` sobrescrevia a data de uma pendência adiada — guarda `adiada_de` (emenda a R13).
- Bloco lateral `ProximaViagem*` de Documentos vencendo sem `@apenasVendedor` (externo via viagem do dono) e ramo (b) idem.
- CSV de Relatórios: coluna "Recebido" → "Comissão recebida"; pluralização "1 reservas" no resumo diário.
- Front: `useColaborador` reduzido a `useFormularioCadastro` com mapper de erros opcional (parked T9); `DetalhesEventoModal` e `TimelineTab` passaram a compartilhar o helper De/Para (parked T10); carimbo relativo unificado; `Badge` fora do mapa em Equipe/Documentos; convidar sem `catch`; combobox de pessoa só com mouse; `ROTULO_SERVICO` duplicado; loading ausente em Agenda/Auditoria; `keepPreviousData` nas listas filtradas.

### Deferidas da 3.6
Backend:
- ~~TZ de produção antes do piloto~~: feito 2026-09-11 via `ENV TZ`/`PGTZ` no Dockerfile (ver checklist (c)).
- Cursor da Auditoria por carimbo (`antesDe`) pula empates de `criado_em` (um `POST /viagens` gera 4+ linhas com o mesmo `now()`) — cursor composto `(criado_em, id)`; `Id` não é único na união `auditoria` ∪ `log_acesso_documento` (front chaveia por `tabela+id`).
- `Total` da Auditoria não desconta os eventos que a projeção por perfil remove de `alteracoes`.
- `expurgo_anexos` ignora anexos soft-deleted (`excluido_em not null` com `data_descarte` vencida ficam no storage); delete de linha sem try/catch (falha de DB aborta o lote da agência); `ILogger` extra em `ExpurgoAuditoriaJob`.
- Pendência derivada `concluida` **nunca** renasce e a adiada **não** acompanha nova validade até ser concluída/cancelada (R13 + emenda) — revisar após 30 dias de uso real.
- Paginação dos blocos da Agenda ("1–3 de 6" do protótipo): teto 100 por bloco sem paginação; `Pendencias` sem `limit` no SQL; `CriarSolta` insere em loop; `ComissoesAtrasadas` não exclui reserva cancelada.
- Aniversariantes na Agenda (só no resumo diário via `GET /clientes/aniversarios`; protótipo não os mostra).
- `Csv.Campo` com `double`/`float` usa current culture (só `decimal` em uso); `DateTimeOffset` imprime no próprio offset (T2/T4 convertem para local antes).
- Equipe: e-mail de convite sai após o commit (não atômico, pré-existente); `req.Perfil` nulo → `DoBanco(null)` indeterminado no PUT (pré-existente); `Nome` só é trimado no create; e-mails literais em `EquipeTests` sem sufixo; sem teste de "convite expirado" nem do 409.
- Relatórios: `ReceitaPorMes`/`Servicos`/`Vendedores` sem arredondamento explícito em C#; filtro `Fixas` mistura predicado por linha com constante em `FILTER`; o teste do resumo usa `valor_total = valor_cliente` (`rav_cliente = 0`) — o caminho com RAV do relatório não tem teste próprio (fórmula coberta por `CalculoReservaTests`).
- Testes: falta caso positivo de `/agenda` só com `viagem.ver_proprias`; sem teste `antesDe` + `de`/`ate`; falta assert de `Documentos.Length` para o contador; `AuditoriaTests.cs` com 421 linhas; "Colaborador excluída" (gênero); fake de e-mail falha global; `DateTime.Today` vs `current_date` nos jobs derivados.
- `GET /viagens/{id}/auditoria` segue com `limit 200` sem cursor (3.3); rate limit de login 10/min/IP derruba suítes E2E **encadeadas** (3.3, reincidiu em 3.6 — rodar uma suíte por vez ou subir o limite em dev).

Frontend:
- `PessoaCombobox` compartilhado — hoje 4 cópias (Nova viagem, pendência de viagem, pendência solta na Agenda, Documentos).
- Filtros De/Até da Auditoria vão além do protótipo (`DateInput` sem `Field` visível) — precisa de ruling de design antes de mexer.
- `download.test.ts` faz asserts dentro do mock sem `try/finally`.
- 5 warnings ESLint pré-existentes em `NovaViagemPage` + aviso de chunk-size no `build`.
- Relatórios: heading "Fornecedores" dividido em dois nós; `aria-label` do mês abreviado; `pct1`/`pctTeto` duplicam cálculo.
- Agenda: `falhou` exportado sem consumidor. Equipe: `apresentacaoStatus` 2× por linha; ordem das linhas Financeiro em `PerfilVe`.
- E2E `operacao.spec.ts` depende do seed ("Cobrar comissão CVC", Marcos, Bruno) — reaplicar `backend/scripts/seed-dev.sql` antes de rodar; sem cleanup (padrão da casa).
- (3.4) Contador de documentos na tab da pessoa (`ResumoClienteDto`) — **não** entrou em 3.6; segue deferida.

### Deferidas da Fase 2 (revisões de task e revisão final)
- Login multiagência: e-mail é único global (migration 0004); pessoa em duas agências precisa de dois e-mails.
- `EsqueciSenha` silencioso para usuário convidado sem senha definida; e-mail de convite sai após o commit (falha no Resend gera 500 com linha criada).
- `ExecutarJob` usa `CancellationToken.None` (sem cancelamento por SIGTERM); sem teste do caminho de falha.
- `PrevisaoComissao`: janelas sobrepostas resolvidas por ordem da lista, sem teste; sem teste de ano bissexto.
- `MigrationsTests`: asserção de grant só cobre INSERT.
- Duas `NpgsqlConnection` soltas em call sites pré-login (aceito pela convenção, documentar); log de e-mail em dev inclui o HTML.
- `NU1510` NoWarn é project-wide em `Meridiano.Api.csproj`.
- ~~`alter default privileges for role meridiano` é específico por ambiente; aplicar no Supabase na Fase 4.~~ Fechada na Fase 4: migration `0017_supabase_hardening.sql` revoga tudo de `anon`/`authenticated`/`service_role` (inclusive default privileges do role corrente) e `usage on schema public` de PUBLIC; verificação real por `curl` no PostgREST fica no smoke de produção (`docs/deploy.md` §12).

### Reviews externos (2026-09-11) — aplicado × rejeitado
Aplicado — backend (`32aa8c8..3fc6e72`): `GET /clientes/busca` com ClienteVer/ClienteVerProprios (Contador 403, vendedor externo só quem viaja com ele); reset de senha revoga cookies anteriores (`usuario.senha_alterada_em`, migration 0018, comparado com `IssuedUtc` do cookie truncado a segundo); Data Protection keys em `data_protection_key` (IXmlRepository Dapper, XML sem cifra — cifrar se o acesso ao banco deixar de ser só `meridiano_api`/owner); cursor da auditoria `(criado_em, id)` (linhas da mesma transação compartilham `now()`); expurgo inclui anexos soft-deleted; `HtmlEncoder` no nome dos e-mails; timeout 10 s no Resend. Frontend (`67446d6..714305a`): respostas stale descartadas (`useNovaViagem`, `PassageirosField`, `ViagemCombobox`); `useFormularioCadastro` invalida lista e refaz GET do detalhe após criar (DTO sintético de fornecedor tinha `versao: ""`); `chaveLocal` estável para reserva nova; `ErrorBoundary`; filtros da auditoria na URL; token de convite/reset sai da URL; `AbortSignal.timeout(30 s)` no `http.ts`; Space em linha de DataTable; scroll lock no Modal.
Rejeitado (verificado no código): X-Forwarded-For "de qualquer origem" — ACA ingress faz append e `ForwardLimit=1` lê o último; falha de e-mail após commit — `ReenviarAsync` já é o retry; recorrência em competência fechada — decisão explícita no código; Migrator ausente derrubar startup — jobs rodam sem Migrator de propósito (`deploy.md`); chaves duplicadas na auditoria — `auditoria.id` é único, warning veio de fixture; NaN em fornecedor — `type="number"`; upload sem HEAD de tamanho, LIMIT na agenda, falha de DB por item no expurgo, NuGet fixo, OpenAPI, correlation ID, Zod, logout entre abas, code splitting — sem necessidade medida no piloto.
Ressalvas: skew de relógio API×Postgres > 1 s faz o auto-login pós-reset cair uma vez (401, usuário loga de novo); timeout HTTP no front mostra "Sem conexão".

### Rulings da Fase 4 (plano R1–R12 em `docs/superpowers/plans/2026-09-11-fase-4-piloto.md`; execução no ledger `.superpowers/sdd/2026-09-11-fase-4-piloto/progress.md`)
Plano — custo se errado:
- R1 "Importar planilha" = 3 viagens lançadas à mão; importador é v1.1 (spec §10) — nenhum.
- R2 Bootstrap da primeira agência por SQL one-shot com token de convite (`scripts/bootstrap-agencia.sql`), sem C#, `Program.cs` intocado — exige BYPASSRLS + pooler em modo sessão (documentado em `docs/deploy.md` §9).
- R3 PostgREST fechado por migration 0017 + remover `public` das exposed schemas — reversível com `grant`.
- R4 CI faz deploy com service principal (`AZURE_CREDENTIALS`); GHCR privado + PAT `read:packages`; OIDC só com mais de um ambiente — rotação manual de um secret.
- R5 Jobs = Container Apps Jobs cron (UTC), mesma imagem, `--args job <nome>`, sem `ConnectionStrings__Migrator` — nenhum.
- R6 UptimeRobot a 30 min, não 5 (cota de 180 k vCPU-s) — cold start percebido; `min-replicas 1` (~US$ 10/mês) se incomodar.
- R7 Backup `pg_dump -Fc -n public --no-owner --no-privileges` → R2; retenção 30 d = lifecycle rule; drill de restore antes de todo deploy com migration nova — nenhum.
- R8 FQDN padrão do ACA no piloto; Resend exige domínio verificado — sem domínio, sem e-mail.
- R9 Segredos no ACA por `--secrets` + `secretref:` — nenhum.
- R10 Gabarito da planilha preenchido antes de lançar; divergência nunca "ajusta a planilha" — nenhum.
- R11 Tempo humano por cronômetro do observador, meta ≤ 300 s para 4 reservas — nenhum.
- R12 Frontend não muda na fase; achados de UI viram plano 4.1 — defeito de UI convive com o piloto.
Execução (2026-09-11):
- P1 T0 pôde editar `Meridiano.Api.Tests.csproj` (`<None>` copia o script ao output) — nenhum.
- T1: loop `for` de deploy aborta no primeiro `az` que falhar (fail-fast; CI vermelho, re-run) — um re-run manual.
- T0: `revoke usage on schema public from public` incondicional na 0017 (implementador; revisor de segurança confirmou; PUBLIC herda USAGE por padrão) — role interna do Supabase perder USAGE, reversível.
- Minors deferidos: `backup.yml` sem `shell: bash`/`pipefail` (sem pipe hoje); objeto `meridiano-<dia>.dump` sobrescrito por dispatch manual no mesmo dia; `postgres:17` tag flutuante.
- **Usuário:** piloto local antes da nuvem (imagem integrada, bootstrap, jobs, drill no compose; T5 no stack local) — repetir smoke em produção (já previsto em T4).
- Drill: `pg_dump -n public` não leva `create extension` → pré-criar `pgcrypto`/`pg_trgm` antes do `pg_restore` — nenhum (idempotente).
- Contagem: base era 258 testes API, não 257 (drift do plano) — nenhum.
- CI vermelho em `main` até T3.8 (step `azure/login` sem segredo) aceito em vez de gate `if: vars.DEPLOY` — custo: um run vermelho por push até provisionar; imagem já vai para o GHCR.

### Achados do piloto local (Fase 4, 2026-09-11 — imagem integrada `meridiano:smoke` contra o compose)
Backend:
- `JobRunner` resolve `IEnumerable<IJob>` e por isso **todo job exige `Armazenamento__*`** (`ExpurgoAnexosJob` pede `IArmazenamentoArquivo`; `AmazonS3Client` sem `Endpoint` mata o processo no boot, exit 139, até no `ping`). Runbook passa as vars em todos os jobs. Melhoria: `JobRunner` resolver só o job pedido (`IServiceProvider` + nome) — 1 arquivo.
- `pg_dump -Fc -n public` **não inclui `create extension`**: restore em banco vazio falha nos 4 índices GIN (`gin_trgm_ops`) sem `pg_trgm`. Runbook pré-cria `pgcrypto`/`pg_trgm` antes do `pg_restore` (`docs/deploy.md` §10). Alternativa: dump sem `-n public` com `--exclude-schema` dos schemas do Supabase — não feito.
- Boot da imagem loga `Cannot load library libgssapi_krb5.so.2` (Npgsql sonda GSSAPI; auth é por senha, inofensivo). Sumir com isso = `apt-get install -y libgssapi-krb5-2` no stage runtime do Dockerfile — não vale a camada; deixar.
- `revoke usage on schema public from public` (0017) é incondicional — no compose/Testcontainers só vale porque `meridiano_api` tem grant explícito da 0002 e o owner é superuser; qualquer role nova precisa de `grant usage` explícito.
- Cookie `Secure` (`CookieSecurePolicy.Always` fora de dev) funciona em `http://localhost:8080` só porque navegadores e curl tratam `localhost` como contexto seguro; piloto local em outro host (`http://192.168.x.x`) precisaria de `ASPNETCORE_ENVIRONMENT=Development` ou TLS.
- Plano previa "257 + 2" testes API; a base já era 258 (drift de contagem no plano, não no código).
Operação:
- Jobs pela imagem: `docker run … meridiano:smoke job <nome>` (args após o ENTRYPOINT) — `ping`, `pendencias_derivadas`, `resumo_diario_email` exit 0, `job_execucao.sucesso = true`; resumo diário rodou sem `Email__ResendApiKey` e saiu 0 porque o resumo estava vazio (agência recém-criada) — comportamento com conteúdo e sem chave não verificado.
- Stack local do piloto: agência "Agência Piloto Local", banco sem `seed-dev.sql`; E2E do front dependem do seed — reaplicar antes de rodar Playwright.

### Versão 1.1 (fora da v1, já registradas)
- RAV com câmbio, imposto e desconto explícito (decisão 49).
- DRE completa (despesa hoje é simples).
- Multiagência por usuário.
- Ver `regras-e-escopo-v2.md` §10 para a lista completa.

## Convenções de manutenção deste arquivo
- Atualizar a tabela de fases ao fechar cada onda da Fase 3.
- Pendência resolvida sai daqui e vira commit; não manter histórico aqui (o git já tem).
