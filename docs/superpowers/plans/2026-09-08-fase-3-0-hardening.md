# Meridiano — Fase 3.0 — Hardening de acesso e integridade: Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execução em ondas:** segue `.claude/rules/parallel-subagent-driven-development.md`. Cada task traz `Files:` e `Depends-on:`. Implementadores **não commitam**; reportam os arquivos tocados. O controlador commita uma task por vez. Tasks 1–6 são no repo `backend/` (`meridiano-api`); Task 7 é no root (`meridiano-root`, só docs).

**Goal:** fechar as falhas preexistentes de sessão, token, concorrência, tradução de erros, isolamento de views e jobs, e entregar as três guardas comuns (referência por tenant, lock de viagem, competência aberta) que todos os módulos da Fase 3 vão usar — tudo com teste de integração em Postgres real.

**Architecture:** só backend. Uma migration (`0012_hardening.sql`) corrige o banco (views `security_invoker`, índices únicos parciais, FKs do log documental, `id` + auditoria em `fechamento_periodo`, duas funções `security definer` para sessão e jobs). O C# ganha: revalidação do cookie por request (`OnValidatePrincipal`), consumo atômico de token, lock advisory na guarda de último dono, mapeamento de `PostgresException` em ProblemDetails, `JobRunner` com exclusão mútua e execução por agência, e `Modules/Comum/Guardas.cs` com as três guardas. Nenhuma tela; nenhum endpoint novo além dos de `_dev`.

**Tech Stack:** .NET 10 · Dapper · Npgsql · DbUp · PostgreSQL 17 · xUnit + Testcontainers.

**Spec:** `docs/superpowers/plans/2026-09-08-fase-3-master.md` (linha 3.0 da tabela + "Contratos transversais") · `regras-e-escopo-v2.md` §5 (repasse), §7.2 (DTO por perfil), §8 (fechamento), §9 (pendências) · `docs/BACKLOG.md` (pendências marcadas **(3.0)**).

## Global Constraints

- `Program.cs` não muda. `TreatWarningsAsErrors=true`. `dotnet format --verify-no-changes` limpo.
- Toda query em tabela de tenant roda em `DbSessao`; conexão solta só para login, token, migrations, `job_execucao` e as duas funções `security definer` novas.
- Toda query Dapper filtra `agencia_id` e `excluido_em is null` onde a tabela tem a coluna.
- Erros: `RegraDeNegocioException(codigo, mensagem)` → 422; `ConflitoConcorrenciaException` → 409; nunca vazar texto de constraint/SQL no `detail`.
- Testes de integração em `tests/Meridiano.Api.Tests`, coleção `db`, Postgres real (Docker). Sem mock de banco. Cada teste cria a própria agência (nome único) — o container é compartilhado.
- Toda view nova daqui em diante nasce `with (security_invoker = on)`; o teste `Todas_as_views_executam_como_invoker` (Task 1) falha se esquecer.
- Commits Conventional Commits em inglês com rodapé de atribuição da sessão.
- Verificação final de cada task: `cd backend && dotnet build -c Release && dotnet test` → 0 falhas.

---

## Ondas

| Onda | Tasks | Motivo |
|---|---|---|
| 0 | T1, T2, T4 | Arquivos disjuntos: T1 = migration + fixture + `MigrationsTests`/`ViewsTests`; T2 = `Infra/` + `InfraTests`; T4 = `Modules/Admin/` + `UsuariosTests` |
| 1 | T3, T5, T6 | T3 usa `sessao_usuario()` (T1); T5 usa `listar_agencias_ativas()` (T1); T6 usa helpers da fixture (T1) e `Guardas` chama `RegraDeNegocioException` já existente. Arquivos disjuntos entre si |
| 2 | T7 | Docs no root após tudo verde |

---

### Task 1 (backend): Migration `0012_hardening.sql`, helpers da fixture, testes de views

**Files:**
- Create: `backend/src/Meridiano.Data/Migrations/0012_hardening.sql`
- Create: `backend/tests/Meridiano.Api.Tests/ViewsTests.cs`
- Modify: `backend/tests/Meridiano.Api.Tests/MigrationsTests.cs` (+3 testes)
- Modify: `backend/tests/Meridiano.Api.Tests/Fixtures/PostgresFixture.cs` (+4 helpers)

**Depends-on:** none

**Interfaces:**
- Produces (banco):
  - Todas as views de `public` com `security_invoker = on` (RLS da role chamadora vale em leitura por view).
  - `vw_viagem_titular` ganha coluna `agencia_id` (última) e ignora cliente com `excluido_em`.
  - Índices únicos parciais: `ux_viagem_passageiro_titular (viagem_id) where titular` · `ux_repasse_ativo (viagem_id) where excluido_em is null` (substitui `repasse_unico`) · `ux_despesa_sucessora (recorrencia_origem_id) where recorrencia_origem_id is not null` (substitui `ix_despesa_recorrencia`).
  - `log_acesso_documento`: FKs `documento_id`/`anexo_id` com `on delete set null`; check `log_acesso_documento_alvo` removido (linha sobrevive ao expurgo do alvo).
  - `fechamento_periodo.id uuid not null default gen_random_uuid() unique` + trigger `aud_fechamento`.
  - `sessao_usuario(p_id uuid) returns table (ativo boolean, perfil text, agencia_id uuid)` — `security definer`, grant para `meridiano_api`.
  - `listar_agencias_ativas() returns setof uuid` — `security definer`, grant para `meridiano_api`.
- Produces (fixture): `InserirFornecedorAsync(Guid agenciaId, string nome) → Guid` · `InserirViagemAsync(Guid agenciaId, Guid clienteId, Guid vendedorId) → Guid` · `InserirPassageiroAsync(Guid agenciaId, Guid viagemId, Guid clienteId, bool titular = true) → Task` · `InserirReservaAsync(Guid agenciaId, Guid viagemId, Guid fornecedorId, decimal valorComissao, bool cancelada = false, bool comissaoMantida = false) → Guid`.

- [ ] **Step 1: Helpers na fixture**

Acrescentar ao final de `PostgresFixture`:
```csharp
    public async Task<Guid> InserirFornecedorAsync(Guid agenciaId, string nome) =>
        (await QueryOwnerAsync<Guid>("insert into fornecedor (agencia_id, nome) values (@agenciaId, @nome) returning id", new { agenciaId, nome })).Single();

    // codigo vem do trigger trg_viagem_codigo
    public async Task<Guid> InserirViagemAsync(Guid agenciaId, Guid clienteId, Guid vendedorId) =>
        (await QueryOwnerAsync<Guid>(
            "insert into viagem (agencia_id, cliente_id, vendedor_id, destino, data_ida, data_volta) values (@agenciaId, @clienteId, @vendedorId, 'Lisboa', current_date + 30, current_date + 40) returning id",
            new { agenciaId, clienteId, vendedorId })).Single();

    public Task InserirPassageiroAsync(Guid agenciaId, Guid viagemId, Guid clienteId, bool titular = true) =>
        QueryOwnerAsync<int>("insert into viagem_passageiro (agencia_id, viagem_id, cliente_id, titular) values (@agenciaId, @viagemId, @clienteId, @titular) returning 1", new { agenciaId, viagemId, clienteId, titular });

    public async Task<Guid> InserirReservaAsync(Guid agenciaId, Guid viagemId, Guid fornecedorId, decimal valorComissao, bool cancelada = false, bool comissaoMantida = false) =>
        (await QueryOwnerAsync<Guid>(
            """
            insert into reserva (agencia_id, viagem_id, fornecedor_id, valor_total, valor_cliente, valor_comissao, status,
                                 cancelada_em, motivo_cancelamento, desfecho_cancelamento, comissao_mantida, data_prevista_comissao)
            values (@agenciaId, @viagemId, @fornecedorId, 1000, 1000, @valorComissao, @status,
                    @canceladaEm, @motivo, @desfecho, @comissaoMantida, current_date + 60)
            returning id
            """,
            new
            {
                agenciaId, viagemId, fornecedorId, valorComissao, comissaoMantida,
                status = cancelada ? "cancelada" : "emitida",
                canceladaEm = cancelada ? DateTime.UtcNow : (DateTime?)null,
                motivo = cancelada ? "teste" : null,
                desfecho = cancelada ? "sem_reembolso" : null,
            })).Single();
```

- [ ] **Step 2: Testes que falham antes da migration**

`MigrationsTests.cs`, acrescentar:
```csharp
    [Fact]
    public async Task Todas_as_views_executam_como_invoker()
    {
        var semInvoker = await pg.QueryOwnerAsync<string>(
            """
            select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relkind = 'v'
               and not exists (select 1 from unnest(c.reloptions) o where o in ('security_invoker=on', 'security_invoker=true'))
            """);
        Assert.Empty(semInvoker);
    }

    [Fact]
    public async Task Indices_unicos_parciais_do_hardening_existem()
    {
        var nomes = await pg.QueryOwnerAsync<string>(
            "select indexname from pg_indexes where schemaname = 'public' and indexname in ('ux_viagem_passageiro_titular','ux_repasse_ativo','ux_despesa_sucessora')");
        Assert.Equal(3, nomes.Count());
        var antigos = await pg.QueryOwnerAsync<string>(
            "select conname from pg_constraint where conname = 'repasse_unico' union all select indexname from pg_indexes where indexname = 'ix_despesa_recorrencia'");
        Assert.Empty(antigos);
    }

    [Fact]
    public async Task Funcoes_de_sessao_e_jobs_liberadas_para_a_api_e_fechamento_tem_id_auditado()
    {
        Assert.True((await pg.QueryOwnerAsync<bool>("select has_function_privilege('meridiano_api', 'sessao_usuario(uuid)', 'execute')")).Single());
        Assert.True((await pg.QueryOwnerAsync<bool>("select has_function_privilege('meridiano_api', 'listar_agencias_ativas()', 'execute')")).Single());
        var trigger = await pg.QueryOwnerAsync<string>("select tgname from pg_trigger where tgname = 'aud_fechamento'");
        Assert.Single(trigger);
        var coluna = await pg.QueryOwnerAsync<string>("select column_name from information_schema.columns where table_name = 'fechamento_periodo' and column_name = 'id'");
        Assert.Single(coluna);
    }
```

`ViewsTests.cs` (novo):
```csharp
using Dapper;
using Npgsql;
using Meridiano.Api.Tests.Fixtures;
using Meridiano.Data.Sessao;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class ViewsTests(PostgresFixture pg)
{
    private async Task<(Guid Agencia, Guid Viagem)> AgenciaComViagemAsync(string nome)
    {
        var a = await pg.InserirAgenciaAsync(nome);
        var vendedor = await pg.InserirUsuarioAsync(a, $"v@{nome}.com", null, "agente");
        var cliente = await pg.InserirClienteAsync(a, $"Titular {nome}");
        var viagem = await pg.InserirViagemAsync(a, cliente, vendedor);
        await pg.InserirPassageiroAsync(a, viagem, cliente);
        return (a, viagem);
    }

    [Theory]
    [InlineData("vw_resultado_viagem")]
    [InlineData("vw_viagem_titular")]
    [InlineData("vw_fase_viagem")]
    public async Task View_com_a_role_da_api_so_mostra_a_agencia_do_contexto(string view)
    {
        var (a, _) = await AgenciaComViagemAsync($"vw-a-{view}");
        var (b, _) = await AgenciaComViagemAsync($"vw-b-{view}");

        var factory = new DbSessaoFactory(pg.ConnApi);
        await using var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), CancellationToken.None);
        var agencias = await s.Conexao.QueryAsync<Guid>($"select distinct agencia_id from {view}", transaction: s.Transacao);
        Assert.Equal([a], agencias);

        await using var solta = new NpgsqlConnection(pg.ConnApi);
        Assert.Equal(0, await solta.ExecuteScalarAsync<long>($"select count(*) from {view}"));
        _ = b;
    }

    [Fact]
    public async Task Titular_ignora_cliente_excluido()
    {
        var (a, viagem) = await AgenciaComViagemAsync("vw-titular-excl");
        await pg.QueryOwnerAsync<int>("update cliente set excluido_em = now() where agencia_id = @a returning 1", new { a });

        var factory = new DbSessaoFactory(pg.ConnApi);
        await using var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), CancellationToken.None);
        var nomes = await s.Conexao.QueryAsync<string>("select nome from vw_viagem_titular where viagem_id = @viagem", new { viagem }, s.Transacao);
        Assert.Empty(nomes);
    }

    [Fact]
    public async Task Reserva_cancelada_com_comissao_mantida_continua_a_receber_e_sem_comissao_mantida_nao_conta()
    {
        // Regra da spec §4.2: cancelada sem comissao_mantida zera o esperado; com comissao_mantida a comissão continua devida.
        var (a, viagem) = await AgenciaComViagemAsync("vw-fase-cancel");
        var fornecedor = await pg.InserirFornecedorAsync(a, "Op");
        await pg.InserirReservaAsync(a, viagem, fornecedor, 100, cancelada: true, comissaoMantida: false);

        var factory = new DbSessaoFactory(pg.ConnApi);
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), CancellationToken.None))
        {
            var fase = await s.Conexao.ExecuteScalarAsync<string>("select fase_financeira from vw_fase_viagem where viagem_id = @viagem", new { viagem }, s.Transacao);
            Assert.Equal("nao_prevista", fase);
        }

        await pg.InserirReservaAsync(a, viagem, fornecedor, 100, cancelada: true, comissaoMantida: true);
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), CancellationToken.None))
        {
            var fase = await s.Conexao.ExecuteScalarAsync<string>("select fase_financeira from vw_fase_viagem where viagem_id = @viagem", new { viagem }, s.Transacao);
            Assert.Equal("a_receber", fase);
        }
    }

    [Fact]
    public async Task Segundo_titular_na_mesma_viagem_e_rejeitado()
    {
        var (a, viagem) = await AgenciaComViagemAsync("vw-titular-2");
        var outro = await pg.InserirClienteAsync(a, "Outro");
        var ex = await Assert.ThrowsAsync<PostgresException>(() => pg.InserirPassageiroAsync(a, viagem, outro, titular: true));
        Assert.Equal("23505", ex.SqlState);
    }
}
```

- [ ] **Step 3: Rodar para ver falhar**

Run: `cd backend && dotnet test --filter "FullyQualifiedName~MigrationsTests|FullyQualifiedName~ViewsTests"`
Expected: FAIL — `Todas_as_views_executam_como_invoker` lista 11 views; `View_com_a_role_da_api...` devolve as duas agências; `Segundo_titular...` não lança.

- [ ] **Step 4: Migration**

`backend/src/Meridiano.Data/Migrations/0012_hardening.sql`:
```sql
-- Fase 3.0 — hardening (review externa 2026-09-08)
--  * views executam como quem chama: RLS da role da API vale também em leitura por view
--  * titular único por viagem; um repasse ativo por viagem; uma sucessora por despesa recorrente
--  * log documental sobrevive ao expurgo do alvo
--  * fechamento_periodo com id e auditoria
--  * funções security definer para revalidar sessão e listar agências (jobs)

-- 1. vw_viagem_titular: agencia_id exposto (coluna nova no fim) e cliente excluído ignorado
create or replace view vw_viagem_titular as
select distinct on (vp.viagem_id) vp.viagem_id, c.id as cliente_id, c.nome, vp.agencia_id
  from viagem_passageiro vp
  join cliente c on c.id = vp.cliente_id and c.excluido_em is null
 order by vp.viagem_id, vp.titular desc, c.nome;

-- 2. unicidades
create unique index ux_viagem_passageiro_titular on viagem_passageiro (viagem_id) where titular;

alter table repasse drop constraint repasse_unico;
create unique index ux_repasse_ativo on repasse (viagem_id) where excluido_em is null;

drop index ix_despesa_recorrencia;
-- sem filtro de excluido_em de propósito: sucessora excluída não renasce sozinha
create unique index ux_despesa_sucessora on despesa (recorrencia_origem_id) where recorrencia_origem_id is not null;

-- 3. log documental: alvo pode ser expurgado; a linha (quem, quando) fica
alter table log_acesso_documento drop constraint log_acesso_documento_alvo;
alter table log_acesso_documento drop constraint log_acesso_documento_anexo_fk;
alter table log_acesso_documento add constraint log_acesso_documento_anexo_fk
  foreign key (anexo_id) references anexo(id) on delete set null;
alter table log_acesso_documento drop constraint log_acesso_documento_documento_id_fkey;
alter table log_acesso_documento add constraint log_acesso_documento_documento_id_fkey
  foreign key (documento_id) references documento_cliente(id) on delete set null;

-- 4. fechamento_periodo: id para fn_auditoria (registro_id not null) e trigger
alter table fechamento_periodo add column id uuid not null default gen_random_uuid() unique;
create trigger aud_fechamento after insert or update or delete on fechamento_periodo
  for each row execute function fn_auditoria();

-- 5. sessão: a API revalida o cookie a cada request sem contexto de agência
create or replace function sessao_usuario(p_id uuid)
returns table (ativo boolean, perfil text, agencia_id uuid) as $$
  select u.ativo, u.perfil, u.agencia_id from usuario u where u.id = p_id
$$ language sql stable security definer set search_path = pg_catalog, public;

-- 6. jobs: iterar agências sem contexto
create or replace function listar_agencias_ativas()
returns setof uuid as $$
  select id from agencia where ativo order by id
$$ language sql stable security definer set search_path = pg_catalog, public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'meridiano_api') then
    grant execute on function sessao_usuario(uuid) to meridiano_api;
    grant execute on function listar_agencias_ativas() to meridiano_api;
  end if;
end $$;

-- 7. security_invoker em TODAS as views (por último: create or replace view acima não mexe em opções,
--    mas assim a regra vale para qualquer view que exista neste ponto)
do $$
declare v text;
begin
  for v in select table_name from information_schema.views where table_schema = 'public' loop
    execute format('alter view %I set (security_invoker = on)', v);
  end loop;
end $$;
```

Se `log_acesso_documento_documento_id_fkey` não existir com esse nome, descobrir com `select conname from pg_constraint where conrelid = 'log_acesso_documento'::regclass` na base local e ajustar; não adivinhar.

- [ ] **Step 5: Rodar tudo**

Run: `cd backend && dotnet build -c Release && dotnet test`
Expected: 0 falhas. Se `vw_resultado_viagem` (0011) reclamar da coluna nova de `vw_viagem_titular`, não reclama: ela seleciona `c.nome` por nome, não `select *`.

- [ ] **Step 6: Reportar arquivos tocados**

Commit sugerido (repo `backend/`): `feat(db): migration 0012 - security_invoker views, partial unique indexes, audited fechamento, session/job definer functions`

---

### Task 2 (backend): `PostgresException` vira ProblemDetails com código

**Files:**
- Modify: `backend/src/Meridiano.Api/Infra/TratadorDeExcecoes.cs`
- Modify: `backend/src/Meridiano.Api/Infra/DevEndpoints.cs`
- Modify: `backend/tests/Meridiano.Api.Tests/InfraTests.cs`

**Depends-on:** none

**Interfaces:**
- Produces: mapeamento fixo por `SqlState` —

| SqlState | Status | `codigo` | `detail` |
|---|---|---|---|
| `23505` unique | 409 | `duplicado` | "Registro duplicado" |
| `23503` FK | 422 | `referencia_invalida` | "Referência inválida" |
| `23514` check | 422 | `regra_banco` | "Valor não permitido" |
| `42501` RLS/privilege | 403 | `sem_acesso` | "Sem acesso ao registro" |
| outro | 500 | `erro_interno` | (inalterado) |

Extensão `constraint` com `ex.ConstraintName` quando houver (nome técnico, sem texto do banco). Módulos das fases seguintes traduzem constraints específicas **antes** (ex.: `ux_repasse_ativo` → `repasse_ja_existe`) capturando `PostgresException` no serviço; este é o fallback.

- [ ] **Step 1: Testes**

Em `InfraTests.cs`, acrescentar linhas ao `[Theory]` existente:
```csharp
    [InlineData("duplicado", HttpStatusCode.Conflict, "duplicado")]
    [InlineData("fk", HttpStatusCode.UnprocessableEntity, "referencia_invalida")]
    [InlineData("check", HttpStatusCode.UnprocessableEntity, "regra_banco")]
    [InlineData("rls", HttpStatusCode.Forbidden, "sem_acesso")]
```
e um teste novo:
```csharp
    [Fact]
    public async Task Erro_de_banco_expoe_constraint_mas_nao_o_texto_do_postgres()
    {
        await using var app = new MeridianoApiFactory(pg);
        var r = await app.CreateClient().GetAsync("/api/v1/_dev/erro/duplicado");
        var body = await r.Content.ReadFromJsonAsync<Dictionary<string, object>>();
        Assert.Equal("ux_exemplo", body!["constraint"].ToString());
        Assert.DoesNotContain("duplicate key", body["detail"].ToString());
    }
```

- [ ] **Step 2: Rodar para ver falhar** — `dotnet test --filter FullyQualifiedName~InfraTests` → FAIL (404 nos tipos novos).

- [ ] **Step 3: Implementar**

`DevEndpoints.cs`, dentro do `switch`:
```csharp
            "duplicado" => throw new PostgresException("duplicate key value violates unique constraint", "ERROR", "ERROR", "23505", constraintName: "ux_exemplo"),
            "fk" => throw new PostgresException("violates foreign key constraint", "ERROR", "ERROR", "23503"),
            "check" => throw new PostgresException("violates check constraint", "ERROR", "ERROR", "23514"),
            "rls" => throw new PostgresException("new row violates row-level security policy", "ERROR", "ERROR", "42501"),
```
(`using Npgsql;` no topo.)

`TratadorDeExcecoes.cs`, trocar o `switch` e o `detalhe`:
```csharp
        var (status, codigo, titulo, detalhe) = ex switch
        {
            RegraDeNegocioException r => (StatusCodes.Status422UnprocessableEntity, r.Codigo, "Regra de negócio", r.Message),
            ConflitoConcorrenciaException => (StatusCodes.Status409Conflict, "conflito_concorrencia", "Registro alterado por outro usuário", ex.Message),
            UnauthorizedAccessException => (StatusCodes.Status401Unauthorized, "nao_autenticado", "Não autenticado", ex.Message),
            PostgresException { SqlState: "23505" } => (StatusCodes.Status409Conflict, "duplicado", "Registro duplicado", "Registro duplicado"),
            PostgresException { SqlState: "23503" } => (StatusCodes.Status422UnprocessableEntity, "referencia_invalida", "Referência inválida", "Referência inválida"),
            PostgresException { SqlState: "23514" } => (StatusCodes.Status422UnprocessableEntity, "regra_banco", "Valor não permitido", "Valor não permitido"),
            PostgresException { SqlState: "42501" } => (StatusCodes.Status403Forbidden, "sem_acesso", "Sem acesso", "Sem acesso ao registro"),
            _ => (StatusCodes.Status500InternalServerError, "erro_interno", "Erro interno", "Erro interno. Tente novamente."),
        };

        if (status == StatusCodes.Status500InternalServerError)
        {
            log.LogError(ex, "Erro não tratado em {Metodo} {Caminho}", http.Request.Method, http.Request.Path);
        }
        else if (ex is PostgresException pg)
        {
            log.LogWarning("Erro de banco {SqlState} {Constraint} em {Metodo} {Caminho}", pg.SqlState, pg.ConstraintName, http.Request.Method, http.Request.Path);
        }

        http.Response.StatusCode = status;
        var problema = new ProblemDetails { Status = status, Title = titulo, Detail = detalhe, Extensions = { ["codigo"] = codigo } };
        if (ex is PostgresException { ConstraintName: { } c }) problema.Extensions["constraint"] = c;
        return await problemas.TryWriteAsync(new ProblemDetailsContext { HttpContext = http, Exception = ex, ProblemDetails = problema });
```
(`using Npgsql;` no topo; remover a variável `detalhe` antiga.)

- [ ] **Step 4: Rodar** — `dotnet build -c Release && dotnet test` → 0 falhas.

- [ ] **Step 5: Reportar arquivos tocados**

Commit sugerido: `feat(infra): map PostgresException (unique, fk, check, rls) to problem details with codigo`

---

### Task 3 (backend): Sessão revalidada por request, token consumido atomicamente, links de convite × reset

**Files:**
- Create: `backend/src/Meridiano.Api/Auth/ValidacaoSessao.cs`
- Modify: `backend/src/Meridiano.Api/Auth/AuthExtensions.cs:17-29`
- Modify: `backend/src/Meridiano.Api/Auth/ConviteService.cs:18,55-70,88-89`
- Modify: `backend/tests/Meridiano.Api.Tests/AuthTests.cs` (+2)
- Modify: `backend/tests/Meridiano.Api.Tests/ConviteTests.cs` (+2)

**Depends-on:** T1 (`sessao_usuario(uuid)`)

**Interfaces:**
- Consumes: `sessao_usuario(p_id uuid) → (ativo, perfil, agencia_id)`.
- Produces:
  - Cookie de usuário inativado ou inexistente → `401` no request seguinte (cookie apagado).
  - Perfil alterado no banco → principal substituído no request seguinte; `/auth/me` devolve o perfil novo.
  - `POST /auth/definir-senha` com o mesmo token em dois requests simultâneos: exatamente um `204`, o outro `422 token_invalido`.
  - E-mail de reset aponta para `{BaseUrl}/redefinir-senha?token=…`; convite continua em `/definir-senha`.

- [ ] **Step 1: Testes**

`AuthTests.cs`:
```csharp
    [Fact]
    public async Task Usuario_inativado_perde_a_sessao_no_request_seguinte()
    {
        var agencia = await pg.InserirAgenciaAsync("Auth E");
        var id = await pg.InserirUsuarioAsync(agencia, "e@auth.com", SenhaHasher.Hash("s"), "agente");
        await using var app = new MeridianoApiFactory(pg);
        var client = app.CreateClient();
        await client.PostAsJsonAsync("/api/v1/auth/login", new { email = "e@auth.com", senha = "s" });
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/v1/auth/me")).StatusCode);

        await pg.QueryOwnerAsync<int>("update usuario set ativo = false where id = @id returning 1", new { id });
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/auth/me")).StatusCode);
    }

    [Fact]
    public async Task Perfil_alterado_no_banco_vale_no_request_seguinte()
    {
        var agencia = await pg.InserirAgenciaAsync("Auth F");
        var id = await pg.InserirUsuarioAsync(agencia, "f@auth.com", SenhaHasher.Hash("s"), "dono");
        await using var app = new MeridianoApiFactory(pg);
        var client = app.CreateClient();
        await client.PostAsJsonAsync("/api/v1/auth/login", new { email = "f@auth.com", senha = "s" });

        await pg.QueryOwnerAsync<int>("update usuario set perfil = 'agente' where id = @id returning 1", new { id });
        var me = await client.GetFromJsonAsync<MeResposta>("/api/v1/auth/me");
        Assert.Equal("agente", me!.Perfil);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/v1/_dev/protegido")).StatusCode);
    }
```

`ConviteTests.cs`:
```csharp
    [Fact]
    public async Task Token_de_convite_usado_em_paralelo_so_vale_uma_vez()
    {
        var agencia = await pg.InserirAgenciaAsync("Conv4");
        await pg.InserirUsuarioAsync(agencia, "dono@conv4.com", SenhaHasher.Hash("s"), "dono");
        var (app, email) = AppComEmailFake(pg);
        await using var _ = app;
        var dono = app.CreateClient();
        await dono.PostAsJsonAsync("/api/v1/auth/login", new { email = "dono@conv4.com", senha = "s" });
        await dono.PostAsJsonAsync("/api/v1/auth/convites", new { nome = "Par", email = "par@conv4.com", perfil = "agente" });
        var token = TokenDo(email.Enviados.Single().Html);

        var anon = app.CreateClient();
        var tarefas = Enumerable.Range(0, 4).Select(i => anon.PostAsJsonAsync("/api/v1/auth/definir-senha", new { token, senha = $"senha-{i}-12345" }));
        var respostas = await Task.WhenAll(tarefas);

        Assert.Equal(1, respostas.Count(r => r.StatusCode == HttpStatusCode.NoContent));
        Assert.Equal(3, respostas.Count(r => r.StatusCode == HttpStatusCode.UnprocessableEntity));
    }

    [Fact]
    public async Task Reset_usa_redefinir_senha_e_convite_usa_definir_senha()
    {
        var agencia = await pg.InserirAgenciaAsync("Conv5");
        await pg.InserirUsuarioAsync(agencia, "dono@conv5.com", SenhaHasher.Hash("s"), "dono");
        var (app, email) = AppComEmailFake(pg);
        await using var _ = app;
        var c = app.CreateClient();
        await c.PostAsJsonAsync("/api/v1/auth/login", new { email = "dono@conv5.com", senha = "s" });
        await c.PostAsJsonAsync("/api/v1/auth/convites", new { nome = "X", email = "x@conv5.com", perfil = "agente" });
        await app.CreateClient().PostAsJsonAsync("/api/v1/auth/esqueci-senha", new { email = "dono@conv5.com" });

        Assert.Contains("/definir-senha?token=", email.Enviados[0].Html);
        Assert.Contains("/redefinir-senha?token=", email.Enviados[1].Html);
        Assert.DoesNotContain("/definir-senha?token=", email.Enviados[1].Html);
    }
```

- [ ] **Step 2: Rodar para ver falhar** — `dotnet test --filter "FullyQualifiedName~AuthTests|FullyQualifiedName~ConviteTests"` → FAIL nos 4 novos.

- [ ] **Step 3: `ValidacaoSessao.cs`**

```csharp
using System.Security.Claims;
using Dapper;
using Microsoft.AspNetCore.Authentication.Cookies;
using Npgsql;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Auth;

// Roda a cada request autenticado: o cookie carrega perfil, mas o banco manda.
// ponytail: uma query por request; cache curto por usuário se virar custo medido.
public static class ValidacaoSessao
{
    private sealed record Linha(bool Ativo, string Perfil, Guid AgenciaId);

    public static async Task ValidarAsync(CookieValidatePrincipalContext ctx)
    {
        var atual = UsuarioAtual.De(ctx.Principal!);
        if (atual is null) { Rejeitar(ctx); return; }

        var cs = ctx.HttpContext.RequestServices.GetRequiredService<IConfiguration>().GetConnectionString("Api")!;
        await using var conexao = new NpgsqlConnection(cs);
        var linha = await conexao.QuerySingleOrDefaultAsync<Linha>(
            "select ativo, perfil, agencia_id as AgenciaId from sessao_usuario(@id)", new { id = atual.UsuarioId });

        if (linha is not { Ativo: true } || linha.AgenciaId != atual.AgenciaId) { Rejeitar(ctx); return; }

        var perfil = PerfilExtensions.DoBanco(linha.Perfil);
        if (perfil != atual.Perfil)
        {
            ctx.ReplacePrincipal((atual with { Perfil = perfil }).ParaPrincipal(ctx.Scheme.Name));
            ctx.ShouldRenew = true;
        }
    }

    private static void Rejeitar(CookieValidatePrincipalContext ctx)
    {
        ctx.RejectPrincipal();
        ctx.HttpContext.Response.Cookies.Delete(ctx.Options.Cookie.Name!);
    }
}
```

`AuthExtensions.cs`, dentro de `AddCookie(o => { ... })`, após `OnRedirectToAccessDenied`:
```csharp
                o.Events.OnValidatePrincipal = ValidacaoSessao.ValidarAsync;
```

- [ ] **Step 4: `ConviteService.cs`**

Linha 18 e chamadas:
```csharp
    private string Link(string token, string rota) => $"{config["Email:BaseUrl"]}/{rota}?token={token}";
```
- no convite (linha 50): `Link(token, "definir-senha")` (duas ocorrências);
- no reset (linha 89): `Link(token, "redefinir-senha")` (duas ocorrências).

`DefinirSenhaAsync` — manter o lookup (precisa da agência para abrir a sessão) e tornar o UPDATE a autoridade:
```csharp
        await using var s = await sessoes.AbrirAsync(new ContextoSessao(alvo.AgenciaId, alvo.Id, null), ct);
        var linhas = await s.Conexao.ExecuteAsync(
            """
            update usuario
               set senha_hash = @hash, convite_token = null, convite_expira_em = null, reset_token = null, reset_expira_em = null
             where id = @id and agencia_id = @agencia and ativo
               and ((convite_token = @token and convite_expira_em > now()) or (reset_token = @token and reset_expira_em > now()))
            """,
            new { hash = SenhaHasher.Hash(senha), id = alvo.Id, agencia = alvo.AgenciaId, token }, s.Transacao);
        if (linhas == 0) throw new RegraDeNegocioException("token_invalido", "Token inválido ou expirado");
        await s.ConfirmarAsync(ct);
```
Por que funciona sob concorrência: o primeiro UPDATE trava a linha; o segundo espera o commit, reavalia o `where` (token já nulo) e afeta 0 linhas.

- [ ] **Step 5: Rodar** — `dotnet build -c Release && dotnet test` → 0 falhas. Os testes antigos de convite/reset continuam passando porque `TokenDo` só lê `token=`.

- [ ] **Step 6: Reportar arquivos tocados**

Commit sugerido: `fix(auth): revalidate cookie against db per request; consume invite/reset token atomically; separate reset link`

---

### Task 4 (backend): Guarda de último dono serializada por agência

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Admin/UsuarioService.cs:24-32`
- Modify: `backend/tests/Meridiano.Api.Tests/UsuariosTests.cs` (+1)

**Depends-on:** none

**Interfaces:**
- Produces: duas desativações simultâneas dos dois últimos donos → exatamente uma `200`, a outra `422 ultimo_dono`.

- [ ] **Step 1: Teste**

```csharp
    [Fact]
    public async Task Dois_donos_se_desativando_ao_mesmo_tempo_deixam_um_ativo()
    {
        var a = await pg.InserirAgenciaAsync("Usr E");
        var d1 = await pg.InserirUsuarioAsync(a, "d1@usre.com", SenhaHasher.Hash("s"), "dono");
        var d2 = await pg.InserirUsuarioAsync(a, "d2@usre.com", SenhaHasher.Hash("s"), "dono");
        await using var app = new MeridianoApiFactory(pg);
        var c1 = await DonoAsync(app, "d1@usre.com");
        var c2 = await DonoAsync(app, "d2@usre.com");
        var lista = (await c1.GetFromJsonAsync<UsuarioDto[]>("/api/v1/usuarios"))!;
        var u1 = lista.Single(u => u.Id == d1);
        var u2 = lista.Single(u => u.Id == d2);

        object Req(UsuarioDto u) => new { nome = u.Nome, telefone = (string?)null, perfil = "dono", geraRepasse = false, percentualPadrao = 0m, ativo = false, versao = u.Versao };
        var respostas = await Task.WhenAll(
            Enumerable.Range(0, 3).Select(_ => c1.PutAsJsonAsync($"/api/v1/usuarios/{d2}", Req(u2)))
            .Concat(Enumerable.Range(0, 3).Select(_ => c2.PutAsJsonAsync($"/api/v1/usuarios/{d1}", Req(u1)))));

        Assert.Equal(1, respostas.Count(r => r.StatusCode == HttpStatusCode.OK));
        var ativos = await pg.QueryOwnerAsync<long>("select count(*) from usuario where agencia_id = @a and perfil = 'dono' and ativo", new { a });
        Assert.Equal(1, ativos.Single());
    }
```
(As repetições com a mesma `versao` caem em 409 depois que uma passa; só a contagem de `OK` e o estado final importam.)

- [ ] **Step 2: Rodar para ver falhar** — `dotnet test --filter FullyQualifiedName~UsuariosTests` → FAIL: `ativos` = 0 (ou o teste passa por acaso; rodar 3× — sem o lock, falha em alguma).

- [ ] **Step 3: Implementar**

Em `AtualizarAsync`, antes do `if (!req.Ativo || perfil != Perfil.Dono)`:
```csharp
        // Serializa mudanças de dono por agência: a guarda abaixo lê duas linhas e decide.
        await s.Conexao.ExecuteAsync("select pg_advisory_xact_lock(hashtext('donos:' || @agencia::text))", new { agencia = ctx.AgenciaId }, s.Transacao);
```

- [ ] **Step 4: Rodar** — `dotnet build -c Release && dotnet test` → 0 falhas.

- [ ] **Step 5: Reportar arquivos tocados**

Commit sugerido: `fix(admin): serialize last-owner guard with per-agency advisory lock`

---

### Task 5 (backend): `JobRunner` com exclusão mútua e execução por agência

**Files:**
- Modify: `backend/src/Meridiano.Api/Jobs/IJob.cs`
- Modify: `backend/src/Meridiano.Api/Jobs/JobRunner.cs`
- Modify: `backend/src/Meridiano.Api/Jobs/PingJob.cs`
- Modify: `backend/tests/Meridiano.Api.Tests/JobsTests.cs` (+2)

**Depends-on:** T1 (`listar_agencias_ativas()`)

**Interfaces:**
- Consumes: `listar_agencias_ativas() → setof uuid`; `DbSessaoFactory` já registrado por `AddSessao`.
- Produces:
```csharp
public interface IJob
{
    string Nome { get; }
    bool PorAgencia { get; }                                  // true: ExecutarAsync é chamado uma vez por agência ativa, com agenciaId
    Task ExecutarAsync(Guid? agenciaId, CancellationToken ct); // agenciaId null quando PorAgencia = false
}
```
  - `JobRunner.ExecutarAsync(nome, ct)` devolve `3` se outra instância do mesmo job estiver rodando (lock `pg_try_advisory_lock(hashtext('job:' || nome))` na conexão de `job_execucao`; solto ao fechar a conexão).
  - Jobs por agência abrem a própria `DbSessao` com `new ContextoSessao(agenciaId, null, $"job:{Nome}")`; falha em uma agência é registrada em `job_execucao.detalhe` e o job segue para a próxima; resultado final `1` se alguma falhou.

- [ ] **Step 1: Testes**

```csharp
    private sealed class JobFake : IJob
    {
        public string Nome => "fake";
        public bool PorAgencia => true;
        public List<Guid> Agencias { get; } = [];
        public TaskCompletionSource Segurar { get; } = new();
        public async Task ExecutarAsync(Guid? agenciaId, CancellationToken ct)
        {
            Agencias.Add(agenciaId!.Value);
            await Segurar.Task;
        }
    }

    [Fact]
    public async Task Job_por_agencia_roda_uma_vez_por_agencia_ativa()
    {
        var a = await pg.InserirAgenciaAsync("Job A");
        var b = await pg.InserirAgenciaAsync("Job B");
        var fake = new JobFake();
        fake.Segurar.SetResult();
        await using var app = new MeridianoApiFactory(pg).WithWebHostBuilder(w => w.ConfigureServices(s => s.AddScoped<IJob>(_ => fake)));
        using var scope = app.Services.CreateScope();
        var codigo = await scope.ServiceProvider.GetRequiredService<JobRunner>().ExecutarAsync("fake", CancellationToken.None);

        Assert.Equal(0, codigo);
        Assert.Contains(a, fake.Agencias);
        Assert.Contains(b, fake.Agencias);
    }

    [Fact]
    public async Task Mesmo_job_em_paralelo_retorna_3_na_segunda_instancia()
    {
        var fake = new JobFake();
        await using var app = new MeridianoApiFactory(pg).WithWebHostBuilder(w => w.ConfigureServices(s => s.AddScoped<IJob>(_ => fake)));
        using var s1 = app.Services.CreateScope();
        using var s2 = app.Services.CreateScope();

        var primeira = s1.ServiceProvider.GetRequiredService<JobRunner>().ExecutarAsync("fake", CancellationToken.None);
        await Task.Delay(300); // primeira já segurou o lock e está esperando Segurar
        var segunda = await s2.ServiceProvider.GetRequiredService<JobRunner>().ExecutarAsync("fake", CancellationToken.None);
        Assert.Equal(3, segunda);

        fake.Segurar.SetResult();
        Assert.Equal(0, await primeira);
    }
```
(`using Microsoft.AspNetCore.Hosting;` no topo. `Job_por_agencia` precisa de agências ativas: as criadas por outros testes também entram na lista — só asserta `Contains`.)

- [ ] **Step 2: Rodar para ver falhar** — `dotnet test --filter FullyQualifiedName~JobsTests` → FAIL de compilação (`PorAgencia` não existe).

- [ ] **Step 3: Implementar**

`IJob.cs`: substituir pelo bloco em Interfaces.

`PingJob.cs`:
```csharp
    public bool PorAgencia => false;

    public async Task ExecutarAsync(Guid? agenciaId, CancellationToken ct)
```
(corpo inalterado).

`JobRunner.cs`:
```csharp
using Dapper;
using Npgsql;
using Meridiano.Data.Sessao;

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

        // Lock de sessão: cai sozinho quando a conexão fecha (fim do método), inclusive em crash.
        await using var c = new NpgsqlConnection(config.GetConnectionString("Api"));
        await c.OpenAsync(ct);
        var travou = await c.ExecuteScalarAsync<bool>("select pg_try_advisory_lock(hashtext('job:' || @nome))", new { nome });
        if (!travou)
        {
            log.LogWarning("Job {Nome} já está em execução", nome);
            return 3;
        }

        var id = await c.ExecuteScalarAsync<long>("insert into job_execucao (nome) values (@nome) returning id", new { nome });
        var falhas = new List<string>();
        try
        {
            if (!job.PorAgencia)
            {
                await job.ExecutarAsync(null, ct);
            }
            else
            {
                foreach (var agencia in await c.QueryAsync<Guid>("select listar_agencias_ativas()"))
                {
                    try { await job.ExecutarAsync(agencia, ct); }
                    catch (Exception ex) when (ex is not OperationCanceledException)
                    {
                        falhas.Add($"{agencia}: {ex}");
                        log.LogError(ex, "Job {Nome} falhou na agência {Agencia}", nome, agencia);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            falhas.Add(ex.ToString());
            log.LogError(ex, "Job {Nome} falhou", nome);
        }

        var sucesso = falhas.Count == 0;
        await c.ExecuteAsync("update job_execucao set terminado_em = now(), sucesso = @sucesso, detalhe = @d where id = @id",
            new { id, sucesso, d = sucesso ? null : string.Join("\n---\n", falhas) });
        log.LogInformation("Job {Nome} concluído: {Resultado}", nome, sucesso ? "ok" : $"{falhas.Count} falha(s)");
        return sucesso ? 0 : 1;
    }
}
```
`JobsExtensions.cs` não muda (`DbSessaoFactory` já é injetável nos jobs que precisarem; `PingJob` não precisa).

- [ ] **Step 4: Rodar** — `dotnet build -c Release && dotnet test` → 0 falhas.

- [ ] **Step 5: Reportar arquivos tocados**

Commit sugerido: `feat(jobs): per-job advisory lock and per-agency execution in JobRunner`

---

### Task 6 (backend): `Guardas` — referência por tenant, lock de viagem, competência aberta

**Files:**
- Create: `backend/src/Meridiano.Api/Modules/Comum/Guardas.cs`
- Create: `backend/tests/Meridiano.Api.Tests/GuardasTests.cs`

**Depends-on:** T1 (helpers da fixture; `fechamento_periodo.id`)

**Interfaces:**
- Consumes: `DbSessao` (`Conexao`, `Transacao`), `RegraDeNegocioException`, `ConflitoConcorrenciaException`, fixture `InserirViagemAsync`/`InserirClienteAsync`/`InserirFornecedorAsync`.
- Produces (`namespace Meridiano.Api.Modules.Comum`, `public static class Guardas`):
```csharp
public enum Tabela { Cliente, Fornecedor, Usuario, Viagem, Reserva, Grupo, Despesa }

// Existe, é da agência e não está excluído; senão 422 referencia_invalida. Usar em TODO *_id recebido no payload.
public static Task ReferenciaAsync(DbSessao s, Tabela tabela, Guid id, Guid agenciaId, CancellationToken ct);

// select ... for update na viagem; devolve xmin::text atual. Se versaoEsperada != null e diferente → 409.
// Toda mutação do agregado de viagem começa aqui.
public static Task<string> TravarViagemAsync(DbSessao s, Guid viagemId, Guid agenciaId, string? versaoEsperada, CancellationToken ct);

// Depois de mexer em filho da viagem: renova atualizado_em (e portanto o xmin/versao da viagem).
public static Task TocarViagemAsync(DbSessao s, Guid viagemId, Guid agenciaId, CancellationToken ct);

// Lock advisory por (agência, mês) + leitura de fechamento_periodo. Fechado e sem (podeEditarFechado && motivo) → 422 periodo_fechado.
// Chamar para a competência antiga E a nova quando uma data muda. Fechar/reabrir usam o mesmo lock.
public static Task CompetenciaAbertaAsync(DbSessao s, Guid agenciaId, DateOnly data, bool podeEditarFechado, string? motivo, CancellationToken ct);
public static Task TravarCompetenciaAsync(DbSessao s, Guid agenciaId, DateOnly competencia, CancellationToken ct);
```

- [ ] **Step 1: Testes**

`GuardasTests.cs`:
```csharp
using Dapper;
using Meridiano.Api.Modules.Comum;
using Meridiano.Api.Tests.Fixtures;
using Meridiano.Data.Sessao;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Tests;

[Collection("db")]
public sealed class GuardasTests(PostgresFixture pg)
{
    private static readonly CancellationToken Ct = CancellationToken.None;

    private async Task<(Guid Agencia, Guid Cliente, Guid Viagem)> BaseAsync(string nome)
    {
        var a = await pg.InserirAgenciaAsync(nome);
        var vendedor = await pg.InserirUsuarioAsync(a, $"v@{nome}.com", null, "agente");
        var cliente = await pg.InserirClienteAsync(a, "C");
        var viagem = await pg.InserirViagemAsync(a, cliente, vendedor);
        return (a, cliente, viagem);
    }

    [Fact]
    public async Task Referencia_de_outra_agencia_ou_excluida_e_422()
    {
        var (a, clienteA, _) = await BaseAsync("guarda-ref-a");
        var (_, clienteB, _) = await BaseAsync("guarda-ref-b");
        var excluido = await pg.InserirClienteAsync(a, "Excluído");
        await pg.QueryOwnerAsync<int>("update cliente set excluido_em = now() where id = @excluido returning 1", new { excluido });

        var factory = new DbSessaoFactory(pg.ConnApi);
        await using var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), Ct);

        await Guardas.ReferenciaAsync(s, Tabela.Cliente, clienteA, a, Ct); // não lança
        var ex1 = await Assert.ThrowsAsync<RegraDeNegocioException>(() => Guardas.ReferenciaAsync(s, Tabela.Cliente, clienteB, a, Ct));
        Assert.Equal("referencia_invalida", ex1.Codigo);
        var ex2 = await Assert.ThrowsAsync<RegraDeNegocioException>(() => Guardas.ReferenciaAsync(s, Tabela.Cliente, excluido, a, Ct));
        Assert.Equal("referencia_invalida", ex2.Codigo);
    }

    [Fact]
    public async Task Travar_viagem_confere_versao_e_tocar_renova()
    {
        var (a, _, viagem) = await BaseAsync("guarda-lock");
        var factory = new DbSessaoFactory(pg.ConnApi);

        string v1;
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), Ct))
        {
            v1 = await Guardas.TravarViagemAsync(s, viagem, a, null, Ct);
            await Guardas.TocarViagemAsync(s, viagem, a, Ct);
            await s.ConfirmarAsync(Ct);
        }
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), Ct))
        {
            var ex = await Assert.ThrowsAsync<ConflitoConcorrenciaException>(() => Guardas.TravarViagemAsync(s, viagem, a, v1, Ct));
            Assert.NotNull(ex);
            var v2 = await Guardas.TravarViagemAsync(s, viagem, a, null, Ct);
            Assert.NotEqual(v1, v2);
        }
    }

    [Fact]
    public async Task Travar_viagem_bloqueia_a_segunda_sessao_ate_o_commit()
    {
        var (a, _, viagem) = await BaseAsync("guarda-lock-2");
        var factory = new DbSessaoFactory(pg.ConnApi);

        await using var s1 = await factory.AbrirAsync(new ContextoSessao(a, null, null), Ct);
        await Guardas.TravarViagemAsync(s1, viagem, a, null, Ct);

        await using var s2 = await factory.AbrirAsync(new ContextoSessao(a, null, null), Ct);
        var segunda = Guardas.TravarViagemAsync(s2, viagem, a, null, Ct);
        Assert.False(segunda.Wait(TimeSpan.FromMilliseconds(500)), "segunda sessão não deveria obter o lock antes do commit");

        await s1.ConfirmarAsync(Ct);
        await segunda; // libera
    }

    [Fact]
    public async Task Viagem_de_outra_agencia_nao_e_travavel()
    {
        var (a, _, _) = await BaseAsync("guarda-lock-3a");
        var (_, _, viagemB) = await BaseAsync("guarda-lock-3b");
        var factory = new DbSessaoFactory(pg.ConnApi);
        await using var s = await factory.AbrirAsync(new ContextoSessao(a, null, null), Ct);
        var ex = await Assert.ThrowsAsync<RegraDeNegocioException>(() => Guardas.TravarViagemAsync(s, viagemB, a, null, Ct));
        Assert.Equal("nao_encontrado", ex.Codigo);
    }

    [Fact]
    public async Task Competencia_fechada_exige_permissao_e_motivo()
    {
        var (a, _, _) = await BaseAsync("guarda-comp");
        var dono = await pg.InserirUsuarioAsync(a, "dono@guarda-comp.com", null, "dono");
        await pg.QueryOwnerAsync<int>("insert into fechamento_periodo (agencia_id, competencia, fechado_por) values (@a, date '2026-07-01', @dono) returning 1", new { a, dono });

        var factory = new DbSessaoFactory(pg.ConnApi);
        await using var s = await factory.AbrirAsync(new ContextoSessao(a, dono, "ajuste"), Ct);

        await Guardas.CompetenciaAbertaAsync(s, a, new DateOnly(2026, 8, 15), false, null, Ct); // agosto aberto
        var ex = await Assert.ThrowsAsync<RegraDeNegocioException>(() => Guardas.CompetenciaAbertaAsync(s, a, new DateOnly(2026, 7, 20), false, null, Ct));
        Assert.Equal("periodo_fechado", ex.Codigo);
        var ex2 = await Assert.ThrowsAsync<RegraDeNegocioException>(() => Guardas.CompetenciaAbertaAsync(s, a, new DateOnly(2026, 7, 20), true, null, Ct));
        Assert.Equal("motivo_obrigatorio", ex2.Codigo);
        await Guardas.CompetenciaAbertaAsync(s, a, new DateOnly(2026, 7, 20), true, "ajuste", Ct); // passa
    }

    [Fact]
    public async Task Fechamento_e_auditado()
    {
        var (a, _, _) = await BaseAsync("guarda-aud");
        var dono = await pg.InserirUsuarioAsync(a, "dono@guarda-aud.com", null, "dono");
        var factory = new DbSessaoFactory(pg.ConnApi);
        await using (var s = await factory.AbrirAsync(new ContextoSessao(a, dono, "fechar julho"), Ct))
        {
            await s.Conexao.ExecuteAsync("insert into fechamento_periodo (agencia_id, competencia, fechado_por) values (@a, date '2026-07-01', @dono)", new { a, dono }, s.Transacao);
            await s.ConfirmarAsync(Ct);
        }
        var aud = await pg.QueryOwnerAsync<(string Acao, string? Motivo)>("select acao, motivo from auditoria where tabela = 'fechamento_periodo' and agencia_id = @a", new { a });
        var (acao, motivo) = aud.Single();
        Assert.Equal("INSERT", acao);
        Assert.Equal("fechar julho", motivo);
    }
}
```

- [ ] **Step 2: Rodar para ver falhar** — `dotnet test --filter FullyQualifiedName~GuardasTests` → FAIL de compilação.

- [ ] **Step 3: Implementar `Guardas.cs`**

```csharp
using Dapper;
using Meridiano.Data.Sessao;
using Meridiano.Domain.Comum;

namespace Meridiano.Api.Modules.Comum;

public enum Tabela { Cliente, Fornecedor, Usuario, Viagem, Reserva, Grupo, Despesa }

// Guardas comuns a todos os módulos. Sem estado, sem framework: três queries que todo mundo precisa.
public static class Guardas
{
    // Lista fechada: o nome vai interpolado no SQL, então nunca vem de fora.
    private static readonly Dictionary<Tabela, (string Nome, bool TemExcluidoEm)> Tabelas = new()
    {
        [Tabela.Cliente] = ("cliente", true),
        [Tabela.Fornecedor] = ("fornecedor", true),
        [Tabela.Usuario] = ("usuario", false),
        [Tabela.Viagem] = ("viagem", true),
        [Tabela.Reserva] = ("reserva", true),
        [Tabela.Grupo] = ("grupo_cliente", true),
        [Tabela.Despesa] = ("despesa", true),
    };

    public static async Task ReferenciaAsync(DbSessao s, Tabela tabela, Guid id, Guid agenciaId, CancellationToken ct)
    {
        var (nome, temExcluido) = Tabelas[tabela];
        var filtroExcluido = temExcluido ? " and excluido_em is null" : "";
        var existe = await s.Conexao.ExecuteScalarAsync<bool>(new CommandDefinition(
            $"select exists (select 1 from {nome} where id = @id and agencia_id = @agenciaId{filtroExcluido})",
            new { id, agenciaId }, s.Transacao, cancellationToken: ct));
        if (!existe) throw new RegraDeNegocioException("referencia_invalida", $"{nome} não encontrado");
    }

    public static async Task<string> TravarViagemAsync(DbSessao s, Guid viagemId, Guid agenciaId, string? versaoEsperada, CancellationToken ct)
    {
        var versao = await s.Conexao.ExecuteScalarAsync<string?>(new CommandDefinition(
            "select xmin::text from viagem where id = @viagemId and agencia_id = @agenciaId and excluido_em is null for update",
            new { viagemId, agenciaId }, s.Transacao, cancellationToken: ct));
        if (versao is null) throw new RegraDeNegocioException("nao_encontrado", "Viagem não encontrada");
        if (versaoEsperada is not null && versaoEsperada != versao)
            throw new ConflitoConcorrenciaException("Viagem foi alterada por outra pessoa. Recarregue e tente de novo.");
        return versao;
    }

    public static Task TocarViagemAsync(DbSessao s, Guid viagemId, Guid agenciaId, CancellationToken ct) =>
        s.Conexao.ExecuteAsync(new CommandDefinition(
            "update viagem set atualizado_em = now() where id = @viagemId and agencia_id = @agenciaId",
            new { viagemId, agenciaId }, s.Transacao, cancellationToken: ct));

    public static Task TravarCompetenciaAsync(DbSessao s, Guid agenciaId, DateOnly competencia, CancellationToken ct) =>
        s.Conexao.ExecuteAsync(new CommandDefinition(
            "select pg_advisory_xact_lock(hashtext('competencia:' || @agenciaId::text || ':' || @mes))",
            new { agenciaId, mes = competencia.ToString("yyyy-MM") }, s.Transacao, cancellationToken: ct));

    public static async Task CompetenciaAbertaAsync(DbSessao s, Guid agenciaId, DateOnly data, bool podeEditarFechado, string? motivo, CancellationToken ct)
    {
        var competencia = new DateOnly(data.Year, data.Month, 1);
        await TravarCompetenciaAsync(s, agenciaId, competencia, ct);
        var fechado = await s.Conexao.ExecuteScalarAsync<bool>(new CommandDefinition(
            "select exists (select 1 from fechamento_periodo where agencia_id = @agenciaId and competencia = @competencia)",
            new { agenciaId, competencia }, s.Transacao, cancellationToken: ct));
        if (!fechado) return;
        if (!podeEditarFechado) throw new RegraDeNegocioException("periodo_fechado", $"Competência {competencia:yyyy-MM} está fechada");
        if (string.IsNullOrWhiteSpace(motivo)) throw new RegraDeNegocioException("motivo_obrigatorio", "Informe o motivo para alterar um período fechado");
    }
}
```
Se Dapper não mapear `DateOnly` no `@competencia`, usar `competencia.ToDateTime(TimeOnly.MinValue)` — Npgsql 8+ mapeia `DateOnly` → `date` nativamente; confirmar na versão do `Directory.Packages.props`/`.csproj`.

- [ ] **Step 4: Rodar** — `dotnet build -c Release && dotnet test` → 0 falhas. `dotnet format --verify-no-changes` limpo.

- [ ] **Step 5: Reportar arquivos tocados**

Commit sugerido: `feat(comum): Guardas - tenant reference check, viagem row lock with version, competencia lock/closed check`

---

### Task 7 (root): Documentação, tabela de autorização por operação, backlog

**Files:**
- Modify: `docs/BACKLOG.md` (marcar as pendências **(3.0)** como fechadas; tabela de fases)
- Modify: `docs/superpowers/plans/2026-09-08-fase-3-master.md` (linha 3.0: "(escrito)" → "(concluído)")
- Modify: `CLAUDE.md` (linha **Estado**: 3.0 concluído, migrations 0001–0012)
- Modify: `backend/README.md` se existir seção de migrations/jobs (regra: view nova com `security_invoker`; `IJob.PorAgencia`)

**Depends-on:** T1–T6 commitados e `dotnet test` verde.

- [ ] **Step 1: BACKLOG** — mover os itens marcados **(3.0)** de "Deferidas da Fase 2" para uma subseção "Fechadas em 3.0 (2026-09-…)" com uma linha cada; manter os não resolvidos (`CancellationToken.None` em `ExecutarJob`, multiagência por e-mail, `EsqueciSenha` silencioso, `PrevisaoComissao` sem testes de borda).

- [ ] **Step 2: Apêndice de autorização por operação** — copiar a tabela abaixo para `docs/autorizacao-por-operacao.md` (novo) e linkar do mestre em "Contratos transversais". Ela é o contrato que 3.2–3.6 implementam; cada subplano só acrescenta linhas.

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

- [ ] **Step 3: CLAUDE.md e mestre** — uma linha cada, sem reescrever.

- [ ] **Step 4: Reportar** — commit no root: `docs: fase 3.0 hardening done; authorization-by-operation appendix; backlog`

---

## Self-review (feito ao escrever)

- **Cobertura do mestre (linha 3.0):** `OnValidatePrincipal` T3 ✓ · token atômico T3 ✓ · links separados T3 ✓ · lock último dono T4 ✓ · `TratadorDeExcecoes` T2 ✓ · `JobRunner` lock + agência T5 ✓ · `Referencias`/`Viagens.Travar`/`Fechamento.ExigirAberto` → `Guardas.ReferenciaAsync`/`TravarViagemAsync`/`CompetenciaAbertaAsync` T6 ✓ (nomes finais são os de T6; o mestre cita os provisórios) · migration 0012 com todos os itens listados T1 ✓ · tabela de autorização T7 ✓.
- **Desvio consciente:** `vw_fase_viagem` **não** muda. A generated column já zera `valor_esperado_operadora` para cancelada sem `comissao_mantida`; cancelada com `comissao_mantida` continua "a receber" porque a comissão é devida (spec §4.2). T1 fixa isso em teste em vez de alterar a view. Se a spec quiser outro comportamento, é decisão de produto, não bug.
- **Desvio consciente:** `job_execucao` não ganha índice único parcial; o lock advisory de sessão em T5 resolve o mesmo problema com zero schema e cai sozinho em crash.
- **Placeholders:** nenhum "TBD"/"similar à task N"; todo código está inline.
- **Consistência de tipos:** `IJob.ExecutarAsync(Guid?, CancellationToken)` em T5 e nos fakes ✓ · `Guardas.*` assinaturas iguais em Interfaces, testes e implementação ✓ · `MeResposta` em `AuthTests` continua com 4 campos (o 5º, `Permissoes`, entra em 3.1 T06) ✓ · fixture helpers usados em `ViewsTests`/`GuardasTests` com as assinaturas de T1 ✓.
- **Ondas:** T1/T2/T4 disjuntos (Migrations+Fixtures+MigrationsTests+ViewsTests · Infra+InfraTests · Admin+UsuariosTests) ✓ · T3/T5/T6 disjuntos (Auth+AuthTests+ConviteTests · Jobs+JobsTests · Modules/Comum+GuardasTests) ✓.
