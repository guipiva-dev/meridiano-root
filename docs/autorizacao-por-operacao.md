# Meridiano — Autorização por operação

> Contrato transversal definido em 3.0 (Task 7), usado por 3.1–3.6. Cada subplano só acrescenta linhas; não redefine as existentes.

| Operação | Permissão ampla | Permissão própria (filtro) | Escrita | Campos omitidos por perfil |
|---|---|---|---|---|
| `GET /viagens`, `GET /viagens/{id}`, `GET /busca` | `ViagemVer` | `ViagemVerProprias` → `viagem.vendedor_id = usuario_id` | — | sem `ReservaVerValores`: `valor_*`, `rav_*`, `percentual_comissao`, `receita_*`; sem `ViagemVerResultado`: `resultado_viagem`, `repasse_*`, `despesas_viagem` |
| `POST /viagens`, `PUT /viagens/{id}`, `POST /viagens/{id}/reservas`, `PUT /reservas/{id}`, remarcar, cancelar, NFSe, serviços | — | — | `ViagemCriar` (POST) · `ViagemEditar` (demais) · `ViagemDefinirVendedor` para mudar `vendedor_id` | resposta segue a linha acima |
| `GET /viagens/{id}/auditoria` | `AuditoriaVer` | — | — | entradas cujo campo está na lista omitida do perfil são filtradas do `alteracoes` |
| `GET /clientes`, `GET /clientes/{id}`, `GET /clientes/busca` | `ClienteVer` | `ClienteVerProprios` → `exists (viagem_passageiro ∪ viagem.cliente_id) com viagem.vendedor_id = usuario_id` | `ClienteEditar` | sem `ClienteVerDocumento`: `documentos[]`, `cpf`, `passaporte` |
| `GET /clientes/{id}/documentos/{doc}` (download), anexo sensível | `ClienteVerDocumento` | — | `AnexoEnviar` | grava `log_acesso_documento` |
| `GET /fornecedores`, `GET /usuarios/vendedores`, `GET /agencia` | qualquer autenticado | — | `FornecedorEditar` / `UsuarioGerenciar` / `UsuarioGerenciar` | `GET /usuarios/vendedores` devolve só `id, nome, gera_repasse, percentual_padrao` |
| `POST /movimentos`, `PUT/DELETE /movimentos/{id}`, encerrar divergência, receber-lote | `FinanceiroMovimentar` (lançar) · `FinanceiroConciliar` (divergência, lote) | — | idem | — |
| `GET /repasses`, `PUT /repasses/{id}/valor`, `POST /repasses/pagar-lote` | `RepasseVerTodos` | vendedor externo vê só `repasse.usuario_id = usuario_id` (sem permissão dedicada: derivado do perfil) | `RepassePagar` | vendedor externo não vê `valor` de outros nem `resultado` |
| `Despesas` CRUD e pagar | `FinanceiroVerDre` (ler) | — | `FinanceiroMovimentar` | — |
| `POST /periodos/{m}/fechar`, `reabrir` | — | — | `FinanceiroFecharPeriodo` · reabrir e editar fechado: `FinanceiroEditarPeriodoFechado` + `motivo` | — |
| `GET /relatorios/*`, CSV | `RelatorioVer` | — | — | CSV usa a mesma projeção da tela; sem `ViagemVerResultado` não há coluna de resultado |
| `GET /agenda`, `Pendencias` CRUD | qualquer autenticado | vendedor externo: pendências de viagens próprias | `ViagemEditar` | — |
| `GET/PUT /usuarios`, convites | `UsuarioGerenciar` | — | idem | — |
