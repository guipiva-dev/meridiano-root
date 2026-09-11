# Meridiano — Fase 4 — Piloto (deploy, dados reais, medição): Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Execução em ondas:** segue `.claude/rules/parallel-subagent-driven-development.md` e `.superpowers/sdd/regras-implementador.md` (branch `feat/fase-4` no `backend/`; root só docs; frontend **não muda** nesta fase). Implementadores **não commitam**; o controlador commita uma task por vez, com pathspec. `--artifacts-path` privado em todo `dotnet build/test`. Só T0–T2 são código; T3–T5 são operação executada pelo controlador/humano com `az`, `psql`, dashboards — sem subagente.

**Goal:** colocar a v1 no ar para a agência piloto e fechar as três pendências humanas da Fase 3: API + jobs em Azure Container Apps, Postgres no Supabase (pooler em modo sessão), anexos no R2, e-mail pelo Resend, CI que publica imagem e faz deploy, backup diário com restauração testada, primeira agência criada sem seed de dev, smoke pós-deploy (imagem integrada, migrations em banco vazio, TZ, jobs), três viagens reais lançadas e comparadas com a planilha (§12), tempo humano de lançamento medido (§7).

**Architecture:** nada de módulo novo. Uma migration (`0017_supabase_hardening.sql`) fecha o PostgREST do Supabase para `anon`/`authenticated`/`service_role`; um script SQL (`scripts/bootstrap-agencia.sql`) cria agência + Dono com token de convite (mesmo formato de `ConviteService`) — sem tocar `Program.cs`; `ci.yml` ganha push para GHCR + `az containerapp update` (API e 6 jobs); `backup.yml` faz `pg_dump` diário para o R2. Provisionamento é runbook (`docs/deploy.md`) com comandos `az` idempotentes, não Terraform/Bicep. Jobs = Container Apps Jobs (cron) com a **mesma imagem** e `--args job <nome>`, **sem** `ConnectionStrings:Migrator` (só a API migra).

**Tech Stack:** o de sempre + `az` CLI 2.6x, GHCR, Azure Container Apps (consumo, `min-replicas 0`), Supabase free (Postgres 17, Supavisor sessão :5432), Cloudflare R2 (SDK S3 já em uso), Resend (já em uso), UptimeRobot, GitHub Actions (`docker/build-push-action`, `azure/login`, `aws` CLI do runner para o R2).

**Spec:** `regras-e-escopo-v2.md` §11 (infra, linha a linha), §10 (v1.1: importação da planilha **fora**), §12 (piloto: validar §4.2 e RAV — decisão 49; decisões 1, 18, 30) · `docs/analise-arquitetural-v1.md` A-01 (API é a única porta; fechar PostgREST), A-02 (Supabase só como Postgres), A-08 (jobs), B-01 (banco portátil) · `docs/BACKLOG.md` "Checklist humano" (a) UX §7, (b) piloto §12, e deferida "`alter default privileges` … aplicar no Supabase na Fase 4" · plano-mestre `2026-09-08-fase-3-master.md` "Critério de fechamento" item (4) (smoke da imagem integrada e migração incremental em banco com dados) · `docs/relatorios-formulas.md` (o que comparar com a planilha) · `docs/design-system-contrato.md` §7 (roteiro do teste de UX).

**Estado de partida:** `main` nos dois repos (backend `b949e97`, frontend `f6f0ceb`), migrations 0001–0016, 257 testes API + 30 domínio, 486 Vitest. Dockerfile já com `TZ`/`PGTZ`. `ci.yml` só builda a imagem (`push: false`). Nenhum recurso de nuvem existe.

## Global Constraints

- Backend: `TreatWarningsAsErrors=true`; `dotnet format` limpo. Migration em transação própria (DbUp), idempotente e **no-op fora do Supabase** (roles `anon`/`authenticated`/`service_role` não existem no compose nem no Testcontainers).
- Nenhum segredo em repo, plano, runbook ou memória: valores entram por `gh secret set` e `az containerapp secret set`; nos docs só o **nome** do segredo. Nunca `Include Error Detail=true` na connection string de produção (deferida 3.0).
- Banco: conectar sempre pelo pooler do Supabase em **modo sessão** (`aws-0-<regiao>.pooler.supabase.com:5432`, usuário `<role>.<ref>`); a conexão direta é IPv6-only no free. `Migrator` = role `postgres`; `Api` = role `meridiano_api` (sem ownership, sem BYPASSRLS, criada **antes** do primeiro boot — senão a 0002 não concede nada).
- Custo: tudo dentro da cota gratuita (spec §11). API `--min-replicas 0 --max-replicas 1 --cpu 0.25 --memory 0.5Gi`; jobs `--cpu 0.25 --memory 0.5Gi --replica-retry-limit 0`. UptimeRobot a cada **30 min**, não 5 (ver R6).
- Dados reais só no Supabase da agência e no R2 da agência; nunca copiar dump para o repo, para o scratchpad compartilhado ou para a memória. Dump restaurado localmente é apagado ao fim do drill (`docker compose down -v`).
- Commits Conventional Commits em inglês com rodapé de atribuição da sessão.

---

## Rulings desta fase

| # | Decisão | Motivo |
|---|---|---|
| R1 | **"Importar planilha" = lançar à mão as três viagens reais** na tela de Nova viagem. Nenhum importador; importação da planilha é v1.1 (spec §10). O tempo de cada lançamento é a medição do §7. | Spec §10/§12; o importador esconderia exatamente o que o piloto precisa medir. |
| R2 | **Bootstrap da primeira agência por SQL** (`scripts/bootstrap-agencia.sql`, rodado uma vez como `postgres` via `psql` pelo pooler): cria `agencia` + `usuario` `dono` sem senha, com `convite_token` no formato de `ConviteService.NovoToken()` (32 bytes, base64url, 72 h) e imprime o link `/definir-senha?token=`. Sem e-mail (o link vai por mão), sem endpoint, sem CLI, sem tocar `Program.cs` (congelado). Testado em Testcontainers (T0). | Rung 3 da escada: pgcrypto + fluxo de convite já existem. `seed-dev.sql` tem senha em texto e dados de E2E — nunca em produção. |
| R3 | **PostgREST fechado por migration** (`0017_supabase_hardening.sql`): se existirem os roles `anon`/`authenticated`/`service_role`, `revoke all` em tabelas/sequences/funções de `public`, `revoke usage on schema public`, e `alter default privileges in schema public revoke …` do **role corrente** (o migrator, que no Supabase é `postgres`). Complemento manual no dashboard: tirar `public` de *Exposed schemas*. Verificação real: `curl` no PostgREST com a `anon key` devolve 401/404 (T3). | Analise A-01 item 1; deferida da Fase 2 (`alter default privileges` por ambiente). Versionado > clique no dashboard. |
| R4 | **CI faz deploy:** job `docker` passa a `push: true` para `ghcr.io/guipiva-dev/meridiano-api:{sha,latest}` (só em `main`), depois `azure/login` com service principal (`AZURE_CREDENTIALS`, JSON de `az ad sp create-for-rbac --sdk-auth`) e `az containerapp update` na API + `az containerapp job update` nos 6 jobs, todos para a tag `sha`. Pacote GHCR **privado**; ACA puxa com PAT `read:packages` (segredo `ghcr-pat`). OIDC fica para quando houver mais de um ambiente. | Spec §11 CI/CD. SP secret = 1 comando; OIDC = 4 passos e uma federated credential por branch. |
| R5 | **Jobs no ACA (cron UTC; BRT = UTC−3):** `ping` `0 3 * * *` (00:00) · `recorrencia_despesas` `0 4 * * *` (01:00) · `pendencias_derivadas` `0 5 * * *` (02:00) · `resumo_diario_email` `0 10 * * *` (07:00) · `expurgo_auditoria` `0 6 1 * *` · `expurgo_anexos` `30 6 1 * *`. Mesma imagem, `--args job <nome>`, `--replica-timeout 1800`, `--replica-retry-limit 0` (o `JobRunner` já grava `job_execucao`; retry duplicaria e-mail). Env dos jobs: `ConnectionStrings__Api`, `Email__*`, `Armazenamento__*`, `TZ`/`PGTZ` (já na imagem) — **sem** `ConnectionStrings__Migrator` (`AddMigrations` é no-op sem ela). | Spec §11 Jobs; A-08. `ping` diário impede a pausa de 7 dias do Supabase. |
| R6 | **UptimeRobot a cada 30 min** em `/health` (o check bate no Postgres). A 5 min a réplica nunca escala a zero (cooldown padrão 300 s) e 0,25 vCPU × 30 d ≈ 650 k vCPU‑s > cota de 180 k. A 30 min: ~1/6 do tempo ativo ≈ 110 k vCPU‑s + uso real. Cold start de alguns segundos é aceito (spec §11). Subir para `min-replicas 1` só se a agência reclamar (≈ US$ 10/mês). | Cota gratuita. |
| R7 | **Backup:** `backup.yml` (cron `30 5 * * *` = 02:30 BRT + `workflow_dispatch`) roda `pg_dump -Fc -n public --no-owner --no-privileges` com a imagem `postgres:17` pelo pooler (role `postgres`) e `aws s3 cp` para `s3://meridiano-backup/meridiano-<data>.dump` no R2 (endpoint `https://<account>.r2.cloudflarestorage.com`, região `auto`). **Retenção 30 dias = lifecycle rule do bucket** no painel do R2 (zero código). Drill de restauração (T3): `pg_restore` no compose local, `grant` para `meridiano_api`, subir a imagem nova — isso **é** o teste de "migração incremental em banco com dados": vira pré-requisito de todo deploy que contenha migration nova (checklist no runbook). | Spec §11 Backup ("sem isso o backup não existe"); mestre item (4). |
| R8 | **Domínio:** piloto usa o FQDN padrão do ACA (`https://meridiano-api.<hash>.<regiao>.azurecontainerapps.io`); `Email:BaseUrl` aponta para ele. Domínio custom + certificado gerenciado é passo opcional no runbook. **Resend exige domínio verificado** (DKIM/SPF) para mandar e-mail a terceiros — a agência precisa de um domínio próprio ou da Build Solutions para o remetente (`Email:Remetente = "Meridiano <no-reply@<dominio>>"`). Sem domínio: convites vão por link copiado (R2) e o resumo diário não sai — registrar no BACKLOG. | Cookie `Secure` já é `Always` fora de dev; ingress do ACA manda `X-Forwarded-Proto` e `UseForwardedHeaders` já confia nele. |
| R9 | **Segredos no ACA** por `--secrets` + `secretref:` (não `--env-vars` com valor): `cs-api`, `cs-migrator` (só API), `resend-key`, `r2-access`, `r2-secret`, `ghcr-pat`. Nomes iguais em API e jobs. | `az containerapp show` não expõe valor de secret; env var plana aparece em `show`. |
| R10 | **Validação §12 tem gabarito escrito antes de lançar:** `docs/piloto/validacao-formulas.md` recebe, por viagem, os números da planilha (venda, custo/valor operadora, comissão %, RAV, taxa) **antes** da tela ser preenchida; depois a tela e o Relatório são copiados ao lado. Divergência = defeito ou regra nova (decisão 49), nunca "ajuste na planilha". A Fase 3 fecha só com as três linhas batendo ou com cada divergência explicada e registrada como ruling. | Mestre "Critério de fechamento"; R17 de 3.6. |
| R11 | **Tempo humano §7** medido com cronômetro pelo observador, do clique em "Nova viagem" até o toast de salvo, viagem de 4 reservas (mesmo cenário do E2E: 6,2 s automatizado @1280). Meta ≤ 300 s (mestre). Cada "onde eu clico?" vira linha no `docs/piloto/teste-ux.md`; não corrigir UI durante a sessão. | Contrato §7; spec §12 "Tempo de lançamento". |
| R12 | **Frontend não muda** nesta fase. Defeito de UI achado no piloto vai para `docs/BACKLOG.md` "Achados do piloto" e vira plano 4.1 — salvo bloqueio total do lançamento (aí abre task extra, controlador decide). | Fase é medição; corrigir no meio invalida a medição. |

---

## Valores do ambiente (preencher no runbook antes da T3; nenhum é segredo)

| Nome | Valor proposto | Origem |
|---|---|---|
| `RG` | `rg-meridiano` | resource group Azure |
| `LOC` | `brazilsouth` | região ACA (latência da agência); Log Analytics vem junto |
| `CAE` | `cae-meridiano` | Container Apps environment |
| `APP` | `meridiano-api` | container app |
| `IMG` | `ghcr.io/guipiva-dev/meridiano-api` | pacote GHCR (privado) |
| `SB_REF` | `<ref do projeto Supabase>` | dashboard → Settings → General |
| `SB_POOL` | `aws-0-sa-east-1.pooler.supabase.com` | dashboard → Connect → Session pooler (conferir região) |
| `R2_ACCOUNT` | `<account id Cloudflare>` | R2 → overview |
| `R2_BUCKET_ANEXOS` / `R2_BUCKET_BACKUP` | `meridiano-anexos` / `meridiano-backup` | criados na T3 |
| `EMAIL_DOMINIO` | `<dominio da agência>` | R8 |

Segredos (nome → onde): `cs-api`, `cs-migrator`, `resend-key`, `r2-access`, `r2-secret`, `ghcr-pat` → ACA · `AZURE_CREDENTIALS`, `GHCR_PAT`? não (CI usa `GITHUB_TOKEN` para push), `BACKUP_PGURL`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` → GitHub Actions do repo `meridiano-api`.

---

## Ondas (4)

| Onda | Tasks | Motivo |
|---|---|---|
| 0 | T0 (migration 0017 + bootstrap SQL + teste) · T1 (`ci.yml`: push GHCR + deploy) · T2 (`backup.yml`) | arquivos disjuntos; 3 implementadores backend |
| 1 | T3 (runbook `docs/deploy.md` + provisionar Supabase/R2/Resend/Azure + primeiro deploy + bootstrap) — **controlador/humano, serial** | precisa da imagem publicada (T1), da 0017 e do bootstrap (T0), do backup (T2) |
| 2 | T4 (smoke pós-deploy + drill de restauração + UptimeRobot) — controlador/humano | precisa do ambiente vivo |
| 3 | T5 (piloto §12 + teste de UX §7) — humano com a agência; dias, não horas | precisa do smoke verde |
| 4 | T6 (docs de fechamento, memória) | fechamento |

Propriedade de arquivos (onda 0):

- T0: `backend/src/Meridiano.Data/Migrations/0017_supabase_hardening.sql`, `backend/scripts/bootstrap-agencia.sql`, `backend/tests/Meridiano.Api.Tests/BootstrapTests.cs`.
- T1: `backend/.github/workflows/ci.yml`.
- T2: `backend/.github/workflows/backup.yml`.
- Congelados: todo o resto de `backend/src`, `Program.cs`, `Dockerfile`, `frontend/**`. Precisou tocar → BLOCKED.

---

### Task 0 (backend): migration 0017 (fechar PostgREST) + `scripts/bootstrap-agencia.sql` + teste

**Files:**
- Create: `backend/src/Meridiano.Data/Migrations/0017_supabase_hardening.sql`
- Create: `backend/scripts/bootstrap-agencia.sql`
- Create: `backend/tests/Meridiano.Api.Tests/BootstrapTests.cs`

**Depends-on:** none

**Interfaces:**
- Produces: script rodável por `psql "<cs-migrator>" -v nome_agencia='…' -v nome_dono='…' -v email='…' -v base_url='https://…' -f scripts/bootstrap-agencia.sql` (T3 usa). Migration 0017 aplicada automaticamente no primeiro boot em produção (T3).

- [ ] **Step 1: Testes** (`BootstrapTests.cs`, coleção `"db"`, fixture `PostgresFixture` como os demais):

```csharp
[Collection("db")]
public sealed class BootstrapTests(PostgresFixture pg)
{
    private static string Script(string arquivo) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "scripts", arquivo));
    // Caminho: tests/Meridiano.Api.Tests/bin/<cfg>/net10.0 → ../../../../../scripts. Se `--artifacts-path` mudar o layout,
    // usar `<None Include="..\..\scripts\bootstrap-agencia.sql" CopyToOutputDirectory="PreserveNewest" />` no csproj de testes.

    [Fact]
    public async Task Bootstrap_cria_agencia_e_dono_com_convite_valido()
    {
        // owner: mesma role das migrations (bypassa RLS); o script real roda como postgres no Supabase
        await using var c = new NpgsqlConnection(pg.ConnOwner);
        await c.OpenAsync();
        var email = $"dono-{Guid.NewGuid():N}@piloto.test";
        await c.ExecuteAsync("select set_config('bootstrap.nome_agencia', 'Agência Piloto', false), set_config('bootstrap.nome_dono', 'Dona Piloto', false), set_config('bootstrap.email', @email, false), set_config('bootstrap.base_url', 'https://piloto.test', false)", new { email });
        await c.ExecuteAsync(Script("bootstrap-agencia.sql").Split("-- psql-only", 2)[1]);   // só o bloco DO (ver Step 3)

        var u = await c.QuerySingleAsync<(Guid AgenciaId, string Perfil, string? SenhaHash, string Token, DateTimeOffset Expira)>(
            "select agencia_id, perfil, senha_hash, convite_token, convite_expira_em from usuario where email = @email", new { email });
        Assert.Equal("dono", u.Perfil);
        Assert.Null(u.SenhaHash);
        Assert.Matches("^[A-Za-z0-9_-]{43}$", u.Token);                       // 32 bytes base64url sem '='
        Assert.InRange(u.Expira, DateTimeOffset.UtcNow.AddHours(71), DateTimeOffset.UtcNow.AddHours(73));
        Assert.Equal("Agência Piloto", await c.ExecuteScalarAsync<string>("select nome from agencia where id = @id", new { id = u.AgenciaId }));

        // O token é aceito pelo fluxo real de convite (GET /auth/tokens?token= → tipo "convite")
        await using var app = new MeridianoApiFactory(pg);
        var resp = await app.CreateClient().GetAsync($"/api/v1/auth/tokens?token={u.Token}");
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);
        Assert.Contains("\"convite\"", await resp.Content.ReadAsStringAsync());

        // Idempotente por e-mail: rodar de novo falha sem duplicar
        var ex = await Assert.ThrowsAsync<PostgresException>(() => c.ExecuteAsync(Script("bootstrap-agencia.sql").Split("-- psql-only", 2)[1]));
        Assert.Contains("já existe", ex.MessageText);
        Assert.Equal(1, await c.ExecuteScalarAsync<int>("select count(*) from usuario where email = @email", new { email }));
    }

    [Fact]
    public async Task Migration_0017_revoga_tudo_de_anon_quando_o_role_existe()
    {
        await using var c = new NpgsqlConnection(pg.ConnOwner);
        await c.OpenAsync();
        await c.ExecuteAsync("do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if; end $$");
        await c.ExecuteAsync("grant usage on schema public to anon; grant select on all tables in schema public to anon; alter default privileges in schema public grant select on tables to anon");
        Assert.True(await c.ExecuteScalarAsync<bool>("select has_table_privilege('anon', 'agencia', 'select')"));

        // Reexecuta o SQL embutido da 0017 (DbUp não repete script já aplicado)
        using var s = typeof(Meridiano.Data.Migrator).Assembly.GetManifestResourceStream(
            typeof(Meridiano.Data.Migrator).Assembly.GetManifestResourceNames().Single(n => n.EndsWith("0017_supabase_hardening.sql")))!;
        await c.ExecuteAsync(await new StreamReader(s).ReadToEndAsync());

        Assert.False(await c.ExecuteScalarAsync<bool>("select has_table_privilege('anon', 'agencia', 'select')"));
        Assert.False(await c.ExecuteScalarAsync<bool>("select has_schema_privilege('anon', 'public', 'usage')"));
        await c.ExecuteAsync("create table _t0017 (id int)");
        Assert.False(await c.ExecuteScalarAsync<bool>("select has_table_privilege('anon', '_t0017', 'select')"));   // default privileges revogados
        await c.ExecuteAsync("drop table _t0017; drop owned by anon; drop role anon");
    }
}
```
  `pg.ConnOwner` é a connection string do owner em `Fixtures/PostgresFixture.cs`; `MeridianoApiFactory(pg)` como nos demais testes.

- [ ] **Step 2: Rodar para ver falhar** — `dotnet test --artifacts-path <privado> --filter BootstrapTests` → falha (script inexistente / privilégio ainda concedido).

- [ ] **Step 3: Implementar.**

`backend/scripts/bootstrap-agencia.sql`:
```sql
-- Primeira agência de um ambiente (produção). Roda UMA vez, como a role das migrations (postgres no Supabase):
--   psql "$CS_MIGRATOR" -v nome_agencia='Viva Turismo' -v nome_dono='Ana Silva' -v email='ana@agencia.com' \
--        -v base_url='https://meridiano-api.<hash>.brazilsouth.azurecontainerapps.io' -f scripts/bootstrap-agencia.sql
-- Cria agência + Dono sem senha e imprime o link /definir-senha (72 h), no mesmo formato de ConviteService.
-- Não manda e-mail. Falha (sem duplicar) se o e-mail já existir. Nunca usar seed-dev.sql em produção.
select set_config('bootstrap.nome_agencia', :'nome_agencia', false),
       set_config('bootstrap.nome_dono',    :'nome_dono',    false),
       set_config('bootstrap.email',        :'email',        false),
       set_config('bootstrap.base_url',     :'base_url',     false);
-- psql-only
do $$
declare
  v_email   text := current_setting('bootstrap.email');
  v_agencia uuid;
  v_token   text := translate(rtrim(encode(gen_random_bytes(32), 'base64'), '='), '+/', '-_');
begin
  if exists (select 1 from usuario where lower(email) = lower(v_email)) then
    raise exception 'usuário % já existe', v_email;
  end if;
  insert into agencia (nome) values (current_setting('bootstrap.nome_agencia')) returning id into v_agencia;
  perform set_config('app.agencia_id', v_agencia::text, true);   -- caso a role não bypasse RLS (force row level security)
  insert into usuario (agencia_id, nome, email, perfil, convite_token, convite_expira_em)
  values (v_agencia, current_setting('bootstrap.nome_dono'), v_email, 'dono', v_token, now() + interval '72 hours');
  raise notice 'Agência % criada. Link do Dono (72 h): %/definir-senha?token=%', v_agencia, current_setting('bootstrap.base_url'), v_token;
end $$;
```

`backend/src/Meridiano.Data/Migrations/0017_supabase_hardening.sql`:
```sql
-- Supabase expõe o schema public pelo PostgREST e, por default privileges do role postgres, concede tudo
-- a anon/authenticated/service_role em cada tabela nova. A API é a única porta (análise A-01): revoga
-- tudo, inclusive os defaults do role corrente (o migrator = postgres no Supabase).
-- No-op fora do Supabase: os roles não existem no compose nem no Testcontainers.
-- Complemento manual (docs/deploy.md): remover `public` de Settings → API → Exposed schemas.
do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on all tables in schema public from %I', r);
      execute format('revoke all on all sequences in schema public from %I', r);
      execute format('revoke all on all functions in schema public from %I', r);
      execute format('revoke usage on schema public from %I', r);
      execute format('alter default privileges in schema public revoke all on tables from %I', r);
      execute format('alter default privileges in schema public revoke all on sequences from %I', r);
      execute format('alter default privileges in schema public revoke all on functions from %I', r);
    end if;
  end loop;
end $$;
```
  `Meridiano.Data.csproj` embute `Migrations/*.sql` por glob — nada a registrar.

- [ ] **Step 4: Rodar tudo; format.** `dotnet test` verde (257 + 2 API), `dotnet format --verify-no-changes`. `MigrationsTests` que conta scripts (se existir) passa a esperar 17. Commit sugerido: `feat(db): migration 0017 revokes PostgREST roles on Supabase; one-shot bootstrap script for the first agency`

---

### Task 1 (backend): `ci.yml` publica imagem no GHCR e faz deploy

**Files:**
- Modify: `backend/.github/workflows/ci.yml` (job `docker`)

**Depends-on:** none (o deploy só passa depois da T3 criar os recursos; até lá o step `az` falha — aceitável em `main` por no máximo uma onda; se incomodar, o controlador usa `if: vars.DEPLOY == 'true'` e liga a variável na T3)

**Interfaces:**
- Consumes: segredos do repo `AZURE_CREDENTIALS` (T3 cria). `GITHUB_TOKEN` com `packages: write`.
- Produces: `ghcr.io/guipiva-dev/meridiano-api:<sha>` e `:latest`; API e jobs atualizados para `<sha>` a cada push em `main`.

- [ ] **Step 1: Editar o job `docker`** (o `build-test` fica como está):

```yaml
  docker:
    runs-on: ubuntu-latest
    needs: build-test
    if: github.ref == 'refs/heads/main'
    permissions:
      contents: read
      packages: write
    env:
      IMG: ghcr.io/guipiva-dev/meridiano-api
      RG: rg-meridiano
      APP: meridiano-api
    steps:
      - uses: actions/checkout@v4
        with:
          path: backend
      # meridiano-app é público: GITHUB_TOKEN basta. Se virar privado, usar token: ${{ secrets.FRONTEND_PAT }}
      - uses: actions/checkout@v4
        with:
          repository: guipiva-dev/meridiano-app
          path: frontend
          ref: main
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: backend/Dockerfile
          push: true
          tags: |
            ${{ env.IMG }}:${{ github.sha }}
            ${{ env.IMG }}:latest
      - uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      # API e os 6 jobs (R5) sobem para a mesma tag; nomes = meridiano-job-<nome do IJob>
      - run: |
          az containerapp update -g "$RG" -n "$APP" --image "$IMG:${{ github.sha }}"
          for j in ping recorrencia_despesas pendencias_derivadas resumo_diario_email expurgo_auditoria expurgo_anexos; do
            az containerapp job update -g "$RG" -n "meridiano-job-${j//_/-}" --image "$IMG:${{ github.sha }}"
          done
```
  Nomes de job do ACA não aceitam `_`: `meridiano-job-resumo-diario-email` etc. — T3 cria com os mesmos nomes (`${j//_/-}`).

- [ ] **Step 2: Validar sintaxe** — `act` não é necessário; rodar `python -c "import yaml,sys; yaml.safe_load(open('backend/.github/workflows/ci.yml'))"` (ou `npx yaml-lint`) e conferir no GitHub que o workflow aparece sem erro de parse após o push da branch (workflow em PR roda só `build-test`).

- [ ] **Step 3: Commit** sugerido: `ci: push image to GHCR on main and roll out to Container Apps (api + 6 cron jobs)`

- [ ] **Verificação final (após T3):** run do `ci` em `main` verde; `az containerapp show -g rg-meridiano -n meridiano-api --query properties.template.containers[0].image` = tag do sha; `az containerapp job show -n meridiano-job-ping … --query properties.template.containers[0].image` idem.

---

### Task 2 (backend): `backup.yml` — `pg_dump` diário para o R2

**Files:**
- Create: `backend/.github/workflows/backup.yml`

**Depends-on:** none

**Interfaces:**
- Consumes: segredos do repo `BACKUP_PGURL` (`postgresql://postgres.<ref>:<senha>@<SB_POOL>:5432/postgres?sslmode=require`), `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` (token do R2 com Object Read & Write **só** no bucket `meridiano-backup`). T3 cria.
- Produces: `s3://meridiano-backup/meridiano-YYYY-MM-DD.dump` (formato custom, só schema `public`, sem owner/privilégios — restaurável em qualquer Postgres 17).

- [ ] **Step 1: Criar o workflow:**

```yaml
name: backup
on:
  schedule:
    - cron: "30 5 * * *"   # 02:30 BRT
  workflow_dispatch:
jobs:
  dump:
    runs-on: ubuntu-latest
    steps:
      # pg_dump 17 (>= servidor) pela imagem oficial; pooler em modo sessão aceita pg_dump; -n public deixa de fora
      # os schemas do Supabase (auth, storage, extensions). Nada do dump toca o disco do repo nem vira artifact.
      - run: |
          docker run --rm postgres:17 pg_dump "${{ secrets.BACKUP_PGURL }}" -Fc -n public --no-owner --no-privileges > meridiano.dump
          test "$(stat -c %s meridiano.dump)" -gt 10000
      - run: |
          aws s3 cp meridiano.dump "s3://meridiano-backup/meridiano-$(date -u +%F).dump" \
            --endpoint-url "https://${{ secrets.R2_ACCOUNT_ID }}.r2.cloudflarestorage.com"
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}
          AWS_DEFAULT_REGION: auto
      - if: always()
        run: rm -f meridiano.dump
```
  O `aws` CLI já vem no runner `ubuntu-latest`. Retenção de 30 dias é lifecycle rule do bucket (R7), não código.

- [ ] **Step 2: Validar sintaxe** como na T1.

- [ ] **Step 3: Commit** sugerido: `ci(backup): daily pg_dump of the public schema to R2 (custom format, manual trigger for drills)`

- [ ] **Verificação final (T4):** `workflow_dispatch` verde; objeto listado com `aws s3 ls s3://meridiano-backup/ --endpoint-url …`; drill de restauração descrito na T4.

---

### Task 3 (operação, serial): runbook `docs/deploy.md` + provisionar + primeiro deploy + bootstrap

**Files:**
- Create: `docs/deploy.md` (root) — o runbook abaixo, mantido como documento vivo; a task é **executar** cada bloco e marcar.
- Modify: `backend/README.md` (seção "Produção" com um parágrafo apontando para `../docs/deploy.md`).

**Depends-on:** T0, T1, T2 (imagem publicada em `main` com 0017 e os workflows)

Pré-requisitos humanos (o controlador pede e espera): conta Azure com subscription ativa; conta Supabase; conta Cloudflare (R2 exige cartão, cota grátis); conta Resend; domínio para o remetente (R8) ou decisão explícita de ficar sem e-mail no piloto; `az login` feito na máquina; `psql` 17 instalado (`docker run --rm -it postgres:17 psql …` serve).

- [ ] **Step 1: Supabase.** Criar projeto (região `sa-east-1`, Postgres 17, senha do `postgres` guardada no gerenciador de senhas). Em *Connect → Session pooler* copiar host/porta. Rodar como `postgres` pelo pooler:
```sql
create role meridiano_api login password '<senha forte, gerada>';   -- sem createdb, sem bypassrls, sem ownership (0002 concede o resto)
```
  Dashboard → *Settings → API → Exposed schemas*: remover `public` (deixar só `graphql_public` ou vazio). Anotar `SB_REF`, `SB_POOL`.
  Connection strings (não gravar em disco): `cs-migrator` = `Host=<SB_POOL>;Port=5432;Database=postgres;Username=postgres.<SB_REF>;Password=<senha postgres>;SSL Mode=Require`; `cs-api` = igual com `Username=meridiano_api.<SB_REF>;Password=<senha meridiano_api>`. **Nunca** `Include Error Detail=true`.

- [ ] **Step 2: R2.** Criar buckets `meridiano-anexos` e `meridiano-backup` (região automática). Em `meridiano-backup`: *Settings → Object lifecycle rules* → apagar objetos após 30 dias. Criar dois API tokens (*Manage R2 API Tokens*): `meridiano-api` (Object Read & Write, só `meridiano-anexos`) e `meridiano-backup` (Object Read & Write, só `meridiano-backup`). Endpoint S3: `https://<R2_ACCOUNT>.r2.cloudflarestorage.com`.

- [ ] **Step 3: Resend.** *Domains → Add* `<EMAIL_DOMINIO>`; criar os registros DNS (DKIM TXT, SPF/MX de retorno) no provedor do domínio; esperar "Verified". *API Keys → Create* (`Sending access`, só esse domínio). Remetente: `Meridiano <no-reply@<EMAIL_DOMINIO>>`. Sem domínio → R8: pular, `resend-key` fica vazio, registrar no BACKLOG.

- [ ] **Step 4: GHCR.** Confirmar que o pacote `meridiano-api` existe (primeiro run verde da T1 em `main`, ainda sem o step `az` passar — ok). Em *Settings → Developer settings → Personal access tokens (classic)*: PAT `read:packages` só para o ACA puxar imagem (`ghcr-pat`). Ligar o pacote ao repo (`Package settings → Manage Actions access`) para o `GITHUB_TOKEN` seguir publicando.

- [ ] **Step 5: Azure — base.** (`az` 2.6x; extensão `containerapp` instala sozinha)
```bash
RG=rg-meridiano; LOC=brazilsouth; CAE=cae-meridiano; APP=meridiano-api; IMG=ghcr.io/guipiva-dev/meridiano-api
az group create -n $RG -l $LOC
az containerapp env create -g $RG -n $CAE -l $LOC          # cria o Log Analytics workspace junto (Serilog JSON já vai para o console)
```

- [ ] **Step 6: Azure — API.** (valores de segredo lidos de variáveis de shell preenchidas na hora, nunca colados no histórico: `read -s CS_API` etc.)
```bash
az containerapp create -g $RG -n $APP --environment $CAE \
  --image $IMG:latest --registry-server ghcr.io --registry-username guipiva-dev --registry-password "$GHCR_PAT" \
  --target-port 8080 --ingress external --min-replicas 0 --max-replicas 1 --cpu 0.25 --memory 0.5Gi \
  --secrets cs-api="$CS_API" cs-migrator="$CS_MIGRATOR" resend-key="$RESEND_KEY" r2-access="$R2_ACCESS" r2-secret="$R2_SECRET" \
  --env-vars ASPNETCORE_ENVIRONMENT=Production \
    ConnectionStrings__Api=secretref:cs-api ConnectionStrings__Migrator=secretref:cs-migrator \
    Email__ResendApiKey=secretref:resend-key "Email__Remetente=Meridiano <no-reply@$EMAIL_DOMINIO>" \
    Armazenamento__Endpoint=https://$R2_ACCOUNT.r2.cloudflarestorage.com Armazenamento__Bucket=meridiano-anexos \
    Armazenamento__AccessKey=secretref:r2-access Armazenamento__SecretKey=secretref:r2-secret
FQDN=$(az containerapp show -g $RG -n $APP --query properties.configuration.ingress.fqdn -o tsv)
az containerapp update -g $RG -n $APP --set-env-vars Email__BaseUrl=https://$FQDN
```
  Primeiro boot aplica 0001–0017 no banco vazio (log: `az containerapp logs show -g $RG -n $APP --tail 200` deve mostrar os 17 scripts do DbUp e nenhum erro). `curl https://$FQDN/health` → `Healthy`.

- [ ] **Step 7: Azure — jobs (R5).**
```bash
for spec in "ping|0 3 * * *" "recorrencia_despesas|0 4 * * *" "pendencias_derivadas|0 5 * * *" \
            "resumo_diario_email|0 10 * * *" "expurgo_auditoria|0 6 1 * *" "expurgo_anexos|30 6 1 * *"; do
  j=${spec%%|*}; cron=${spec#*|}
  az containerapp job create -g $RG -n "meridiano-job-${j//_/-}" --environment $CAE \
    --trigger-type Schedule --cron-expression "$cron" --replica-timeout 1800 --replica-retry-limit 0 --parallelism 1 \
    --image $IMG:latest --registry-server ghcr.io --registry-username guipiva-dev --registry-password "$GHCR_PAT" \
    --args job "$j" --cpu 0.25 --memory 0.5Gi \
    --secrets cs-api="$CS_API" resend-key="$RESEND_KEY" r2-access="$R2_ACCESS" r2-secret="$R2_SECRET" \
    --env-vars ASPNETCORE_ENVIRONMENT=Production ConnectionStrings__Api=secretref:cs-api \
      Email__ResendApiKey=secretref:resend-key "Email__Remetente=Meridiano <no-reply@$EMAIL_DOMINIO>" Email__BaseUrl=https://$FQDN \
      Armazenamento__Endpoint=https://$R2_ACCOUNT.r2.cloudflarestorage.com Armazenamento__Bucket=meridiano-anexos \
      Armazenamento__AccessKey=secretref:r2-access Armazenamento__SecretKey=secretref:r2-secret
done
```
  Sem `ConnectionStrings__Migrator` de propósito (R5). `az containerapp job start -g $RG -n meridiano-job-ping` e `az containerapp job execution list …` → `Succeeded`; `select * from job_execucao order by id desc limit 1` (via psql) mostra `ping` com `sucesso = true`.

- [ ] **Step 8: CI → Azure.** Service principal com escopo no resource group:
```bash
az ad sp create-for-rbac -n sp-meridiano-ci --role Contributor --scopes $(az group show -n $RG --query id -o tsv) --sdk-auth \
  | gh secret set AZURE_CREDENTIALS -R guipiva-dev/meridiano-api
gh secret set BACKUP_PGURL -R guipiva-dev/meridiano-api           # postgresql://postgres.<SB_REF>:<senha>@<SB_POOL>:5432/postgres?sslmode=require
gh secret set R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY -R guipiva-dev/meridiano-api   # um por vez, token do bucket de backup
```
  Re-rodar o último workflow `ci` de `main` (`gh run rerun`): step `az` verde; imagem da API e dos jobs = tag do sha.

- [ ] **Step 9: Bootstrap da agência (R2).**
```bash
docker run --rm -it -v "$PWD/backend/scripts:/s:ro" postgres:17 psql "$CS_MIGRATOR_URL" \
  -v nome_agencia='<Nome da agência>' -v nome_dono='<Nome>' -v email='<e-mail do dono>' -v base_url="https://$FQDN" -f /s/bootstrap-agencia.sql
```
  Copiar o link do `NOTICE`, entregar ao Dono por canal seguro; ele define a senha e entra. Em *Equipe*, ele mesmo convida o restante (fluxo de 3.6).

- [ ] **Step 10: Runbook e commit.** Gravar `docs/deploy.md` com exatamente os blocos acima (valores do ambiente preenchidos, segredos só por nome), mais a seção "Antes de todo deploy com migration nova" (drill da T4) e "Domínio custom (opcional)": `az containerapp hostname add/bind` com certificado gerenciado + `Email__BaseUrl` atualizado. Commit root: `docs(deploy): production runbook — supabase, r2, resend, container apps, ci secrets, bootstrap`; commit backend: `docs: point README to the production runbook`.

---

### Task 4 (operação): smoke pós-deploy, drill de restauração, UptimeRobot

**Files:**
- Modify: `docs/deploy.md` (seção "Smoke pós-deploy" com o resultado datado)

**Depends-on:** T3

- [ ] **Step 1: Imagem integrada, local** (mestre item 4): `docker build -f backend/Dockerfile -t meridiano:smoke .` na raiz (`viva-erp/`, os dois repos irmãos); `docker run --rm -p 8080:8080 -e ConnectionStrings__Api=… -e ConnectionStrings__Migrator=… --network host meridiano:smoke` contra o compose local zerado; `curl localhost:8080/health` = `Healthy`; `GET /` devolve o `index.html` do front (build embutido); login com o seed de dev funciona.

- [ ] **Step 2: Produção — trilha mínima** (Dono do bootstrap): login → `GET /api/v1/auth/me` com `permissoes[]` → criar um cliente de teste "Smoke Teste" → anexar um PDF pequeno (R2: objeto aparece no bucket `meridiano-anexos`; download por URL assinada abre) → convidar um colaborador de teste (e-mail chega pelo Resend, link `/definir-senha` com o FQDN certo) → excluir os dados de teste. Fechar viagem/cliente de teste antes do piloto (soft delete basta; auditoria fica).

- [ ] **Step 3: TZ e pooler.** `psql "$CS_API_URL" -c "show timezone"` pelo pooler = `America/Sao_Paulo`? Se o Supavisor não repassar o parâmetro de startup do `PGTZ`, acrescentar `;Timezone=America/Sao_Paulo` em `cs-api`/`cs-migrator` (e registrar no runbook). Conferir no log da API a data do `job_execucao` do `ping` (Step 7 da T3) em BRT.

- [ ] **Step 4: Jobs.** `az containerapp job start` para `pendencias_derivadas` e `resumo_diario_email` (com pelo menos uma pendência de hoje na agência de teste); e-mail de resumo chega para o Dono; `job_execucao` com `sucesso = true` para ambos; `expurgo_*` iniciados à mão terminam em `Succeeded` com 0 linhas.

- [ ] **Step 5: PostgREST fechado (R3).** `curl -i "https://<SB_REF>.supabase.co/rest/v1/agencia?select=*" -H "apikey: <anon key>" -H "Authorization: Bearer <anon key>"` → 401/404/`permission denied` — **nunca** 200 com linhas. Idem com `usuario`. Anotar o status obtido no runbook.

- [ ] **Step 6: Backup + drill de restauração (R7).** `gh workflow run backup -R guipiva-dev/meridiano-api`; `aws s3 ls s3://meridiano-backup/ --endpoint-url …` mostra o objeto. Baixar para uma pasta temporária **fora do repo**; local: `cd backend && docker compose down -v && docker compose up -d` → `docker run --rm -i --network host postgres:17 pg_restore -h localhost -U meridiano -d meridiano --no-owner --no-privileges < meridiano-<data>.dump` → `psql … -c "grant select, insert, update, delete on all tables in schema public to meridiano_api; grant usage, select on all sequences in schema public to meridiano_api; grant execute on all functions in schema public to meridiano_api"` → `dotnet run --project src/Meridiano.Api` (Development) sobe, DbUp diz "already applied" para 0001–0017, login do Dono funciona com a senha de produção, viagem/cliente aparecem. Depois `docker compose down -v` e apagar o dump. Gravar no runbook como pré-requisito de todo deploy com migration nova ("restaurar o dump de ontem, subir a imagem nova, ver a migration aplicar sem erro").

- [ ] **Step 7: UptimeRobot (R6).** Monitor HTTP em `https://$FQDN/health`, intervalo 30 min, alerta por e-mail para o Dono e para a Build Solutions. Verificar em Azure → Container App → *Metrics → Replica count* que a réplica volta a 0 entre pings.

- [ ] **Step 8: Custo.** Após 48 h: *Cost Management* do RG ≈ R$ 0; Supabase *Usage* < 10 % de 500 MB; R2 < 1 GB. Registrar os três números no runbook. Commit root: `docs(deploy): post-deploy smoke, restore drill and uptime monitor — results`.

---

### Task 5 (humano, com a agência): piloto §12 e teste de UX §7

**Files:**
- Create: `docs/piloto/validacao-formulas.md`, `docs/piloto/teste-ux.md`

**Depends-on:** T4

- [ ] **Step 1: Gabarito antes da tela (R10).** Escolher com a agência 3 viagens **já fechadas** da planilha, de tipos diferentes (ideal: 1 nacional comissionada com 1 reserva; 1 internacional com 2+ reservas de operadoras diferentes e RAV; 1 com cancelamento/crédito ou taxa de serviço). Preencher `validacao-formulas.md`:

```markdown
# Piloto §12 — validação das fórmulas (3 viagens reais)

Fonte: planilha da agência, aba/linhas ___ (não copiada para o repo). Fórmulas: docs/relatorios-formulas.md, spec §4.2, decisão 49.

| Viagem | Reserva | Fornecedor | Venda (planilha) | Custo/valor operadora (planilha) | % comissão | RAV (planilha) | Taxa serviço | Receita prevista (planilha) |
|---|---|---|---|---|---|---|---|---|
| V1 … | R1 | CVC | 8.450,00 | 7.605,00 | 10 | 0,00 | 0,00 | 845,00 |

## Depois de lançar (mesmo dia)

| Viagem | `receita_prevista` tela | `valor_esperado_operadora` tela | Relatório (competência, mês) | Bate? | Divergência / ruling |
|---|---|---|---|---|---|

Regra: divergência nunca se resolve "ajustando a planilha". Ou é defeito (→ BACKLOG, plano 4.1) ou é regra de negócio nova (→ ruling numerado aqui e em regras-e-escopo-v2 §4.2).
```

- [ ] **Step 2: Lançamento cronometrado (R1, R11).** Quem lança: pessoa da agência que **não** viu o design (contrato §7). Observador com cronômetro, tela real (1280 ou 1366). Por viagem: início = clique em "Nova viagem", fim = toast de salvo. Preencher `teste-ux.md`:

```markdown
# Teste de UX §7 — tempo humano e "onde eu clico?"

Data · quem lançou (papel, sem nome) · resolução · navegador.

| Viagem | Reservas | Tempo humano | E2E automatizado (referência) | "Onde eu clico?" (momento → o que procurava → onde estava) |
|---|---|---|---|---|
| V1 | 1 | mm:ss | 6,2 s @1280 | … |

Roteiro completo do contrato §7 (uma vez, além das 3 viagens): criar viagem para Carlos Mendes → reserva CVC → informar pagamento → ver quanto deixa → segunda reserva → corrigir a primeira → sair sem salvar. Tempo: mm:ss. Meta ≤ 300 s para 4 reservas.
```
  Não corrigir a UI durante a sessão (R12). Anexar os achados ao BACKLOG em "Achados do piloto".

- [ ] **Step 3: Comparar.** Preencher a segunda tabela de `validacao-formulas.md` com a tela da viagem (tab Financeiro/Resumo) e `GET /relatorios/resumo?ano=` do mesmo mês. As três linhas batem, ou cada divergência tem ruling. Revisar a RAV (decisão 49) com o que apareceu: câmbio/imposto/desconto surgiram? → v1.1 confirmada ou antecipada (ruling).

- [ ] **Step 4: Commit root** `docs(piloto): §12 formula validation and §7 human timing — 3 real trips` (sem dado pessoal de cliente nos docs: nomes de viagem genéricos "V1/V2/V3", valores podem ficar).

---

### Task 6 (docs, root): fechamento da Fase 4 e da Fase 3

**Files:**
- Modify: `docs/BACKLOG.md` (tabela de fases: 3 **concluída** se T5 bateu, 4 concluída; "Checklist humano" (a)(b) com os resultados; nova seção "Achados do piloto" → plano 4.1; deferida "`alter default privileges` … Supabase" fechada; R8 sem domínio se for o caso), `CLAUDE.md` (linha "Estado": Fase 4 ✓, migrations 0001–0017, URL de produção **sem** segredos, tempo humano medido), `docs/superpowers/plans/2026-09-08-fase-3-master.md` ("Critério de fechamento": itens 1–4 fechados com data), `regras-e-escopo-v2.md` (§12: rulings do piloto sobre §4.2/decisão 49 como notas "Ruling piloto"), `backend/README.md` (linha de estado).
- Memória: `meridiano-estado-2026-09-08.md` (Fase 4 feita, FQDN, nomes dos recursos, rotina "antes de migration nova = drill"), `MEMORY.md`.

**Depends-on:** T5

- [ ] **Step 1:** Coletar: hashes de HEAD (`main` backend/frontend/root), contagem de testes (`dotnet test` resumo), tempos humanos da T5, custo de 48 h da T4.
- [ ] **Step 2:** Editar os arquivos acima. Se T5 encontrou divergência sem ruling, a Fase 3 **continua aberta** e o BACKLOG diz exatamente qual linha da tabela não bate.
- [ ] **Step 3:** Commit root `docs: fase 4 done — production on container apps + supabase, backup drill, pilot §12/§7 results; state line, backlog, rulings`. Merge `feat/fase-4` em `main` no backend (controlador, após revisão). Atualizar memória.

---

## Self-review (feito ao escrever)

- **Cobertura de §11:** API ACA `min 0` ✓ (T3.6, R6) · Jobs ACA cron mesma imagem ✓ (T3.7, R5) · Supabase pooler sessão ✓ (constraints, T3.1) · DbUp no startup ✓ (já existia; jobs sem migrator, R5) · R2 ✓ (T3.2) · Resend ✓ (T3.3, R8) · Serilog → Log Analytics ✓ (env cria o workspace; console JSON já existia) · UptimeRobot ✓ (T4.7) · CI/CD GHCR + `az containerapp update` ✓ (T1) · Backup `pg_dump` → R2, retenção 30 d, restauração testada ✓ (T2, T4.6; "trimestral" vira "antes de toda migration nova", mais frequente) · domínio custom = opcional (R8).
- **Cobertura do BACKLOG/mestre:** checklist (a) UX §7 ✓ T5 · (b) piloto §12 ✓ T5 · mestre item (4) smoke da imagem integrada ✓ T4.1 e migração incremental com dados ✓ T4.6 · deferida `alter default privileges` no Supabase ✓ T0/R3 · "importar planilha" da tabela de fases ✓ reinterpretado em R1 (v1.1 por spec).
- **Placeholders:** `<…>` só em valores que existem apenas no ambiente (ref do projeto, account id, domínio, senhas) — listados em "Valores do ambiente"; nenhum "TBD" de código. T0 tem SQL e teste completos; T1/T2 têm YAML completo; T3/T4 têm comandos completos.
- **Consistência:** nomes dos jobs `ping recorrencia_despesas pendencias_derivadas resumo_diario_email expurgo_auditoria expurgo_anexos` = `IJob.Nome` de `Jobs/*.cs`; nomes ACA `meridiano-job-<nome com hífen>` iguais em T1 (`${j//_/-}`) e T3.7; segredos `cs-api cs-migrator resend-key r2-access r2-secret ghcr-pat` iguais em T3.6/T3.7/R9; `bootstrap.*` GUCs iguais no script e no teste; separador `-- psql-only` presente no script e usado pelo teste; formato do token (43 chars base64url) = `ConviteService.NovoToken()` (32 bytes, sem `=`).
- **Riscos assumidos:** (1) Supavisor pode não repassar `PGTZ` — T4.3 tem o fallback (`Timezone=` na connection string); (2) `alter default privileges` sem `for role` afeta o role corrente — no Supabase é `postgres`, que é quem cria as tabelas (correto); em Testcontainers é `meridiano` (teste cobre); (3) o step `az` do CI falha até a T3 existir — aceito por uma onda.
