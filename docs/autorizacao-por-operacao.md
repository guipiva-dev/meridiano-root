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

> **Nota (3.2, 2026-09-09):** `nao_encontrado` (referência inválida, inativa ou de outro tenant, inclusive `Guardas.TravarViagemAsync`) é sempre **422** na v1, nunca 404 — nenhum endpoint traduz. Ver `RegraDeNegocioException("nao_encontrado")`.

> **Nota (3.3, 2026-09-09):** pendência manual, serviço e anexo de viagem/reserva travam a viagem (`Guardas.TravarViagemAsync`, `for update`) mas **não** renovam o `xmin` da viagem — não fazem parte do formulário de edição (PUT); renovar geraria 409 falso na tela de edição. `sem_permissao_vendedor` (3.2, 422) migrou para o padrão geral: 403 `sem_permissao` via `Results.Problem`.

> **Nota (R6, 3.3):** consumo de crédito exige que o cliente do crédito seja passageiro da viagem (`credito_cliente_invalido`); NFSe recusa reserva cancelada; `adiar` recusa pendência concluída.
