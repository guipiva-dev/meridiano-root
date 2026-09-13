# Correções da auditoria de homologação — rodada 3 (2026-09-13)

Fonte: `docs/piloto/auditoria-homologacao-3-2026-09-12.md` (1 bloqueador, 6 altos, 24 médios, 27 baixos). Spec: `regras-e-escopo-v2.md`.

**Sem ação de código (registrar em BACKLOG):** B01 (config de storage do ambiente de piloto — `Armazenamento__Endpoint` aponta para `localhost:9000`; operação, não código — mas a falha silenciosa do upload entra em F3); A24 (fase `sem_reserva` é derivada por view, spec §6.1 — só rótulo, em F6); M01 aba "canceladas com recebimento" (rótulos e KPI em F5 resolvem a confusão; aba nova fica no backlog); A07 header "Recebida" com divergência (spec §6.1: divergente = conciliada; só esconder "Receber", em F6).

Branch `fix/homologacao-3` em backend e frontend (já criada a partir de `main`). Global: seguir `.superpowers/sdd/regras-implementador.md` (substituir `feat/fase-3-6` por `fix/homologacao-3`). Implementadores **não commitam**. Códigos 422 novos usados por back e front: `taxa_maior_que_total`, `esperado_negativo`, `valor_acima_da_venda`, `cnpj_duplicado`, `janelas_incompletas`. Permissão nova: `Permissao.FornecedorVer` = `"fornecedor.ver"`.

## Backend

### Task B1 — Validações de reserva, remarcação e NFSe (A02, A03, A12, A16)
Files: `backend/src/Meridiano.Api/Modules/Viagens/ReservaGravacao.cs`, `backend/src/Meridiano.Api/Modules/Viagens/ViagensOperacoes.cs`, `backend/src/Meridiano.Domain/Financeiro/CalculoReserva.cs` (só adicionar helper), `backend/tests/Meridiano.Api.Tests/ViagensCriarTests.cs`, `backend/tests/Meridiano.Api.Tests/ViagensEditarTests.cs`, `backend/tests/Meridiano.Api.Tests/ViagensOperacoesTests.cs`, `backend/tests/Meridiano.Domain.Tests/*CalculoReserva*` (se existir)
Depends-on: none
- A02: `ReservaGravacao.ValidarAsync` — `valor_taxas > valor_total` → 422 `taxa_maior_que_total` ("Taxas não podem passar do total da reserva").
- A03: `valor_cliente` nulo **ou zero** com `valor_total > 0` → gravar `valor_cliente = valor_total` (create e update). Caso comum: cliente paga o total. Não bloquear valores explícitos abaixo do total (desconto é legítimo, §4.2).
- A12: em create, update e `RemarcarAsync` (após aplicar `ValorNovo`/`NovoValorCliente`): calcular `esperado_operadora = valor_comissao + rav_operadora + (valor_cliente − valor_total se rav_cliente_modo = via_operadora)`; se `< 0` → 422 `esperado_negativo` ("Com esses valores a operadora ficaria devendo negativo (R$ X). Ajuste a venda ao cliente ou mude o RAV do cliente para 'retido pela agência'"). Helper `CalculoReserva.EsperadoOperadora(...)` no Domain (ou reutilizar `Calcular`). Na remarcação, o `valor_cliente` usado é o novo se informado, senão o atual.
- A16: `DefinirNfseAsync` — status `emitida` exige `numero` não vazio **e** `data_emissao` ≤ hoje (`Relogio.Hoje()`), além do tomador. 422 `nfse_incompleta` (código existente) com mensagem dizendo o que falta; data futura → 422 `nfse_data_futura`.
- Testes (RED→GREEN): taxa 20000/total 10000 → 422; venda nula → gravada = total (GET devolve `valorCliente = valorTotal`, receita = comissão); remarcar custo 12000 com venda 10500 via operadora → 422 `esperado_negativo` e nada muda; NFSe emitida sem número → 422; data futura → 422.

### Task B2 — CPF nulo, CNPJ único, agenda internacional (A21, A27, A42)
Files: `backend/src/Meridiano.Api/Modules/Pessoas/PessoaDtos.cs`, `backend/src/Meridiano.Api/Modules/Pessoas/ClientesService.cs` (só se necessário para o CPF), `backend/src/Meridiano.Api/Modules/Grupos/GruposService.cs`, `backend/src/Meridiano.Api/Modules/Agenda/AgendaSql.cs`, `backend/tests/Meridiano.Api.Tests/ClientesTests.cs`, `backend/tests/Meridiano.Api.Tests/GruposTests.cs`, `backend/tests/Meridiano.Api.Tests/AgendaTests.cs`
Depends-on: none
- A21: `ClienteDto.Cpf` deixa de omitir quando nulo: com permissão `cliente.ver_documento` o JSON traz `"cpf": null` (ou string); **sem** a permissão a chave continua ausente. Implementar sem `[JsonIgnore(WhenWritingNull)]` — ex.: propriedade `Cpf` sempre serializada e um segundo caminho/DTO sem a propriedade para quem não vê, ou `JsonIgnoreCondition.Never` + DTO distinto. Manter `Editar_sem_permissao_de_documento_preserva_o_cpf` passando. Teste: dono abre pessoa sem CPF → JSON contém a chave `cpf` com `null`; contador (sem permissão) → chave ausente.
- A27: `GruposService.ValidarEnormalizarAsync` — CNPJ (dígitos) único por agência entre grupos não excluídos, ignorando o próprio id na edição → 422 `cnpj_duplicado` ("Já existe um grupo com esse CNPJ"). Teste.
- A42: `AgendaSql.Documentos` — lateral "próxima viagem" só considera `viagem.tipo = 'internacional'` não cancelada com `data_ida >= hoje` (para passaporte); se nenhuma, `proximaViagem` nulo. Teste: pessoa com viagem nacional em outubro e internacional em janeiro → próxima = janeiro; só nacional → nulo.

### Task B3 — Permissões do vendedor externo (P01, P02)
Files: `backend/src/Meridiano.Domain/Comum/Permissao.cs`, `backend/src/Meridiano.Domain/Comum/Permissoes.cs`, `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresEndpoints.cs`, `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresDetalheEndpoints.cs`, `backend/src/Meridiano.Api/Modules/Viagens/ViagemLeitura.cs`, `backend/src/Meridiano.Api/Modules/Viagens/ViagemDtos.cs`, `backend/tests/Meridiano.Api.Tests/AutorizacaoTests.cs`, `backend/tests/Meridiano.Api.Tests/FornecedoresTests.cs`, `backend/tests/Meridiano.Domain.Tests/*Permiss*` (se existir)
Depends-on: none
- P01: nova `Permissao.FornecedorVer` (`"fornecedor.ver"`) em **todos** os perfis exceto `vendedor_externo`. `GET /fornecedores`, `GET /fornecedores/resumo`, `GET /fornecedores/{id}`, `GET /fornecedores/{id}/reservas`, `GET /fornecedores/{id}/regras` (e qualquer outro GET do módulo) → `.RequerPermissao(Permissao.FornecedorVer)`. `GET /usuarios/perfis` (matriz) passa a expor a nova permissão automaticamente. Testes: vendedor externo → 403 `fornecedor.ver`; agente/contador/financeiro → 200.
- P02: no DTO da viagem para quem tem só `viagem.ver_proprias` (vendedor externo, viagem própria), incluir `repasse: { valor, status }` (mesmos campos que o dono vê em `Repasse`, sem `resumo`/resultado). Spec §7.1: "status do repasse e valor do repasse dele". Teste em `AutorizacaoTests` ou `ViagensCriarTests` (`Vendedor_externo_ve_so_a_propria_viagem_e_sem_valores` continua sem valores de reserva, mas com `repasse`).

### Task B4 — Cabeçalhos de segurança, teto de crédito/reembolso, revogar convite (P03, A22, X03)
Files: `backend/src/Meridiano.Api/Infra/InfraExtensions.cs`, `backend/src/Meridiano.Api/Modules/Viagens/ReservaOperacoes.cs`, `backend/src/Meridiano.Api/Modules/Admin/AdminEndpoints.cs`, `backend/src/Meridiano.Api/Auth/ConviteService.cs`, `backend/tests/Meridiano.Api.Tests/InfraTests.cs`, `backend/tests/Meridiano.Api.Tests/CancelamentoTetoTests.cs` (novo), `backend/tests/Meridiano.Api.Tests/EquipeTests.cs`
Depends-on: none
- P03: middleware em `UseInfra` (antes de static files) que adiciona em **toda** resposta (HTML, assets e API): `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: same-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=()`, `Strict-Transport-Security: max-age=31536000; includeSubDomains` (só quando `Request.IsHttps` ou `X-Forwarded-Proto: https`), `Content-Security-Policy: default-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; font-src 'self' data:; connect-src 'self' <origens do storage>; frame-ancestors 'none'` — `connect-src` precisa permitir o host do `Armazenamento:Endpoint` (o front faz PUT direto na URL assinada): ler a config e incluir o origin. Teste em `InfraTests`: index e `/api/v1/auth/me` trazem os cabeçalhos; CSP contém o origin do storage.
- A22: `ReservaOperacoes.CancelarAsync` — `valor_reembolso` e `valor_credito` ≤ `valor_cliente` da reserva → senão 422 `valor_acima_da_venda` ("Valor maior que a venda ao cliente (R$ X)"). Vale também no cancelamento da viagem (mesmo caminho). Testes no arquivo novo.
- X03: `DELETE /usuarios/{id}/convite` (`usuario.gerenciar`): limpa `convite_token`/`convite_expira_em`; usuário volta a `sem_acesso`. Já tem senha → 422 `ja_tem_acesso`. Teste em `EquipeTests`.

### Task B5 — Repasses de viagem cancelada e resultado com repasses (A35, A36)
Files: `backend/src/Meridiano.Api/Modules/Repasses/RepassesService.cs`, `backend/src/Meridiano.Api/Modules/Viagens/Rotinas.cs`, `backend/src/Meridiano.Api/Modules/Relatorios/RelatoriosSql.cs`, `backend/src/Meridiano.Api/Modules/Relatorios/RelatoriosService.cs`, `backend/src/Meridiano.Api/Modules/Relatorios/RelatoriosDtos.cs` (ou onde está o DTO do resumo), `backend/tests/Meridiano.Api.Tests/RepassesTests.cs`, `backend/tests/Meridiano.Api.Tests/RelatoriosTests.cs`
Depends-on: B1, B3, B4 (evitar `Rotinas.cs`/`Relatorios*` em paralelo com quem mexe em Viagens)
- A35: `ReavaliarRepasseAsync` — viagem `cancelada` com repasse **não pago** → `status = 'cancelado'` (se o check da coluna não permitir, usar `bloqueado` + `valor = 0` e documentar); repasse já pago fica como está (§5). `RepassesService.SqlItens`/`SqlKpis` excluem viagens canceladas dos abertos (a pagar/bloqueado/sem valor); histórico de pagos continua listando. Viagem sem reserva ativa **nunca** entra em "sem valor definido" (só pede valor quando há reserva ativa). Teste: cancelar viagem com repasse bloqueado → some dos KPIs; viagem rascunho sem reserva → não conta em `semValor`.
- A36: `RelatoriosSql`/`RelatoriosService.ResumoAsync` — novo campo `repassesPagos` (soma de `repasse.valor` com `pago_em` no ano, respeitando filtro de vendedor) e `resultadoOperacional = recebida − despesasPagas − repassesPagos`. Teste ajusta `Resumo_do_ano_separa_competencia_caixa_e_despesas`.

### Task B6 — Regra de pagamento do fornecedor (F02)
Files: `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresService.cs`, `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresDetalheEndpoints.cs` (só se precisar de rota nova), `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresLeitura.cs` (só leitura de versões, se necessário), `backend/tests/Meridiano.Api.Tests/FornecedoresTests.cs`
Depends-on: B3 (mesmos arquivos de endpoints/testes)
- Janelas: validar cobertura completa de 1..31 sem lacuna nem sobreposição → 422 `janelas_incompletas` ("As janelas precisam cobrir os dias 1 a 31 sem sobreposição"). Fornecedor com `prazo_comissao_dias` continua podendo ter zero janelas.
- Mesmo dia: `POST /regras` com `vigente_desde` **igual** à vigência mais recente **substitui** essa versão (apaga janelas antigas dessa versão, grava as novas) em vez de 422 — a versão do dia é editável. `vigente_desde` anterior à mais recente continua 422 `vigencia_invalida`.
- `GET .../regras` (listagem) devolve versões ordenadas por `vigente_desde desc` com campo `vigente: bool` (a que vale hoje) para o front separar "Próximas versões" / "Vigente" / "Anteriores".
- Testes: lacuna → 422; mesmo dia substitui (só uma versão com aquela data); listagem marca `vigente`.

## Frontend

### Task F1 — Lista de viagens, tabelas e responsivo (A01, R02, R03, U04, U09-parte, "1 viagens")
Files: `frontend/src/pages/viagens/lista/ViagensPage.tsx`, `frontend/src/pages/viagens/lista/ViagensPage.module.css`, `frontend/src/pages/viagens/lista/*.test.tsx`, `frontend/src/components/DataTable/DataTable.module.css`, `frontend/src/components/Tabs/*.module.css`, `frontend/src/components/KpiCard/*.module.css`, `frontend/src/pages/relatorios/*.module.css`, `frontend/src/pages/financeiro/despesas/*.module.css`, `frontend/src/shell/*.module.css` (só header/busca), `frontend/src/lib/display.ts` (helper `plural(n, 'viagem', 'viagens')` se não existir)
Depends-on: none
- A01: 1ª coluna da lista: `.primary` e `.secondary` com `max-width: 34rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap` e `title` com o texto completo; `<code>` do código nunca truncado (colocar código antes do destino ou em `flex: none`). Tabela cabe no contêiner em 1366 com destino de 120 chars (teste: classe aplicada + `title`).
- DataTable: quando `scrollWidth > clientWidth`, sombra/gradiente à direita indicando rolagem (CSS `background-attachment` ou classe via ResizeObserver — o mais simples).
- R02/R03: `Tabs` com `overflow-x: auto` e `flex-wrap: nowrap` abaixo de 640 px; grids de KPI (Relatórios, Despesas, Conciliação) com `grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr))`; barra de ações de Relatórios com `flex-wrap`; busca do header em ≤ 480 px esconde o atalho `Ctrl K` e mantém placeholder curto.
- U04: select "Ida" mostra sempre o prefixo (`Ida: qualquer`, `Ida: este mês`).
- "1 viagens" → `1 viagem` (subtítulo e contadores); helper de plural reutilizável.

### Task F2 — Formulário de reserva (A03, A02, A12, A04, A05)
Files: `frontend/src/components/Reserva/FinancialFields.tsx`, `frontend/src/components/Reserva/FinancialFields.test.tsx`, `frontend/src/components/Reserva/tipos.ts`, `frontend/src/components/Reserva/BookingFields.tsx` (+ test), `frontend/src/pages/viagens/useNovaViagem.ts` (+ test), `frontend/src/pages/viagens/NovaViagemPage.tsx` (+ test), `frontend/src/pages/viagens/mapaErros.ts`, `frontend/src/dominio/calculoReserva.ts` (+ test), `frontend/src/components/ViagemOperacoes/RemarcarModal.tsx` (+ test)
Depends-on: none
- A03: ao sair do campo "Total da reserva" com "Venda ao cliente" vazio → preencher venda = total (marcado como sugerido, editável; se o usuário já digitou venda, não sobrescrever). No `validarReserva`: venda vazia/0 com total > 0 → erro "Informe quanto o cliente contratou (sugerido: total)". Resumo da reserva nunca mostra RAV −total por venda vazia (tratar vazio como "—", não como 0).
- A02: `validarReserva`: taxa > total → erro inline "Taxas não podem passar do total"; mapear `taxa_maior_que_total` em `mapaErros.ts` para o campo `valorTaxas`.
- A12: se `esperado da operadora < 0` (venda < custo com RAV via operadora) → erro inline em "Venda ao cliente": "Com RAV via operadora a venda não pode ficar abaixo do custo"; mapear `esperado_negativo`. `RemarcarModal`: mesma checagem com o novo valor/nova venda antes de enviar; mostrar erro do back.
- A04: erro "Escolha o fornecedor" só depois de tentar salvar ou de tocar o campo (não ao criar o card).
- A05: banner "viagem semelhante" só na criação (`/viagens/nova`), nunca na edição.
- Testes Vitest para cada regra.

### Task F3 — Feedback de erro nos dialogs (F01/A13/A26, B01-front)
Files: `frontend/src/api/errors.ts` (+ test), `frontend/src/api/anexos.ts` (+ test), `frontend/src/components/Anexos/AnexarModal.tsx` (+ test), `frontend/src/components/Financeiro/ReceberModal.tsx` (+ test), `frontend/src/components/Financeiro/useMutacaoFinanceira.ts` (+ test), `frontend/src/components/Cadastros/pessoa/AtendimentoModal.tsx` (+ test), `frontend/src/components/ViagemOperacoes/useOperacao.ts` (+ test), `frontend/src/components/Modal/*` (só se precisar de slot padrão de erro), `frontend/src/components/Cadastros/mapaErrosCadastro.ts`
Depends-on: none
- Regra geral: todo dialog/modal que chama a API mostra `Alert` de erro com `mensagemDeErro(e)` para **qualquer** falha (422 sem campo mapeado, 409, 5xx, rede/timeout). `mensagemDeErro`: 5xx/502 → "O servidor não respondeu (erro N). Tente de novo em instantes."; rede → "Sem conexão com o servidor."; 422 → `detail` do ProblemDetails.
- Receber comissão: `recebimento_acima_esperado` sem checkbox → além de exibir o aviso, mostrar erro "Marque 'Registrar mesmo assim' para confirmar" e focar o checkbox.
- Atendimento: 5xx/rede → Alert no dialog (dialog aberto, dados preservados).
- Anexar: falha no `PUT` (rede, mixed content, 4xx/5xx do storage) → Alert "Não foi possível enviar o arquivo ao armazenamento (<motivo>). Tente de novo." e botão volta a "Anexar"; após 2 falhas, sugerir contato com o suporte. `enviarArquivo` inclui status/URL host na mensagem.
- Testes Vitest: cada caso acima.

### Task F4 — Clientes e Equipe (A21-front, A29, A30, P04, X03, X07-parte)
Files: `frontend/src/pages/clientes/PessoaPage.tsx` (+ test), `frontend/src/pages/clientes/usePessoa.ts`, `frontend/src/pages/clientes/DadosPessoaForm.tsx` (+ test), `frontend/src/pages/equipe/*.tsx` (+ tests), `frontend/src/pages/equipe/useColaborador.ts`, `frontend/src/api/equipe.ts` (+ test), `frontend/src/auth/*` (só leitura do usuário atual; criar hook se não existir)
Depends-on: none (B2 muda o JSON; F4 deve funcionar com `cpf: null` E com chave ausente)
- A21: mostrar campo CPF quando o usuário tem `cliente.ver_documento` (permissões do `/auth/me`), independentemente de a chave `cpf` existir no DTO. Sem permissão → campo oculto.
- A29: "Excluir cliente" desabilitado (com tooltip "Tem viagem ou crédito; não pode ser excluída") quando `resumo.viagens > 0`; confirmação só quando habilitado.
- A30: pessoa não encontrada/excluída (422 `nao_encontrado`) → "Pessoa não encontrada ou excluída." com link para a lista (sem "Tentar de novo").
- P04: `ColaboradorPage` — quando o colaborador é o usuário logado: `Situação` e `Perfil` desabilitados com ajuda "Você não pode alterar o próprio acesso; peça a outro Dono".
- X03: lista de Equipe — botão "Editar" em **todas** as linhas; linha com convite pendente ganha "Cancelar convite" (`DELETE /usuarios/{id}/convite`, confirmação) além de "Reenviar"; toast "Convite enviado para <e-mail>" após convidar/reenviar e "Convite cancelado" após cancelar.

### Task F5 — Financeiro: rótulos, conciliação, repasses, despesas, relatórios (M01, A46, X02, U07, U08, A35/A36-front)
Files: `frontend/src/pages/financeiro/conciliacao/*` (+ tests), `frontend/src/pages/financeiro/fechamento/*` (+ tests), `frontend/src/pages/financeiro/repasses/*` (+ tests), `frontend/src/pages/relatorios/RelatoriosPage.tsx` (+ test), `frontend/src/components/Financeiro/DespesaModal.tsx` (+ test), `frontend/src/api/relatorios.ts` (tipo `repassesPagos`)
Depends-on: F1 (CSS de relatórios/despesas), B5 (campo `repassesPagos`)
- M01: KPI da Conciliação "Recebido no mês" → "Comissões recebidas no mês" com subtítulo "só recebimentos e estornos de operadora"; Fechamento "recebida" → "entradas de caixa" ; Relatórios "Receita recebida" ganha subtítulo "todas as entradas de caixa (operadora + cliente)".
- A46: aba Recebidas: quando `recebido > esperado`, badge "Recebida · +R$ X acima" (mesmo estilo de divergência, cor de aviso).
- X02: linha PARCIAL mostra "Encerrar divergência…" como ação visível ao lado de "Receber saldo" (além do kebab). Hint do motivo no dialog de divergência: "O motivo vai para a auditoria." (sem "Período fechado ou exclusão").
- U07: caption das abas Recebidas/Divergências = "Comissões recebidas" / "Divergências" (não "Comissões a receber").
- U08: `DespesaModal` — com viagem selecionada, esconder "Repete todo mês" (e o aviso) em vez de mostrar select + aviso. KPI "Fixos" subtítulo "despesas fixas (categoria Fixo)".
- A35: `VendedorCard.textoItem`: bloqueado com `aguardando 0` nunca acontece mais (B5); se vier, texto "aguardando comissões da viagem". Sem "informar valor" para viagem sem reserva ativa.
- A36: Relatórios KPI "Resultado operacional" subtítulo "receita recebida − despesas pagas − repasses pagos" e linha "repasses pagos R$ X".

### Task F6 — Detalhe da viagem e fornecedor (A07/A38, X01, A23, A24-rótulo, P02-front, F02-front, U07-parte, NFSe)
Files: `frontend/src/pages/viagens/detalhe/*` (+ tests), `frontend/src/components/Financeiro/ComissoesViagem*.tsx` ou onde vive "Comissões a receber" da aba Financeiro da viagem (+ test), `frontend/src/components/ViagemOperacoes/UsarCreditoModal.tsx` (+ test), `frontend/src/components/ViagemOperacoes/CancelarReservaModal.tsx` (+ test), `frontend/src/components/ViagemOperacoes/CancelarViagemModal.tsx` (+ test), `frontend/src/components/ViagemOperacoes/NfseModal.tsx` (+ test), `frontend/src/components/ViagemOperacoes/DesfechoFields.tsx` (+ test), `frontend/src/pages/fornecedores/NovaVersaoRegraModal.tsx` (+ test), `frontend/src/pages/fornecedores/RegrasTab.tsx` (+ test), `frontend/src/api/fornecedores.ts` (tipo `vigente`), `frontend/src/api/viagens.ts` (tipo `repasse` opcional)
Depends-on: F2 (mesmo diretório `ViagemOperacoes`), B3, B6
- A38/U07: aba Financeiro da viagem — seção "Comissões a receber" só lista reservas `a_receber`/`parcial`/`atrasada` com botão Receber; recebidas/divergentes vão para "Comissões recebidas" sem botão. Parcial mostra "recebido R$ X · falta R$ Y".
- X01: `UsarCreditoModal` — ao escolher crédito, se não há reserva ativa do mesmo fornecedor: mensagem "Este crédito é da <operadora>; não há reserva ativa dela nesta viagem. Adicione uma reserva da <operadora> para usar o crédito." Botão "Usar crédito…" oculto em viagem cancelada.
- A23: `CancelarReservaModal`/`CancelarViagemModal`: quando a reserva tem recebido de operadora > 0 e "Operadora mantém a comissão" desmarcado, mostrar `Alert` de aviso: "Já entraram R$ X desta reserva. Se a operadora vai cobrar de volta, lance um 'Estorno da operadora' depois do cancelamento." (dados já disponíveis no detalhe; passar por prop).
- A22-front: `DesfechoFields` valida crédito/reembolso ≤ venda ao cliente (erro inline) e mapeia `valor_acima_da_venda`.
- A24: badge de fase `sem_reserva` mostra "Sem reserva ativa" quando a viagem tem reservas canceladas (total > 0); "Rascunho" só quando nunca teve reserva.
- P02: Resumo da viagem para vendedor externo (DTO com `repasse` e sem `resumo`): card "Seu repasse: R$ X · <status>".
- NFSe: `NfseModal` — status emitida exige número e data ≤ hoje (inline) e mapeia `nfse_data_futura`; mostrar data de emissão no card da reserva.
- F02-front: `NovaVersaoRegraModal` pré-carrega as janelas da versão vigente; `vigente_desde` default hoje; mensagem quando o back devolve `janelas_incompletas`; `RegrasTab` separa "Próxima versão (a partir de dd/mm)" / "Vigente" / "Versões anteriores" usando `vigente` do B6.

### Task F7 — Rota de fornecedores, título, tipografia, copies (P01-front, F06, U03/AC01, F07, U09, U11, A19, "1 meses")
Files: `frontend/src/pages/fornecedores/rotas.tsx` (+ test), `frontend/src/shell/navegacao.ts` (+ test), `frontend/src/shell/RotaProtegida.tsx` (só se precisar), `frontend/src/components/Page/Page.tsx` (+ test), `frontend/src/styles/global.css`, `frontend/src/styles/tokens.css` (só comentário), `frontend/src/pages/auditoria/*` (+ test), `frontend/src/pages/fornecedores/FornecedoresPage.tsx` (+ test), `frontend/src/pages/agenda/*` (+ tests), `frontend/src/components/Pendencias/AdiarModal.tsx` (ou onde está "Hoje prevista")
Depends-on: B3 (`fornecedor.ver`)
- P01: `/fornecedores/*` protegido por `fornecedor.ver`; item de menu só com a permissão; `GET /fornecedores` só disparado com permissão (nova viagem/despesa já não aparecem para o vendedor).
- F06: `Page` (ou hook `useTitulo`) define `document.title = "<título da página> · Meridiano"` (detalhe da viagem: código + destino). Teste.
- U03/AC01: `global.css` — `html { font-size: 100% }` e `font: var(--type-body)` movido para `body`. Hoje `html { font: var(--type-body) }` faz `rem` = 14 px e todos os tokens saem 12,5 % menores que o contrato (helper 10,5 px em vez de 12). Conferir visualmente 1366 (screenshot no relatório) — o contrato do design system (`docs/design-system-contrato.md`) já prevê 12/13/14/24.
- F07: Auditoria "Ver detalhes" — mapa `campo → rótulo` (`divergencia_motivo` → "Motivo da divergência", `conciliacao_encerrada` → "Conciliação encerrada", `valor_total` → "Total da reserva", etc.; desconhecidos: snake_case → "Snake case" com espaço) e valores booleanos "Sim/Não".
- U09: Fornecedores header "N ativos" / "N inativos" / "N cadastrados" conforme filtro.
- Copies: Agenda "10/2026 · 1 meses" → "vence em 10/2026 (1 mês)" com plural; "Hoje prevista para" → "Prevista para"; Agenda coluna "PENDÊNCIA" → "Alerta" com valores "só no cadastro" → "sem pendência criada".
