# Meridiano — Fase 3.3 — Viagens e reservas: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execução em ondas:** segue `.claude/rules/parallel-subagent-driven-development.md`. Cada task traz `Files:` e `Depends-on:`. Implementadores **não commitam**; o controlador commita uma task por vez, no repo certo (`backend/` = `meridiano-api`, `frontend/` = `meridiano-app`, root só docs). Agentes especialistas da tabela do CLAUDE.md não existem no harness: usar `general-purpose` (modelo por complexidade) e `code-reviewer` genérico.

**Goal:** operar viagens já lançadas: lista com filtros e fases (`vw_fase_viagem`), detalhe com tabs (Resumo · Reservas · Financeiro · Pendências · Documentos · Timeline), cancelamento de reserva/viagem com desfecho e crédito na mesma transação, consumo de crédito uma única vez, remarcação, NFSe, serviços, transferência de agente, pendências manuais (multi-passageiro), anexos com URL assinada e `log_acesso_documento`, auditoria projetada por perfil e busca global.

**Architecture:** backend cresce dentro de `Modules/Viagens` (lista, operações sobre o agregado) e ganha quatro módulos novos (`Busca`, `Pendencias`, `Servicos`, `Anexos`) mais `Auditoria` (leitura). Toda operação sobre viagem/reserva segue o protocolo de 3.0/3.2: competência → `Guardas.TravarViagemAsync(id, versao)` → escrita → `Rotinas.ReavaliarRepasseAsync` → `Rotinas.GerarPendenciasAsync` → `TocarViagemAsync` → `ViagemLeitura.CarregarAsync`. Anexos usam presign S3 local (sem chamada de rede na transação) via `IArmazenamentoArquivo`; migration **0014** acrescenta `anexo.confirmado_em`. Front: `ViagensPage` (lista) e `ViagemPage` (detalhe) sobre `DataTable`/`MoneyCell`/`DateCell`/`StatusCell`/`KpiCard` novos; modais de operação como componentes de domínio; `viagensApi` estendida em `src/api/`; busca global no `GlobalHeader`.

**Tech Stack:** .NET 10 · Dapper · Npgsql · PostgreSQL 17 · AWSSDK.S3 (presign; única dependência nova) · xUnit + Testcontainers · React 19 · react-router 8 · TanStack Query 5 · react-hook-form 7 · Vitest · Playwright.

**Spec:** `regras-e-escopo-v2.md` §4.6 (remarcação), §4.7 (cancelamento, crédito), §4.8 (NFSe), §6/§6.1 (fases e estados), §7 (perfis), §8 (auditoria, motivo obrigatório, LGPD), §9 (pendências, transferência), §10 (busca global, anexos) · `docs/superpowers/plans/2026-09-08-fase-3-master.md` (linha 3.3; "Contratos transversais": Autorização, Protocolo transacional, Repasse, Pendências automáticas, Anexos; D3, D5) · `docs/design-system-contrato.md` §3 (`DataTable`, células, `KpiCard`), §4.1, §4.2, §4.4 (filtros, linha de pendência, auditoria com "Ver detalhes") · `docs/design/prototipo-v1.html` telas `#s-viagens` e `#s-viagem` · `docs/autorizacao-por-operacao.md` · `docs/BACKLOG.md` "Deferidas da 3.2" e "Deferidas da 3.1".

## Global Constraints

- Backend: `Program.cs` não muda; módulos registram serviços em `Endpoints.AddModules` e rotas em `Endpoints.MapEndpoints`. `TreatWarningsAsErrors=true`; `dotnet format --verify-no-changes` limpo; máx. ~350 linhas por arquivo (dividir por responsabilidade, como `ViagensEdicao.cs`).
- Toda query em `DbSessao`; filtra `agencia_id` e `excluido_em is null`. Todo `*_id` do payload passa por `Guardas.ReferenciaAsync` na mesma transação. Mutação do agregado viagem (reserva, alteração, crédito, serviço, repasse, pendência automática, anexo de viagem/reserva) começa com `Guardas.TravarViagemAsync(id, versao)` (competência antes, quando houver `data_compra` envolvida) e termina com `Guardas.TocarViagemAsync` quando só filhos mudaram. **Exceção registrada (ruling 3.3):** pendência manual, serviço e anexo travam a viagem (`for update`, sem conferir versão) mas **não** renovam o `xmin` — não fazem parte do formulário de edição; renovar geraria 409 falso na tela de edição.
- Erros: `RegraDeNegocioException(codigo, msg)` → 422; `ConflitoConcorrenciaException` → 409; `nao_encontrado` é 422 (ruling 3.2). Gates de permissão dentro do serviço respondem **403** `sem_permissao` via `Results.Problem` (padrão de `ViagensEndpoints.cs:47`); `sem_permissao_vendedor` (3.2) migra para esse padrão nesta fase.
- DTO por perfil: sem `ReservaVerValores`, campos de valor **não existem** no JSON (`JsonIgnore(WhenWritingNull)` + `null`); sem `ViagemVerResultado`, `resumo`/`repasse` não existem; `ViagemVerProprias` sem `ViagemVer` filtra `viagem.vendedor_id = usuario_id` em lista, busca, pendências, anexos e auditoria. CSV fica em 3.6 (D3): o botão "Exportar CSV" do protótipo **não entra**.
- Dinheiro `decimal` 2 casas BRL; datas de serviço `DateOnly` ↔ `yyyy-MM-dd`; `servico.data_inicio/data_fim` são `timestamp` sem fuso → `DateTime` `Kind.Unspecified` ↔ `yyyy-MM-ddTHH:mm`; carimbos `DateTimeOffset`; arrays nunca `null`.
- Front: CSS Modules + `tokens.css` (congelado) + `global.css`; sem hex, `font-size:` solto ou `@media` fora de 700/1024/1280/1366/1440; só lucide; máx. 350 linhas/arquivo; textos em português; `npm run lint`, `typecheck`, `test`, `build` verdes. `pode()` só esconde; a API protege. Status de domínio passam por `apresentacaoStatus`.
- Front: toda tela que salva usa `useSalvamento` + `Page dirty` + `versao`; modais de operação (cancelar, remarcar, NFSe, transferir, crédito, pendência, serviço, anexo) são **decisão/risco** (contrato §3) e mandam `versao` da viagem; 409 → Alert "Alguém alterou… Recarregar" que refaz `obter`. Modal destrutivo: título explícito, impacto, botão `danger`.
- Atalhos só pelo registry (`ctrl+k` busca global já registrado no header; `escape` fecha modal/popover).
- Tempo (spec §14): re-executar `e2e/nova-viagem.spec.ts` no fechamento e reportar o tempo (4 reservas) no BACKLOG, ao lado do de 3.2.
- Commits Conventional Commits em inglês com rodapé de atribuição da sessão.

---

## Rulings desta fase (decisões tomadas ao escrever; valem para todas as tasks)

| # | Decisão | Motivo |
|---|---|---|
| R1 | **`PUT /reservas/{id}` não é criado.** "Editar reserva" no detalhe abre `/viagens/{id}/editar?reserva={reservaId}` (card já aberto). | `PUT /viagens/{id}` (3.2) já edita reservas individualmente por `Id`; endpoint novo seria duplicação. |
| R2 | **Reserva cancelada é imutável pelo PUT.** `ReservaGravacao.AtualizarAsync` lança 422 `reserva_cancelada` se a reserva atual está `cancelada`; o front (`paraRequest`/`useNovaViagem`) **omite** reservas canceladas do `reservas[]` (PUT deixa ausentes intocadas). | Fecha os carry-forwards "PUT ressuscita cancelada" e "`status: cancelada` dá `status_invalido`". |
| R3 | Tabs do detalhe = protótipo: **Resumo · Reservas · Financeiro · Pendências · Documentos · Timeline** (6 = teto do contrato). Em 3.3: Financeiro é leitura (faixa + "Comissões a receber" sem botão "Marcar recebida", sem Movimentos/Despesas — 3.5); Documentos = só Anexos (documentos dos passageiros — 3.4); Timeline só aparece com `auditoria.ver` (matriz atual: Agente não tem; revisar no piloto). | Master dizia "Reservas · Financeiro · Pendências · Anexos · Auditoria"; o protótipo congelado vence. |
| R4 | **Transferir = trocar `agente_id`** (`POST /viagens/{id}/transferir`, permissão `ViagemTransferir`, hoje só Dono). Pendências automáticas abertas mudam de responsável. Troca de **vendedor** continua no PUT (3.2, D5 aplicado: repasse pago → 422 `repasse_pago`). | Spec §9 "transferência de viagem entre agentes"; `agente_id` é "quem opera (transferível)". |
| R5 | **Cancelar viagem** (`ViagemEditar`): payload traz desfecho por reserva ativa; reserva ativa fora da lista → 422 `reservas_ativas`. Pendências automáticas abertas → `cancelada`. Repasse reavaliado (pago fica como está, spec §4.7). | Spec §4.7 "toda reserva ativa cancelada antes (ou junto, na mesma ação)". |
| R6 | **Crédito**: criado no cancelamento com desfecho `credito` (cliente = titular da viagem, salvo `clienteId` informado entre os passageiros; fornecedor = da reserva; `reserva_origem_id`). Consumo por `POST /viagens/{id}/creditos/consumir`: crédito `disponivel`, validade `null` ou ≥ hoje, mesmo fornecedor da reserva destino (senão 422 `credito_fornecedor_diferente`); `update … where status = 'disponivel'` com 0 linhas → 422 `credito_indisponivel` (uso único sob concorrência). Consumo não altera valores da reserva (vínculo informativo, spec §4.7). | Spec §4.7 e master "consumo de crédito uma única vez". |
| R7 | **Anexos**: `IArmazenamentoArquivo` com presign S3 (AWSSDK.S3, `ForcePathStyle`, SigV4) — funciona com R2 e com MinIO no `docker compose` (dev). Migration 0014: `anexo.confirmado_em timestamptz`; lista só mostra confirmados; `DELETE` é soft (objeto no storage sai no job `expurgo_anexos`, 3.6). Download de anexo `sensivel` exige `ClienteVerDocumento` e grava `log_acesso_documento`. Nenhuma chamada de rede dentro da transação. | Contrato transversal "Anexos"; testes sem MinIO (presign é cálculo local). |
| R8 | **Busca global** `GET /busca?q` (≥ 2 chars): clientes (`ClienteVer`/`ClienteVerProprios`), viagens (destino, código, titular) e reservas (localizador), 5 de cada, `ilike` com escape de `%`/`_` (também aplicado às buscas de 3.2). | Spec §10; índices `gin_trgm_ops` já existem (0001). |
| R9 | **Lista** `GET /viagens` com `aba` (todas · em_emissao · embarcam_semana · comissao_atrasada · concluidas) + filtros da decisão 38 + paginação (`pagina`, `tamanho ≤ 100`) + `contadores` na mesma resposta (uma query com `count(*) filter`). Ordenação por lista branca (`ida`, `codigo`, `venda`). | Protótipo `#s-viagens`; contrato "Listas paginadas". |
| R10 | **Pendências**: sem `excluido_em` na tabela → "Excluir" = `status = 'cancelada'`. Automáticas (`origem = 'automatica'`) só aceitam concluir/adiar; editar/excluir → 422 `pendencia_automatica`. Concorrência por `xmin` da pendência (`versao` própria). | Schema 0009; spec §9 "cancelar viagem cancela as automáticas". |
| R11 | **Serviços**: CRUD por reserva; `detalhe jsonb` fica `{}` na UI (estrutura por tipo é v1.1); `ordem` = posição. Excluir = soft. | Spec §3 "detalhe operacional fica em `servico`, opcional". |
| R12 | **NFSe**: `PUT /reservas/{id}/nfse` aceita `ViagemEditar` **ou** `FinanceiroMovimentar` (Financeiro faz NFSe por spec §7.1 e não tem `ViagemEditar`). `emitido` exige `numero` e `dataEmissao` → senão 422 `nfse_incompleta`. | Spec §4.8/§7.1. |
| R13 | **Remarcação** `POST /reservas/{id}/remarcar`: grava `reserva_alteracao` (multa informativa); `valorNovo` opcional atualiza `reserva.valor_total` (competência de `data_compra` aberta); `novaDataIda`/`novaDataVolta` opcionais atualizam a viagem e regeneram pendências (reabre concluída se a data mudou). | Spec §4.6 e §9. |
| R14 | `GerarPendenciasAsync` passa a **cancelar órfãs**: automáticas abertas cuja `chave_unica` não foi gerada nesta chamada (ida/volta limpas). | Deferida da 3.2. |
| R15 | Rota-guard por permissão no front: `RotaProtegida` (mostra "Sem permissão" com ação "Ir para Viagens"); aplica em `/viagens*`, `/auditoria`, `/equipe`, `/relatorios`, `/financeiro*`. Só esconde; a API protege. | Deferida da 3.1 "retomar em 3.3". |

---

## Ondas

| Onda | Tasks | Motivo |
|---|---|---|
| 0 | T1 (backend base) · T8 (front componentes) · T9 (front api/tipos/guard) | T1 cria os esqueletos de módulo e registra tudo em `Endpoints.cs` de uma vez; T8/T9 pastas disjuntas |
| 1 | T2 (lista + busca) · T3 (operações) · T4 (pendências) · T5 (serviços) · T7 (auditoria) · T10 (lista front) · T11 (modais de operação) · T12 (pendências/anexos/serviços front + card de leitura) · T13 (busca global) | Backend: pastas disjuntas após T1 (`Endpoints.cs` não é mais tocado; T2 e T3 dividem `Modules/Viagens` por arquivos disjuntos). Front: T10–T13 usam T8/T9 e não se tocam (`rotasModulos.tsx` só em T10) |
| 2 | T6 (anexos) · T14 (detalhe front) | T6 usa `SemPermissaoException` criada em T3; T14 compõe T11 + T12 e toca `rotasModulos.tsx` depois de T10 |
| 3 | T15 (E2E + styleguide + dev docs) | precisa de tudo |
| 4 | T16 (docs, root) | fechamento |

---

## Contrato de API (fonte única para backend e front)

```
GET  /api/v1/viagens?aba&q&vendedorId&tipo&fornecedorId=..&fornecedorId=..&nfse&idaDe&idaAte&compraDe&compraAte&ordem&direcao&pagina&tamanho
                                                        → 200 ListaViagensDto
GET  /api/v1/busca?q                                    → 200 BuscaDto
POST /api/v1/viagens/{id}/cancelar     CancelarViagemRequest   → 200 ViagemDto | 409
POST /api/v1/viagens/{id}/transferir   TransferirRequest       → 200 ViagemDto | 409
GET  /api/v1/viagens/{id}/creditos                             → 200 CreditoDto[]
POST /api/v1/viagens/{id}/creditos/consumir ConsumirCreditoRequest → 200 ViagemDto | 409
POST /api/v1/reservas/{id}/cancelar    CancelarReservaRequest  → 200 ViagemDto | 409
POST /api/v1/reservas/{id}/remarcar    RemarcarRequest         → 200 ViagemDto | 409
PUT  /api/v1/reservas/{id}/nfse        NfseRequest             → 200 ViagemDto | 409
GET  /api/v1/reservas/{id}/alteracoes                          → 200 ReservaAlteracaoDto[]
GET  /api/v1/reservas/{id}/servicos                            → 200 ServicoDto[]
POST /api/v1/reservas/{id}/servicos    ServicoRequest          → 201 ServicoDto
PUT  /api/v1/servicos/{id}             ServicoRequest (+versao)→ 200 ServicoDto | 409
DELETE /api/v1/servicos/{id}                                   → 204
GET  /api/v1/viagens/{id}/pendencias?incluirConcluidas         → 200 PendenciaDto[]
POST /api/v1/viagens/{id}/pendencias   NovaPendenciaRequest    → 201 PendenciaDto[]
PUT  /api/v1/pendencias/{id}           PendenciaRequest        → 200 PendenciaDto | 409
POST /api/v1/pendencias/{id}/concluir  { versao }              → 200 PendenciaDto | 409
POST /api/v1/pendencias/{id}/adiar     { novaData, versao }    → 200 PendenciaDto | 409
DELETE /api/v1/pendencias/{id}                                 → 204   (status = cancelada)
GET  /api/v1/viagens/{id}/anexos                               → 200 AnexoDto[]
POST /api/v1/anexos                    NovoAnexoRequest        → 201 { anexo: AnexoDto, urlUpload: string }
POST /api/v1/anexos/{id}/confirmar                             → 200 AnexoDto
GET  /api/v1/anexos/{id}/download                              → 200 { url: string }
DELETE /api/v1/anexos/{id}                                     → 204
GET  /api/v1/viagens/{id}/auditoria                            → 200 EventoAuditoriaDto[]
```

Permissões (acrescentar em `docs/autorizacao-por-operacao.md` na T16):

| Operação | Permissão | Observação |
|---|---|---|
| `GET /viagens`, `GET /busca`, `GET /viagens/{id}/pendencias`, `/anexos`, `/creditos`, `GET /reservas/{id}/alteracoes`, `/servicos` | `ViagemVer` ou `ViagemVerProprias` (filtro `vendedor_id = usuario`) | sem nenhuma das duas → 403 |
| `POST …/cancelar` (viagem e reserva), `remarcar`, `creditos/consumir`, `POST/PUT/DELETE servicos`, `POST/PUT/DELETE pendencias`, `concluir`, `adiar` | `ViagemEditar` | |
| `PUT /reservas/{id}/nfse` | `ViagemEditar` **ou** `FinanceiroMovimentar` | R12 |
| `POST /viagens/{id}/transferir` | `ViagemTransferir` | R4 |
| `POST /anexos`, `confirmar`, `DELETE /anexos/{id}` | `AnexoEnviar` (+ visibilidade da viagem) | |
| `GET /anexos/{id}/download` | visibilidade da viagem; `sensivel` exige `ClienteVerDocumento` e grava `log_acesso_documento` | |
| `GET /viagens/{id}/auditoria` | `AuditoriaVer` | campos omitidos por perfil filtrados de `alteracoes` |

```csharp
// ---- Modules/Viagens/ViagemDtos.cs (T1 estende ReservaDto/ViagemDto — campos novos antes dos campos com JsonIgnore) ----
public sealed record ReservaDto(
    /* …campos de 3.2 inalterados… */,
    // 3.3 (sempre visíveis)
    bool ComissaoMantida, DateTimeOffset? CanceladaEm, string? MotivoCancelamento, string? DesfechoCancelamento,
    string? NfseTomador, string? NfseNumero, DateOnly? NfseDataEmissao, bool ConciliacaoEncerrada, string SituacaoComissao,
    // 3.3 (omitidos sem ReservaVerValores)
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? ValorReembolso,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? RecebidoOperadora);
public sealed record ResumoViagemDto(decimal VendaTotal, decimal CustoFornecedores, decimal ReceitaPrevista, decimal ReceitaRecebida, decimal? RepasseValor, string? RepasseStatus, decimal DespesasViagem, decimal Resultado);
public sealed record ViagemDto(/* …3.2… */, string? AgenteNome, DateTimeOffset? CanceladaEm, string? MotivoCancelamento, /* Repasse, Resumo */);
// SituacaoComissao ∈ nao_prevista | a_receber | parcial | atrasada | recebida | divergente (spec §6.1, entidade "comissao")

// ---- Modules/Viagens/ViagemListaDtos.cs (T2) ----
public sealed record ListaViagemDto(Guid Id, string Codigo, string Titular, string Destino, string Tipo, DateOnly? DataIda, DateOnly? DataVolta,
    string VendedorNome, string FaseOperacional, string FaseFinanceira,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? VendaTotal,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? ReceitaPrevista);
public sealed record ContadoresDto(int Todas, int EmEmissao, int EmbarcamSemana, int ComissaoAtrasada, int Concluidas);
public sealed record ListaViagensDto(ListaViagemDto[] Itens, int Total, int Pagina, int Tamanho, ContadoresDto Contadores);
public sealed record FiltroViagens(string? Aba, string? Q, Guid? VendedorId, string? Tipo, Guid[] FornecedorId, string? Nfse,
    DateOnly? IdaDe, DateOnly? IdaAte, DateOnly? CompraDe, DateOnly? CompraAte, string? Ordem, string? Direcao, int Pagina = 1, int Tamanho = 25);

// ---- Modules/Busca/BuscaDtos.cs (T2) ----
public sealed record BuscaClienteDto(Guid Id, string Nome, string? Telefone);
public sealed record BuscaViagemDto(Guid Id, string Codigo, string Destino, string Titular, DateOnly? DataIda, string FaseOperacional);
public sealed record BuscaReservaDto(Guid ReservaId, Guid ViagemId, string Codigo, string Localizador, string FornecedorNome);
public sealed record BuscaDto(BuscaClienteDto[] Clientes, BuscaViagemDto[] Viagens, BuscaReservaDto[] Reservas);

// ---- Modules/Viagens/OperacoesDtos.cs (T3) ----
public sealed record CreditoRequest(decimal Valor, DateOnly? Validade, Guid? ClienteId);
public sealed record CancelarReservaRequest(string Motivo, string Desfecho, decimal? ValorReembolso, bool ComissaoMantida, CreditoRequest? Credito, string Versao);
public sealed record CancelarReservaItem(Guid ReservaId, string Desfecho, decimal? ValorReembolso, bool ComissaoMantida, CreditoRequest? Credito);
public sealed record CancelarViagemRequest(string Motivo, CancelarReservaItem[] Reservas, string Versao);
public sealed record RemarcarRequest(DateOnly DataAlteracao, string Descricao, decimal? ValorNovo, decimal MultaCliente, DateOnly? NovaDataIda, DateOnly? NovaDataVolta, string Versao);
public sealed record NfseRequest(string Status, string? Tomador, string? Numero, DateOnly? DataEmissao, string Versao);
public sealed record TransferirRequest(Guid AgenteId, string Versao);
public sealed record ConsumirCreditoRequest(Guid CreditoId, Guid ReservaId, string Versao);
public sealed record CreditoDto(Guid Id, Guid ClienteId, string ClienteNome, Guid FornecedorId, string FornecedorNome, decimal Valor, DateOnly? Validade, string Status, Guid? ReservaOrigemId, string? CodigoViagemOrigem, Guid? ReservaUsoId);
public sealed record ReservaAlteracaoDto(Guid Id, DateOnly DataAlteracao, string Descricao, decimal? ValorAnterior, decimal? ValorNovo, decimal MultaCliente, string? UsuarioNome, DateTimeOffset CriadoEm);

// ---- Modules/Pendencias/PendenciaDtos.cs (T4) ----
public sealed record PendenciaDto(Guid Id, string Versao, string Titulo, string? Descricao, DateOnly DataPrevista, Guid? ResponsavelId, string? ResponsavelNome,
    Guid? ClienteId, string? ClienteNome, Guid? ViagemId, string? CodigoViagem, string Status, string Origem, string Prioridade, DateOnly? AdiadaDe, DateTimeOffset? ConcluidaEm, bool Atrasada);
public sealed record NovaPendenciaRequest(string Titulo, string? Descricao, DateOnly DataPrevista, Guid? ResponsavelId, string Prioridade, Guid[] ClienteIds);
public sealed record PendenciaRequest(string Titulo, string? Descricao, DateOnly DataPrevista, Guid? ResponsavelId, string Prioridade, string Versao);
public sealed record ConcluirPendenciaRequest(string Versao);
public sealed record AdiarPendenciaRequest(DateOnly NovaData, string Versao);

// ---- Modules/Servicos/ServicoDtos.cs (T5) ----
public sealed record ServicoDto(Guid Id, string Versao, Guid ReservaId, string Tipo, string Titulo, DateTime? DataInicio, DateTime? DataFim, string? Localidade, string? LocalizadorCia, string? NumeroBilhete, string? Observacoes, int Ordem);
public sealed record ServicoRequest(string Tipo, string Titulo, DateTime? DataInicio, DateTime? DataFim, string? Localidade, string? LocalizadorCia, string? NumeroBilhete, string? Observacoes, int Ordem, string? Versao);

// ---- Modules/Anexos/AnexoDtos.cs (T6) ----
public sealed record NovoAnexoRequest(Guid? ClienteId, Guid? ViagemId, Guid? ReservaId, string Tipo, string NomeArquivo, string? MimeType, long? TamanhoBytes, bool Sensivel, DateOnly? DataDescarte);
public sealed record AnexoDto(Guid Id, string Vinculo, Guid? ClienteId, Guid? ViagemId, Guid? ReservaId, string Tipo, string NomeArquivo, string? MimeType, long? TamanhoBytes, bool Sensivel, DateOnly? DataDescarte, string? EnviadoPorNome, DateTimeOffset CriadoEm);
public sealed record AnexoCriadoDto(AnexoDto Anexo, string UrlUpload);
// Vinculo ∈ cliente | viagem | reserva (derivado da coluna preenchida; anexo_tem_vinculo garante ≥ 1; a API exige exatamente 1)

// ---- Modules/Auditoria/AuditoriaDtos.cs (T7) ----
public sealed record AlteracaoDto(JsonElement? De, JsonElement? Para);
public sealed record EventoAuditoriaDto(long Id, string Tabela, Guid RegistroId, string Acao, string Titulo, string? Subtitulo,
    Dictionary<string, AlteracaoDto> Alteracoes, string? Motivo, string? UsuarioNome, DateTimeOffset CriadoEm);
```

Códigos 422 novos: `reserva_cancelada`, `reservas_ativas`, `viagem_cancelada`, `motivo_obrigatorio` (já existe), `desfecho_invalido`, `credito_valor_invalido`, `credito_cliente_invalido`, `credito_indisponivel`, `credito_expirado`, `credito_fornecedor_diferente`, `nfse_incompleta`, `nfse_invalida`, `pendencia_automatica`, `pendencia_cancelada`, `titulo_obrigatorio`, `prioridade_invalida`, `passageiro_invalido`, `servico_tipo_invalido`, `anexo_vinculo_invalido`, `anexo_tipo_invalido`, `anexo_nao_confirmado`, `arquivo_grande` (> 25 MB), `busca_curta` (já existe), `aba_invalida`, `ordem_invalida`, `agente_igual`.

---

### Task 1 (backend): Base — migration 0014, DTOs estendidos, leitura, pendências órfãs, storage, esqueletos de módulo, fixture

**Files:**
- Create: `backend/src/Meridiano.Data/Migrations/0014_anexo_confirmado_e_indices.sql`
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagemDtos.cs`, `backend/src/Meridiano.Api/Modules/Viagens/ViagemLeitura.cs`, `backend/src/Meridiano.Api/Modules/Viagens/Rotinas.cs`, `backend/src/Meridiano.Api/Modules/Comum/Guardas.cs` (enum `Tabela` + `TravarViagemDaReservaAsync`), `backend/src/Meridiano.Api/Modules/Endpoints.cs`
- Create: `backend/src/Meridiano.Api/Infra/Armazenamento/{IArmazenamentoArquivo.cs,ArmazenamentoS3.cs,ArmazenamentoExtensions.cs}`
- Create (esqueletos vazios, só assinatura + registro): `backend/src/Meridiano.Api/Modules/Viagens/{ViagensOperacoes.cs,ViagensLista.cs,ViagensOperacoesEndpoints.cs}`, `backend/src/Meridiano.Api/Modules/Busca/BuscaEndpoints.cs`, `backend/src/Meridiano.Api/Modules/Pendencias/PendenciasEndpoints.cs`, `backend/src/Meridiano.Api/Modules/Servicos/ServicosEndpoints.cs`, `backend/src/Meridiano.Api/Modules/Anexos/AnexosEndpoints.cs`, `backend/src/Meridiano.Api/Modules/Auditoria/AuditoriaEndpoints.cs`
- Modify: `backend/src/Meridiano.Api/Meridiano.Api.csproj` (+ `AWSSDK.S3`), `backend/src/Meridiano.Api/appsettings.json` (+ seção `Armazenamento`), `backend/docker-compose.yml` (+ `minio` e `minio-init`)
- Modify: `backend/tests/Meridiano.Api.Tests/Fixtures/PostgresFixture.cs` (+ helpers), `backend/tests/Meridiano.Api.Tests/Fixtures/MeridianoApiFactory.cs` (+ config `Armazenamento` fake)
- Create: `backend/tests/Meridiano.Api.Tests/ArmazenamentoTests.cs`, `backend/tests/Meridiano.Api.Tests/RotinasTests.cs`
- Modify: `backend/tests/Meridiano.Api.Tests/MigrationsTests.cs` (+ asserção da coluna nova)

**Depends-on:** none

**Interfaces:**
- Produces:
```csharp
// Guardas
public enum Tabela { Cliente, Fornecedor, Usuario, Viagem, Reserva, Grupo, Despesa, Servico, Pendencia, Anexo, Credito }
// Servico: ("servico", true, false) · Pendencia: ("pendencia", false, false) · Anexo: ("anexo", true, false) · Credito: ("credito", true, false)
public static async Task<(Guid ViagemId, string Versao)> TravarViagemDaReservaAsync(DbSessao s, Guid reservaId, Guid agenciaId, string? versaoEsperada, CancellationToken ct)
// = select viagem_id from reserva where id and agencia_id and excluido_em is null → nao_encontrado; depois TravarViagemAsync(viagemId, versaoEsperada)

// Rotinas.GerarPendenciasAsync: mesma assinatura; após o upsert:
//   update pendencia set status = 'cancelada' where agencia_id = @agenciaId and viagem_id = @viagemId and origem = 'automatica' and status = 'aberta' and chave_unica <> all(@chaves)
public static Task CancelarPendenciasAutomaticasAsync(DbSessao s, Guid agenciaId, Guid viagemId, CancellationToken ct)   // todas as automáticas abertas → cancelada
public static Task TransferirPendenciasAutomaticasAsync(DbSessao s, Guid agenciaId, Guid viagemId, Guid novoResponsavel, CancellationToken ct) // abertas → responsavel_id

// Infra/Armazenamento
public interface IArmazenamentoArquivo
{
    string UrlParaEnviar(string caminho, string? mimeType, TimeSpan validade);
    string UrlParaBaixar(string caminho, string nomeArquivo, TimeSpan validade);   // Content-Disposition: attachment; filename
    Task ExcluirAsync(string caminho, CancellationToken ct);
}
public sealed record ArmazenamentoOpcoes(string Endpoint, string Bucket, string AccessKey, string SecretKey, string Regiao = "auto");
public sealed class ArmazenamentoS3(ArmazenamentoOpcoes o) : IArmazenamentoArquivo   // AmazonS3Client { ServiceURL = Endpoint, ForcePathStyle = true, AuthenticationRegion = Regiao }; GetPreSignedURL (cálculo local)
public static WebApplicationBuilder AddArmazenamento(this WebApplicationBuilder b)   // lê "Armazenamento:*"; registra singleton IArmazenamentoArquivo; chamado dentro de AddModules (Program.cs não muda)

// ViagemLeitura.CarregarAsync: mesma assinatura; ReservaDto/ViagemDto/ResumoViagemDto com os campos do Contrato
// Fixture
public Task<Guid> InserirViagemCompletaAsync(Guid agenciaId, Guid vendedorId, Guid titularId, Guid fornecedorId, DateOnly? ida = null, DateOnly? volta = null, Guid? agenteId = null)
//   viagem (ida/volta default current_date+30/+40, agente_id) + passageiro titular + 1 reserva emitida (total 1000, cliente 1000, comissão 100, esperado 100, prevista current_date+60)
public Task<Guid> InserirMovimentoAsync(Guid agenciaId, Guid reservaId, string tipo, decimal valor, DateOnly? data = null)
public Task InserirFechamentoAsync(Guid agenciaId, DateOnly competencia)
public Task<Guid> InserirPendenciaAsync(Guid agenciaId, Guid? viagemId, string titulo, DateOnly data, Guid? responsavelId = null, string origem = "manual", string? chave = null, Guid? clienteId = null)
public Task<Guid> InserirCreditoAsync(Guid agenciaId, Guid clienteId, Guid fornecedorId, decimal valor, DateOnly? validade = null, Guid? reservaOrigemId = null, string status = "disponivel")
```
  - `Endpoints.AddModules`: `+ b.AddArmazenamento(); AddScoped<Viagens.ViagensOperacoes>(), <Viagens.ViagensLista>(), <Busca.BuscaService>(), <Pendencias.PendenciasService>(), <Servicos.ServicosService>(), <Anexos.AnexosService>(), <Auditoria.AuditoriaService>()` — cada classe criada **vazia** (`public sealed class XService(DbSessaoFactory sessoes);`) no arquivo `<Modulo>Service.cs` da pasta, para T2–T7 preencherem sem tocar `Endpoints.cs`. `MapEndpoints`: `+ api.MapViagensOperacoesEndpoints(); api.MapBuscaEndpoints(); api.MapPendenciasEndpoints(); api.MapServicosEndpoints(); api.MapAnexosEndpoints(); api.MapAuditoriaEndpoints();` — cada `Map*` criado vazio (`return app;`).
  - `ReservaDto.SituacaoComissao` calculado no SQL a partir de `vw_reserva_financeiro f` (join por `reserva_id`):
    ```sql
    case when f.valor_esperado_operadora = 0 then 'nao_prevista'
         when f.conciliacao_encerrada and f.recebido_operadora < f.valor_esperado_operadora then 'divergente'
         when not f.aguardando_operadora then 'recebida'
         when f.recebido_operadora > 0 then 'parcial'
         when r.data_prevista_comissao < current_date then 'atrasada'
         else 'a_receber' end as SituacaoComissao
    ```
  - `ViagemDto.AgenteNome` via `left join usuario ag on ag.id = v.agente_id`; `ResumoViagemDto.ReceitaRecebida/RepasseStatus` de `vw_resultado_viagem`.
  - Migration 0014:
    ```sql
    -- Fase 3.3 — anexos em dois passos (presign → upload → confirmar) e apoio à lista/busca
    alter table anexo add column confirmado_em timestamptz;
    create index ix_anexo_pendente on anexo (criado_em) where confirmado_em is null and excluido_em is null;
    create index ix_viagem_agencia_cancelada on viagem (agencia_id, cancelada) where excluido_em is null;
    create index ix_pendencia_viagem_origem on pendencia (viagem_id, origem, status);
    ```
    (RLS já cobre `anexo`; grants por `alter default privileges` de 0002.)
  - `MeridianoApiFactory.ConfigureWebHost`: `builder.UseSetting("Armazenamento:Endpoint", "http://localhost:9000"); ("Armazenamento:Bucket", "meridiano-teste"); ("Armazenamento:AccessKey", "teste"); ("Armazenamento:SecretKey", "teste-secret");`
  - `docker-compose.yml`:
    ```yaml
      minio:
        image: minio/minio:latest
        command: server /data --console-address ":9001"
        environment: { MINIO_ROOT_USER: meridiano, MINIO_ROOT_PASSWORD: meridiano123 }
        ports: ["9000:9000", "9001:9001"]
        volumes: [miniodata:/data]
      minio-init:
        image: minio/mc:latest
        depends_on: [minio]
        entrypoint: >
          /bin/sh -c "until mc alias set local http://minio:9000 meridiano meridiano123; do sleep 1; done; mc mb -p local/meridiano-dev; exit 0"
    volumes: { pgdata: , miniodata: }
    ```
    `appsettings.Development.json`: `"Armazenamento": { "Endpoint": "http://localhost:9000", "Bucket": "meridiano-dev", "AccessKey": "meridiano", "SecretKey": "meridiano123" }`. `appsettings.json`: seção com strings vazias (produção via env `Armazenamento__*`).

- [ ] **Step 1: Testes**

`RotinasTests.cs` (usa `DbSessaoFactory` direto, como `GuardasTests`):
```csharp
[Collection("db")]
public sealed class RotinasTests(PostgresFixture pg)
{
    private static readonly CancellationToken Ct = CancellationToken.None;

    [Fact]
    public async Task Limpar_volta_cancela_posviagem_e_recompra_e_mantem_checkin()
    {
        var a = await pg.InserirAgenciaAsync("rot-a");
        var u = await pg.InserirUsuarioAsync(a, "ag@rot-a.com", null, "agente");
        var c = await pg.InserirClienteAsync(a, "Carlos"); var f = await pg.InserirFornecedorAsync(a, "CVC");
        var v = await pg.InserirViagemCompletaAsync(a, u, c, f, new DateOnly(2026, 4, 18), new DateOnly(2026, 4, 28));
        var factory = new DbSessaoFactory(pg.ConnApi);
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, u, null), Ct))
        { await Rotinas.GerarPendenciasAsync(s, a, v, new DateOnly(2026, 4, 18), new DateOnly(2026, 4, 28), u, Ct); await s.ConfirmarAsync(Ct); }
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, u, null), Ct))
        { await Rotinas.GerarPendenciasAsync(s, a, v, new DateOnly(2026, 4, 18), null, u, Ct); await s.ConfirmarAsync(Ct); }
        var rows = (await pg.QueryOwnerAsync<(string Chave, string Status)>("select chave_unica, status from pendencia where viagem_id = @v order by chave_unica", new { v })).ToList();
        Assert.Equal([($"{v}:checkin", "aberta"), ($"{v}:posviagem", "cancelada"), ($"{v}:recompra", "cancelada")], rows);
    }

    [Fact]
    public async Task Cancelar_e_transferir_automaticas_nao_tocam_manuais()
    {
        var a = await pg.InserirAgenciaAsync("rot-b");
        var u1 = await pg.InserirUsuarioAsync(a, "a1@rot-b.com", null, "agente"); var u2 = await pg.InserirUsuarioAsync(a, "a2@rot-b.com", null, "agente");
        var c = await pg.InserirClienteAsync(a, "Carlos"); var f = await pg.InserirFornecedorAsync(a, "CVC");
        var v = await pg.InserirViagemCompletaAsync(a, u1, c, f);
        var auto = await pg.InserirPendenciaAsync(a, v, "Check-in", new DateOnly(2026, 4, 15), u1, "automatica", $"{v}:checkin");
        var manual = await pg.InserirPendenciaAsync(a, v, "Ligar", new DateOnly(2026, 4, 1), u1);
        var factory = new DbSessaoFactory(pg.ConnApi);
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, u1, null), Ct))
        { await Rotinas.TransferirPendenciasAutomaticasAsync(s, a, v, u2, Ct); await s.ConfirmarAsync(Ct); }
        Assert.Equal(u2, (await pg.QueryOwnerAsync<Guid>("select responsavel_id from pendencia where id = @auto", new { auto })).Single());
        Assert.Equal(u1, (await pg.QueryOwnerAsync<Guid>("select responsavel_id from pendencia where id = @manual", new { manual })).Single());
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, u1, null), Ct))
        { await Rotinas.CancelarPendenciasAutomaticasAsync(s, a, v, Ct); await s.ConfirmarAsync(Ct); }
        Assert.Equal(["aberta", "cancelada"], (await pg.QueryOwnerAsync<string>("select status from pendencia where id in (@manual, @auto) order by origem", new { manual, auto })).ToList());
    }
}
```

`ArmazenamentoTests.cs` (sem rede):
```csharp
public sealed class ArmazenamentoTests
{
    private static readonly ArmazenamentoS3 S3 = new(new ArmazenamentoOpcoes("http://localhost:9000", "meridiano-teste", "teste", "teste-secret"));

    [Fact]
    public void Url_de_upload_e_assinada_path_style_com_bucket_e_caminho()
    {
        var url = S3.UrlParaEnviar("ag/2026/x/voucher.pdf", "application/pdf", TimeSpan.FromMinutes(5));
        Assert.StartsWith("http://localhost:9000/meridiano-teste/ag/2026/x/voucher.pdf?", url);
        Assert.Contains("X-Amz-Signature=", url); Assert.Contains("X-Amz-Expires=300", url);
    }

    [Fact]
    public void Url_de_download_forca_attachment_com_nome()
    {
        var url = S3.UrlParaBaixar("ag/2026/x/voucher.pdf", "voucher cvc.pdf", TimeSpan.FromMinutes(2));
        Assert.Contains("response-content-disposition=", url); Assert.Contains("voucher%20cvc.pdf", url);
    }
}
```
`MigrationsTests.cs`: `+ Assert.True(await ColunaExiste("anexo", "confirmado_em"))` no padrão existente do arquivo (ver como as outras asserções de coluna/índice são feitas e copiar). Leitura estendida é coberta pelos testes de T2/T3 (JSON contém `situacaoComissao`, `agenteNome`, `receitaRecebida`).

- [ ] **Step 2: Rodar para ver falhar** — `cd backend && dotnet test --filter "FullyQualifiedName~RotinasTests|FullyQualifiedName~ArmazenamentoTests"` → erro de compilação.

- [ ] **Step 3: Migration 0014, `Guardas`, `Rotinas`**

`Rotinas.GerarPendenciasAsync` — depois do `foreach` de upsert:
```csharp
await s.Conexao.ExecuteAsync(new CommandDefinition(
    "update pendencia set status = 'cancelada' where agencia_id = @agenciaId and viagem_id = @viagemId and origem = 'automatica' and status = 'aberta' and chave_unica <> all(@chaves)",
    new { agenciaId, viagemId, chaves = itens.Select(i => i.Chave).ToArray() }, s.Transacao, cancellationToken: ct));
```
```csharp
public static Task CancelarPendenciasAutomaticasAsync(DbSessao s, Guid agenciaId, Guid viagemId, CancellationToken ct) =>
    s.Conexao.ExecuteAsync(new CommandDefinition(
        "update pendencia set status = 'cancelada' where agencia_id = @agenciaId and viagem_id = @viagemId and origem = 'automatica' and status = 'aberta'",
        new { agenciaId, viagemId }, s.Transacao, cancellationToken: ct));

public static Task TransferirPendenciasAutomaticasAsync(DbSessao s, Guid agenciaId, Guid viagemId, Guid novoResponsavel, CancellationToken ct) =>
    s.Conexao.ExecuteAsync(new CommandDefinition(
        "update pendencia set responsavel_id = @novoResponsavel where agencia_id = @agenciaId and viagem_id = @viagemId and origem = 'automatica' and status = 'aberta'",
        new { agenciaId, viagemId, novoResponsavel }, s.Transacao, cancellationToken: ct));
```
`Guardas.TravarViagemDaReservaAsync`:
```csharp
public static async Task<(Guid ViagemId, string Versao)> TravarViagemDaReservaAsync(DbSessao s, Guid reservaId, Guid agenciaId, string? versaoEsperada, CancellationToken ct)
{
    var viagemId = await s.Conexao.ExecuteScalarAsync<Guid?>(new CommandDefinition(
        "select viagem_id from reserva where id = @reservaId and agencia_id = @agenciaId and excluido_em is null", new { reservaId, agenciaId }, s.Transacao, cancellationToken: ct))
        ?? throw new RegraDeNegocioException("nao_encontrado", "Reserva não encontrada");
    return (viagemId, await TravarViagemAsync(s, viagemId, agenciaId, versaoEsperada, ct));
}
```

- [ ] **Step 4: DTOs e `ViagemLeitura`** — acrescentar os campos do Contrato; a query de reservas passa a `join vw_reserva_financeiro f on f.reserva_id = r.id` e seleciona `r.comissao_mantida, r.cancelada_em, r.motivo_cancelamento, r.desfecho_cancelamento, r.valor_reembolso, r.nfse_tomador, r.nfse_numero, r.nfse_data_emissao, r.conciliacao_encerrada, f.recebido_operadora, <case SituacaoComissao>`; `ReservaRow.ParaDto(verValores)` zera `ValorReembolso`/`RecebidoOperadora` sem permissão. Cabeçalho: `+ ag.nome as AgenteNome, v.cancelada_em as CanceladaEm, v.motivo_cancelamento as MotivoCancelamento`. Resumo: `+ receita_recebida as ReceitaRecebida, repasse_status as RepasseStatus`. Atualizar os testes de 3.2 que constroem `ReservaDto`/`ViagemDto` por posição (procurar `new ReservaDto(` em `src/` e `tests/`; os DTOs locais dos testes são records próprios e não quebram).

- [ ] **Step 5: Storage**

`ArmazenamentoS3.cs`:
```csharp
using Amazon.Runtime; using Amazon.S3; using Amazon.S3.Model;

public sealed class ArmazenamentoS3 : IArmazenamentoArquivo
{
    private readonly AmazonS3Client _s3; private readonly string _bucket;
    public ArmazenamentoS3(ArmazenamentoOpcoes o)
    {
        _bucket = o.Bucket;
        _s3 = new AmazonS3Client(new BasicAWSCredentials(o.AccessKey, o.SecretKey),
            new AmazonS3Config { ServiceURL = o.Endpoint, ForcePathStyle = true, AuthenticationRegion = o.Regiao, RequestChecksumCalculation = RequestChecksumCalculation.WHEN_REQUIRED });
    }
    public string UrlParaEnviar(string caminho, string? mimeType, TimeSpan validade) =>
        _s3.GetPreSignedURL(new GetPreSignedUrlRequest { BucketName = _bucket, Key = caminho, Verb = HttpVerb.PUT, Expires = DateTime.UtcNow.Add(validade), ContentType = mimeType, Protocol = Protocolo() });
    public string UrlParaBaixar(string caminho, string nomeArquivo, TimeSpan validade)
    {
        var req = new GetPreSignedUrlRequest { BucketName = _bucket, Key = caminho, Verb = HttpVerb.GET, Expires = DateTime.UtcNow.Add(validade), Protocol = Protocolo() };
        req.ResponseHeaderOverrides.ContentDisposition = $"attachment; filename*=UTF-8''{Uri.EscapeDataString(nomeArquivo)}";
        return _s3.GetPreSignedURL(req);
    }
    public Task ExcluirAsync(string caminho, CancellationToken ct) => _s3.DeleteObjectAsync(_bucket, caminho, ct);
    private Protocol Protocolo() => _s3.Config.ServiceURL.StartsWith("https", StringComparison.OrdinalIgnoreCase) ? Protocol.HTTPS : Protocol.HTTP;
}
```
Se `RequestChecksumCalculation` não existir na versão instalada, remover a linha (é só para R2 não recusar checksum). `AddArmazenamento`: `var o = b.Configuration.GetSection("Armazenamento"); b.Services.AddSingleton<IArmazenamentoArquivo>(new ArmazenamentoS3(new ArmazenamentoOpcoes(o["Endpoint"] ?? "", o["Bucket"] ?? "", o["AccessKey"] ?? "", o["SecretKey"] ?? "", o["Regiao"] ?? "auto")));` — sem endpoint configurado, presign ainda calcula (URL inválida só em uso real); documentar em `scripts/dev.md` (T15). `csproj`: `<PackageReference Include="AWSSDK.S3" Version="4.*" />`.

- [ ] **Step 6: Esqueletos + `Endpoints.cs` + fixture** — conforme Interfaces. Fixture `InserirViagemCompletaAsync` reutiliza `InserirViagemAsync`/`InserirPassageiroAsync`/`InserirReservaAsync` existentes (acrescentar parâmetros `ida`, `volta`, `agenteId` a `InserirViagemAsync` com defaults compatíveis).

- [ ] **Step 7: Rodar tudo** — `cd backend && dotnet build -c Release && dotnet test && dotnet format --verify-no-changes` → 0 falhas (106 + 4 novos API; 21 domínio).

- [ ] **Step 8: Reportar arquivos tocados.** Commit sugerido: `feat(base): migration 0014, extended trip read model, orphan pendencias, S3 presign storage, module skeletons for 3.3`

---

### Task 2 (backend): Lista de viagens e busca global

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Viagens/ViagemListaDtos.cs`; Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagensLista.cs` (esqueleto de T1)
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagensConsultas.cs` (escape de `ilike`, `excetoViagemId`, escopo de `duplicada`), `backend/src/Meridiano.Api/Modules/Viagens/ViagensEndpoints.cs` (`GET /viagens`, ajustes de `semelhantes`/`duplicada`)
- Modify: `backend/src/Meridiano.Api/Modules/Pessoas/PessoasService.cs` (escape de `ilike`)
- Create: `backend/src/Meridiano.Api/Modules/Comum/Sql.cs` (`EscaparLike`)
- Create: `backend/src/Meridiano.Api/Modules/Busca/{BuscaDtos.cs,BuscaService.cs}`; Modify: `BuscaEndpoints.cs` (esqueleto de T1)
- Create: `backend/tests/Meridiano.Api.Tests/ViagensListaTests.cs`, `backend/tests/Meridiano.Api.Tests/BuscaTests.cs`

**Depends-on:** T1

**Interfaces:**
- Produces:
```csharp
public static class Sql { public static string EscaparLike(string s) => s.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_"); }
// padrão: "… ilike @padrao escape '\\'" com padrao = $"%{Sql.EscaparLike(q)}%"
public sealed class ViagensLista(DbSessaoFactory sessoes)
{ public Task<ListaViagensDto> ListarAsync(ContextoSessao ctx, Guid? apenasVendedor, FiltroViagens f, CancellationToken ct); }
public sealed class BuscaService(DbSessaoFactory sessoes)
{ public Task<BuscaDto> BuscarAsync(ContextoSessao ctx, UsuarioAtual u, string q, CancellationToken ct); }
// ViagensConsultas
Task<IReadOnlyList<ViagemSemelhanteDto>> SemelhantesAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid clienteId, DateOnly? ida, DateOnly? volta, Guid? excetoViagemId, CancellationToken ct)
Task<(Guid ViagemId, string Codigo)?> ReservaDuplicadaAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid fornecedorId, string localizador, CancellationToken ct)
```
  - Rotas: `GET /viagens` (`RequireAuthorization`; sem `ViagemVer`/`ViagemVerProprias` → 403 como em `GET /{id}`; `apenasVendedor = u.Pode(ViagemVer) ? null : u.UsuarioId`); `FiltroViagens` via `[AsParameters]`; `GET /busca` (`RequireAuthorization`, mesma regra). `GET /viagens/semelhantes` ganha `excetoViagemId`; `GET /reservas/duplicada` passa `apenasVendedor`.
  - `ListarAsync`: `Tamanho` fora de 1..100 → 100; `Pagina < 1` → 1; `Aba` fora da lista → 422 `aba_invalida`; `Ordem` fora de `ida|codigo|venda` → 422 `ordem_invalida`; `Direcao` ∈ `asc|desc` (default `desc`). Query base (CTE `base`) com todos os filtros **exceto** `aba`; contadores = `count(*) filter (...)` sobre `base`; itens = `base` + filtro da aba + ordem + `limit/offset`; `total` = count da aba.
    ```sql
    with base as (
      select v.id, v.codigo, v.destino, v.tipo, v.data_ida, v.data_volta, v.cancelada, u.nome as vendedor, t.nome as titular,
             f.fase_operacional, f.fase_financeira, r.venda_total, r.receita_prevista
        from viagem v
        join usuario u on u.id = v.vendedor_id
        join vw_fase_viagem f on f.viagem_id = v.id
        join vw_resultado_viagem r on r.viagem_id = v.id
        left join vw_viagem_titular t on t.viagem_id = v.id
       where v.agencia_id = @agencia and v.excluido_em is null
         and (@apenasVendedor::uuid is null or v.vendedor_id = @apenasVendedor)
         and (@vendedorId::uuid is null or v.vendedor_id = @vendedorId)
         and (@tipo::text is null or v.tipo = @tipo)
         and (@idaDe::date is null or v.data_ida >= @idaDe) and (@idaAte::date is null or v.data_ida <= @idaAte)
         and (cardinality(@fornecedorId::uuid[]) = 0 or exists (select 1 from reserva x where x.viagem_id = v.id and x.excluido_em is null and x.fornecedor_id = any(@fornecedorId)))
         and (@nfse::text is null or exists (select 1 from reserva x where x.viagem_id = v.id and x.excluido_em is null and x.nfse_status = @nfse))
         and (@compraDe::date is null or exists (select 1 from reserva x where x.viagem_id = v.id and x.excluido_em is null and x.data_compra >= @compraDe))
         and (@compraAte::date is null or exists (select 1 from reserva x where x.viagem_id = v.id and x.excluido_em is null and x.data_compra <= @compraAte))
         and (@padrao::text is null or v.destino ilike @padrao escape '\' or v.codigo ilike @padrao escape '\' or t.nome ilike @padrao escape '\'
              or exists (select 1 from reserva x where x.viagem_id = v.id and x.excluido_em is null and x.localizador ilike @padrao escape '\'))
    )
    select count(*) as Todas,
           count(*) filter (where fase_operacional = 'em_emissao') as EmEmissao,
           count(*) filter (where data_ida between current_date and current_date + 7 and not cancelada) as EmbarcamSemana,
           count(*) filter (where fase_financeira = 'atrasada') as ComissaoAtrasada,
           count(*) filter (where fase_operacional = 'concluida') as Concluidas
      from base;
    ```
    Filtro da aba (segunda query, sobre a mesma CTE): `em_emissao → fase_operacional = 'em_emissao'` · `embarcam_semana → data_ida between current_date and current_date + 7 and not cancelada` · `comissao_atrasada → fase_financeira = 'atrasada'` · `concluidas → fase_operacional = 'concluida'` · `todas → sem filtro`. Ordem: `ida → data_ida {dir} nulls last, codigo desc` · `codigo → codigo {dir}` · `venda → venda_total {dir}`. `VendaTotal`/`ReceitaPrevista` nulos sem `ReservaVerValores` (montar o DTO com `verValores ? x : null`).
  - `BuscarAsync`: `q.Trim().Length < 2` → 422 `busca_curta`. Clientes só se `u.Pode(ClienteVer) || u.Pode(ClienteVerProprios)`; com só `ClienteVerProprios`: `exists (select 1 from viagem_passageiro vp join viagem v on v.id = vp.viagem_id where vp.cliente_id = c.id and v.vendedor_id = @usuario and v.excluido_em is null)`. Viagens: `destino/codigo/titular ilike`, `apenasVendedor`, `order by data_ida desc nulls last limit 5`. Reservas: `localizador ilike`, join viagem/fornecedor, `apenasVendedor`, `limit 5`. Arrays vazios, nunca null.

- [ ] **Step 1: Testes**

`ViagensListaTests.cs` (helpers `LogadoAsync`/`Cenario` copiados de `ViagensCriarTests`; dados via `pg.InserirViagemCompletaAsync` + `InserirReservaAsync` + `QueryOwnerAsync` para datas/cancelamento):
```csharp
[Fact] public async Task Lista_pagina_ordena_e_conta_abas()
// 3 viagens: A ida hoje+3 (emitida), B ida hoje+40 (reserva pendente → em_emissao), C data_volta ontem (concluida, prevista ontem sem movimento → fase_financeira atrasada)
// GET /viagens?tamanho=2 → 2 itens, total 3, contadores {todas 3, emEmissao 1, embarcamSemana 1, comissaoAtrasada 1, concluidas 1}; pagina=2 → 1 item
// GET /viagens?aba=comissao_atrasada → só C; ?ordem=codigo&direcao=asc → códigos crescentes; ?aba=xyz → 422 aba_invalida

[Fact] public async Task Filtros_por_fornecedor_nfse_compra_e_texto()
// viagem X com reserva CVC loc "K7X2PQ" nfse falta_emitir data_compra 2026-03-10; viagem Y com reserva Decolar nfse emitido 2026-04-01
// ?fornecedorId=cvc → só X; ?nfse=emitido → só Y; ?compraDe=2026-04-01 → só Y; ?q=k7x → só X; ?q=%25 → 0 itens (escape); ?q=<titular de Y> → só Y

[Fact] public async Task Vendedor_externo_ve_so_as_suas_e_sem_valores()
// externa com senha; 2 viagens (uma dela); GET /viagens como externa → 1 item, JSON sem "vendaTotal"; contador todas = 1

[Fact] public async Task Contador_le_lista_com_valores_e_agente_sem_resultado_ainda_ve_venda()
// contador (ViagemVer + ReservaVerValores) → JSON contém "vendaTotal"; agente também (ReservaVerValores); nenhum dos dois recebe campo de resultado (lista não expõe resultado)
```
`BuscaTests.cs`:
```csharp
[Fact] public async Task Busca_agrupa_clientes_viagens_e_reservas_e_exige_2_chars()
// cliente "Carlos Mendes"; viagem Lisboa (titular Carlos) com reserva loc "K7X2PQ"; GET /busca?q=carl → clientes 1, viagens 1 (titular), reservas 0; ?q=k7x → reservas 1 com codigo da viagem; ?q=c → 422

[Fact] public async Task Vendedor_externo_so_ve_o_que_e_dele()
// duas viagens (uma da externa); busca pelo destino comum → viagens 1; clientes só os das viagens dela (o outro titular não aparece)
```
Escrever cada teste completo (login, seeds, asserções acima).

- [ ] **Step 2: Rodar para ver falhar.**

- [ ] **Step 3: Implementar** `Sql.EscaparLike`, `ViagensLista.ListarAsync` (SQL acima; Dapper com `uuid[]` via `Guid[]`), `BuscaService`, ajustes em `ViagensConsultas` (`excetoViagemId`: `and (@excetoViagemId::uuid is null or v.id <> @excetoViagemId)`; `duplicada`: `and (@apenasVendedor::uuid is null or v.vendedor_id = @apenasVendedor)`), `PessoasService.BuscarAsync` e `FornecedoresService.ListarAsync`? (só Pessoas usa `ilike`) com escape, endpoints. `ViagensLista` já está registrada por T1 (esqueleto vazio em `ViagensLista.cs`; T2 preenche). Qualquer classe nova de T2–T7 **não** prevista nos esqueletos deve ser `static` (recebe `DbSessaoFactory` por parâmetro) — `Endpoints.cs` não é tocado depois de T1.

- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(viagens): paginated list with tabs/filters/counters, global search, like escaping, scoped duplicate lookup`

---

### Task 3 (backend): Operações — cancelar reserva/viagem, crédito, remarcação, NFSe, transferir

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Viagens/OperacoesDtos.cs`, `backend/src/Meridiano.Api/Modules/Viagens/ReservaOperacoes.cs`, `backend/src/Meridiano.Api/Modules/Viagens/Creditos.cs`, `backend/src/Meridiano.Api/Modules/Comum/SemPermissaoException.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagensOperacoes.cs` (esqueleto de T1 → serviço), `backend/src/Meridiano.Api/Modules/Viagens/ViagensOperacoesEndpoints.cs` (esqueleto → rotas), `backend/src/Meridiano.Api/Modules/Viagens/ReservaGravacao.cs` (R2), `backend/src/Meridiano.Api/Modules/Viagens/ViagensService.cs` (`sem_permissao_vendedor` → `SemPermissaoException`), `backend/src/Meridiano.Api/Modules/Viagens/ViagensEdicao.cs` (`AjustarRepasseValorAsync`: pago + valor diferente → 422 `repasse_pago`), `backend/src/Meridiano.Api/Infra/TratadorDeExcecoes.cs` (`SemPermissaoException` → 403 `sem_permissao` + extensão `permissao`)
- Create: `backend/tests/Meridiano.Api.Tests/ViagensOperacoesTests.cs`, `backend/tests/Meridiano.Api.Tests/CreditosTests.cs`
- Modify: `backend/tests/Meridiano.Api.Tests/ViagensEditarTests.cs` (+ `reserva_cancelada`; troca de vendedor sem permissão agora 403)

**Depends-on:** T1

**Interfaces:**
- Produces:
```csharp
public sealed class SemPermissaoException(Permissao permissao) : Exception($"Requer {permissao.Chave()}") { public Permissao Permissao { get; } = permissao; }
// TratadorDeExcecoes: SemPermissaoException → 403, codigo "sem_permissao", extensions["permissao"] = e.Permissao.Chave()

public sealed class ViagensOperacoes(DbSessaoFactory sessoes)
{
    public Task<ViagemDto> CancelarReservaAsync(ContextoSessao ctx, UsuarioAtual u, Guid reservaId, CancelarReservaRequest req, CancellationToken ct);
    public Task<ViagemDto> CancelarViagemAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, CancelarViagemRequest req, CancellationToken ct);
    public Task<ViagemDto> RemarcarAsync(ContextoSessao ctx, UsuarioAtual u, Guid reservaId, RemarcarRequest req, CancellationToken ct);
    public Task<ViagemDto> DefinirNfseAsync(ContextoSessao ctx, UsuarioAtual u, Guid reservaId, NfseRequest req, CancellationToken ct);
    public Task<ViagemDto> TransferirAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, TransferirRequest req, CancellationToken ct);
    public Task<ViagemDto> ConsumirCreditoAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, ConsumirCreditoRequest req, CancellationToken ct);
    public Task<IReadOnlyList<CreditoDto>> ListarCreditosAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, CancellationToken ct);
    public Task<IReadOnlyList<ReservaAlteracaoDto>> ListarAlteracoesAsync(ContextoSessao ctx, UsuarioAtual u, Guid reservaId, CancellationToken ct);
}
// ReservaOperacoes (static, dentro da transação; chamador já travou a viagem)
public static Task CancelarAsync(DbSessao s, ContextoSessao ctx, Guid viagemId, Guid reservaId, string motivo, string desfecho, decimal? valorReembolso, bool comissaoMantida, CreditoRequest? credito, bool podeEditarFechado, CancellationToken ct)
// Creditos (static)
public static Task<Guid> CriarAsync(DbSessao s, ContextoSessao ctx, Guid viagemId, Guid reservaOrigemId, Guid fornecedorId, CreditoRequest c, CancellationToken ct)
public static Task ConsumirAsync(DbSessao s, ContextoSessao ctx, Guid viagemId, Guid creditoId, Guid reservaId, CancellationToken ct)
```
  - **Ordem de locks** (vale para todas as operações abaixo, mesmo padrão de `ViagensService.AtualizarAsync`): ler `data_compra` das reservas afetadas **sem lock** → `Guardas.CompetenciaAbertaAsync` para cada → `TravarViagemAsync`/`TravarViagemDaReservaAsync(versao)` → revalidar competência com os dados travados → escrever → `Rotinas.ReavaliarRepasseAsync` → `Rotinas.GerarPendenciasAsync` (só quando datas mudam) → `Guardas.TocarViagemAsync` (quando `viagem` não foi atualizada) → `ViagemLeitura.CarregarAsync(ProjecaoDe(u))` → `ConfirmarAsync`.
  - **`ReservaOperacoes.CancelarAsync`** — validações: `motivo` vazio → 422 `motivo_obrigatorio`; `desfecho ∉ {sem_reembolso, reembolso, credito}` → `desfecho_invalido`; `reembolso` sem `valorReembolso ≥ 0` → `valor_invalido`; `credito` sem `credito` ou `Valor <= 0` → `credito_valor_invalido`; reserva (`select status, data_compra, fornecedor_id … for update`) inexistente → `reserva_nao_encontrada`; `cancelada` → `reserva_cancelada`; `CompetenciaAbertaAsync(data_compra)`; `update reserva set status = 'cancelada', cancelada_em = now(), motivo_cancelamento, desfecho_cancelamento, valor_reembolso (só se reembolso), comissao_mantida`; `credito` → `Creditos.CriarAsync`.
  - **`CancelarViagemAsync`** — viagem `cancelada` → 422 `viagem_cancelada`; ativas = `select id from reserva where viagem_id and agencia_id and excluido_em is null and status <> 'cancelada'`; ativa ausente de `req.Reservas` → 422 `reservas_ativas` (mensagem lista os ids); item que não é ativa da viagem → `reserva_nao_encontrada`; cada item → `ReservaOperacoes.CancelarAsync(motivo = req.Motivo)`; `update viagem set cancelada = true, cancelada_em = now(), motivo_cancelamento = @motivo`; `Rotinas.CancelarPendenciasAutomaticasAsync`; reavaliar; carregar.
  - **`RemarcarAsync`** — `Descricao` vazia → `descricao_obrigatoria`; `MultaCliente < 0` ou `ValorNovo < 0` → `valor_negativo`; `NovaDataVolta < NovaDataIda` (considerando as atuais quando só uma vem) → `datas_incoerentes`; reserva cancelada → `reserva_cancelada`; `ValorNovo` → competência de `data_compra`; `insert into reserva_alteracao (agencia_id, reserva_id, data_alteracao, descricao, valor_anterior, valor_novo, multa_cliente, usuario_id)` (`valor_anterior = valor_total` atual só quando `ValorNovo` vem); `update reserva set valor_total = @ValorNovo` quando vem; datas novas → `update viagem set data_ida = coalesce(@ida, data_ida), data_volta = coalesce(@volta, data_volta)` + `GerarPendenciasAsync(ida, volta, agente_id)`; reavaliar; tocar se `viagem` não mudou; carregar.
  - **`DefinirNfseAsync`** — `Status ∉ {falta_emitir, emitido, nao_precisa}` ou `Tomador ∉ {cliente, operadora, null}` → `nfse_invalida`; `emitido` sem `Numero` ou `DataEmissao` → `nfse_incompleta`; lock; `update reserva set nfse_status, nfse_tomador, nfse_numero, nfse_data_emissao`; tocar; carregar. Gate no endpoint: `u.Pode(ViagemEditar) || u.Pode(FinanceiroMovimentar)` senão 403.
  - **`TransferirAsync`** — `ReferenciaAsync(Usuario, AgenteId, exigirAtivo)`; lock; igual ao atual → `agente_igual`; `update viagem set agente_id`; `Rotinas.TransferirPendenciasAutomaticasAsync`; carregar.
  - **`Creditos.CriarAsync`** — cliente = `c.ClienteId ?? titular (vw_viagem_titular)`; informado e não passageiro → `credito_cliente_invalido`; `insert into credito (agencia_id, cliente_id, fornecedor_id, reserva_origem_id, valor, validade) returning id`.
  - **`Creditos.ConsumirAsync`** — reserva da viagem (`reserva_nao_encontrada`), não cancelada (`reserva_cancelada`); `select cliente_id, fornecedor_id, status, (validade is not null and validade < current_date) as Vencido from credito where id and agencia_id and excluido_em is null for update` → nulo → `nao_encontrado`; cliente não passageiro → `credito_cliente_invalido`; fornecedor ≠ → `credito_fornecedor_diferente`; `Vencido` → `credito_expirado`; `update credito set status = 'utilizado', reserva_uso_id = @reservaId where id and agencia_id and status = 'disponivel'` → 0 linhas → `credito_indisponivel`.
  - **`ListarCreditosAsync`** — `disponivel` (validade nula ou ≥ `current_date`) dos passageiros da viagem **mais** os `utilizado` por reservas desta viagem; `CodigoViagemOrigem` por `reserva_origem_id → viagem.codigo`; ordem `status, validade nulls last`.
  - **`ListarAlteracoesAsync`** — `order by data_alteracao desc, criado_em desc`; visibilidade da viagem.
  - **R2** em `ReservaGravacao.AtualizarAsync`: o `select` inicial traz `status`; `cancelada` → 422 `reserva_cancelada`.
  - Rotas (`ViagensOperacoesEndpoints.cs`, `RequerPermissao(ViagemEditar)` salvo indicado): `POST /viagens/{id:guid}/cancelar` · `POST /viagens/{id:guid}/transferir` (`ViagemTransferir`) · `GET /viagens/{id:guid}/creditos` (visibilidade, como `GET /viagens/{id}`) · `POST /viagens/{id:guid}/creditos/consumir` · `POST /reservas/{id:guid}/cancelar` · `POST /reservas/{id:guid}/remarcar` · `PUT /reservas/{id:guid}/nfse` (gate manual) · `GET /reservas/{id:guid}/alteracoes` (visibilidade).

- [ ] **Step 1: Testes** (`ViagensOperacoesTests.cs`; cenário com dono `dono@`, agente `ag@`, financeiro `fin@`, contador `ct@`, externa `ana@` com senha, Carlos titular + Lúcia, CVC (10 %, janelas) e Decolar; viagem criada via `POST /viagens` pelo agente com 2 reservas (`Reserva1` de `ViagensCriarTests`) e vendedora externa com repasse 300; helper `VersaoAsync(http, id)` lê `GET /viagens/{id}`)
```csharp
[Fact] public async Task Cancelar_reserva_com_credito_zera_previsto_cria_credito_e_mantem_repasse_bloqueado()
// POST /reservas/{r1}/cancelar { motivo "cliente desistiu", desfecho "credito", comissaoMantida false, credito { valor 9000, validade 2027-03-01 }, versao }
// → 200; r1: status cancelada, receitaPrevista 0, valorEsperadoOperadora 0, desfechoCancelamento "credito", motivoCancelamento; credito no banco: cliente Carlos, fornecedor CVC, reserva_origem_id r1, status disponivel, valor 9000
// repasse "bloqueado" (r2 ainda aguarda); repetir → 422 reserva_cancelada; versao velha → 409

[Fact] public async Task Cancelar_reserva_com_comissao_mantida_preserva_esperado()
// r1 desfecho sem_reembolso, comissaoMantida true → valorEsperadoOperadora 1600 e receitaPrevista 1600 mantidos; status cancelada; faseFinanceira segue a_receber

[Theory] [InlineData("motivo_vazio","motivo_obrigatorio")] [InlineData("desfecho_x","desfecho_invalido")] [InlineData("credito_sem_valor","credito_valor_invalido")] [InlineData("reembolso_sem_valor","valor_invalido")]
public async Task Cancelar_reserva_rejeita_payload_invalido(string caso, string codigo)

[Fact] public async Task Cancelar_reserva_em_competencia_fechada_exige_permissao_e_motivo_de_sessao()
// pg.InserirFechamentoAsync(agencia, mês de data_compra de r1); agente → 422 periodo_fechado; dono (tem FinanceiroEditarPeriodoFechado) sem app.motivo → 422 motivo_obrigatorio (header X-Motivo é 3.5; registrar no BACKLOG)

[Fact] public async Task Cancelar_viagem_exige_todas_as_ativas_e_cancela_pendencias_automaticas()
// POST /viagens/{id}/cancelar { motivo "cliente cancelou", reservas [ { r1, sem_reembolso } ], versao } → 422 reservas_ativas
// com r1 e r2 → 200 cancelada true, canceladaEm, faseOperacional "cancelada", reservas ambas canceladas com motivoCancelamento "cliente cancelou"; pendencia automáticas → cancelada; repetir → 422 viagem_cancelada

[Fact] public async Task Remarcar_grava_alteracao_atualiza_valor_move_datas_e_reabre_pendencia()
// owner: update pendencia checkin set status='concluida', concluida_em=now(); POST /reservas/{r1}/remarcar { dataAlteracao hoje, descricao "voo remarcado", valorNovo 10400, multaCliente 250, novaDataIda 2026-05-02, novaDataVolta 2026-05-12, versao }
// → 200 dataIda 2026-05-02, dataVolta 2026-05-12; r1.valorTotal 10400, ravCliente 100; GET /reservas/{r1}/alteracoes → [ { valorAnterior 10000, valorNovo 10400, multaCliente 250, usuarioNome } ]; pendencia checkin: status aberta, data 2026-04-29; posviagem 2026-05-15

[Fact] public async Task Nfse_aceita_agente_e_financeiro_rejeita_contador_e_emitido_incompleto()
// financeiro: PUT { status emitido, tomador cliente, numero "123", dataEmissao hoje, versao } → 200 nfseStatus emitido, nfseNumero "123"; contador → 403 sem_permissao; agente { status emitido, versao } → 422 nfse_incompleta; { status "x" } → nfse_invalida

[Fact] public async Task Transferir_exige_viagem_transferir_e_move_responsavel_das_automaticas()
// ag2 = novo agente; agente → 403 sem_permissao; dono → 200 agenteId ag2, agenteNome "ag2@…"; pendencias automáticas abertas com responsavel_id ag2; mesmo agente de novo → 422 agente_igual; usuário inativo → 422 usuario_inativo

[Fact] public async Task Put_com_reserva_cancelada_da_422_e_sem_ela_passa()
// cancelar r1; PUT /viagens/{id} reenviando r1 → 422 reserva_cancelada; PUT só com r2 → 200 e r1 continua cancelada com desfecho intacto
```
`CreditosTests.cs`:
```csharp
[Fact] public async Task Consome_credito_uma_unica_vez_e_exige_mesmo_fornecedor()
// pg.InserirCreditoAsync(a, Carlos, CVC, 9000); viagem nova de Carlos com reservas CVC (r) e Decolar (d)
// GET /viagens/{id}/creditos → 1 disponivel; consumir em d → 422 credito_fornecedor_diferente; em r → 200; banco: status utilizado, reserva_uso_id r; de novo → 422 credito_indisponivel; GET → item status utilizado reservaUsoId r
[Fact] public async Task Credito_vencido_e_de_quem_nao_viaja_nao_aparecem_nem_consomem()
// validade ontem → não listado, consumir → 422 credito_expirado; crédito de Pedro (não passageiro) → não listado, consumir → 422 credito_cliente_invalido
[Fact] public async Task Dois_consumos_concorrentes_so_um_vence()
// duas viagens de Carlos com reserva CVC; Task.WhenAll de dois POST consumir do mesmo crédito → um 200 e um 422 credito_indisponivel (ou 409 se o lock da viagem serializar — aceitar {200, 422})
```
Escrever cada teste completo (login, seeds, asserções).

- [ ] **Step 2: Rodar para ver falhar.**

- [ ] **Step 3: `ReservaOperacoes.CancelarAsync` e `Creditos`** (esqueleto obrigatório):
```csharp
public static async Task CancelarAsync(DbSessao s, ContextoSessao ctx, Guid viagemId, Guid reservaId, string motivo, string desfecho, decimal? valorReembolso, bool comissaoMantida, CreditoRequest? credito, bool podeEditarFechado, CancellationToken ct)
{
    if (string.IsNullOrWhiteSpace(motivo)) throw new RegraDeNegocioException("motivo_obrigatorio", "Informe o motivo do cancelamento");
    if (desfecho is not ("sem_reembolso" or "reembolso" or "credito")) throw new RegraDeNegocioException("desfecho_invalido", "Desfecho inválido");
    if (desfecho == "reembolso" && valorReembolso is null or < 0) throw new RegraDeNegocioException("valor_invalido", "Informe o valor do reembolso");
    if (desfecho == "credito" && (credito is null || credito.Valor <= 0)) throw new RegraDeNegocioException("credito_valor_invalido", "Informe o valor do crédito");
    var atual = await s.Conexao.QuerySingleOrDefaultAsync<(string Status, DateOnly DataCompra, Guid FornecedorId)>(new CommandDefinition(
        "select status, data_compra, fornecedor_id from reserva where id = @reservaId and viagem_id = @viagemId and agencia_id = @agencia and excluido_em is null for update",
        new { reservaId, viagemId, agencia = ctx.AgenciaId }, s.Transacao, cancellationToken: ct));
    if (atual == default) throw new RegraDeNegocioException("reserva_nao_encontrada", "Reserva não encontrada nesta viagem");
    if (atual.Status == "cancelada") throw new RegraDeNegocioException("reserva_cancelada", "Reserva já cancelada");
    await Guardas.CompetenciaAbertaAsync(s, ctx.AgenciaId, atual.DataCompra, podeEditarFechado, ctx.Motivo, ct);
    await s.Conexao.ExecuteAsync(new CommandDefinition(
        "update reserva set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = @motivo, desfecho_cancelamento = @desfecho, valor_reembolso = @valorReembolso, comissao_mantida = @comissaoMantida where id = @reservaId and agencia_id = @agencia",
        new { reservaId, agencia = ctx.AgenciaId, motivo = motivo.Trim(), desfecho, valorReembolso = desfecho == "reembolso" ? valorReembolso : null, comissaoMantida }, s.Transacao, cancellationToken: ct));
    if (desfecho == "credito") await Creditos.CriarAsync(s, ctx, viagemId, reservaId, atual.FornecedorId, credito!, ct);
}
```
`Creditos.ConsumirAsync` — sequência: reserva (`select fornecedor_id, status from reserva where id = @reservaId and viagem_id = @viagemId and agencia_id = @agencia and excluido_em is null`) → crédito `for update` com `Vencido` calculado no SQL → passageiro (`exists viagem_passageiro`) → fornecedor → vencido → `update … where status = 'disponivel'` → `n == 0` → `credito_indisponivel`.

- [ ] **Step 4: `ViagensOperacoes`, endpoints, R2, `SemPermissaoException`.** Se `ViagensOperacoes.cs` passar de 350 linhas, mover NFSe/transferir/listagens para `ViagensOperacoesLeitura.cs` (`partial class` na mesma pasta).

- [ ] **Step 5: Rodar tudo; format.** Commit sugerido: `feat(viagens): cancel reserva/viagem with desfecho and credito, single-use credit consumption, remarcacao, nfse, agent transfer; cancelled reserva immutable; 403 for permission gates`

---

### Task 4 (backend): `Modules/Pendencias`

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Pendencias/PendenciaDtos.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Pendencias/PendenciasService.cs`, `backend/src/Meridiano.Api/Modules/Pendencias/PendenciasEndpoints.cs` (esqueletos de T1)
- Create: `backend/tests/Meridiano.Api.Tests/PendenciasTests.cs`

**Depends-on:** T1

**Interfaces:**
```csharp
public sealed class PendenciasService(DbSessaoFactory sessoes)
{
    public Task<IReadOnlyList<PendenciaDto>> ListarDaViagemAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, bool incluirConcluidas, CancellationToken ct);
    public Task<IReadOnlyList<PendenciaDto>> CriarNaViagemAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, NovaPendenciaRequest req, CancellationToken ct);
    public Task<PendenciaDto> AtualizarAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, PendenciaRequest req, CancellationToken ct);
    public Task<PendenciaDto> ConcluirAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, string versao, CancellationToken ct);
    public Task<PendenciaDto> AdiarAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, DateOnly novaData, string versao, CancellationToken ct);
    public Task CancelarAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, CancellationToken ct);
}
```
  - Escopo: só pendências com `viagem_id` (pessoa e agenda são 3.4/3.6). Visibilidade segue a viagem (`ViagemVer` ou `vendedor_id = usuario`).
  - Listar: `status <> 'cancelada'`; sem `incluirConcluidas` → `status = 'aberta'`; `Atrasada = status = 'aberta' and data_prevista < current_date`; `order by data_prevista, prioridade desc, criado_em`; joins `usuario` (responsável), `cliente`, `viagem` (código); `Versao = xmin::text`.
  - Criar: `Titulo` vazio → 422 `titulo_obrigatorio`; `Prioridade ∉ {normal, urgente}` → `prioridade_invalida`; `ResponsavelId` → `ReferenciaAsync(Usuario, exigirAtivo)`, default `agente_id` da viagem ?? `ctx.UsuarioId`; cada `ClienteIds` precisa ser passageiro da viagem senão `passageiro_invalido`; `TravarViagemAsync(id, null)`; sem `ClienteIds` → 1 linha; com N → N linhas (`cliente_id` cada); `origem 'manual'`; devolve as criadas.
  - Atualizar/Concluir/Adiar/Cancelar: `select viagem_id, origem, status, data_prevista, adiada_de from pendencia where id and agencia_id` → nulo → `nao_encontrado`; `cancelada` → `pendencia_cancelada`; `automatica` em Atualizar/Cancelar → `pendencia_automatica`; `TravarViagemAsync(viagem_id, null)`; `update … where id = @id and xmin::text = @versao` → 0 → `ConflitoConcorrenciaException`. Concluir: `status = 'concluida', concluida_em = now()` (já concluída → 422 `pendencia_concluida`). Adiar: `novaData <= data_prevista` → 422 `data_invalida`; `adiada_de = coalesce(adiada_de, data_prevista), data_prevista = @novaData`. Cancelar: `status = 'cancelada'`, sem versão, idempotente.
  - Rotas: `GET /viagens/{id:guid}/pendencias?incluirConcluidas=` (visibilidade) · `POST /viagens/{id:guid}/pendencias` → 201 (corpo = lista; sem `Location`) · `PUT /pendencias/{id:guid}` · `POST /pendencias/{id:guid}/concluir` · `POST /pendencias/{id:guid}/adiar` · `DELETE /pendencias/{id:guid}` → 204 — escritas `ViagemEditar`.

- [ ] **Step 1: Testes** (`PendenciasTests.cs`; viagem via `InserirViagemCompletaAsync` + `InserirPassageiroAsync(Lúcia, titular:false)`):
```csharp
[Fact] public async Task Cria_uma_por_passageiro_ou_uma_na_viagem()
// POST { titulo "Enviar voucher", dataPrevista 2026-04-10, prioridade "normal", clienteIds [Carlos, Lúcia] } → 201 com 2 itens (clienteNome distintos, responsavelId = agente da viagem, origem manual, versao)
// sem clienteIds → 1 item clienteId null; clienteIds com pessoa fora da viagem → 422 passageiro_invalido; titulo "" → titulo_obrigatorio; prioridade "alta" → prioridade_invalida
[Fact] public async Task Lista_abertas_por_padrao_marca_atrasada_e_inclui_concluidas_sob_demanda()
// fixture: A ontem, B amanhã, C concluída (owner update), D cancelada; GET → [A(atrasada true), B]; ?incluirConcluidas=true → [A, B, C]; D nunca
[Fact] public async Task Editar_adiar_concluir_e_cancelar_respeitam_versao()
// PUT { titulo "Novo", …, versao } → 200 titulo "Novo", versao diferente; PUT com versao velha → 409; adiar +5 dias → adiadaDe = data original, dataPrevista nova; adiar para data anterior → 422 data_invalida; concluir → concluida, concluidaEm; concluir de novo → 422 pendencia_concluida; DELETE → 204; GET não lista; concluir cancelada → 422 pendencia_cancelada
[Fact] public async Task Automatica_so_conclui_ou_adia()
// pg.InserirPendenciaAsync(origem "automatica", chave `{v}:checkin`); PUT → 422 pendencia_automatica; DELETE → 422 pendencia_automatica; adiar → 200; concluir → 200
[Fact] public async Task Vendedor_externo_le_as_da_propria_viagem_e_nao_escreve()
// GET própria → 200; alheia → 422 nao_encontrado; POST → 403
```

- [ ] **Step 2–3:** RED → implementar (SQL de listagem numa constante; `PendenciasService.cs` ≤ 350 linhas).

- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(pendencias): trip pendencias (multi-passenger create, edit, conclude, postpone, cancel) with row version; automatic ones read-mostly`

---

### Task 5 (backend): `Modules/Servicos`

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Servicos/ServicoDtos.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Servicos/ServicosService.cs`, `backend/src/Meridiano.Api/Modules/Servicos/ServicosEndpoints.cs` (esqueletos)
- Create: `backend/tests/Meridiano.Api.Tests/ServicosTests.cs`

**Depends-on:** T1

**Interfaces:**
```csharp
public sealed class ServicosService(DbSessaoFactory sessoes)
{
    public Task<IReadOnlyList<ServicoDto>> ListarDaReservaAsync(ContextoSessao ctx, UsuarioAtual u, Guid reservaId, CancellationToken ct);
    public Task<ServicoDto> CriarAsync(ContextoSessao ctx, UsuarioAtual u, Guid reservaId, ServicoRequest req, CancellationToken ct);
    public Task<ServicoDto> AtualizarAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, ServicoRequest req, CancellationToken ct);
    public Task ExcluirAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, CancellationToken ct);
}
```
  - Validação: `Tipo ∈ ReservaGravacao.TiposServico` senão 422 `servico_tipo_invalido`; `Titulo` vazio → `titulo_obrigatorio`; `DataFim < DataInicio` → `datas_incoerentes`; `Ordem < 0` → `valor_invalido`.
  - Escrita: `TravarViagemDaReservaAsync(reservaId, null)` (não confere nem renova a versão da viagem — ruling nas Global Constraints); reserva `cancelada` → 422 `reserva_cancelada`; `AtualizarAsync` exige `req.Versao` (`versao_obrigatoria`) e faz `update … where id and agencia_id and excluido_em is null and xmin::text = @versao` → 0 → 409 (se a linha existe) / `nao_encontrado`; `ExcluirAsync` = `update servico set excluido_em = now(), excluido_por = @usuario`.
  - Leitura: `where reserva_id and agencia_id and excluido_em is null order by ordem, criado_em`; visibilidade da viagem. `DateTime` sem fuso: `System.Text.Json` desserializa `"2026-04-18T23:15"` como `Kind.Unspecified` e Npgsql grava em `timestamp` sem conversão; na leitura sai `Unspecified` e serializa sem `Z`. Cobrir com o teste.
  - Rotas: `GET /reservas/{id:guid}/servicos` (visibilidade) · `POST /reservas/{id:guid}/servicos` → 201 `Location /api/v1/servicos/{id}` · `PUT /servicos/{id:guid}` · `DELETE /servicos/{id:guid}` → 204 — escritas `ViagemEditar`.

- [ ] **Step 1: Testes**
```csharp
[Fact] public async Task Cria_lista_edita_e_exclui_servico_da_reserva()
// POST { tipo "aereo", titulo "GRU→LIS TP 82", dataInicio "2026-04-18T23:15", dataFim "2026-04-19T12:40", localizadorCia "ABC123", numeroBilhete "0471234567890", ordem 0 } → 201 Location; GET → 1 item, JSON contém "2026-04-18T23:15:00" e não contém "Z"; PUT { …, titulo "GRU→LIS TP 82 (novo)", versao } → 200 versao nova; PUT versao velha → 409; DELETE → 204; GET → []
[Fact] public async Task Rejeita_tipo_invalido_datas_incoerentes_e_reserva_cancelada()
// "jato" → 422 servico_tipo_invalido; fim < inicio → datas_incoerentes; reserva cancelada (fixture cancelada:true) → reserva_cancelada; titulo "" → titulo_obrigatorio
[Fact] public async Task Servico_nao_renova_versao_da_viagem_e_externo_so_le()
// versao antes == versao depois do POST; externa GET própria → 200; POST → 403
```

- [ ] **Step 2–4:** RED → implementar → `dotnet test`, format. Commit sugerido: `feat(servicos): per-reserva service items crud with own version and no trip version bump`

---

### Task 6 (backend): `Modules/Anexos` — presign, confirmar, download com `log_acesso_documento`

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Anexos/AnexoDtos.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Anexos/AnexosService.cs`, `backend/src/Meridiano.Api/Modules/Anexos/AnexosEndpoints.cs` (esqueletos)
- Create: `backend/tests/Meridiano.Api.Tests/AnexosTests.cs`

**Depends-on:** T1, T3 (`SemPermissaoException` e seu mapeamento no `TratadorDeExcecoes`)

**Interfaces:**
```csharp
public sealed class AnexosService(DbSessaoFactory sessoes, IArmazenamentoArquivo storage)
{
    public Task<IReadOnlyList<AnexoDto>> ListarDaViagemAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, CancellationToken ct);   // anexos da viagem + das suas reservas, confirmados
    public Task<AnexoCriadoDto> IniciarAsync(ContextoSessao ctx, UsuarioAtual u, NovoAnexoRequest req, CancellationToken ct);
    public Task<AnexoDto> ConfirmarAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, CancellationToken ct);
    public Task<string> UrlDownloadAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, CancellationToken ct);
    public Task ExcluirAsync(ContextoSessao ctx, UsuarioAtual u, Guid id, CancellationToken ct);
}
```
  - `IniciarAsync`: exatamente um de `ClienteId/ViagemId/ReservaId` senão 422 `anexo_vinculo_invalido`; `Tipo ∈ {voucher, comprovante, documento, contrato, extrato, outro}` senão `anexo_tipo_invalido`; `NomeArquivo` vazio → `nome_obrigatorio`; `TamanhoBytes > 25 * 1024 * 1024` → `arquivo_grande`; `Guardas.ReferenciaAsync` do vínculo; vínculo viagem/reserva → visibilidade da viagem (reserva resolve `viagem_id`); vínculo cliente → `ClienteVer` (o filtro `ClienteVerProprios` completo é 3.4); `caminho = $"{agencia}/{DateTime.UtcNow:yyyy}/{id}/{Sanitizar(nome)}"` (`Sanitizar`: `[A-Za-z0-9._-]`, resto `_`, máx. 120 chars); `insert into anexo (id, agencia_id, cliente_id, viagem_id, reserva_id, tipo, nome_arquivo, caminho, mime_type, tamanho_bytes, sensivel, data_descarte, enviado_por)`; `ConfirmarAsync` do banco; **depois** do commit, `storage.UrlParaEnviar(caminho, mime, 10 min)`.
  - `ConfirmarAsync`: `update anexo set confirmado_em = now() where id and agencia_id and excluido_em is null and confirmado_em is null`; inexistente → `nao_encontrado`; já confirmado → devolve o atual (idempotente).
  - `UrlDownloadAsync`: não confirmado → 422 `anexo_nao_confirmado`; visibilidade por vínculo; `sensivel` sem `ClienteVerDocumento` → `SemPermissaoException(ClienteVerDocumento)`; `sensivel` → `insert into log_acesso_documento (agencia_id, usuario_id, anexo_id)` e commit; URL = `storage.UrlParaBaixar(caminho, nome_arquivo, 2 min)`.
  - `ExcluirAsync`: soft delete (`excluido_em`, `excluido_por`); objeto no storage fica para `expurgo_anexos` (3.6) — registrar no BACKLOG.
  - `ListarDaViagemAsync`: `where (viagem_id = @v or reserva_id in (select id from reserva where viagem_id = @v)) and agencia_id and excluido_em is null and confirmado_em is not null order by criado_em desc`; `Vinculo` = `case when reserva_id is not null then 'reserva' when viagem_id is not null then 'viagem' else 'cliente' end`.
  - Rotas: `GET /viagens/{id:guid}/anexos` (visibilidade) · `POST /anexos` (`AnexoEnviar`) → 201 `Location /api/v1/anexos/{id}` · `POST /anexos/{id:guid}/confirmar` (`AnexoEnviar`) · `GET /anexos/{id:guid}/download` (`RequireAuthorization`; serviço decide) · `DELETE /anexos/{id:guid}` (`AnexoEnviar`) → 204.

- [ ] **Step 1: Testes** (`AnexosTests.cs`)
```csharp
[Fact] public async Task Inicia_confirma_lista_e_baixa_anexo_de_reserva()
// POST /anexos { reservaId r, tipo "voucher", nomeArquivo "voucher cvc.pdf", mimeType "application/pdf", tamanhoBytes 2048, sensivel false } → 201 { anexo.vinculo "reserva", urlUpload contém "/meridiano-teste/<agencia>/" e "X-Amz-Signature" }
// GET /viagens/{id}/anexos → [] ; POST /anexos/{id}/confirmar → 200; GET → 1 item nomeArquivo "voucher cvc.pdf"; GET /anexos/{id}/download → { url } contendo "response-content-disposition"; log_acesso_documento vazio; download antes de confirmar → 422 anexo_nao_confirmado
[Fact] public async Task Anexo_sensivel_exige_ver_documento_e_grava_log()
// anexo sensivel vinculado à viagem; download como financeiro → 403 sem_permissao (permissao "cliente.ver_documento"); como agente → 200 e 1 linha em log_acesso_documento (usuario_id = agente, anexo_id)
[Theory] [InlineData("dois_vinculos","anexo_vinculo_invalido")] [InlineData("nenhum","anexo_vinculo_invalido")] [InlineData("tipo_foto","anexo_tipo_invalido")] [InlineData("30mb","arquivo_grande")] [InlineData("reserva_de_outra_agencia","referencia_invalida")]
public async Task Rejeita_payload_invalido(string caso, string codigo)
[Fact] public async Task Vendedor_externo_le_e_baixa_da_propria_viagem_e_nao_envia()
// GET anexos própria → 200; download → 200; POST /anexos → 403; viagem alheia → 422 nao_encontrado
[Fact] public async Task Excluir_e_soft_e_some_da_lista()
```

- [ ] **Step 2–4:** RED → implementar → testes, format. Commit sugerido: `feat(anexos): presigned upload/confirm/download with sensitive access log and soft delete`

---

### Task 7 (backend): `GET /viagens/{id}/auditoria` — timeline por perfil

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Auditoria/AuditoriaDtos.cs`, `backend/src/Meridiano.Api/Modules/Auditoria/Frases.cs`, `backend/src/Meridiano.Api/Modules/Auditoria/Projecao.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Auditoria/AuditoriaService.cs`, `backend/src/Meridiano.Api/Modules/Auditoria/AuditoriaEndpoints.cs` (esqueletos)
- Create: `backend/tests/Meridiano.Api.Tests/AuditoriaTests.cs`, `backend/tests/Meridiano.Api.Tests/AuditoriaProjecaoTests.cs`

**Depends-on:** T1

**Interfaces:**
```csharp
public sealed class AuditoriaService(DbSessaoFactory sessoes)
{ public Task<IReadOnlyList<EventoAuditoriaDto>> DaViagemAsync(ContextoSessao ctx, UsuarioAtual u, Guid viagemId, CancellationToken ct); }
public static class Frases
{ public static (string Titulo, string? Subtitulo) Para(string tabela, string acao, IReadOnlyDictionary<string, AlteracaoDto> alteracoes, string? rotuloRegistro); }
public static class ProjecaoAuditoria
{ public static EventoAuditoriaDto? Projetar(EventoAuditoriaDto e, bool verValores, bool verResultado); }   // null = descartar
```
  - Query (uma só): `auditoria a` com `a.agencia_id = @agencia and ( (a.tabela = 'viagem' and a.registro_id = @v) or (a.tabela = 'reserva' and a.registro_id in (select id from reserva where viagem_id = @v)) or (a.tabela = 'servico' and a.registro_id in (select s.id from servico s join reserva r on r.id = s.reserva_id where r.viagem_id = @v)) or (a.tabela = 'movimento_financeiro' and a.registro_id in (select m.id from movimento_financeiro m join reserva r on r.id = m.reserva_id where r.viagem_id = @v)) or (a.tabela = 'repasse' and a.registro_id in (select id from repasse where viagem_id = @v)) )`, `left join usuario u on u.id = a.usuario_id`, rótulo por `left join lateral` (reserva: `f.nome || ' · ' || coalesce(r.localizador, '—')`; serviço: `titulo`; repasse: `usuario.nome`; movimento: `tipo || ' ' || valor`), `order by a.criado_em desc limit 200`. `alteracoes jsonb` lido como `string` e desserializado em `Dictionary<string, AlteracaoDto>`.
  - Visibilidade: endpoint `RequerPermissao(AuditoriaVer)`; serviço exige a viagem visível (`ViagemVer` ou `vendedor_id = usuario`) senão `nao_encontrado`.
  - `ProjecaoAuditoria.Projetar`: remove sempre `criado_por, excluido_por, atualizado_em, agencia_id`; sem `verValores` remove `valor_total, valor_taxas, valor_comissao, rav_operadora, valor_cliente, taxa_servico, valor_reembolso, valor, multa_cliente`; sem `verResultado` descarta eventos de `repasse`; `UPDATE` que ficou sem chaves → `null`.
  - `Frases.Para`: `viagem/INSERT → "Viagem criada"` · `viagem/UPDATE`: `cancelada.para = true → "Viagem cancelada"`, tem `agente_id → "Viagem transferida"`, tem `vendedor_id → "Vendedor alterado"`, senão `"Viagem alterada"` · `reserva/INSERT → "Reserva lançada"` · `reserva/UPDATE`: `status.para = "cancelada" → "Reserva cancelada"`, `"emitida" → "Reserva emitida"`, tem `nfse_status → "NFSe atualizada"`, tem `valor_total|valor_comissao|valor_cliente → "Valores da reserva alterados"`, senão `"Reserva alterada"` · `servico`: INSERT `"Serviço adicionado"`, UPDATE com `excluido_em.para` não nulo `"Serviço removido"`, senão `"Serviço alterado"` · `movimento_financeiro/INSERT → "Movimento lançado"`, UPDATE com `excluido_em` → `"Movimento excluído"` · `repasse/INSERT → "Repasse criado"`, UPDATE `status.para = "a_pagar" → "Repasse liberado"`, `"pago" → "Repasse pago"`, `excluido_em → "Repasse substituído"`, senão `"Repasse alterado"` · `DELETE → "<Entidade> excluída"`. Subtítulo = rótulo.

- [ ] **Step 1: Testes**

`AuditoriaProjecaoTests.cs` (puro, sem banco): evento `reserva/UPDATE` com `{valor_comissao, observacoes}` → sem `verValores` fica só `observacoes`; evento só com `{valor_comissao}` → `null`; evento `repasse` sem `verResultado` → `null`; `Frases.Para("reserva","UPDATE", {status: {de: "emitida", para: "cancelada"}}, "CVC · K7X2PQ")` → `("Reserva cancelada", "CVC · K7X2PQ")`; `("viagem","UPDATE",{agente_id…})` → `"Viagem transferida"`.

`AuditoriaTests.cs`:
```csharp
[Fact] public async Task Timeline_da_viagem_em_ordem_decrescente_com_frases()
// dono cria viagem (2 reservas) via API; PUT com valorComissao de r1 = 2000; owner: update reserva set status='cancelada', cancelada_em=now(), motivo_cancelamento='x', desfecho_cancelamento='sem_reembolso' where id = r2 (o trigger grava com usuario_id null)
// GET /viagens/{id}/auditoria como dono → títulos (do mais novo): "Reserva cancelada" (subtitulo "Decolar · DCL-1", usuarioNome null), "Valores da reserva alterados" (alteracoes.valor_comissao.de 1000 / .para 2000, usuarioNome dono), "Reserva lançada", "Reserva lançada", "Repasse criado", "Viagem criada"
[Fact] public async Task Contador_ve_valores_e_repasse_agente_recebe_403_externa_nao_ve_alheia()
// contador (AuditoriaVer + ReservaVerValores + ViagemVerResultado) → contém "valor_comissao" e evento "Repasse criado"; agente → 403 sem_permissao; externa (sem AuditoriaVer) → 403
```

- [ ] **Step 2–4:** RED → implementar → testes, format. Commit sugerido: `feat(auditoria): trip timeline with readable phrases and per-profile field projection`

---

### Task 8 (front): Componentes — `DataTable`, `MoneyCell`, `DateCell`, `StatusCell`, `Paginacao`, `KpiCard`, `FaixaResumo`, `formatarData`

**Files:**
- Create: `frontend/src/lib/datas.ts`, `frontend/src/lib/datas.test.ts`
- Create: `frontend/src/components/DataTable/{DataTable.tsx,DataTable.test.tsx,DataTable.module.css,MoneyCell.tsx,DateCell.tsx,StatusCell.tsx,Paginacao.tsx,Paginacao.test.tsx}`
- Create: `frontend/src/components/KpiCard/{KpiCard.tsx,KpiCard.test.tsx,KpiCard.module.css}`
- Create: `frontend/src/components/Viagem/FaixaResumo.tsx`, `frontend/src/components/Viagem/FaixaResumo.test.tsx`
- Modify: `frontend/src/components/index.ts` (+ exports), `frontend/src/components/viagem.ts` (+ `FaixaResumo`)

**Depends-on:** none

**Interfaces:**
```ts
// src/lib/datas.ts
export function formatarData(iso: string | null | undefined): string          // "2026-04-18" → "18/04/2026"; null → "—"
export function formatarDataHora(iso: string | null | undefined): string      // "2026-04-18T23:15:00" → "18/04/2026 23:15"
export function formatarPeriodo(ida: string | null, volta: string | null): string  // "18–28/04/2026" (mesmo mês/ano) · "28/04–02/05/2026" · "18/04/2026–02/01/2027" · só ida "18/04/2026" · nada "—"
export function hojeIso(): string                                             // yyyy-mm-dd local (mesma receita de reservaVazia)
export function diasAte(iso: string): number                                  // inteiro, negativo se passado

// src/components/DataTable/DataTable.tsx
export interface Coluna<T> { id: string; titulo: string; alinhar?: "right"; ordenavel?: boolean; render: (linha: T) => ReactNode; largura?: string }
export interface Ordenacao { campo: string; direcao: "asc" | "desc" }
interface DataTableProps<T> {
  colunas: Coluna<T>[]; linhas: T[]; chave: (l: T) => string; onLinha?: (l: T) => void; rotuloLinha?: (l: T) => string;
  carregando?: boolean; vazio?: ReactNode; ordenacao?: Ordenacao; onOrdenar?: (o: Ordenacao) => void; rodape?: ReactNode; legenda: string;
}
export function DataTable<T>(props: DataTableProps<T>)
//  <table> com <caption class="visually-hidden">{legenda}</caption>; th ordenável = <button aria-sort>; linha clicável = <tr tabIndex=0 role="link"? não: role="row" + onClick/onKeyDown Enter> com aria-label = rotuloLinha(l); carregando → Skeleton.Block height="table" (delay 300 ms já no Skeleton); linhas vazias → vazio (EmptyState do chamador) numa <td colSpan>
export function MoneyCell({ value, emphasis }: { value: number | null | undefined; emphasis?: "normal" | "result" })   // MoneyValue alinhado à direita, tabular
export function DateCell({ value }: { value: string | null | undefined })
export function StatusCell({ entidade, valor }: { entidade: EntidadeStatus; valor: string })                            // StatusBadge
export function Paginacao({ pagina, tamanho, total, onPagina }: { pagina: number; tamanho: number; total: number; onPagina: (p: number) => void })
//  "1–25 de 42" · Anterior (secondary sm, disabled na 1ª) · Próxima → (secondary sm)

// src/components/KpiCard/KpiCard.tsx  (contrato §3: informativo ou acionável)
export function KpiCard({ label, value, contexto, actionLabel, onAction, tone }: { label: string; value: ReactNode; contexto?: string; actionLabel?: string; onAction?: () => void; tone?: "normal" | "warning" | "danger" })

// src/components/Viagem/FaixaResumo.tsx  (a "summary-strip" do protótipo, versão de leitura; TripSummary continua para o formulário)
export interface ItemFaixa { label: string; value: number | null | undefined; tooltip?: string; destaque?: boolean; badge?: ReactNode }
export function FaixaResumo({ itens, extra }: { itens: ItemFaixa[]; extra?: { label: string; value: number } })   // extra = "Comissões recebidas" à direita; quebra em 1366 (CSS do componente)
```
  - `DataTable.module.css`: cabeçalho caps `--type-caption`, linha 48px, hover `--color-surface-hover`, colunas monetárias `text-align: right` + `font-variant-numeric: tabular-nums`, `overflow-x: auto` no wrapper. Sem `@media` fora da lista.

- [ ] **Step 1: Testes**
  - `datas.test.ts`: os 5 exemplos de `formatarPeriodo`; `formatarData(null) === "—"`; `formatarDataHora("2026-04-18T23:15:00") === "18/04/2026 23:15"`; `diasAte(hoje + 3) === 3`.
  - `DataTable.test.tsx`: renderiza 2 colunas × 2 linhas; clicar na linha chama `onLinha`; Enter na linha focada chama `onLinha`; `carregando` não renderiza linhas; `linhas=[]` mostra `vazio`; clicar em cabeçalho ordenável chama `onOrdenar({campo, direcao: "asc"})` e de novo `"desc"`; `aria-sort` reflete.
  - `Paginacao.test.tsx`: "1–25 de 42"; Anterior desabilitado na página 1; Próxima chama `onPagina(2)`; na última página Próxima desabilitado; "26–42 de 42".
  - `KpiCard.test.tsx`: informativo sem botão; acionável com botão que chama `onAction`.
  - `FaixaResumo.test.tsx`: 5 itens + extra → textos e `R$ 1.640,00` com classe de destaque; tooltip renderiza `Tooltip`.

- [ ] **Step 2–4:** RED → implementar → `node node_modules/vitest/vitest.mjs run`, `npm run lint`, `npm run typecheck`.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(components): DataTable with money/date/status cells and pagination, KpiCard, FaixaResumo, date formatting`

---

### Task 9 (front): API, tipos, mapas de status, `RotaProtegida`, `paraRequest` sem canceladas

**Files:**
- Modify: `frontend/src/api/viagens.ts` (+ tipos e funções da lista/operações/créditos/alterações), `frontend/src/api/viagens.test.ts` (criar)
- Create: `frontend/src/api/{busca.ts,pendencias.ts,servicos.ts,anexos.ts,auditoria.ts}`
- Modify: `frontend/src/dominio/status.ts` (+ `credito`, `prioridade`, `desfecho`, `nfse_tomador`, `anexo_tipo`; rótulos de `tipo_servico` via `ROTULO_SERVICO` já existente), `frontend/src/dominio/status.test.ts`
- Modify: `frontend/src/components/Reserva/tipos.ts` (`deDto` preserva campos de cancelamento; **`paraRequest` inalterado**), `frontend/src/pages/viagens/useNovaViagem.ts` (R2: `reservas.filter(r => r.status !== "cancelada").map(paraRequest)` ao montar o PUT; `?reserva=<id>` abre só aquele card; `excetoViagemId` em `semelhantes` na edição), `frontend/src/pages/viagens/useNovaViagem.test.ts` (+2 casos)
- Create: `frontend/src/shell/RotaProtegida.tsx`, `frontend/src/shell/RotaProtegida.test.tsx`

**Depends-on:** none

**Interfaces:**
```ts
// src/api/viagens.ts — acréscimos (nomes espelham o C#)
export type SituacaoComissao = "nao_prevista" | "a_receber" | "parcial" | "atrasada" | "recebida" | "divergente";
export type Desfecho = "sem_reembolso" | "reembolso" | "credito";
export interface ReservaDto { /* …3.2… */ comissaoMantida: boolean; canceladaEm: string | null; motivoCancelamento: string | null; desfechoCancelamento: Desfecho | null; nfseTomador: "cliente" | "operadora" | null; nfseNumero: string | null; nfseDataEmissao: string | null; conciliacaoEncerrada: boolean; situacaoComissao: SituacaoComissao; valorReembolso?: number | null; recebidoOperadora?: number }
export interface ResumoViagemDto { vendaTotal; custoFornecedores; receitaPrevista; receitaRecebida: number; repasseValor: number | null; repasseStatus: string | null; despesasViagem; resultado }
export interface ViagemDto { /* …3.2… */ agenteNome: string | null; canceladaEm: string | null; motivoCancelamento: string | null }
export interface ListaViagemDto { id: string; codigo: string; titular: string; destino: string; tipo: Tipo; dataIda: string | null; dataVolta: string | null; vendedorNome: string; faseOperacional: string; faseFinanceira: string; vendaTotal?: number; receitaPrevista?: number }
export interface ContadoresDto { todas: number; emEmissao: number; embarcamSemana: number; comissaoAtrasada: number; concluidas: number }
export interface ListaViagensDto { itens: ListaViagemDto[]; total: number; pagina: number; tamanho: number; contadores: ContadoresDto }
export type AbaViagens = "todas" | "em_emissao" | "embarcam_semana" | "comissao_atrasada" | "concluidas";
export interface FiltroViagens { aba?: AbaViagens; q?: string; vendedorId?: string; tipo?: Tipo; fornecedorId?: string[]; nfse?: NfseStatus; idaDe?: string; idaAte?: string; compraDe?: string; compraAte?: string; ordem?: "ida" | "codigo" | "venda"; direcao?: "asc" | "desc"; pagina?: number; tamanho?: number }
export interface CreditoRequest { valor: number; validade: string | null; clienteId: string | null }
export interface CancelarReservaRequest { motivo: string; desfecho: Desfecho; valorReembolso: number | null; comissaoMantida: boolean; credito: CreditoRequest | null; versao: string }
export interface CancelarReservaItem { reservaId: string; desfecho: Desfecho; valorReembolso: number | null; comissaoMantida: boolean; credito: CreditoRequest | null }
export interface CancelarViagemRequest { motivo: string; reservas: CancelarReservaItem[]; versao: string }
export interface RemarcarRequest { dataAlteracao: string; descricao: string; valorNovo: number | null; multaCliente: number; novaDataIda: string | null; novaDataVolta: string | null; versao: string }
export interface NfseRequest { status: NfseStatus; tomador: "cliente" | "operadora" | null; numero: string | null; dataEmissao: string | null; versao: string }
export interface CreditoDto { id: string; clienteId: string; clienteNome: string; fornecedorId: string; fornecedorNome: string; valor: number; validade: string | null; status: "disponivel" | "utilizado" | "expirado"; reservaOrigemId: string | null; codigoViagemOrigem: string | null; reservaUsoId: string | null }
export interface ReservaAlteracaoDto { id: string; dataAlteracao: string; descricao: string; valorAnterior: number | null; valorNovo: number | null; multaCliente: number; usuarioNome: string | null; criadoEm: string }
export const viagensApi = { /* …3.2… */
  listar: (f: FiltroViagens) => api.get<ListaViagensDto>(`/viagens?${qsLista(f)}`),        // fornecedorId repete a chave; omite undefined/""/[]
  cancelarViagem: (id, r: CancelarViagemRequest) => api.post<ViagemDto>(`/viagens/${id}/cancelar`, r),
  transferir: (id, agenteId, versao) => api.post<ViagemDto>(`/viagens/${id}/transferir`, { agenteId, versao }),
  creditos: (id) => api.get<CreditoDto[]>(`/viagens/${id}/creditos`),
  consumirCredito: (id, creditoId, reservaId, versao) => api.post<ViagemDto>(`/viagens/${id}/creditos/consumir`, { creditoId, reservaId, versao }),
  cancelarReserva: (reservaId, r: CancelarReservaRequest) => api.post<ViagemDto>(`/reservas/${reservaId}/cancelar`, r),
  remarcar: (reservaId, r: RemarcarRequest) => api.post<ViagemDto>(`/reservas/${reservaId}/remarcar`, r),
  nfse: (reservaId, r: NfseRequest) => api.put<ViagemDto>(`/reservas/${reservaId}/nfse`, r),
  alteracoes: (reservaId) => api.get<ReservaAlteracaoDto[]>(`/reservas/${reservaId}/alteracoes`),
};
export const chaves = { /* …3.2… */ viagens: (f: FiltroViagens) => ["viagens", "lista", f] as const, creditos: (id) => ["viagens", id, "creditos"] as const, alteracoes: (r) => ["reservas", r, "alteracoes"] as const };

// src/api/busca.ts
export interface BuscaDto { clientes: { id; nome; telefone: string | null }[]; viagens: { id; codigo; destino; titular; dataIda: string | null; faseOperacional }[]; reservas: { reservaId; viagemId; codigo; localizador; fornecedorNome }[] }
export const buscaApi = { buscar: (q: string) => api.get<BuscaDto>(`/busca?q=${encodeURIComponent(q)}`) };

// src/api/pendencias.ts
export type Prioridade = "normal" | "urgente";
export interface PendenciaDto { id; versao; titulo; descricao: string | null; dataPrevista: string; responsavelId: string | null; responsavelNome: string | null; clienteId: string | null; clienteNome: string | null; viagemId: string | null; codigoViagem: string | null; status: "aberta" | "concluida" | "cancelada"; origem: "manual" | "automatica"; prioridade: Prioridade; adiadaDe: string | null; concluidaEm: string | null; atrasada: boolean }
export interface NovaPendenciaRequest { titulo: string; descricao: string | null; dataPrevista: string; responsavelId: string | null; prioridade: Prioridade; clienteIds: string[] }
export interface PendenciaRequest { titulo; descricao; dataPrevista; responsavelId; prioridade; versao: string }
export const pendenciasApi = { daViagem: (viagemId, incluirConcluidas: boolean) => api.get<PendenciaDto[]>(`/viagens/${viagemId}/pendencias?incluirConcluidas=${incluirConcluidas}`), criar: (viagemId, r: NovaPendenciaRequest) => api.post<PendenciaDto[]>(`/viagens/${viagemId}/pendencias`, r), atualizar: (id, r: PendenciaRequest) => api.put<PendenciaDto>(`/pendencias/${id}`, r), concluir: (id, versao) => api.post<PendenciaDto>(`/pendencias/${id}/concluir`, { versao }), adiar: (id, novaData, versao) => api.post<PendenciaDto>(`/pendencias/${id}/adiar`, { novaData, versao }), cancelar: (id) => api.delete(`/pendencias/${id}`) };
export const chavesPendencias = { daViagem: (id, c: boolean) => ["viagens", id, "pendencias", c] as const };

// src/api/servicos.ts
export interface ServicoDto { id; versao; reservaId; tipo: TipoServico; titulo; dataInicio: string | null; dataFim: string | null; localidade: string | null; localizadorCia: string | null; numeroBilhete: string | null; observacoes: string | null; ordem: number }
export interface ServicoRequest { tipo: TipoServico; titulo; dataInicio; dataFim; localidade; localizadorCia; numeroBilhete; observacoes; ordem: number; versao?: string }
export const servicosApi = { daReserva: (reservaId) => api.get<ServicoDto[]>(`/reservas/${reservaId}/servicos`), criar: (reservaId, r) => api.post<ServicoDto>(`/reservas/${reservaId}/servicos`, r), atualizar: (id, r) => api.put<ServicoDto>(`/servicos/${id}`, r), excluir: (id) => api.delete(`/servicos/${id}`) };
export const chavesServicos = { daReserva: (r) => ["reservas", r, "servicos"] as const };

// src/api/anexos.ts
export type TipoAnexo = "voucher" | "comprovante" | "documento" | "contrato" | "extrato" | "outro";
export interface AnexoDto { id; vinculo: "cliente" | "viagem" | "reserva"; clienteId; viagemId; reservaId; tipo: TipoAnexo; nomeArquivo; mimeType: string | null; tamanhoBytes: number | null; sensivel: boolean; dataDescarte: string | null; enviadoPorNome: string | null; criadoEm: string }
export interface NovoAnexoRequest { clienteId?: string; viagemId?: string; reservaId?: string; tipo: TipoAnexo; nomeArquivo: string; mimeType: string | null; tamanhoBytes: number | null; sensivel: boolean; dataDescarte: string | null }
export const anexosApi = { daViagem: (viagemId) => api.get<AnexoDto[]>(`/viagens/${viagemId}/anexos`), iniciar: (r: NovoAnexoRequest) => api.post<{ anexo: AnexoDto; urlUpload: string }>("/anexos", r), confirmar: (id) => api.post<AnexoDto>(`/anexos/${id}/confirmar`), urlDownload: (id) => api.get<{ url: string }>(`/anexos/${id}/download`), excluir: (id) => api.delete(`/anexos/${id}`) };
export async function enviarArquivo(urlUpload: string, arquivo: File): Promise<void>   // fetch PUT com body=File e Content-Type do arquivo; !ok → throw new Error("Falha ao enviar o arquivo")
export const chavesAnexos = { daViagem: (id) => ["viagens", id, "anexos"] as const };

// src/api/auditoria.ts
export interface AlteracaoDto { de: unknown; para: unknown }
export interface EventoAuditoriaDto { id: number; tabela: string; registroId: string; acao: "INSERT" | "UPDATE" | "DELETE"; titulo: string; subtitulo: string | null; alteracoes: Record<string, AlteracaoDto>; motivo: string | null; usuarioNome: string | null; criadoEm: string }
export const auditoriaApi = { daViagem: (id) => api.get<EventoAuditoriaDto[]>(`/viagens/${id}/auditoria`) };
export const chavesAuditoria = { daViagem: (id) => ["viagens", id, "auditoria"] as const };

// src/dominio/status.ts — mapas novos
credito: disponivel "Disponível"/success · utilizado "Utilizado"/neutral · expirado "Expirado"/danger
prioridade: normal "Normal"/neutral · urgente "Urgente"/danger
desfecho: sem_reembolso "Sem reembolso"/neutral · reembolso "Reembolso"/info · credito "Crédito"/success
nfse_tomador: cliente "Cliente" · operadora "Operadora" (neutral)
anexo_tipo: voucher "Voucher" · comprovante "Comprovante" · documento "Documento" · contrato "Contrato" · extrato "Extrato" · outro "Outro" (neutral)

// src/shell/RotaProtegida.tsx
export function RotaProtegida({ permissao }: { permissao: string | string[] })   // temPermissao(pode, permissao) ? <Outlet/> : <Page><EmptyState title="Sem permissão" description="Seu perfil não acessa esta área." action={<Button variant="secondary" onClick={() => nav("/viagens")}>Ir para Viagens</Button>} /></Page>
```
  - `useNovaViagem`: `salvar()` monta `reservas: form.reservas.filter(r => r.status !== "cancelada").map(paraRequest)`; ao carregar em edição com `?reserva=<id>` (`useSearchParams`), `aberta = r.id === id` (demais fechadas); `semelhantes` em edição passa `excetoViagemId = id` (função `viagensApi.semelhantes` ganha 4º parâmetro opcional).

- [ ] **Step 1: Testes** — `viagens.test.ts`: `qsLista({ aba: "todas", fornecedorId: ["a","b"], q: "", pagina: 2 })` → `aba=todas&fornecedorId=a&fornecedorId=b&pagina=2`; `status.test.ts`: `apresentacaoStatus("desfecho","credito").texto === "Crédito"`; `useNovaViagem.test.ts`: (a) form com reserva `cancelada` + emitida → PUT envia só a emitida; (b) `?reserva=<id2>` → só o card 2 `aberta`; `RotaProtegida.test.tsx`: sem permissão mostra "Sem permissão"; com permissão renderiza o `Outlet`.

- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(api): trip list/operations, pendencias, servicos, anexos, auditoria and busca clients; status maps; route guard; cancelled reservas omitted from PUT`

---

### Task 10 (front): `ViagensPage` — lista com abas, filtros e tabela

**Files:**
- Create: `frontend/src/pages/viagens/lista/{ViagensPage.tsx,ViagensPage.test.tsx,FiltrosViagens.tsx,FiltrosViagens.test.tsx,useFiltrosViagens.ts,useFiltrosViagens.test.ts,ViagensPage.module.css}`
- Modify: `frontend/src/shell/rotasModulos.tsx` (`/viagens` → `ViagensPage`; envolver o grupo `/viagens*` em `<Route element={<RotaProtegida permissao={["viagem.ver","viagem.ver_proprias"]} />}>`; `/auditoria` `auditoria.ver`; `/equipe` `usuario.gerenciar`; `/relatorios` `relatorio.ver`; `/financeiro*` `["financeiro.movimentar","financeiro.conciliar"]`)

**Depends-on:** T8, T9

**Interfaces:**
```ts
// useFiltrosViagens.ts — filtros vivem na URL (useSearchParams) para voltar/compartilhar
export function useFiltrosViagens(): { filtro: FiltroViagens; definir: (patch: Partial<FiltroViagens>) => void; limpar: () => void; ativos: number }
//  defaults: aba "todas", pagina 1, tamanho 25, ordem "ida", direcao "desc", `idaPreset` "90d" (parâmetro só da URL, convertido em idaDe=hoje/idaAte=hoje+90; presets: "90d" | "mes" | "qualquer"); `ativos` = quantos filtros avançados preenchidos (tipo, fornecedorId, nfse, compraDe/compraAte); mudar qualquer filtro reseta pagina=1
<FiltrosViagens filtro definir limpar ativos vendedores={VendedorDto[]} fornecedores={FornecedorDto[]} />
//  linha 1: Input busca (placeholder "Cliente, destino, localizador…", debounce 300 ms) · Select "Vendedor: todos" · Select "Ida: próximos 90 dias | Este mês | Qualquer" · Button secondary "Filtros" + Badge "● N" (aria-expanded) · "Limpar" (tertiary, só se ativos > 0 ou q)
//  painel avançados (recolhido por padrão; aberto se ativos > 0): Select Tipo · Chips de fornecedor (multi, ✓) · Select NFSe · Emissão de/até (DateInput ×2)
```
  - `ViagensPage`: `Page` + `Subnav` (padrão de `EmConstrucao`) + `PageHeader title="Viagens" subtitle="{todas} viagens · {emEmissao} em emissão · {comissaoAtrasada} com comissão atrasada" actions={pode("viagem.criar") && <Button variant="business" icon={<Plus/>}>+ Nova viagem</Button>}` → `Tabs` (Todas · Em emissão · Embarcam esta semana · Comissão atrasada · Concluídas, `count` dos contadores; `Tabs.Panel` único) → `FiltrosViagens` → `DataTable` colunas: **Viagem** (`primary` titular; `secondary` "{destino} · {Tipo} · <code>{codigo}</code>"), **Ida** (`DateCell`, ordenável), **Vendedor**, **Fase** (`StatusCell fase_viagem`), **Financeiro** (`StatusCell comissao`), **Venda** (`MoneyCell`, ordenável, só se `vendaTotal` presente no primeiro item — perfil sem valores não vê a coluna), **Receita** (`MoneyCell emphasis="result"`) → `Paginacao` no `rodape`. `onLinha` → `nav(/viagens/{id})`; `rotuloLinha` = "{titular} · {destino} · {codigo}". `useQuery({ queryKey: chaves.viagens(filtro), queryFn, placeholderData: keepPreviousData })`. Vazio: `EmptyState title="Nenhuma viagem por aqui" description="Nada bate com os filtros. Limpe os filtros ou lance a primeira viagem." action=<Limpar filtros>`. Erro: `Alert danger` com "Tentar de novo".
  - Sem "Exportar CSV" (3.6).

- [ ] **Step 1: Testes** — `useFiltrosViagens.test.ts`: default gera `idaDe=hoje`/`idaAte=hoje+90`; `definir({ aba: "concluidas" })` escreve na URL e reseta página; `limpar()` volta ao default; `ativos` conta 2 com tipo + nfse. `FiltrosViagens.test.tsx`: painel fechado por padrão; clicar "Filtros" abre e mostra chips de fornecedor; clicar chip "CVC" chama `definir({ fornecedorId: ["<id>"] })`. `ViagensPage.test.tsx` (fetch stub: `/viagens?` → lista com 2 itens e contadores; `/usuarios/vendedores`, `/fornecedores`): header com "2 viagens"; abas com contadores; tabela com 2 linhas; clicar linha navega para `/viagens/<id>`; perfil sem `vendaTotal` no payload → sem coluna "Venda".

- [ ] **Step 2–4:** RED → implementar (`ViagensPage.tsx` ≤ 200 linhas) → vitest, lint, typecheck, build.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(viagens): trip list page with url-backed filters, tabs with counters, sortable table and pagination; permission route guards`

---

### Task 11 (front): Modais de operação — cancelar reserva/viagem, remarcar, NFSe, transferir, usar crédito

**Files:**
- Create: `frontend/src/components/ViagemOperacoes/{CancelarReservaModal.tsx,CancelarReservaModal.test.tsx,CancelarViagemModal.tsx,CancelarViagemModal.test.tsx,RemarcarModal.tsx,RemarcarModal.test.tsx,NfseModal.tsx,TransferirModal.tsx,UsarCreditoModal.tsx,UsarCreditoModal.test.tsx,DesfechoFields.tsx,useOperacao.ts,useOperacao.test.ts,Operacoes.module.css}`
- Create: `frontend/src/components/viagemOperacoes.ts` (barrel)

**Depends-on:** T9

**Interfaces:**
```ts
// useOperacao.ts — receita comum: estado saving/error, 409 → conflito, 422 → erro de campo (mapa por modal) ou bloco
export function useOperacao<TReq>(executar: (req: TReq) => Promise<ViagemDto>, mapa: Record<string, string>): {
  salvando: boolean; erros: Record<string, string>; erroBloco: string | null; conflito: boolean;
  enviar: (req: TReq) => Promise<ViagemDto | null>;   // null em erro; em sucesso o chamador fecha o modal e faz queryClient.setQueryData(chaves.viagem(id), dto)
  limpar: () => void;
}
<DesfechoFields value={{ desfecho, valorReembolso, comissaoMantida, credito }} onChange erros passageiros={PassageiroDto[]} />
//  Select Desfecho (sem_reembolso | reembolso | credito) · reembolso → MoneyInput "Valor do reembolso" · credito → MoneyInput "Valor do crédito" + DateInput "Validade" + Select "Crédito em nome de" (passageiros; default titular) · Checkbox "Operadora mantém a comissão"
<CancelarReservaModal open reserva={ReservaDto} viagem={ViagemDto} onClose onCancelada={(v: ViagemDto) => void} />
//  título "Cancelar reserva {n} · {fornecedor}"; impacto "Zera comissão prevista (salvo comissão mantida) e reavalia o repasse."; Textarea Motivo (required); DesfechoFields; footer: Voltar (tertiary) · "Cancelar reserva" (danger, loading)
<CancelarViagemModal open viagem onClose onCancelada />
//  título "Cancelar viagem {codigo}"; Textarea Motivo; lista de reservas ativas, cada uma com DesfechoFields compacto (default sem_reembolso); impacto "Cancela {n} reservas ativas e as pendências automáticas."; botão danger "Cancelar viagem e {n} reservas"
<RemarcarModal open reserva viagem onClose onRemarcada />
//  DateInput Data da alteração (hoje) · Textarea Descrição (required) · MoneyInput "Novo valor da reserva" (helper "Atual: R$ X"; vazio = não muda) · MoneyInput "Multa paga pelo cliente" (helper "Informativa: não altera receita nem repasse") · <details> "Alterar datas da viagem": Ida · Volta (DateInput, pré-preenchidas)
<NfseModal open reserva viagem onClose onSalva />           // Select Status · Select Tomador · Input Número (mono) · DateInput Emissão; 422 nfse_incompleta → erro em Número
<TransferirModal open viagem vendedores={VendedorDto[]} onClose onTransferida />   // Select "Novo agente" (usuários ativos, exceto o atual); botão primary "Transferir"
<UsarCreditoModal open viagem creditos={CreditoDto[]} onClose onUsado />
//  lista de créditos disponíveis (cliente · fornecedor · valor · validade) com Radio; Select "Aplicar na reserva" (só reservas ativas do mesmo fornecedor do crédito escolhido); 422 credito_* → bloco
```
  - Mapas 422 → campo: `motivo_obrigatorio → motivo`, `desfecho_invalido → desfecho`, `valor_invalido → valorReembolso`, `credito_valor_invalido → credito.valor`, `credito_cliente_invalido → credito.clienteId`, `descricao_obrigatoria → descricao`, `valor_negativo → valorNovo`, `datas_incoerentes → novaDataVolta`, `nfse_incompleta → numero`, `nfse_invalida → status`, `agente_igual → agenteId`, `usuario_inativo → agenteId`; `periodo_fechado`, `reserva_cancelada`, `viagem_cancelada`, `reservas_ativas`, `credito_*` restantes → bloco (Alert danger no topo do modal com `detalhe`).
  - Todos com `Modal` do contrato (focus trap, Esc), `aria-describedby` nos erros, `Button loading` durante `salvando`; nenhum `toast` de sucesso para operação visível na tela (contrato); `toast.success` só em transferir (a tela não muda visivelmente além do nome do agente).

- [ ] **Step 1: Testes** — `useOperacao.test.ts`: 422 `motivo_obrigatorio` vira `erros.motivo`; 409 → `conflito = true`; sucesso devolve o DTO. `CancelarReservaModal.test.tsx`: submit sem motivo → erro de campo (validação local); desfecho `credito` mostra campos de crédito; submit chama `viagensApi.cancelarReserva` com `{ motivo, desfecho: "credito", credito: { valor: 9000, … }, versao }` e chama `onCancelada`. `CancelarViagemModal.test.tsx`: lista 2 reservas ativas; submit envia `reservas` com 2 itens e botão diz "Cancelar viagem e 2 reservas". `RemarcarModal.test.tsx`: valor novo vazio envia `valorNovo: null`; datas só quando o `<details>` foi editado. `UsarCreditoModal.test.tsx`: escolher crédito CVC filtra o Select para reservas CVC; submit chama `consumirCredito`.

- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck, tokens.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(viagem): operation modals (cancel reserva/trip with desfecho and credit, remarcar, nfse, transfer, use credit) with shared 422/409 handling`

---

### Task 12 (front): Pendências, anexos, serviços e card de reserva em leitura

**Files:**
- Create: `frontend/src/components/Pendencias/{ListaPendencias.tsx,ListaPendencias.test.tsx,LinhaPendencia.tsx,NovaPendenciaModal.tsx,NovaPendenciaModal.test.tsx,AdiarModal.tsx,Pendencias.module.css}`, `frontend/src/components/pendencias.ts`
- Create: `frontend/src/components/Anexos/{ListaAnexos.tsx,ListaAnexos.test.tsx,AnexarModal.tsx,AnexarModal.test.tsx,Anexos.module.css}`, `frontend/src/components/anexos.ts`
- Create: `frontend/src/components/Servicos/{ListaServicos.tsx,ServicoModal.tsx,ServicoModal.test.tsx,Servicos.module.css}`, `frontend/src/components/servicos.ts`
- Create: `frontend/src/components/Reserva/ReservaDetalheCard.tsx`, `frontend/src/components/Reserva/ReservaDetalheCard.test.tsx`; Modify: `frontend/src/components/reserva.ts` (+ export)

**Depends-on:** T8 (`DateCell`, `formatarData`), T9

**Interfaces:**
```ts
// Pendências (contrato §4.4: uma ação visível + menu ⋯; linha inteira abre o contexto)
<ListaPendencias viagemId={string} passageiros={PassageiroDto[]} vendedores={VendedorDto[]} podeEditar={boolean} />
//  header: Button primary "+ Nova pendência" (podeEditar) · texto de ajuda · Checkbox "Mostrar concluídas"
//  useQuery(chavesPendencias.daViagem(id, mostrarConcluidas)); mutations concluir/adiar/cancelar invalidam a chave; 409 → toast.error(mensagemDeErro) + invalidate
<LinhaPendencia p={PendenciaDto} onConcluir onAdiar onEditar onExcluir podeEditar />
//  checkbox visual (aria-label "Concluir {titulo}") + título (+ " — {clienteNome}") + "{data} · {origem} · {responsavelNome}" (abaixo de 1366 o responsável vai para a 2ª linha) + StatusBadge prioridade (só urgente) / "atrasada" (pendencia) + ações: "✓ Concluir" (secondary sm) + IconButton "⋯" com menu (Adiar · Editar · Excluir; Editar/Excluir só manual)
<NovaPendenciaModal open viagemId passageiros vendedores pendencia?={PendenciaDto} onClose onSalva />
//  Input "O que precisa ser feito" (required) · DateInput Data (required, default hoje) · Select Responsável · Select Prioridade · Chips "Para quem" (passageiros; "Todos"); em edição (pendencia) sem chips; botão primary "Criar {n} pendência(s)" / "Salvar"
<AdiarModal open pendencia onClose onAdiada />   // DateInput nova data (> atual); 422 data_invalida → campo

// Anexos
<ListaAnexos viagemId={string} reservas={ReservaDto[]} podeEnviar={boolean} />
//  header "Anexos" + contagem + Button secondary sm "+ Anexar" (podeEnviar); item: nome (mono? não: body) + "reserva {n} · {tamanho KB} · {enviadoPorNome}" ou "viagem · sensível · descarte {data}" + ação "Abrir" (tertiary; chama urlDownload e `window.open(url, "_blank", "noopener")`) + IconButton excluir (podeEnviar, ConfirmModal danger)
//  403 no download → toast.error("Você não tem permissão para abrir documentos sensíveis.")
<AnexarModal open viagemId reservas onClose onEnviado />
//  <input type="file"> nativo dentro de Field "Arquivo" (required; máx. 25 MB checado local → erro de campo) · Select Tipo · Select Vínculo ("Viagem" | "Reserva N · fornecedor") · Checkbox "Documento pessoal (sensível)" · DateInput "Descartar em" (só se sensível; default hoje + 180 dias)
//  fluxo: iniciar → enviarArquivo(urlUpload, file) → confirmar → onEnviado; erro de upload → Alert bloco "Falha ao enviar o arquivo. Tente de novo." (o anexo pendente fica invisível; sem limpeza no cliente)

// Serviços
<ListaServicos reserva={ReservaDto} podeEditar />   // useQuery(chavesServicos.daReserva); linhas "{Tipo} · {titulo} · {formatarDataHora(inicio)} → {formatarDataHora(fim)} · {localizadorCia}" + Editar/Excluir (⋯); Button tertiary "+ Serviço"
<ServicoModal open reservaId servico?={ServicoDto} onClose onSalvo />  // Select Tipo (9) · Input Título (required) · Input datetime-local Início/Fim (nativo) · Input Localidade · Input Localizador da cia (mono) · Input Nº do bilhete (mono) · Textarea Observações; 422 → campo (servico_tipo_invalido → tipo, titulo_obrigatorio → titulo, datas_incoerentes → dataFim)

// Card de reserva em leitura (detalhe; ReservationCard continua sendo o do formulário)
<ReservaDetalheCard indice reserva={ReservaDto} verValores={boolean} podeEditar={boolean} aberta onToggle
   onEditar onRemarcar onCancelar onNfse />
//  header igual ao ReservationCard (número, fornecedor, localizador mono, StatusBadge reserva, serviços, venda + "receita R$ X" se verValores, toggle)
//  body (aberta): grid de leitura (Data da compra · NFSe (StatusBadge nfse + número) · Formas · Fluxo · Previsão da comissão · Situação (StatusBadge comissao)) · ResultSummary (se verValores; reutiliza `deDto`) · bloco Cancelamento (se cancelada: motivo, desfecho, reembolso/crédito, "comissão mantida") · <ListaServicos/> · "Histórico de alterações" (useQuery alteracoes; lista data · descrição · valores · multa) · ações (podeEditar e não cancelada): Editar (secondary) · Remarcar… (secondary) · NFSe… (secondary) · Cancelar reserva… (danger tertiary)
```

- [ ] **Step 1: Testes** — `ListaPendencias.test.tsx` (fetch stub): lista 2 abertas; marcar "Mostrar concluídas" refaz a query com `incluirConcluidas=true`; "✓ Concluir" chama `POST …/concluir` com `versao`; automática não mostra Editar/Excluir no menu. `NovaPendenciaModal.test.tsx`: selecionar 2 passageiros muda o botão para "Criar 2 pendências" e envia `clienteIds` com 2; sem título → erro local. `ListaAnexos.test.tsx`: renderiza item "reserva 1 · 212 KB"; "Abrir" chama `/download` e `window.open` (spy). `AnexarModal.test.tsx`: arquivo > 25 MB → erro de campo sem chamar API; fluxo feliz chama `iniciar` → `PUT urlUpload` → `confirmar` na ordem. `ServicoModal.test.tsx`: envia `dataInicio` no formato `yyyy-MM-ddTHH:mm`. `ReservaDetalheCard.test.tsx`: fechado só header; aberto mostra `R$ 520,00` no ResultSummary para a reserva do protótipo; cancelada mostra bloco "Cancelamento" e esconde ações; sem `verValores` não mostra receita nem ResultSummary.

- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck, tokens.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(viagem): pendencias list/modals, anexos list/upload, servicos list/modal, read-only reserva card with history`

---

### Task 13 (front): Busca global no header

**Files:**
- Create: `frontend/src/shell/BuscaGlobal.tsx`, `frontend/src/shell/BuscaGlobal.test.tsx`, `frontend/src/shell/BuscaGlobal.module.css`
- Modify: `frontend/src/shell/GlobalHeader.tsx` (troca o `Input` solto por `<BuscaGlobal ref={busca} />`)

**Depends-on:** T9

**Interfaces:**
```ts
export const BuscaGlobal = forwardRef<HTMLInputElement>(function BuscaGlobal(_, ref))
//  Input (aria-label "Buscar", role="combobox", aria-expanded, aria-controls) + popover (role="listbox") com 3 grupos (Clientes · Viagens · Reservas; role="group" aria-label); debounce 250 ms; q < 2 → fechado; setas navegam, Enter abre o item focado, Esc fecha (useAtalho("escape", fechar, aberto)); clique fora fecha
//  destino: cliente → /clientes/{id} (EmConstrucao até 3.4; ok) · viagem → /viagens/{id} · reserva → /viagens/{viagemId}?reserva={reservaId} (a tab Reservas abre o card)
//  item de viagem: "{titular} · {destino} · <code>{codigo}</code>" + StatusBadge fase; reserva: "<code>{localizador}</code> · {fornecedorNome} · {codigo}"; vazio: "Nada encontrado para “{q}”"
//  guarda de resposta stale: ignora resultado cujo q ≠ q atual
```

- [ ] **Step 1: Testes** — digitar "carl" chama `/busca?q=carl` após o debounce e mostra "Clientes" com 1 item; ArrowDown + Enter navega para `/viagens/<id>` quando o primeiro item é viagem; Esc fecha; "c" (1 char) não chama a API; resposta antiga não sobrescreve a nova.

- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(shell): global search popover (clients, trips, reservas) with keyboard navigation`

---

### Task 14 (front): `ViagemPage` — detalhe com tabs

**Files:**
- Create: `frontend/src/pages/viagens/detalhe/{ViagemPage.tsx,ViagemPage.test.tsx,useViagem.ts,useViagem.test.ts,CabecalhoViagem.tsx,ResumoTab.tsx,ReservasTab.tsx,ReservasTab.test.tsx,FinanceiroTab.tsx,DocumentosTab.tsx,TimelineTab.tsx,TimelineTab.test.tsx,Viagem.module.css}`
- Modify: `frontend/src/shell/rotasModulos.tsx` (`/viagens/:id` → `ViagemPage`)

**Depends-on:** T8, T9, T11, T12 (front); contratos de T2–T7 (backend)

**Interfaces:**
```ts
// useViagem.ts
export function useViagem(id: string): {
  viagem: ViagemDto | undefined; carregando: boolean; erro: unknown; recarregar: () => Promise<void>;
  me: Me; pode: (p: string) => boolean; verValores: boolean;          // verValores = viagem.reservas[0]?.valorTotal !== undefined || pode("reserva.ver_valores")
  vendedores: VendedorDto[]; creditos: CreditoDto[];                    // creditos só quando pode("viagem.editar")
  aplicar: (dto: ViagemDto) => void;                                    // queryClient.setQueryData(chaves.viagem(id), dto) + invalidate lista/pendências/auditoria
  tab: string; setTab: (t: string) => void;                             // ?tab= na URL; default "resumo"; ?reserva=<id> força "reservas" e abre o card
  modal: null | { tipo: "cancelarReserva" | "remarcar" | "nfse"; reserva: ReservaDto } | { tipo: "cancelarViagem" | "transferir" | "usarCredito" }; abrir: (m) => void; fechar: () => void;
}
```
  - `CabecalhoViagem`: `PageHeader title="{titular} · {destino}" meta={<Badge tone="neutral"><code>{codigo}</code></Badge>} status={<StatusBadge fase_viagem/> <StatusBadge comissao faseFinanceira/>} subtitle="{formatarPeriodo(ida, volta)} · {Tipo} · {n} passageiros · Vendedor(a): {vendedorNome} · Agente: {agenteNome ?? "—"}" actions={[Transferir (secondary; pode("viagem.transferir")), "Cancelar viagem…" (danger; pode("viagem.editar") && !cancelada), Editar (primary → /viagens/{id}/editar; pode("viagem.editar") && !cancelada)]}`. Viagem cancelada: `Alert tone="danger"` "Viagem cancelada em {data}: {motivo}".
  - Tabs (`Tabs` do contrato, com `count`): `resumo` "Resumo" · `reservas` "Reservas" (count reservas ativas) · `financeiro` "Financeiro" (só `verValores`) · `pendencias` "Pendências" (count abertas — segunda query leve reutilizando `chavesPendencias.daViagem(id,false)`) · `documentos` "Documentos" (count anexos) · `timeline` "Timeline" (só `pode("auditoria.ver")`). Filtrar tabs indisponíveis antes de renderizar (≤ 6).
  - `ResumoTab`: `FaixaResumo` (Venda total · Custo dos fornecedores · Comissão da vendedora (`repasse.valor`, com StatusBadge repasse) · Despesas da viagem · Resultado da viagem (destaque, tooltip "Receita das reservas − comissão da vendedora − despesas vinculadas"); extra "Comissões recebidas" = `resumo.receitaRecebida`) — só com `resumo` presente; sem `ViagemVerResultado`, faixa reduzida: Venda total · Custo · Receita da agência (soma `receitaPrevista` das reservas) quando `verValores`; sem valores, nenhuma faixa. `split`: bloco "Reservas" (lista compacta, clique → `setTab("reservas")` + abre card) · bloco "Passageiros" (nome + badge titular; "Passaporte …" fica para 3.4 — mostrar só nome) · bloco "Próximas pendências" (2 mais próximas abertas; link "ver todas na aba Pendências").
  - `ReservasTab`: `Alert info` "Crédito disponível: {n} · {valor total}" com botão "Usar crédito…" quando `creditos.some(c => c.status === "disponivel")`; `ReservaDetalheCard[]` (canceladas por último, recolhidas); botão `business` "+ Adicionar reserva" → `/viagens/{id}/editar` (o usuário usa Ctrl+Enter na edição; abrir um card novo por `?nova=1` fica como deferida no BACKLOG).
  - `FinanceiroTab` (leitura; 3.5 completa com movimentos e despesas): `FaixaResumo` (Receita prevista · Comissões recebidas · Comissão da vendedora + badge repasse · Despesas · Resultado — só com `resumo`) · bloco "Comissões a receber" (reservas ativas com `valorEsperadoOperadora > 0`: "{fornecedor} · {localizador}" / "previsto para {formatarData(dataPrevistaComissao)}" · `StatusBadge comissao situacaoComissao` · `MoneyValue` do esperado · sem botão). Blocos "Movimentos" e "Despesas" **não são renderizados** nesta fase (sem placeholder).
  - `DocumentosTab`: `<ListaAnexos viagemId reservas podeEnviar={pode("anexo.enviar")} />` (documentos dos passageiros: 3.4).
  - `TimelineTab`: `useQuery(chavesAuditoria.daViagem(id))`; lista de eventos (bolinha por tipo: `money` para `movimento_financeiro`/`repasse`, `warn` para cancelamentos, normal demais): título · subtítulo · "{formatarDataHora(criadoEm)} · {usuarioNome ?? "sistema"}" · `motivo` quando existe · `<details>` "Ver detalhes" com tabela campo / de / para (`JSON.stringify` para não-string; dinheiro formatado quando a chave começa com `valor_`/`rav_`/`taxa_`/`multa_`).
  - `ViagemPage`: `Skeleton` durante carga; erro → `Alert danger` + "Tentar de novo"; `useAtalho("escape", fechar, modal !== null)` já é do `Modal`. Modais montados uma vez no fim da página, controlados por `modal`.

- [ ] **Step 1: Testes** — `useViagem.test.ts`: `?tab=pendencias` seleciona a tab; `?reserva=<id>` força `reservas`; `aplicar(dto)` atualiza o cache e a próxima leitura. `ViagemPage.test.tsx` (fetch stub com viagem do protótipo: 2 reservas, resumo, repasse; `/pendencias`, `/anexos`, `/creditos`, `/usuarios/vendedores` vazios): header "Carlos Mendes · Lisboa" + `VG-…`; faixa com `R$ 1.640,00`; tab "Reservas" mostra 2 cards; tab "Timeline" ausente para `me` sem `auditoria.ver`; "Cancelar viagem…" abre o modal; viagem `cancelada` esconde Editar. `ReservasTab.test.tsx`: crédito disponível mostra o Alert com "Usar crédito…"; clicar "Cancelar reserva…" no card 1 abre `CancelarReservaModal` com "Cancelar reserva 1". `TimelineTab.test.tsx`: renderiza título/subtítulo/usuário; "Ver detalhes" mostra "valor_comissao" com `R$ 1.000,00 → R$ 2.000,00`.

- [ ] **Step 2–4:** RED → implementar (`ViagemPage.tsx` ≤ 200 linhas; cada tab ≤ 200) → vitest, lint, typecheck, build.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(viagens): trip detail page with summary, reservas, financeiro (read), pendencias, documentos and timeline tabs`

---

### Task 15 (front + backend): E2E, styleguide, dev docs, tempo

**Files:**
- Create: `frontend/e2e/viagens.spec.ts`, `frontend/e2e/api.ts` (helper: login por `request` e `POST /viagens` para semear)
- Modify: `frontend/src/pages/styleguide/StyleguidePage.tsx` (+ seções `sg-tabela`: `DataTable` com 3 linhas/estado loading/vazio + `Paginacao`; `sg-kpi`: informativo e acionável; `sg-faixa`: `FaixaResumo`), `frontend/e2e/styleguide.spec.ts` (+ `tabela`, `kpi`, `faixa`; regenerar baselines win32 + linux)
- Modify: `backend/scripts/dev.md` (+ MinIO: `docker compose up -d` sobe `minio`; console em `http://localhost:9001`; bucket `meridiano-dev` criado por `minio-init`; `appsettings.Development.json` já aponta), `backend/scripts/seed-dev.sql` (+ 2º agente `ana.agente@viva.dev` ativo sem senha para "Transferir")

**Depends-on:** T1–T14

- [ ] **Step 1: `e2e/viagens.spec.ts`**
```ts
import { expect, test } from "@playwright/test";
import { criarViagemViaApi, loginUi } from "./api";

test.describe("viagens", () => {
  test("lista → filtro por aba → abre detalhe → cancela reserva com crédito → timeline", async ({ page, request }) => {
    const { id, codigo } = await criarViagemViaApi(request, { destino: "Lisboa E2E", reservas: 2 });
    await loginUi(page);
    await page.goto("/viagens?aba=todas&idaPreset=qualquer");
    await expect(page.getByRole("row", { name: new RegExp(codigo) })).toBeVisible();
    await page.getByRole("tab", { name: /Em emissão/ }).click();
    await page.getByRole("row", { name: new RegExp(codigo) }).click();
    await expect(page).toHaveURL(new RegExp(`/viagens/${id}`));
    await expect(page.getByRole("heading", { name: /Carlos Mendes · Lisboa E2E/ })).toBeVisible();
    await page.getByRole("tab", { name: /Reservas/ }).click();
    await page.getByRole("button", { name: "Expandir" }).first().click();
    await page.getByRole("button", { name: "Cancelar reserva…" }).click();
    await page.getByLabel("Motivo").fill("cliente desistiu");
    await page.getByLabel("Desfecho").selectOption("credito");
    await page.getByLabel("Valor do crédito").fill("9000");
    await page.getByRole("button", { name: "Cancelar reserva" }).click();
    await expect(page.getByText("Cancelada").first()).toBeVisible();
    await expect(page.getByText(/Crédito disponível/)).toBeVisible();
    await page.getByRole("tab", { name: "Timeline" }).click();
    await expect(page.getByText("Reserva cancelada").first()).toBeVisible();
  });

  test("busca global acha a viagem pelo localizador", async ({ page, request }) => {
    const { id } = await criarViagemViaApi(request, { destino: "Porto E2E", reservas: 1, localizador: "E2EPRT1" });
    await loginUi(page);
    await page.keyboard.press("Control+K");
    await page.getByRole("combobox", { name: "Buscar" }).fill("e2eprt");
    await page.getByRole("option", { name: /E2EPRT1/ }).click();
    await expect(page).toHaveURL(new RegExp(`/viagens/${id}`));
  });
});
```
`e2e/api.ts`: `loginUi(page)` = o `login` de `nova-viagem.spec.ts`; `criarViagemViaApi(request, opts)` faz `POST /api/v1/auth/login` com `DEV_USER`, `GET /clientes/busca?q=Carlos`, `GET /fornecedores`, `POST /viagens` (reservas `pendente`, CVC/Decolar, `valorTotal 10000/3000`), devolve `{ id, codigo }`. `baseURL` da API = `http://localhost:5000` (proxy do Vite não vale para `request`).

- [ ] **Step 2: Rodar** com API + seed + MinIO (`backend/scripts/dev.md`): `npx playwright test e2e/viagens.spec.ts e2e/nova-viagem.spec.ts` → verdes nos 2 viewports; anotar o tempo de `nova-viagem` (4 reservas) para o BACKLOG.

- [ ] **Step 3: Styleguide + baselines** — `npx playwright test e2e/styleguide.spec.ts --update-snapshots` (win32) e no container `mcr.microsoft.com/playwright:v1.63.0-noble` (linux), como em 3.1/3.2.

- [ ] **Step 4: Reportar** (tempos por viewport). Commits: frontend `test(e2e): trip list/detail/cancel flow and global search; styleguide table, kpi and faixa sections`; backend `chore(dev): minio in compose docs, second agent in seed`.

---

### Task 16 (root): Docs e fechamento

**Files:**
- Modify: `docs/BACKLOG.md` (3.3 concluída com contagens; tempo automatizado de `nova-viagem` re-medido em linha própria; remover das "Deferidas da 3.2" o que fechou: `ilike` escape, `reserva cancelada` no PUT, `excetoViagemId`, `duplicada` por vendedor, pendências órfãs, `sem_permissao_vendedor` 403, `repasse_pago` no valor; da 3.1: rota-guard; novas deferidas: objeto do storage após `DELETE /anexos` (job 3.6), `X-Motivo`/`app.motivo` por header (3.5), `?nova=1` na edição, documentos de passageiro na tab Documentos (3.4), Timeline sem `auditoria.ver` para Agente (revisar no piloto), `ReservaDuplicada` índice `lower(trim())`, mais o que os reviews levantarem)
- Modify: `docs/autorizacao-por-operacao.md` (linhas da tabela "Permissões" deste plano; nota de R12; nota "pendência/serviço/anexo não renovam versão da viagem"; `sem_permissao_vendedor` → 403)
- Modify: `docs/superpowers/plans/2026-09-08-fase-3-master.md` (linha 3.3: "(concluído: 16 tasks, 5 ondas)"; se algum endpoint divergir do previsto, atualizar; D5 marcada aplicada)
- Modify: `CLAUDE.md` (linha Estado: 3.3 ✓ com contagens; migrations 0001–0014; próximo: 3.4 e 3.5 com contrato de dependência)
- Modify: `regras-e-escopo-v2.md` §4.7 (nota: "Ruling 3.3 — consumo de crédito não altera valores da reserva; vínculo por `reserva_uso_id`"), §9 (nota: transferência = `agente_id`, permissão `viagem.transferir`)

**Depends-on:** T15

- [ ] **Step 1–2:** editar; controlador commita no root: `docs: fase 3.3 viagens e reservas done — backlog, authorization table, state line, rulings`

---

## Self-review (feito ao escrever)

- **Spec §4.6** remarcação em `reserva_alteracao` com multa informativa → T3 `RemarcarAsync` + T11 `RemarcarModal` + histórico no card (T12) ✓.
- **§4.7** cancelamento de reserva (status, `cancelada_em`, motivo, desfecho, reembolso, `comissao_mantida`), crédito com validade vinculado depois à reserva que o consome → T3 (`CancelarAsync`, `Creditos`), T11 (`DesfechoFields`, `UsarCreditoModal`), T14 (Alert de crédito) ✓ · viagem cancelada exige reservas canceladas junto → T3 `CancelarViagemAsync` + T11 `CancelarViagemModal` ✓ · repasse pago fica → `ReavaliarRepasseAsync` já ignora `pago` ✓.
- **§4.8** NFSe (status, tomador, número, data) → T3 + T11 `NfseModal` ✓ (R12 para Financeiro).
- **§6/§6.1** fases pela view; situação da comissão por reserva (`divergente` incluído) → T1 `SituacaoComissao` + mapas existentes ✓.
- **§7.2** DTO por perfil em lista, detalhe, auditoria, anexos → T1/T2/T6/T7 ✓; `ClienteVerDocumento` para sensível + `log_acesso_documento` → T6 ✓.
- **§8** motivo obrigatório ao cancelar → T3 ✓ · timeline legível com frases e "Ver detalhes" (contrato §4.4) → T7 + T14 ✓ · soft delete em serviço/anexo → T5/T6 ✓ · período fechado → competência em cancelar/remarcar ✓ (header de motivo fica para 3.5, anotado).
- **§9** pendências com data, responsável, viagem/pessoa, prioridade, multi-passageiro (decisão 39), adiar com `adiada_de`, "Mostrar concluídas" → T4 + T12 ✓ · cancelar viagem cancela automáticas → T1/T3 ✓ · remarcação reabre concluída → `GerarPendenciasAsync` existente + T3 ✓ · transferência entre agentes → R4/T3 ✓ · serviços/dados do aéreo → T5/T12 ✓ · anexo por reserva → T6/T12 ✓.
- **§10** busca global → T2/T13 ✓ · CSV → 3.6 (D3) anotado ✓.
- **Decisão 38** filtros (compra, NFSe, fornecedor multi, fase, vendedor, tipo) → T2/T10 ✓. **Decisão 30** CPF nunca na lista/busca → `BuscaClienteDto` sem CPF ✓.
- **Contrato §3/§4.4** `DataTable` + células + `KpiCard` + linha inteira clicável + filtros "busca + 2 principais + Filtros ● N" + linha de pendência com uma ação + `⋯` → T8/T10/T12 ✓; laranja só em "+ Nova viagem" (lista) e "+ Adicionar reserva" (detalhe) ✓; modal só decisão/risco ✓.
- **Contratos transversais**: lock competência → viagem em todas as operações (T3 cabeçalho "Ordem de locks") ✓; `for update` + `TocarViagemAsync` ✓; exceção documentada para pendência/serviço/anexo ✓; anexos sem rede na transação, chave gerada no servidor, `confirmado_em` (0014) ✓; `ViagemVerProprias` em todas as leituras novas ✓.
- **Backlog "decidir em 3.3"**: `paraRequest` com cancelada → R2 (T3 + T9) ✓ · PUT ressuscita cancelada → R2 ✓ · pendências órfãs → R14 (T1) ✓ · `excetoViagemId`, `duplicada` por vendedor, `ilike` escape → T2 ✓ · `sem_permissao_vendedor` 403 → T3 ✓ · rota-guard → R15 (T9/T10) ✓ · `repasseValor` com repasse pago → T3 ✓.
- **Placeholders**: nenhum "TBD"; cada task tem código-esqueleto ou props exatas e testes com dados concretos. Passagem a limpo feita em T14 `FinanceiroTab` (decisão: omitir blocos de 3.5, sem placeholder) e `ReservasTab` (`?nova=1` vira deferida).
- **Tipos**: DTOs C# (Contrato) = TS (T9) campo a campo; `SemPermissaoException` criada em T3 e usada em T6 (nota de coordenação em T6 `Depends-on`); `TravarViagemDaReservaAsync` (T1) usada em T3/T5/T6; `Rotinas.Cancelar/TransferirPendenciasAutomaticasAsync` (T1) usadas em T3; `FaixaResumo`/`DateCell`/`formatarData` (T8) usadas em T12/T14; `useOperacao` (T11) usado pelos modais; `chaves*` (T9) usadas em T10–T14 ✓.
- **Ondas**: T1 registra todos os esqueletos em `Endpoints.cs`, então T2–T7 não tocam esse arquivo ✓; T2 (`ViagensEndpoints.cs`, `ViagensConsultas.cs`, `ViagensLista.cs`, `ViagemListaDtos.cs`, `Busca/`, `Pessoas/PessoasService.cs`, `Comum/Sql.cs`) × T3 (`ViagensOperacoesEndpoints.cs`, `ViagensOperacoes.cs`, `ReservaOperacoes.cs`, `Creditos.cs`, `OperacoesDtos.cs`, `ReservaGravacao.cs`, `ViagensService.cs`, `ViagensEdicao.cs`, `Comum/SemPermissaoException.cs`, `Infra/TratadorDeExcecoes.cs`) disjuntos ✓; T6 depende de `SemPermissaoException` (T3), por isso fica na onda 2 (tabela de Ondas). Front: T10 (`pages/viagens/lista/`, `rotasModulos.tsx`) × T11 (`components/ViagemOperacoes/`) × T12 (`components/Pendencias|Anexos|Servicos`, `Reserva/ReservaDetalheCard.tsx`, `reserva.ts`) × T13 (`shell/BuscaGlobal*`, `shell/GlobalHeader.tsx`) disjuntos ✓; T9 toca `shell/RotaProtegida.tsx` (onda 0) e T10 `rotasModulos.tsx` (onda 1) ✓; T14 toca `rotasModulos.tsx` na onda 2 ✓.
