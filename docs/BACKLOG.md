# Meridiano — Backlog e estado do projeto

Última revisão: 2026-09-09. Fonte de verdade para "o que já foi feito" e "o que falta". Backlog de configuração do harness fica em `.claude/SETUP-BACKLOG.md`.

## Estado por fase

| Fase | Entrega | Estado | Onde |
|---|---|---|---|
| 1 — Especificação | `regras-e-escopo-v2.md`, `schema-agencia-v2.sql`, análise arquitetural, 50 decisões registradas | Concluída (2026-09-07/08) | raiz, `docs/analise-arquitetural-v1.md` |
| 2 — Esqueleto | Solution .NET 10, migrations DbUp 0001–0011, RLS, auth própria, perfis/permissões, ProblemDetails, jobs CLI, CI, endpoint vertical de usuários | Concluída (2026-09-07). 13 testes de domínio + 26 de API, verdes | `backend/` (repo `meridiano-api`), plano em `docs/superpowers/plans/2026-09-07-fase-2-esqueleto.md` |
| Design | Design system v3, contrato de implementação, protótipo clicável v1 com 22 telas, tokens CSS | **Congelado** em 2026-09-08 após 5 revisões externas (tag `design-v1-freeze` no root) | `docs/design-system-contrato.md`, `docs/design/prototipo-v1.html` + `prototipo-v1/*.png`, `frontend/src/styles/tokens.css` |
| 3 — Front + módulos | React/Vite/TS servido pela API; módulos viagem/reserva, pessoas, fornecedores, financeiro, pendências, despesas, repasses, fechamento, relatórios | **Em andamento.** Plano-mestre `docs/superpowers/plans/2026-09-08-fase-3-master.md` (7 subplanos, 3.0–3.6, revisado 2026-09-08 após review externa; 5 decisões pendentes D1–D5 no mestre); 3.0 **concluída** (2026-09-08) em `2026-09-08-fase-3-0-hardening.md` (7 tasks, 3 ondas), migrations 0001–0012; 3.1 **concluída** (2026-09-08) em `2026-09-08-fase-3-1-scaffold.md` (12 tasks, 7 ondas), migration 0013, D2/D4 aplicadas; 3.2 **concluída** (2026-09-09) em `2026-09-09-fase-3-2-nova-viagem.md` (10 tasks, 6 ondas), 106 testes API + 21 domínio backend, 123 testes Vitest + Playwright e2e 4/4 front; tempo automatizado (E2E, 4 reservas) 6,0 s @1280 / 6,4 s @1440 (meta ≤ 300 s); 3.3 **concluída** (2026-09-09) em `2026-09-09-fase-3-3-viagens-reservas.md` (16 tasks, 5 ondas), migration 0014, 179 testes API + 22 domínio backend, 237 testes Vitest + Playwright e2e 8/8 front; tempo automatizado (E2E, 4 reservas) 6,0 s @1280 / 7,3 s @1440 (3.2: 6,0 / 6,4) | `frontend/` (repo `meridiano-app`), `backend/src/Meridiano.Api/Modules/` |
| 4 — Piloto | Deploy Azure Container Apps + Supabase, importar planilha, medir tempo de lançamento | Não iniciada | — |

Tempo humano (teste de UX §7, subplanos 3.2 e 3.3): pendente.

## Fase 3 — subplanos (detalhe no plano-mestre)

Cada item vira um plano próprio quando os de que depende fecham:

0. **Hardening** (só backend, **concluído 2026-09-08**) — revalidação de sessão contra o banco, token de convite/reset consumido atomicamente, links `/definir-senha` × `/redefinir-senha`, guarda de último dono com lock, tradução de `PostgresException`, lock de job, helpers de lock de viagem/competência e validação de referência por tenant, migration 0012 (views `security_invoker`, `vw_viagem_titular` corrigida, `vw_fase_viagem` inalterada — cancelada com `comissao_mantida` segue "a receber" por spec §4.2, fixado em teste —, índices únicos parciais de repasse/recorrência/titular, FK do log documental `set null`, auditoria de `fechamento_periodo`), `JobRunner` com `pg_try_advisory_lock` por nome (sem índice em `job_execucao`), tabela de autorização por operação (`docs/autorizacao-por-operacao.md`). Fechou as pendências da Fase 2 listadas em "Fechadas em 3.0" abaixo.
1. **Scaffold** (**concluído 2026-09-08**) — Vite + React + TS no `frontend/`, tokens já existentes, componentes obrigatórios do contrato (§3 de `design-system-contrato.md`: Button, Field/Input, Select, Chip, Tabs, Subnav, Sidebar, Table, Dialog, Toast, EmptyState, Skeleton), roteamento, cliente HTTP com ProblemDetails (422 no campo, 409, 403), sessão por cookie, build em `wwwroot/`. `UsuarioService` movido de `AddAuth` para `AddModules` (fechou pendência da Fase 2); `/auth/me` retorna `permissoes[]`; `GET /auth/tokens/{token}` criado; migration `0013_localizar_usuario_por_token_dados.sql`; Dockerfile em layout irmão + CI do backend construindo a imagem integrada com dois checkouts (D4); breakpoints 700/1024/1280/1366/1440 no lint de tokens (D2); baseline visual do Playwright (`e2e/styleguide.spec.ts-snapshots/`, win32+linux) é a baseline de regressão da `/styleguide`.
2. **Nova viagem** (risco número um, **concluído 2026-09-09**) — endpoint transacional viagem + passageiros + reservas + repasse + pendências automáticas, salvar parcial, adicionar reserva depois, pré-preenchimento, criação inline de pessoa (fornecedor: D1), teclado, aviso de viagem semelhante e reserva duplicada, vigência da regra de pagamento, teste E2E cronometrado. Backend `feat/fase-3-2-nova-viagem` (HEAD `2dd5c37`, base `66c3fd4`): módulos Pessoas, Fornecedores, Agencia, Admin, Viagens, `Meridiano.Domain/Financeiro/CalculoReserva.cs`; 106 testes API + 21 domínio. Frontend `feat/fase-3-2-nova-viagem` (HEAD `265945c`, base `b1ec8bc`): 123 testes Vitest, Playwright styleguide 18/18 (win32+linux), `e2e/nova-viagem.spec.ts` 4/4. Tempo automatizado (4 reservas): 6,0 s @1280 / 6,4 s @1440 (meta ≤ 300 s); tempo humano pendente (teste de UX §7). Fechou as pendências listadas em "Fechadas em 3.2" abaixo.
3. **Viagens e reservas** — `2026-09-09-fase-3-3-viagens-reservas.md` (**concluído 2026-09-09**: 16 tasks, 5 ondas) — lista com filtros recolhidos e `vw_fase_viagem`; detalhe com tabs Resumo · Reservas · Financeiro · Pendências · Documentos · Timeline (protótipo, R3); editar reserva pelo `PUT /viagens/{id}` existente (R1: `PUT /reservas/{id}` não foi criado); remarcação (`reserva_alteracao`, reabre pendências); cancelamento de viagem/reserva com motivo/desfecho/crédito; consumo de crédito uma única vez (`reserva_uso_id`); NFSe por reserva; serviços operacionais; transferência de agente (`agente_id`, `ViagemTransferir`); busca global; anexos com `log_acesso_documento`. Backend `feat/fase-3-3-viagens-reservas` (HEAD `9edb433`, base `64ef818`, 15 commits): migration 0014; 179 testes API + 22 domínio. Frontend `feat/fase-3-3-viagens-reservas` (HEAD `f488107`, base `e2f0b79`, 17 commits): 237 testes Vitest, Playwright styleguide 24/24 (win32+linux), `e2e/viagens.spec.ts` + `e2e/nova-viagem.spec.ts` 8/8 (1280 e 1440). Tempo automatizado (4 reservas) re-medido: 6,0 s @1280 / 7,3 s @1440 (3.2: 6,0 / 6,4). Tempo humano (teste de UX §7): pendente. Fechou as pendências listadas em "Fechadas em 3.3" abaixo.
4. **Cadastros** — Clientes/Pessoa (tabs, pendências, atendimentos), Grupos, Fornecedores (regra de pagamento com `vigente_desde`).
5. **Financeiro** — Conciliação com os 5 tipos de movimento, divergência, lote atômico, Repasses, Despesas (recorrência idempotente, forma ao pagar), Fechamento com lock por competência e reabertura auditada.
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
- Módulo Financeiro invisível para o perfil Contador com as permissões do brief (`movimentar|conciliar`) vs. as do documento mestre (`movimentar|ver_dre`) — decidir em 3.5.
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
- `X-Motivo`/`app.motivo` continuam por corpo da requisição, não header — mover em 3.5.
- Requisição abortada pelo cliente vira 500 + log Error (`OperationCanceledException`) em `ViagensLista`/`ViagemLeitura`.
- Rate limit de login (10/min/IP) aperta a suíte E2E.
- `UsuarioAtual u` não usado nas escritas de `ServicosService`/`CriarNaViagemAsync` (contrato do plano); query extra de `agente_id` antes do lock em `CriarNaViagemAsync`.
- `q` da lista de viagens sem mínimo de caracteres; join de fornecedor na busca sem `agencia_id`.
- `BuscaEndpoints` importa `Modules.Viagens` para `SemVisibilidade` (acoplamento); sem teste do branch `ViagemVer` sem `ClienteVer`; sem teste positivo de `ordem=venda` com `ReservaVerValores`.
- `DELETE` repetido em anexo já excluído devolve 422; lock da viagem antes da checagem do uploader em `confirmar`; `enviado_por` nullable no schema.
- `mudouDatas` considera "veio data no payload", não "mudou de fato"; `Protocolo()` morto em `ArmazenamentoS3`; joins de leitura sem `agencia_id`/`excluido_em` explícito (convenção, RLS cobre); perf: join com `vw_reserva_financeiro` no detalhe da viagem — medir no piloto.
- Documentos de passageiro entram na tab Documentos em 3.4; Timeline só renderiza com `auditoria.ver` (Agente não tem — revisar no piloto).
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
