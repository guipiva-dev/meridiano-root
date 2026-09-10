# Meridiano — Fase 3.4 — Cadastros: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execução em ondas:** segue `.claude/rules/parallel-subagent-driven-development.md` **e** o contrato `2026-09-09-fase-3-4-3-5-contrato.md` (Task 0 já commitada; propriedade de arquivos §3; congelados §4; teto de implementadores). Implementadores **não commitam**; o controlador commita uma task por vez, no repo certo, com pathspec. Agentes especialistas da tabela do CLAUDE.md não existem no harness: usar `general-purpose` e `code-reviewer` genérico.

**Goal:** cadastros completos com página própria (decisão 32): Pessoa com tabs Dados · Documentos · Pendências · Viagens · Atendimentos, lista de Clientes com filtros; Grupos/empresas; Fornecedores com tabs Dados · Financeiro (regra de pagamento **versionada** por `vigente_desde`, previsões já gravadas intocadas) · Reservas. Telas 08–13 do protótipo congelado.

**Architecture:** backend cresce dentro de `Modules/Pessoas` (lista/detalhe/PUT em `ClientesService`; documentos, atendimentos em serviços próprios; pendências e anexos da pessoa em `Modules/Pendencias`/`Modules/Anexos`), ganha `Modules/Grupos` e completa `Modules/Fornecedores` (`FornecedoresLeitura` + versões de regra). Nenhuma migration além da 0015 (T0). Front: três módulos de página (`pages/clientes`, `pages/grupos`, `pages/fornecedores`) sobre a receita de formulário de 3.2 (`react-hook-form` + `useSalvamento` + `Page dirty` + `versao`), componentes de domínio em `components/Cadastros/`, generalização de `ListaPendencias`/`ListaAnexos` para escopo pessoa.

**Tech Stack:** .NET 10 · Dapper · Npgsql · PostgreSQL 17 · xUnit + Testcontainers · React 19 · react-router 8 · TanStack Query 5 · react-hook-form 7 · Vitest · Playwright. Nenhuma dependência nova.

**Spec:** `regras-e-escopo-v2.md` §2 (pessoa, grupo, fornecedor), §3 (grupo opcional, fornecedor sempre existe), §4.5 (regra por janelas/prazo, **vigência**), §7.1/§7.2 (`cliente.ver_documento`, `ClienteVerProprios`), §8 (LGPD: `log_acesso_documento`), §9 (pendências da pessoa: as suas **e** as das viagens em que é passageira; "+ Nova pendência" exige data; atendimentos por mês, anos anteriores recolhidos), decisões 27, 30, 32, 33, 34 · plano-mestre linha 3.4 e "Contratos transversais" (Autorização, Anexos) · `docs/design-system-contrato.md` §3, §4, §4.1 (cadastro em página própria, CPF mascarado, pendências da pessoa), §4.2 (tabs: Pessoa e Fornecedor), §4.4 · `docs/design/prototipo-v1.html` `#s-clientes` `#s-pessoa` `#s-grupos` `#s-grupo` `#s-fornecedores` `#s-fornecedor` · `docs/autorizacao-por-operacao.md` · `docs/BACKLOG.md` ("Deferidas da 3.3": documentos de passageiro na tab Documentos; `ClienteVerProprios` completo em anexos).

## Global Constraints

- Tudo do contrato (§1, §3, §4, §5): branch `feat/fase-3-4-3-5`; só arquivos de que 3.4 é dona; `Endpoints.cs`, `Guardas.cs`, `PostgresFixture.cs`, `rotasModulos.tsx`, `status.ts`, `datas.ts`, `http.ts`, `components/index.ts` **não** são editados (T0 já fez); rotas só em `pages/{clientes,grupos,fornecedores}/rotas.tsx`; barrel `components/cadastros.ts`.
- Backend: `TreatWarningsAsErrors=true`; `dotnet format` limpo; ≤ ~350 linhas por arquivo. Toda query em `DbSessao`, filtra `agencia_id` e `excluido_em is null` (fornecedor: `ativo`, sem `excluido_em`). Todo `*_id` do payload → `Guardas.ReferenciaAsync` na transação. Erros: `RegraDeNegocioException` → 422; `ConflitoConcorrenciaException` → 409; gates dentro do serviço → `SemPermissaoException` (403).
- Concorrência por `xmin::text` (`versao`) em cliente, grupo, fornecedor, documento, atendimento: `update … where id = @id and agencia_id = @agencia and excluido_em is null and xmin::text = @versao` → 0 linhas → (linha existe? 409 : 422 `nao_encontrado`).
- DTO por perfil: sem `ClienteVerDocumento`, `cpf` (detalhe) e `documento.numero` **não existem** no JSON (`JsonIgnore(WhenWritingNull)`); listas mostram `cpfMascarado` (decisão 30); leitura de `documento_cliente` com permissão grava `log_acesso_documento` (uma linha por documento devolvido, `documento_id`). `ClienteVerProprios` sem `ClienteVer` filtra `exists (select 1 from viagem_passageiro vp join viagem v on v.id = vp.viagem_id where vp.cliente_id = c.id and v.vendedor_id = @usuario and v.excluido_em is null)` em lista, detalhe, viagens, documentos, atendimentos, pendências e anexos da pessoa. Sem `ReservaVerValores`, valores (venda, esperado, recebido, receita) não existem.
- Listas paginadas: `pagina ≥ 1`, `tamanho ∈ 1..100` (default 25), `total`, ordenação por lista branca (422 `ordem_invalida`). Arrays nunca `null`.
- Front: CSS Modules + `tokens.css`; sem hex/`font-size`/`@media` fora dos breakpoints; só lucide; ≤ 350 linhas/arquivo; `npm run lint`, `typecheck`, `test`, `build` verdes; `pode()` só esconde. Status via `apresentacaoStatus`. Formulários: `react-hook-form` + `useSalvamento` + `Page dirty titulo onSalvarESair` + `PageHeader dirty salvoEm` + `useAtalho("ctrl+s")` + `versao` no PUT; 409 → `Alert warning` "Alguém alterou… Recarregar"; 422 → campo via mapa próprio ou `Alert danger` de bloco. Cadastros abrem em página própria; ações `Fechar` (tertiary) e `Salvar` (primary). "+ Nova pessoa / grupo / fornecedor" = `primary` (protótipo; `business` fica só onde o contrato §4.1 lista).
- Commits Conventional Commits em inglês com rodapé de atribuição da sessão.

---

## Rulings desta fase

| # | Decisão | Motivo |
|---|---|---|
| R1 | **Tabs da Pessoa = protótipo:** Dados · Documentos · Pendências · Viagens · Atendimentos (5). Sem "resumo lateral fixo" (§4.1 fala nele; o protótipo congelado não tem). | Protótipo vence (mesmo critério da 3.3 R3). |
| R2 | **CPF completo no detalhe com `ClienteVerDocumento` não grava log.** `log_acesso_documento` cobre `documento_cliente` (passaporte, RG, visto…) e anexo sensível. | Logar cada abertura da página de pessoa vira ruído; o schema vincula o log a documento/anexo. Registrado no BACKLOG para revisão LGPD no piloto. |
| R3 | **Documentos:** CRUD em `documento_cliente` (tipo ∈ rg·cpf·passaporte·visto·certidao·outro). Arquivo do documento = anexo da pessoa (`POST /anexos` com `clienteId`, `sensivel = true` por padrão) listado na mesma tab; sem coluna de vínculo documento↔anexo (não existe no schema; BACKLOG). | Protótipo mostra "Anexo: passaporte-lucia.jpg" mas o schema não liga os dois. |
| R4 | **Pendências da pessoa:** `GET /clientes/{id}/pendencias` = `cliente_id = id` **ou** `viagem_id in (viagens em que é passageira)`; `POST /clientes/{id}/pendencias` cria **uma** pendência com `cliente_id` (+ `viagem_id` opcional, exigindo que a pessoa seja passageira). Checklist derivado (decisão 33, contrato §4.1/§4.3) fica para o job `pendencias_derivadas` (3.6): esta tab lista o que está gravado. Escrita exige `ClienteEditar`. | Spec §9; job é 3.6. |
| R5 | **Atendimentos = `interacao`** (canal ∈ whatsapp·ligacao·presencial·email·outro; `resumo`; `ocorrido_em`; `usuario_id` = quem registrou). CRUD com soft delete (0015). Filtro "Tipo: só automáticos" do protótipo **não entra** (não há automáticos na v1). Agrupamento por mês/ano é do front. | Tabela existe desde 0001, sem uso. |
| R6 | **`POST /clientes` continua devolvendo um superconjunto de `ClienteBuscaDto`** (`id`, `nome`, `telefone`, `cpf?`) — `ClienteDto` completo —, e o request vira `ClienteRequest` com tudo opcional exceto `nome`. `PessoaInlineModal` (congelado) continua funcionando. **CPF duplicado** é pré-checado → 422 `cpf_duplicado` (corrida residual cai no 409 `duplicado` do tratador). | Contrato: endpoints de 3.2 usados pela Nova viagem não mudam de forma. |
| R7 | **Fornecedor:** `GET /fornecedores` (3.2) **intocado**; lista da tela é `GET /fornecedores/resumo`. `POST /fornecedores` aceita `FornecedorRequest` completo (só `nome`+`tipo` obrigatórios) e devolve o mesmo `FornecedorDto`. **Nova versão da regra** = `POST /fornecedores/{id}/regras { vigenteDesde, janelas[] }` inserindo N linhas com o mesmo `vigente_desde` (> maior existente, senão 422 `vigencia_invalida`); nunca `update`/`delete` em `regra_pagamento_fornecedor`; reservas existentes mantêm `data_prevista_comissao` (teste de invariante). Prazo em dias (`prazo_comissao_dias`) segue **não versionado** (schema); trocar de janelas para prazo puro não é suportado em 3.4 (422 `janelas_obrigatorias`; BACKLOG). | Spec §4.5 e decisão 29; `PrevisaoAsync` (3.2) já escolhe a versão pela `data_compra`. |
| R8 | **Grupos:** leitura exige `ClienteVer` (vendedor externo recebe 403 e a rota `/clientes/grupos` mostra "Sem permissão"; o item da subnav continua visível — `navegacao.ts` é de 3.5). Vincular/desvincular pessoa = `update cliente set grupo_id`. Soft delete do grupo desvincula as pessoas na mesma transação. CNPJ só quando `tipo = empresa` (senão ignorado). | Grupo "não é entidade financeira" (spec §2). |
| R9 | **Lista de clientes:** filtros `q` (nome, CPF só dígitos, telefone, e-mail — `ilike` com `Sql.EscaparLike`), `grupoId`, `pendencia` (com · urgente · sem), `ultimaViagem=recompra` (última `data_volta` < hoje − 330 dias, ou nunca viajou), ordem `nome | ultima_viagem`, paginação; `contadores` {pessoas, grupos, passaportesVencendo (validade em ≤ 180 dias)}. Visíveis: busca + Grupo + Pendências; "Última viagem" no painel "Filtros ● N" (contrato §4.4). CSV → 3.6. | Protótipo `#s-clientes` + decisão 34. |
| R10 | **Generalização de componentes de 3.3** (arquivos de 3.4): `ListaPendencias` aceita `{ viagemId, passageiros }` **ou** `{ clienteId, viagens }` (props de viagem inalteradas — `ViagemPage` é congelada); `ListaAnexos` aceita `{ viagemId, reservas }` **ou** `{ clienteId }`; `NovaPendenciaModal` ganha "Viagem relacionada (opcional)" no escopo pessoa; `AnexarModal` no escopo pessoa fixa vínculo cliente e `sensivel` marcado por padrão. | Reuso em vez de cópia; as chamadas existentes não mudam. |
| R11 | **`DocumentosTab` da viagem** (arquivo de 3.4) passa a mostrar, além dos anexos, um bloco "Documentos dos passageiros" (`GET /clientes/{id}/documentos` por passageiro, só tipo · número (se permissão) · validade com badge) — leitura; edição na página da pessoa (link). | Deferida da 3.3. |
| R12 | **UF** = `Select` com as 27 siglas (constante em `lib/documentos.ts`); **Origem** = `Input` livre (`origem_lead` é texto); **Tags** = chips + input (Enter adiciona, Backspace vazio remove a última); **Grupo** no formulário da pessoa tem opção "+ Criar grupo…" que abre `GrupoInlineModal` (nome + tipo) e seleciona o criado. | Protótipo `#s-pessoa`. |

---

## Ondas (3.4)

| Onda | Tasks | Motivo |
|---|---|---|
| 1 | T1 (backend clientes) · T2 (backend documentos/atendimentos/pendências/anexos da pessoa) · T3 (backend grupos) · T4 (backend fornecedores) · T5 (front api/lib/componentes base) | esqueletos e registro já feitos em T0; pastas/arquivos disjuntos (T1: `ClientesService.cs`, `ClientesEndpoints.cs`, `PessoaDtos.cs`, `PessoasService.cs`, `PessoasEndpoints.cs`; T2: `DocumentosService.cs`, `AtendimentosService.cs`, `PessoaDetalheEndpoints.cs`, `PessoaDetalheDtos.cs`, `Modules/Pendencias/*`, `Modules/Anexos/*`) |
| 2 | T7 (front tabs da pessoa + generalizações) · T8 (front grupos) · T9 (front fornecedores) | usam T5; `components/Cadastros/pessoa/*`, `pages/grupos/*`, `pages/fornecedores/*` disjuntos; cada um edita só o próprio `rotas.tsx` |
| 3 | T6 (front lista de clientes + `PessoaPage` compondo as tabs de T7) | compõe T7; edita `pages/clientes/rotas.tsx` e o barrel |
| 4 | T10 (E2E) | precisa de tudo |
| 5 | T11 (docs, root) — **serial com o fechamento de 3.5** (contrato §1.8) | fechamento |

Lembrete do contrato: ondas de 3.4 e 3.5 podem se sobrepor (teto 6 implementadores, 4 no backend).

---

## Contrato de API (fonte única para backend e front)

```
GET    /api/v1/clientes?q&grupoId&pendencia&ultimaViagem&ordem&direcao&pagina&tamanho   → 200 ListaClientesDto
GET    /api/v1/clientes/{id}                                     → 200 ClienteDto
POST   /api/v1/clientes                 ClienteRequest           → 201 ClienteDto      (3.2: era NovoClienteRequest; superconjunto)
PUT    /api/v1/clientes/{id}            ClienteRequest (+versao) → 200 ClienteDto | 409
GET    /api/v1/clientes/{id}/viagens                             → 200 ViagemDaPessoaDto[]
GET    /api/v1/clientes/{id}/documentos                          → 200 DocumentoDto[]   (grava log_acesso_documento com ClienteVerDocumento)
POST   /api/v1/clientes/{id}/documentos DocumentoRequest         → 201 DocumentoDto
PUT    /api/v1/documentos/{id}          DocumentoRequest (+versao) → 200 DocumentoDto | 409
DELETE /api/v1/documentos/{id}                                   → 204
GET    /api/v1/clientes/{id}/atendimentos?canal                  → 200 AtendimentoDto[]
POST   /api/v1/clientes/{id}/atendimentos AtendimentoRequest     → 201 AtendimentoDto
PUT    /api/v1/atendimentos/{id}        AtendimentoRequest (+versao) → 200 AtendimentoDto | 409
DELETE /api/v1/atendimentos/{id}                                 → 204
GET    /api/v1/clientes/{id}/pendencias?incluirConcluidas        → 200 PendenciaDto[]   (3.3 DTO)
POST   /api/v1/clientes/{id}/pendencias NovaPendenciaPessoaRequest → 201 PendenciaDto
GET    /api/v1/clientes/{id}/anexos                              → 200 AnexoDto[]       (3.3 DTO)
GET    /api/v1/grupos?q&pagina&tamanho                           → 200 ListaGruposDto
GET    /api/v1/grupos/{id}                                       → 200 GrupoDto
POST   /api/v1/grupos                   GrupoRequest             → 201 GrupoDto
PUT    /api/v1/grupos/{id}              GrupoRequest (+versao)   → 200 GrupoDto | 409
DELETE /api/v1/grupos/{id}                                       → 204
POST   /api/v1/grupos/{id}/pessoas      { clienteId }            → 200 GrupoDto
DELETE /api/v1/grupos/{id}/pessoas/{clienteId}                   → 204   (front refaz `obter`; `api.delete` devolve void)
GET    /api/v1/fornecedores/resumo?q&ativo&pagina&tamanho        → 200 ListaFornecedoresDto
GET    /api/v1/fornecedores/{id}                                 → 200 FornecedorDetalheDto
POST   /api/v1/fornecedores             FornecedorRequest        → 201 FornecedorDto    (3.2 DTO; só nome+tipo obrigatórios)
PUT    /api/v1/fornecedores/{id}        FornecedorRequest (+versao) → 200 FornecedorDetalheDto | 409
POST   /api/v1/fornecedores/{id}/regras NovaVersaoRegraRequest   → 200 FornecedorDetalheDto
GET    /api/v1/fornecedores/{id}/reservas?pagina&tamanho         → 200 ListaReservasFornecedorDto
```

Permissões (acrescentar em `docs/autorizacao-por-operacao.md` na T11):

| Operação | Permissão | Observação |
|---|---|---|
| `GET /clientes`, `GET /clientes/{id}`, `/viagens`, `/documentos`, `/atendimentos`, `/pendencias`, `/anexos` | `ClienteVer` ou `ClienteVerProprios` (filtro por viagens do vendedor) | sem nenhuma → 403 (padrão `SemVisibilidade` de `ViagensEndpoints.cs:47`, reproduzido em `ClientesEndpoints`) |
| `POST/PUT /clientes`, `POST/PUT/DELETE` documentos, atendimentos, `POST /clientes/{id}/pendencias` | `ClienteEditar` | |
| `documento.numero`, `cliente.cpf` (detalhe) | `ClienteVerDocumento` | documentos: grava `log_acesso_documento` por linha devolvida |
| `GET /grupos*` | `ClienteVer` | R8 |
| `POST/PUT/DELETE /grupos*` | `ClienteEditar` | |
| `GET /fornecedores/resumo`, `GET /fornecedores/{id}` | qualquer autenticado | como `GET /fornecedores` |
| `GET /fornecedores/{id}/reservas` | `ViagemVer` ou `ViagemVerProprias` | valores só com `ReservaVerValores`; `receitaAno` da lista/detalhe só com `ReservaVerValores` |
| `PUT /fornecedores/{id}`, `POST /fornecedores/{id}/regras` | `FornecedorEditar` | |

```csharp
// ---- Modules/Pessoas/PessoaDtos.cs (T1; substitui NovoClienteRequest) ----
public sealed record ClienteRequest(string Nome, string? Cpf, string? Email, string? Telefone, string? Whatsapp, DateOnly? DataNascimento, string? Cidade, string? Uf,
    string? OrigemLead, string[]? Tags, string? Observacoes, string? ContatoEmergencia, Guid? GrupoId, string? Versao);
public sealed record UltimaViagemDto(Guid Id, string Codigo, string Destino, DateOnly? DataIda, DateOnly? DataVolta, bool Cancelada);
public sealed record ResumoClienteDto(int Viagens, UltimaViagemDto? UltimaViagem, int PendenciasAbertas, int PendenciasUrgentes, int ClienteDesde);
public sealed record ClienteDto(Guid Id, string Versao, string Nome, [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Cpf,
    string? Email, string? Telefone, string? Whatsapp, DateOnly? DataNascimento, string? Cidade, string? Uf, string? OrigemLead, string[] Tags, string? Observacoes,
    string? ContatoEmergencia, Guid? GrupoId, string? GrupoNome, DateTimeOffset CriadoEm, ResumoClienteDto Resumo);
public sealed record ListaClienteDto(Guid Id, string Nome, string? CpfMascarado, int? Idade, string? GrupoNome, string? Contato, int PendenciasAbertas, int PendenciasUrgentes,
    string? UltimaViagemDestino, DateOnly? UltimaViagemData, bool UltimaViagemCancelada, int Viagens);
public sealed record ContadoresClientesDto(int Pessoas, int Grupos, int PassaportesVencendo);
public sealed record ListaClientesDto(ListaClienteDto[] Itens, int Total, int Pagina, int Tamanho, ContadoresClientesDto Contadores);
public sealed record FiltroClientes(string? Q, Guid? GrupoId, string? Pendencia, string? UltimaViagem, string? Ordem, string? Direcao, int Pagina = 1, int Tamanho = 25);
public sealed record ViagemDaPessoaDto(Guid Id, string Codigo, string Destino, string Tipo, DateOnly? DataIda, DateOnly? DataVolta, bool Titular, string FaseOperacional, string FaseFinanceira,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? VendaTotal);
// ClienteBuscaDto (3.2) permanece para GET /clientes/busca.

// ---- Modules/Pessoas/PessoaDetalheDtos.cs (T2) ----
public sealed record DocumentoRequest(string Tipo, string? Numero, DateOnly? Emissao, DateOnly? Validade, string? PaisEmissor, string? Versao);
public sealed record DocumentoDto(Guid Id, string Versao, Guid ClienteId, string Tipo, [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Numero,
    DateOnly? Emissao, DateOnly? Validade, string? PaisEmissor, int? DiasParaVencer);
public sealed record AtendimentoRequest(string Canal, string Resumo, DateTimeOffset? OcorridoEm, string? Versao);
public sealed record AtendimentoDto(Guid Id, string Versao, string Canal, string Resumo, DateTimeOffset OcorridoEm, Guid? UsuarioId, string? UsuarioNome);
public sealed record NovaPendenciaPessoaRequest(string Titulo, string? Descricao, DateOnly DataPrevista, Guid? ResponsavelId, string Prioridade, Guid? ViagemId);

// ---- Modules/Grupos/GrupoDtos.cs (T3) ----
public sealed record GrupoRequest(string Nome, string Tipo, string? Cnpj, string? Observacoes, string? Versao);
public sealed record PessoaDoGrupoDto(Guid Id, string Nome, int? Idade);
public sealed record GrupoDto(Guid Id, string Versao, string Nome, string Tipo, string? Cnpj, string? Observacoes, PessoaDoGrupoDto[] Pessoas, int Viagens);
public sealed record ListaGrupoDto(Guid Id, string Nome, string Tipo, string? Cnpj, int Pessoas, string PessoasResumo, int Viagens);
public sealed record ListaGruposDto(ListaGrupoDto[] Itens, int Total, int Pagina, int Tamanho);
public sealed record VincularPessoaRequest(Guid ClienteId);

// ---- Modules/Fornecedores/FornecedorDtos.cs (T4; FornecedorDto de 3.2 permanece) ----
public sealed record FornecedorRequest(string Nome, string Tipo, string? Cnpj, string? Site, string? Contato, string? Telefone, string? TelefoneEmergencia,
    decimal? PercentualComissaoPadrao, int? PrazoComissaoDias, bool Ativo = true, string? Observacoes = null, string? Versao = null);
public sealed record JanelaDto(int DiaInicial, int DiaFinal, int DiaPagamento, int MesesAFrente);
public sealed record VersaoRegraDto(DateOnly VigenteDesde, JanelaDto[] Janelas);
public sealed record NovaVersaoRegraRequest(DateOnly VigenteDesde, JanelaDto[] Janelas);
public sealed record ResumoFornecedorDto(int Reservas, [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? ReceitaAno);
public sealed record FornecedorDetalheDto(Guid Id, string Versao, string Nome, string Tipo, string? Cnpj, string? Site, string? Contato, string? Telefone, string? TelefoneEmergencia,
    decimal? PercentualComissaoPadrao, int? PrazoComissaoDias, bool Ativo, string? Observacoes, ResumoFornecedorDto Resumo, VersaoRegraDto[] Regras, VersaoRegraDto? RegraVigente);
public sealed record ListaFornecedorDto(Guid Id, string Nome, string Tipo, string? TelefoneEmergencia, decimal? PercentualComissaoPadrao, int? PrazoComissaoDias, JanelaDto[] JanelasVigentes,
    bool Ativo, int Reservas, [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? ReceitaAno);
public sealed record ListaFornecedoresDto(ListaFornecedorDto[] Itens, int Total, int Pagina, int Tamanho, int Ano);
public sealed record ReservaDoFornecedorDto(Guid ReservaId, Guid ViagemId, string Codigo, string? Titular, string Destino, string? Localizador, DateOnly DataCompra, string Status, string SituacaoComissao,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? Venda,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? Esperado,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] decimal? Recebido);
public sealed record ListaReservasFornecedorDto(ReservaDoFornecedorDto[] Itens, int Total, int Pagina, int Tamanho);
```

Códigos 422 novos: `nome_obrigatorio` (existe), `cpf_invalido` (existe), `cpf_duplicado`, `uf_invalida`, `data_nascimento_invalida` (futuro), `email_invalido`, `documento_tipo_invalido`, `validade_invalida` (validade < emissão), `canal_invalido`, `resumo_obrigatorio`, `data_invalida`, `passageiro_invalido` (existe), `grupo_tipo_invalido`, `cnpj_invalido`, `grupo_com_pessoas`? (**não**: excluir desvincula), `tipo_invalido` (existe), `percentual_invalido`, `prazo_invalido`, `vigencia_invalida`, `janelas_obrigatorias`, `janela_invalida`, `janelas_sobrepostas`, `pendencia_invalida`, `ordem_invalida`, `filtro_invalido`.

---

### Task 1 (backend): Clientes — lista, detalhe, criar/editar, viagens da pessoa

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Pessoas/PessoaDtos.cs` (reescrever: `ClienteBuscaDto` + DTOs do Contrato), `backend/src/Meridiano.Api/Modules/Pessoas/ClientesLista.cs` (SQL da lista, `static`)
- Modify: `backend/src/Meridiano.Api/Modules/Pessoas/ClientesService.cs` (esqueleto de T0), `backend/src/Meridiano.Api/Modules/Pessoas/ClientesEndpoints.cs` (esqueleto), `backend/src/Meridiano.Api/Modules/Pessoas/PessoasService.cs` (`CriarAsync` passa a delegar em `ClientesService`; `BuscarAsync` intocado), `backend/src/Meridiano.Api/Modules/Pessoas/PessoasEndpoints.cs` (`POST /clientes` usa `ClienteRequest` e devolve `ClienteDto`)
- Create: `backend/tests/Meridiano.Api.Tests/ClientesTests.cs`; Modify: `backend/tests/Meridiano.Api.Tests/PessoasTests.cs` (o teste `Cria_pessoa_inline_e_rejeita_cpf_invalido` continua passando; `Cliente` record local ganha nada)

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class ClientesService(DbSessaoFactory sessoes)
{
    public Task<ListaClientesDto> ListarAsync(ContextoSessao ctx, Guid? apenasVendedor, FiltroClientes f, CancellationToken ct);
    public Task<ClienteDto> ObterAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid id, bool verDocumento, CancellationToken ct);
    public Task<ClienteDto> CriarAsync(ContextoSessao ctx, ClienteRequest req, bool verDocumento, CancellationToken ct);
    public Task<ClienteDto> AtualizarAsync(ContextoSessao ctx, Guid id, ClienteRequest req, bool verDocumento, CancellationToken ct);
    public Task<IReadOnlyList<ViagemDaPessoaDto>> ViagensAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid id, bool verValores, CancellationToken ct);
    // Visibilidade (usada também por T2 via ClientesService.VisivelAsync):
    public static Task<bool> VisivelAsync(DbSessao s, Guid agenciaId, Guid clienteId, Guid? apenasVendedor, CancellationToken ct);
    //   = exists cliente (agencia, excluido_em is null) and (@apenasVendedor is null or exists (vp join v where vp.cliente_id and v.vendedor_id = @apenasVendedor and v.excluido_em is null))
    //   chamadores lançam RegraDeNegocioException("nao_encontrado") quando false
    public static string Normalizar(string? cpf)   // só dígitos; "" → null; ≠ 11 → cpf_invalido (também usada por T3 para CNPJ? não: T3 tem a sua de 14)
}
public static class ClientesEndpoints   // MapClientesEndpoints: GET /clientes, GET /clientes/{id:guid}, PUT /clientes/{id:guid}, GET /clientes/{id:guid}/viagens
// ApenasVendedor(u) = u.Pode(ClienteVer) ? null : u.UsuarioId; SemVisibilidade(u) = !ClienteVer && !ClienteVerProprios → 403 (copiar padrão de ViagensEndpoints)
```
  - **Validação** (`ClienteRequest`): `Nome` vazio → `nome_obrigatorio`; CPF normalizado (`cpf_invalido`); `select 1 from cliente where agencia_id and cpf = @cpf and excluido_em is null and id <> @id` → `cpf_duplicado`; `Uf` fora das 27 siglas → `uf_invalida`; `DataNascimento > current_date` → `data_nascimento_invalida`; `Email` sem `@` → `email_invalido`; `Tags` → `trim`, sem vazios, distinct (case-insensitive), máx. 20; `GrupoId` → `Guardas.ReferenciaAsync(Tabela.Grupo)`. Telefones: só `trim` (sem máscara no banco).
  - **Lista** (`ClientesLista.SqlAsync`): CTE `base` com `c.*`, `g.nome as GrupoNome`, `coalesce(c.whatsapp, c.telefone) as Contato`, `case when c.cpf is not null then '***.' || substr(c.cpf,4,3) || '.' || substr(c.cpf,7,3) || '-**' end as CpfMascarado`, `extract(year from age(c.data_nascimento))::int as Idade`, `lateral` de viagens (`count(*)`, última por `coalesce(data_ida, criado_em::date) desc` → destino, `data_ida`, `cancelada`), `lateral` de pendências abertas (`count(*)`, `count(*) filter (where prioridade = 'urgente')`) onde `p.cliente_id = c.id or p.viagem_id in (select viagem_id from viagem_passageiro where cliente_id = c.id)` e `status = 'aberta'`. Filtros: `q` → `c.nome ilike @padrao escape '\' or c.email ilike … or c.telefone ilike … or c.whatsapp ilike … or (@digitos <> '' and c.cpf like @digitos || '%')`; `grupoId`; `pendencia`: `com → PendenciasAbertas > 0`, `urgente → PendenciasUrgentes > 0`, `sem → = 0`, outro → `filtro_invalido`; `ultimaViagem = recompra → (UltimaVolta is null or UltimaVolta < current_date - 330)`, outro valor → `filtro_invalido`; `apenasVendedor` → `exists` de visibilidade. Ordem: `nome → c.nome {dir}` · `ultima_viagem → UltimaViagemData {dir} nulls last, c.nome`; default `nome asc`. Contadores (sempre sobre a agência inteira, respeitando `apenasVendedor`): `pessoas = count(*) from cliente`, `grupos = count(*) from grupo_cliente where excluido_em is null`, `passaportesVencendo = count(*) from documento_cliente d join cliente c … where d.tipo = 'passaporte' and d.excluido_em is null and d.validade between current_date and current_date + 180`.
  - **Detalhe**: `ObterAsync` → `VisivelAsync` senão `nao_encontrado`; `cpf = verDocumento ? c.cpf : null`; `Resumo`: viagens (`count`), última viagem (mesma regra da lista, com `Id`/`Codigo`), pendências abertas/urgentes, `ClienteDesde = extract(year from criado_em)`.
  - **Criar/Atualizar**: `insert … returning id` → `ObterAsync`; `AtualizarAsync`: `Versao` nulo → 422 `versao_obrigatoria`; `update cliente set … where id and agencia_id and excluido_em is null and xmin::text = @versao` → 0 linhas → existe? 409 : `nao_encontrado`. `PessoasService.CriarAsync` → `ClientesService.CriarAsync` (mantém `Results.Created`).
  - **Viagens da pessoa**: `viagem v join viagem_passageiro vp on vp.viagem_id = v.id and vp.cliente_id = @id join vw_fase_viagem f join vw_resultado_viagem r where v.agencia_id and v.excluido_em is null and (@apenasVendedor is null or v.vendedor_id = @apenasVendedor) order by v.data_ida desc nulls last, v.criado_em desc`; `VendaTotal` só com `verValores`.

- [ ] **Step 1: Testes** (`ClientesTests.cs`; helpers `LogadoAsync` como em `PessoasTests`; cenário: agência, dono `dono@`, agente `ag@`, financeiro `fin@`, externa `ana@` com senha; grupo "Família Mendes" (`InserirGrupoAsync`); Carlos (cpf 12345678901, nasc. 1974-03-01, grupo) e Lúcia (cpf 98765432100) via `InserirClienteCompletoAsync`; Pedro sem cpf; viagem completa de Carlos vendida pela externa (`InserirViagemCompletaAsync`, ida hoje+30) + viagem antiga de Lúcia (volta hoje−400); pendência aberta urgente de Lúcia (`InserirPendenciaAsync(cliente)`); passaporte de Lúcia validade hoje+40):
```csharp
[Fact] public async Task Lista_mascara_cpf_calcula_idade_e_conta_pendencias_e_viagens()
// GET /clientes como agente → itens ordenados por nome; Carlos: cpfMascarado "***.456.789-**", idade 52 (calcular a partir de 1974-03-01 e hoje), grupoNome "Família Mendes", viagens 1, ultimaViagemDestino; Lúcia: pendenciasAbertas 1, pendenciasUrgentes 1; contadores {pessoas 3, grupos 1, passaportesVencendo 1}; JSON nunca contém "12345678901"
[Fact] public async Task Filtros_por_texto_grupo_pendencia_e_recompra()
// ?q=987 → só Lúcia (CPF por dígitos); ?q=%25 → 0; ?grupoId → só Carlos; ?pendencia=urgente → só Lúcia; ?pendencia=sem → Carlos e Pedro; ?ultimaViagem=recompra → Lúcia (volta há 400 dias) e Pedro (nunca viajou); ?pendencia=x → 422 filtro_invalido; ?ordem=idade → 422 ordem_invalida
[Fact] public async Task Detalhe_mostra_cpf_so_com_permissao_e_traz_resumo()
// GET /clientes/{carlos} como agente → cpf "12345678901", resumo.viagens 1, resumo.ultimaViagem.codigo, grupoNome; como financeiro (ClienteVer sem ClienteVerDocumento) → JSON sem "cpf"; versao presente
[Fact] public async Task Externa_ve_so_clientes_das_suas_viagens()
// GET /clientes como externa → só Carlos; GET /clientes/{lucia} → 422 nao_encontrado; GET /clientes/{carlos}/viagens → 1 item sem "vendaTotal"; contadores.pessoas 1
[Fact] public async Task Cria_e_edita_com_versao_e_rejeita_cpf_duplicado_uf_e_nascimento_futuro()
// POST /clientes { nome "Maria", cpf "111.444.777-35", uf "SP", tags ["vip"," vip ","novo"], grupoId } → 201 tags ["vip","novo"], grupoNome; PUT com versao → 200 nome novo, versao diferente; PUT versao velha → 409; POST cpf "12345678901" → 422 cpf_duplicado; uf "XX" → uf_invalida; dataNascimento amanhã → data_nascimento_invalida; externa POST → 403
[Fact] public async Task Viagens_da_pessoa_marcam_titular_e_fases()
// Lúcia passageira (não titular) da viagem de Carlos (InserirPassageiroAsync titular:false); GET /clientes/{lucia}/viagens como agente → 2 itens (a de Carlos com titular false, a antiga com titular true, faseOperacional "concluida"), ordem data_ida desc; vendaTotal presente (agente tem ReservaVerValores)
```
- [ ] **Step 2: Rodar para ver falhar** — `cd backend && dotnet test --filter "FullyQualifiedName~ClientesTests"`.
- [ ] **Step 3: Implementar** DTOs, `ClientesLista` (SQL numa constante; parâmetros Dapper tipados `@grupoId::uuid`, `@padrao::text`), `ClientesService`, endpoints, ajuste de `PessoasService/PessoasEndpoints`. Idade: `extract(year from age(current_date, data_nascimento))`.
- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(pessoas): client list with filters/counters, full client detail and edit with row version, client trips; POST /clientes accepts the full request`

---

### Task 2 (backend): Documentos, atendimentos, pendências e anexos da pessoa

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Pessoas/PessoaDetalheDtos.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Pessoas/DocumentosService.cs`, `backend/src/Meridiano.Api/Modules/Pessoas/AtendimentosService.cs`, `backend/src/Meridiano.Api/Modules/Pessoas/PessoaDetalheEndpoints.cs` (esqueletos de T0)
- Modify: `backend/src/Meridiano.Api/Modules/Pendencias/PendenciasService.cs` (+ `ListarDaPessoaAsync`, `CriarNaPessoaAsync`), `backend/src/Meridiano.Api/Modules/Pendencias/PendenciasEndpoints.cs` (+ 2 rotas), `backend/src/Meridiano.Api/Modules/Anexos/AnexosService.cs` (+ `ListarDoClienteAsync`; visibilidade de vínculo cliente com `ClienteVerProprios`), `backend/src/Meridiano.Api/Modules/Anexos/AnexosEndpoints.cs` (+ `GET /clientes/{id}/anexos`)
- Create: `backend/tests/Meridiano.Api.Tests/DocumentosTests.cs`, `backend/tests/Meridiano.Api.Tests/AtendimentosTests.cs`; Modify: `backend/tests/Meridiano.Api.Tests/PendenciasTests.cs` (+2), `backend/tests/Meridiano.Api.Tests/AnexosTests.cs` (+1)

**Depends-on:** T0

**Arquivo compartilhado entre T1 e T2 (única exceção à disjunção):** `Modules/Pessoas/VisibilidadeCliente.cs`, com o conteúdo canônico abaixo. Regra: quem chegar primeiro cria o arquivo **exatamente** assim; o outro só usa (se já existir, não edita). O controlador commita o arquivo junto com a task que terminar primeiro. T1 chama `VisibilidadeCliente.VisivelAsync` no lugar de um método próprio (o `ClientesService.VisivelAsync` listado nas Interfaces de T1 **não existe**; ler como `VisibilidadeCliente.VisivelAsync`).

```csharp
// Modules/Pessoas/VisibilidadeCliente.cs — conteúdo canônico (idêntico em T1 e T2)
using Dapper;
using Meridiano.Data.Sessao;

namespace Meridiano.Api.Modules.Pessoas;

// ClienteVerProprios: a pessoa é visível quando é passageira de alguma viagem vendida por quem pergunta.
public static class VisibilidadeCliente
{
    public const string FiltroSql = "(@apenasVendedor::uuid is null or exists (select 1 from viagem_passageiro vp join viagem v on v.id = vp.viagem_id where vp.cliente_id = c.id and v.vendedor_id = @apenasVendedor and v.excluido_em is null))";

    public static async Task<bool> VisivelAsync(DbSessao s, Guid agenciaId, Guid clienteId, Guid? apenasVendedor, CancellationToken ct) =>
        await s.Conexao.ExecuteScalarAsync<bool>(new CommandDefinition(
            $"select exists (select 1 from cliente c where c.id = @clienteId and c.agencia_id = @agenciaId and c.excluido_em is null and {FiltroSql})",
            new { clienteId, agenciaId, apenasVendedor }, s.Transacao, cancellationToken: ct));
}
```

**Interfaces:**
```csharp
public sealed class DocumentosService(DbSessaoFactory sessoes)
{
    public Task<IReadOnlyList<DocumentoDto>> ListarAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid clienteId, bool verNumero, CancellationToken ct);  // verNumero → insert log_acesso_documento por doc
    public Task<DocumentoDto> CriarAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid clienteId, DocumentoRequest req, bool verNumero, CancellationToken ct);
    public Task<DocumentoDto> AtualizarAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid id, DocumentoRequest req, bool verNumero, CancellationToken ct);
    public Task ExcluirAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid id, CancellationToken ct);
}
public sealed class AtendimentosService(DbSessaoFactory sessoes)
{
    public Task<IReadOnlyList<AtendimentoDto>> ListarAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid clienteId, string? canal, CancellationToken ct);
    public Task<AtendimentoDto> CriarAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid clienteId, AtendimentoRequest req, CancellationToken ct);
    public Task<AtendimentoDto> AtualizarAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid id, AtendimentoRequest req, CancellationToken ct);
    public Task ExcluirAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid id, CancellationToken ct);
}
// PendenciasService (+)
public Task<IReadOnlyList<PendenciaDto>> ListarDaPessoaAsync(ContextoSessao ctx, UsuarioAtual u, Guid clienteId, bool incluirConcluidas, CancellationToken ct);
public Task<PendenciaDto> CriarNaPessoaAsync(ContextoSessao ctx, UsuarioAtual u, Guid clienteId, NovaPendenciaPessoaRequest req, CancellationToken ct);
// AnexosService (+)
public Task<IReadOnlyList<AnexoDto>> ListarDoClienteAsync(ContextoSessao ctx, UsuarioAtual u, Guid clienteId, CancellationToken ct);
```
  - **Documentos**: `Tipo ∈ rg·cpf·passaporte·visto·certidao·outro` senão `documento_tipo_invalido`; `Validade < Emissao` → `validade_invalida`; `DiasParaVencer = validade - current_date` (null sem validade); `Numero` `trim`, null se vazio; lista `order by validade nulls last, tipo`. Log: com `verNumero`, depois do select, `insert into log_acesso_documento (agencia_id, usuario_id, documento_id) select @agencia, @usuario, unnest(@ids)` e `ConfirmarAsync` (é a única escrita do GET). Sem `verNumero`, `Numero = null`. `AtualizarAsync`/`ExcluirAsync` resolvem `cliente_id` do documento e checam visibilidade; `Versao` obrigatória no PUT; excluir = soft.
  - **Atendimentos**: `Canal` ∈ lista senão `canal_invalido`; `Resumo` vazio → `resumo_obrigatorio`; `OcorridoEm` default `now()`, futuro (> now + 1 dia) → `data_invalida`; `usuario_id = ctx.UsuarioId` no insert (no PUT não muda); lista `order by ocorrido_em desc`, `left join usuario`; filtro `canal` opcional (inválido → `canal_invalido`).
  - **Pendências da pessoa** (R4): visibilidade = `VisibilidadeCliente` com `apenasVendedor = u.Pode(ClienteVer) ? null : u.UsuarioId`; SQL da lista de 3.3 com `where (p.cliente_id = @clienteId or p.viagem_id in (select viagem_id from viagem_passageiro where cliente_id = @clienteId and agencia_id = @agencia))`, mesmos filtros de status/`incluirConcluidas`; criar: validações de 3.3 (`titulo_obrigatorio`, `prioridade_invalida`, responsável ativo), `ViagemId` → `ReferenciaAsync(Viagem)` + pessoa passageira senão `passageiro_invalido`; se `ViagemId` vem, `TravarViagemAsync(viagemId, null)` (sem renovar xmin, ruling 3.3); `responsavel_id` default = `agente_id` da viagem ?? `ctx.UsuarioId`; `origem 'manual'`, `cliente_id = clienteId`. Rotas em `PendenciasEndpoints`: `GET /clientes/{id:guid}/pendencias` (gate `ClienteVer || ClienteVerProprios`) · `POST /clientes/{id:guid}/pendencias` (`ClienteEditar`) → 201 objeto único.
  - **Anexos da pessoa**: `ListarDoClienteAsync`: visibilidade `VisibilidadeCliente`; `where cliente_id = @id and confirmado_em is not null and excluido_em is null order by criado_em desc`. `IniciarAsync`/`UrlDownloadAsync`/`ExcluirAsync` com vínculo cliente passam a usar `VisibilidadeCliente` (fecha a deferida "filtro `ClienteVerProprios` completo é 3.4"). Rota `GET /clientes/{id:guid}/anexos` (gate cliente).
  - Rotas em `PessoaDetalheEndpoints` (`MapPessoaDetalheEndpoints`): `GET/POST /clientes/{id:guid}/documentos`, `PUT/DELETE /documentos/{id:guid}`, `GET/POST /clientes/{id:guid}/atendimentos`, `PUT/DELETE /atendimentos/{id:guid}`. Gates: leitura `ClienteVer || ClienteVerProprios` (403 padrão), escrita `RequerPermissao(ClienteEditar)`.

- [ ] **Step 1: Testes**
```csharp
// DocumentosTests.cs
[Fact] public async Task Cria_lista_com_numero_so_com_permissao_e_grava_log()
// agente POST /clientes/{lucia}/documentos { tipo "passaporte", numero "GB998877", emissao 2016-05-30, validade hoje+32, paisEmissor "Brasil" } → 201 numero, diasParaVencer 32; GET como agente → numero presente e 1 linha em log_acesso_documento (usuario_id agente, documento_id); GET como financeiro → JSON sem "numero" e nenhuma linha nova no log
[Fact] public async Task Edita_com_versao_exclui_soft_e_rejeita_tipo_e_validade()
// PUT { …, versao } → 200; versao velha → 409; DELETE → 204 e GET não lista, linha com excluido_em; tipo "cnh" → 422 documento_tipo_invalido; validade < emissao → validade_invalida
[Fact] public async Task Externa_le_documentos_de_quem_viaja_com_ela_sem_numero_e_nao_escreve()
// GET própria → 200 sem "numero"; GET pessoa alheia → 422 nao_encontrado; POST → 403
// AtendimentosTests.cs
[Fact] public async Task Registra_lista_por_canal_edita_e_exclui()
// POST { canal "whatsapp", resumo "Pediu orçamento" } → 201 usuarioNome do agente, ocorridoEm ≈ agora; POST canal "ligacao" ocorridoEm ontem; GET → 2 (mais recente primeiro); ?canal=ligacao → 1; PUT resumo com versao → 200; versao velha → 409; DELETE → 204; canal "fax" → 422 canal_invalido; resumo "" → resumo_obrigatorio
// PendenciasTests.cs (+)
[Fact] public async Task Pessoa_lista_as_suas_e_as_das_viagens_e_cria_com_viagem_opcional()
// pendência com cliente_id Lúcia + pendência da viagem em que Lúcia é passageira + pendência de outra viagem → GET /clientes/{lucia}/pendencias → 2; POST { titulo "Pedir foto do passaporte", dataPrevista, prioridade "normal", viagemId } → 201 clienteId Lúcia, viagemId, responsavelId = agente da viagem; viagemId de viagem sem Lúcia → 422 passageiro_invalido
[Fact] public async Task Externa_le_pendencias_da_pessoa_visivel_e_nao_cria()
// AnexosTests.cs (+)
[Fact] public async Task Anexo_de_cliente_lista_por_pessoa_e_respeita_ver_proprios()
// agente inicia+confirma anexo { clienteId lucia, tipo "documento", sensivel true } → GET /clientes/{lucia}/anexos → 1; externa: pessoa visível → 200, pessoa alheia → 422 nao_encontrado; POST /anexos { clienteId alheio } como externa → 403 (AnexoEnviar) — e como agente com clienteId inexistente → 422 referencia_invalida
```
- [ ] **Step 2–3:** RED → implementar (`DocumentosService.cs`, `AtendimentosService.cs` ≤ 200 linhas cada; `PendenciasService.cs` pode passar de 350 → mover o SQL de listagem para `PendenciasSql.cs` `static`).
- [ ] **Step 4: Rodar tudo; format.** Commit sugerido: `feat(pessoas): client documents with access log, atendimentos, person-scoped pendencias and anexos with ClienteVerProprios`

---

### Task 3 (backend): `Modules/Grupos`

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Grupos/GrupoDtos.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Grupos/GruposService.cs`, `backend/src/Meridiano.Api/Modules/Grupos/GruposEndpoints.cs` (esqueletos)
- Create: `backend/tests/Meridiano.Api.Tests/GruposTests.cs`

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class GruposService(DbSessaoFactory sessoes)
{
    public Task<ListaGruposDto> ListarAsync(ContextoSessao ctx, string? q, int pagina, int tamanho, CancellationToken ct);
    public Task<GrupoDto> ObterAsync(ContextoSessao ctx, Guid id, CancellationToken ct);
    public Task<GrupoDto> CriarAsync(ContextoSessao ctx, GrupoRequest req, CancellationToken ct);
    public Task<GrupoDto> AtualizarAsync(ContextoSessao ctx, Guid id, GrupoRequest req, CancellationToken ct);
    public Task ExcluirAsync(ContextoSessao ctx, Guid id, CancellationToken ct);           // soft + update cliente set grupo_id = null where grupo_id = @id
    public Task<GrupoDto> VincularAsync(ContextoSessao ctx, Guid id, Guid clienteId, CancellationToken ct);
    public Task DesvincularAsync(ContextoSessao ctx, Guid id, Guid clienteId, CancellationToken ct);   // rota devolve 204
}
```
  - Validação: `Nome` vazio → `nome_obrigatorio`; `Tipo ∈ familia·empresa·outro` senão `grupo_tipo_invalido`; `Cnpj`: só dígitos, 14 senão `cnpj_invalido`; **ignorado (null) se `Tipo ≠ empresa`**; `Observacoes` `trim`.
  - Lista: `q` → `nome ilike`; `PessoasResumo` = primeiros 3 nomes por `nome` + `", +N"`; `Pessoas = count(cliente where grupo_id and excluido_em is null)`; `Viagens = count(distinct v.id) from viagem v join viagem_passageiro vp join cliente c on c.grupo_id = @id`; ordem `nome`.
  - `ObterAsync`: `Pessoas[]` com `Idade`; inexistente/excluído → `nao_encontrado`. Concorrência por `xmin`. Vincular: `ReferenciaAsync(Cliente)`; já em outro grupo → troca (uma pessoa, um grupo, spec §2). Desvincular: cliente não está no grupo → `nao_encontrado`.
  - Rotas: grupo `/grupos` — `GET /`, `GET /{id:guid}` (`RequerPermissao(ClienteVer)`); `POST /`, `PUT /{id:guid}`, `DELETE /{id:guid}`, `POST /{id:guid}/pessoas`, `DELETE /{id:guid}/pessoas/{clienteId:guid}` (`ClienteEditar`).

- [ ] **Step 1: Testes**
```csharp
[Fact] public async Task Cria_lista_com_resumo_de_pessoas_e_conta_viagens()
// POST { nome "Família Mendes", tipo "familia", cnpj "12.345.678/0001-90" } → 201 cnpj null (não é empresa); vincular Carlos e Lúcia; viagem de Carlos → GET /grupos → item pessoas 2, pessoasResumo "Carlos Mendes, Lúcia Mendes", viagens 1; ?q=mend → 1; ?q=xyz → 0
[Fact] public async Task Empresa_exige_cnpj_valido_e_edicao_respeita_versao()
// POST { tipo "empresa", cnpj "123" } → 422 cnpj_invalido; POST { tipo "empresa", cnpj "12.345.678/0001-90" } → cnpj "12345678000190"; PUT com versao → 200; versao velha → 409; tipo "turma" → grupo_tipo_invalido
[Fact] public async Task Excluir_desvincula_pessoas_e_desvincular_individual_funciona()
// DELETE /grupos/{id}/pessoas/{lucia} → 200 pessoas 1; DELETE /grupos/{id} → 204; cliente Carlos com grupo_id null; GET → 422 nao_encontrado
[Fact] public async Task Externa_recebe_403_e_financeiro_le_mas_nao_edita()
```
- [ ] **Step 2–4:** RED → implementar → testes, format. Commit sugerido: `feat(grupos): client groups crud with member linking and trip counts`

---

### Task 4 (backend): Fornecedores completo — resumo, detalhe, edição, versões da regra, reservas

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedorDtos.cs` (+ DTOs do Contrato), `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresService.cs` (`CriarAsync` aceita `FornecedorRequest`; + `AtualizarAsync`, `NovaVersaoRegraAsync`), `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresEndpoints.cs` (`POST` com `FornecedorRequest`), `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresLeitura.cs` (esqueleto → `ResumoAsync`, `ObterAsync`, `ReservasAsync`), `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresDetalheEndpoints.cs` (esqueleto → rotas)
- Modify: `backend/tests/Meridiano.Api.Tests/FornecedoresTests.cs` (+ testes; os de 3.2 continuam)

**Depends-on:** T0

**Interfaces:**
```csharp
public sealed class FornecedoresService(DbSessaoFactory sessoes)
{
    public Task<IReadOnlyList<FornecedorDto>> ListarAsync(ContextoSessao ctx, bool? ativo, CancellationToken ct);     // 3.2, intocado
    public Task<FornecedorDto> CriarAsync(ContextoSessao ctx, FornecedorRequest req, CancellationToken ct);           // devolve FornecedorDto (3.2)
    public Task<FornecedorDetalheDto> AtualizarAsync(ContextoSessao ctx, Guid id, FornecedorRequest req, bool verValores, CancellationToken ct);
    public Task<FornecedorDetalheDto> NovaVersaoRegraAsync(ContextoSessao ctx, Guid id, NovaVersaoRegraRequest req, bool verValores, CancellationToken ct);
}
public sealed class FornecedoresLeitura(DbSessaoFactory sessoes)
{
    public Task<ListaFornecedoresDto> ResumoAsync(ContextoSessao ctx, string? q, bool? ativo, int pagina, int tamanho, bool verValores, CancellationToken ct);
    public Task<FornecedorDetalheDto> ObterAsync(ContextoSessao ctx, Guid id, bool verValores, CancellationToken ct);
    public static Task<FornecedorDetalheDto> CarregarAsync(DbSessao s, Guid agenciaId, Guid id, bool verValores, CancellationToken ct);   // usado por Service depois de escrever
    public Task<ListaReservasFornecedorDto> ReservasAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid id, int pagina, int tamanho, bool verValores, CancellationToken ct);
}
```
  - Validação (`FornecedorRequest`): `nome_obrigatorio`, `tipo_invalido` (lista de 3.2), `Cnpj` 14 dígitos ou null (`cnpj_invalido`), `PercentualComissaoPadrao` fora de 0..100 → `percentual_invalido`, `PrazoComissaoDias ≤ 0` → `prazo_invalido`; `Site`/`Contato`/`Telefone*`/`Observacoes` `trim`.
  - `Regras[]`: `select vigente_desde, dia_inicial, … order by vigente_desde desc, dia_inicial` agrupado em C#; `RegraVigente` = primeira com `VigenteDesde <= current_date`.
  - `NovaVersaoRegraAsync`: `Janelas` vazio → `janelas_obrigatorias`; cada janela: dias em 1..31, `DiaInicial <= DiaFinal`, `MesesAFrente` 0..3 senão `janela_invalida`; sobreposição entre janelas (intervalos `[DiaInicial, DiaFinal]`) → `janelas_sobrepostas`; `VigenteDesde <= max(vigente_desde)` existente → `vigencia_invalida` (fornecedor sem regra: qualquer data); `insert … select unnest(...)` N linhas; **nenhum update em reserva**.
  - `ResumoAsync`: `q` → `nome ilike`; `ativo` null = todos; `Reservas = count(reserva where fornecedor_id and excluido_em is null)`; `ReceitaAno = sum(receita_prevista) where data_compra in ano corrente and status <> 'cancelada'` (só com `verValores`); `JanelasVigentes` = janelas da versão vigente hoje (lateral com `max(vigente_desde) <= current_date`); `Ano = current year`; ordem `nome`.
  - `ReservasAsync`: `reserva r join viagem v join vw_reserva_financeiro f left join vw_viagem_titular t where r.fornecedor_id = @id and r.agencia_id and r.excluido_em is null and v.excluido_em is null and (@apenasVendedor is null or v.vendedor_id = @apenasVendedor) order by r.data_compra desc, r.criado_em desc`; `SituacaoComissao` = mesmo `case` de 3.3 T1; `Venda = r.valor_cliente`, `Esperado = f.valor_esperado_operadora`, `Recebido = f.recebido_operadora` só com `verValores`.
  - Rotas (`FornecedoresDetalheEndpoints`, grupo `/fornecedores`): `GET /resumo`, `GET /{id:guid}` (`RequireAuthorization`; `verValores = u.Pode(ReservaVerValores)`), `GET /{id:guid}/reservas` (gate `ViagemVer || ViagemVerProprias`), `PUT /{id:guid}`, `POST /{id:guid}/regras` (`FornecedorEditar`). **`/resumo` antes de `/{id:guid}`** só por legibilidade (a constraint separa).

- [ ] **Step 1: Testes** (`FornecedoresTests.cs` +; cenário com CVC (10 %, janelas 1–14→20/0 e 15–31→5/1 vigentes desde 2020-01-01) e Decolar (prazo 45); viagem de Carlos com reserva CVC `data_compra` 2026-03-10 e prevista gravada 2026-03-20):
```csharp
[Fact] public async Task Resumo_lista_janelas_vigentes_contagens_e_receita_so_com_valores()
// GET /fornecedores/resumo como agente → CVC: janelasVigentes 2, reservas 1, receitaAno presente; Decolar: janelasVigentes [], prazoComissaoDias 45; como externa → JSON sem "receitaAno"; ?q=cvc → 1; ?ativo=false → 0
[Fact] public async Task Detalhe_edicao_e_versao()
// GET /fornecedores/{cvc} → regras 1 versão (2020-01-01, 2 janelas), regraVigente; PUT { …, percentualComissaoPadrao 12, telefoneEmergencia "0800", observacoes "x", versao } → 200; versao velha → 409; percentual 120 → 422 percentual_invalido; externa PUT → 403
[Fact] public async Task Nova_versao_da_regra_nao_muda_previsao_de_reserva_existente_e_vale_para_compra_nova()
// POST /fornecedores/{cvc}/regras { vigenteDesde 2026-04-01, janelas [ {1,31,10,1} ] } → 200 regras 2 versões, regraVigente = a nova se hoje ≥ 2026-04-01 (calcular com DateOnly.FromDateTime(DateTime.Today))
// banco: reserva antiga continua data_prevista_comissao 2026-03-20
// POST /viagens (agente) com reserva CVC dataCompra 2026-04-15 → dataPrevistaComissao 2026-05-10; com dataCompra 2026-03-16 → 2026-04-05 (versão antiga)
// POST regras vigenteDesde 2026-04-01 de novo → 422 vigencia_invalida; janelas [] → janelas_obrigatorias; [{1,20,5,0},{15,31,5,1}] → janelas_sobrepostas; [{0,…}] → janela_invalida
[Fact] public async Task Reservas_do_fornecedor_com_situacao_e_valores_por_perfil()
// GET /fornecedores/{cvc}/reservas como agente → 1 item codigo, titular "Carlos Mendes", situacaoComissao "a_receber", venda/esperado/recebido presentes; como externa (viagem de outro vendedor) → 0 itens; como financeiro → valores presentes
[Fact] public async Task Post_inline_continua_aceitando_so_nome_e_tipo()
// POST /fornecedores { nome "Nova", tipo "hotel" } → 201 FornecedorDto (id, nome, tipo, percentualComissaoPadrao null, ativo true)
```
- [ ] **Step 2–4:** RED → implementar → testes, format. Commit sugerido: `feat(fornecedores): supplier summary list, detail with versioned payment rules (existing forecasts untouched), edit, supplier reservas`

---

### Task 5 (front): API, tipos, `lib/documentos`, componentes base de cadastro

**Files:**
- Create: `frontend/src/api/clientes.ts`, `frontend/src/api/grupos.ts`, `frontend/src/api/fornecedores.ts`, `frontend/src/api/fornecedores.test.ts` (`resumoRegra`)
- Create: `frontend/src/lib/documentos.ts`, `frontend/src/lib/documentos.test.ts`
- Create: `frontend/src/components/Cadastros/{TagsInput.tsx,TagsInput.test.tsx,GrupoInlineModal.tsx,GrupoInlineModal.test.tsx,mapaErrosCadastro.ts,useFormularioCadastro.ts,useFormularioCadastro.test.ts,Cadastros.module.css}`, `frontend/src/components/cadastros.ts` (barrel com os de T5; T6 acrescenta o resto)

**Depends-on:** T0

**Interfaces:**
```ts
// src/api/clientes.ts (nomes espelham o C#)
export interface ClienteRequest { nome: string; cpf: string | null; email: string | null; telefone: string | null; whatsapp: string | null; dataNascimento: string | null; cidade: string | null; uf: string | null; origemLead: string | null; tags: string[]; observacoes: string | null; contatoEmergencia: string | null; grupoId: string | null; versao?: string }
export interface UltimaViagemDto { id: string; codigo: string; destino: string; dataIda: string | null; dataVolta: string | null; cancelada: boolean }
export interface ResumoClienteDto { viagens: number; ultimaViagem: UltimaViagemDto | null; pendenciasAbertas: number; pendenciasUrgentes: number; clienteDesde: number }
export interface ClienteDto { id: string; versao: string; nome: string; cpf?: string | null; email: string | null; telefone: string | null; whatsapp: string | null; dataNascimento: string | null; cidade: string | null; uf: string | null; origemLead: string | null; tags: string[]; observacoes: string | null; contatoEmergencia: string | null; grupoId: string | null; grupoNome: string | null; criadoEm: string; resumo: ResumoClienteDto }
export interface ListaClienteDto { id; nome; cpfMascarado: string | null; idade: number | null; grupoNome: string | null; contato: string | null; pendenciasAbertas: number; pendenciasUrgentes: number; ultimaViagemDestino: string | null; ultimaViagemData: string | null; ultimaViagemCancelada: boolean; viagens: number }
export interface ContadoresClientesDto { pessoas: number; grupos: number; passaportesVencendo: number }
export interface ListaClientesDto { itens: ListaClienteDto[]; total: number; pagina: number; tamanho: number; contadores: ContadoresClientesDto }
export interface FiltroClientes { q?: string; grupoId?: string; pendencia?: "com" | "urgente" | "sem"; ultimaViagem?: "recompra"; ordem?: "nome" | "ultima_viagem"; direcao?: "asc" | "desc"; pagina?: number; tamanho?: number }
export interface ViagemDaPessoaDto { id; codigo; destino; tipo: "nacional" | "internacional"; dataIda: string | null; dataVolta: string | null; titular: boolean; faseOperacional: string; faseFinanceira: string; vendaTotal?: number }
export type TipoDocumento = "rg" | "cpf" | "passaporte" | "visto" | "certidao" | "outro";
export interface DocumentoDto { id; versao; clienteId; tipo: TipoDocumento; numero?: string | null; emissao: string | null; validade: string | null; paisEmissor: string | null; diasParaVencer: number | null }
export interface DocumentoRequest { tipo: TipoDocumento; numero: string | null; emissao: string | null; validade: string | null; paisEmissor: string | null; versao?: string }
export type Canal = "whatsapp" | "ligacao" | "presencial" | "email" | "outro";
export interface AtendimentoDto { id; versao; canal: Canal; resumo: string; ocorridoEm: string; usuarioId: string | null; usuarioNome: string | null }
export interface AtendimentoRequest { canal: Canal; resumo: string; ocorridoEm: string | null; versao?: string }
export interface NovaPendenciaPessoaRequest { titulo: string; descricao: string | null; dataPrevista: string; responsavelId: string | null; prioridade: Prioridade; viagemId: string | null }
export function qsClientes(f: FiltroClientes): string   // mesma receita de qsLista (omite undefined/""/[])
export const clientesApi = {
  listar: (f) => api.get<ListaClientesDto>(`/clientes?${qsClientes(f)}`),
  obter: (id) => api.get<ClienteDto>(`/clientes/${id}`),
  criar: (c: ClienteRequest) => api.post<ClienteDto>("/clientes", c),
  atualizar: (id, c: ClienteRequest) => api.put<ClienteDto>(`/clientes/${id}`, c),
  viagens: (id) => api.get<ViagemDaPessoaDto[]>(`/clientes/${id}/viagens`),
  documentos: (id) => api.get<DocumentoDto[]>(`/clientes/${id}/documentos`),
  criarDocumento: (id, d: DocumentoRequest) => api.post<DocumentoDto>(`/clientes/${id}/documentos`, d),
  atualizarDocumento: (docId, d: DocumentoRequest) => api.put<DocumentoDto>(`/documentos/${docId}`, d),
  excluirDocumento: (docId) => api.delete(`/documentos/${docId}`),
  atendimentos: (id, canal?: Canal) => api.get<AtendimentoDto[]>(`/clientes/${id}/atendimentos${canal ? `?canal=${canal}` : ""}`),
  criarAtendimento: (id, a: AtendimentoRequest) => api.post<AtendimentoDto>(`/clientes/${id}/atendimentos`, a),
  atualizarAtendimento: (atId, a: AtendimentoRequest) => api.put<AtendimentoDto>(`/atendimentos/${atId}`, a),
  excluirAtendimento: (atId) => api.delete(`/atendimentos/${atId}`),
  pendencias: (id, incluirConcluidas: boolean) => api.get<PendenciaDto[]>(`/clientes/${id}/pendencias?incluirConcluidas=${incluirConcluidas}`),
  criarPendencia: (id, r: NovaPendenciaPessoaRequest) => api.post<PendenciaDto>(`/clientes/${id}/pendencias`, r),
  anexos: (id) => api.get<AnexoDto[]>(`/clientes/${id}/anexos`),
};
export const chavesClientes = {
  lista: (f: FiltroClientes) => ["clientes", "lista", f] as const,
  cliente: (id) => ["clientes", id] as const,
  viagens: (id) => ["clientes", id, "viagens"] as const,
  documentos: (id) => ["clientes", id, "documentos"] as const,
  atendimentos: (id, canal?: Canal) => ["clientes", id, "atendimentos", canal ?? "todos"] as const,
  pendencias: (id, c: boolean) => ["clientes", id, "pendencias", c] as const,
  anexos: (id) => ["clientes", id, "anexos"] as const,
};

// src/api/grupos.ts
export type TipoGrupo = "familia" | "empresa" | "outro";
export interface GrupoRequest { nome: string; tipo: TipoGrupo; cnpj: string | null; observacoes: string | null; versao?: string }
export interface PessoaDoGrupoDto { id; nome; idade: number | null }
export interface GrupoDto { id; versao; nome; tipo: TipoGrupo; cnpj: string | null; observacoes: string | null; pessoas: PessoaDoGrupoDto[]; viagens: number }
export interface ListaGrupoDto { id; nome; tipo: TipoGrupo; cnpj: string | null; pessoas: number; pessoasResumo: string; viagens: number }
export interface ListaGruposDto { itens: ListaGrupoDto[]; total; pagina; tamanho }
export const gruposApi = { listar: (q: string, pagina: number) => api.get<ListaGruposDto>(`/grupos?q=${encodeURIComponent(q)}&pagina=${pagina}`), obter: (id) => api.get<GrupoDto>(`/grupos/${id}`), criar: (g: GrupoRequest) => api.post<GrupoDto>("/grupos", g), atualizar: (id, g: GrupoRequest) => api.put<GrupoDto>(`/grupos/${id}`, g), excluir: (id) => api.delete(`/grupos/${id}`), vincular: (id, clienteId) => api.post<GrupoDto>(`/grupos/${id}/pessoas`, { clienteId }), desvincular: (id, clienteId) => api.delete(`/grupos/${id}/pessoas/${clienteId}`) };
export const chavesGrupos = { lista: (q, pagina) => ["grupos", "lista", q, pagina] as const, grupo: (id) => ["grupos", id] as const };

// src/api/fornecedores.ts (FornecedorDto de 3.2 continua em @/api/viagens)
export type TipoFornecedor = "operadora" | "consolidadora" | "cia_aerea" | "hotel" | "seguradora" | "receptivo" | "despachante" | "outro";
export interface JanelaDto { diaInicial: number; diaFinal: number; diaPagamento: number; mesesAFrente: number }
export interface VersaoRegraDto { vigenteDesde: string; janelas: JanelaDto[] }
export interface FornecedorRequest { nome; tipo: TipoFornecedor; cnpj: string | null; site; contato; telefone; telefoneEmergencia: string | null; percentualComissaoPadrao: number | null; prazoComissaoDias: number | null; ativo: boolean; observacoes: string | null; versao?: string }
export interface FornecedorDetalheDto { id; versao; nome; tipo: TipoFornecedor; cnpj; site; contato; telefone; telefoneEmergencia; percentualComissaoPadrao: number | null; prazoComissaoDias: number | null; ativo: boolean; observacoes: string | null; resumo: { reservas: number; receitaAno?: number }; regras: VersaoRegraDto[]; regraVigente: VersaoRegraDto | null }
export interface ListaFornecedorDto { id; nome; tipo: TipoFornecedor; telefoneEmergencia: string | null; percentualComissaoPadrao: number | null; prazoComissaoDias: number | null; janelasVigentes: JanelaDto[]; ativo: boolean; reservas: number; receitaAno?: number }
export interface ListaFornecedoresDto { itens: ListaFornecedorDto[]; total; pagina; tamanho; ano: number }
export interface ReservaDoFornecedorDto { reservaId; viagemId; codigo; titular: string | null; destino; localizador: string | null; dataCompra: string; status: string; situacaoComissao: string; venda?: number; esperado?: number; recebido?: number }
export interface ListaReservasFornecedorDto { itens: ReservaDoFornecedorDto[]; total; pagina; tamanho }
export function resumoRegra(janelas: JanelaDto[], prazoDias: number | null): string
//  janelas → "1–14 → dia 20 · 15–31 → dia 5 (mês seguinte)" (sufixo " (mês seguinte)" quando mesesAFrente = 1; "(+N meses)" para 2..3); sem janelas e prazo → "30 dias após a compra"; nada → "—"
export function descreverJanela(j: JanelaDto): { titulo: string; sub: string }   // { "Vendas de 1 a 14", "pagam dia 20 do mesmo mês" } · mesesAFrente 1 → "do mês seguinte"
export const fornecedoresApi = { resumo: (q, ativo: boolean | undefined, pagina) => …, obter, criar: (f: FornecedorRequest) => api.post<FornecedorDto>("/fornecedores", f), atualizar, novaVersaoRegra: (id, r: { vigenteDesde: string; janelas: JanelaDto[] }) => api.post<FornecedorDetalheDto>(`/fornecedores/${id}/regras`, r), reservas: (id, pagina) => … };
export const chavesFornecedores = { resumo: (q, ativo, pagina) => ["fornecedores", "resumo", q, ativo ?? "todos", pagina] as const, fornecedor: (id) => ["fornecedores", id] as const, reservas: (id, pagina) => ["fornecedores", id, "reservas", pagina] as const };

// src/lib/documentos.ts
export const UFS: readonly string[]   // 27 siglas ordenadas
export function somenteDigitos(s: string): string
export function formatarCpf(digitos: string | null | undefined): string      // "12345678901" → "123.456.789-01"; vazio → ""
export function formatarCnpj(digitos: string | null | undefined): string     // "12345678000190" → "12.345.678/0001-90"
export function formatarTelefone(s: string | null | undefined): string       // 11 dígitos → "(11) 99876-5678"; 10 → "(11) 3003-9282"; senão devolve como está
export function situacaoValidade(dias: number | null): { texto: string; tone: Tone }   // null → {"—", neutral}; < 0 → {"vencido há N dias", danger}; ≤ 180 → {"N dias", warning}; > 180 → {"N dias", neutral}

// src/components/Cadastros/TagsInput.tsx
<TagsInput value={string[]} onChange id? aria-label="Tags" />   // Chips selecionadas com ✓ e botão × (aria-label "Remover {tag}"); Input "+ tag" (Enter adiciona trim+dedupe, Backspace vazio remove a última)
// src/components/Cadastros/GrupoInlineModal.tsx
<GrupoInlineModal open onClose onCriado={(g: GrupoDto) => void} />   // Input Nome (required) · Select Tipo; POST /grupos; 422 nome_obrigatorio → campo
// src/components/Cadastros/mapaErrosCadastro.ts
export const CAMPO_POR_CODIGO: Record<string, string> = { nome_obrigatorio: "nome", cpf_invalido: "cpf", cpf_duplicado: "cpf", uf_invalida: "uf", data_nascimento_invalida: "dataNascimento", email_invalido: "email", referencia_invalida: "grupoId", grupo_tipo_invalido: "tipo", cnpj_invalido: "cnpj", tipo_invalido: "tipo", percentual_invalido: "percentualComissaoPadrao", prazo_invalido: "prazoComissaoDias", vigencia_invalida: "vigenteDesde", janelas_obrigatorias: "janelas", janela_invalida: "janelas", janelas_sobrepostas: "janelas", documento_tipo_invalido: "tipo", validade_invalida: "validade", canal_invalido: "canal", resumo_obrigatorio: "resumo", data_invalida: "ocorridoEm", titulo_obrigatorio: "titulo", prioridade_invalida: "prioridade", passageiro_invalido: "viagemId" };
export function errosDeCadastro(erro: unknown): ErrosApi   // mesma forma de pages/viagens/mapaErros.ts (campos, bloco, conflito) com este mapa
// src/components/Cadastros/useFormularioCadastro.ts — receita comum das três páginas de cadastro
export function useFormularioCadastro<TForm extends FieldValues, TDto>(opts: {
  id: string | undefined; carregar: (id: string) => Promise<TDto>; chave: (id: string) => readonly unknown[];
  paraForm: (dto: TDto) => TForm; paraRequest: (f: TForm, versao?: string) => unknown;
  criar: (req: unknown) => Promise<TDto>; atualizar: (id: string, req: unknown) => Promise<TDto>;
  rotaDepoisDeCriar: (dto: TDto) => string; versaoDe: (dto: TDto) => string;
}): { form: UseFormReturn<TForm>; dto: TDto | undefined; carregando: boolean; salvamento: ReturnType<typeof useSalvamento>; erros: Record<string,string>; erroBloco: string | null; conflito: boolean; salvar: () => Promise<boolean>; recarregar: () => Promise<void> }
//  useQuery quando id; form.reset(paraForm(dto)) ao carregar; watch → marcarSujo; salvar: sem id → criar + queryClient.setQueryData + nav(rotaDepoisDeCriar, { replace: true }); com id → atualizar(id, paraRequest(f, versaoDe(dto))) + setQueryData; erros via errosDeCadastro; 409 → conflito (recarregar limpa)
```

- [ ] **Step 1: Testes** — `documentos.test.ts` (formatos, `situacaoValidade(-3)`, `situacaoValidade(32).tone === "warning"`, `UFS.length === 27`); `fornecedores.test.ts` (`resumoRegra` com as janelas da CVC → `"1–14 → dia 20 · 15–31 → dia 5 (mês seguinte)"`; sem janelas com prazo 30; `descreverJanela`); `TagsInput.test.tsx` (Enter adiciona sem duplicar, × remove); `GrupoInlineModal.test.tsx` (submit chama `POST /grupos` e `onCriado`); `useFormularioCadastro.test.ts` (renderHook com `MemoryRouter`: sem id `salvar()` chama `criar` e navega; com id chama `atualizar` com `versao`; 409 → `conflito`; 422 `cpf_duplicado` → `erros.cpf`).
- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(api): clients/groups/suppliers clients and types, document formatting helpers, shared cadastro form recipe, tags input and inline group modal`

---

### Task 6 (front): `ClientesPage` (lista) e `PessoaPage` (Dados + tabs)

**Files:**
- Create: `frontend/src/pages/clientes/{ClientesPage.tsx,ClientesPage.test.tsx,FiltrosClientes.tsx,useFiltrosClientes.ts,useFiltrosClientes.test.ts,PessoaPage.tsx,PessoaPage.test.tsx,DadosPessoaForm.tsx,usePessoa.ts,Clientes.module.css}`
- Modify: `frontend/src/pages/clientes/rotas.tsx` (T0 → páginas reais), `frontend/src/components/cadastros.ts` (+ exports dos componentes de T7)

**Depends-on:** T5, T7

**Interfaces:**
```ts
export function useFiltrosClientes(): { filtro: FiltroClientes; definir: (p: Partial<FiltroClientes>) => void; limpar: () => void; ativos: number }   // URL; defaults ordem "nome" asc, pagina 1, tamanho 25; `ativos` = ultimaViagem preenchido ? 1 : 0; mudar filtro reseta pagina
<FiltrosClientes filtro definir limpar ativos grupos={ListaGrupoDto[]} />
//  visíveis: Input busca (placeholder "Nome, CPF, telefone, e-mail…", debounce 300 ms) · Select "Grupo: todos" · Select "Pendências: todas | Com pendência | Com pendência urgente | Sem pendência" · Button secondary "Filtros" + Badge "● N" · "Limpar"
//  painel: Select "Última viagem: qualquer | Há mais de 11 meses (recompra)"
// ClientesPage: PageHeader title="Clientes" subtitle="{pessoas} pessoas · {grupos} grupos · {passaportesVencendo} passaportes vencendo" actions={pode("cliente.editar") && <Button variant="primary" icon={<Plus/>}>+ Nova pessoa</Button> → /clientes/nova} · Subnav subnavs["/clientes"] · FiltrosClientes · DataTable colunas: Pessoa (primary nome; secondary <code>cpfMascarado</code> · "{idade} anos") · Grupo · Contato (formatarTelefone) · Pendências (Badge warning "{abertas} · urgente" se urgentes > 0; "{abertas}" info; "—") · Última viagem ("{destino} · {formatarMesAno(data)}"; cancelada → "cancelada · mes") · Viagens (right, ordenável? não) — Pessoa ordenável (nome), Última viagem ordenável (ultima_viagem) · Paginacao · onLinha → /clientes/{id}; rotuloLinha = nome. Vazio: EmptyState "Nenhuma pessoa por aqui" / "Nada bate com os filtros. Limpe os filtros ou cadastre a primeira pessoa." Erro: Alert danger + Tentar de novo. Sem "Exportar CSV" (3.6).

// usePessoa.ts
export function usePessoa(id: string | undefined): ReturnType<typeof useFormularioCadastro<FormPessoa, ClienteDto>> & { tab: string; setTab: (t: string) => void; grupos: ListaGrupoDto[]; vendedores: VendedorDto[]; viagens: ViagemDaPessoaDto[]; documentos: DocumentoDto[]; pendenciasAbertas: number; atendimentos: number; anexos: number }
//  tab na URL (?tab=), default "dados"; queries das tabs só com id (enabled)
interface FormPessoa { nome: string; cpf: string; email: string; telefone: string; whatsapp: string; dataNascimento: string; cidade: string; uf: string; origemLead: string; tags: string[]; observacoes: string; contatoEmergencia: string; grupoId: string }
// paraRequest: strings vazias → null; cpf → somenteDigitos; tags como estão
<DadosPessoaForm form grupos erros verDocumento onNovoGrupo />
//  Section "Dados pessoais": Nome* (span 2) · CPF (mono; máscara ao blur via formatarCpf; readOnly quando !verDocumento e há cpf → mostra "***.***.***-**"? Não: sem permissão o campo nem existe no DTO → Field "CPF" não renderiza) · Nascimento (DateInput) · Grupo/empresa (Select: "— nenhum —", grupos, "+ Criar grupo…" = value "__novo" → onNovoGrupo) · Cidade · UF (Select UFS) · Origem (Input)
//  Section "Contato": WhatsApp · Telefone · E-mail (span 2) · Contato de emergência (span 2) · Tags (TagsInput, span 4)
//  Section "Observações e preferências": Textarea rows 4
// PessoaPage: id de useParams (undefined em /clientes/nova); Page dirty titulo={dto?.nome ?? "Nova pessoa"} onSalvarESair={salvar}; PageHeader title={dto?.nome ?? "Nova pessoa"} subtitle="{formatarCpf(cpf)} · {grupoNome} · {viagens} viagens · cliente desde {clienteDesde}" (partes presentes) status={pendenciasAbertas > 0 && <Badge tone="warning">{n} pendências</Badge>} dirty salvoEm actions=[Fechar (tertiary → nav("/clientes")), Salvar (primary, loading; pode("cliente.editar"))]; Subnav; Alert 409/bloco como NovaViagemPage; useAtalho("ctrl+s"); sem id → só o formulário; com id → Tabs: dados · documentos (count) · pendencias (count abertas) · viagens (count) · atendimentos (count) com Tabs.Panel: <DadosPessoaForm/> · <DocumentosPessoa clienteId verDocumento podeEditar/> · <ListaPendencias clienteId viagens vendedores podeEditar/> · <ViagensPessoa viagens/> · <AtendimentosPessoa clienteId podeEditar/>
//  GrupoInlineModal: onCriado → invalidate chavesGrupos.lista + form.setValue("grupoId", g.id, { shouldDirty: true })
// rotas.tsx: /clientes → ClientesPage; /clientes/nova → PessoaPage; /clientes/:id → PessoaPage (mantém o RotaProtegida de T0)
```

- [ ] **Step 1: Testes** — `useFiltrosClientes.test.ts` (default; `definir({pendencia:"urgente"})` escreve URL e reseta página; `ativos`); `ClientesPage.test.tsx` (fetch stub `/clientes?` com 2 itens + contadores, `/grupos?`): header "3 pessoas"; linha "Carlos Mendes" com `***.456.789-**`; clicar → `/clientes/<id>`; badge "1 · urgente"); `PessoaPage.test.tsx` (stub `/clientes/<id>` do protótipo Lúcia + tabs vazias): header "Lúcia Mendes", tabs 5 com contadores; editar Cidade → "● Alterações não salvas"; Ctrl+S → `PUT /clientes/<id>` com `versao` e depois "✓ Salvo às"; `/clientes/nova` sem tabs, salvar → `POST /clientes` e navega para `/clientes/<novo id>`; perfil sem `cliente.ver_documento` (stub sem `cpf`) não renderiza o campo CPF.
- [ ] **Step 2–4:** RED → implementar (`PessoaPage.tsx` ≤ 200 linhas; `DadosPessoaForm.tsx` ≤ 200) → vitest, lint, typecheck, build.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(clientes): client list with url filters and person page with data form and tabs`

---

### Task 7 (front): Tabs da pessoa, generalização de pendências/anexos, documentos dos passageiros na viagem

**Files:**
- Create: `frontend/src/components/Cadastros/pessoa/{DocumentosPessoa.tsx,DocumentosPessoa.test.tsx,DocumentoModal.tsx,DocumentoModal.test.tsx,ViagensPessoa.tsx,AtendimentosPessoa.tsx,AtendimentosPessoa.test.tsx,AtendimentoModal.tsx,agruparAtendimentos.ts,agruparAtendimentos.test.ts,Pessoa.module.css}`
- Modify: `frontend/src/components/Pendencias/ListaPendencias.tsx`, `frontend/src/components/Pendencias/ListaPendencias.test.tsx` (+2), `frontend/src/components/Pendencias/NovaPendenciaModal.tsx`, `frontend/src/components/Pendencias/NovaPendenciaModal.test.tsx` (+1), `frontend/src/components/Pendencias/chave.ts` (+ `chaveDasPendenciasDaPessoa`), `frontend/src/components/Anexos/ListaAnexos.tsx`, `frontend/src/components/Anexos/ListaAnexos.test.tsx` (+1), `frontend/src/components/Anexos/AnexarModal.tsx`, `frontend/src/components/Anexos/AnexarModal.test.tsx` (+1)
- Modify: `frontend/src/pages/viagens/detalhe/DocumentosTab.tsx` (R11)

**Depends-on:** T5

**Interfaces:**
```ts
// Pendências (R10) — props de viagem inalteradas
type EscopoPendencias = { viagemId: string; passageiros: PassageiroDto[] } | { clienteId: string; viagens: ViagemDaPessoaDto[] };
<ListaPendencias {...escopo} vendedores podeEditar />
//  escopo cliente: useQuery(chavesClientes.pendencias(id, mostrar)); criar via clientesApi.criarPendencia; linha mostra "· viagem {codigo}" quando codigoViagem; automáticas sem Editar/Excluir (igual); invalidação = chaveDasPendenciasDaPessoa(clienteId)
<NovaPendenciaModal escopo … />   // escopo cliente: sem chips "Para quem"; Select "Viagem relacionada (opcional)" (viagens não canceladas); botão "Criar pendência"
// Anexos (R10)
type EscopoAnexos = { viagemId: string; reservas: ReservaDto[] } | { clienteId: string };
<ListaAnexos {...escopo} podeEnviar />   // cliente: useQuery(chavesClientes.anexos(id)); item "pessoa · sensível · descarte {data}"; AnexarModal sem Select de vínculo, Checkbox sensível marcado por padrão, "Descartar em" default hoje+180
// Documentos
<DocumentosPessoa clienteId verDocumento podeEditar />
//  bloco "Documentos" (meta "Alerta 180 dias antes de vencer · acesso registrado (LGPD)") + Button primary sm "+ Documento" (podeEditar) · DataTable: Tipo (StatusBadge documento_tipo? não — texto de apresentacaoStatus("documento_tipo")) · Número (<code>; sem verDocumento → "•••••") · Emissão (DateCell) · Validade (DateCell + Badge de situacaoValidade(diasParaVencer)) · País · ⋯ (Editar · Excluir; podeEditar) · vazio "Nenhum documento cadastrado" · abaixo: <ListaAnexos clienteId podeEnviar={podeEditar}/>
<DocumentoModal open clienteId documento? onClose onSalvo />   // Select Tipo · Input Número (mono) · DateInput Emissão · DateInput Validade · Input País; 422 via errosDeCadastro; excluir = ConfirmModal danger na lista
// Viagens
<ViagensPessoa viagens={ViagemDaPessoaDto[]} />   // DataTable: Viagem (destino; secondary "{Tipo} · <code>{codigo}</code>") · Período (formatarPeriodo) · Papel ("titular" | "passageira") · Fase (StatusCell fase_viagem) · Financeiro (StatusCell comissao) · Vendido (MoneyCell, só se vendaTotal presente no 1º item) → nav(/viagens/{id}); vazio "Nenhuma viagem ainda"
// Atendimentos
export function agruparAtendimentos(itens: AtendimentoDto[], hoje: Date): { chave: string; titulo: string; recolhido: boolean; itens: AtendimentoDto[] }[]
//  ano corrente → um grupo por mês ("Abril de 2026"), anos anteriores → um grupo por ano ("2025", recolhido)
<AtendimentosPessoa clienteId podeEditar />
//  topo: Button primary "+ Registrar atendimento" · Select "Canal: todos" · "{n} registros · agrupados por mês"; grupos: cabeçalho + lista (canal em negrito · resumo · "dd/mm · usuário"), anos anteriores em <details>; ⋯ Editar · Excluir (podeEditar)
<AtendimentoModal open clienteId atendimento? onClose onSalvo />   // Select Canal · Textarea Resumo (required) · Input datetime-local "Quando" (default agora)
// DocumentosTab da viagem (R11)
//  <ListaAnexos viagemId reservas podeEnviar/> + bloco "Documentos dos passageiros": para cada passageiro, useQuery(chavesClientes.documentos(clienteId)) → linhas "{nome} · {Tipo} · {numero | •••••} · validade {data} {badge}" + link "Abrir cadastro" (/clientes/{id}?tab=documentos); passageiro sem documentos → "Sem documentos cadastrados"
```

- [ ] **Step 1: Testes** — `ListaPendencias.test.tsx` (+): escopo cliente chama `/clientes/<id>/pendencias?incluirConcluidas=false`; criar envia `viagemId`. `NovaPendenciaModal.test.tsx` (+): escopo cliente mostra "Viagem relacionada" e não mostra chips. `ListaAnexos.test.tsx` (+): escopo cliente chama `/clientes/<id>/anexos`. `AnexarModal.test.tsx` (+): escopo cliente envia `clienteId` e `sensivel: true` por padrão. `DocumentosPessoa.test.tsx`: lista 2 docs com badge "32 dias"; sem `verDocumento` mostra "•••••"; "+ Documento" abre o modal. `DocumentoModal.test.tsx`: submit envia `tipo`, `numero`, datas; 422 `validade_invalida` → erro no campo Validade. `agruparAtendimentos.test.ts`: 3 itens (2 no mês atual, 1 em 2025) → 2 grupos, 2025 recolhido. `AtendimentosPessoa.test.tsx`: renderiza grupos; filtro canal refaz a query com `?canal=ligacao`.
- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck, tokens.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(pessoa): documents, atendimentos and trips tabs; pendencias/anexos lists generalized to person scope; passenger documents on trip page`

---

### Task 8 (front): Grupos — lista e página

**Files:**
- Create: `frontend/src/pages/grupos/{GruposPage.tsx,GruposPage.test.tsx,GrupoPage.tsx,GrupoPage.test.tsx,PessoasDoGrupo.tsx,useGrupo.ts,Grupos.module.css}`
- Modify: `frontend/src/pages/grupos/rotas.tsx`

**Depends-on:** T5

**Interfaces:**
```ts
// GruposPage: PageHeader "Grupos e empresas" subtitle "{total} grupos · organizam o cadastro de pessoas; não têm valor financeiro" actions "+ Novo grupo" (primary, cliente.editar) · Subnav /clientes · Input busca (debounce) · DataTable: Grupo (primary nome; secondary pessoasResumo) · Tipo (StatusCell grupo_tipo) · CNPJ (<code>formatarCnpj</code> | —) · Pessoas (right) · Viagens (right) → /clientes/grupos/{id} · Paginacao
// useGrupo = useFormularioCadastro<FormGrupo, GrupoDto> (paraRequest: cnpj → somenteDigitos || null; tipo ≠ empresa → cnpj null)
// GrupoPage: Page dirty; PageHeader title={nome ?? "Novo grupo"} subtitle "{Tipo} · {n} pessoas · {viagens} viagens" actions Fechar/Salvar; form: Nome* · Tipo (Select) · CNPJ (mono, disabled se tipo ≠ empresa, helper "(empresa)") · Observações (Textarea); com id: <PessoasDoGrupo grupo podeEditar onMudou/>
<PessoasDoGrupo grupo={GrupoDto} podeEditar onMudou={() => void} />
//  eyebrow "Pessoas · N" · lista: nome (+ "menor · {idade} anos" se idade < 18) · "Abrir" (tertiary → /clientes/{id}) · "Remover" (tertiary danger, ConfirmModal; DELETE …/pessoas/{id} → invalidate chavesGrupos.grupo) · "+ Vincular pessoa": combobox de busca (viagensApi.buscarClientes, mesmo padrão de PassageirosField: role=combobox/listbox) → POST vincular → invalidate
// rotas.tsx: /clientes/grupos → GruposPage; /clientes/grupos/nova, /clientes/grupos/:id → GrupoPage
```

- [ ] **Step 1: Testes** — `GruposPage.test.tsx` (stub 2 grupos; linha "Família Mendes" com "Carlos, Lúcia"; clicar navega); `GrupoPage.test.tsx` (stub grupo empresa: CNPJ habilitado e formatado; trocar tipo para família desabilita CNPJ; Ctrl+S → PUT com `versao`; "Remover" confirma e chama DELETE; "+ Vincular pessoa" busca e chama POST).
- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(grupos): group list and group page with member linking`

---

### Task 9 (front): Fornecedores — lista e página com tabs

**Files:**
- Create: `frontend/src/pages/fornecedores/{FornecedoresPage.tsx,FornecedoresPage.test.tsx,FornecedorPage.tsx,FornecedorPage.test.tsx,DadosFornecedorForm.tsx,RegrasTab.tsx,RegrasTab.test.tsx,NovaVersaoRegraModal.tsx,NovaVersaoRegraModal.test.tsx,ReservasFornecedorTab.tsx,useFornecedor.ts,Fornecedores.module.css}`
- Modify: `frontend/src/pages/fornecedores/rotas.tsx`

**Depends-on:** T5

**Interfaces:**
```ts
// FornecedoresPage: PageHeader "Fornecedores" subtitle "{total} cadastrados · a regra de pagamento define quando a comissão é esperada" actions "+ Novo fornecedor" (primary, fornecedor.editar) · filtros: Input busca · Select "Situação: ativos | inativos | todos" (default ativos) · DataTable: Fornecedor (primary nome; secondary "plantão {telefoneEmergencia}") · Tipo (apresentacaoStatus fornecedor_tipo) · Comissão padrão (right "{n} %" | —) · Pagamento (resumoRegra(janelasVigentes, prazo)) · Reservas (right) · Receita {ano} (MoneyCell emphasis result; só se receitaAno presente no 1º item) → /fornecedores/{id} · Paginacao
// useFornecedor = useFormularioCadastro<FormFornecedor, FornecedorDetalheDto> + tab (?tab=) + reservasQ (pagina)
// FornecedorPage: PageHeader title={nome ?? "Novo fornecedor"} subtitle "{Tipo} · {reservas} reservas · comissão padrão {n} %" status={!ativo && <Badge tone="neutral">inativo</Badge>} actions Fechar/Salvar (fornecedor.editar); Tabs (com id): dados · financeiro · reservas (count)
<DadosFornecedorForm form erros />   // Nome* (span 2) · Tipo (Select 8) · CNPJ (mono) · Comissão padrão (Input number step 0.1 + sufixo "%", helper "Pré-preenche a comissão no lançamento como valor sugerido") · Telefone de emergência · Situação (Select Ativo/Inativo, helper "Inativo não aparece ao lançar reserva nova; histórico permanece") · Site / portal · Contato comercial · Telefone · Prazo de comissão (dias; helper "usado quando não há janela para o dia da compra") · Observações (Textarea, span 2)
<RegrasTab fornecedor podeEditar onMudou />
//  bloco "Quando paga a comissão" (meta "define a data prevista de cada reserva na conciliação") · Alert neutral "Regra vigente desde {formatarData(regraVigente.vigenteDesde)}" + "Alterar cria uma nova versão válida a partir de uma data. Reservas já lançadas mantêm a previsão gravada." · lista das janelas vigentes (descreverJanela) · linha "ou prazo fixo: {prazoComissaoDias} dias após a compra" quando há prazo · Button secondary sm "Nova versão da regra a partir de…" (podeEditar) · <details> "Versões anteriores ({n})" com cada versão (vigenteDesde + janelas); sem regra nenhuma: EmptyState "Sem regra de pagamento" / "A previsão usa o prazo em dias (ou 30 dias). Cadastre janelas para prever pelo calendário da operadora."
<NovaVersaoRegraModal open fornecedorId onClose onSalva />
//  DateInput "Vigente a partir de" (default hoje) · tabela editável de janelas (Dia inicial · Dia final · Dia do pagamento · Meses à frente (0–3)) com "+ Janela" e × por linha; valida localmente (1..31, inicial ≤ final) e envia; 422 vigencia_invalida → campo data; janelas_* → bloco
<ReservasFornecedorTab fornecedorId />   // DataTable paginada: Reserva (titular · destino; secondary <code>codigo</code> · <code>localizador</code>) · Compra (DateCell) · Situação (StatusCell comissao) · Venda · Esperado · Recebido (MoneyCell, só se presentes) → /viagens/{viagemId}?reserva={reservaId}
// rotas.tsx: /fornecedores → FornecedoresPage; /fornecedores/nova, /fornecedores/:id → FornecedorPage
```

- [ ] **Step 1: Testes** — `FornecedoresPage.test.tsx` (stub: CVC com janelas → célula "1–14 → dia 20 · 15–31 → dia 5 (mês seguinte)"; Decolar prazo 45 → "45 dias após a compra"; sem `receitaAno` → sem coluna); `FornecedorPage.test.tsx` (tabs 3; Ctrl+S → PUT com versao; tab financeiro renderiza "Regra vigente desde"); `RegrasTab.test.tsx` (2 janelas vigentes listadas; "Versões anteriores (1)"; botão abre modal); `NovaVersaoRegraModal.test.tsx` (adicionar 2 janelas e enviar → `POST /fornecedores/<id>/regras` com `{ vigenteDesde, janelas: [...] }`; dia final < inicial → erro local).
- [ ] **Step 2–4:** RED → implementar → vitest, lint, typecheck.
- [ ] **Step 5: Reportar.** Commit sugerido: `feat(fornecedores): supplier list, supplier page with data form, versioned payment rules tab and reservas tab`

---

### Task 10 (front): E2E dos cadastros

**Files:**
- Create: `frontend/e2e/cadastros.spec.ts`, `frontend/e2e/cadastros.ts` (helper: `abrirPessoaPorNome(page, nome)`)

**Depends-on:** T6–T9 (e seed de T0)

- [ ] **Step 1: Spec**
```ts
import { expect, test } from "@playwright/test";
import { loginUi } from "./api";

test.describe("cadastros", () => {
  test("lista → pessoa → documentos → edita e salva com Ctrl+S", async ({ page }) => {
    await loginUi(page);
    await page.goto("/clientes");
    await page.getByPlaceholder(/Nome, CPF/).fill("Lúcia");
    await page.getByRole("row", { name: /Lúcia Mendes/ }).click();
    await expect(page.getByRole("heading", { name: /Lúcia Mendes/ })).toBeVisible();
    await page.getByRole("tab", { name: /Documentos/ }).click();
    await expect(page.getByText("GB998877")).toBeVisible();          // dono tem cliente.ver_documento
    await page.getByRole("tab", { name: "Dados" }).click();
    await page.getByLabel("Cidade").fill(`Campinas ${Date.now() % 1000}`);
    await expect(page.getByText("Alterações não salvas")).toBeVisible();
    await page.keyboard.press("Control+S");
    await expect(page.getByText(/Salvo às/)).toBeVisible();
  });

  test("grupo mostra as pessoas e fornecedor mostra a regra vigente", async ({ page }) => {
    await loginUi(page);
    await page.goto("/clientes/grupos");
    await page.getByRole("row", { name: /Família Mendes/ }).click();
    await expect(page.getByText("Carlos Mendes")).toBeVisible();
    await page.goto("/fornecedores");
    await page.getByRole("row", { name: /CVC/ }).click();
    await page.getByRole("tab", { name: "Financeiro" }).click();
    await expect(page.getByText("Vendas de 1 a 14")).toBeVisible();
  });
});
```
- [ ] **Step 2: Rodar** com API + seed (`backend/scripts/dev.md`): `npx playwright test e2e/cadastros.spec.ts` → verde nos 2 viewports. Se 3.5 já fechou, rodar também `e2e/nova-viagem.spec.ts` e anotar o tempo (contrato C14).
- [ ] **Step 3: Reportar.** Commit sugerido: `test(e2e): client/person/group/supplier flows`

---

### Task 11 (root): Docs e fechamento — **serial com o fechamento de 3.5**

**Files:**
- Modify: `docs/BACKLOG.md` (3.4 concluída com contagens; remover das "Deferidas da 3.3": documentos de passageiro na tab Documentos, `ClienteVerProprios` completo em anexos; novas deferidas: R2 (CPF sem log — revisar LGPD no piloto), R3 (vínculo documento↔anexo), R7 (janelas → prazo puro), `interacao` sem auditoria por trigger, filtro "só automáticos" do protótipo, subnav "Grupos" visível ao externo, mais o que os reviews levantarem)
- Modify: `docs/autorizacao-por-operacao.md` (tabela "Permissões" deste plano; nota R2)
- Modify: `docs/superpowers/plans/2026-09-08-fase-3-master.md` (linha 3.4: "(concluído: 11 tasks, 5 ondas)"; endpoints divergentes atualizados)
- Modify: `CLAUDE.md` (linha Estado: 3.4 ✓ com contagens; migrations 0001–0015; próximo 3.5 ou 3.6 conforme o outro subplano)
- Modify: `regras-e-escopo-v2.md` §9 (nota: atendimentos = `interacao`, canais fixos) e decisão 30 (nota R2)

**Depends-on:** T10

- [ ] **Step 1–2:** editar; controlador commita no root: `docs: fase 3.4 cadastros done — backlog, authorization table, state line, rulings`

---

## Self-review (feito ao escrever)

- **Spec §2/§3** pessoa, grupo opcional (uma pessoa, um grupo), fornecedor sempre existe → T1/T3/T4 ✓. **§4.5** vigência: versão nova por `vigente_desde`, reservas antigas intocadas → T4 (teste de invariante) ✓; prazo em dias não versionado (R7, BACKLOG) ✓.
- **§7.2** `cliente.ver_documento`: `cpf` no detalhe, `documento.numero`, anexo sensível → T1/T2 ✓; `ClienteVerProprios` em lista/detalhe/viagens/documentos/atendimentos/pendências/anexos → `VisibilidadeCliente` (T1/T2) ✓. **§8** LGPD: `log_acesso_documento` por documento lido → T2 ✓ (CPF: R2, registrado).
- **§9** pendências da pessoa (suas + das viagens em que é passageira), "+ Nova pendência" exige data (DateInput required), "Mostrar concluídas" → T2/T7 ✓; atendimentos por mês, anos anteriores recolhidos → T7 `agruparAtendimentos` ✓; checklist derivado → 3.6 (R4) ✓.
- **Decisões** 27 (grupo), 30 (CPF mascarado em lista), 32 (página própria), 33/34 (pendências: job em 3.6; badge de Clientes na sidebar = 3.6, `navegacao.ts` é de 3.5) → cobertas ou anotadas ✓.
- **Contrato §4.1/§4.2/§4.4**: cadastro em página própria com Fechar/Salvar; tabs Pessoa (5) e Fornecedor (3); filtros "busca + 2 principais + Filtros ● N" → T6 ✓; linha de pendência com uma ação + ⋯ (reuso de 3.3) ✓; `Textarea` (T0) ✓.
- **Contrato 3.4∥3.5**: nenhum arquivo fora de §3 do contrato é tocado (conferido task a task: `Endpoints.cs`, `Guardas.cs`, `PostgresFixture.cs`, `rotasModulos.tsx`, `status.ts`, `datas.ts`, `http.ts`, `index.ts`, `navegacao.ts`, `ViagemPage.tsx`, `api/viagens.ts` intocados) ✓. `GET /fornecedores` e `POST /clientes`/`POST /fornecedores` mantêm forma de resposta (R6/R7) ✓.
- **Placeholders**: nenhum; `VisibilidadeCliente.cs` tem conteúdo canônico para as duas tasks que o podem criar; `DELETE …/pessoas/{clienteId}` devolve 204 (Contrato, T3, T5 coerentes).
- **Tipos**: DTOs C# ↔ TS campo a campo; `chavesClientes.pendencias` usada por `ListaPendencias` (T7) e `usePessoa` (T6); `errosDeCadastro`/`useFormularioCadastro` (T5) usados por T6/T8/T9; `resumoRegra`/`descreverJanela` (T5) por T9; `situacaoValidade` (T5) por T7 ✓.
- **Ondas**: T1×T2 disjuntos por arquivo (exceção controlada: `VisibilidadeCliente.cs`); T2×T3×T4 pastas distintas; T5 só front; T7×T8×T9 pastas/rotas próprias; T6 depois de T7 (compõe as tabs) ✓.
