# Meridiano — Autorização por operação

> Contrato transversal definido em 3.0 (Task 7), usado por 3.1–3.6. Cada subplano só acrescenta linhas; não redefine as existentes.

| Operação | Permissão ampla | Permissão própria (filtro) | Escrita | Campos omitidos por perfil |
|---|---|---|---|---|
| `GET /viagens`, `GET /viagens/{id}`, `GET /busca` | `ViagemVer` | `ViagemVerProprias` → `viagem.vendedor_id = usuario_id` | — | sem `ReservaVerValores`: `valor_*`, `rav_*`, `percentual_comissao`, `receita_*`; sem `ViagemVerResultado`: `resultado_viagem`, `repasse_*`, `despesas_viagem` |
| `POST /viagens`, `PUT /viagens/{id}`, `POST /viagens/{id}/reservas`, `PUT /reservas/{id}`, remarcar, cancelar, NFSe, serviços | — | — | `ViagemCriar` (POST) · `ViagemEditar` (demais) · `ViagemDefinirVendedor` para mudar `vendedor_id` | resposta segue a linha acima |
| `GET /viagens/{id}/auditoria` | `AuditoriaVer` | — | — | entradas cujo campo está na lista omitida do perfil são filtradas do `alteracoes` |
| `GET /clientes`, `GET /clientes/{id}`, `GET /clientes/busca`, `POST /clientes` | `ClienteVer` (GET) | `ClienteVerProprios` → `exists (viagem_passageiro) com viagem.vendedor_id = usuario_id` | `ClienteEditar` | sem `ClienteVerDocumento`: `documentos[]`, `cpf`, `passaporte`; `POST /clientes` é a criação inline mínima (nome + CPF opcional) usada na Nova viagem, mesma permissão `ClienteEditar` |
| `GET /clientes/{id}/documentos/{doc}` (download), anexo sensível | `ClienteVerDocumento` | — | `AnexoEnviar` | grava `log_acesso_documento` |
| `GET /viagens/semelhantes` | qualquer autenticado | sem `ViagemVer`: filtra por `vendedor_id = usuario_id`; com `ViagemVer`: sem filtro | — | — |
| `GET /reservas/duplicada` | qualquer autenticado | sem `ViagemVer`: filtra por `vendedor_id = usuario_id` (fechado em 3.3, ver "Fechadas em 3.3" em `docs/BACKLOG.md`) | — | — |
| `GET /fornecedores`, `GET /usuarios/vendedores`, `GET /agencia`, `POST /fornecedores` | qualquer autenticado (GET) | — | `FornecedorEditar` / `UsuarioGerenciar` / `UsuarioGerenciar` | `GET /usuarios/vendedores` devolve só `id, nome, gera_repasse, percentual_padrao`; `POST /fornecedores` é a criação inline mínima (nome + tipo, exceção D1) usada na Nova viagem, mesma permissão `FornecedorEditar` |
| `GET /viagens/{id}/creditos`, `GET /reservas/{id}/alteracoes`, `GET /reservas/{id}/servicos`, `GET /viagens/{id}/pendencias`, `GET /viagens/{id}/anexos`, `GET /busca` | `ViagemVer` | `ViagemVerProprias` → `vendedor_id = usuario_id` (também filtra `GET /viagens`) | — | sem `ReservaVerValores`: `CreditoDto.Valor` e `ReservaAlteracaoDto.ValorAnterior/ValorNovo/MultaCliente` omitidos (`JsonIgnore(WhenWritingNull)`); `GET /viagens?ordem=venda` exige `ReservaVerValores` |
| `POST /viagens/{id}/cancelar`, `POST /reservas/{id}/cancelar`, `POST /reservas/{id}/remarcar`, `POST /viagens/{id}/creditos/consumir`, `POST/PUT/DELETE /servicos`, `POST/PUT/DELETE /pendencias`, `concluir`, `adiar` | — | — | `ViagemEditar` | — |
| `PUT /reservas/{id}/nfse` | — | — | `ViagemEditar` **ou** `FinanceiroMovimentar` (R12: Financeiro emite NFSe por spec §7.1 sem ter `ViagemEditar`) | — |
| `POST /viagens/{id}/transferir` | — | — | `ViagemTransferir` (R4, troca `agente_id`; hoje só Dono) | — |
| `POST /anexos`, `POST /anexos/{id}/confirmar`, `DELETE /anexos/{id}` | — | — | `AnexoEnviar` + visibilidade da viagem | — |
| `GET /anexos/{id}/download` | visibilidade da viagem | `sensivel` exige `ClienteVerDocumento` | — | grava `log_acesso_documento` |
| `POST /movimentos`, `PUT/DELETE /movimentos/{id}`, encerrar divergência, receber-lote | `FinanceiroMovimentar` (lançar) · `FinanceiroConciliar` (divergência, lote) | — | idem | — |
| `GET /repasses`, `PUT /repasses/{id}/valor`, `POST /repasses/pagar-lote` | `RepasseVerTodos` | vendedor externo vê só `repasse.usuario_id = usuario_id` (sem permissão dedicada: derivado do perfil) | `RepassePagar` | vendedor externo não vê `valor` de outros nem `resultado` |
| `Despesas` CRUD e pagar | `FinanceiroVerDre` (ler) | — | `FinanceiroMovimentar` | — |
| `POST /periodos/{m}/fechar`, `reabrir` | — | — | `FinanceiroFecharPeriodo` · reabrir e editar fechado: `FinanceiroEditarPeriodoFechado` + `motivo` | — |
| `GET /relatorios/*`, CSV | `RelatorioVer` | — | — | CSV usa a mesma projeção da tela; sem `ViagemVerResultado` não há coluna de resultado |
| `GET /agenda`, `Pendencias` CRUD | qualquer autenticado | vendedor externo: pendências de viagens próprias | `ViagemEditar` | — |
| `GET/PUT /usuarios`, convites | `UsuarioGerenciar` | — | idem | — |
| **3.4** `GET /clientes/{id}/viagens`, `/documentos`, `/atendimentos`, `/pendencias`, `/anexos` | `ClienteVer` | `ClienteVerProprios` → `exists (viagem_passageiro vp join viagem v … v.vendedor_id = usuario_id)`; pendências **de viagem** só das viagens do próprio vendedor | `ClienteEditar` (POST/PUT/DELETE de documento, atendimento e `POST /clientes/{id}/pendencias`) | sem `ClienteVerDocumento`: `documento.numero` ausente; `GET …/documentos` grava `log_acesso_documento` por linha devolvida (POST/PUT de documento **não** gravam) |
| **3.4** `PUT /clientes/{id}` | — | — | `ClienteEditar` | sem `ClienteVerDocumento` o `cpf` do request é **ignorado** e o CPF gravado é preservado (defesa em profundidade) |
| **3.4** `GET /grupos`, `GET /grupos/{id}` | `ClienteVer` (R8) | — | `ClienteEditar` (`POST/PUT/DELETE /grupos*`, vincular/desvincular) | `DELETE /grupos/{id}/pessoas/{clienteId}` → **204** (front refaz `obter`); soft delete do grupo desvincula as pessoas |
| **3.4** `GET /fornecedores/resumo`, `GET /fornecedores/{id}` | qualquer autenticado | — | `FornecedorEditar` (`PUT /fornecedores/{id}`, `POST /fornecedores/{id}/regras`) | `receitaAno` só com `ReservaVerValores` |
| **3.4** `GET /fornecedores/{id}/reservas` | `ViagemVer` | `ViagemVerProprias` → `vendedor_id = usuario_id` | — | valores (`venda`, `esperado`, `recebido`) só com `ReservaVerValores`; fornecedor de outra agência → 422 `nao_encontrado` |
| **3.5** `GET /conciliacao`, `GET /despesas`, `GET /periodos`, `GET /periodos/{yyyy-MM}/pendentes` | `FinanceiroMovimentar` ou `FinanceiroConciliar` ou `FinanceiroVerDre` | — | — | Contador lê (C7); páginas escondem escrita por `pode()` |
| **3.5** `GET /viagens/{id}/movimentos` | visibilidade da viagem (`ViagemVer`/`ViagemVerProprias`) **e** `ReservaVerValores` | idem lista de viagens | — | sem `ReservaVerValores` → 403 |
| **3.5** `POST /movimentos`, `PUT /movimentos/{id}` | — | — | `FinanceiroMovimentar` | competência de `data_movimento` (no PUT: antiga **e** nova); não renova `xmin` da viagem |
| **3.5** `DELETE /movimentos/{id}` | — | — | `FinanceiroMovimentar` + header `X-Motivo` (ausente → 422 `motivo_obrigatorio`) | soft delete |
| **3.5** `POST /reservas/{id}/encerrar-divergencia`, `POST /reservas/receber-lote` | — | — | `FinanceiroConciliar` | lote é tudo ou nada; viagens travadas em ordem de `viagem_id` vinda do SQL |
| **3.5** `GET /repasses` | `RepasseVerTodos` | sem ela, vendedor externo vê só `repasse.usuario_id = usuario_id` (spec §7.1) | — | Agente **e Contador** → 403 (`ContadorSet` não tem `RepasseVerTodos` e `Permissoes.cs` é congelado, C13 — permissão a decidir em 3.6). Não paginado |
| **3.5** `PUT /repasses/{id}/valor`, `POST /repasses/pagar-lote` | — | — | `RepassePagar` | `PUT` **renova o `xmin` da viagem** (`repasseValor` está no formulário); repasse pago → 422 `repasse_pago` |
| **3.5** `POST/PUT /despesas`, `DELETE /despesas/{id}`, `POST /despesas/{id}/pagar` | — | — | `FinanceiroMovimentar` | competências antiga e nova de `vencimento`/`pago_em`; em período fechado exige `FinanceiroEditarPeriodoFechado` + `X-Motivo` |
| **3.5** `POST /periodos/{yyyy-MM}/fechar` | — | — | `FinanceiroFecharPeriodo` | mês corrente/futuro → 422 `periodo_em_andamento` |
| **3.5** `POST /periodos/{yyyy-MM}/reabrir` | — | — | `FinanceiroEditarPeriodoFechado` + header `X-Motivo` (ausente → 422 `motivo_obrigatorio`) | é `delete` da linha; trigger `aud_fechamento` grava o `DELETE` com `app.motivo` |

> **Nota (3.2, 2026-09-09):** `nao_encontrado` (referência inválida, inativa ou de outro tenant, inclusive `Guardas.TravarViagemAsync`) é sempre **422** na v1, nunca 404 — nenhum endpoint traduz. Ver `RegraDeNegocioException("nao_encontrado")`.

> **Nota (3.3, 2026-09-09):** pendência manual, serviço e anexo de viagem/reserva travam a viagem (`Guardas.TravarViagemAsync`, `for update`) mas **não** renovam o `xmin` da viagem — não fazem parte do formulário de edição (PUT); renovar geraria 409 falso na tela de edição. `sem_permissao_vendedor` (3.2, 422) migrou para o padrão geral: 403 `sem_permissao` via `Results.Problem`.

> **Nota (R6, 3.3):** consumo de crédito exige que o cliente do crédito seja passageiro da viagem (`credito_cliente_invalido`); NFSe recusa reserva cancelada; `adiar` recusa pendência concluída.

> **Nota (3.4, 2026-09-10):** CPF completo no detalhe com `ClienteVerDocumento` **não** grava `log_acesso_documento` (R2) — o log cobre `documento_cliente` e anexo sensível; revisar LGPD no piloto. Abrir a página da pessoa não busca documentos (sem fetch eager), justamente para não gravar log a cada abertura: a tab Documentos só consulta quando aberta e por isso não tem contador (campo em `ResumoClienteDto` fica para 3.6). Listas mostram `cpfMascarado` (decisão 30). Padrão geral confirmado: campo escondido por permissão nunca é apagado por um PUT que volta `null` — vale para `cliente.cpf` (`PUT /clientes/{id}`) e para `documento_cliente.numero` (`PUT /documentos/{id}`); falta conferir os valores sob `ReservaVerValores`.

> **Nota (3.5, 2026-09-10):** `X-Motivo` passou de corpo da requisição para **header** (`ctx.Motivo` → `app.motivo`), fechando a deferida da 3.3: exclusão de movimento, reabertura de período e qualquer escrita em período fechado. `useMutacaoFinanceira` (front) trata 422 `motivo_obrigatorio` abrindo o campo "Motivo" no próprio modal e reenviando com o header; 422 `periodo_fechado` (sem `FinanceiroEditarPeriodoFechado`) vira bloco "peça ao Dono/Financeiro". O Contador (C7) enxerga o módulo Financeiro — `navegacao.ts` aceita `financeiro.ver_dre` —, mas recebe 403 em `GET /repasses`.
