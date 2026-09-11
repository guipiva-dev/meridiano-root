# Meridiano — Backlog e estado do projeto

Última revisão: 2026-09-11. Fonte de verdade para "o que já foi feito" e "o que falta". Backlog de configuração do harness fica em `.claude/SETUP-BACKLOG.md`.

## Estado por fase

| Fase | Entrega | Estado | Onde |
|---|---|---|---|
| 1 — Especificação | `regras-e-escopo-v2.md`, `schema-agencia-v2.sql`, análise arquitetural, 50 decisões registradas | Concluída (2026-09-07/08) | raiz, `docs/analise-arquitetural-v1.md` |
| 2 — Esqueleto | Solution .NET 10, migrations DbUp 0001–0011, RLS, auth própria, perfis/permissões, ProblemDetails, jobs CLI, CI, endpoint vertical de usuários | Concluída (2026-09-07). 13 testes de domínio + 26 de API, verdes | `backend/` (repo `meridiano-api`), plano em `docs/superpowers/plans/2026-09-07-fase-2-esqueleto.md` |
| Design | Design system v3, contrato de implementação, protótipo clicável v1 com 22 telas, tokens CSS | **Congelado** em 2026-09-08 após 5 revisões externas (tag `design-v1-freeze` no root) | `docs/design-system-contrato.md`, `docs/design/prototipo-v1.html` + `prototipo-v1/*.png`, `frontend/src/styles/tokens.css` |
| 3 — Front + módulos | React/Vite/TS servido pela API; módulos viagem/reserva, pessoas, fornecedores, financeiro, pendências, despesas, repasses, fechamento, relatórios | **Em andamento.** Plano-mestre `docs/superpowers/plans/2026-09-08-fase-3-master.md` (7 subplanos, 3.0–3.6, revisado 2026-09-08 após review externa; 5 decisões pendentes D1–D5 no mestre); 3.0 **concluída** (2026-09-08) em `2026-09-08-fase-3-0-hardening.md` (7 tasks, 3 ondas), migrations 0001–0012; 3.1 **concluída** (2026-09-08) em `2026-09-08-fase-3-1-scaffold.md` (12 tasks, 7 ondas), migration 0013, D2/D4 aplicadas; 3.2 **concluída** (2026-09-09) em `2026-09-09-fase-3-2-nova-viagem.md` (10 tasks, 6 ondas), 106 testes API + 21 domínio backend, 123 testes Vitest + Playwright e2e 4/4 front; tempo automatizado (E2E, 4 reservas) 6,0 s @1280 / 6,4 s @1440 (meta ≤ 300 s); 3.3 **concluída** (2026-09-09) em `2026-09-09-fase-3-3-viagens-reservas.md` (16 tasks, 5 ondas), migration 0014, 179 testes API + 22 domínio backend, 237 testes Vitest + Playwright e2e 8/8 front; tempo automatizado (E2E, 4 reservas) 6,0 s @1280 / 7,3 s @1440 (3.2: 6,0 / 6,4); 3.4 e 3.5 **concluídas** (2026-09-10) **em paralelo** sob o contrato `2026-09-09-fase-3-4-3-5-contrato.md` (Task 0 serial e compartilhada) — `2026-09-09-fase-3-4-cadastros.md` (11 tasks, 5 ondas) e `2026-09-09-fase-3-5-financeiro.md` (12 tasks, 4 ondas), migration 0015, 226 testes API + 26 domínio backend, 402 testes Vitest (107 arquivos) + Playwright `cadastros.spec.ts` 4/4 e `financeiro.spec.ts` 4/4 (1280 e 1440), styleguide intocado; tempo automatizado (E2E, 4 reservas) re-medido: 5,8 s @1280 / 6,3 s @1440 (3.3: 6,0 / 7,3) | `frontend/` (repo `meridiano-app`), `backend/src/Meridiano.Api/Modules/` |
| 4 — Piloto | Deploy Azure Container Apps + Supabase, importar planilha, medir tempo de lançamento | Não iniciada | — |

Tempo humano (teste de UX §7, subplanos 3.2 a 3.5): pendente.

## Fase 3 — subplanos (detalhe no plano-mestre)

Cada item vira um plano próprio quando os de que depende fecham:

0. **Hardening** (só backend, **concluído 2026-09-08**) — revalidação de sessão contra o banco, token de convite/reset consumido atomicamente, links `/definir-senha` × `/redefinir-senha`, guarda de último dono com lock, tradução de `PostgresException`, lock de job, helpers de lock de viagem/competência e validação de referência por tenant, migration 0012 (views `security_invoker`, `vw_viagem_titular` corrigida, `vw_fase_viagem` inalterada — cancelada com `comissao_mantida` segue "a receber" por spec §4.2, fixado em teste —, índices únicos parciais de repasse/recorrência/titular, FK do log documental `set null`, auditoria de `fechamento_periodo`), `JobRunner` com `pg_try_advisory_lock` por nome (sem índice em `job_execucao`), tabela de autorização por operação (`docs/autorizacao-por-operacao.md`). Fechou as pendências da Fase 2 listadas em "Fechadas em 3.0" abaixo.
1. **Scaffold** (**concluído 2026-09-08**) — Vite + React + TS no `frontend/`, tokens já existentes, componentes obrigatórios do contrato (§3 de `design-system-contrato.md`: Button, Field/Input, Select, Chip, Tabs, Subnav, Sidebar, Table, Dialog, Toast, EmptyState, Skeleton), roteamento, cliente HTTP com ProblemDetails (422 no campo, 409, 403), sessão por cookie, build em `wwwroot/`. `UsuarioService` movido de `AddAuth` para `AddModules` (fechou pendência da Fase 2); `/auth/me` retorna `permissoes[]`; `GET /auth/tokens/{token}` criado; migration `0013_localizar_usuario_por_token_dados.sql`; Dockerfile em layout irmão + CI do backend construindo a imagem integrada com dois checkouts (D4); breakpoints 700/1024/1280/1366/1440 no lint de tokens (D2); baseline visual do Playwright (`e2e/styleguide.spec.ts-snapshots/`, win32+linux) é a baseline de regressão da `/styleguide`.
2. **Nova viagem** (risco número um, **concluído 2026-09-09**) — endpoint transacional viagem + passageiros + reservas + repasse + pendências automáticas, salvar parcial, adicionar reserva depois, pré-preenchimento, criação inline de pessoa (fornecedor: D1), teclado, aviso de viagem semelhante e reserva duplicada, vigência da regra de pagamento, teste E2E cronometrado. Backend `feat/fase-3-2-nova-viagem` (HEAD `2dd5c37`, base `66c3fd4`): módulos Pessoas, Fornecedores, Agencia, Admin, Viagens, `Meridiano.Domain/Financeiro/CalculoReserva.cs`; 106 testes API + 21 domínio. Frontend `feat/fase-3-2-nova-viagem` (HEAD `265945c`, base `b1ec8bc`): 123 testes Vitest, Playwright styleguide 18/18 (win32+linux), `e2e/nova-viagem.spec.ts` 4/4. Tempo automatizado (4 reservas): 6,0 s @1280 / 6,4 s @1440 (meta ≤ 300 s); tempo humano pendente (teste de UX §7). Fechou as pendências listadas em "Fechadas em 3.2" abaixo.
3. **Viagens e reservas** — `2026-09-09-fase-3-3-viagens-reservas.md` (**concluído 2026-09-09**: 16 tasks, 5 ondas) — lista com filtros recolhidos e `vw_fase_viagem`; detalhe com tabs Resumo · Reservas · Financeiro · Pendências · Documentos · Timeline (protótipo, R3); editar reserva pelo `PUT /viagens/{id}` existente (R1: `PUT /reservas/{id}` não foi criado); remarcação (`reserva_alteracao`, reabre pendências); cancelamento de viagem/reserva com motivo/desfecho/crédito; consumo de crédito uma única vez (`reserva_uso_id`); NFSe por reserva; serviços operacionais; transferência de agente (`agente_id`, `ViagemTransferir`); busca global; anexos com `log_acesso_documento`. Backend `feat/fase-3-3-viagens-reservas` (HEAD `9edb433`, base `64ef818`, 15 commits): migration 0014; 179 testes API + 22 domínio. Frontend `feat/fase-3-3-viagens-reservas` (HEAD `f488107`, base `e2f0b79`, 17 commits): 237 testes Vitest, Playwright styleguide 24/24 (win32+linux), `e2e/viagens.spec.ts` + `e2e/nova-viagem.spec.ts` 8/8 (1280 e 1440). Tempo automatizado (4 reservas) re-medido: 6,0 s @1280 / 7,3 s @1440 (3.2: 6,0 / 6,4). Tempo humano (teste de UX §7): pendente. Fechou as pendências listadas em "Fechadas em 3.3" abaixo.
4. **Cadastros** — `2026-09-09-fase-3-4-cadastros.md` (**concluído 2026-09-10**: 11 tasks, 5 ondas) — Clientes/Pessoa em página própria com tabs Dados · Documentos · Pendências · Viagens · Atendimentos; lista com filtros recolhidos e contadores; Grupos (família/empresa, vincular/desvincular); Fornecedores com tabs Dados · Financeiro · Reservas e regra de pagamento **versionada** por `vigente_desde` (previsões já gravadas intocadas, teste de invariante). Atendimentos = tabela `interacao` (R5); documentos com `log_acesso_documento` por linha lida; `ClienteVerProprios` em lista, detalhe, viagens, documentos, atendimentos, pendências e anexos. Backend `feat/fase-3-4-3-5` (base `9edb433`, HEAD `aaf784d`, compartilhada com 3.5; **mergeada em main 2026-09-11**, merge `16d9c65`): migration 0015. Frontend `feat/fase-3-4-3-5` (base `f488107`, HEAD `cf450af`; **mergeada em main 2026-09-11**, merge `f5a4884`): `e2e/cadastros.spec.ts` 4/4. Fechou as pendências listadas em "Fechadas em 3.4/3.5" abaixo.
5. **Financeiro** — `2026-09-09-fase-3-5-financeiro.md` (**concluído 2026-09-10**: 12 tasks, 4 ondas) — Conciliação com os 5 tipos de movimento e KPIs, encerrar divergência com motivo, lote atômico de recebimento (decisão 48), Repasses (`bloqueado → a_pagar → pago`, valor editável até pagar, pagamento em lote por vendedor com data), Despesas com recorrência idempotente (`ux_despesa_sucessora`) e job `recorrencia_despesas`, Fechamento por competência com lock e reabertura auditada (`delete` + `aud_fechamento`). `X-Motivo` migrou para header. Contador enxerga o módulo (C7) mas recebe 403 em `GET /repasses`. Sem migration própria (0015 é da Task 0 compartilhada). `e2e/financeiro.spec.ts` 4/4. Fechou as pendências listadas em "Fechadas em 3.4/3.5" abaixo.
6. **Agenda, Relatórios, Equipe, Auditoria, jobs** — pendências multi-passageiro, KPIs com fórmulas documentadas, CSV, convite/perfis, auditoria por perfil, RLS em `log_acesso`, jobs (pendências derivadas, resumo e-mail, expurgos, aniversários).

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
- `ix_pendencia_viagem` redundante após a migration 0014 — dropar em migration futura.
- `UrlParaBaixar`/`Sanitizar` de anexo aceita `.`/`..`; truncagem 255 em UTF-16 pode partir surrogate pair.
- Limite de 25 MB em anexos é só declaratório (URL assinada não vincula `Content-Length`); objeto do storage só some no job `expurgo_anexos` (3.6) — considerar regra de tamanho no bucket ou HEAD após confirmar.
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
- `ix_interacao_cliente` é redundante ao lado de `ix_interacao_agencia_cliente` — dropar em migration futura.
- DB local do dev ainda tem `ix_cliente_agencia_cpf` da primeira execução da 0015 (DbUp não reaplica): `drop index` manual ou `docker compose down -v`.
- Padrão transversal "campo escondido por permissão volta `null` num PUT": resolvido para `cliente.cpf` e `documento_cliente.numero`; falta conferir os valores sob `ReservaVerValores`.
- CPF completo no detalhe não grava log (R2) — revisar LGPD no piloto.
- Contador de documentos na tab da pessoa: sem fetch eager (LGPD), então falta o número — campo em `ResumoClienteDto` em 3.6.
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
- Contador recebe 403 em `GET /repasses` (`ContadorSet` sem `RepasseVerTodos`, `Permissoes.cs` congelado) — decidir a permissão em 3.6.
- `GerarProximaAsync` não valida competência da sucessora: a despesa gerada pode nascer em mês já fechado.
- Drift da recorrência aceito (31/01 → 28/02 → 28/03) e **uma** sucessora por origem por execução do job — cadeia atrasada só alcança o presente em execuções seguintes.
- Helper de leitura financeira duplicado ×3 (`LeituraFinanceira`/`LeFinanceiro` em Financeiro/Despesas/Fechamento) — com o paralelo encerrado, unificar numa cópia em `Modules/Comum`.
- `UltimoRecebimentoEm` tem duas definições: em Repasses inclui `recebimento_cliente`, na conciliação só `recebimento_operadora` — alinhar.
- `encerrar-divergencia` usa o motivo da divergência também como `app.motivo` de período fechado, sem pedir justificativa separada (aceito; registrar a decisão).
- `GET /repasses` não é paginado (o contrato não pede); filtro natural é por vendedor.
- `GET /viagens/{id}/movimentos` devolve 200 `[]` para viagem inexistente com `ViagemVer`; `previsto_invalido` é recusado mesmo em aba que ignora o filtro; `RecebidoMes` ignora `fornecedorId`.
- `FechamentoService.ReceitaRecebida` soma `movimento_financeiro.valor` de todos os tipos, inclusive os negativos (nome enganoso — filtrar ou renomear); contagens de reservas/despesas do mês não excluem reserva cancelada.
- `VencemAte7Dias` usa `between current_date and current_date + 7` = 8 dias — confirmar a intenção com o dono do produto.
- Joins de leitura sem `agencia_id` explícito (RLS cobre); comentários `DateTime`→`DateTimeOffset` desatualizados; caminho `valor: null` de repasse sem teste.
- `RepassesTests` calcula `hoje` com `DateTime.UtcNow` enquanto o serviço usa `DateTime.Today` — possível flakiness 21h–00h BRT; alinhar os testes a `Today`.
- Conciliação não localiza reserva por localizador: não há filtro de texto na tela e o `aria-label` da linha não inclui o localizador.

Frontend:
- "Ver extrato" de repasses (R5) — fora da v1.
- Badge de comissões atrasadas na sidebar (contrato §4.2) → 3.6.
- "+ Nova despesa" saiu em `primary`; o protótipo usa o laranja (`business`).
- Quatro modais sem teste (`DivergenciaModal`, `ExcluirMovimentoModal`, `FecharPeriodoModal`, `ReabrirModal`); "Encerrar divergência…" sem teste.
- Modais seedam estado inicial via `useState(props)` e são montados sem `key` (`PagarRepasseModal` e irmãos): a página precisa de `key` ao trocar de item.
- Pluralização "1 comissões"; `FecharPeriodoModal` recomputa n/valor; `DespesaModal` sem check local de Valor e com 250 linhas; combobox sem feedback de zero resultados; cálculo de hoje+7 convoluto.
- `aria-label` do checkbox da conciliação cai em `codigo`; `limpar()` não usado; `TIPOS_ENTRADA` exportado sem consumidor.
- Repasses sem skeleton; branch `bloqueado` sem teste; botões de ação dos KPIs renderizados incondicionalmente.
- Chave de tradução `forma_pagamento_despesa` reusada para a forma de pagamento de movimento.
- `useMutacaoFinanceira`: args não memorizados no reenvio com motivo; `periodo_fechado` só como bloco.
- E2E: cada execução polui o banco de dev (uma pessoa, uma viagem, duas despesas) — mesmo custo que `viagens.spec.ts`; seed continua idempotente.

### Deferidas da Fase 2 (revisões de task e revisão final)
- RLS em `log_acesso` (nada lê a tabela ainda; login insere sem `app.agencia_id`).
- Login multiagência: e-mail é único global (migration 0004); pessoa em duas agências precisa de dois e-mails.
- `EsqueciSenha` silencioso para usuário convidado sem senha definida; e-mail de convite sai após o commit (falha no Resend gera 500 com linha criada).
- `ExecutarJob` usa `CancellationToken.None` (sem cancelamento por SIGTERM); sem teste do caminho de falha.
- `PrevisaoComissao`: janelas sobrepostas resolvidas por ordem da lista, sem teste; sem teste de ano bissexto.
- `MigrationsTests`: asserção de grant só cobre INSERT.
- Duas `NpgsqlConnection` soltas em call sites pré-login (aceito pela convenção, documentar); log de e-mail em dev inclui o HTML.
- `NU1510` NoWarn é project-wide em `Meridiano.Api.csproj`.
- `alter default privileges for role meridiano` é específico por ambiente; aplicar no Supabase na Fase 4.

### Versão 1.1 (fora da v1, já registradas)
- RAV com câmbio, imposto e desconto explícito (decisão 49).
- DRE completa (despesa hoje é simples).
- Multiagência por usuário.
- Ver `regras-e-escopo-v2.md` §10 para a lista completa.

## Convenções de manutenção deste arquivo
- Atualizar a tabela de fases ao fechar cada onda da Fase 3.
- Pendência resolvida sai daqui e vira commit; não manter histórico aqui (o git já tem).
