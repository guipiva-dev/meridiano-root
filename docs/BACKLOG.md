# Meridiano — Backlog e estado do projeto

Última revisão: 2026-09-09. Fonte de verdade para "o que já foi feito" e "o que falta". Backlog de configuração do harness fica em `.claude/SETUP-BACKLOG.md`.

## Estado por fase

| Fase | Entrega | Estado | Onde |
|---|---|---|---|
| 1 — Especificação | `regras-e-escopo-v2.md`, `schema-agencia-v2.sql`, análise arquitetural, 50 decisões registradas | Concluída (2026-09-07/08) | raiz, `docs/analise-arquitetural-v1.md` |
| 2 — Esqueleto | Solution .NET 10, migrations DbUp 0001–0011, RLS, auth própria, perfis/permissões, ProblemDetails, jobs CLI, CI, endpoint vertical de usuários | Concluída (2026-09-07). 13 testes de domínio + 26 de API, verdes | `backend/` (repo `meridiano-api`), plano em `docs/superpowers/plans/2026-09-07-fase-2-esqueleto.md` |
| Design | Design system v3, contrato de implementação, protótipo clicável v1 com 22 telas, tokens CSS | **Congelado** em 2026-09-08 após 5 revisões externas (tag `design-v1-freeze` no root) | `docs/design-system-contrato.md`, `docs/design/prototipo-v1.html` + `prototipo-v1/*.png`, `frontend/src/styles/tokens.css` |
| 3 — Front + módulos | React/Vite/TS servido pela API; módulos viagem/reserva, pessoas, fornecedores, financeiro, pendências, despesas, repasses, fechamento, relatórios | **Em andamento.** Plano-mestre `docs/superpowers/plans/2026-09-08-fase-3-master.md` (7 subplanos, 3.0–3.6, revisado 2026-09-08 após review externa; 5 decisões pendentes D1–D5 no mestre); 3.0 **concluída** (2026-09-08) em `2026-09-08-fase-3-0-hardening.md` (7 tasks, 3 ondas), migrations 0001–0012; 3.1 **concluída** (2026-09-08) em `2026-09-08-fase-3-1-scaffold.md` (12 tasks, 7 ondas), migration 0013, D2/D4 aplicadas; 3.2 **concluída** (2026-09-09) em `2026-09-09-fase-3-2-nova-viagem.md` (10 tasks, 6 ondas), 106 testes API + 21 domínio backend, 123 testes Vitest + Playwright e2e 4/4 front; tempo automatizado (E2E, 4 reservas) 6,0 s @1280 / 6,4 s @1440 (meta ≤ 300 s) | `frontend/` (repo `meridiano-app`), `backend/src/Meridiano.Api/Modules/` |
| 4 — Piloto | Deploy Azure Container Apps + Supabase, importar planilha, medir tempo de lançamento | Não iniciada | — |

Tempo humano (teste de UX §7, subplano 3.2): pendente.

## Fase 3 — subplanos (detalhe no plano-mestre)

Cada item vira um plano próprio quando os de que depende fecham:

0. **Hardening** (só backend, **concluído 2026-09-08**) — revalidação de sessão contra o banco, token de convite/reset consumido atomicamente, links `/definir-senha` × `/redefinir-senha`, guarda de último dono com lock, tradução de `PostgresException`, lock de job, helpers de lock de viagem/competência e validação de referência por tenant, migration 0012 (views `security_invoker`, `vw_viagem_titular` corrigida, `vw_fase_viagem` inalterada — cancelada com `comissao_mantida` segue "a receber" por spec §4.2, fixado em teste —, índices únicos parciais de repasse/recorrência/titular, FK do log documental `set null`, auditoria de `fechamento_periodo`), `JobRunner` com `pg_try_advisory_lock` por nome (sem índice em `job_execucao`), tabela de autorização por operação (`docs/autorizacao-por-operacao.md`). Fechou as pendências da Fase 2 listadas em "Fechadas em 3.0" abaixo.
1. **Scaffold** (**concluído 2026-09-08**) — Vite + React + TS no `frontend/`, tokens já existentes, componentes obrigatórios do contrato (§3 de `design-system-contrato.md`: Button, Field/Input, Select, Chip, Tabs, Subnav, Sidebar, Table, Dialog, Toast, EmptyState, Skeleton), roteamento, cliente HTTP com ProblemDetails (422 no campo, 409, 403), sessão por cookie, build em `wwwroot/`. `UsuarioService` movido de `AddAuth` para `AddModules` (fechou pendência da Fase 2); `/auth/me` retorna `permissoes[]`; `GET /auth/tokens/{token}` criado; migration `0013_localizar_usuario_por_token_dados.sql`; Dockerfile em layout irmão + CI do backend construindo a imagem integrada com dois checkouts (D4); breakpoints 700/1024/1280/1366/1440 no lint de tokens (D2); baseline visual do Playwright (`e2e/styleguide.spec.ts-snapshots/`, win32+linux) é a baseline de regressão da `/styleguide`.
2. **Nova viagem** (risco número um, **concluído 2026-09-09**) — endpoint transacional viagem + passageiros + reservas + repasse + pendências automáticas, salvar parcial, adicionar reserva depois, pré-preenchimento, criação inline de pessoa (fornecedor: D1), teclado, aviso de viagem semelhante e reserva duplicada, vigência da regra de pagamento, teste E2E cronometrado. Backend `feat/fase-3-2-nova-viagem` (HEAD `2dd5c37`, base `66c3fd4`): módulos Pessoas, Fornecedores, Agencia, Admin, Viagens, `Meridiano.Domain/Financeiro/CalculoReserva.cs`; 106 testes API + 21 domínio. Frontend `feat/fase-3-2-nova-viagem` (HEAD `265945c`, base `b1ec8bc`): 123 testes Vitest, Playwright styleguide 18/18 (win32+linux), `e2e/nova-viagem.spec.ts` 4/4. Tempo automatizado (4 reservas): 6,0 s @1280 / 6,4 s @1440 (meta ≤ 300 s); tempo humano pendente (teste de UX §7). Fechou as pendências listadas em "Fechadas em 3.2" abaixo.
3. **Viagens** — lista com filtros recolhidos, detalhe com tabs (Reservas · Financeiro · Pendências · Anexos · Auditoria), editar reserva, remarcação, cancelamento com motivo/desfecho/crédito, NFSe, serviços, anexos com `log_acesso_documento`, busca global, `vw_fase_viagem`.
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
- Rota-guard por permissão no front só esconde item de menu, não bloqueia a rota — por design nesta fase; retomar em 3.3.
- `Field.htmlFor` prometido no contrato e ainda ausente.

### Deferidas da 3.2
Backend:
- `ilike '%q%'` em busca de clientes/fornecedores sem escape de `%`/`_` (só amplia dentro do tenant).
- Path `ativo` omitido em `GET /fornecedores` sem teste.
- PUT pode ressuscitar reserva cancelada (SELECT sem filtro de status) → tratar em 3.3.
- Invariante a documentar: toda escrita em reserva renova o xmin da viagem (sustenta a ordem de locks).
- `GET /viagens/semelhantes` sem `excetoViagemId` (edição avisa contra si mesma).
- `GET /reservas/duplicada` sem escopo por vendedor (enumeração de códigos por quem só tem `ViagemVerProprias`).
- `ix_reserva_fornecedor_loc` não cobre `lower(trim())`.
- Valor de repasse pago ignorado silenciosamente no PUT (simétrico: 422 `repasse_pago`).
- 5 códigos de validação sem teste dedicado.
- PUT que limpa `dataIda`/`dataVolta` não remove as pendências automáticas geradas antes (checkin/posviagem/recompra ficam órfãs) → 3.3.
- `sem_permissao_vendedor` responde 422 (plano) enquanto os demais gates de permissão respondem 403 `sem_permissao`; unificar quando a UI de troca de vendedor existir.

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
- **3.3 (obrigatório):** `paraRequest` reenvia `status: "cancelada"` no PUT, mas `ReservaGravacao.ValidarAsync` só aceita `pendente`/`emitida` — ao existir cancelamento, o PUT de uma viagem com reserva cancelada dá 422 `status_invalido`. Decidir em 3.3: omitir canceladas do lote ou aceitar `cancelada` no backend.
- Front envia `repasseValor: null` no PUT quando o usuário não vê resultado (backend ignora sem `ViagemVerResultado`, ver `ViagensService.cs`); omitir o campo no front por defesa em profundidade.
- Cards de reserva sem id usam key por índice (`nova-${i}`): remover do meio pode trocar o nó DOM/foco entre reservas não salvas.
- "Salvar e sair" com erro de validação local só para o spinner do modal; erros ficam na página atrás do modal.

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
