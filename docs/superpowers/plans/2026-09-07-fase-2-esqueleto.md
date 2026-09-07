# Meridiano — Fase 2 — Esqueleto da Solution: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execução em ondas:** este plano segue `.claude/rules/parallel-subagent-driven-development.md`. Cada task traz `Files:` e `Depends-on:`. Tasks da mesma onda têm arquivos disjuntos e não dependem uma da outra. **Implementadores não commitam** — deixam as mudanças na árvore de trabalho e reportam os arquivos tocados; o controlador commita uma task por vez, na ordem da onda, capturando o HEAD na hora.

**Goal:** Solution .NET 10 rodando contra Postgres com migrations, isolamento de tenant, autenticação própria, autorização por perfil, tratamento de erro padrão, jobs por linha de comando, CI — provada por um endpoint vertical de usuários com concorrência otimista.

**Architecture:** Monólito modular: `Meridiano.Api` (host, endpoints por módulo), `Meridiano.Domain` (regras puras), `Meridiano.Data` (migrations DbUp, sessão de banco com contexto de tenant). Toda transação abre com `set_config('app.agencia_id' …)`; policies RLS no Postgres são a rede de segurança sob o Dapper. `Program.cs` é escrito uma vez na Task 1 chamando extension methods stub; tasks posteriores preenchem os stubs nos próprios arquivos e nunca tocam `Program.cs`.

**Tech Stack:** .NET 10 LTS · ASP.NET Core Minimal API · Dapper · Npgsql · DbUp (dbup-postgresql) · Serilog · cookie auth + `PasswordHasher` (Microsoft.Extensions.Identity.Core) · xUnit · Testcontainers.PostgreSql · Docker · GitHub Actions.

**Spec:** `regras-e-escopo-v2.md` (§7 perfis, §8 controles, §11 stack) · `schema-agencia-v2.sql` · `docs/analise-arquitetural-v1.md` (A-01, A-03, A-05, A-08, A-10..A-13).

## Global Constraints

- Target `net10.0`, `Nullable` e `ImplicitUsings` ligados, `TreatWarningsAsErrors=true`.
- Três projetos de código (`Api`, `Domain`, `Data`) e dois de teste. Não criar mais.
- Sem EF Core, MediatR, AutoMapper, Repository, CQRS.
- Toda query Dapper de tabela de tenant roda dentro de `DbSessao` (que define `app.agencia_id`). Nunca abrir `NpgsqlConnection` direto fora de `DbSessao`, exceto login e migrations.
- Role do banco para a API: `meridiano_api` (sem ownership, sem BYPASSRLS). Migrations rodam com o owner (`meridiano` local / `postgres` no Supabase).
- Connection strings por configuração: `ConnectionStrings:Migrator` (owner) e `ConnectionStrings:Api` (meridiano_api). Segredos só por variável de ambiente.
- Enums do domínio serializam como `snake_case` igual ao banco (`dono`, `vendedor_externo`, `viagem.ver`).
- Erros: RFC 9457 ProblemDetails. `RegraDeNegocioException` → 422; `ConflitoConcorrenciaException` → 409; sem permissão → 403; não autenticado → 401.
- Pré-requisito de máquina: **Docker Desktop** (Testcontainers e Postgres local). Sem Docker, os testes de integração não rodam. CI (ubuntu-latest) já tem Docker.
- Commits em Conventional Commits (`feat:`, `test:`, `chore:`), com o rodapé de atribuição da sessão.

---

## Ondas

| Onda | Tasks | Motivo |
|---|---|---|
| 0 | T01 | Cria solution, `Program.cs` e todos os stubs |
| 1 | T02, T03, T04, T11 | Só dependem de T01; arquivos disjuntos |
| 2 | T05, T08 | Precisam das migrations e da fixture (T03) |
| 3 | T06, T10 | Auth precisa de sessão (T05) e domínio (T04); jobs precisam de sessão (T05) |
| 4 | T07, T09 | Autorização precisa de auth (T06); convite precisa de auth (T06) |
| 5 | T12 | Endpoint vertical usa tudo |

---

### Task 1: Solution, projetos, `Program.cs` e stubs

**Files:**
- Create: `.gitignore`, `.editorconfig`, `Directory.Build.props`, `Meridiano.sln`
- Create: `src/Meridiano.Domain/Meridiano.Domain.csproj`
- Create: `src/Meridiano.Data/Meridiano.Data.csproj`
- Create: `src/Meridiano.Api/Meridiano.Api.csproj`, `src/Meridiano.Api/Program.cs`, `src/Meridiano.Api/appsettings.json`
- Create: `src/Meridiano.Api/Infra/InfraExtensions.cs`, `src/Meridiano.Api/Data/MigrationsExtensions.cs`, `src/Meridiano.Api/Data/SessaoExtensions.cs`, `src/Meridiano.Api/Auth/AuthExtensions.cs`, `src/Meridiano.Api/Auth/AuthEndpoints.cs`, `src/Meridiano.Api/Auth/ConviteEndpoints.cs`, `src/Meridiano.Api/Jobs/JobsExtensions.cs`, `src/Meridiano.Api/Modules/Endpoints.cs`, `src/Meridiano.Api/Modules/Admin/AdminEndpoints.cs`
- Create: `tests/Meridiano.Domain.Tests/Meridiano.Domain.Tests.csproj`, `tests/Meridiano.Api.Tests/Meridiano.Api.Tests.csproj`

**Depends-on:** none

**Interfaces:**
- Produces: `Program` (partial, público para `WebApplicationFactory<Program>`); os stubs abaixo com exatamente estas assinaturas — tasks seguintes substituem o corpo, nunca a assinatura:
  - `InfraExtensions.AddInfra(this WebApplicationBuilder)`, `InfraExtensions.UseInfra(this WebApplication)`
  - `MigrationsExtensions.AddMigrations(this WebApplicationBuilder)`
  - `SessaoExtensions.AddSessao(this WebApplicationBuilder)`
  - `AuthExtensions.AddAuth(this WebApplicationBuilder)`, `AuthExtensions.UseAutenticacao(this WebApplication)`
  - `AuthEndpoints.MapAuthEndpoints(this IEndpointRouteBuilder)`, `ConviteEndpoints.MapConviteEndpoints(this IEndpointRouteBuilder)`
  - `JobsExtensions.AddJobs(this WebApplicationBuilder)`, `JobsExtensions.ExecutarJob(this WebApplication, string nome) : Task<int>`
  - `Endpoints.MapEndpoints(this WebApplication)`, `AdminEndpoints.MapAdminEndpoints(this IEndpointRouteBuilder)`

- [ ] **Step 1: `git init` e arquivos raiz**

```bash
cd E:/workspace/meridiano-erp && git init -b main
```

`.gitignore`:
```
bin/
obj/
*.user
.vs/
.idea/
TestResults/
node_modules/
web/dist/
src/Meridiano.Api/wwwroot/
.env
*.local.json
```

`.editorconfig`:
```
root = true
[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
insert_final_newline = true
[*.{json,yml,yaml,md,sql}]
indent_size = 2
[*.cs]
csharp_style_namespace_declarations = file_scoped:warning
```

`Directory.Build.props`:
```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <LangVersion>latest</LangVersion>
    <InvariantGlobalization>true</InvariantGlobalization>
  </PropertyGroup>
</Project>
```

- [ ] **Step 2: Projetos**

`src/Meridiano.Domain/Meridiano.Domain.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
</Project>
```

`src/Meridiano.Data/Meridiano.Data.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Dapper" Version="2.1.*" />
    <PackageReference Include="Npgsql" Version="10.0.*" />
    <PackageReference Include="dbup-postgresql" Version="6.*" />
  </ItemGroup>
  <ItemGroup>
    <EmbeddedResource Include="Migrations\*.sql" />
  </ItemGroup>
</Project>
```

`src/Meridiano.Api/Meridiano.Api.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <ItemGroup>
    <ProjectReference Include="..\Meridiano.Domain\Meridiano.Domain.csproj" />
    <ProjectReference Include="..\Meridiano.Data\Meridiano.Data.csproj" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="Dapper" Version="2.1.*" />
    <PackageReference Include="Npgsql" Version="10.0.*" />
    <PackageReference Include="Serilog.AspNetCore" Version="9.*" />
    <PackageReference Include="Microsoft.Extensions.Identity.Core" Version="10.0.*" />
  </ItemGroup>
</Project>
```

`tests/Meridiano.Domain.Tests/Meridiano.Domain.Tests.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><IsPackable>false</IsPackable></PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
    <PackageReference Include="xunit" Version="2.9.*" />
    <PackageReference Include="xunit.runner.visualstudio" Version="3.*" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Meridiano.Domain\Meridiano.Domain.csproj" />
  </ItemGroup>
</Project>
```

`tests/Meridiano.Api.Tests/Meridiano.Api.Tests.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><IsPackable>false</IsPackable></PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
    <PackageReference Include="xunit" Version="2.9.*" />
    <PackageReference Include="xunit.runner.visualstudio" Version="3.*" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.*" />
    <PackageReference Include="Testcontainers.PostgreSql" Version="4.*" />
    <PackageReference Include="Dapper" Version="2.1.*" />
    <PackageReference Include="Npgsql" Version="10.0.*" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Meridiano.Api\Meridiano.Api.csproj" />
  </ItemGroup>
</Project>
```

Solution:
```bash
dotnet new sln -n Meridiano
dotnet sln add src/Meridiano.Domain src/Meridiano.Data src/Meridiano.Api tests/Meridiano.Domain.Tests tests/Meridiano.Api.Tests
```

- [ ] **Step 3: `Program.cs` e `appsettings.json`**

`src/Meridiano.Api/Program.cs`:
```csharp
using Meridiano.Api.Auth;
using Meridiano.Api.Data;
using Meridiano.Api.Infra;
using Meridiano.Api.Jobs;
using Meridiano.Api.Modules;

var builder = WebApplication.CreateBuilder(args);

builder.AddInfra();
builder.AddMigrations();
builder.AddSessao();
builder.AddAuth();
builder.AddJobs();

var app = builder.Build();

app.UseInfra();
app.UseAutenticacao();
app.MapEndpoints();

if (args.Length >= 2 && args[0] == "job")
{
    return await app.ExecutarJob(args[1]);
}

await app.RunAsync();
return 0;

public partial class Program;
```

`src/Meridiano.Api/appsettings.json`:
```json
{
  "ConnectionStrings": {
    "Migrator": "",
    "Api": ""
  },
  "Serilog": {
    "MinimumLevel": { "Default": "Information", "Override": { "Microsoft.AspNetCore": "Warning" } }
  },
  "Auth": {
    "CookieNome": "meridiano_sessao",
    "ExpiracaoHoras": 12
  },
  "Email": {
    "ResendApiKey": "",
    "Remetente": "Meridiano <no-reply@example.com>",
    "BaseUrl": "http://localhost:5000"
  },
  "AllowedHosts": "*"
}
```

- [ ] **Step 4: Stubs**

Cada arquivo abaixo com o conteúdo exato (corpo vazio ou mínimo). Tasks seguintes substituem o corpo.

`src/Meridiano.Api/Infra/InfraExtensions.cs`:
```csharp
namespace Meridiano.Api.Infra;

public static class InfraExtensions
{
    public static WebApplicationBuilder AddInfra(this WebApplicationBuilder builder) => builder;
    public static WebApplication UseInfra(this WebApplication app) => app;
}
```

`src/Meridiano.Api/Data/MigrationsExtensions.cs`:
```csharp
namespace Meridiano.Api.Data;

public static class MigrationsExtensions
{
    public static WebApplicationBuilder AddMigrations(this WebApplicationBuilder builder) => builder;
}
```

`src/Meridiano.Api/Data/SessaoExtensions.cs`:
```csharp
namespace Meridiano.Api.Data;

public static class SessaoExtensions
{
    public static WebApplicationBuilder AddSessao(this WebApplicationBuilder builder) => builder;
}
```

`src/Meridiano.Api/Auth/AuthExtensions.cs`:
```csharp
namespace Meridiano.Api.Auth;

public static class AuthExtensions
{
    public static WebApplicationBuilder AddAuth(this WebApplicationBuilder builder) => builder;
    public static WebApplication UseAutenticacao(this WebApplication app) => app;
}
```

`src/Meridiano.Api/Auth/AuthEndpoints.cs`:
```csharp
namespace Meridiano.Api.Auth;

public static class AuthEndpoints
{
    public static IEndpointRouteBuilder MapAuthEndpoints(this IEndpointRouteBuilder app) => app;
}
```

`src/Meridiano.Api/Auth/ConviteEndpoints.cs`:
```csharp
namespace Meridiano.Api.Auth;

public static class ConviteEndpoints
{
    public static IEndpointRouteBuilder MapConviteEndpoints(this IEndpointRouteBuilder app) => app;
}
```

`src/Meridiano.Api/Jobs/JobsExtensions.cs`:
```csharp
namespace Meridiano.Api.Jobs;

public static class JobsExtensions
{
    public static WebApplicationBuilder AddJobs(this WebApplicationBuilder builder) => builder;
    public static Task<int> ExecutarJob(this WebApplication app, string nome) => Task.FromResult(1);
}
```

`src/Meridiano.Api/Modules/Admin/AdminEndpoints.cs`:
```csharp
namespace Meridiano.Api.Modules.Admin;

public static class AdminEndpoints
{
    public static IEndpointRouteBuilder MapAdminEndpoints(this IEndpointRouteBuilder app) => app;
}
```

`src/Meridiano.Api/Modules/Endpoints.cs`:
```csharp
using Meridiano.Api.Auth;
using Meridiano.Api.Modules.Admin;

namespace Meridiano.Api.Modules;

public static class Endpoints
{
    public static WebApplication MapEndpoints(this WebApplication app)
    {
        var api = app.MapGroup("/api/v1");
        api.MapAuthEndpoints();
        api.MapConviteEndpoints();
        api.MapAdminEndpoints();
        return app;
    }
}
```

- [ ] **Step 5: Build**

Run: `dotnet build`
Expected: `Build succeeded. 0 Warning(s) 0 Error(s)`

- [ ] **Step 6: Reportar arquivos tocados** (controlador commita: `chore: solution skeleton with program stubs`)

---

### Task 2: Postgres local via Docker Compose

**Files:**
- Create: `docker-compose.yml`, `scripts/postgres-init.sql`, `src/Meridiano.Api/appsettings.Development.json`, `docs/dev.md`

**Depends-on:** T01

**Interfaces:**
- Produces: banco local `meridiano` em `localhost:5432`, owner `meridiano`/`meridiano`, role `meridiano_api`/`meridiano_api`.

- [ ] **Step 1: Compose e init**

`docker-compose.yml`:
```yaml
services:
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: meridiano
      POSTGRES_PASSWORD: meridiano
      POSTGRES_DB: meridiano
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./scripts/postgres-init.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U meridiano -d meridiano"]
      interval: 5s
      timeout: 3s
      retries: 10
volumes:
  pgdata:
```

`scripts/postgres-init.sql`:
```sql
-- Role da API: sem ownership, sem BYPASSRLS. Grants vêm da migration 0002.
create role meridiano_api login password 'meridiano_api';
```

- [ ] **Step 2: Config de desenvolvimento**

`src/Meridiano.Api/appsettings.Development.json`:
```json
{
  "ConnectionStrings": {
    "Migrator": "Host=localhost;Port=5432;Database=meridiano;Username=meridiano;Password=meridiano",
    "Api": "Host=localhost;Port=5432;Database=meridiano;Username=meridiano_api;Password=meridiano_api"
  },
  "Serilog": { "MinimumLevel": { "Default": "Debug" } }
}
```

- [ ] **Step 3: `docs/dev.md`**

```markdown
# Desenvolvimento local

Pré-requisitos: .NET 10 SDK, Docker Desktop, Node 22 (front, fase 3).

    docker compose up -d          # Postgres 17 em localhost:5432
    dotnet run --project src/Meridiano.Api   # aplica migrations e sobe em http://localhost:5000
    dotnet test                   # Testcontainers sobe um Postgres próprio; não usa o compose

Roles: `meridiano` (owner, migrations) e `meridiano_api` (API, sujeita a RLS).
Zerar o banco: `docker compose down -v && docker compose up -d`.
Jobs: `dotnet run --project src/Meridiano.Api -- job ping`.
```

- [ ] **Step 4: Verificar**

Run: `docker compose up -d && docker compose exec postgres psql -U meridiano -d meridiano -c "\du meridiano_api"`
Expected: linha `meridiano_api` na lista de roles.

- [ ] **Step 5: Reportar arquivos** (commit: `chore: local postgres via docker compose`)

---

### Task 3: Migrations DbUp, fixture Testcontainers e factory da API

**Files:**
- Create: `src/Meridiano.Data/Migrations/0001_schema_v2.sql` (cópia exata de `schema-agencia-v2.sql`), `src/Meridiano.Data/Migrations/0002_grants_api.sql`, `src/Meridiano.Data/Migrator.cs`
- Modify: `src/Meridiano.Api/Data/MigrationsExtensions.cs`
- Create: `tests/Meridiano.Api.Tests/Fixtures/PostgresFixture.cs`, `tests/Meridiano.Api.Tests/Fixtures/MeridianoApiFactory.cs`, `tests/Meridiano.Api.Tests/Fixtures/DbCollection.cs`, `tests/Meridiano.Api.Tests/MigrationsTests.cs`

**Depends-on:** T01

**Interfaces:**
- Produces: `Meridiano.Data.Migrator.Aplicar(string connectionString)`; `PostgresFixture` com `ConnOwner`, `ConnApi`, `InserirAgenciaAsync(string nome) : Task<Guid>`, `InserirUsuarioAsync(Guid agenciaId, string email, string? senhaHash, string perfil, bool geraRepasse = false) : Task<Guid>`, `InserirClienteAsync(Guid agenciaId, string nome) : Task<Guid>`, `QueryOwnerAsync<T>(string sql, object? p = null)`; `MeridianoApiFactory(PostgresFixture)`; coleção xUnit `"db"`.

- [ ] **Step 1: Teste de migration (falha: `Migrator` não existe)**

`tests/Meridiano.Api.Tests/Fixtures/DbCollection.cs`:
```csharp
namespace Meridiano.Api.Tests.Fixtures;

[CollectionDefinition("db")]
public sealed class DbCollection : ICollectionFixture<PostgresFixture>;
```

`tests/Meridiano.Api.Tests/Fixtures/PostgresFixture.cs`:
```csharp
using Dapper;
using Npgsql;
using Testcontainers.PostgreSql;
using Meridiano.Data;

namespace Meridiano.Api.Tests.Fixtures;

public sealed class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder()
        .WithImage("postgres:17-alpine")
        .WithUsername("meridiano")
        .WithPassword("meridiano")
        .WithDatabase("meridiano")
        .Build();

    public string ConnOwner { get; private set; } = "";
    public string ConnApi { get; private set; } = "";

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        ConnOwner = _container.GetConnectionString();
        await using (var c = new NpgsqlConnection(ConnOwner))
        {
            await c.ExecuteAsync("create role meridiano_api login password 'meridiano_api'");
        }
        ConnApi = new NpgsqlConnectionStringBuilder(ConnOwner) { Username = "meridiano_api", Password = "meridiano_api" }.ToString();
        Migrator.Aplicar(ConnOwner);
    }

    public Task DisposeAsync() => _container.DisposeAsync().AsTask();

    // owner é superusuário no container: ignora RLS. Só para preparar dados de teste.
    public async Task<IEnumerable<T>> QueryOwnerAsync<T>(string sql, object? p = null)
    {
        await using var c = new NpgsqlConnection(ConnOwner);
        return await c.QueryAsync<T>(sql, p);
    }

    public async Task<Guid> InserirAgenciaAsync(string nome) =>
        (await QueryOwnerAsync<Guid>("insert into agencia (nome) values (@nome) returning id", new { nome })).Single();

    public async Task<Guid> InserirUsuarioAsync(Guid agenciaId, string email, string? senhaHash, string perfil, bool geraRepasse = false) =>
        (await QueryOwnerAsync<Guid>(
            "insert into usuario (agencia_id, nome, email, senha_hash, perfil, gera_repasse) values (@agenciaId, @email, @email, @senhaHash, @perfil, @geraRepasse) returning id",
            new { agenciaId, email, senhaHash, perfil, geraRepasse })).Single();

    public async Task<Guid> InserirClienteAsync(Guid agenciaId, string nome) =>
        (await QueryOwnerAsync<Guid>("insert into cliente (agencia_id, nome) values (@agenciaId, @nome) returning id", new { agenciaId, nome })).Single();
}
```

`tests/Meridiano.Api.Tests/Fixtures/MeridianoApiFactory.cs`:
```csharp
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Meridiano.Api.Tests.Fixtures;

public sealed class MeridianoApiFactory(PostgresFixture pg) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:Migrator", pg.ConnOwner);
        builder.UseSetting("ConnectionStrings:Api", pg.ConnApi);
    }
}
```

`tests/Meridiano.Api.Tests/MigrationsTests.cs`:
```csharp
using Meridiano.Api.Tests.Fixtures;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class MigrationsTests(PostgresFixture pg)
{
    [Fact]
    public async Task Schema_v2_aplicado_e_journal_registrado()
    {
        var tabelas = await pg.QueryOwnerAsync<string>(
            "select table_name from information_schema.tables where table_schema = 'public' and table_name in ('viagem','reserva','movimento_financeiro','repasse','schemaversions')");
        Assert.Equal(5, tabelas.Count());
    }

    [Fact]
    public async Task Role_meridiano_api_tem_grant_e_esta_sujeita_a_rls()
    {
        var bypass = await pg.QueryOwnerAsync<bool>("select rolbypassrls from pg_roles where rolname = 'meridiano_api'");
        Assert.False(bypass.Single());
        var grants = await pg.QueryOwnerAsync<int>(
            "select count(*) from information_schema.role_table_grants where grantee = 'meridiano_api' and table_name = 'reserva' and privilege_type = 'INSERT'");
        Assert.Equal(1, grants.Single());
    }
}
```

- [ ] **Step 2: Rodar (falha de compilação)**

Run: `dotnet test tests/Meridiano.Api.Tests`
Expected: erro `The type or namespace name 'Migrator' does not exist`.

- [ ] **Step 3: Migrations**

Copiar `schema-agencia-v2.sql` para `src/Meridiano.Data/Migrations/0001_schema_v2.sql` sem alterar.

`src/Meridiano.Data/Migrations/0002_grants_api.sql`:
```sql
-- Grants para a role da API, se ela existir neste ambiente.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'meridiano_api') then
    grant usage on schema public to meridiano_api;
    grant select, insert, update, delete on all tables in schema public to meridiano_api;
    grant usage, select on all sequences in schema public to meridiano_api;
    grant execute on all functions in schema public to meridiano_api;
    alter default privileges in schema public grant select, insert, update, delete on tables to meridiano_api;
    alter default privileges in schema public grant usage, select on sequences to meridiano_api;
    alter default privileges in schema public grant execute on functions to meridiano_api;
  end if;
end $$;
```

`src/Meridiano.Data/Migrator.cs`:
```csharp
using DbUp;

namespace Meridiano.Data;

public static class Migrator
{
    public static void Aplicar(string connectionString)
    {
        var upgrader = DeployChanges.To
            .PostgresqlDatabase(connectionString)
            .WithScriptsEmbeddedInAssembly(typeof(Migrator).Assembly, s => s.EndsWith(".sql", StringComparison.Ordinal))
            .WithTransactionPerScript()
            .LogToConsole()
            .Build();

        var resultado = upgrader.PerformUpgrade();
        if (!resultado.Successful)
        {
            throw new InvalidOperationException($"Migration falhou em {resultado.ErrorScript?.Name}", resultado.Error);
        }
    }
}
```

`src/Meridiano.Api/Data/MigrationsExtensions.cs`:
```csharp
using Meridiano.Data;

namespace Meridiano.Api.Data;

public static class MigrationsExtensions
{
    public static WebApplicationBuilder AddMigrations(this WebApplicationBuilder builder)
    {
        var cs = builder.Configuration.GetConnectionString("Migrator");
        if (!string.IsNullOrWhiteSpace(cs))
        {
            Migrator.Aplicar(cs);
        }
        return builder;
    }
}
```

- [ ] **Step 4: Rodar**

Run: `dotnet test tests/Meridiano.Api.Tests`
Expected: 2 passed.

- [ ] **Step 5: Reportar arquivos** (commit: `feat: dbup migrations with schema v2 and test fixture`)

---

### Task 4: Domínio — perfis, permissões e previsão de comissão

**Files:**
- Create: `src/Meridiano.Domain/Comum/Perfil.cs`, `src/Meridiano.Domain/Comum/Permissao.cs`, `src/Meridiano.Domain/Comum/Permissoes.cs`, `src/Meridiano.Domain/Financeiro/PrevisaoComissao.cs`
- Create: `tests/Meridiano.Domain.Tests/PermissoesTests.cs`, `tests/Meridiano.Domain.Tests/PrevisaoComissaoTests.cs`

**Depends-on:** T01

**Interfaces:**
- Produces: `enum Perfil { Dono, Financeiro, Agente, VendedorExterno, Contador }`; `Perfil.ParaBanco() : string` / `PerfilExtensions.DoBanco(string) : Perfil`; `enum Permissao`; `Permissoes.Do(Perfil) : IReadOnlySet<Permissao>`; `Permissao.Chave() : string` (ex.: `"viagem.ver"`); `PrevisaoComissao.Calcular(DateOnly dataCompra, IReadOnlyList<JanelaPagamento> janelas, int? prazoDias) : DateOnly`; `record JanelaPagamento(int DiaInicial, int DiaFinal, int DiaPagamento, int MesesAFrente)`.

- [ ] **Step 1: Testes (falham: tipos não existem)**

`tests/Meridiano.Domain.Tests/PermissoesTests.cs`:
```csharp
using Meridiano.Domain.Comum;

namespace Meridiano.Domain.Tests;

public sealed class PermissoesTests
{
    [Fact]
    public void Dono_tem_todas()
    {
        var todas = Enum.GetValues<Permissao>();
        Assert.Equal(todas.Length, Permissoes.Do(Perfil.Dono).Count);
    }

    [Fact]
    public void Vendedor_externo_so_ve_o_proprio()
    {
        var p = Permissoes.Do(Perfil.VendedorExterno);
        Assert.Equal([Permissao.ViagemVerProprias, Permissao.ClienteVerProprios], p.Order());
    }

    [Fact]
    public void Agente_nao_ve_resultado_nem_gerencia_usuarios()
    {
        var p = Permissoes.Do(Perfil.Agente);
        Assert.Contains(Permissao.ViagemCriar, p);
        Assert.Contains(Permissao.ReservaVerValores, p);
        Assert.DoesNotContain(Permissao.ViagemVerResultado, p);
        Assert.DoesNotContain(Permissao.UsuarioGerenciar, p);
    }

    [Fact]
    public void Contador_e_somente_leitura()
    {
        var p = Permissoes.Do(Perfil.Contador);
        Assert.Contains(Permissao.FinanceiroVerDre, p);
        Assert.DoesNotContain(Permissao.ViagemEditar, p);
        Assert.DoesNotContain(Permissao.FinanceiroMovimentar, p);
    }

    [Theory]
    [InlineData(Perfil.VendedorExterno, "vendedor_externo")]
    [InlineData(Perfil.Dono, "dono")]
    public void Perfil_serializa_snake_case(Perfil perfil, string esperado)
    {
        Assert.Equal(esperado, perfil.ParaBanco());
        Assert.Equal(perfil, PerfilExtensions.DoBanco(esperado));
    }

    [Fact]
    public void Chave_da_permissao_e_modulo_ponto_acao()
    {
        Assert.Equal("viagem.ver_resultado", Permissao.ViagemVerResultado.Chave());
        Assert.Equal("usuario.gerenciar", Permissao.UsuarioGerenciar.Chave());
    }
}
```

`tests/Meridiano.Domain.Tests/PrevisaoComissaoTests.cs`:
```csharp
using Meridiano.Domain.Financeiro;

namespace Meridiano.Domain.Tests;

public sealed class PrevisaoComissaoTests
{
    private static readonly JanelaPagamento[] Janelas =
    [
        new(1, 14, 20, 0),   // vendas de 1 a 14 pagam dia 20 do mesmo mês
        new(15, 31, 5, 1),   // vendas de 15 a 31 pagam dia 5 do mês seguinte
    ];

    [Fact]
    public void Primeira_quinzena_paga_dia_20_do_mesmo_mes() =>
        Assert.Equal(new DateOnly(2026, 3, 20), PrevisaoComissao.Calcular(new DateOnly(2026, 3, 10), Janelas, null));

    [Fact]
    public void Segunda_quinzena_paga_dia_5_do_mes_seguinte() =>
        Assert.Equal(new DateOnly(2026, 4, 5), PrevisaoComissao.Calcular(new DateOnly(2026, 3, 20), Janelas, null));

    [Fact]
    public void Virada_de_ano() =>
        Assert.Equal(new DateOnly(2027, 1, 5), PrevisaoComissao.Calcular(new DateOnly(2026, 12, 31), Janelas, null));

    [Fact]
    public void Dia_de_pagamento_inexistente_vai_para_ultimo_dia_do_mes()
    {
        JanelaPagamento[] j = [new(1, 31, 31, 1)];
        Assert.Equal(new DateOnly(2026, 2, 28), PrevisaoComissao.Calcular(new DateOnly(2026, 1, 31), j, null));
    }

    [Fact]
    public void Sem_janela_usa_prazo_em_dias() =>
        Assert.Equal(new DateOnly(2026, 4, 24), PrevisaoComissao.Calcular(new DateOnly(2026, 3, 10), [], 45));

    [Fact]
    public void Sem_janela_e_sem_prazo_usa_30_dias() =>
        Assert.Equal(new DateOnly(2026, 4, 9), PrevisaoComissao.Calcular(new DateOnly(2026, 3, 10), [], null));
}
```

- [ ] **Step 2: Rodar (falha de compilação)**

Run: `dotnet test tests/Meridiano.Domain.Tests`
Expected: erros `The type or namespace name 'Permissao' does not exist`.

- [ ] **Step 3: Implementação**

`src/Meridiano.Domain/Comum/Perfil.cs`:
```csharp
namespace Meridiano.Domain.Comum;

public enum Perfil
{
    Dono,
    Financeiro,
    Agente,
    VendedorExterno,
    Contador,
}

public static class PerfilExtensions
{
    public static string ParaBanco(this Perfil perfil) => perfil switch
    {
        Perfil.Dono => "dono",
        Perfil.Financeiro => "financeiro",
        Perfil.Agente => "agente",
        Perfil.VendedorExterno => "vendedor_externo",
        Perfil.Contador => "contador",
        _ => throw new ArgumentOutOfRangeException(nameof(perfil)),
    };

    public static Perfil DoBanco(string valor) => valor switch
    {
        "dono" => Perfil.Dono,
        "financeiro" => Perfil.Financeiro,
        "agente" => Perfil.Agente,
        "vendedor_externo" => Perfil.VendedorExterno,
        "contador" => Perfil.Contador,
        _ => throw new ArgumentOutOfRangeException(nameof(valor), valor, "perfil desconhecido"),
    };
}
```

`src/Meridiano.Domain/Comum/Permissao.cs`:
```csharp
namespace Meridiano.Domain.Comum;

public enum Permissao
{
    ViagemVer,
    ViagemVerProprias,
    ViagemCriar,
    ViagemEditar,
    ViagemExcluir,
    ViagemDefinirVendedor,
    ViagemTransferir,
    ViagemVerResultado,
    ReservaVerValores,
    ClienteVer,
    ClienteVerProprios,
    ClienteEditar,
    ClienteVerDocumento,
    FornecedorEditar,
    FinanceiroMovimentar,
    FinanceiroConciliar,
    FinanceiroFecharPeriodo,
    FinanceiroEditarPeriodoFechado,
    FinanceiroVerDre,
    RepasseVerTodos,
    RepassePagar,
    RelatorioVer,
    AnexoEnviar,
    UsuarioGerenciar,
    AuditoriaVer,
}

public static class PermissaoExtensions
{
    public static string Chave(this Permissao p) => p switch
    {
        Permissao.ViagemVer => "viagem.ver",
        Permissao.ViagemVerProprias => "viagem.ver_proprias",
        Permissao.ViagemCriar => "viagem.criar",
        Permissao.ViagemEditar => "viagem.editar",
        Permissao.ViagemExcluir => "viagem.excluir",
        Permissao.ViagemDefinirVendedor => "viagem.definir_vendedor",
        Permissao.ViagemTransferir => "viagem.transferir",
        Permissao.ViagemVerResultado => "viagem.ver_resultado",
        Permissao.ReservaVerValores => "reserva.ver_valores",
        Permissao.ClienteVer => "cliente.ver",
        Permissao.ClienteVerProprios => "cliente.ver_proprios",
        Permissao.ClienteEditar => "cliente.editar",
        Permissao.ClienteVerDocumento => "cliente.ver_documento",
        Permissao.FornecedorEditar => "fornecedor.editar",
        Permissao.FinanceiroMovimentar => "financeiro.movimentar",
        Permissao.FinanceiroConciliar => "financeiro.conciliar",
        Permissao.FinanceiroFecharPeriodo => "financeiro.fechar_periodo",
        Permissao.FinanceiroEditarPeriodoFechado => "financeiro.editar_periodo_fechado",
        Permissao.FinanceiroVerDre => "financeiro.ver_dre",
        Permissao.RepasseVerTodos => "repasse.ver_todos",
        Permissao.RepassePagar => "repasse.pagar",
        Permissao.RelatorioVer => "relatorio.ver",
        Permissao.AnexoEnviar => "anexo.enviar",
        Permissao.UsuarioGerenciar => "usuario.gerenciar",
        Permissao.AuditoriaVer => "auditoria.ver",
        _ => throw new ArgumentOutOfRangeException(nameof(p)),
    };
}
```

`src/Meridiano.Domain/Comum/Permissoes.cs`:
```csharp
namespace Meridiano.Domain.Comum;

// Matriz fixa da v1 (regras-e-escopo-v2 §7.1). Vira tabela quando uma agência precisar de perfil customizado.
public static class Permissoes
{
    private static readonly IReadOnlySet<Permissao> Todas = Enum.GetValues<Permissao>().ToHashSet();

    private static readonly IReadOnlySet<Permissao> FinanceiroSet = new HashSet<Permissao>
    {
        Permissao.ViagemVer, Permissao.ReservaVerValores, Permissao.ViagemVerResultado, Permissao.ClienteVer,
        Permissao.FinanceiroMovimentar, Permissao.FinanceiroConciliar, Permissao.FinanceiroFecharPeriodo,
        Permissao.FinanceiroEditarPeriodoFechado, Permissao.FinanceiroVerDre,
        Permissao.RepasseVerTodos, Permissao.RepassePagar, Permissao.RelatorioVer, Permissao.AuditoriaVer,
    };

    private static readonly IReadOnlySet<Permissao> AgenteSet = new HashSet<Permissao>
    {
        Permissao.ViagemVer, Permissao.ViagemCriar, Permissao.ViagemEditar, Permissao.ViagemDefinirVendedor,
        Permissao.ReservaVerValores, Permissao.ClienteVer, Permissao.ClienteEditar, Permissao.ClienteVerDocumento,
        Permissao.FornecedorEditar, Permissao.AnexoEnviar,
    };

    private static readonly IReadOnlySet<Permissao> VendedorExternoSet = new HashSet<Permissao>
    {
        Permissao.ViagemVerProprias, Permissao.ClienteVerProprios,
    };

    private static readonly IReadOnlySet<Permissao> ContadorSet = new HashSet<Permissao>
    {
        Permissao.ViagemVer, Permissao.ReservaVerValores, Permissao.ViagemVerResultado,
        Permissao.FinanceiroVerDre, Permissao.RelatorioVer, Permissao.AuditoriaVer,
    };

    public static IReadOnlySet<Permissao> Do(Perfil perfil) => perfil switch
    {
        Perfil.Dono => Todas,
        Perfil.Financeiro => FinanceiroSet,
        Perfil.Agente => AgenteSet,
        Perfil.VendedorExterno => VendedorExternoSet,
        Perfil.Contador => ContadorSet,
        _ => throw new ArgumentOutOfRangeException(nameof(perfil)),
    };
}
```

`src/Meridiano.Domain/Financeiro/PrevisaoComissao.cs`:
```csharp
namespace Meridiano.Domain.Financeiro;

public sealed record JanelaPagamento(int DiaInicial, int DiaFinal, int DiaPagamento, int MesesAFrente);

public static class PrevisaoComissao
{
    private const int PrazoPadraoDias = 30;

    public static DateOnly Calcular(DateOnly dataCompra, IReadOnlyList<JanelaPagamento> janelas, int? prazoDias)
    {
        var janela = janelas.FirstOrDefault(j => dataCompra.Day >= j.DiaInicial && dataCompra.Day <= j.DiaFinal);
        if (janela is null)
        {
            return dataCompra.AddDays(prazoDias ?? PrazoPadraoDias);
        }

        var mes = new DateOnly(dataCompra.Year, dataCompra.Month, 1).AddMonths(janela.MesesAFrente);
        var dia = Math.Min(janela.DiaPagamento, DateTime.DaysInMonth(mes.Year, mes.Month));
        return new DateOnly(mes.Year, mes.Month, dia);
    }
}
```

- [ ] **Step 4: Rodar**

Run: `dotnet test tests/Meridiano.Domain.Tests`
Expected: 12 passed.

- [ ] **Step 5: Reportar arquivos** (commit: `feat(domain): perfis, permissoes e previsao de comissao`)

---

### Task 5: `DbSessao` com contexto de tenant + prova de RLS

**Files:**
- Create: `src/Meridiano.Data/Sessao/ContextoSessao.cs`, `src/Meridiano.Data/Sessao/DbSessao.cs`, `src/Meridiano.Data/Sessao/DbSessaoFactory.cs`
- Modify: `src/Meridiano.Api/Data/SessaoExtensions.cs`
- Create: `tests/Meridiano.Api.Tests/SessaoTests.cs`

**Depends-on:** T03

**Interfaces:**
- Produces: `record ContextoSessao(Guid AgenciaId, Guid? UsuarioId, string? Motivo)`; `DbSessaoFactory(string connectionString)` com `AbrirAsync(ContextoSessao, CancellationToken) : Task<DbSessao>`; `DbSessao : IAsyncDisposable` com `NpgsqlConnection Conexao`, `NpgsqlTransaction Transacao`, `ConfirmarAsync(CancellationToken)`; registrada como singleton no DI.

- [ ] **Step 1: Teste (falha: tipos não existem)**

`tests/Meridiano.Api.Tests/SessaoTests.cs`:
```csharp
using Dapper;
using Npgsql;
using Meridiano.Api.Tests.Fixtures;
using Meridiano.Data.Sessao;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class SessaoTests(PostgresFixture pg)
{
    [Fact]
    public async Task Sessao_so_enxerga_a_propria_agencia()
    {
        var a = await pg.InserirAgenciaAsync("A");
        var b = await pg.InserirAgenciaAsync("B");
        await pg.InserirClienteAsync(a, "Cliente de A");
        await pg.InserirClienteAsync(b, "Cliente de B");

        var factory = new DbSessaoFactory(pg.ConnApi);
        await using var sessao = await factory.AbrirAsync(new ContextoSessao(a, null, null), CancellationToken.None);

        var nomes = await sessao.Conexao.QueryAsync<string>("select nome from cliente", transaction: sessao.Transacao);
        Assert.Equal(["Cliente de A"], nomes);
    }

    [Fact]
    public async Task Insert_em_outra_agencia_e_rejeitado_pela_policy()
    {
        var a = await pg.InserirAgenciaAsync("A2");
        var b = await pg.InserirAgenciaAsync("B2");

        var factory = new DbSessaoFactory(pg.ConnApi);
        await using var sessao = await factory.AbrirAsync(new ContextoSessao(a, null, null), CancellationToken.None);

        var ex = await Assert.ThrowsAsync<PostgresException>(() => sessao.Conexao.ExecuteAsync(
            "insert into cliente (agencia_id, nome) values (@b, 'intruso')", new { b }, sessao.Transacao));
        Assert.Equal("42501", ex.SqlState); // insufficient_privilege: new row violates row-level security policy
    }

    [Fact]
    public async Task Sem_contexto_a_role_da_api_nao_ve_nada()
    {
        var a = await pg.InserirAgenciaAsync("A3");
        await pg.InserirClienteAsync(a, "Escondido");

        await using var c = new NpgsqlConnection(pg.ConnApi);
        var total = await c.ExecuteScalarAsync<long>("select count(*) from cliente");
        Assert.Equal(0, total);
    }

    [Fact]
    public async Task Confirmar_persiste_e_dispose_sem_confirmar_desfaz()
    {
        var a = await pg.InserirAgenciaAsync("A4");
        var factory = new DbSessaoFactory(pg.ConnApi);

        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), CancellationToken.None))
        {
            await s.Conexao.ExecuteAsync("insert into cliente (agencia_id, nome) values (@a, 'descartado')", new { a }, s.Transacao);
        }
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), CancellationToken.None))
        {
            await s.Conexao.ExecuteAsync("insert into cliente (agencia_id, nome) values (@a, 'gravado')", new { a }, s.Transacao);
            await s.ConfirmarAsync(CancellationToken.None);
        }

        var nomes = await pg.QueryOwnerAsync<string>("select nome from cliente where agencia_id = @a", new { a });
        Assert.Equal(["gravado"], nomes);
    }
}
```

- [ ] **Step 2: Rodar (falha de compilação)**

Run: `dotnet test tests/Meridiano.Api.Tests --filter SessaoTests`
Expected: `'DbSessaoFactory' could not be found`.

- [ ] **Step 3: Implementação**

`src/Meridiano.Data/Sessao/ContextoSessao.cs`:
```csharp
namespace Meridiano.Data.Sessao;

public sealed record ContextoSessao(Guid AgenciaId, Guid? UsuarioId, string? Motivo);
```

`src/Meridiano.Data/Sessao/DbSessao.cs`:
```csharp
using Npgsql;

namespace Meridiano.Data.Sessao;

public sealed class DbSessao(NpgsqlConnection conexao, NpgsqlTransaction transacao) : IAsyncDisposable
{
    private bool _confirmada;

    public NpgsqlConnection Conexao { get; } = conexao;
    public NpgsqlTransaction Transacao { get; } = transacao;

    public async Task ConfirmarAsync(CancellationToken ct)
    {
        await Transacao.CommitAsync(ct);
        _confirmada = true;
    }

    public async ValueTask DisposeAsync()
    {
        if (!_confirmada)
        {
            await Transacao.RollbackAsync();
        }
        await Transacao.DisposeAsync();
        await Conexao.DisposeAsync();
    }
}
```

`src/Meridiano.Data/Sessao/DbSessaoFactory.cs`:
```csharp
using Dapper;
using Npgsql;

namespace Meridiano.Data.Sessao;

public sealed class DbSessaoFactory(string connectionString)
{
    // set_config(..., true) = local à transação. As policies RLS leem app.agencia_id;
    // o trigger de auditoria lê app.usuario_id e app.motivo.
    private const string SqlContexto =
        "select set_config('app.agencia_id', @agencia, true), set_config('app.usuario_id', @usuario, true), set_config('app.motivo', @motivo, true)";

    public async Task<DbSessao> AbrirAsync(ContextoSessao ctx, CancellationToken ct)
    {
        var conexao = new NpgsqlConnection(connectionString);
        await conexao.OpenAsync(ct);
        var transacao = await conexao.BeginTransactionAsync(ct);
        await conexao.ExecuteAsync(new CommandDefinition(SqlContexto, new
        {
            agencia = ctx.AgenciaId.ToString(),
            usuario = ctx.UsuarioId?.ToString() ?? "",
            motivo = ctx.Motivo ?? "",
        }, transacao, cancellationToken: ct));
        return new DbSessao(conexao, transacao);
    }
}
```

`src/Meridiano.Api/Data/SessaoExtensions.cs`:
```csharp
using Meridiano.Data.Sessao;

namespace Meridiano.Api.Data;

public static class SessaoExtensions
{
    public static WebApplicationBuilder AddSessao(this WebApplicationBuilder builder)
    {
        var cs = builder.Configuration.GetConnectionString("Api")
                 ?? throw new InvalidOperationException("ConnectionStrings:Api não configurada");
        builder.Services.AddSingleton(new DbSessaoFactory(cs));
        return builder;
    }
}
```

- [ ] **Step 4: Rodar**

Run: `dotnet test tests/Meridiano.Api.Tests --filter SessaoTests`
Expected: 4 passed.

- [ ] **Step 5: Reportar arquivos** (commit: `feat(data): DbSessao com contexto de tenant e prova de RLS`)

---

### Task 6: Autenticação própria — login por cookie, `/me`, logout

**Files:**
- Modify: `src/Meridiano.Api/Auth/AuthExtensions.cs`, `src/Meridiano.Api/Auth/AuthEndpoints.cs`
- Create: `src/Meridiano.Api/Auth/SenhaHasher.cs`, `src/Meridiano.Api/Auth/UsuarioAtual.cs`, `src/Meridiano.Api/Auth/LoginService.cs`
- Create: `tests/Meridiano.Api.Tests/AuthTests.cs`

**Depends-on:** T04, T05

**Interfaces:**
- Consumes: `DbSessaoFactory`, `ContextoSessao`, `Perfil`, `PerfilExtensions.DoBanco`.
- Produces: `SenhaHasher.Hash(string) : string`, `SenhaHasher.Confere(string hash, string senha) : bool`; `record UsuarioAtual(Guid UsuarioId, Guid AgenciaId, Perfil Perfil, string Nome)`; `UsuarioAtualExtensions.UsuarioAtual(this HttpContext) : UsuarioAtual` (lança `UnauthorizedAccessException` se ausente) e `UsuarioAtualExtensions.Contexto(this HttpContext, string? motivo = null) : ContextoSessao`; `LoginService.LoginAsync(string email, string senha, string? ip, CancellationToken) : Task<UsuarioAtual?>`; endpoints `POST /api/v1/auth/login`, `GET /api/v1/auth/me`, `POST /api/v1/auth/logout`; cookie `meridiano_sessao`; claims `sub`, `agencia_id`, `perfil`, `name`.

- [ ] **Step 1: Teste (falha)**

`tests/Meridiano.Api.Tests/AuthTests.cs`:
```csharp
using System.Net;
using System.Net.Http.Json;
using Meridiano.Api.Auth;
using Meridiano.Api.Tests.Fixtures;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class AuthTests(PostgresFixture pg)
{
    private sealed record MeResposta(Guid UsuarioId, Guid AgenciaId, string Perfil, string Nome);

    [Fact]
    public async Task Login_correto_gera_cookie_e_me_retorna_claims()
    {
        var agencia = await pg.InserirAgenciaAsync("Auth A");
        var usuarioId = await pg.InserirUsuarioAsync(agencia, "dono@auth.com", SenhaHasher.Hash("segredo123"), "dono");

        await using var app = new MeridianoApiFactory(pg);
        var client = app.CreateClient();

        var login = await client.PostAsJsonAsync("/api/v1/auth/login", new { email = "dono@auth.com", senha = "segredo123" });
        Assert.Equal(HttpStatusCode.NoContent, login.StatusCode);
        Assert.Contains(login.Headers.GetValues("Set-Cookie"), h => h.StartsWith("meridiano_sessao=", StringComparison.Ordinal));

        var me = await client.GetFromJsonAsync<MeResposta>("/api/v1/auth/me");
        Assert.NotNull(me);
        Assert.Equal(usuarioId, me.UsuarioId);
        Assert.Equal(agencia, me.AgenciaId);
        Assert.Equal("dono", me.Perfil);

        var ultimo = await pg.QueryOwnerAsync<DateTime?>("select ultimo_login_em from usuario where id = @usuarioId", new { usuarioId });
        Assert.NotNull(ultimo.Single());
    }

    [Fact]
    public async Task Senha_errada_e_401_e_registra_log_de_acesso()
    {
        var agencia = await pg.InserirAgenciaAsync("Auth B");
        await pg.InserirUsuarioAsync(agencia, "x@auth.com", SenhaHasher.Hash("certa"), "agente");

        await using var app = new MeridianoApiFactory(pg);
        var client = app.CreateClient();

        var r = await client.PostAsJsonAsync("/api/v1/auth/login", new { email = "x@auth.com", senha = "errada" });
        Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode);

        var falhas = await pg.QueryOwnerAsync<long>("select count(*) from log_acesso where email = 'x@auth.com' and not sucesso");
        Assert.Equal(1, falhas.Single());
    }

    [Fact]
    public async Task Usuario_sem_senha_nao_loga()
    {
        var agencia = await pg.InserirAgenciaAsync("Auth C");
        await pg.InserirUsuarioAsync(agencia, "semlogin@auth.com", null, "vendedor_externo");

        await using var app = new MeridianoApiFactory(pg);
        var r = await app.CreateClient().PostAsJsonAsync("/api/v1/auth/login", new { email = "semlogin@auth.com", senha = "qualquer" });
        Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode);
    }

    [Fact]
    public async Task Me_sem_cookie_e_401_e_logout_invalida()
    {
        var agencia = await pg.InserirAgenciaAsync("Auth D");
        await pg.InserirUsuarioAsync(agencia, "d@auth.com", SenhaHasher.Hash("s"), "dono");

        await using var app = new MeridianoApiFactory(pg);
        var client = app.CreateClient();

        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/auth/me")).StatusCode);

        await client.PostAsJsonAsync("/api/v1/auth/login", new { email = "d@auth.com", senha = "s" });
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/auth/me")).StatusCode);

        await client.PostAsync("/api/v1/auth/logout", null);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/auth/me")).StatusCode);
    }
}
```

- [ ] **Step 2: Rodar (falha de compilação)**

Run: `dotnet test tests/Meridiano.Api.Tests --filter AuthTests`
Expected: `'SenhaHasher' could not be found`.

- [ ] **Step 3: Implementação**

`src/Meridiano.Api/Auth/SenhaHasher.cs`:
```csharp
using Microsoft.AspNetCore.Identity;

namespace Meridiano.Api.Auth;

// Só o hasher do Identity (PBKDF2), sem as tabelas do Identity.
public static class SenhaHasher
{
    private static readonly PasswordHasher<object> Hasher = new();
    private static readonly object Dummy = new();

    public static string Hash(string senha) => Hasher.HashPassword(Dummy, senha);

    public static bool Confere(string hash, string senha) =>
        Hasher.VerifyHashedPassword(Dummy, hash, senha) is PasswordVerificationResult.Success or PasswordVerificationResult.SuccessRehashNeeded;
}
```

`src/Meridiano.Api/Auth/UsuarioAtual.cs`:
```csharp
using System.Security.Claims;
using Meridiano.Data.Sessao;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Auth;

public sealed record UsuarioAtual(Guid UsuarioId, Guid AgenciaId, Perfil Perfil, string Nome)
{
    public const string ClaimAgencia = "agencia_id";
    public const string ClaimPerfil = "perfil";

    public ClaimsPrincipal ParaPrincipal(string scheme) => new(new ClaimsIdentity(
    [
        new Claim(ClaimTypes.NameIdentifier, UsuarioId.ToString()),
        new Claim(ClaimTypes.Name, Nome),
        new Claim(ClaimAgencia, AgenciaId.ToString()),
        new Claim(ClaimPerfil, Perfil.ParaBanco()),
    ], scheme));

    public static UsuarioAtual? De(ClaimsPrincipal principal)
    {
        var id = principal.FindFirstValue(ClaimTypes.NameIdentifier);
        var agencia = principal.FindFirstValue(ClaimAgencia);
        var perfil = principal.FindFirstValue(ClaimPerfil);
        if (id is null || agencia is null || perfil is null) return null;
        return new UsuarioAtual(Guid.Parse(id), Guid.Parse(agencia), PerfilExtensions.DoBanco(perfil), principal.Identity?.Name ?? "");
    }
}

public static class UsuarioAtualExtensions
{
    public static UsuarioAtual UsuarioAtual(this HttpContext http) =>
        Auth.UsuarioAtual.De(http.User) ?? throw new UnauthorizedAccessException("sem usuário autenticado");

    public static ContextoSessao Contexto(this HttpContext http, string? motivo = null)
    {
        var u = http.UsuarioAtual();
        return new ContextoSessao(u.AgenciaId, u.UsuarioId, motivo);
    }
}
```

`src/Meridiano.Api/Auth/LoginService.cs`:
```csharp
using Dapper;
using Npgsql;
using Meridiano.Data.Sessao;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Auth;

public sealed class LoginService(DbSessaoFactory sessoes, IConfiguration config)
{
    private sealed record LinhaLogin(Guid Id, Guid AgenciaId, string SenhaHash, string Perfil, bool Ativo);

    // Antes do login não há app.agencia_id: usa a função security definer do schema.
    public async Task<UsuarioAtual?> LoginAsync(string email, string senha, string? ip, CancellationToken ct)
    {
        var cs = config.GetConnectionString("Api")!;
        await using var conexao = new NpgsqlConnection(cs);
        await conexao.OpenAsync(ct);

        var linha = await conexao.QuerySingleOrDefaultAsync<LinhaLogin>(
            "select id, agencia_id as AgenciaId, senha_hash as SenhaHash, perfil, ativo from localizar_usuario_login(@email)",
            new { email });

        var ok = linha is { Ativo: true } && SenhaHasher.Confere(linha.SenhaHash, senha);

        await conexao.ExecuteAsync(
            "insert into log_acesso (agencia_id, usuario_id, email, sucesso, ip) values (@agencia, @usuario, @email, @ok, @ip)",
            new { agencia = linha?.AgenciaId, usuario = linha?.Id, email, ok, ip });

        if (!ok) return null;

        string nome;
        await using (var s = await sessoes.AbrirAsync(new ContextoSessao(linha!.AgenciaId, linha.Id, null), ct))
        {
            nome = await s.Conexao.ExecuteScalarAsync<string>(
                "update usuario set ultimo_login_em = now() where id = @id returning nome", new { id = linha.Id }, s.Transacao) ?? "";
            await s.ConfirmarAsync(ct);
        }

        return new UsuarioAtual(linha.Id, linha.AgenciaId, PerfilExtensions.DoBanco(linha.Perfil), nome);
    }
}
```

`src/Meridiano.Api/Auth/AuthExtensions.cs`:
```csharp
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.RateLimiting;

namespace Meridiano.Api.Auth;

public static class AuthExtensions
{
    public const string PoliticaLogin = "login";

    public static WebApplicationBuilder AddAuth(this WebApplicationBuilder builder)
    {
        var nomeCookie = builder.Configuration["Auth:CookieNome"] ?? "meridiano_sessao";
        var horas = int.TryParse(builder.Configuration["Auth:ExpiracaoHoras"], out var h) ? h : 12;

        builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
            .AddCookie(o =>
            {
                o.Cookie.Name = nomeCookie;
                o.Cookie.HttpOnly = true;
                o.Cookie.SameSite = SameSiteMode.Strict;
                o.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
                o.ExpireTimeSpan = TimeSpan.FromHours(horas);
                o.SlidingExpiration = true;
                // API: nunca redireciona para página de login
                o.Events.OnRedirectToLogin = ctx => { ctx.Response.StatusCode = StatusCodes.Status401Unauthorized; return Task.CompletedTask; };
                o.Events.OnRedirectToAccessDenied = ctx => { ctx.Response.StatusCode = StatusCodes.Status403Forbidden; return Task.CompletedTask; };
            });
        builder.Services.AddAuthorization();

        builder.Services.AddRateLimiter(o =>
        {
            o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            o.AddPolicy(PoliticaLogin, http => RateLimitPartition.GetFixedWindowLimiter(
                http.Connection.RemoteIpAddress?.ToString() ?? "anon",
                _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1) }));
        });

        builder.Services.AddScoped<LoginService>();
        return builder;
    }

    public static WebApplication UseAutenticacao(this WebApplication app)
    {
        app.UseRateLimiter();
        app.UseAuthentication();
        app.UseAuthorization();
        return app;
    }
}
```

`src/Meridiano.Api/Auth/AuthEndpoints.cs`:
```csharp
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace Meridiano.Api.Auth;

public static class AuthEndpoints
{
    public sealed record LoginRequest(string Email, string Senha);
    public sealed record MeResponse(Guid UsuarioId, Guid AgenciaId, string Perfil, string Nome);

    public static IEndpointRouteBuilder MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/auth");

        g.MapPost("/login", async (LoginRequest req, HttpContext http, LoginService login, CancellationToken ct) =>
        {
            var usuario = await login.LoginAsync(req.Email.Trim(), req.Senha, http.Connection.RemoteIpAddress?.ToString(), ct);
            if (usuario is null) return Results.Unauthorized();
            await http.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, usuario.ParaPrincipal(CookieAuthenticationDefaults.AuthenticationScheme));
            return Results.NoContent();
        }).RequireRateLimiting(AuthExtensions.PoliticaLogin).AllowAnonymous();

        g.MapGet("/me", (HttpContext http) =>
        {
            var u = http.UsuarioAtual();
            return Results.Ok(new MeResponse(u.UsuarioId, u.AgenciaId, u.Perfil.ParaBanco(), u.Nome));
        }).RequireAuthorization();

        g.MapPost("/logout", async (HttpContext http) =>
        {
            await http.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            return Results.NoContent();
        }).RequireAuthorization();

        return app;
    }
}
```

Adicionar `using Meridiano.Domain.Comum;` em `AuthEndpoints.cs` (para `ParaBanco`).

- [ ] **Step 4: Rodar**

Run: `dotnet test tests/Meridiano.Api.Tests --filter AuthTests`
Expected: 4 passed.

- [ ] **Step 5: Reportar arquivos** (commit: `feat(auth): login por cookie, me e logout`)

---

### Task 7: Autorização por permissão (`RequerPermissao`)

**Files:**
- Create: `src/Meridiano.Api/Auth/Autorizacao.cs`, `src/Meridiano.Api/Infra/DevEndpoints.cs`
- Create: `tests/Meridiano.Api.Tests/AutorizacaoTests.cs`

**Depends-on:** T06, T08

**Interfaces:**
- Consumes: `UsuarioAtual`, `Permissoes.Do`, `ProblemDetails` de T08.
- Produces: `Autorizacao.RequerPermissao<TBuilder>(this TBuilder, Permissao) : TBuilder where TBuilder : IEndpointConventionBuilder` (filtro que devolve 403 ProblemDetails com `codigo = "sem_permissao"`); `DevEndpoints.MapDevEndpoints(this IEndpointRouteBuilder)` mapeando `GET /api/v1/_dev/protegido` (requer `UsuarioGerenciar`) e `GET /api/v1/_dev/erro/{tipo}` (T08 usa) — **registrado dentro de `UseInfra` (T08) só em Development/Testing**; T08 cria `DevEndpoints.cs` com o endpoint de erro e esta task **adiciona** o endpoint protegido no mesmo arquivo. Por isso T07 depende de T08.

- [ ] **Step 1: Teste (falha)**

`tests/Meridiano.Api.Tests/AutorizacaoTests.cs`:
```csharp
using System.Net;
using System.Net.Http.Json;
using Meridiano.Api.Auth;
using Meridiano.Api.Tests.Fixtures;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class AutorizacaoTests(PostgresFixture pg)
{
    private static async Task<HttpClient> LogadoAsync(MeridianoApiFactory app, string email, string senha)
    {
        var c = app.CreateClient();
        var r = await c.PostAsJsonAsync("/api/v1/auth/login", new { email, senha });
        Assert.Equal(HttpStatusCode.NoContent, r.StatusCode);
        return c;
    }

    [Fact]
    public async Task Agente_recebe_403_dono_recebe_200()
    {
        var agencia = await pg.InserirAgenciaAsync("Autz");
        await pg.InserirUsuarioAsync(agencia, "agente@autz.com", SenhaHasher.Hash("s"), "agente");
        await pg.InserirUsuarioAsync(agencia, "dono@autz.com", SenhaHasher.Hash("s"), "dono");

        await using var app = new MeridianoApiFactory(pg);

        var agente = await LogadoAsync(app, "agente@autz.com", "s");
        var r = await agente.GetAsync("/api/v1/_dev/protegido");
        Assert.Equal(HttpStatusCode.Forbidden, r.StatusCode);
        var problem = await r.Content.ReadFromJsonAsync<Dictionary<string, object>>();
        Assert.Equal("sem_permissao", problem!["codigo"].ToString());

        var dono = await LogadoAsync(app, "dono@autz.com", "s");
        Assert.Equal(HttpStatusCode.OK, (await dono.GetAsync("/api/v1/_dev/protegido")).StatusCode);
    }

    [Fact]
    public async Task Anonimo_recebe_401()
    {
        await using var app = new MeridianoApiFactory(pg);
        Assert.Equal(HttpStatusCode.Unauthorized, (await app.CreateClient().GetAsync("/api/v1/_dev/protegido")).StatusCode);
    }
}
```

- [ ] **Step 2: Rodar (falha)**

Run: `dotnet test tests/Meridiano.Api.Tests --filter AutorizacaoTests`
Expected: 404 em `/_dev/protegido` (endpoint não existe) → asserts falham.

- [ ] **Step 3: Implementação**

`src/Meridiano.Api/Auth/Autorizacao.cs`:
```csharp
using Microsoft.AspNetCore.Http.HttpResults;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Auth;

public static class Autorizacao
{
    public static bool Pode(this UsuarioAtual usuario, Permissao permissao) => Permissoes.Do(usuario.Perfil).Contains(permissao);

    public static TBuilder RequerPermissao<TBuilder>(this TBuilder builder, Permissao permissao) where TBuilder : IEndpointConventionBuilder
    {
        builder.RequireAuthorization();
        builder.AddEndpointFilter(async (ctx, next) =>
        {
            var usuario = UsuarioAtual.De(ctx.HttpContext.User);
            if (usuario is null) return Results.Unauthorized();
            if (!usuario.Pode(permissao))
            {
                return Results.Problem(
                    statusCode: StatusCodes.Status403Forbidden,
                    title: "Sem permissão",
                    detail: $"Requer {permissao.Chave()}",
                    extensions: new Dictionary<string, object?> { ["codigo"] = "sem_permissao", ["permissao"] = permissao.Chave() });
            }
            return await next(ctx);
        });
        return builder;
    }
}
```

Em `src/Meridiano.Api/Infra/DevEndpoints.cs` (criado por T08), adicionar dentro de `MapDevEndpoints`:
```csharp
        g.MapGet("/protegido", () => Results.Ok(new { ok = true })).RequerPermissao(Permissao.UsuarioGerenciar);
```
com `using Meridiano.Api.Auth;` e `using Meridiano.Domain.Comum;`.

- [ ] **Step 4: Rodar**

Run: `dotnet test tests/Meridiano.Api.Tests --filter AutorizacaoTests`
Expected: 2 passed.

- [ ] **Step 5: Reportar arquivos** (commit: `feat(auth): filtro RequerPermissao por perfil`)

---

### Task 8: Infra — Serilog, ProblemDetails, exceções de domínio, health check

**Files:**
- Create: `src/Meridiano.Domain/Comum/RegraDeNegocioException.cs`, `src/Meridiano.Domain/Comum/ConflitoConcorrenciaException.cs`
- Modify: `src/Meridiano.Api/Infra/InfraExtensions.cs`
- Create: `src/Meridiano.Api/Infra/TratadorDeExcecoes.cs`, `src/Meridiano.Api/Infra/PostgresHealthCheck.cs`, `src/Meridiano.Api/Infra/DevEndpoints.cs`
- Create: `tests/Meridiano.Api.Tests/InfraTests.cs`

**Depends-on:** T03

**Interfaces:**
- Produces: `RegraDeNegocioException(string codigo, string mensagem)` com `Codigo`; `ConflitoConcorrenciaException(string mensagem)`; respostas ProblemDetails com extensão `codigo`; `GET /health`; `GET /api/v1/_dev/erro/{tipo}` com `tipo ∈ {regra, conflito, bug}` só em Development/Testing; `DevEndpoints.MapDevEndpoints(this IEndpointRouteBuilder)` com grupo `/_dev` (T07 adiciona um endpoint nele).

- [ ] **Step 1: Teste (falha)**

`tests/Meridiano.Api.Tests/InfraTests.cs`:
```csharp
using System.Net;
using System.Net.Http.Json;
using Meridiano.Api.Tests.Fixtures;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class InfraTests(PostgresFixture pg)
{
    [Fact]
    public async Task Health_responde_healthy()
    {
        await using var app = new MeridianoApiFactory(pg);
        var r = await app.CreateClient().GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        Assert.Equal("Healthy", await r.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData("regra", HttpStatusCode.UnprocessableEntity, "exemplo_regra")]
    [InlineData("conflito", HttpStatusCode.Conflict, "conflito_concorrencia")]
    [InlineData("bug", HttpStatusCode.InternalServerError, "erro_interno")]
    public async Task Excecoes_viram_problem_details_com_codigo(string tipo, HttpStatusCode status, string codigo)
    {
        await using var app = new MeridianoApiFactory(pg);
        var r = await app.CreateClient().GetAsync($"/api/v1/_dev/erro/{tipo}");
        Assert.Equal(status, r.StatusCode);
        Assert.Equal("application/problem+json", r.Content.Headers.ContentType?.MediaType);
        var body = await r.Content.ReadFromJsonAsync<Dictionary<string, object>>();
        Assert.Equal(codigo, body!["codigo"].ToString());
    }
}
```

- [ ] **Step 2: Rodar (falha)**

Run: `dotnet test tests/Meridiano.Api.Tests --filter InfraTests`
Expected: `/health` 404.

- [ ] **Step 3: Implementação**

`src/Meridiano.Domain/Comum/RegraDeNegocioException.cs`:
```csharp
namespace Meridiano.Domain.Comum;

public sealed class RegraDeNegocioException(string codigo, string mensagem) : Exception(mensagem)
{
    public string Codigo { get; } = codigo;
}
```

`src/Meridiano.Domain/Comum/ConflitoConcorrenciaException.cs`:
```csharp
namespace Meridiano.Domain.Comum;

public sealed class ConflitoConcorrenciaException(string mensagem) : Exception(mensagem);
```

`src/Meridiano.Api/Infra/TratadorDeExcecoes.cs`:
```csharp
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Infra;

public sealed class TratadorDeExcecoes(IProblemDetailsService problemas, ILogger<TratadorDeExcecoes> log) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception ex, CancellationToken ct)
    {
        var (status, codigo, titulo) = ex switch
        {
            RegraDeNegocioException r => (StatusCodes.Status422UnprocessableEntity, r.Codigo, "Regra de negócio"),
            ConflitoConcorrenciaException => (StatusCodes.Status409Conflict, "conflito_concorrencia", "Registro alterado por outro usuário"),
            UnauthorizedAccessException => (StatusCodes.Status401Unauthorized, "nao_autenticado", "Não autenticado"),
            _ => (StatusCodes.Status500InternalServerError, "erro_interno", "Erro interno"),
        };

        if (status == StatusCodes.Status500InternalServerError)
        {
            log.LogError(ex, "Erro não tratado em {Metodo} {Caminho}", http.Request.Method, http.Request.Path);
        }

        http.Response.StatusCode = status;
        var detalhe = status == StatusCodes.Status500InternalServerError ? "Erro interno. Tente novamente." : ex.Message;
        return await problemas.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = http,
            Exception = ex,
            ProblemDetails = new ProblemDetails
            {
                Status = status,
                Title = titulo,
                Detail = detalhe,
                Extensions = { ["codigo"] = codigo },
            },
        });
    }
}
```

`src/Meridiano.Api/Infra/PostgresHealthCheck.cs`:
```csharp
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Npgsql;

namespace Meridiano.Api.Infra;

public sealed class PostgresHealthCheck(IConfiguration config) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken ct = default)
    {
        try
        {
            await using var c = new NpgsqlConnection(config.GetConnectionString("Api"));
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand("select 1", c);
            await cmd.ExecuteScalarAsync(ct);
            return HealthCheckResult.Healthy();
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("postgres indisponível", ex);
        }
    }
}
```

`src/Meridiano.Api/Infra/DevEndpoints.cs`:
```csharp
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Infra;

// Só em Development/Testing. Prova o tratador de exceções e o filtro de permissão.
public static class DevEndpoints
{
    public static IEndpointRouteBuilder MapDevEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/v1/_dev");
        g.MapGet("/erro/{tipo}", (string tipo) => tipo switch
        {
            "regra" => throw new RegraDeNegocioException("exemplo_regra", "Exemplo de regra violada"),
            "conflito" => throw new ConflitoConcorrenciaException("Exemplo de conflito"),
            "bug" => throw new InvalidOperationException("Exemplo de bug"),
            _ => Results.NotFound(),
        });
        return app;
    }
}
```

`src/Meridiano.Api/Infra/InfraExtensions.cs`:
```csharp
using Serilog;
using Serilog.Formatting.Compact;

namespace Meridiano.Api.Infra;

public static class InfraExtensions
{
    public static WebApplicationBuilder AddInfra(this WebApplicationBuilder builder)
    {
        builder.Host.UseSerilog((ctx, cfg) => cfg
            .ReadFrom.Configuration(ctx.Configuration)
            .Enrich.FromLogContext()
            .WriteTo.Console(new CompactJsonFormatter()));

        builder.Services.AddProblemDetails();
        builder.Services.AddExceptionHandler<TratadorDeExcecoes>();
        builder.Services.AddHealthChecks().AddCheck<PostgresHealthCheck>("postgres");
        return builder;
    }

    public static WebApplication UseInfra(this WebApplication app)
    {
        app.UseExceptionHandler();
        app.UseSerilogRequestLogging();
        app.MapHealthChecks("/health");
        if (app.Environment.IsDevelopment() || app.Environment.IsEnvironment("Testing"))
        {
            app.MapDevEndpoints();
        }
        return app;
    }
}
```

Nota: `MapDevEndpoints` é chamado em `UseInfra`, que roda **antes** de `UseAutenticacao` em `Program.cs`; endpoints mapeados ali ainda passam pelos middlewares de auth porque `UseAuthentication`/`UseAuthorization` são registrados antes do endpoint executar (o pipeline é montado no `Build`, o mapeamento só registra rotas). Se `RequireAuthorization` reclamar de ordem, mover `app.MapDevEndpoints()` para o fim de `Endpoints.MapEndpoints` **não é permitido** (arquivo de T01); em vez disso, manter em `UseInfra` e confirmar com o teste de T07.

- [ ] **Step 4: Rodar**

Run: `dotnet test tests/Meridiano.Api.Tests --filter InfraTests`
Expected: 4 passed.

- [ ] **Step 5: Reportar arquivos** (commit: `feat(infra): serilog, problem details, excecoes de dominio e health check`)

---

### Task 9: Convite, definir senha e esqueci senha (e-mail via Resend)

**Files:**
- Create: `src/Meridiano.Api/Infra/Email/IEnviadorEmail.cs`, `src/Meridiano.Api/Infra/Email/ResendEnviadorEmail.cs`, `src/Meridiano.Api/Infra/Email/EmailExtensions.cs`
- Create: `src/Meridiano.Api/Auth/ConviteService.cs`
- Modify: `src/Meridiano.Api/Auth/ConviteEndpoints.cs`
- Create: `tests/Meridiano.Api.Tests/Fixtures/EmailFake.cs`, `tests/Meridiano.Api.Tests/ConviteTests.cs`

**Depends-on:** T06, T07

**Interfaces:**
- Consumes: `DbSessaoFactory`, `UsuarioAtual`, `RequerPermissao`, `SenhaHasher`, `RegraDeNegocioException`.
- Produces: `IEnviadorEmail.EnviarAsync(string para, string assunto, string html, CancellationToken)`; registro via `EmailExtensions.AddEmail(this IServiceCollection, IConfiguration)` chamado por `AddAuth`? **Não** — `AddAuth` é de T06. Solução: `ConviteEndpoints.MapConviteEndpoints` não registra serviços; o registro de `IEnviadorEmail` e `ConviteService` acontece em `EmailExtensions.AddEmail(this WebApplicationBuilder)` chamado **de dentro de `AddJobs`**? Também não. Regra: esta task **modifica `AuthExtensions.AddAuth`** para chamar `builder.Services.AddEmail(builder.Configuration)` e `AddScoped<ConviteService>()` — `AuthExtensions.cs` é de T06, que já terminou na onda 3; T09 está na onda 4, sem colisão na mesma onda. Adicionar `Modify: src/Meridiano.Api/Auth/AuthExtensions.cs` aos Files.
- Endpoints: `POST /api/v1/auth/convites` `{nome, email, perfil}` (requer `UsuarioGerenciar`) → 201 `{usuarioId}`; `POST /api/v1/auth/definir-senha` `{token, senha}` → 204; `POST /api/v1/auth/esqueci-senha` `{email}` → 204 sempre.

- [ ] **Step 1: Teste (falha)**

`tests/Meridiano.Api.Tests/Fixtures/EmailFake.cs`:
```csharp
using Meridiano.Api.Infra.Email;

namespace Meridiano.Api.Tests.Fixtures;

public sealed class EmailFake : IEnviadorEmail
{
    public List<(string Para, string Assunto, string Html)> Enviados { get; } = [];

    public Task EnviarAsync(string para, string assunto, string html, CancellationToken ct)
    {
        Enviados.Add((para, assunto, html));
        return Task.CompletedTask;
    }
}
```

`tests/Meridiano.Api.Tests/ConviteTests.cs`:
```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Meridiano.Api.Auth;
using Meridiano.Api.Infra.Email;
using Meridiano.Api.Tests.Fixtures;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class ConviteTests(PostgresFixture pg)
{
    private static (WebApplicationFactory<Program> App, EmailFake Email) AppComEmailFake(PostgresFixture pg)
    {
        var email = new EmailFake();
        var app = new MeridianoApiFactory(pg).WithWebHostBuilder(b =>
            b.ConfigureServices(s => s.AddSingleton<IEnviadorEmail>(email)));
        return (app, email);
    }

    private static string TokenDo(string html) => Regex.Match(html, @"token=([A-Za-z0-9_\-]+)").Groups[1].Value;

    [Fact]
    public async Task Dono_convida_convidado_define_senha_e_loga()
    {
        var agencia = await pg.InserirAgenciaAsync("Conv");
        await pg.InserirUsuarioAsync(agencia, "dono@conv.com", SenhaHasher.Hash("s"), "dono");
        var (app, email) = AppComEmailFake(pg);
        await using var _ = app;

        var dono = app.CreateClient();
        await dono.PostAsJsonAsync("/api/v1/auth/login", new { email = "dono@conv.com", senha = "s" });

        var r = await dono.PostAsJsonAsync("/api/v1/auth/convites", new { nome = "Nova Agente", email = "nova@conv.com", perfil = "agente" });
        Assert.Equal(HttpStatusCode.Created, r.StatusCode);
        var enviado = Assert.Single(email.Enviados);
        Assert.Equal("nova@conv.com", enviado.Para);

        var anon = app.CreateClient();
        var def = await anon.PostAsJsonAsync("/api/v1/auth/definir-senha", new { token = TokenDo(enviado.Html), senha = "nova-senha-123" });
        Assert.Equal(HttpStatusCode.NoContent, def.StatusCode);

        var login = await anon.PostAsJsonAsync("/api/v1/auth/login", new { email = "nova@conv.com", senha = "nova-senha-123" });
        Assert.Equal(HttpStatusCode.NoContent, login.StatusCode);

        // token é de uso único
        var de_novo = await anon.PostAsJsonAsync("/api/v1/auth/definir-senha", new { token = TokenDo(enviado.Html), senha = "outra" });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, de_novo.StatusCode);
    }

    [Fact]
    public async Task Agente_nao_pode_convidar()
    {
        var agencia = await pg.InserirAgenciaAsync("Conv2");
        await pg.InserirUsuarioAsync(agencia, "ag@conv2.com", SenhaHasher.Hash("s"), "agente");
        var (app, _) = AppComEmailFake(pg);
        await using var __ = app;

        var c = app.CreateClient();
        await c.PostAsJsonAsync("/api/v1/auth/login", new { email = "ag@conv2.com", senha = "s" });
        var r = await c.PostAsJsonAsync("/api/v1/auth/convites", new { nome = "X", email = "x@conv2.com", perfil = "agente" });
        Assert.Equal(HttpStatusCode.Forbidden, r.StatusCode);
    }

    [Fact]
    public async Task Esqueci_senha_envia_email_e_redefine()
    {
        var agencia = await pg.InserirAgenciaAsync("Conv3");
        await pg.InserirUsuarioAsync(agencia, "esq@conv3.com", SenhaHasher.Hash("antiga"), "financeiro");
        var (app, email) = AppComEmailFake(pg);
        await using var _ = app;
        var c = app.CreateClient();

        Assert.Equal(HttpStatusCode.NoContent, (await c.PostAsJsonAsync("/api/v1/auth/esqueci-senha", new { email = "esq@conv3.com" })).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await c.PostAsJsonAsync("/api/v1/auth/esqueci-senha", new { email = "naoexiste@conv3.com" })).StatusCode);
        var enviado = Assert.Single(email.Enviados);

        await c.PostAsJsonAsync("/api/v1/auth/definir-senha", new { token = TokenDo(enviado.Html), senha = "nova" });
        Assert.Equal(HttpStatusCode.NoContent, (await c.PostAsJsonAsync("/api/v1/auth/login", new { email = "esq@conv3.com", senha = "nova" })).StatusCode);
    }
}
```

- [ ] **Step 2: Rodar (falha de compilação)**

Run: `dotnet test tests/Meridiano.Api.Tests --filter ConviteTests`
Expected: `'IEnviadorEmail' could not be found`.

- [ ] **Step 3: Implementação**

`src/Meridiano.Api/Infra/Email/IEnviadorEmail.cs`:
```csharp
namespace Meridiano.Api.Infra.Email;

public interface IEnviadorEmail
{
    Task EnviarAsync(string para, string assunto, string html, CancellationToken ct);
}
```

`src/Meridiano.Api/Infra/Email/ResendEnviadorEmail.cs`:
```csharp
using System.Net.Http.Headers;

namespace Meridiano.Api.Infra.Email;

public sealed class ResendEnviadorEmail(HttpClient http, IConfiguration config, ILogger<ResendEnviadorEmail> log) : IEnviadorEmail
{
    public async Task EnviarAsync(string para, string assunto, string html, CancellationToken ct)
    {
        var apiKey = config["Email:ResendApiKey"];
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            // sem chave (dev): loga em vez de enviar
            log.LogWarning("Email não enviado (sem Email:ResendApiKey). Para={Para} Assunto={Assunto} Html={Html}", para, assunto, html);
            return;
        }

        using var req = new HttpRequestMessage(HttpMethod.Post, "https://api.resend.com/emails");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        req.Content = JsonContent.Create(new { from = config["Email:Remetente"], to = new[] { para }, subject = assunto, html });
        var resp = await http.SendAsync(req, ct);
        resp.EnsureSuccessStatusCode();
    }
}
```

`src/Meridiano.Api/Infra/Email/EmailExtensions.cs`:
```csharp
namespace Meridiano.Api.Infra.Email;

public static class EmailExtensions
{
    public static IServiceCollection AddEmail(this IServiceCollection services)
    {
        services.AddHttpClient<IEnviadorEmail, ResendEnviadorEmail>();
        return services;
    }
}
```

`src/Meridiano.Api/Auth/ConviteService.cs`:
```csharp
using System.Security.Cryptography;
using Dapper;
using Npgsql;
using Meridiano.Api.Infra.Email;
using Meridiano.Data.Sessao;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Auth;

public sealed class ConviteService(DbSessaoFactory sessoes, IEnviadorEmail email, IConfiguration config)
{
    private static readonly TimeSpan ValidadeConvite = TimeSpan.FromHours(72);
    private static readonly TimeSpan ValidadeReset = TimeSpan.FromHours(2);

    private static string NovoToken() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
        .Replace('+', '-').Replace('/', '_').TrimEnd('=');

    private string Link(string token) => $"{config["Email:BaseUrl"]}/definir-senha?token={token}";

    public async Task<Guid> ConvidarAsync(ContextoSessao ctx, string nome, string emailDestino, Perfil perfil, CancellationToken ct)
    {
        var token = NovoToken();
        Guid id;
        await using (var s = await sessoes.AbrirAsync(ctx, ct))
        {
            var existe = await s.Conexao.ExecuteScalarAsync<bool>(
                "select exists (select 1 from usuario where agencia_id = @agencia and lower(email) = lower(@emailDestino))",
                new { agencia = ctx.AgenciaId, emailDestino }, s.Transacao);
            if (existe) throw new RegraDeNegocioException("email_ja_cadastrado", "Já existe usuário com este e-mail");

            id = await s.Conexao.ExecuteScalarAsync<Guid>(
                """
                insert into usuario (agencia_id, nome, email, perfil, gera_repasse, convite_token, convite_expira_em)
                values (@agencia, @nome, @emailDestino, @perfil, @geraRepasse, @token, now() + @validade)
                returning id
                """,
                new { agencia = ctx.AgenciaId, nome, emailDestino, perfil = perfil.ParaBanco(), geraRepasse = perfil == Perfil.VendedorExterno, token, validade = ValidadeConvite },
                s.Transacao);
            await s.ConfirmarAsync(ct);
        }

        await email.EnviarAsync(emailDestino, "Convite — Meridiano",
            $"<p>Olá, {nome}. Você foi convidado. Defina sua senha: <a href=\"{Link(token)}\">{Link(token)}</a></p>", ct);
        return id;
    }

    // Sem tenant: token é global e único. Usa conexão direta + função definer não existe para isso,
    // então a busca roda como meridiano_api sem app.agencia_id e precisa de uma função no banco? Não:
    // o token localiza a agência primeiro via função definer criada nesta task (migration 0003).
    public async Task DefinirSenhaAsync(string token, string senha, CancellationToken ct)
    {
        if (senha.Length < 8) throw new RegraDeNegocioException("senha_curta", "Senha precisa de ao menos 8 caracteres");

        await using var conexao = new NpgsqlConnection(config.GetConnectionString("Api")!);
        await conexao.OpenAsync(ct);
        var alvo = await conexao.QuerySingleOrDefaultAsync<(Guid Id, Guid AgenciaId)>(
            "select id, agencia_id from localizar_usuario_por_token(@token)", new { token });
        if (alvo == default) throw new RegraDeNegocioException("token_invalido", "Token inválido ou expirado");

        await using var s = await sessoes.AbrirAsync(new ContextoSessao(alvo.AgenciaId, alvo.Id, null), ct);
        await s.Conexao.ExecuteAsync(
            "update usuario set senha_hash = @hash, convite_token = null, convite_expira_em = null, reset_token = null, reset_expira_em = null where id = @id",
            new { hash = SenhaHasher.Hash(senha), id = alvo.Id }, s.Transacao);
        await s.ConfirmarAsync(ct);
    }

    public async Task EsqueciSenhaAsync(string emailDestino, CancellationToken ct)
    {
        await using var conexao = new NpgsqlConnection(config.GetConnectionString("Api")!);
        await conexao.OpenAsync(ct);
        var alvo = await conexao.QuerySingleOrDefaultAsync<(Guid Id, Guid AgenciaId)>(
            "select id, agencia_id from localizar_usuario_login(@emailDestino)", new { emailDestino });
        if (alvo == default) return; // nunca revela existência

        var token = NovoToken();
        await using (var s = await sessoes.AbrirAsync(new ContextoSessao(alvo.AgenciaId, alvo.Id, null), ct))
        {
            await s.Conexao.ExecuteAsync(
                "update usuario set reset_token = @token, reset_expira_em = now() + @validade where id = @id",
                new { token, validade = ValidadeReset, id = alvo.Id }, s.Transacao);
            await s.ConfirmarAsync(ct);
        }
        await email.EnviarAsync(emailDestino, "Redefinir senha — Meridiano",
            $"<p>Para redefinir sua senha: <a href=\"{Link(token)}\">{Link(token)}</a> (válido por 2 horas)</p>", ct);
    }
}
```

Migration nova — `src/Meridiano.Data/Migrations/0003_localizar_usuario_por_token.sql` (adicionar a **Files: Create**):
```sql
-- Localiza usuário por token de convite ou reset, ignorando RLS (não há agência antes do login).
create or replace function localizar_usuario_por_token(p_token text)
returns table (id uuid, agencia_id uuid) as $$
  select u.id, u.agencia_id
    from usuario u
   where u.ativo
     and ((u.convite_token = p_token and u.convite_expira_em > now())
       or (u.reset_token   = p_token and u.reset_expira_em   > now()))
   limit 1
$$ language sql stable security definer;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'meridiano_api') then
    grant execute on function localizar_usuario_por_token(text) to meridiano_api;
  end if;
end $$;
```

`src/Meridiano.Api/Auth/ConviteEndpoints.cs`:
```csharp
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Auth;

public static class ConviteEndpoints
{
    public sealed record ConviteRequest(string Nome, string Email, string Perfil);
    public sealed record DefinirSenhaRequest(string Token, string Senha);
    public sealed record EsqueciSenhaRequest(string Email);

    public static IEndpointRouteBuilder MapConviteEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/auth");

        g.MapPost("/convites", async (ConviteRequest req, HttpContext http, ConviteService convites, CancellationToken ct) =>
        {
            var id = await convites.ConvidarAsync(http.Contexto(), req.Nome.Trim(), req.Email.Trim(), PerfilExtensions.DoBanco(req.Perfil), ct);
            return Results.Created($"/api/v1/usuarios/{id}", new { usuarioId = id });
        }).RequerPermissao(Permissao.UsuarioGerenciar);

        g.MapPost("/definir-senha", async (DefinirSenhaRequest req, ConviteService convites, CancellationToken ct) =>
        {
            await convites.DefinirSenhaAsync(req.Token, req.Senha, ct);
            return Results.NoContent();
        }).RequireRateLimiting(AuthExtensions.PoliticaLogin).AllowAnonymous();

        g.MapPost("/esqueci-senha", async (EsqueciSenhaRequest req, ConviteService convites, CancellationToken ct) =>
        {
            await convites.EsqueciSenhaAsync(req.Email.Trim(), ct);
            return Results.NoContent();
        }).RequireRateLimiting(AuthExtensions.PoliticaLogin).AllowAnonymous();

        return app;
    }
}
```

Em `src/Meridiano.Api/Auth/AuthExtensions.cs`, dentro de `AddAuth`, logo após `builder.Services.AddScoped<LoginService>();`:
```csharp
        builder.Services.AddEmail();
        builder.Services.AddScoped<ConviteService>();
```
com `using Meridiano.Api.Infra.Email;`.

- [ ] **Step 4: Rodar**

Run: `dotnet test tests/Meridiano.Api.Tests --filter ConviteTests`
Expected: 3 passed.

- [ ] **Step 5: Reportar arquivos** (commit: `feat(auth): convite, definir senha e esqueci senha via Resend`)

---

### Task 10: Jobs por linha de comando com registro em `job_execucao`

**Files:**
- Create: `src/Meridiano.Api/Jobs/IJob.cs`, `src/Meridiano.Api/Jobs/JobRunner.cs`, `src/Meridiano.Api/Jobs/PingJob.cs`
- Modify: `src/Meridiano.Api/Jobs/JobsExtensions.cs`
- Create: `tests/Meridiano.Api.Tests/JobsTests.cs`

**Depends-on:** T05

**Interfaces:**
- Produces: `interface IJob { string Nome { get; } Task ExecutarAsync(CancellationToken ct); }`; `JobRunner.ExecutarAsync(string nome, CancellationToken) : Task<int>` (0 sucesso, 1 erro, 2 job desconhecido); `PingJob` (`Nome = "ping"`); `dotnet Meridiano.Api.dll job <nome>`. Azure Container Apps Jobs chama exatamente isso.

- [ ] **Step 1: Teste (falha)**

`tests/Meridiano.Api.Tests/JobsTests.cs`:
```csharp
using Microsoft.Extensions.DependencyInjection;
using Meridiano.Api.Jobs;
using Meridiano.Api.Tests.Fixtures;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class JobsTests(PostgresFixture pg)
{
    [Fact]
    public async Task Ping_registra_execucao_com_sucesso()
    {
        await using var app = new MeridianoApiFactory(pg);
        using var scope = app.Services.CreateScope();
        var runner = scope.ServiceProvider.GetRequiredService<JobRunner>();

        var codigo = await runner.ExecutarAsync("ping", CancellationToken.None);

        Assert.Equal(0, codigo);
        var linhas = await pg.QueryOwnerAsync<(bool Sucesso, DateTime? TerminadoEm)>(
            "select sucesso, terminado_em from job_execucao where nome = 'ping' order by id desc limit 1");
        var (sucesso, terminado) = linhas.Single();
        Assert.True(sucesso);
        Assert.NotNull(terminado);
    }

    [Fact]
    public async Task Job_desconhecido_retorna_2()
    {
        await using var app = new MeridianoApiFactory(pg);
        using var scope = app.Services.CreateScope();
        var runner = scope.ServiceProvider.GetRequiredService<JobRunner>();
        Assert.Equal(2, await runner.ExecutarAsync("nao-existe", CancellationToken.None));
    }
}
```

- [ ] **Step 2: Rodar (falha de compilação)**

Run: `dotnet test tests/Meridiano.Api.Tests --filter JobsTests`
Expected: `'JobRunner' could not be found`.

- [ ] **Step 3: Implementação**

`src/Meridiano.Api/Jobs/IJob.cs`:
```csharp
namespace Meridiano.Api.Jobs;

public interface IJob
{
    string Nome { get; }
    Task ExecutarAsync(CancellationToken ct);
}
```

`src/Meridiano.Api/Jobs/PingJob.cs`:
```csharp
using Dapper;
using Npgsql;

namespace Meridiano.Api.Jobs;

// Mantém o banco acordado (Supabase free pausa após 7 dias sem uso) e prova o pipeline de jobs.
public sealed class PingJob(IConfiguration config) : IJob
{
    public string Nome => "ping";

    public async Task ExecutarAsync(CancellationToken ct)
    {
        await using var c = new NpgsqlConnection(config.GetConnectionString("Api"));
        await c.ExecuteScalarAsync<int>(new CommandDefinition("select 1", cancellationToken: ct));
    }
}
```

`src/Meridiano.Api/Jobs/JobRunner.cs`:
```csharp
using Dapper;
using Npgsql;

namespace Meridiano.Api.Jobs;

public sealed class JobRunner(IEnumerable<IJob> jobs, IConfiguration config, ILogger<JobRunner> log)
{
    public async Task<int> ExecutarAsync(string nome, CancellationToken ct)
    {
        var job = jobs.FirstOrDefault(j => j.Nome == nome);
        if (job is null)
        {
            log.LogError("Job desconhecido: {Nome}. Disponíveis: {Jobs}", nome, string.Join(", ", jobs.Select(j => j.Nome)));
            return 2;
        }

        await using var c = new NpgsqlConnection(config.GetConnectionString("Api"));
        var id = await c.ExecuteScalarAsync<long>("insert into job_execucao (nome) values (@nome) returning id", new { nome });
        try
        {
            await job.ExecutarAsync(ct);
            await c.ExecuteAsync("update job_execucao set terminado_em = now(), sucesso = true where id = @id", new { id });
            log.LogInformation("Job {Nome} concluído", nome);
            return 0;
        }
        catch (Exception ex)
        {
            await c.ExecuteAsync("update job_execucao set terminado_em = now(), sucesso = false, detalhe = @d where id = @id", new { id, d = ex.ToString() });
            log.LogError(ex, "Job {Nome} falhou", nome);
            return 1;
        }
    }
}
```

`src/Meridiano.Api/Jobs/JobsExtensions.cs`:
```csharp
namespace Meridiano.Api.Jobs;

public static class JobsExtensions
{
    public static WebApplicationBuilder AddJobs(this WebApplicationBuilder builder)
    {
        builder.Services.AddScoped<JobRunner>();
        builder.Services.AddScoped<IJob, PingJob>();
        return builder;
    }

    public static async Task<int> ExecutarJob(this WebApplication app, string nome)
    {
        using var scope = app.Services.CreateScope();
        return await scope.ServiceProvider.GetRequiredService<JobRunner>().ExecutarAsync(nome, CancellationToken.None);
    }
}
```

Nota sobre RLS: `job_execucao` não tem policy (não é tabela de tenant). Jobs futuros que tocam tabelas de tenant iteram agências e abrem uma `DbSessao` por agência.

- [ ] **Step 4: Rodar**

Run: `dotnet test tests/Meridiano.Api.Tests --filter JobsTests`
Expected: 2 passed.

- [ ] **Step 5: Reportar arquivos** (commit: `feat(jobs): runner por linha de comando e ping`)

---

### Task 11: CI (GitHub Actions) e Dockerfile

**Files:**
- Create: `.github/workflows/ci.yml`, `Dockerfile`, `.dockerignore`

**Depends-on:** T01

**Interfaces:**
- Produces: imagem `meridiano-api` com `ENTRYPOINT ["dotnet", "Meridiano.Api.dll"]` (job: `docker run meridiano-api job ping`).

- [ ] **Step 1: Workflow**

`.github/workflows/ci.yml`:
```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:
jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: 10.0.x
      - run: dotnet restore
      - run: dotnet build --no-restore -c Release
      - run: dotnet test --no-build -c Release --logger "trx;LogFileName=test.trx"
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: "**/TestResults/*.trx"
  docker:
    runs-on: ubuntu-latest
    needs: build-test
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          tags: meridiano-api:ci
```

- [ ] **Step 2: Dockerfile**

`Dockerfile`:
```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Directory.Build.props Meridiano.sln ./
COPY src/Meridiano.Domain/Meridiano.Domain.csproj src/Meridiano.Domain/
COPY src/Meridiano.Data/Meridiano.Data.csproj src/Meridiano.Data/
COPY src/Meridiano.Api/Meridiano.Api.csproj src/Meridiano.Api/
RUN dotnet restore src/Meridiano.Api/Meridiano.Api.csproj
COPY src/ src/
RUN dotnet publish src/Meridiano.Api/Meridiano.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
COPY --from=build /app .
USER app
ENTRYPOINT ["dotnet", "Meridiano.Api.dll"]
```

`.dockerignore`:
```
**/bin
**/obj
tests
web/node_modules
.git
```

- [ ] **Step 3: Verificar**

Run: `docker build -t meridiano-api:local .`
Expected: build ok. Depois `docker run --rm meridiano-api:local job ping` sem `ConnectionStrings:Api` → sai com código 1 e log de erro (comportamento esperado sem banco).

- [ ] **Step 4: Reportar arquivos** (commit: `chore: ci workflow and dockerfile`)

---

### Task 12: Endpoint vertical de usuários com concorrência otimista

**Files:**
- Modify: `src/Meridiano.Api/Modules/Admin/AdminEndpoints.cs`
- Create: `src/Meridiano.Api/Modules/Admin/UsuarioDtos.cs`, `src/Meridiano.Api/Modules/Admin/UsuarioService.cs`
- Create: `tests/Meridiano.Api.Tests/UsuariosTests.cs`

**Depends-on:** T07, T08, T09

**Interfaces:**
- Consumes: `DbSessaoFactory`, `http.Contexto()`, `RequerPermissao`, `ConflitoConcorrenciaException`, `RegraDeNegocioException`, `Perfil`.
- Produces: `GET /api/v1/usuarios` → `UsuarioDto[]`; `PUT /api/v1/usuarios/{id}` com `AtualizarUsuarioRequest` → `UsuarioDto`; `versao` = `xmin::text`.

- [ ] **Step 1: Teste (falha)**

`tests/Meridiano.Api.Tests/UsuariosTests.cs`:
```csharp
using System.Net;
using System.Net.Http.Json;
using Meridiano.Api.Auth;
using Meridiano.Api.Tests.Fixtures;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class UsuariosTests(PostgresFixture pg)
{
    private sealed record UsuarioDto(Guid Id, string Nome, string Email, string? Telefone, string Perfil, bool GeraRepasse, decimal PercentualPadrao, bool Ativo, string Versao);

    private static async Task<HttpClient> DonoAsync(MeridianoApiFactory app, string email)
    {
        var c = app.CreateClient();
        await c.PostAsJsonAsync("/api/v1/auth/login", new { email, senha = "s" });
        return c;
    }

    [Fact]
    public async Task Lista_so_usuarios_da_propria_agencia()
    {
        var a = await pg.InserirAgenciaAsync("Usr A");
        var b = await pg.InserirAgenciaAsync("Usr B");
        await pg.InserirUsuarioAsync(a, "dono@usra.com", SenhaHasher.Hash("s"), "dono");
        await pg.InserirUsuarioAsync(a, "agente@usra.com", null, "agente");
        await pg.InserirUsuarioAsync(b, "dono@usrb.com", SenhaHasher.Hash("s"), "dono");

        await using var app = new MeridianoApiFactory(pg);
        var c = await DonoAsync(app, "dono@usra.com");
        var lista = await c.GetFromJsonAsync<UsuarioDto[]>("/api/v1/usuarios");

        Assert.Equal(["agente@usra.com", "dono@usra.com"], lista!.Select(u => u.Email).Order());
    }

    [Fact]
    public async Task Update_com_versao_atual_grava_e_com_versao_velha_da_409()
    {
        var a = await pg.InserirAgenciaAsync("Usr C");
        await pg.InserirUsuarioAsync(a, "dono@usrc.com", SenhaHasher.Hash("s"), "dono");
        var alvo = await pg.InserirUsuarioAsync(a, "ext@usrc.com", null, "vendedor_externo", geraRepasse: true);

        await using var app = new MeridianoApiFactory(pg);
        var c = await DonoAsync(app, "dono@usrc.com");
        var antes = (await c.GetFromJsonAsync<UsuarioDto[]>("/api/v1/usuarios"))!.Single(u => u.Id == alvo);

        var req = new { nome = "Externo Renomeado", telefone = "11999", perfil = "vendedor_externo", geraRepasse = true, percentualPadrao = 12.5m, ativo = true, versao = antes.Versao };
        var r1 = await c.PutAsJsonAsync($"/api/v1/usuarios/{alvo}", req);
        Assert.Equal(HttpStatusCode.OK, r1.StatusCode);
        var depois = await r1.Content.ReadFromJsonAsync<UsuarioDto>();
        Assert.Equal("Externo Renomeado", depois!.Nome);
        Assert.NotEqual(antes.Versao, depois.Versao);

        var r2 = await c.PutAsJsonAsync($"/api/v1/usuarios/{alvo}", req); // versão velha
        Assert.Equal(HttpStatusCode.Conflict, r2.StatusCode);
    }

    [Fact]
    public async Task Nao_pode_inativar_o_ultimo_dono()
    {
        var a = await pg.InserirAgenciaAsync("Usr D");
        var dono = await pg.InserirUsuarioAsync(a, "dono@usrd.com", SenhaHasher.Hash("s"), "dono");

        await using var app = new MeridianoApiFactory(pg);
        var c = await DonoAsync(app, "dono@usrd.com");
        var eu = (await c.GetFromJsonAsync<UsuarioDto[]>("/api/v1/usuarios"))!.Single();
        var r = await c.PutAsJsonAsync($"/api/v1/usuarios/{dono}", new { nome = eu.Nome, telefone = (string?)null, perfil = "dono", geraRepasse = false, percentualPadrao = 0m, ativo = false, versao = eu.Versao });
        Assert.Equal(HttpStatusCode.UnprocessableEntity, r.StatusCode);
    }
}
```

- [ ] **Step 2: Rodar (falha)**

Run: `dotnet test tests/Meridiano.Api.Tests --filter UsuariosTests`
Expected: 404 em `/api/v1/usuarios`.

- [ ] **Step 3: Implementação**

`src/Meridiano.Api/Modules/Admin/UsuarioDtos.cs`:
```csharp
namespace Meridiano.Api.Modules.Admin;

public sealed record UsuarioDto(Guid Id, string Nome, string Email, string? Telefone, string Perfil, bool GeraRepasse, decimal PercentualPadrao, bool Ativo, string Versao);

public sealed record AtualizarUsuarioRequest(string Nome, string? Telefone, string Perfil, bool GeraRepasse, decimal PercentualPadrao, bool Ativo, string Versao);
```

`src/Meridiano.Api/Modules/Admin/UsuarioService.cs`:
```csharp
using Dapper;
using Meridiano.Data.Sessao;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Modules.Admin;

public sealed class UsuarioService(DbSessaoFactory sessoes)
{
    private const string Colunas = "id, nome, email, telefone, perfil, gera_repasse as GeraRepasse, percentual_padrao as PercentualPadrao, ativo, xmin::text as Versao";

    public async Task<IReadOnlyList<UsuarioDto>> ListarAsync(ContextoSessao ctx, CancellationToken ct)
    {
        await using var s = await sessoes.AbrirAsync(ctx, ct);
        var lista = await s.Conexao.QueryAsync<UsuarioDto>($"select {Colunas} from usuario order by nome", transaction: s.Transacao);
        return lista.ToList();
    }

    public async Task<UsuarioDto> AtualizarAsync(ContextoSessao ctx, Guid id, AtualizarUsuarioRequest req, CancellationToken ct)
    {
        var perfil = PerfilExtensions.DoBanco(req.Perfil);
        if (req.PercentualPadrao is < 0 or > 100) throw new RegraDeNegocioException("percentual_invalido", "Percentual entre 0 e 100");

        await using var s = await sessoes.AbrirAsync(ctx, ct);

        if (!req.Ativo || perfil != Perfil.Dono)
        {
            var outrosDonos = await s.Conexao.ExecuteScalarAsync<int>(
                "select count(*) from usuario where perfil = 'dono' and ativo and id <> @id", new { id }, s.Transacao);
            var eraDono = await s.Conexao.ExecuteScalarAsync<bool>("select perfil = 'dono' from usuario where id = @id", new { id }, s.Transacao);
            if (eraDono && outrosDonos == 0) throw new RegraDeNegocioException("ultimo_dono", "A agência precisa de ao menos um Dono ativo");
        }

        var atualizado = await s.Conexao.QuerySingleOrDefaultAsync<UsuarioDto>(
            $"""
            update usuario
               set nome = @Nome, telefone = @Telefone, perfil = @perfilBanco, gera_repasse = @GeraRepasse,
                   percentual_padrao = @PercentualPadrao, ativo = @Ativo
             where id = @id and xmin::text = @Versao
            returning {Colunas}
            """,
            new { id, req.Nome, req.Telefone, perfilBanco = perfil.ParaBanco(), req.GeraRepasse, req.PercentualPadrao, req.Ativo, req.Versao },
            s.Transacao);

        if (atualizado is null)
        {
            var existe = await s.Conexao.ExecuteScalarAsync<bool>("select exists (select 1 from usuario where id = @id)", new { id }, s.Transacao);
            if (!existe) throw new RegraDeNegocioException("nao_encontrado", "Usuário não encontrado");
            throw new ConflitoConcorrenciaException("Usuário foi alterado por outra pessoa. Recarregue e tente de novo.");
        }

        await s.ConfirmarAsync(ct);
        return atualizado;
    }
}
```

`src/Meridiano.Api/Modules/Admin/AdminEndpoints.cs`:
```csharp
using Meridiano.Api.Auth;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Modules.Admin;

public static class AdminEndpoints
{
    public static IEndpointRouteBuilder MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/usuarios").RequerPermissao(Permissao.UsuarioGerenciar);

        g.MapGet("/", async (HttpContext http, UsuarioService usuarios, CancellationToken ct) =>
            Results.Ok(await usuarios.ListarAsync(http.Contexto(), ct)));

        g.MapPut("/{id:guid}", async (Guid id, AtualizarUsuarioRequest req, HttpContext http, UsuarioService usuarios, CancellationToken ct) =>
            Results.Ok(await usuarios.AtualizarAsync(http.Contexto(), id, req, ct)));

        return app;
    }
}
```

Registro do serviço: em `src/Meridiano.Api/Auth/AuthExtensions.cs` (`AddAuth`), após `AddScoped<ConviteService>()`:
```csharp
        builder.Services.AddScoped<Meridiano.Api.Modules.Admin.UsuarioService>();
```
(Adicionar `Modify: src/Meridiano.Api/Auth/AuthExtensions.cs` aos Files. Colocar registros de módulo em `AddAuth` é provisório; na Fase 3 cada módulo ganha seu `Add<Modulo>()` chamado de um `ModulesExtensions.AddModules` — mudança que toca `Program.cs` uma vez, na primeira task da Fase 3.)

- [ ] **Step 4: Rodar tudo**

Run: `dotnet test`
Expected: Domain 12 passed; Api 19 passed (2 migrations + 4 sessão + 4 auth + 2 autorização + 4 infra + 3 convite + 2 jobs + 3 usuários = 24). Corrigir a contagem esperada conforme o resultado real; o critério é **zero falhas**.

- [ ] **Step 5: Reportar arquivos** (commit: `feat(admin): listar e atualizar usuarios com concorrencia otimista`)

---

## Self-review

**Cobertura da spec (Fase 2 do doc de análise §10 e regras v2 §7, §8, §11):** solution 3+2 projetos (T01) · compose (T02) · DbUp + role sem BYPASSRLS (T03) · matriz de permissões fixa + previsão de comissão com clamp (T04) · `DbSessao` com `app.*` + prova de RLS + rollback (T05) · auth própria, cookie HttpOnly, rate limit, `log_acesso`, `ultimo_login_em` (T06) · `RequerPermissao` 403 ProblemDetails (T07) · Serilog JSON, ProblemDetails, 422/409/500, health (T08) · convite/reset por token único com validade, e-mail Resend com fallback de log (T09) · jobs por CLI para Container Apps Jobs + `job_execucao` (T10) · CI + Dockerfile (T11) · endpoint vertical com `xmin` e regra "último dono" (T12). Fora deste plano, de propósito: frontend, storage R2, auditoria/timeline (trigger já existe no schema; endpoint de leitura é Fase 6), deploy Azure (Fase 6), MFA.

**Placeholders:** nenhum "TBD"/"implementar depois". Todo passo de código traz o código.

**Consistência de tipos:** `ContextoSessao(Guid AgenciaId, Guid? UsuarioId, string? Motivo)` igual em T05/T06/T09/T12 · `DbSessaoFactory.AbrirAsync(ContextoSessao, CancellationToken)` igual em todos · `UsuarioAtual.De(ClaimsPrincipal)` usado em T07 · `Permissao.Chave()` usado em T07 · `PerfilExtensions.DoBanco/ParaBanco` usados em T06/T09/T12 · `AuthExtensions.PoliticaLogin` usado em T09 · `MapDevEndpoints` criado em T08 e estendido em T07 (T07 depende de T08) · `IEnviadorEmail` em T09 e `EmailFake` · `JobRunner.ExecutarAsync(string, CancellationToken) : Task<int>` em T10.

**Colisões de arquivo por onda:** Onda 1 — T02 (`docker-compose.yml`, `scripts/`, `appsettings.Development.json`, `docs/dev.md`), T03 (`Data/Migrations`, `Data/Migrator.cs`, `Api/Data/MigrationsExtensions.cs`, `Api.Tests/Fixtures`, `MigrationsTests.cs`), T04 (`Domain/Comum/{Perfil,Permissao,Permissoes}.cs`, `Domain/Financeiro`, `Domain.Tests`), T11 (`.github`, `Dockerfile`, `.dockerignore`) — disjuntos. Onda 2 — T05 (`Data/Sessao`, `Api/Data/SessaoExtensions.cs`, `SessaoTests.cs`), T08 (`Domain/Comum/{RegraDeNegocio,ConflitoConcorrencia}Exception.cs`, `Api/Infra/*`, `InfraTests.cs`) — disjuntos. Onda 3 — T06 (`Api/Auth/{AuthExtensions,AuthEndpoints,SenhaHasher,UsuarioAtual,LoginService}.cs`, `AuthTests.cs`), T10 (`Api/Jobs/*`, `JobsTests.cs`) — disjuntos. Onda 4 — T07 (`Api/Auth/Autorizacao.cs`, `Api/Infra/DevEndpoints.cs`, `AutorizacaoTests.cs`), T09 (`Api/Infra/Email/*`, `Api/Auth/{ConviteService,ConviteEndpoints,AuthExtensions}.cs`, `Data/Migrations/0003_*.sql`, `Fixtures/EmailFake.cs`, `ConviteTests.cs`) — disjuntos (T07 não toca `AuthExtensions.cs`). Onda 5 — T12 sozinha.
