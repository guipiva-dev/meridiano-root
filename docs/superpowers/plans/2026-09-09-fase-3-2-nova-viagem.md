# Meridiano — Fase 3.2 — Nova viagem: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execução em ondas:** segue `.claude/rules/parallel-subagent-driven-development.md`. Cada task traz `Files:` e `Depends-on:`. Implementadores **não commitam**; o controlador commita uma task por vez, no repo certo (`backend/` = `meridiano-api`, `frontend/` = `meridiano-app`, root só docs).

**Goal:** lançar uma viagem completa (passageiros, N reservas, repasse, pendências automáticas) numa transação, a partir de uma tela que se opera só pelo teclado com pré-preenchimento — e provar com E2E cronometrado que 4 reservas cabem em ≤ 5 min.

**Architecture:** backend ganha três módulos (`Modules/Viagens`, `Modules/Pessoas`, `Modules/Fornecedores`) e dois endpoints de apoio (`GET /usuarios/vendedores`, `GET /agencia`). `ViagensService.CriarAsync` grava viagem + passageiros + reservas + repasse + pendências numa `DbSessao`, usando `Guardas` (3.0) para referência/lock; `PrevisaoComissao.Calcular` (Fase 2) escolhe a janela vigente por `data_compra`; `Meridiano.Domain.Financeiro.CalculoReserva` espelha as generated columns para preview e é testado por equivalência contra o banco. Front: `NovaViagemPage` com react-hook-form + `useFieldArray`, `ReservationCard`/`TripSummary` como componentes de domínio, preview em `src/dominio/calculoReserva.ts` (mesmas fórmulas; backend vence ao salvar), estado via `useSalvamento` + `Page dirty`.

**Tech Stack:** .NET 10 · Dapper · Npgsql · PostgreSQL 17 · xUnit + Testcontainers · React 19 · react-router 8 · TanStack Query 5 · react-hook-form 7 · Vitest · Playwright.

**Spec:** `regras-e-escopo-v2.md` §3, §4.1–§4.5, §5, §9, §13 (exemplos A–E), §14 · `docs/superpowers/plans/2026-09-08-fase-3-master.md` (linha 3.2, "Contratos transversais", D1 aceita: fornecedor inline mínimo) · `docs/design-system-contrato.md` §3, §4, §4.1, §6, §7 · `docs/design/prototipo-v1.html` tela `#s-nova-viagem` · `docs/autorizacao-por-operacao.md`.

## Global Constraints

- Backend: `Program.cs` não muda; módulos registram serviços em `Endpoints.AddModules` e rotas em `Endpoints.MapEndpoints`. `TreatWarningsAsErrors=true`; `dotnet format --verify-no-changes` limpo.
- Toda query em `DbSessao`; filtra `agencia_id` e `excluido_em is null`. Todo `*_id` do payload passa por `Guardas.ReferenciaAsync` na mesma transação. Mutação do agregado viagem começa com `Guardas.TravarViagemAsync` e termina com `Guardas.TocarViagemAsync` se só filhos mudaram.
- Erros: `RegraDeNegocioException(codigo, msg)` → 422; `ConflitoConcorrenciaException` → 409. **Ruling 3.2:** `nao_encontrado` continua 422 (convenção de 3.0/Admin); registrado em `docs/autorizacao-por-operacao.md` na Task 10.
- Dinheiro `decimal` com 2 casas, BRL; datas de serviço `DateOnly` ↔ `yyyy-MM-dd`; arrays nunca `null`. DTO por perfil: sem `ReservaVerValores` os campos de valor **não existem** no JSON (`JsonIgnore(WhenWritingNull)` + `null`); sem `ViagemVerResultado`, `resumo` e `repasse` não existem.
- Permissões (matriz `Permissoes.cs`): `POST /viagens` = `ViagemCriar`; `PUT`/`POST reservas` = `ViagemEditar`; trocar `vendedor_id` = `ViagemDefinirVendedor`; `GET /viagens/{id}` = `ViagemVer` ou `ViagemVerProprias` (filtro `vendedor_id = usuario`); `POST /clientes` = `ClienteEditar`; `POST /fornecedores` = `FornecedorEditar`; `GET /fornecedores`, `GET /usuarios/vendedores`, `GET /agencia`, `GET /clientes/busca` = qualquer autenticado (`RequireAuthorization()`); `GET /clientes/busca` omite `cpf` sem `ClienteVerDocumento`.
- Front: CSS Modules + `tokens.css` (congelado) + `global.css`; sem hex, `font-size:` solto ou `@media` fora de 700/1024/1280/1366/1440; ícones lucide via tokens; máx. 350 linhas/arquivo; textos em português; `npm run lint`, `typecheck`, `test`, `build` verdes.
- Front nunca protege; `pode()` só esconde. Cálculo no front é preview; ao salvar, a resposta da API substitui os valores.
- Atalhos só pelo registry: `ctrl+s` salvar · `ctrl+enter` adicionar reserva · `escape` recolher card (quando nenhum modal aberto).
- Tempo: E2E `e2e/nova-viagem.spec.ts` cronometra 4 reservas e grava o tempo no relatório; meta automatizada informativa; **meta humana ≤ 5 min** fica para o teste de UX (§7) e é registrada separadamente no BACKLOG.
- Commits Conventional Commits em inglês com rodapé de atribuição da sessão.

---

## Ondas

| Onda | Tasks | Motivo |
|---|---|---|
| 0 | T1 (backend base), T5 (front base) | repos diferentes |
| 1 | T2 (backend apoio), T6, T7 (front) | T2 usa fixture de T1 e toca `Modules/Endpoints.cs`; T6/T7 usam T5, pastas disjuntas |
| 2 | T3 (backend viagens), T8 (front página) | T3 toca `Modules/Endpoints.cs` (por isso não vai junto de T2); T8 usa T6+T7 e os contratos de T2–T4 (E2E só em T9) |
| 3 | T4 (backend edição/consultas) | estende `ViagensService` de T3 |
| 4 | T9 (seed + E2E + styleguide) | precisa de tudo |
| 5 | T10 (docs, root) | fechamento |

---|---|---|
| 0 | T1 (backend base), T5 (front base) | repos diferentes; nada depende ainda |
| 1 | T2, T3 (backend), T6, T7 (front) | T2/T3 usam fixture e `CalculoReserva` de T1, pastas disjuntas; T6/T7 usam `calculoReserva.ts`/`api/viagens.ts` de T5, pastas disjuntas |
| 2 | T4 (backend), T8 (front) | T4 estende `ViagensService` (T3); T8 monta a página com T6+T7 e os contratos de T2–T4 |
| 3 | T9 (seed + E2E) | precisa de tudo |
| 4 | T10 (docs, root) | fechamento |

---

## Contrato de API (fonte única para backend e front)

```
POST /api/v1/viagens                 ViagemRequest            → 201 ViagemDto (Location: /api/v1/viagens/{id})
GET  /api/v1/viagens/{id}                                      → 200 ViagemDto
PUT  /api/v1/viagens/{id}            ViagemRequest + versao   → 200 ViagemDto | 409
POST /api/v1/viagens/{id}/reservas   { reserva, versao }      → 200 ViagemDto | 409
GET  /api/v1/viagens/semelhantes?clienteId&dataIda&dataVolta   → 200 ViagemSemelhanteDto[]
GET  /api/v1/reservas/duplicada?fornecedorId&localizador       → 200 { viagemId, codigo } | 204
GET  /api/v1/clientes/busca?q=                                 → 200 ClienteBuscaDto[] (≤ 10)
POST /api/v1/clientes                { nome, telefone?, email?, cpf? } → 201 ClienteBuscaDto
GET  /api/v1/fornecedores?ativo=true                           → 200 FornecedorDto[]
POST /api/v1/fornecedores            { nome, tipo }            → 201 FornecedorDto
GET  /api/v1/usuarios/vendedores                               → 200 VendedorDto[]
GET  /api/v1/agencia                                           → 200 { nome, taxaServicoPadrao }
```

```csharp
// Modules/Viagens/ViagemDtos.cs — nomes exatos; o front espelha em src/api/viagens.ts
public sealed record PassageiroRequest(Guid ClienteId, bool Titular);
public sealed record ReservaRequest(
    Guid? Id, Guid FornecedorId, string? Localizador, DateOnly DataCompra, string Status,   // pendente | emitida
    string[] TiposServico, decimal ValorTotal, decimal ValorTaxas, decimal ValorComissao, decimal RavOperadora,
    decimal ValorCliente, decimal TaxaServico, string RavClienteModo,                          // retido_agencia | via_operadora
    string FluxoPagamento,                                                                     // cliente_paga_operadora | cliente_paga_agencia
    string[] FormasPagamento, string NfseStatus, string? Observacoes);
public sealed record ViagemRequest(
    string Destino, string Tipo, DateOnly? DataIda, DateOnly? DataVolta, Guid VendedorId, Guid? AgenteId,
    string? Ocasiao, string? Observacoes, PassageiroRequest[] Passageiros, decimal? RepasseValor,
    ReservaRequest[] Reservas, string? Versao);
public sealed record NovaReservaRequest(ReservaRequest Reserva, string Versao);

public sealed record PassageiroDto(Guid ClienteId, string Nome, bool Titular);
public sealed record ReservaDto(
    Guid Id, string Versao, Guid FornecedorId, string FornecedorNome, string? Localizador, DateOnly DataCompra, string Status,
    string[] TiposServico, string[] FormasPagamento, string RavClienteModo, string FluxoPagamento, string NfseStatus, string? Observacoes,
    DateOnly? DataPrevistaComissao,
    // omitidos sem ReservaVerValores
    decimal? ValorTotal, decimal? ValorTaxas, decimal? ValorComissao, decimal? RavOperadora, decimal? ValorCliente, decimal? TaxaServico,
    decimal? RavCliente, decimal? ValorEsperadoOperadora, decimal? ReceitaPrevista, decimal? PercentualComissao);
public sealed record RepasseDto(Guid Id, decimal? Valor, string Status);
public sealed record ResumoViagemDto(decimal VendaTotal, decimal CustoFornecedores, decimal ReceitaPrevista, decimal? RepasseValor, decimal DespesasViagem, decimal Resultado);
public sealed record ViagemDto(
    Guid Id, string Codigo, string Versao, string Destino, string Tipo, DateOnly? DataIda, DateOnly? DataVolta,
    Guid VendedorId, string VendedorNome, Guid? AgenteId, string? Ocasiao, string? Observacoes, bool Cancelada,
    string FaseOperacional, string FaseFinanceira, PassageiroDto[] Passageiros, ReservaDto[] Reservas,
    RepasseDto? Repasse, ResumoViagemDto? Resumo);   // Repasse/Resumo omitidos sem ViagemVerResultado
public sealed record ViagemSemelhanteDto(Guid Id, string Codigo, string Destino, DateOnly? DataIda, DateOnly? DataVolta, string FaseOperacional, bool Sobrepoe);
```

Códigos 422 novos: `titular_obrigatorio`, `titular_duplicado`, `passageiro_duplicado`, `sem_passageiro`, `vendedor_inativo`, `fornecedor_inativo`, `tipo_invalido`, `status_invalido`, `datas_incoerentes`, `valor_negativo`, `tipos_servico_invalido`, `formas_pagamento_invalido`, `repasse_sem_vendedor`, `reserva_nao_encontrada`, `busca_curta`.

---

### Task 1 (backend): Base — `CalculoReserva`, `DateOnly` no Dapper, `Guardas` com `ativo`, fixture

**Files:**
- Create: `backend/src/Meridiano.Domain/Financeiro/CalculoReserva.cs`
- Create: `backend/tests/Meridiano.Domain.Tests/CalculoReservaTests.cs`
- Modify: `backend/src/Meridiano.Api/Data/SessaoExtensions.cs` (onde está `AddSessao`; confirmar o nome do arquivo com `grep -rn "AddSessao" backend/src/Meridiano.Api`)
- Modify: `backend/src/Meridiano.Api/Modules/Comum/Guardas.cs`
- Modify: `backend/tests/Meridiano.Api.Tests/GuardasTests.cs` (+1)
- Modify: `backend/tests/Meridiano.Api.Tests/Fixtures/PostgresFixture.cs` (+3 helpers)

**Depends-on:** none

**Interfaces:**
- Produces:
```csharp
namespace Meridiano.Domain.Financeiro;
public sealed record ValoresReserva(decimal ValorTotal, decimal ValorComissao, decimal RavOperadora, decimal ValorCliente, decimal TaxaServico, bool ViaOperadora, bool Cancelada, bool ComissaoMantida);
public sealed record ResultadoReserva(decimal RavCliente, decimal ValorEsperadoOperadora, decimal ReceitaPrevista, decimal? PercentualComissao);
public static class CalculoReserva { public static ResultadoReserva Calcular(ValoresReserva v); }
```
  - `Guardas.ReferenciaAsync(DbSessao s, Tabela tabela, Guid id, Guid agenciaId, CancellationToken ct, bool exigirAtivo = false)` — com `exigirAtivo` e tabela `Usuario`/`Fornecedor`, acrescenta `and ativo`; outras tabelas ignoram o flag. Código de erro quando inativo: `usuario_inativo` / `fornecedor_inativo`.
  - `SqlMapper.AddTypeMap(typeof(DateOnly), DbType.Date)` e `typeof(DateOnly?)` registrados em `AddSessao` (uma vez). Depois disso, `Guardas.CompetenciaAbertaAsync` volta a passar `competencia` (`DateOnly`) direto — remover o `ToDateTime`.
  - Fixture: `InserirFornecedorAsync(Guid agenciaId, string nome, decimal? percentualComissaoPadrao = null, int? prazoComissaoDias = null)` (assinatura estendida, compatível); `InserirRegraPagamentoAsync(Guid agenciaId, Guid fornecedorId, int diaInicial, int diaFinal, int diaPagamento, int mesesAFrente, DateOnly? vigenteDesde = null)`; `InserirUsuarioAsync` já existe (`geraRepasse`); `DefinirPercentualPadraoAsync(Guid usuarioId, decimal percentual)`.

- [ ] **Step 1: Testes de domínio (§13 A–E)**

`CalculoReservaTests.cs`:
```csharp
using Meridiano.Domain.Financeiro;

namespace Meridiano.Domain.Tests;

public sealed class CalculoReservaTests
{
    private static ValoresReserva V(decimal total, decimal comissao, decimal ravOp, decimal cliente, decimal taxa = 0, bool via = false, bool cancelada = false, bool mantida = false)
        => new(total, comissao, ravOp, cliente, taxa, via, cancelada, mantida);

    [Fact] public void A_comissionada_simples() { var r = CalculoReserva.Calcular(V(10000, 1000, 100, 10000)); Assert.Equal((0m, 1100m, 1100m, 10.00m), (r.RavCliente, r.ValorEsperadoOperadora, r.ReceitaPrevista, r.PercentualComissao)); }
    [Fact] public void B_rav_cliente_via_operadora() { var r = CalculoReserva.Calcular(V(10000, 1000, 100, 10500, via: true)); Assert.Equal((500m, 1600m, 1600m), (r.RavCliente, r.ValorEsperadoOperadora, r.ReceitaPrevista)); }
    [Fact] public void C_rav_cliente_retido() { var r = CalculoReserva.Calcular(V(10000, 1000, 100, 10500)); Assert.Equal((500m, 1100m, 1600m), (r.RavCliente, r.ValorEsperadoOperadora, r.ReceitaPrevista)); }
    [Fact] public void D_markup() { var r = CalculoReserva.Calcular(V(800, 0, 0, 1000)); Assert.Equal((200m, 0m, 200m, 0.00m), (r.RavCliente, r.ValorEsperadoOperadora, r.ReceitaPrevista, r.PercentualComissao)); }
    [Fact] public void E_cancelada_sem_comissao_mantida_zera() { var r = CalculoReserva.Calcular(V(10000, 1000, 100, 10500, via: true, cancelada: true)); Assert.Equal((0m, 0m), (r.ValorEsperadoOperadora, r.ReceitaPrevista)); Assert.Equal(500m, r.RavCliente); }
    [Fact] public void Cancelada_com_comissao_mantida_mantem() { var r = CalculoReserva.Calcular(V(10000, 1000, 100, 10000, cancelada: true, mantida: true)); Assert.Equal(1100m, r.ValorEsperadoOperadora); }
    [Fact] public void Percentual_nulo_sem_total() { Assert.Null(CalculoReserva.Calcular(V(0, 0, 0, 0)).PercentualComissao); }
    [Fact] public void Percentual_arredonda_como_o_banco() { Assert.Equal(33.33m, CalculoReserva.Calcular(V(300, 100, 0, 300)).PercentualComissao); }
}
```

- [ ] **Step 2: Rodar para ver falhar** — `cd backend && dotnet test tests/Meridiano.Domain.Tests` → erro de compilação.

- [ ] **Step 3: `CalculoReserva.cs`** (espelho exato das generated columns de `0001_schema_v2.sql:355-365`)

```csharp
namespace Meridiano.Domain.Financeiro;

public sealed record ValoresReserva(decimal ValorTotal, decimal ValorComissao, decimal RavOperadora, decimal ValorCliente, decimal TaxaServico, bool ViaOperadora, bool Cancelada, bool ComissaoMantida);

public sealed record ResultadoReserva(decimal RavCliente, decimal ValorEsperadoOperadora, decimal ReceitaPrevista, decimal? PercentualComissao);

// Preview das generated columns de `reserva` (spec §4.2). O banco é a autoridade; este código só antecipa o resultado.
public static class CalculoReserva
{
    public static ResultadoReserva Calcular(ValoresReserva v)
    {
        var ravCliente = v.ValorCliente - v.ValorTotal;
        var zera = v.Cancelada && !v.ComissaoMantida;
        var esperado = zera ? 0 : v.ValorComissao + v.RavOperadora + (v.ViaOperadora ? ravCliente : 0);
        var prevista = zera ? 0 : v.ValorComissao + v.RavOperadora + ravCliente + v.TaxaServico;
        decimal? percentual = v.ValorTotal > 0 ? Math.Round(100 * v.ValorComissao / v.ValorTotal, 2, MidpointRounding.AwayFromZero) : null;
        return new ResultadoReserva(ravCliente, esperado, prevista, percentual);
    }
}
```

- [ ] **Step 4: `DateOnly` no Dapper** — em `AddSessao`, antes de registrar `DbSessaoFactory`:
```csharp
SqlMapper.AddTypeMap(typeof(DateOnly), DbType.Date);
SqlMapper.AddTypeMap(typeof(DateOnly?), DbType.Date);
```
(`using System.Data; using Dapper;`). Em `Guardas.CompetenciaAbertaAsync` trocar `competencia = competencia.ToDateTime(TimeOnly.MinValue)` por `competencia` e apagar o comentário sobre Dapper.

- [ ] **Step 5: `Guardas.ReferenciaAsync` com `exigirAtivo`**

```csharp
private static readonly Dictionary<Tabela, (string Nome, bool TemExcluidoEm, bool TemAtivo)> Tabelas = new()
{
    [Tabela.Cliente] = ("cliente", true, false),
    [Tabela.Fornecedor] = ("fornecedor", false, true),
    [Tabela.Usuario] = ("usuario", false, true),
    [Tabela.Viagem] = ("viagem", true, false),
    [Tabela.Reserva] = ("reserva", true, false),
    [Tabela.Grupo] = ("grupo_cliente", true, false),
    [Tabela.Despesa] = ("despesa", true, false),
};

public static async Task ReferenciaAsync(DbSessao s, Tabela tabela, Guid id, Guid agenciaId, CancellationToken ct, bool exigirAtivo = false)
{
    var (nome, temExcluido, temAtivo) = Tabelas[tabela];
    var filtro = temExcluido ? " and excluido_em is null" : "";
    var existe = await s.Conexao.ExecuteScalarAsync<bool>(new CommandDefinition(
        $"select exists (select 1 from {nome} where id = @id and agencia_id = @agenciaId{filtro})", new { id, agenciaId }, s.Transacao, cancellationToken: ct));
    if (!existe) throw new RegraDeNegocioException("referencia_invalida", $"{nome} não encontrado");
    if (!exigirAtivo || !temAtivo) return;
    var ativo = await s.Conexao.ExecuteScalarAsync<bool>(new CommandDefinition(
        $"select ativo from {nome} where id = @id", new { id }, s.Transacao, cancellationToken: ct));
    if (!ativo) throw new RegraDeNegocioException($"{nome}_inativo", $"{nome} inativo");
}
```
Teste em `GuardasTests.cs`:
```csharp
[Fact]
public async Task Referencia_com_exigirAtivo_rejeita_inativo()
{
    var (a, _, _) = await BaseAsync("guarda-ativo");
    var f = await pg.InserirFornecedorAsync(a, "Inativo");
    await pg.QueryOwnerAsync<int>("update fornecedor set ativo = false where id = @f returning 1", new { f });
    var factory = new DbSessaoFactory(pg.ConnApi);
    await using var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), Ct);
    await Guardas.ReferenciaAsync(s, Tabela.Fornecedor, f, a, Ct); // sem flag: passa
    var ex = await Assert.ThrowsAsync<RegraDeNegocioException>(() => Guardas.ReferenciaAsync(s, Tabela.Fornecedor, f, a, Ct, exigirAtivo: true));
    Assert.Equal("fornecedor_inativo", ex.Codigo);
}
```

- [ ] **Step 6: Fixture**

```csharp
public async Task<Guid> InserirFornecedorAsync(Guid agenciaId, string nome, decimal? percentualComissaoPadrao = null, int? prazoComissaoDias = null) =>
    (await QueryOwnerAsync<Guid>(
        "insert into fornecedor (agencia_id, nome, percentual_comissao_padrao, prazo_comissao_dias) values (@agenciaId, @nome, @percentualComissaoPadrao, @prazoComissaoDias) returning id",
        new { agenciaId, nome, percentualComissaoPadrao, prazoComissaoDias })).Single();

public Task InserirRegraPagamentoAsync(Guid agenciaId, Guid fornecedorId, int diaInicial, int diaFinal, int diaPagamento, int mesesAFrente, DateOnly? vigenteDesde = null) =>
    QueryOwnerAsync<int>(
        "insert into regra_pagamento_fornecedor (agencia_id, fornecedor_id, dia_inicial, dia_final, dia_pagamento, meses_a_frente, vigente_desde) values (@agenciaId, @fornecedorId, @diaInicial, @diaFinal, @diaPagamento, @mesesAFrente, coalesce(@vigenteDesde, current_date)) returning 1",
        new { agenciaId, fornecedorId, diaInicial, diaFinal, diaPagamento, mesesAFrente, vigenteDesde });

public Task DefinirPercentualPadraoAsync(Guid usuarioId, decimal percentual) =>
    QueryOwnerAsync<int>("update usuario set percentual_padrao = @percentual where id = @usuarioId returning 1", new { usuarioId, percentual });
```
`QueryOwnerAsync` usa conexão solta: registrar o type map também nos testes — em `PostgresFixture.InitializeAsync`, primeira linha: `SqlMapper.AddTypeMap(typeof(DateOnly), DbType.Date); SqlMapper.AddTypeMap(typeof(DateOnly?), DbType.Date);`.

- [ ] **Step 7: Rodar tudo** — `cd backend && dotnet build -c Release && dotnet test && dotnet format --verify-no-changes` → 0 falhas (12+8 domínio, 56+1 API).

- [ ] **Step 8: Reportar arquivos tocados.** Commit sugerido: `feat(domain): CalculoReserva preview; DateOnly dapper map; Guardas exigirAtivo; fixture for fornecedor rules`

---

### Task 2 (backend): Consultas de apoio — Pessoas, Fornecedores, vendedores, agência

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Pessoas/{PessoasEndpoints.cs,PessoaDtos.cs,PessoasService.cs}`
- Create: `backend/src/Meridiano.Api/Modules/Fornecedores/{FornecedoresEndpoints.cs,FornecedorDtos.cs,FornecedoresService.cs}`
- Create: `backend/src/Meridiano.Api/Modules/Agencia/{AgenciaEndpoints.cs,AgenciaService.cs}`
- Modify: `backend/src/Meridiano.Api/Modules/Admin/AdminEndpoints.cs` (+ `GET /usuarios/vendedores` fora do grupo com `UsuarioGerenciar`), `backend/src/Meridiano.Api/Modules/Admin/UsuarioDtos.cs` (+ `VendedorDto`), `backend/src/Meridiano.Api/Modules/Admin/UsuarioService.cs` (+ `ListarVendedoresAsync`)
- Modify: `backend/src/Meridiano.Api/Modules/Endpoints.cs` (registrar serviços e mapas)
- Create: `backend/tests/Meridiano.Api.Tests/PessoasTests.cs`, `FornecedoresTests.cs`, `ApoioTests.cs`

**Depends-on:** T1 (fixture)

**Interfaces:**
- Produces:
```csharp
// Pessoas
public sealed record ClienteBuscaDto(Guid Id, string Nome, string? Telefone, string? Cpf);            // Cpf null (omitido) sem ClienteVerDocumento
public sealed record NovoClienteRequest(string Nome, string? Telefone, string? Email, string? Cpf);
Task<IReadOnlyList<ClienteBuscaDto>> PessoasService.BuscarAsync(ContextoSessao ctx, string q, bool verDocumento, CancellationToken ct);   // q < 2 chars → 422 busca_curta; ilike '%q%' em nome, limit 10, order nome
Task<ClienteBuscaDto> PessoasService.CriarAsync(ContextoSessao ctx, NovoClienteRequest req, bool verDocumento, CancellationToken ct);  // nome obrigatório; cpf só dígitos (11) ou 422 cpf_invalido; 23505 do índice ux_cliente_cpf → 409 duplicado (fallback do TratadorDeExcecoes)
// Fornecedores
public sealed record RegraVigenteDto(int DiaInicial, int DiaFinal, int DiaPagamento, int MesesAFrente);
public sealed record FornecedorDto(Guid Id, string Nome, string Tipo, decimal? PercentualComissaoPadrao, int? PrazoComissaoDias, bool Ativo);
public sealed record NovoFornecedorRequest(string Nome, string Tipo);
Task<IReadOnlyList<FornecedorDto>> FornecedoresService.ListarAsync(ContextoSessao ctx, bool? ativo, CancellationToken ct);  // order nome
Task<FornecedorDto> FornecedoresService.CriarAsync(ContextoSessao ctx, NovoFornecedorRequest req, CancellationToken ct);   // tipo ∈ check do banco senão 422 tipo_invalido
// Admin
public sealed record VendedorDto(Guid Id, string Nome, string Perfil, bool GeraRepasse, decimal PercentualPadrao);
Task<IReadOnlyList<VendedorDto>> UsuarioService.ListarVendedoresAsync(ContextoSessao ctx, CancellationToken ct);           // ativo, order nome
// Agencia
public sealed record AgenciaDto(string Nome, decimal TaxaServicoPadrao);
Task<AgenciaDto> AgenciaService.ObterAsync(ContextoSessao ctx, CancellationToken ct);  // config->>'taxa_servico_padrao' coalesce 0
```
  - Rotas: `GET /clientes/busca?q=` (RequireAuthorization; `verDocumento = usuario.Pode(ClienteVerDocumento)`), `POST /clientes` (`ClienteEditar`) → 201 `Location /api/v1/clientes/{id}`; `GET /fornecedores?ativo=` (RequireAuthorization), `POST /fornecedores` (`FornecedorEditar`) → 201; `GET /usuarios/vendedores` (RequireAuthorization — **não** dentro do grupo `UsuarioGerenciar`); `GET /agencia` (RequireAuthorization).
  - `Endpoints.AddModules` registra `PessoasService`, `FornecedoresService`, `AgenciaService`; `MapEndpoints` chama `MapPessoasEndpoints()`, `MapFornecedoresEndpoints()`, `MapAgenciaEndpoints()`.

- [ ] **Step 1: Testes** (padrão `UsuariosTests`: login real, DTO local)

`PessoasTests.cs`:
```csharp
[Collection("db")]
public sealed class PessoasTests(PostgresFixture pg)
{
    private sealed record Cliente(Guid Id, string Nome, string? Telefone, string? Cpf);
    private static async Task<HttpClient> LogadoAsync(MeridianoApiFactory app, string email) { var c = app.CreateClient(); await c.PostAsJsonAsync("/api/v1/auth/login", new { email, senha = "s" }); return c; }

    [Fact]
    public async Task Busca_por_nome_so_na_propria_agencia_e_minimo_2_chars()
    {
        var a = await pg.InserirAgenciaAsync("Pes A"); var b = await pg.InserirAgenciaAsync("Pes B");
        await pg.InserirUsuarioAsync(a, "ag@pesa.com", SenhaHasher.Hash("s"), "agente");
        await pg.InserirClienteAsync(a, "Carlos Mendes"); await pg.InserirClienteAsync(a, "Lúcia Mendes"); await pg.InserirClienteAsync(b, "Carlos Outro");
        await using var app = new MeridianoApiFactory(pg); var c = await LogadoAsync(app, "ag@pesa.com");
        var lista = await c.GetFromJsonAsync<Cliente[]>("/api/v1/clientes/busca?q=mendes");
        Assert.Equal(["Carlos Mendes", "Lúcia Mendes"], lista!.Select(x => x.Nome));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await c.GetAsync("/api/v1/clientes/busca?q=m")).StatusCode);
    }

    [Fact]
    public async Task Cpf_so_aparece_com_permissao_de_documento()
    {
        var a = await pg.InserirAgenciaAsync("Pes C");
        await pg.InserirUsuarioAsync(a, "fin@pesc.com", SenhaHasher.Hash("s"), "financeiro");
        await pg.InserirUsuarioAsync(a, "ag@pesc.com", SenhaHasher.Hash("s"), "agente");
        await pg.QueryOwnerAsync<int>("insert into cliente (agencia_id, nome, cpf) values (@a, 'Com CPF', '12345678901') returning 1", new { a });
        await using var app = new MeridianoApiFactory(pg);
        var fin = await (await LogadoAsync(app, "fin@pesc.com")).GetStringAsync("/api/v1/clientes/busca?q=com");
        Assert.DoesNotContain("cpf", fin, StringComparison.OrdinalIgnoreCase);
        var ag = await (await LogadoAsync(app, "ag@pesc.com")).GetFromJsonAsync<Cliente[]>("/api/v1/clientes/busca?q=com");
        Assert.Equal("12345678901", ag!.Single().Cpf);
    }

    [Fact]
    public async Task Cria_pessoa_inline_e_rejeita_cpf_invalido()
    {
        var a = await pg.InserirAgenciaAsync("Pes D");
        await pg.InserirUsuarioAsync(a, "ag@pesd.com", SenhaHasher.Hash("s"), "agente");
        await using var app = new MeridianoApiFactory(pg); var c = await LogadoAsync(app, "ag@pesd.com");
        var r = await c.PostAsJsonAsync("/api/v1/clientes", new { nome = "Nova Pessoa", telefone = "11999" });
        Assert.Equal(HttpStatusCode.Created, r.StatusCode);
        Assert.Equal("Nova Pessoa", (await r.Content.ReadFromJsonAsync<Cliente>())!.Nome);
        var ruim = await c.PostAsJsonAsync("/api/v1/clientes", new { nome = "X", cpf = "123" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, ruim.StatusCode);
    }
}
```

`FornecedoresTests.cs`:
```csharp
[Collection("db")]
public sealed class FornecedoresTests(PostgresFixture pg)
{
    private sealed record Forn(Guid Id, string Nome, string Tipo, decimal? PercentualComissaoPadrao, int? PrazoComissaoDias, bool Ativo);
    private static async Task<HttpClient> LogadoAsync(MeridianoApiFactory app, string email) { var c = app.CreateClient(); await c.PostAsJsonAsync("/api/v1/auth/login", new { email, senha = "s" }); return c; }

    [Fact]
    public async Task Lista_ativos_com_percentual_e_cria_inline()
    {
        var a = await pg.InserirAgenciaAsync("For A");
        await pg.InserirUsuarioAsync(a, "ag@fora.com", SenhaHasher.Hash("s"), "agente");
        var cvc = await pg.InserirFornecedorAsync(a, "CVC", 10m, null);
        var inativo = await pg.InserirFornecedorAsync(a, "Antigo");
        await pg.QueryOwnerAsync<int>("update fornecedor set ativo = false where id = @inativo returning 1", new { inativo });
        await using var app = new MeridianoApiFactory(pg); var c = await LogadoAsync(app, "ag@fora.com");
        var lista = await c.GetFromJsonAsync<Forn[]>("/api/v1/fornecedores?ativo=true");
        var f = Assert.Single(lista!); Assert.Equal(cvc, f.Id); Assert.Equal(10m, f.PercentualComissaoPadrao);
        var r = await c.PostAsJsonAsync("/api/v1/fornecedores", new { nome = "Decolar", tipo = "operadora" });
        Assert.Equal(HttpStatusCode.Created, r.StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await c.PostAsJsonAsync("/api/v1/fornecedores", new { nome = "X", tipo = "banca" })).StatusCode);
    }

    [Fact]
    public async Task Contador_nao_cria_fornecedor()
    {
        var a = await pg.InserirAgenciaAsync("For B");
        await pg.InserirUsuarioAsync(a, "ct@forb.com", SenhaHasher.Hash("s"), "contador");
        await using var app = new MeridianoApiFactory(pg); var c = await LogadoAsync(app, "ct@forb.com");
        Assert.Equal(HttpStatusCode.Forbidden, (await c.PostAsJsonAsync("/api/v1/fornecedores", new { nome = "X", tipo = "operadora" })).StatusCode);
    }
}
```

`ApoioTests.cs`:
```csharp
[Collection("db")]
public sealed class ApoioTests(PostgresFixture pg)
{
    private sealed record Vendedor(Guid Id, string Nome, string Perfil, bool GeraRepasse, decimal PercentualPadrao);
    private sealed record Agencia(string Nome, decimal TaxaServicoPadrao);
    private static async Task<HttpClient> LogadoAsync(MeridianoApiFactory app, string email) { var c = app.CreateClient(); await c.PostAsJsonAsync("/api/v1/auth/login", new { email, senha = "s" }); return c; }

    [Fact]
    public async Task Agente_lista_vendedores_ativos_sem_usuario_gerenciar()
    {
        var a = await pg.InserirAgenciaAsync("Apo A");
        await pg.InserirUsuarioAsync(a, "ag@apoa.com", SenhaHasher.Hash("s"), "agente");
        var ext = await pg.InserirUsuarioAsync(a, "ana@apoa.com", null, "vendedor_externo", geraRepasse: true);
        await pg.DefinirPercentualPadraoAsync(ext, 12.5m);
        var inativo = await pg.InserirUsuarioAsync(a, "old@apoa.com", null, "agente");
        await pg.QueryOwnerAsync<int>("update usuario set ativo = false where id = @inativo returning 1", new { inativo });
        await using var app = new MeridianoApiFactory(pg); var c = await LogadoAsync(app, "ag@apoa.com");
        var lista = await c.GetFromJsonAsync<Vendedor[]>("/api/v1/usuarios/vendedores");
        Assert.Equal(["ag@apoa.com", "ana@apoa.com"], lista!.Select(v => v.Nome).Order());
        Assert.Equal(12.5m, lista.Single(v => v.Id == ext).PercentualPadrao);
        Assert.Equal(HttpStatusCode.Forbidden, (await c.GetAsync("/api/v1/usuarios")).StatusCode); // grupo admin continua protegido
    }

    [Fact]
    public async Task Agencia_devolve_taxa_de_servico_padrao()
    {
        var a = await pg.InserirAgenciaAsync("Apo B");
        await pg.InserirUsuarioAsync(a, "ag@apob.com", SenhaHasher.Hash("s"), "agente");
        await pg.QueryOwnerAsync<int>("update agencia set config = config || '{\"taxa_servico_padrao\": 50}' where id = @a returning 1", new { a });
        await using var app = new MeridianoApiFactory(pg); var c = await LogadoAsync(app, "ag@apob.com");
        var ag = await c.GetFromJsonAsync<Agencia>("/api/v1/agencia");
        Assert.Equal(50m, ag!.TaxaServicoPadrao); Assert.Equal("Apo B", ag.Nome);
    }
}
```

- [ ] **Step 2: Rodar para ver falhar** — `dotnet test --filter "FullyQualifiedName~PessoasTests|FullyQualifiedName~FornecedoresTests|FullyQualifiedName~ApoioTests"` → 404s.

- [ ] **Step 3: Implementar**

`Modules/Pessoas/PessoasService.cs`:
```csharp
using Dapper;
using Meridiano.Data.Sessao;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Modules.Pessoas;

public sealed class PessoasService(DbSessaoFactory sessoes)
{
    public async Task<IReadOnlyList<ClienteBuscaDto>> BuscarAsync(ContextoSessao ctx, string q, bool verDocumento, CancellationToken ct)
    {
        q = q.Trim();
        if (q.Length < 2) throw new RegraDeNegocioException("busca_curta", "Digite ao menos 2 letras");
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        var cpf = verDocumento ? "cpf" : "null::text as cpf";
        var lista = await s.Conexao.QueryAsync<ClienteBuscaDto>(new CommandDefinition(
            $"select id, nome, telefone, {cpf} from cliente where agencia_id = @agencia and excluido_em is null and nome ilike @padrao order by nome limit 10",
            new { agencia = ctx.AgenciaId, padrao = $"%{q}%" }, s.Transacao, cancellationToken: ct));
        return lista.ToList();
    }

    public async Task<ClienteBuscaDto> CriarAsync(ContextoSessao ctx, NovoClienteRequest req, bool verDocumento, CancellationToken ct)
    {
        var nome = req.Nome?.Trim() ?? "";
        if (nome.Length == 0) throw new RegraDeNegocioException("nome_obrigatorio", "Informe o nome");
        var cpf = string.IsNullOrWhiteSpace(req.Cpf) ? null : new string(req.Cpf.Where(char.IsDigit).ToArray());
        if (cpf is not null && cpf.Length != 11) throw new RegraDeNegocioException("cpf_invalido", "CPF precisa de 11 dígitos");
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        var id = await s.Conexao.ExecuteScalarAsync<Guid>(new CommandDefinition(
            "insert into cliente (agencia_id, nome, telefone, email, cpf, criado_por) values (@agencia, @nome, @telefone, @email, @cpf, @usuario) returning id",
            new { agencia = ctx.AgenciaId, nome, telefone = req.Telefone?.Trim(), email = req.Email?.Trim(), cpf, usuario = ctx.UsuarioId }, s.Transacao, cancellationToken: ct));
        await s.ConfirmarAsync(ct);
        return new ClienteBuscaDto(id, nome, req.Telefone?.Trim(), verDocumento ? cpf : null);
    }
}
```
`PessoaDtos.cs`: os dois records acima, `ClienteBuscaDto.Cpf` com `[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]` (`using System.Text.Json.Serialization;`).

`PessoasEndpoints.cs`:
```csharp
public static IEndpointRouteBuilder MapPessoasEndpoints(this IEndpointRouteBuilder app)
{
    var g = app.MapGroup("/clientes");
    g.MapGet("/busca", async (string? q, HttpContext http, PessoasService pessoas, CancellationToken ct) =>
        Results.Ok(await pessoas.BuscarAsync(http.Contexto(), q ?? "", http.UsuarioAtual().Pode(Permissao.ClienteVerDocumento), ct)))
     .RequireAuthorization();
    g.MapPost("/", async (NovoClienteRequest req, HttpContext http, PessoasService pessoas, CancellationToken ct) =>
    {
        var dto = await pessoas.CriarAsync(http.Contexto(), req, http.UsuarioAtual().Pode(Permissao.ClienteVerDocumento), ct);
        return Results.Created($"/api/v1/clientes/{dto.Id}", dto);
    }).RequerPermissao(Permissao.ClienteEditar);
    return app;
}
```

`Modules/Fornecedores/FornecedoresService.cs`:
```csharp
public sealed class FornecedoresService(DbSessaoFactory sessoes)
{
    private static readonly HashSet<string> Tipos = ["operadora", "consolidadora", "cia_aerea", "hotel", "seguradora", "receptivo", "despachante", "outro"];
    private const string Colunas = "id, nome, tipo, percentual_comissao_padrao as PercentualComissaoPadrao, prazo_comissao_dias as PrazoComissaoDias, ativo";

    public async Task<IReadOnlyList<FornecedorDto>> ListarAsync(ContextoSessao ctx, bool? ativo, CancellationToken ct)
    {
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        var lista = await s.Conexao.QueryAsync<FornecedorDto>(new CommandDefinition(
            $"select {Colunas} from fornecedor where agencia_id = @agencia and (@ativo::boolean is null or ativo = @ativo) order by nome",
            new { agencia = ctx.AgenciaId, ativo }, s.Transacao, cancellationToken: ct));
        return lista.ToList();
    }

    public async Task<FornecedorDto> CriarAsync(ContextoSessao ctx, NovoFornecedorRequest req, CancellationToken ct)
    {
        var nome = req.Nome?.Trim() ?? "";
        if (nome.Length == 0) throw new RegraDeNegocioException("nome_obrigatorio", "Informe o nome");
        if (!Tipos.Contains(req.Tipo)) throw new RegraDeNegocioException("tipo_invalido", "Tipo de fornecedor inválido");
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        var dto = await s.Conexao.QuerySingleAsync<FornecedorDto>(new CommandDefinition(
            $"insert into fornecedor (agencia_id, nome, tipo) values (@agencia, @nome, @tipo) returning {Colunas}",
            new { agencia = ctx.AgenciaId, nome, tipo = req.Tipo }, s.Transacao, cancellationToken: ct));
        await s.ConfirmarAsync(ct);
        return dto;
    }
}
```
Endpoints: grupo `/fornecedores`; `GET /` `RequireAuthorization()`; `POST /` `.RequerPermissao(Permissao.FornecedorEditar)` → `Results.Created($"/api/v1/fornecedores/{dto.Id}", dto)`.

`Modules/Agencia/AgenciaService.cs`:
```csharp
public sealed record AgenciaDto(string Nome, decimal TaxaServicoPadrao);
public sealed class AgenciaService(DbSessaoFactory sessoes)
{
    public async Task<AgenciaDto> ObterAsync(ContextoSessao ctx, CancellationToken ct)
    {
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        return await s.Conexao.QuerySingleAsync<AgenciaDto>(new CommandDefinition(
            "select nome, coalesce((config->>'taxa_servico_padrao')::numeric, 0) as TaxaServicoPadrao from agencia where id = @agencia",
            new { agencia = ctx.AgenciaId }, s.Transacao, cancellationToken: ct));
    }
}
```
`AgenciaEndpoints.cs`: `app.MapGet("/agencia", …).RequireAuthorization()`.

`AdminEndpoints.cs` — antes do grupo protegido:
```csharp
app.MapGet("/usuarios/vendedores", async (HttpContext http, UsuarioService usuarios, CancellationToken ct) =>
    Results.Ok(await usuarios.ListarVendedoresAsync(http.Contexto(), ct))).RequireAuthorization();
```
`UsuarioService.ListarVendedoresAsync`: `select id, nome, perfil, gera_repasse as GeraRepasse, percentual_padrao as PercentualPadrao from usuario where agencia_id = @agencia and ativo order by nome`. Atenção: `MapGet("/usuarios/vendedores")` deve ser registrado **antes** de `g.MapPut("/{id:guid}")` do grupo — rotas distintas (`vendedores` não é guid), sem conflito.

`Endpoints.cs`:
```csharp
builder.Services.AddScoped<UsuarioService>();
builder.Services.AddScoped<Pessoas.PessoasService>();
builder.Services.AddScoped<Fornecedores.FornecedoresService>();
builder.Services.AddScoped<Agencia.AgenciaService>();
…
api.MapAdminEndpoints();
api.MapPessoasEndpoints();
api.MapFornecedoresEndpoints();
api.MapAgenciaEndpoints();
```

- [ ] **Step 4: Rodar** — `dotnet build -c Release && dotnet test && dotnet format --verify-no-changes` → 0 falhas.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(modules): pessoas busca/inline, fornecedores list/inline, vendedores and agencia lookups`

---

### Task 3 (backend): `Modules/Viagens` — criar e ler a viagem (agregado completo)

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Viagens/{ViagensEndpoints.cs,ViagemDtos.cs,ViagensService.cs,ViagemLeitura.cs,ReservaGravacao.cs,Rotinas.cs}`
- Modify: `backend/src/Meridiano.Api/Modules/Endpoints.cs`
- Create: `backend/tests/Meridiano.Api.Tests/ViagensCriarTests.cs`

**Depends-on:** T1

**Interfaces:**
- Consumes: `Guardas.*`, `CalculoReserva`, `PrevisaoComissao.Calcular(DateOnly, IReadOnlyList<JanelaPagamento>, int?)`, fixture de T1.
- Produces:
  - DTOs do "Contrato de API" (arquivo `ViagemDtos.cs`; campos opcionais com `[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]`).
  - `ViagensService.CriarAsync(ContextoSessao ctx, UsuarioAtual usuario, ViagemRequest req, CancellationToken ct) → Task<ViagemDto>`
  - `ViagensService.ObterAsync(ContextoSessao ctx, UsuarioAtual usuario, Guid id, CancellationToken ct) → Task<ViagemDto>` — 422 `nao_encontrado` se não existe, não é da agência, ou (`ViagemVerProprias` sem `ViagemVer`) `vendedor_id ≠ usuario`.
  - `ViagemLeitura.CarregarAsync(DbSessao s, Guid agenciaId, Guid viagemId, Projecao p, CancellationToken ct) → Task<ViagemDto?>` com `record Projecao(bool VerValores, bool VerResultado)` — usado por T4.
  - `ReservaGravacao.ValidarAsync(DbSessao s, Guid agenciaId, ReservaRequest r, CancellationToken ct)` e `ReservaGravacao.InserirAsync(DbSessao s, ContextoSessao ctx, Guid viagemId, ReservaRequest r, CancellationToken ct) → Task<Guid>` (calcula e grava `data_prevista_comissao` pela regra vigente em `data_compra`), `ReservaGravacao.PrevisaoAsync(DbSessao s, Guid agenciaId, Guid fornecedorId, DateOnly dataCompra, CancellationToken ct) → Task<DateOnly?>`.
  - `Rotinas.ReavaliarRepasseAsync(DbSessao s, Guid agenciaId, Guid viagemId, CancellationToken ct)` — não mexe em `pago`; `a_pagar` se existe ≥ 1 reserva ativa e nenhuma com `aguardando_operadora` (via `vw_reserva_financeiro`); senão `bloqueado`; grava `liberado_em = now()` na transição para `a_pagar`.
  - `Rotinas.GerarPendenciasAsync(DbSessao s, Guid agenciaId, Guid viagemId, DateOnly? ida, DateOnly? volta, Guid? responsavelId, CancellationToken ct)` — upsert por `chave_unica` (`{viagemId}:checkin` ida−3, `{viagemId}:posviagem` volta+3, `{viagemId}:recompra` volta+330); títulos `Check-in`, `Pós-viagem`, `Recompra`; `origem = 'automatica'`; se já existe: atualiza `data_prevista` e, se `status = 'concluida'` e a data mudou, volta a `aberta` (`concluida_em = null`); sem ida → nenhuma `checkin`; sem volta → nenhuma `posviagem`/`recompra`.
  - Rota `POST /viagens` (`ViagemCriar`) → 201 + `Location`; `GET /viagens/{id:guid}` (`RequireAuthorization()`; serviço decide por `ViagemVer`/`ViagemVerProprias`; sem nenhuma das duas → 403 `sem_permissao` via `Results.Problem` como em `Autorizacao.cs`).

- [ ] **Step 1: Testes** (`ViagensCriarTests.cs`)

```csharp
using System.Net; using System.Net.Http.Json;
using Meridiano.Api.Auth; using Meridiano.Api.Tests.Fixtures;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class ViagensCriarTests(PostgresFixture pg)
{
    private sealed record Passageiro(Guid ClienteId, string Nome, bool Titular);
    private sealed record Reserva(Guid Id, string Versao, Guid FornecedorId, string Status, string[] TiposServico, DateOnly? DataPrevistaComissao,
        decimal? ValorTotal, decimal? ValorComissao, decimal? RavCliente, decimal? ValorEsperadoOperadora, decimal? ReceitaPrevista, decimal? PercentualComissao);
    private sealed record Repasse(Guid Id, decimal? Valor, string Status);
    private sealed record Resumo(decimal VendaTotal, decimal CustoFornecedores, decimal ReceitaPrevista, decimal? RepasseValor, decimal DespesasViagem, decimal Resultado);
    private sealed record Viagem(Guid Id, string Codigo, string Versao, string Destino, string Tipo, DateOnly? DataIda, DateOnly? DataVolta, Guid VendedorId,
        string FaseOperacional, string FaseFinanceira, Passageiro[] Passageiros, Reserva[] Reservas, Repasse? Repasse, Resumo? Resumo);

    private sealed record Cenario(Guid Agencia, Guid Agente, Guid Externa, Guid Carlos, Guid Lucia, Guid Cvc, Guid Decolar);

    private async Task<Cenario> CenarioAsync(string nome)
    {
        var a = await pg.InserirAgenciaAsync(nome);
        var agente = await pg.InserirUsuarioAsync(a, $"ag@{nome}.com", SenhaHasher.Hash("s"), "agente");
        var externa = await pg.InserirUsuarioAsync(a, $"ana@{nome}.com", null, "vendedor_externo", geraRepasse: true);
        var carlos = await pg.InserirClienteAsync(a, "Carlos Mendes");
        var lucia = await pg.InserirClienteAsync(a, "Lúcia Mendes");
        var cvc = await pg.InserirFornecedorAsync(a, "CVC", 10m, null);
        await pg.InserirRegraPagamentoAsync(a, cvc, 1, 14, 20, 0);
        await pg.InserirRegraPagamentoAsync(a, cvc, 15, 31, 5, 1);
        var decolar = await pg.InserirFornecedorAsync(a, "Decolar", null, 45);
        return new Cenario(a, agente, externa, carlos, lucia, cvc, decolar);
    }

    private static async Task<HttpClient> LogadoAsync(MeridianoApiFactory app, string email) { var c = app.CreateClient(); await c.PostAsJsonAsync("/api/v1/auth/login", new { email, senha = "s" }); return c; }

    private static object Reserva1(Guid fornecedor, string data = "2026-03-14", string? localizador = "K7X2PQ") => new
    {
        fornecedorId = fornecedor, localizador, dataCompra = data, status = "emitida", tiposServico = new[] { "aereo", "hospedagem" },
        valorTotal = 10000m, valorTaxas = 500m, valorComissao = 1000m, ravOperadora = 100m, valorCliente = 10500m, taxaServico = 0m,
        ravClienteModo = "via_operadora", fluxoPagamento = "cliente_paga_operadora", formasPagamento = new[] { "pix" }, nfseStatus = "nao_precisa",
    };

    private static object Pedido(Cenario c, Guid vendedor, decimal? repasseValor, params object[] reservas) => new
    {
        destino = "Lisboa", tipo = "internacional", dataIda = "2026-04-18", dataVolta = "2026-04-28", vendedorId = vendedor, agenteId = c.Agente,
        passageiros = new[] { new { clienteId = c.Carlos, titular = true }, new { clienteId = c.Lucia, titular = false } },
        repasseValor, reservas,
    };

    [Fact]
    public async Task Cria_viagem_completa_numa_transacao_com_repasse_e_pendencias()
    {
        var c = await CenarioAsync("vg-a");
        await using var app = new MeridianoApiFactory(pg); var http = await LogadoAsync(app, "ag@vg-a.com");

        var r = await http.PostAsJsonAsync("/api/v1/viagens", Pedido(c, c.Externa, 300m, Reserva1(c.Cvc), Reserva1(c.Decolar, "2026-03-20", "DCL-1")));
        Assert.Equal(HttpStatusCode.Created, r.StatusCode);
        var v = (await r.Content.ReadFromJsonAsync<Viagem>())!;

        Assert.Matches(@"^VG-\d{4}-\d{4}$", v.Codigo);
        Assert.Equal(2, v.Passageiros.Length); Assert.Single(v.Passageiros, p => p.Titular && p.ClienteId == c.Carlos);
        Assert.Equal(2, v.Reservas.Length);
        var cvc = v.Reservas.Single(x => x.FornecedorId == c.Cvc);
        Assert.Equal((500m, 1600m, 1600m, 10.00m), (cvc.RavCliente, cvc.ValorEsperadoOperadora, cvc.ReceitaPrevista, cvc.PercentualComissao)); // §13 B
        Assert.Equal(new DateOnly(2026, 3, 20), cvc.DataPrevistaComissao);                 // janela 1–14 → dia 20 do mesmo mês
        Assert.Equal(new DateOnly(2026, 5, 4), v.Reservas.Single(x => x.FornecedorId == c.Decolar).DataPrevistaComissao); // sem janela: 45 dias
        Assert.Equal("em_emissao", v.FaseOperacional == "confirmada" ? "em_emissao" : v.FaseOperacional == "em_emissao" ? "em_emissao" : v.FaseOperacional); // status emitida → confirmada
        Assert.Equal("confirmada", v.FaseOperacional); Assert.Equal("a_receber", v.FaseFinanceira);
        Assert.NotNull(v.Repasse); Assert.Equal((300m, "bloqueado"), (v.Repasse!.Valor, v.Repasse.Status));
        Assert.Equal(3200m, v.Resumo!.ReceitaPrevista); Assert.Equal(2900m, v.Resumo.Resultado);       // 3200 − 300 − 0

        var pend = await pg.QueryOwnerAsync<(string Chave, DateTime Data, Guid? Resp)>("select chave_unica, data_prevista, responsavel_id from pendencia where viagem_id = @id order by data_prevista", new { id = v.Id });
        Assert.Equal([$"{v.Id}:checkin", $"{v.Id}:posviagem", $"{v.Id}:recompra"], pend.Select(p => p.Chave));
        Assert.Equal(new DateTime(2026, 4, 15), pend.First().Data); Assert.All(pend, p => Assert.Equal(c.Agente, p.Resp));
    }

    [Fact]
    public async Task Rascunho_sem_reserva_e_valido_e_sem_repasse_para_agente()
    {
        var c = await CenarioAsync("vg-b");
        await using var app = new MeridianoApiFactory(pg); var http = await LogadoAsync(app, "ag@vg-b.com");
        var r = await http.PostAsJsonAsync("/api/v1/viagens", Pedido(c, c.Agente, null));
        Assert.Equal(HttpStatusCode.Created, r.StatusCode);
        var v = (await r.Content.ReadFromJsonAsync<Viagem>())!;
        Assert.Empty(v.Reservas); Assert.Equal("sem_reserva", v.FaseOperacional); Assert.Equal("nao_prevista", v.FaseFinanceira); Assert.Null(v.Repasse);
    }

    [Theory]
    [InlineData("sem_titular", "titular_obrigatorio")]
    [InlineData("dois_titulares", "titular_duplicado")]
    [InlineData("sem_passageiro", "sem_passageiro")]
    [InlineData("volta_antes_da_ida", "datas_incoerentes")]
    [InlineData("servico_invalido", "tipos_servico_invalido")]
    [InlineData("valor_negativo", "valor_negativo")]
    [InlineData("repasse_para_agente", "repasse_sem_vendedor")]
    public async Task Rejeita_payload_invalido_sem_gravar_nada(string caso, string codigo)
    {
        var c = await CenarioAsync($"vg-{caso}");
        await using var app = new MeridianoApiFactory(pg); var http = await LogadoAsync(app, $"ag@vg-{caso}.com");
        object pedido = caso switch
        {
            "sem_titular" => new { destino = "X", tipo = "nacional", vendedorId = c.Agente, passageiros = new[] { new { clienteId = c.Carlos, titular = false } }, reservas = Array.Empty<object>() },
            "dois_titulares" => new { destino = "X", tipo = "nacional", vendedorId = c.Agente, passageiros = new[] { new { clienteId = c.Carlos, titular = true }, new { clienteId = c.Lucia, titular = true } }, reservas = Array.Empty<object>() },
            "sem_passageiro" => new { destino = "X", tipo = "nacional", vendedorId = c.Agente, passageiros = Array.Empty<object>(), reservas = Array.Empty<object>() },
            "volta_antes_da_ida" => new { destino = "X", tipo = "nacional", dataIda = "2026-05-10", dataVolta = "2026-05-01", vendedorId = c.Agente, passageiros = new[] { new { clienteId = c.Carlos, titular = true } }, reservas = Array.Empty<object>() },
            "servico_invalido" => Pedido(c, c.Agente, null, new { fornecedorId = c.Cvc, dataCompra = "2026-03-01", status = "emitida", tiposServico = new[] { "jato" }, valorTotal = 1m, valorTaxas = 0m, valorComissao = 0m, ravOperadora = 0m, valorCliente = 1m, taxaServico = 0m, ravClienteModo = "retido_agencia", fluxoPagamento = "cliente_paga_operadora", formasPagamento = Array.Empty<string>(), nfseStatus = "nao_precisa" }),
            "valor_negativo" => Pedido(c, c.Agente, null, new { fornecedorId = c.Cvc, dataCompra = "2026-03-01", status = "emitida", tiposServico = new[] { "aereo" }, valorTotal = -1m, valorTaxas = 0m, valorComissao = 0m, ravOperadora = 0m, valorCliente = 1m, taxaServico = 0m, ravClienteModo = "retido_agencia", fluxoPagamento = "cliente_paga_operadora", formasPagamento = Array.Empty<string>(), nfseStatus = "nao_precisa" }),
            _ => Pedido(c, c.Agente, 100m),
        };
        var r = await http.PostAsJsonAsync("/api/v1/viagens", pedido);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, r.StatusCode);
        Assert.Equal(codigo, (await r.Content.ReadFromJsonAsync<Dictionary<string, object>>())!["codigo"].ToString());
        Assert.Equal(0, (await pg.QueryOwnerAsync<long>("select count(*) from viagem where agencia_id = @a", new { a = c.Agencia })).Single());
    }

    [Fact]
    public async Task Referencias_de_outra_agencia_ou_inativas_sao_rejeitadas()
    {
        var c = await CenarioAsync("vg-c"); var outra = await CenarioAsync("vg-c2");
        await using var app = new MeridianoApiFactory(pg); var http = await LogadoAsync(app, "ag@vg-c.com");
        var r1 = await http.PostAsJsonAsync("/api/v1/viagens", Pedido(c, c.Agente, null, Reserva1(outra.Cvc)));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, r1.StatusCode);
        await pg.QueryOwnerAsync<int>("update fornecedor set ativo = false where id = @f returning 1", new { f = c.Decolar });
        var r2 = await http.PostAsJsonAsync("/api/v1/viagens", Pedido(c, c.Agente, null, Reserva1(c.Decolar)));
        Assert.Equal("fornecedor_inativo", (await r2.Content.ReadFromJsonAsync<Dictionary<string, object>>())!["codigo"].ToString());
    }

    [Fact]
    public async Task Vendedor_externo_ve_so_a_propria_viagem_e_sem_valores()
    {
        var c = await CenarioAsync("vg-d");
        await pg.QueryOwnerAsync<int>("update usuario set senha_hash = @h where id = @id returning 1", new { h = SenhaHasher.Hash("s"), id = c.Externa });
        await using var app = new MeridianoApiFactory(pg); var agente = await LogadoAsync(app, "ag@vg-d.com");
        var propria = (await (await agente.PostAsJsonAsync("/api/v1/viagens", Pedido(c, c.Externa, 300m, Reserva1(c.Cvc)))).Content.ReadFromJsonAsync<Viagem>())!;
        var alheia = (await (await agente.PostAsJsonAsync("/api/v1/viagens", Pedido(c, c.Agente, null, Reserva1(c.Cvc)))).Content.ReadFromJsonAsync<Viagem>())!;

        var ext = await LogadoAsync(app, "ana@vg-d.com");
        var json = await ext.GetStringAsync($"/api/v1/viagens/{propria.Id}");
        Assert.DoesNotContain("valorTotal", json); Assert.DoesNotContain("resumo", json); Assert.DoesNotContain("repasse", json);
        Assert.Contains("\"localizador\":\"K7X2PQ\"", json);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await ext.GetAsync($"/api/v1/viagens/{alheia.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await ext.PostAsJsonAsync("/api/v1/viagens", Pedido(c, c.Externa, null))).StatusCode);
    }

    [Fact]
    public async Task Generated_columns_batem_com_CalculoReserva_nos_exemplos_da_spec()
    {
        var c = await CenarioAsync("vg-e");
        await using var app = new MeridianoApiFactory(pg); var http = await LogadoAsync(app, "ag@vg-e.com");
        object R(decimal total, decimal com, decimal rav, decimal cli, string modo, decimal taxa = 0) => new { fornecedorId = c.Cvc, dataCompra = "2026-03-01", status = "emitida", tiposServico = new[] { "passeio" }, valorTotal = total, valorTaxas = 0m, valorComissao = com, ravOperadora = rav, valorCliente = cli, taxaServico = taxa, ravClienteModo = modo, fluxoPagamento = "cliente_paga_agencia", formasPagamento = new[] { "pix" }, nfseStatus = "nao_precisa" };
        var v = (await (await http.PostAsJsonAsync("/api/v1/viagens", Pedido(c, c.Agente, null,
            R(10000, 1000, 100, 10000, "retido_agencia"), R(10000, 1000, 100, 10500, "via_operadora"), R(10000, 1000, 100, 10500, "retido_agencia"), R(800, 0, 0, 1000, "retido_agencia")))).Content.ReadFromJsonAsync<Viagem>())!;
        var esperado = new[] { (0m, 1100m, 1100m), (500m, 1600m, 1600m), (500m, 1100m, 1600m), (200m, 0m, 200m) };
        Assert.Equal(esperado, v.Reservas.Select(x => (x.RavCliente!.Value, x.ValorEsperadoOperadora!.Value, x.ReceitaPrevista!.Value)));
    }
}
```

- [ ] **Step 2: Rodar para ver falhar** — `dotnet test --filter FullyQualifiedName~ViagensCriarTests` → 404.

- [ ] **Step 3: `ReservaGravacao.cs`**

```csharp
using Dapper;
using Meridiano.Api.Modules.Comum;
using Meridiano.Data.Sessao;
using Meridiano.Domain.Comum;
using Meridiano.Domain.Financeiro;

namespace Meridiano.Api.Modules.Viagens;

// Validação e INSERT de uma reserva dentro da transação da viagem. UPDATE fica em T4.
public static class ReservaGravacao
{
    public static readonly HashSet<string> TiposServico = ["aereo", "hospedagem", "seguro", "traslado", "passeio", "ingresso", "aluguel_carro", "documentacao", "outro"];
    public static readonly HashSet<string> FormasPagamento = ["pix", "boleto", "cartao"];
    private static readonly HashSet<string> Status = ["pendente", "emitida"];
    private static readonly HashSet<string> RavModo = ["retido_agencia", "via_operadora"];
    private static readonly HashSet<string> Fluxo = ["cliente_paga_operadora", "cliente_paga_agencia"];
    private static readonly HashSet<string> Nfse = ["falta_emitir", "emitido", "nao_precisa"];

    public static async Task ValidarAsync(DbSessao s, Guid agenciaId, ReservaRequest r, CancellationToken ct)
    {
        if (!Status.Contains(r.Status)) throw new RegraDeNegocioException("status_invalido", "Status da reserva inválido");
        if (!RavModo.Contains(r.RavClienteModo) || !Fluxo.Contains(r.FluxoPagamento) || !Nfse.Contains(r.NfseStatus)) throw new RegraDeNegocioException("valor_invalido", "Opção inválida na reserva");
        if (r.TiposServico.Any(t => !TiposServico.Contains(t))) throw new RegraDeNegocioException("tipos_servico_invalido", "Serviço vendido inválido");
        if (r.FormasPagamento.Any(f => !FormasPagamento.Contains(f))) throw new RegraDeNegocioException("formas_pagamento_invalido", "Forma de pagamento inválida");
        if (new[] { r.ValorTotal, r.ValorTaxas, r.ValorComissao, r.RavOperadora, r.ValorCliente, r.TaxaServico }.Any(v => v < 0)) throw new RegraDeNegocioException("valor_negativo", "Valores não podem ser negativos");
        await Guardas.ReferenciaAsync(s, Tabela.Fornecedor, r.FornecedorId, agenciaId, ct, exigirAtivo: true);
    }

    public static async Task<DateOnly?> PrevisaoAsync(DbSessao s, Guid agenciaId, Guid fornecedorId, DateOnly dataCompra, CancellationToken ct)
    {
        // versão vigente = todas as janelas cujo vigente_desde é o maior <= data_compra
        var janelas = (await s.Conexao.QueryAsync<JanelaPagamento>(new CommandDefinition(
            """
            select dia_inicial as DiaInicial, dia_final as DiaFinal, dia_pagamento as DiaPagamento, meses_a_frente as MesesAFrente
              from regra_pagamento_fornecedor
             where agencia_id = @agenciaId and fornecedor_id = @fornecedorId
               and vigente_desde = (select max(vigente_desde) from regra_pagamento_fornecedor where fornecedor_id = @fornecedorId and vigente_desde <= @dataCompra)
             order by dia_inicial
            """, new { agenciaId, fornecedorId, dataCompra }, s.Transacao, cancellationToken: ct))).ToList();
        var prazo = await s.Conexao.ExecuteScalarAsync<int?>(new CommandDefinition("select prazo_comissao_dias from fornecedor where id = @fornecedorId", new { fornecedorId }, s.Transacao, cancellationToken: ct));
        if (janelas.Count == 0 && prazo is null) return dataCompra.AddDays(30); // padrão do domínio
        return PrevisaoComissao.Calcular(dataCompra, janelas, prazo);
    }

    public static async Task<Guid> InserirAsync(DbSessao s, ContextoSessao ctx, Guid viagemId, ReservaRequest r, CancellationToken ct)
    {
        var prevista = await PrevisaoAsync(s, ctx.AgenciaId, r.FornecedorId, r.DataCompra, ct);
        return await s.Conexao.ExecuteScalarAsync<Guid>(new CommandDefinition(
            """
            insert into reserva (agencia_id, viagem_id, fornecedor_id, localizador, data_compra, status, tipos_servico, formas_pagamento,
                                 valor_total, valor_taxas, valor_comissao, rav_operadora, valor_cliente, taxa_servico, rav_cliente_modo, fluxo_pagamento,
                                 nfse_status, observacoes, data_prevista_comissao, criado_por)
            values (@agencia, @viagemId, @FornecedorId, nullif(trim(@Localizador), ''), @DataCompra, @Status, @TiposServico, @FormasPagamento,
                    @ValorTotal, @ValorTaxas, @ValorComissao, @RavOperadora, @ValorCliente, @TaxaServico, @RavClienteModo, @FluxoPagamento,
                    @NfseStatus, @Observacoes, @prevista, @usuario)
            returning id
            """,
            new { agencia = ctx.AgenciaId, viagemId, r.FornecedorId, r.Localizador, r.DataCompra, r.Status, r.TiposServico, r.FormasPagamento, r.ValorTotal, r.ValorTaxas, r.ValorComissao, r.RavOperadora, r.ValorCliente, r.TaxaServico, r.RavClienteModo, r.FluxoPagamento, r.NfseStatus, r.Observacoes, prevista, usuario = ctx.UsuarioId },
            s.Transacao, cancellationToken: ct));
    }
}
```
Npgsql grava `string[]` em `text[]` direto.

- [ ] **Step 4: `Rotinas.cs`**

```csharp
public static class Rotinas
{
    public static async Task ReavaliarRepasseAsync(DbSessao s, Guid agenciaId, Guid viagemId, CancellationToken ct)
    {
        var atual = await s.Conexao.QuerySingleOrDefaultAsync<(Guid Id, string Status)>(new CommandDefinition(
            "select id, status from repasse where viagem_id = @viagemId and agencia_id = @agenciaId and excluido_em is null", new { viagemId, agenciaId }, s.Transacao, cancellationToken: ct));
        if (atual == default || atual.Status == "pago") return;
        var (ativas, aguardando) = await s.Conexao.QuerySingleAsync<(long Ativas, long Aguardando)>(new CommandDefinition(
            "select count(*) filter (where status <> 'cancelada'), count(*) filter (where aguardando_operadora) from vw_reserva_financeiro where viagem_id = @viagemId", new { viagemId }, s.Transacao, cancellationToken: ct));
        var novo = ativas > 0 && aguardando == 0 ? "a_pagar" : "bloqueado";
        if (novo == atual.Status) return;
        await s.Conexao.ExecuteAsync(new CommandDefinition(
            "update repasse set status = @novo, liberado_em = case when @novo = 'a_pagar' then now() else null end where id = @id", new { novo, id = atual.Id }, s.Transacao, cancellationToken: ct));
    }

    public static async Task GerarPendenciasAsync(DbSessao s, Guid agenciaId, Guid viagemId, DateOnly? ida, DateOnly? volta, Guid? responsavelId, CancellationToken ct)
    {
        var itens = new List<(string Chave, string Titulo, DateOnly Data)>();
        if (ida is { } i) itens.Add(($"{viagemId}:checkin", "Check-in", i.AddDays(-3)));
        if (volta is { } v) { itens.Add(($"{viagemId}:posviagem", "Pós-viagem", v.AddDays(3))); itens.Add(($"{viagemId}:recompra", "Recompra", v.AddDays(330))); }
        foreach (var (chave, titulo, data) in itens)
        {
            await s.Conexao.ExecuteAsync(new CommandDefinition(
                """
                insert into pendencia (agencia_id, titulo, data_prevista, responsavel_id, viagem_id, origem, chave_unica)
                values (@agenciaId, @titulo, @data, @responsavelId, @viagemId, 'automatica', @chave)
                on conflict (agencia_id, chave_unica) do update
                   set data_prevista = excluded.data_prevista,
                       responsavel_id = coalesce(excluded.responsavel_id, pendencia.responsavel_id),
                       status = case when pendencia.status = 'concluida' and pendencia.data_prevista <> excluded.data_prevista then 'aberta' else pendencia.status end,
                       concluida_em = case when pendencia.status = 'concluida' and pendencia.data_prevista <> excluded.data_prevista then null else pendencia.concluida_em end
                """, new { agenciaId, titulo, data, responsavelId, viagemId, chave }, s.Transacao, cancellationToken: ct));
        }
    }
}
```

- [ ] **Step 5: `ViagemLeitura.cs`** (uma consulta por bloco; projeção por perfil)

```csharp
public sealed record Projecao(bool VerValores, bool VerResultado);

public static class ViagemLeitura
{
    public static async Task<ViagemDto?> CarregarAsync(DbSessao s, Guid agenciaId, Guid viagemId, Projecao p, CancellationToken ct)
    {
        var v = await s.Conexao.QuerySingleOrDefaultAsync<CabecalhoRow>(new CommandDefinition(
            """
            select v.id, v.codigo, v.xmin::text as Versao, v.destino, v.tipo, v.data_ida as DataIda, v.data_volta as DataVolta, v.vendedor_id as VendedorId, u.nome as VendedorNome,
                   v.agente_id as AgenteId, v.ocasiao, v.observacoes, v.cancelada, f.fase_operacional as FaseOperacional, f.fase_financeira as FaseFinanceira
              from viagem v join usuario u on u.id = v.vendedor_id join vw_fase_viagem f on f.viagem_id = v.id
             where v.id = @viagemId and v.agencia_id = @agenciaId and v.excluido_em is null
            """, new { viagemId, agenciaId }, s.Transacao, cancellationToken: ct));
        if (v is null) return null;

        var passageiros = (await s.Conexao.QueryAsync<PassageiroDto>(new CommandDefinition(
            "select vp.cliente_id as ClienteId, c.nome, vp.titular from viagem_passageiro vp join cliente c on c.id = vp.cliente_id where vp.viagem_id = @viagemId order by vp.titular desc, c.nome", new { viagemId }, s.Transacao, cancellationToken: ct))).ToArray();

        var reservas = (await s.Conexao.QueryAsync<ReservaRow>(new CommandDefinition(
            """
            select r.id, r.xmin::text as Versao, r.fornecedor_id as FornecedorId, f.nome as FornecedorNome, r.localizador, r.data_compra as DataCompra, r.status,
                   r.tipos_servico as TiposServico, r.formas_pagamento as FormasPagamento, r.rav_cliente_modo as RavClienteModo, r.fluxo_pagamento as FluxoPagamento, r.nfse_status as NfseStatus, r.observacoes,
                   r.data_prevista_comissao as DataPrevistaComissao, r.valor_total as ValorTotal, r.valor_taxas as ValorTaxas, r.valor_comissao as ValorComissao, r.rav_operadora as RavOperadora,
                   r.valor_cliente as ValorCliente, r.taxa_servico as TaxaServico, r.rav_cliente as RavCliente, r.valor_esperado_operadora as ValorEsperadoOperadora,
                   r.receita_prevista as ReceitaPrevista, r.percentual_comissao as PercentualComissao
              from reserva r join fornecedor f on f.id = r.fornecedor_id
             where r.viagem_id = @viagemId and r.excluido_em is null order by r.criado_em
            """, new { viagemId }, s.Transacao, cancellationToken: ct))).Select(r => r.ParaDto(p.VerValores)).ToArray();

        RepasseDto? repasse = null; ResumoViagemDto? resumo = null;
        if (p.VerResultado)
        {
            repasse = await s.Conexao.QuerySingleOrDefaultAsync<RepasseDto>(new CommandDefinition(
                "select id, valor, status from repasse where viagem_id = @viagemId and excluido_em is null", new { viagemId }, s.Transacao, cancellationToken: ct));
            resumo = await s.Conexao.QuerySingleAsync<ResumoViagemDto>(new CommandDefinition(
                "select venda_total as VendaTotal, custo_fornecedores as CustoFornecedores, receita_prevista as ReceitaPrevista, repasse_valor as RepasseValor, despesas_viagem as DespesasViagem, resultado_viagem as Resultado from vw_resultado_viagem where viagem_id = @viagemId",
                new { viagemId }, s.Transacao, cancellationToken: ct));
        }
        return new ViagemDto(v.Id, v.Codigo, v.Versao, v.Destino, v.Tipo, v.DataIda, v.DataVolta, v.VendedorId, v.VendedorNome, v.AgenteId, v.Ocasiao, v.Observacoes, v.Cancelada, v.FaseOperacional, v.FaseFinanceira, passageiros, reservas, repasse, resumo);
    }

    private sealed record CabecalhoRow(Guid Id, string Codigo, string Versao, string Destino, string Tipo, DateOnly? DataIda, DateOnly? DataVolta, Guid VendedorId, string VendedorNome, Guid? AgenteId, string? Ocasiao, string? Observacoes, bool Cancelada, string FaseOperacional, string FaseFinanceira);

    private sealed record ReservaRow(Guid Id, string Versao, Guid FornecedorId, string FornecedorNome, string? Localizador, DateOnly DataCompra, string Status, string[] TiposServico, string[] FormasPagamento, string RavClienteModo, string FluxoPagamento, string NfseStatus, string? Observacoes, DateOnly? DataPrevistaComissao, decimal ValorTotal, decimal ValorTaxas, decimal ValorComissao, decimal RavOperadora, decimal ValorCliente, decimal TaxaServico, decimal RavCliente, decimal ValorEsperadoOperadora, decimal ReceitaPrevista, decimal? PercentualComissao)
    {
        public ReservaDto ParaDto(bool verValores) => verValores
            ? new(Id, Versao, FornecedorId, FornecedorNome, Localizador, DataCompra, Status, TiposServico, FormasPagamento, RavClienteModo, FluxoPagamento, NfseStatus, Observacoes, DataPrevistaComissao, ValorTotal, ValorTaxas, ValorComissao, RavOperadora, ValorCliente, TaxaServico, RavCliente, ValorEsperadoOperadora, ReceitaPrevista, PercentualComissao)
            : new(Id, Versao, FornecedorId, FornecedorNome, Localizador, DataCompra, Status, TiposServico, FormasPagamento, RavClienteModo, FluxoPagamento, NfseStatus, Observacoes, DataPrevistaComissao, null, null, null, null, null, null, null, null, null, null);
    }
}
```
Se Dapper não mapear `string[]` em record com construtor posicional, usar classe com propriedades `{ get; init; }` para `ReservaRow` — dizer no relatório.

- [ ] **Step 6: `ViagensService.cs`**

```csharp
public sealed class ViagensService(DbSessaoFactory sessoes)
{
    private static readonly HashSet<string> Tipos = ["nacional", "internacional"];

    public static Projecao ProjecaoDe(UsuarioAtual u) => new(u.Pode(Permissao.ReservaVerValores), u.Pode(Permissao.ViagemVerResultado));

    public async Task<ViagemDto> CriarAsync(ContextoSessao ctx, UsuarioAtual usuario, ViagemRequest req, CancellationToken ct)
    {
        ValidarCabecalho(req);
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        await ValidarReferenciasAsync(s, ctx.AgenciaId, req, ct);
        foreach (var r in req.Reservas) await ReservaGravacao.ValidarAsync(s, ctx.AgenciaId, r, ct);
        var geraRepasse = await s.Conexao.ExecuteScalarAsync<bool>(new CommandDefinition("select gera_repasse from usuario where id = @id", new { id = req.VendedorId }, s.Transacao, cancellationToken: ct));
        if (req.RepasseValor is not null && !geraRepasse) throw new RegraDeNegocioException("repasse_sem_vendedor", "Este vendedor não gera repasse");

        var viagemId = await s.Conexao.ExecuteScalarAsync<Guid>(new CommandDefinition(
            """
            insert into viagem (agencia_id, vendedor_id, agente_id, destino, tipo, data_ida, data_volta, num_pax, ocasiao, observacoes, criado_por)
            values (@agencia, @VendedorId, @agente, @destino, @Tipo, @DataIda, @DataVolta, @numPax, @Ocasiao, @Observacoes, @usuario) returning id
            """,
            new { agencia = ctx.AgenciaId, req.VendedorId, agente = req.AgenteId ?? ctx.UsuarioId, destino = req.Destino.Trim(), req.Tipo, req.DataIda, req.DataVolta, numPax = req.Passageiros.Length, req.Ocasiao, req.Observacoes, usuario = ctx.UsuarioId },
            s.Transacao, cancellationToken: ct));

        foreach (var p in req.Passageiros)
            await s.Conexao.ExecuteAsync(new CommandDefinition("insert into viagem_passageiro (agencia_id, viagem_id, cliente_id, titular) values (@agencia, @viagemId, @ClienteId, @Titular)", new { agencia = ctx.AgenciaId, viagemId, p.ClienteId, p.Titular }, s.Transacao, cancellationToken: ct));
        foreach (var r in req.Reservas) await ReservaGravacao.InserirAsync(s, ctx, viagemId, r, ct);
        if (geraRepasse)
            await s.Conexao.ExecuteAsync(new CommandDefinition("insert into repasse (agencia_id, viagem_id, usuario_id, valor) values (@agencia, @viagemId, @VendedorId, @RepasseValor)", new { agencia = ctx.AgenciaId, viagemId, req.VendedorId, req.RepasseValor }, s.Transacao, cancellationToken: ct));
        await Rotinas.ReavaliarRepasseAsync(s, ctx.AgenciaId, viagemId, ct);
        await Rotinas.GerarPendenciasAsync(s, ctx.AgenciaId, viagemId, req.DataIda, req.DataVolta, req.AgenteId ?? ctx.UsuarioId, ct);

        var dto = await ViagemLeitura.CarregarAsync(s, ctx.AgenciaId, viagemId, ProjecaoDe(usuario), ct) ?? throw new InvalidOperationException("viagem recém-criada não encontrada");
        await s.ConfirmarAsync(ct);
        return dto;
    }

    public async Task<ViagemDto> ObterAsync(ContextoSessao ctx, UsuarioAtual usuario, Guid id, CancellationToken ct)
    {
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        var dto = await ViagemLeitura.CarregarAsync(s, ctx.AgenciaId, id, ProjecaoDe(usuario), ct);
        if (dto is null || (!usuario.Pode(Permissao.ViagemVer) && dto.VendedorId != usuario.UsuarioId))
            throw new RegraDeNegocioException("nao_encontrado", "Viagem não encontrada");
        return dto;
    }

    internal static void ValidarCabecalho(ViagemRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Destino)) throw new RegraDeNegocioException("destino_obrigatorio", "Informe o destino");
        if (!Tipos.Contains(req.Tipo)) throw new RegraDeNegocioException("tipo_invalido", "Tipo da viagem inválido");
        if (req.DataIda is { } i && req.DataVolta is { } v && v < i) throw new RegraDeNegocioException("datas_incoerentes", "Volta antes da ida");
        if (req.Passageiros.Length == 0) throw new RegraDeNegocioException("sem_passageiro", "Informe ao menos um passageiro");
        if (req.Passageiros.Select(p => p.ClienteId).Distinct().Count() != req.Passageiros.Length) throw new RegraDeNegocioException("passageiro_duplicado", "Passageiro repetido");
        var titulares = req.Passageiros.Count(p => p.Titular);
        if (titulares == 0) throw new RegraDeNegocioException("titular_obrigatorio", "Marque o passageiro titular");
        if (titulares > 1) throw new RegraDeNegocioException("titular_duplicado", "Só um titular por viagem");
        if (req.RepasseValor is < 0) throw new RegraDeNegocioException("valor_negativo", "Repasse não pode ser negativo");
    }

    internal static async Task ValidarReferenciasAsync(DbSessao s, Guid agenciaId, ViagemRequest req, CancellationToken ct)
    {
        await Guardas.ReferenciaAsync(s, Tabela.Usuario, req.VendedorId, agenciaId, ct, exigirAtivo: true);
        if (req.AgenteId is { } ag) await Guardas.ReferenciaAsync(s, Tabela.Usuario, ag, agenciaId, ct, exigirAtivo: true);
        foreach (var p in req.Passageiros) await Guardas.ReferenciaAsync(s, Tabela.Cliente, p.ClienteId, agenciaId, ct);
    }
}
```
`usuario_inativo` do `Guardas` cobre "vendedor inativo" (documentar no relatório; o código do contrato é `usuario_inativo`).

- [ ] **Step 7: Endpoints + registro**

```csharp
public static IEndpointRouteBuilder MapViagensEndpoints(this IEndpointRouteBuilder app)
{
    var g = app.MapGroup("/viagens");
    g.MapPost("/", async (ViagemRequest req, HttpContext http, ViagensService viagens, CancellationToken ct) =>
    {
        var dto = await viagens.CriarAsync(http.Contexto(), http.UsuarioAtual(), req, ct);
        return Results.Created($"/api/v1/viagens/{dto.Id}", dto);
    }).RequerPermissao(Permissao.ViagemCriar);

    g.MapGet("/{id:guid}", async (Guid id, HttpContext http, ViagensService viagens, CancellationToken ct) =>
    {
        var u = http.UsuarioAtual();
        if (!u.Pode(Permissao.ViagemVer) && !u.Pode(Permissao.ViagemVerProprias))
            return Results.Problem(statusCode: 403, title: "Sem permissão", detail: "Requer viagem.ver", extensions: new Dictionary<string, object?> { ["codigo"] = "sem_permissao", ["permissao"] = "viagem.ver" });
        return Results.Ok(await viagens.ObterAsync(http.Contexto(), u, id, ct));
    }).RequireAuthorization();
    return app;
}
```
`Endpoints.cs`: `AddScoped<Viagens.ViagensService>()`; `api.MapViagensEndpoints()`.

- [ ] **Step 8: Rodar** — `dotnet build -c Release && dotnet test && dotnet format --verify-no-changes` → 0 falhas.

- [ ] **Step 9: Reportar.** Commit sugerido: `feat(viagens): create trip aggregate (passengers, reservas, repasse, pendencias) in one transaction; per-profile read`

---

### Task 4 (backend): Editar viagem, adicionar reserva, viagem semelhante, reserva duplicada

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/{ViagensEndpoints.cs,ViagensService.cs,ReservaGravacao.cs}`
- Create: `backend/src/Meridiano.Api/Modules/Viagens/ViagensConsultas.cs`
- Create: `backend/tests/Meridiano.Api.Tests/ViagensEditarTests.cs`

**Depends-on:** T3

**Interfaces:**
- Produces:
  - `ViagensService.AtualizarAsync(ctx, usuario, Guid id, ViagemRequest req, ct) → ViagemDto`: `TravarViagemAsync(id, req.Versao)` (409 se mudou; `Versao` null → 422 `versao_obrigatoria`); cabeçalho `UPDATE`; passageiros = conjunto substituído (2 statements: `update … set titular = false`, depois insert/delete/set titular); `vendedor_id` diferente do atual exige `ViagemDefinirVendedor` (senão 403 `sem_permissao`) e, com repasse existente não pago, faz soft delete + novo repasse (com repasse pago → 422 `repasse_pago`, D5); reservas: com `Id` → `ReservaGravacao.AtualizarAsync` (mesma validação; `data_compra` alterada exige `Guardas.CompetenciaAbertaAsync` para data antiga e nova com `podeEditarFechado = usuario.Pode(FinanceiroEditarPeriodoFechado)` e `motivo = ctx.Motivo`; recalcula `data_prevista_comissao` só quando `fornecedor_id` ou `data_compra` mudou), sem `Id` → insert; reservas existentes ausentes do payload **não são tocadas** (cancelar/excluir é 3.3); `Id` desconhecido → 422 `reserva_nao_encontrada`; termina com `ReavaliarRepasseAsync`, `GerarPendenciasAsync`, `TocarViagemAsync`.
  - `ViagensService.AdicionarReservaAsync(ctx, usuario, Guid id, NovaReservaRequest req, ct) → ViagemDto`: lock + versão, validar, inserir, competência da `data_compra`, reavaliar repasse, tocar viagem.
  - `ViagensConsultas.SemelhantesAsync(ctx, Guid clienteId, DateOnly? ida, DateOnly? volta, ct) → ViagemSemelhanteDto[]`: viagens não canceladas, não excluídas, com `data_volta >= current_date` ou sem data, em que o cliente é passageiro; `Sobrepoe = ida/volta informadas e intervalos se cruzam`; ordem `data_ida desc`, limit 5.
  - `ViagensConsultas.ReservaDuplicadaAsync(ctx, Guid fornecedorId, string localizador, ct) → (Guid ViagemId, string Codigo)?` usando `ix_reserva_fornecedor_loc` (comparação `lower(trim())`).
  - Rotas: `PUT /viagens/{id}` (`ViagemEditar`), `POST /viagens/{id}/reservas` (`ViagemEditar`), `GET /viagens/semelhantes?clienteId&dataIda&dataVolta` (`RequireAuthorization`; usuário só com `ViagemVerProprias` recebe filtro `vendedor_id = usuario`), `GET /reservas/duplicada?fornecedorId&localizador` (`RequireAuthorization`; 204 quando não há) — registrar `/reservas/duplicada` em `MapViagensEndpoints` também. **Ordem:** `MapGet("/semelhantes")` antes de `MapGet("/{id:guid}")` (não conflita, mas mantém legível).

- [ ] **Step 1: Testes** (`ViagensEditarTests.cs`; reutilizar o `Cenario`/`Pedido`/`Reserva1` de `ViagensCriarTests` copiando os helpers — arquivos de teste não compartilham)

```csharp
[Fact] public async Task Put_com_versao_velha_da_409_e_com_atual_grava_e_renova_versao()
// cria viagem; PUT destino "Porto" com versao atual → 200, Versao diferente; PUT de novo com a versao antiga → 409 conflito_concorrencia

[Fact] public async Task Put_troca_titular_e_passageiros_sem_violar_indice()
// cria com Carlos titular + Lúcia; PUT com Lúcia titular e Carlos removido → 200; passageiros = [Lúcia titular]; num_pax = 1

[Fact] public async Task Put_atualiza_reserva_existente_e_insere_nova_sem_tocar_nas_outras()
// cria com 2 reservas; PUT com reservas = [ {id: r1, valorComissao 2000 …}, {nova sem id} ] → 200; 3 reservas; r1.ValorComissao 2000; r2 inalterada

[Fact] public async Task Put_com_data_compra_em_mes_fechado_e_422_periodo_fechado()
// inserir fechamento_periodo (agencia, '2026-03-01') via owner; PUT movendo data_compra de r1 para 2026-03-20 → 422 periodo_fechado (agente não tem FinanceiroEditarPeriodoFechado)

[Fact] public async Task Put_mudando_vendedor_exige_permissao_e_substitui_repasse_nao_pago()
// cria com Externa (repasse 300); PUT como agente (tem ViagemDefinirVendedor) para outro externo → repasse antigo excluido_em not null, novo repasse bloqueado; marcar repasse pago via owner e repetir → 422 repasse_pago

[Fact] public async Task Adicionar_reserva_a_viagem_existente_reavalia_repasse_e_versao()
// cria rascunho com Externa; POST /viagens/{id}/reservas {reserva, versao} → 200 com 1 reserva; nova Versao; segundo POST com versao velha → 409

[Fact] public async Task Semelhantes_encontra_viagem_ativa_do_passageiro_e_marca_sobreposicao()
// cria viagem Carlos 2026-04-18..28; GET semelhantes?clienteId=Carlos&dataIda=2026-04-20&dataVolta=2026-04-25 → 1 item Sobrepoe=true; com 2026-06-01..05 → Sobrepoe=false; viagem cancelada via owner não aparece

[Fact] public async Task Reserva_duplicada_por_fornecedor_e_localizador()
// cria viagem com reserva CVC K7X2PQ; GET /reservas/duplicada?fornecedorId=cvc&localizador=k7x2pq → 200 {codigo}; localizador ZZZ → 204
```
Escrever cada teste completo seguindo o modelo de T3 (login, `Pedido`, asserções acima).

- [ ] **Step 2: Rodar para ver falhar.**

- [ ] **Step 3: `ReservaGravacao.AtualizarAsync`**

```csharp
public static async Task AtualizarAsync(DbSessao s, ContextoSessao ctx, Guid viagemId, ReservaRequest r, bool podeEditarFechado, CancellationToken ct)
{
    var atual = await s.Conexao.QuerySingleOrDefaultAsync<(Guid FornecedorId, DateOnly DataCompra)>(new CommandDefinition(
        "select fornecedor_id, data_compra from reserva where id = @id and viagem_id = @viagemId and agencia_id = @agencia and excluido_em is null",
        new { id = r.Id, viagemId, agencia = ctx.AgenciaId }, s.Transacao, cancellationToken: ct));
    if (atual == default) throw new RegraDeNegocioException("reserva_nao_encontrada", "Reserva não encontrada nesta viagem");
    if (atual.DataCompra != r.DataCompra)
    {
        await Guardas.CompetenciaAbertaAsync(s, ctx.AgenciaId, atual.DataCompra, podeEditarFechado, ctx.Motivo, ct);
        await Guardas.CompetenciaAbertaAsync(s, ctx.AgenciaId, r.DataCompra, podeEditarFechado, ctx.Motivo, ct);
    }
    var recalcular = atual.FornecedorId != r.FornecedorId || atual.DataCompra != r.DataCompra;
    var prevista = recalcular ? await PrevisaoAsync(s, ctx.AgenciaId, r.FornecedorId, r.DataCompra, ct) : null;
    await s.Conexao.ExecuteAsync(new CommandDefinition(
        """
        update reserva set fornecedor_id = @FornecedorId, localizador = nullif(trim(@Localizador), ''), data_compra = @DataCompra, status = @Status,
               tipos_servico = @TiposServico, formas_pagamento = @FormasPagamento, valor_total = @ValorTotal, valor_taxas = @ValorTaxas, valor_comissao = @ValorComissao,
               rav_operadora = @RavOperadora, valor_cliente = @ValorCliente, taxa_servico = @TaxaServico, rav_cliente_modo = @RavClienteModo, fluxo_pagamento = @FluxoPagamento,
               nfse_status = @NfseStatus, observacoes = @Observacoes, data_prevista_comissao = coalesce(@prevista, data_prevista_comissao)
         where id = @Id and agencia_id = @agencia
        """, new { r.Id, agencia = ctx.AgenciaId, r.FornecedorId, r.Localizador, r.DataCompra, r.Status, r.TiposServico, r.FormasPagamento, r.ValorTotal, r.ValorTaxas, r.ValorComissao, r.RavOperadora, r.ValorCliente, r.TaxaServico, r.RavClienteModo, r.FluxoPagamento, r.NfseStatus, r.Observacoes, prevista }, s.Transacao, cancellationToken: ct));
}
```
Ordem de lock (Guardas): competência **antes** da viagem — então em `AtualizarAsync` do serviço, calcular primeiro o conjunto de competências afetadas (reservas com `Id` cuja `data_compra` muda: antiga + nova) e chamar `CompetenciaAbertaAsync` para cada uma **antes** de `TravarViagemAsync`; `ReservaGravacao.AtualizarAsync` então recebe `podeEditarFechado` só para revalidar (idempotente: o lock advisory é reentrante na mesma transação).

- [ ] **Step 4: `ViagensService.AtualizarAsync` / `AdicionarReservaAsync`** — seguir a descrição em Interfaces; esqueleto:

```csharp
public async Task<ViagemDto> AtualizarAsync(ContextoSessao ctx, UsuarioAtual usuario, Guid id, ViagemRequest req, CancellationToken ct)
{
    if (req.Versao is null) throw new RegraDeNegocioException("versao_obrigatoria", "Envie a versão atual da viagem");
    ValidarCabecalho(req);
    await using var s = await sessoes.AbrirAsync(ctx, ct);
    var podeFechado = usuario.Pode(Permissao.FinanceiroEditarPeriodoFechado);
    await TravarCompetenciasAfetadasAsync(s, ctx, id, req, podeFechado, ct);   // lê data_compra atual das reservas com Id e chama CompetenciaAbertaAsync (antiga e nova) quando diferem
    await Guardas.TravarViagemAsync(s, id, ctx.AgenciaId, req.Versao, ct);
    await ValidarReferenciasAsync(s, ctx.AgenciaId, req, ct);
    foreach (var r in req.Reservas) await ReservaGravacao.ValidarAsync(s, ctx.AgenciaId, r, ct);

    var vendedorAtual = await s.Conexao.ExecuteScalarAsync<Guid>(new CommandDefinition("select vendedor_id from viagem where id = @id", new { id }, s.Transacao, cancellationToken: ct));
    if (vendedorAtual != req.VendedorId)
    {
        if (!usuario.Pode(Permissao.ViagemDefinirVendedor)) throw new RegraDeNegocioException("sem_permissao_vendedor", "Requer viagem.definir_vendedor");
        await TrocarVendedorAsync(s, ctx, id, req.VendedorId, req.RepasseValor, ct);   // pago → 422 repasse_pago; não pago → soft delete; gera_repasse → insert novo
    }
    else await AjustarRepasseValorAsync(s, ctx, id, req.RepasseValor, ct);           // atualiza valor do repasse ativo se existir e não estiver pago

    await s.Conexao.ExecuteAsync(new CommandDefinition("update viagem set vendedor_id = @VendedorId, agente_id = @agente, destino = @destino, tipo = @Tipo, data_ida = @DataIda, data_volta = @DataVolta, num_pax = @numPax, ocasiao = @Ocasiao, observacoes = @Observacoes where id = @id",
        new { id, req.VendedorId, agente = req.AgenteId, destino = req.Destino.Trim(), req.Tipo, req.DataIda, req.DataVolta, numPax = req.Passageiros.Length, req.Ocasiao, req.Observacoes }, s.Transacao, cancellationToken: ct));
    await SubstituirPassageirosAsync(s, ctx, id, req.Passageiros, ct);               // 1) set titular=false em todos; 2) delete os ausentes; 3) insert on conflict (viagem_id, cliente_id) do update set titular = excluded.titular
    foreach (var r in req.Reservas)
        if (r.Id is null) await ReservaGravacao.InserirAsync(s, ctx, id, r, ct); else await ReservaGravacao.AtualizarAsync(s, ctx, id, r, podeFechado, ct);
    await Rotinas.ReavaliarRepasseAsync(s, ctx.AgenciaId, id, ct);
    await Rotinas.GerarPendenciasAsync(s, ctx.AgenciaId, id, req.DataIda, req.DataVolta, req.AgenteId, ct);
    var dto = await ViagemLeitura.CarregarAsync(s, ctx.AgenciaId, id, ProjecaoDe(usuario), ct)!;
    await s.ConfirmarAsync(ct);
    return dto!;
}
```
O `update viagem` renova o `xmin` (não precisa de `TocarViagemAsync`); em `AdicionarReservaAsync` usar `TocarViagemAsync` após o insert. O `ViagensService.cs` vai passar de 350 linhas: mover `TrocarVendedorAsync`, `AjustarRepasseValorAsync`, `SubstituirPassageirosAsync`, `TravarCompetenciasAfetadasAsync` para `ViagensEdicao.cs` (static, mesma pasta).

- [ ] **Step 5: `ViagensConsultas.cs`**

```csharp
public sealed class ViagensConsultas(DbSessaoFactory sessoes)
{
    public async Task<IReadOnlyList<ViagemSemelhanteDto>> SemelhantesAsync(ContextoSessao ctx, Guid? apenasVendedor, Guid clienteId, DateOnly? ida, DateOnly? volta, CancellationToken ct)
    {
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        var lista = await s.Conexao.QueryAsync<ViagemSemelhanteDto>(new CommandDefinition(
            """
            select v.id, v.codigo, v.destino, v.data_ida as DataIda, v.data_volta as DataVolta, f.fase_operacional as FaseOperacional,
                   (@ida::date is not null and @volta::date is not null and v.data_ida is not null and v.data_volta is not null and v.data_ida <= @volta and v.data_volta >= @ida) as Sobrepoe
              from viagem v join viagem_passageiro vp on vp.viagem_id = v.id join vw_fase_viagem f on f.viagem_id = v.id
             where v.agencia_id = @agencia and v.excluido_em is null and not v.cancelada and vp.cliente_id = @clienteId
               and (v.data_volta is null or v.data_volta >= current_date)
               and (@apenasVendedor::uuid is null or v.vendedor_id = @apenasVendedor)
             order by v.data_ida desc nulls last limit 5
            """, new { agencia = ctx.AgenciaId, clienteId, ida, volta, apenasVendedor }, s.Transacao, cancellationToken: ct));
        return lista.ToList();
    }

    public async Task<(Guid ViagemId, string Codigo)?> ReservaDuplicadaAsync(ContextoSessao ctx, Guid fornecedorId, string localizador, CancellationToken ct)
    {
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        var r = await s.Conexao.QuerySingleOrDefaultAsync<(Guid ViagemId, string Codigo)>(new CommandDefinition(
            "select v.id, v.codigo from reserva r join viagem v on v.id = r.viagem_id where r.agencia_id = @agencia and r.fornecedor_id = @fornecedorId and lower(trim(r.localizador)) = lower(trim(@localizador)) and r.excluido_em is null limit 1",
            new { agencia = ctx.AgenciaId, fornecedorId, localizador }, s.Transacao, cancellationToken: ct));
        return r == default ? null : r;
    }
}
```
Registrar `ViagensConsultas` em `AddModules`.

- [ ] **Step 6: Rodar tudo; format.** Commit sugerido: `feat(viagens): update aggregate with version/lock, add reserva, similar trip and duplicate reserva lookups`

---

### Task 5 (front): Base — grid de formulário, `calculoReserva`, cliente `api/viagens`, `Page` com "Salvar e sair", clamp do `MoneyInput`

**Files:**
- Modify: `frontend/src/styles/global.css` (+ `.grid-form`, `.span-*`, `@media (max-width: 700px)`)
- Create: `frontend/src/dominio/calculoReserva.ts`, `frontend/src/dominio/calculoReserva.test.ts`
- Create: `frontend/src/api/viagens.ts` (tipos + funções)
- Modify: `frontend/src/components/Page/Page.tsx`, `frontend/src/components/Page/Page.test.tsx` (3º botão)
- Modify: `frontend/src/components/Input/MoneyInput.tsx`, `MoneyInput.test.tsx` (clamp em `mudar`)
- Modify: `frontend/src/dominio/status.ts` (+ entidade `nfse`: `falta_emitir` "Falta emitir"/warning, `emitido` "Emitida"/success, `nao_precisa` "Não precisa"/neutral) e `status.test.ts`

**Depends-on:** none

**Interfaces:**
- Produces:
```ts
// src/dominio/calculoReserva.ts
export interface ValoresReserva { valorTotal: number; valorComissao: number; ravOperadora: number; valorCliente: number; taxaServico: number; viaOperadora: boolean; cancelada?: boolean; comissaoMantida?: boolean }
export interface ResultadoReserva { ravCliente: number; valorEsperadoOperadora: number; receitaPrevista: number; percentualComissao: number | null }
export function calcularReserva(v: ValoresReserva): ResultadoReserva   // centavos exatos: opera em inteiros de centavos (Math.round(x*100)) e devolve /100
export function arredondar2(n: number): number                          // half away from zero

// src/api/viagens.ts — espelho do contrato C# (camelCase)
export type Tipo = "nacional" | "internacional"; export type StatusReserva = "pendente" | "emitida";
export type RavClienteModo = "retido_agencia" | "via_operadora"; export type FluxoPagamento = "cliente_paga_operadora" | "cliente_paga_agencia";
export type NfseStatus = "falta_emitir" | "emitido" | "nao_precisa";
export const TIPOS_SERVICO = ["aereo","hospedagem","seguro","traslado","passeio","ingresso","aluguel_carro","documentacao","outro"] as const; export type TipoServico = typeof TIPOS_SERVICO[number];
export const ROTULO_SERVICO: Record<TipoServico, string> = { aereo: "Aéreo", hospedagem: "Hospedagem", seguro: "Seguro", traslado: "Traslado", passeio: "Passeio", ingresso: "Ingresso", aluguel_carro: "Aluguel de carro", documentacao: "Documentação", outro: "Outro" };
export const FORMAS_PAGAMENTO = ["pix","boleto","cartao"] as const; export type FormaPagamento = typeof FORMAS_PAGAMENTO[number];
export const ROTULO_FORMA: Record<FormaPagamento, string> = { pix: "PIX", boleto: "Boleto", cartao: "Cartão" };
export interface PassageiroRequest { clienteId: string; titular: boolean }
export interface ReservaRequest { id?: string; fornecedorId: string; localizador: string | null; dataCompra: string; status: StatusReserva; tiposServico: TipoServico[]; valorTotal: number; valorTaxas: number; valorComissao: number; ravOperadora: number; valorCliente: number; taxaServico: number; ravClienteModo: RavClienteModo; fluxoPagamento: FluxoPagamento; formasPagamento: FormaPagamento[]; nfseStatus: NfseStatus; observacoes: string | null }
export interface ViagemRequest { destino: string; tipo: Tipo; dataIda: string | null; dataVolta: string | null; vendedorId: string; agenteId: string | null; ocasiao: string | null; observacoes: string | null; passageiros: PassageiroRequest[]; repasseValor: number | null; reservas: ReservaRequest[]; versao?: string }
export interface PassageiroDto { clienteId: string; nome: string; titular: boolean }
export interface ReservaDto { id: string; versao: string; fornecedorId: string; fornecedorNome: string; localizador: string | null; dataCompra: string; status: StatusReserva | "cancelada"; tiposServico: TipoServico[]; formasPagamento: FormaPagamento[]; ravClienteModo: RavClienteModo; fluxoPagamento: FluxoPagamento; nfseStatus: NfseStatus; observacoes: string | null; dataPrevistaComissao: string | null; valorTotal?: number; valorTaxas?: number; valorComissao?: number; ravOperadora?: number; valorCliente?: number; taxaServico?: number; ravCliente?: number; valorEsperadoOperadora?: number; receitaPrevista?: number; percentualComissao?: number | null }
export interface RepasseDto { id: string; valor: number | null; status: "bloqueado" | "a_pagar" | "pago" }
export interface ResumoViagemDto { vendaTotal: number; custoFornecedores: number; receitaPrevista: number; repasseValor: number | null; despesasViagem: number; resultado: number }
export interface ViagemDto { id: string; codigo: string; versao: string; destino: string; tipo: Tipo; dataIda: string | null; dataVolta: string | null; vendedorId: string; vendedorNome: string; agenteId: string | null; ocasiao: string | null; observacoes: string | null; cancelada: boolean; faseOperacional: string; faseFinanceira: string; passageiros: PassageiroDto[]; reservas: ReservaDto[]; repasse?: RepasseDto | null; resumo?: ResumoViagemDto | null }
export interface ViagemSemelhanteDto { id: string; codigo: string; destino: string; dataIda: string | null; dataVolta: string | null; faseOperacional: string; sobrepoe: boolean }
export interface ClienteBuscaDto { id: string; nome: string; telefone: string | null; cpf?: string | null }
export interface FornecedorDto { id: string; nome: string; tipo: string; percentualComissaoPadrao: number | null; prazoComissaoDias: number | null; ativo: boolean }
export interface VendedorDto { id: string; nome: string; perfil: string; geraRepasse: boolean; percentualPadrao: number }
export interface AgenciaDto { nome: string; taxaServicoPadrao: number }
export const viagensApi = {
  criar: (v: ViagemRequest) => api.post<ViagemDto>("/viagens", v),
  obter: (id: string) => api.get<ViagemDto>(`/viagens/${id}`),
  atualizar: (id: string, v: ViagemRequest) => api.put<ViagemDto>(`/viagens/${id}`, v),
  adicionarReserva: (id: string, reserva: ReservaRequest, versao: string) => api.post<ViagemDto>(`/viagens/${id}/reservas`, { reserva, versao }),
  semelhantes: (clienteId: string, dataIda: string | null, dataVolta: string | null) => api.get<ViagemSemelhanteDto[]>(`/viagens/semelhantes?${qs({ clienteId, dataIda, dataVolta })}`),
  reservaDuplicada: (fornecedorId: string, localizador: string) => api.get<{ viagemId: string; codigo: string } | undefined>(`/reservas/duplicada?${qs({ fornecedorId, localizador })}`),
  buscarClientes: (q: string) => api.get<ClienteBuscaDto[]>(`/clientes/busca?q=${encodeURIComponent(q)}`),
  criarCliente: (c: { nome: string; telefone?: string; email?: string; cpf?: string }) => api.post<ClienteBuscaDto>("/clientes", c),
  fornecedores: () => api.get<FornecedorDto[]>("/fornecedores?ativo=true"),
  criarFornecedor: (f: { nome: string; tipo: string }) => api.post<FornecedorDto>("/fornecedores", f),
  vendedores: () => api.get<VendedorDto[]>("/usuarios/vendedores"),
  agencia: () => api.get<AgenciaDto>("/agencia"),
};
export const chaves = { viagem: (id: string) => ["viagens", id] as const, fornecedores: ["fornecedores"] as const, vendedores: ["vendedores"] as const, agencia: ["agencia"] as const };
```
(`qs` = helper local que omite `null`/`undefined` e usa `URLSearchParams`.)
  - `Page` ganha `onSalvarESair?: () => Promise<boolean>`; quando presente, o modal mostra o terceiro botão `Salvar e sair` (primary): chama o callback e, se `true`, `confirmar()`.
  - `.grid-form` = `display:grid; grid-template-columns: repeat(12, minmax(0,1fr)); gap: var(--space-4) var(--space-4)`; `.span-2 … .span-12` = `grid-column: span N`; `@media (max-width: 700px) { .grid-form > * { grid-column: 1 / -1 } }`.
  - `MoneyInput.mudar` aplica o mesmo clamp do blur (`allowNegative=false` → `Math.abs`).

- [ ] **Step 1: Testes** — `calculoReserva.test.ts` com os 8 casos de T1 (mesmos números) + `expect(calcularReserva({valorTotal: 0.1, valorComissao: 0.2, ravOperadora: 0, valorCliente: 0.3, taxaServico: 0, viaOperadora: false}).ravCliente).toBe(0.2)` (sem erro de ponto flutuante); `Page.test.tsx`: com `onSalvarESair` o modal tem 3 botões e clicar "Salvar e sair" chama o callback e navega quando resolve `true`; `MoneyInput.test.tsx`: `allowNegative` false + digitar `-50` emite `50` durante a digitação (nunca `-5`); `status.test.ts`: `apresentacaoStatus("nfse","falta_emitir")` → `{ texto: "Falta emitir", tone: "warning" }`.

- [ ] **Step 2: Rodar para ver falhar.**

- [ ] **Step 3: `calculoReserva.ts`**

```ts
export function arredondar2(n: number): number { const s = Math.sign(n); return (s * Math.round(Math.abs(n) * 100 + Number.EPSILON)) / 100; }
const c = (n: number) => Math.round(n * 100);           // centavos inteiros
export function calcularReserva(v: ValoresReserva): ResultadoReserva {
  const total = c(v.valorTotal), com = c(v.valorComissao), rav = c(v.ravOperadora), cli = c(v.valorCliente), taxa = c(v.taxaServico);
  const ravCliente = cli - total;
  const zera = Boolean(v.cancelada) && !v.comissaoMantida;
  const esperado = zera ? 0 : com + rav + (v.viaOperadora ? ravCliente : 0);
  const prevista = zera ? 0 : com + rav + ravCliente + taxa;
  const percentual = total > 0 ? arredondar2((100 * com) / total) : null;
  return { ravCliente: ravCliente / 100, valorEsperadoOperadora: esperado / 100, receitaPrevista: prevista / 100, percentualComissao: percentual };
}
```

- [ ] **Step 4: implementar o resto (global.css, api/viagens.ts, Page, MoneyInput, status).** `Page`: footer do modal recebe `{onSalvarESair && <Button variant="primary" loading={salvando} onClick={…}>Salvar e sair</Button>}` com `useState` local `salvando`.

- [ ] **Step 5: Rodar** — `node node_modules/vitest/vitest.mjs run`, `npm run lint`, `npm run typecheck` verdes.

- [ ] **Step 6: Reportar.** Commit sugerido: `feat(base): form grid, calculoReserva preview, viagens api client, save-and-leave in Page, money clamp while typing, nfse status map`

---

### Task 6 (front): `ReservationCard` e sub-blocos

**Files:**
- Create: `frontend/src/components/Reserva/{ServiceChips.tsx,ServiceChips.test.tsx,BookingFields.tsx,FinancialFields.tsx,FinancialFields.test.tsx,ResultSummary.tsx,ReservationCard.tsx,ReservationCard.test.tsx,Reserva.module.css,tipos.ts}`
- Create: `frontend/src/components/reserva.ts` (barrel)

**Depends-on:** T5 (`calcularReserva`, tipos, `.grid-form`)

**Interfaces:**
- Consumes: `Field Input Select DateInput MoneyInput MoneyValue Button IconButton` (`@/components`), `Chip Badge StatusBadge Tooltip` (`@/components/display`), `calcularReserva`, `TIPOS_SERVICO/ROTULO_*`, `FornecedorDto`.
- Produces:
```ts
// tipos.ts — estado do formulário de UMA reserva (o que a página guarda no useFieldArray)
export interface ReservaForm { id?: string; versao?: string; fornecedorId: string; localizador: string; dataCompra: string; status: StatusReserva; nfseStatus: NfseStatus; tiposServico: TipoServico[]; valorTotal: number | null; valorTaxas: number | null; valorComissao: number | null; comissaoSugerida: boolean; ravOperadora: number | null; valorCliente: number | null; taxaServico: number | null; ravClienteModo: RavClienteModo; fluxoPagamento: FluxoPagamento; formasPagamento: FormaPagamento[]; observacoes: string; aberta: boolean }
export function reservaVazia(taxaServicoPadrao: number): ReservaForm   // status "pendente", nfse "nao_precisa", modo "retido_agencia", fluxo "cliente_paga_operadora", dataCompra = hoje (yyyy-mm-dd), aberta true
export function paraRequest(r: ReservaForm): ReservaRequest             // null → 0 nos dinheiros; localizador vazio → null
export function deDto(r: ReservaDto): ReservaForm

<ServiceChips value={TipoServico[]} onChange={(v) => void} />           // 9 chips (ROTULO_SERVICO), toggle, aria-pressed; role="group" aria-label="Serviços vendidos"
<BookingFields value={ReservaForm} onChange={(patch: Partial<ReservaForm>) => void} fornecedores={FornecedorDto[]} onNovoFornecedor={() => void} erros={Partial<Record<keyof ReservaForm,string>>} />
  // Fornecedor (Select + botão "+ novo" tertiary), Localizador (Input mono), Data da compra (DateInput), NFSe (Select), Serviços vendidos (ServiceChips, span 12)
<FinancialFields value={ReservaForm} onChange={…} percentualSugerido={number | null} erros={…} />
  // Total da reserva (tooltip "O que o fornecedor cobrou, taxas incluídas"), Do total, quanto é taxa, Comissão (helper "Sugerido: N %" quando comissaoSugerida), RAV da operadora,
  // Venda ao cliente (tooltip), RAV do cliente vem (Select via_operadora/retido_agencia), Formas de pagamento (3 chips), Fluxo (Select "Cliente paga a operadora"/"Cliente paga a agência"), Taxa de serviço (dentro de "+ mais campos", details/summary), Observações (textarea via Input? → usar <textarea> nativo dentro de Field com className s.control)
<ResultSummary value={ReservaForm} />                                    // 5 números do protótipo: Venda ao cliente · Custo · Comissão + RAV op. (esperado) · RAV do cliente · Receita da agência (emphasis result)
<ReservationCard indice={number} value={ReservaForm} onChange={…} onToggle={() => void} onRemover={() => void} fornecedores={FornecedorDto[]} onNovoFornecedor={…} erros={…} avisoDuplicada={string | null} />
  // header: "Reserva N", fornecedor nome, localizador mono, StatusBadge("reserva"), serviços (texto), venda + "receita R$ X"; botão "Expandir"/"Recolher" (aria-expanded); body só quando aberta; avisoDuplicada → <Alert tone="warning"> dentro do body
```
  - Regra "sugerido": a página decide `comissaoSugerida` (T8); `FinancialFields` só mostra o helper e, ao editar `valorComissao`, emite `{ valorComissao, comissaoSugerida: false }`.
  - Sem `@media` além de 700 (grid). Header do card em uma linha, `flex-wrap` abaixo de 1366 é responsabilidade do CSS do card (`@media (max-width: 1366px)`).

- [ ] **Step 1: Testes**
  - `ServiceChips.test.tsx`: renderiza 9 chips; clicar "Seguro" adiciona `"seguro"`; clicar de novo remove; `aria-pressed` reflete.
  - `FinancialFields.test.tsx`: com `comissaoSugerida` true e `percentualSugerido` 10 aparece "Sugerido: 10 %"; digitar em Comissão emite `comissaoSugerida: false`.
  - `ReservationCard.test.tsx`: header mostra "Reserva 1", fornecedor e `R$ 3.200,00`; fechado não renderiza campos; "Expandir" chama `onToggle`; `ResultSummary` dentro mostra `R$ 520,00` para total 3000 / comissão 300 / rav 20 / cliente 3200 / via_operadora (§ protótipo).

- [ ] **Step 2: Rodar para ver falhar.**

- [ ] **Step 3: Implementar** — layout com `.grid-form` + `.span-3` (fornecedor), `.span-2` (localizador, data, NFSe, dinheiro), `.span-12` (chips). `ResultSummary` usa `MoneyValue` com `emphasis="result"` no último. Sem lógica de cálculo fora de `calcularReserva`.

- [ ] **Step 4: Rodar; lint; typecheck; `node scripts/check-tokens.mjs`.**

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(reserva): ReservationCard with booking, service chips, financial fields and result summary`

---

### Task 7 (front): Passageiros, pessoa inline, fornecedor inline, `TripSummary`, aviso de viagem semelhante

**Files:**
- Create: `frontend/src/components/Viagem/{PassageirosField.tsx,PassageirosField.test.tsx,PessoaInlineModal.tsx,PessoaInlineModal.test.tsx,FornecedorInlineModal.tsx,TripSummary.tsx,TripSummary.test.tsx,AvisoViagemSemelhante.tsx,Viagem.module.css}`
- Create: `frontend/src/components/viagem.ts` (barrel)

**Depends-on:** T5

**Interfaces:**
```ts
export interface PassageiroForm { clienteId: string; nome: string; titular: boolean }
<PassageirosField value={PassageiroForm[]} onChange={(v) => void} buscar={(q: string) => Promise<ClienteBuscaDto[]>} onNovaPessoa={() => void} erro={string | undefined} />
  // chips (Chip selected) com o titular destacado (classe .titular + texto "titular" visualmente oculto para leitor); clicar num chip → vira titular; botão ✕ por chip remove; campo de busca (Input) com lista (role="listbox", setas + Enter) — debounce 250 ms; "+ pessoa" (tertiary) abre onNovaPessoa
<PessoaInlineModal open onClose onCriada={(c: ClienteBuscaDto) => void} criar={(c) => Promise<ClienteBuscaDto>} />   // Nome (required), Telefone, E-mail, CPF; erro 422 vira erro de campo (codigo cpf_invalido → CPF; nome_obrigatorio → Nome); 409 duplicado → Alert
<FornecedorInlineModal open onClose onCriado={(f: FornecedorDto) => void} criar={(f) => Promise<FornecedorDto>} />        // Nome + Tipo (Select com os 8 tipos; rótulos: Operadora, Consolidadora, Cia. aérea, Hotel, Seguradora, Receptivo, Despachante, Outro)
<TripSummary reservas={ReservaForm[]} repasseValor={number | null} despesas={number} onAdicionarReserva={() => void} />
  // faixa: Venda total · Custo dos fornecedores · Comissão da vendedora · Despesas da viagem · Resultado da viagem (tooltip "Receita das reservas − comissão da vendedora − despesas vinculadas"); botão business "+ Adicionar reserva"; quebra em 1366
<AvisoViagemSemelhante item={ViagemSemelhanteDto} titularNome={string} onAdicionarNaExistente={() => void} onAbrir={() => void} onContinuar={() => void} />   // Alert tone warning (sobrepoe) ou info; 3 botões do protótipo
export function somarReservas(reservas: ReservaForm[]): { vendaTotal: number; custo: number; receitaPrevista: number }   // usa calcularReserva por reserva; ignora nada (3.2 não tem cancelada)
```

- [ ] **Step 1: Testes** — `PassageirosField.test.tsx`: buscar "men" chama `buscar` e mostra 2 opções; Enter na primeira adiciona como titular quando é a primeira pessoa; clicar em outro chip troca o titular (exatamente um). `PessoaInlineModal.test.tsx`: submit sem nome mostra erro de campo; `criar` rejeitando com `ValidationError(422,"cpf_invalido",…)` mostra erro no campo CPF. `TripSummary.test.tsx`: com 2 reservas (3200/3000/300/20/via e 10500/10000/1000/100/via) e repasse 300 → Venda total `R$ 13.700,00`, Resultado `R$ 1.820,00`.

- [ ] **Step 2–4:** RED → implementar → lint/typecheck/tokens verdes.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(viagem): passengers field with inline person, inline supplier, trip summary strip, similar-trip notice`

---

### Task 8 (front): `NovaViagemPage` — formulário, pré-preenchimento, atalhos, salvar, rotas

**Files:**
- Create: `frontend/src/pages/viagens/{NovaViagemPage.tsx,NovaViagemPage.test.tsx,useNovaViagem.ts,useNovaViagem.test.ts,DadosViagemSection.tsx,NovaViagem.module.css}`
- Modify: `frontend/src/shell/rotasModulos.tsx` (`/viagens/nova` e `/viagens/:id/editar` → `NovaViagemPage`; `/viagens/:id` continua `EmConstrucao` até 3.3)
- Modify: `frontend/src/shell/navegacao.ts` (subnav `/viagens`: Viagens `/viagens` · Nova viagem `/viagens/nova`)

**Depends-on:** T5, T6, T7 (front); contratos de T2–T4 (backend)

**Interfaces:**
```ts
// useNovaViagem.ts — toda a lógica fora do JSX
export interface ViagemForm { destino: string; tipo: Tipo; dataIda: string; dataVolta: string; vendedorId: string; agenteId: string; ocasiao: string; observacoes: string; passageiros: PassageiroForm[]; repasseValor: number | null; reservas: ReservaForm[] }
export function useNovaViagem(id: string | undefined): {
  form: UseFormReturn<ViagemForm>; carregando: boolean; viagem: ViagemDto | null;           // viagem = última resposta da API (valores oficiais)
  fornecedores: FornecedorDto[]; vendedores: VendedorDto[]; agencia: AgenciaDto | null; me: Me;
  vendedorSelecionado: VendedorDto | undefined;                                              // para "Comissão da vendedora" (só se geraRepasse)
  semelhante: ViagemSemelhanteDto | null; dispensarSemelhante(): void;                        // consulta ao definir titular e datas (debounce 400 ms), ignorada em edição
  duplicadas: Record<number, string | null>;                                                 // por índice de reserva: código da viagem duplicada
  adicionarReserva(): void; removerReserva(i: number): void; alternarReserva(i: number): void;
  salvamento: ReturnType<typeof useSalvamento<ViagemForm>>; salvar(): Promise<boolean>;      // cria (POST) ou atualiza (PUT com versao); depois de criar, navega para /viagens/{id}/editar (replace) e injeta a resposta no form (reservas ganham id/versao; dinheiros oficiais)
  erros: Record<string, string>;                                                             // erros de campo derivados do codigo 422 (mapa abaixo)
}
```
  - **Pré-preenchimento** (spec §4.1/§14): ao escolher fornecedor com `percentualComissaoPadrao` e `valorComissao` null ou `comissaoSugerida` true, ao mudar `valorTotal`: `valorComissao = arredondar2(valorTotal × pct / 100)`, `comissaoSugerida = true`; `taxaServico` inicial = `agencia.taxaServicoPadrao`; `dataCompra` = hoje; `vendedorId` inicial = `me.usuarioId` se ele está em `vendedores`, senão o primeiro; `agenteId` = `me.usuarioId`; `repasseValor` sugerido = `arredondar2(receitaPrevista total × percentualPadrao / 100)` quando vendedor `geraRepasse` e campo ainda vazio (helper "Sugerido").
  - **Mapa 422 → campo:** `destino_obrigatorio`→`destino`, `titular_obrigatorio`/`sem_passageiro`/`passageiro_duplicado`/`titular_duplicado`→`passageiros`, `datas_incoerentes`→`dataVolta`, `repasse_sem_vendedor`/`valor_negativo`→`repasseValor`, `usuario_inativo`→`vendedorId`, `fornecedor_inativo`/`referencia_invalida`/`tipos_servico_invalido`/`formas_pagamento_invalido`/`status_invalido`/`valor_invalido`/`reserva_nao_encontrada`→ bloco (Alert no topo, texto do `detalhe`); `periodo_fechado`/`motivo_obrigatorio`→ bloco; 409 → Alert "Alguém alterou… Recarregar" com botão que refaz `obter` e substitui o form.
  - **Atalhos:** `useAtalho("ctrl+s", salvar)`, `useAtalho("ctrl+enter", adicionarReserva)`, `useAtalho("escape", recolherReservaAberta, algumaAberta && nenhumModalAberto)`.
  - **Dirty:** `form.formState.isDirty` → `salvamento.marcarSujo()` (efeito) e `<Page dirty={estado === "dirty" || estado === "error"} titulo={codigo ?? "Nova viagem"} onSalvarESair={salvar}>`.
  - **Layout** (protótipo): `PageHeader title="Nova viagem"|codigo meta={<Badge>codigo</Badge>} status={<StatusBadge entidade="fase_viagem" valor=…/>} dirty actions={Fechar (tertiary → navigate(-1)) · Salvar viagem (primary, loading=saving)}` → `AvisoViagemSemelhante` → `Section "Dados da viagem" description="Quem viaja, para onde, quando, quem vendeu"` (`DadosViagemSection`: Passageiros span 6, Destino span 3, Tipo span 3, Ida span 2, Volta span 2, Vendedor span 3, Comissão da vendedora span 2 (só `geraRepasse`), `<details>` "+ mais campos (ocasião, observações)") → `ReservationCard[]` → `TripSummary` → rodapé com dicas de teclado (`<kbd>`).
  - Ao carregar `/viagens/:id/editar`: `viagensApi.obter(id)` → `deDto` por reserva, cards fechados; `Skeleton` enquanto carrega.
  - `staleTime` já é 30 s; `fornecedores/vendedores/agencia` via `useQuery` com `chaves`.

- [ ] **Step 1: Testes**
  - `useNovaViagem.test.ts` (renderHook com `QueryClientProvider` + `createMemoryRouter`, `fetch` mockado): pré-preenche comissão 10% de 3000 → 300 e `comissaoSugerida`; editar comissão desliga sugestão; `salvar()` faz POST com `paraRequest` correto (dinheiros null → 0, localizador "" → null) e navega para `/viagens/{id}/editar`; 422 `titular_obrigatorio` vira `erros.passageiros`.
  - `NovaViagemPage.test.tsx`: renderiza header "Nova viagem", seção e botão business "+ Adicionar reserva"; Ctrl+Enter adiciona um card "Reserva 1"; Ctrl+S com passageiros vazios mostra erro no campo Passageiros (sem chamar a API — validação local `required` do RHF para destino/passageiros/vendedor).

- [ ] **Step 2–4:** RED → implementar (`NovaViagemPage.tsx` ≤ 200 linhas: composição; lógica no hook) → `node node_modules/vitest/vitest.mjs run`, `npm run lint`, `npm run typecheck`, `npm run build` verdes.

- [ ] **Step 5: Reportar.** Commit sugerido: `feat(viagens): nova viagem page with prefill, shortcuts, similar-trip and duplicate warnings, create/update flow`

---

### Task 9 (front + backend): E2E cronometrado com 4 reservas, seed estendida

**Files:**
- Modify: `backend/scripts/seed-dev.sql` (+ fornecedores CVC (10 %, janelas 1–14→20/0 e 15–31→5/1), Decolar (prazo 45), Azul Viagens; clientes Carlos Mendes, Lúcia Mendes; usuário `ana@viva.dev` vendedor_externo `gera_repasse` 12,5 % sem senha; agência `taxa_servico_padrao: 0`)
- Create: `frontend/e2e/nova-viagem.spec.ts`
- Modify: `frontend/e2e/fixtures.ts` (+ `SEED = { cliente: "Carlos Mendes", fornecedores: ["CVC", "Decolar", "Azul Viagens"] }`)
- Modify: `frontend/src/pages/styleguide/StyleguidePage.tsx` (+ seção `sg-reserva`: `ReservationCard` aberta e fechada, `TripSummary`) e `frontend/e2e/styleguide.spec.ts` (+ `reserva` na lista de seções; regenerar baselines win32 + linux)

**Depends-on:** T1–T8

**Interfaces:** nenhum contrato novo.

- [ ] **Step 1: `nova-viagem.spec.ts`**

```ts
import { expect, test } from "@playwright/test";
import { DEV_USER, SEED } from "./fixtures";

async function reserva(page, n: number, fornecedor: string, loc: string, total: string, cliente: string) {
  await page.keyboard.press("Control+Enter");
  const card = page.getByRole("region", { name: `Reserva ${n}` });
  await card.getByLabel("Fornecedor").selectOption({ label: fornecedor });
  await card.getByLabel("Localizador").fill(loc);
  await card.getByRole("button", { name: "Aéreo" }).click();
  await card.getByLabel("Total da reserva").fill(total);
  await card.getByLabel("Venda ao cliente").fill(cliente);
  await card.getByLabel("Venda ao cliente").press("Tab");
}

test("lança viagem com 4 reservas só pelo teclado e mede o tempo", async ({ page }, testInfo) => {
  await page.goto("/login");
  await page.getByLabel(/E-mail/).fill(DEV_USER.email); await page.getByLabel(/Senha/).fill(DEV_USER.senha);
  await page.getByRole("button", { name: "Entrar" }).click();
  await expect(page).toHaveURL(/\/viagens/);

  const inicio = Date.now();
  await page.goto("/viagens/nova");
  const busca = page.getByLabel("Passageiros");
  await busca.fill("Carlos"); await busca.press("ArrowDown"); await busca.press("Enter");
  await page.getByLabel("Destino").fill("Lisboa");
  await page.getByLabel("Tipo").selectOption("internacional");
  await page.getByLabel("Ida").fill("2026-04-18"); await page.getByLabel("Volta").fill("2026-04-28");
  await reserva(page, 1, "CVC", "K7X2PQ", "10000", "10500");
  await expect(page.getByRole("region", { name: "Reserva 1" }).getByLabel("Comissão")).toHaveValue("1.000,00"); // sugerido 10 %
  await reserva(page, 2, "Decolar", "DCL-88213", "3000", "3200");
  await reserva(page, 3, "Azul Viagens", "AZ-90213", "2500", "2500");
  await reserva(page, 4, "CVC", "CVC-77A2Q", "1200", "1400");
  await page.keyboard.press("Control+S");
  await expect(page).toHaveURL(/\/viagens\/[0-9a-f-]+\/editar/);
  await expect(page.getByText(/✓ Salvo/)).toBeVisible();
  const segundos = (Date.now() - inicio) / 1000;
  testInfo.annotations.push({ type: "tempo-4-reservas-s", description: segundos.toFixed(1) });
  console.log(`[tempo] 4 reservas em ${segundos.toFixed(1)} s`);
  expect(segundos).toBeLessThan(300);
  await expect(page.getByText("R$ 17.600,00")).toBeVisible(); // venda total
});

test("aviso de viagem semelhante aparece e não bloqueia", async ({ page }) => { /* login; criar viagem Carlos 2026-05-01..05; abrir /viagens/nova; escolher Carlos e datas sobrepostas; expect Alert "Encontramos uma viagem semelhante"; clicar "Continuar criando nova"; alert some */ });
```
`getByRole("region", { name: "Reserva N" })` exige `role="region"` + `aria-labelledby` no `ReservationCard` (T6 já deve ter; se não, ajustar em T6 é fora de escopo — usar `data-testid="reserva-N"` e registrar).

- [ ] **Step 2: Rodar** com API + seed (`backend/scripts/dev.md`): `npx playwright test e2e/nova-viagem.spec.ts` → 2 testes × 2 viewports verdes; anotar o tempo do relatório.

- [ ] **Step 3: Styleguide + baselines** — adicionar seção; `npx playwright test e2e/styleguide.spec.ts --update-snapshots` local (win32) e no container `mcr.microsoft.com/playwright:v1.63.0-noble` (linux), como em 3.1.

- [ ] **Step 4: Reportar** (tempo medido por viewport). Commits: backend `chore(dev): seed suppliers, rules, clients and external seller for nova viagem e2e`; frontend `test(e2e): timed nova viagem with 4 reservations; styleguide reserva section`.

---

### Task 10 (root): Docs e fechamento

**Files:**
- Modify: `docs/BACKLOG.md` (3.2 concluída; tempo automatizado registrado; linha separada "tempo humano: pendente (teste de UX §7)"; remover pendências resolvidas: `MoneyInput` clamp, `DateOnly` type map, `Guardas ativo`; registrar ruling 422 `nao_encontrado`; novas deferidas que os reviews levantarem)
- Modify: `docs/autorizacao-por-operacao.md` (corrigir a linha de `ClienteVerProprios` — `viagem.cliente_id` não existe, é `viagem_passageiro`; anotar `GET /viagens/semelhantes`, `GET /reservas/duplicada`, `POST /clientes`, `POST /fornecedores`; nota "`nao_encontrado` = 422 na v1")
- Modify: `docs/superpowers/plans/2026-09-08-fase-3-master.md` (linha 3.2: "(concluído)"; se `CalculoReserva` divergir do plano, atualizar)
- Modify: `CLAUDE.md` (linha Estado: 3.2 ✓, contagens)
- Modify: `regras-e-escopo-v2.md` (decisão 20: acrescentar "Exceção D1 (2026-09-09): criação inline mínima — nome + tipo — na Nova viagem")

**Depends-on:** T9

- [ ] **Step 1–2:** editar; controlador commita no root.

---

## Self-review (feito ao escrever)

- **Spec §3:** fornecedor por select + inline mínimo (D1) T2/T7 ✓ · `tipos_servico[]` T3/T6 ✓ · `viagem.tipo` T3/T8 ✓ · passageiros/titular único T3/T7 ✓ · `vendedor_id` obrigatório, `agente_id` T3 ✓.
- **§4.1/§4.2:** campos digitados T6 ✓ · pré-preenchimento comissão e taxa T8 ✓ · fórmulas: `CalculoReserva` (T1) + `calcularReserva` (T5) + equivalência com generated columns (T3 teste `Generated_columns_batem…`) ✓ · sem "tipo de receita" ✓.
- **§4.3:** `fluxo_pagamento` e `formas_pagamento[]` T3/T6 ✓ (movimentos são 3.5).
- **§4.5:** vigência por `data_compra` T3 `PrevisaoAsync` ✓ · gravada e mantida na edição salvo mudança de fornecedor/data T4 ✓.
- **§4.8:** `nfse_status` T3/T6 + mapa `nfse` T5 ✓.
- **§5:** repasse criado com a viagem, valor digitado, `bloqueado`/`a_pagar` por conciliação T3 `Rotinas` ✓ · troca de vendedor D5 T4 ✓.
- **§9:** pendências automáticas T3 ✓ · aviso de viagem duplicada com 3 saídas T4/T7/T8 ✓ · aviso de reserva duplicada T4/T8 ✓.
- **§14:** pré-preenchimento, inline pessoa/fornecedor, teclado (atalhos + listbox), salvar parcial (rascunho sem reserva T3), E2E cronometrado T9 ✓.
- **Contratos transversais:** referências validadas (`Guardas`), lock de viagem + versão, competência antes da viagem (T4), DTO por perfil (T3), datas `yyyy-MM-dd` (`DateOnly` + type map T1), arrays nunca null ✓.
- **Backlog "decidir em 3.2":** `ativo` em `ReferenciaAsync` → T1 ✓; 422 vs 404 → ruling 422 (T10 documenta) ✓; clamp `MoneyInput` → T5 ✓; `DateOnly` → T1 ✓; rota-guard por permissão → mantido "só esconde" (Global Constraints) ✓.
- **Placeholders:** nenhum "TBD"; T4 e T8 têm código-esqueleto com nomes definidos e regras explícitas; testes de T4/T7/T8 descritos com dados concretos.
- **Tipos:** `ReservaRequest`/`ViagemRequest`/DTOs iguais em C# (T3) e TS (T5); `reservaVazia/paraRequest/deDto` (T6) usados por T8; `somarReservas` (T7) usado por `TripSummary`; `useAtalho(combo, handler, ativo)` conforme 3.1; `Page.onSalvarESair` (T5) usado por T8 ✓.
- **Ondas:** T1 (Domain, Guardas, fixture, AddSessao) × T5 (frontend) disjuntos ✓ · T2 (Pessoas/Fornecedores/Agencia/Admin/Endpoints.cs) × T3 (Viagens/Endpoints.cs) — **colisão em `Modules/Endpoints.cs`**: T3 registra `ViagensService` e `MapViagensEndpoints`; T2 registra os outros três. Ruling: T2 e T3 na mesma onda **só** se um deles não tocar `Endpoints.cs`; para evitar, T3 inclui o registro e T2 **também** — mesmo arquivo → viola a regra. Decisão: **T2 fica na onda 0 com T1? não (usa fixture de T1)**. Solução: T2 entra na onda 1 e T3 na onda 2 junto de T6/T7? T6/T7 são front. Ordem final: onda 0 = T1, T5 · onda 1 = T2, T6, T7 · onda 2 = T3, T8? T8 depende dos contratos, não do código de T3 — aceitável, mas T8 não pode rodar E2E antes de T3/T4. Ordem final adotada: **onda 0 = T1, T5 · onda 1 = T2, T6, T7 · onda 2 = T3, T8 · onda 3 = T4 · onda 4 = T9 · onda 5 = T10.** A tabela "Ondas" acima fica substituída por esta.
