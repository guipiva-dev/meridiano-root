# Meridiano — Runbook de produção (Fase 4)

Fonte: `docs/superpowers/plans/2026-09-11-fase-4-piloto.md` (rulings R2–R9). Spec §11. Estado: **escrito em 2026-09-11, ainda não executado** — marcar cada bloco ao executar e registrar data/resultado na seção "Smoke pós-deploy".

Regras que valem para tudo aqui:
- Nenhum segredo neste arquivo, no repo, no histórico do shell (`read -s VAR`) nem na memória do agente. Só o **nome** do segredo.
- Banco sempre pelo **pooler do Supabase em modo sessão** (`:5432`, usuário `<role>.<ref>`). Conexão direta é IPv6-only no free.
- Nunca `Include Error Detail=true` na connection string de produção.
- Tudo na cota gratuita: API `min-replicas 0`, UptimeRobot a cada 30 min (a 5 min a réplica nunca desce e estoura 180 k vCPU-s).

## Valores do ambiente (não são segredos)

| Nome | Valor | Origem |
|---|---|---|
| `RG` | `rg-meridiano` | resource group Azure |
| `LOC` | `brazilsouth` | região ACA |
| `CAE` | `cae-meridiano` | Container Apps environment |
| `APP` | `meridiano-api` | container app |
| `IMG` | `ghcr.io/guipiva-dev/meridiano-api` | pacote GHCR (privado) |
| `SB_REF` | `<ref do projeto Supabase>` | Settings → General |
| `SB_POOL` | `aws-0-sa-east-1.pooler.supabase.com` | Connect → Session pooler (conferir região) |
| `R2_ACCOUNT` | `<account id Cloudflare>` | R2 → overview |
| buckets R2 | `meridiano-anexos` · `meridiano-backup` | criados abaixo |
| `EMAIL_DOMINIO` | `<domínio>` | Resend exige domínio verificado |
| `FQDN` | `meridiano-api.<hash>.brazilsouth.azurecontainerapps.io` | sai do `az containerapp show` |

Segredos por destino:
- **ACA** (`--secrets`, referenciados por `secretref:`): `cs-api`, `cs-migrator` (só a API), `resend-key`, `r2-access`, `r2-secret`; registry: PAT `ghcr-pat`.
- **GitHub Actions** (repo `guipiva-dev/meridiano-api`): `AZURE_CREDENTIALS`, `BACKUP_PGURL`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`. O push para o GHCR usa `GITHUB_TOKEN`.

Nomes dos jobs no ACA (o `ci.yml` atualiza exatamente estes): `meridiano-job-ping`, `meridiano-job-recorrencia-despesas`, `meridiano-job-pendencias-derivadas`, `meridiano-job-resumo-diario-email`, `meridiano-job-expurgo-auditoria`, `meridiano-job-expurgo-anexos`.

Pré-requisitos humanos: conta Azure com subscription; conta Supabase; conta Cloudflare (R2 pede cartão, fica na cota grátis); conta Resend; domínio para o remetente (ou decisão explícita "piloto sem e-mail"); `az login` e `gh auth login` na máquina; `docker` (o `psql`/`pg_dump` rodam pela imagem `postgres:17`).

## 1. Supabase

- [ ] Criar projeto (região `sa-east-1`, Postgres 17). Senha do `postgres` no gerenciador de senhas.
- [ ] *Connect → Session pooler*: anotar `SB_POOL` e `SB_REF`.
- [ ] Como `postgres`, pelo pooler, **antes do primeiro boot da API** (senão a migration 0002 não concede nada à role):

```bash
docker run --rm -it postgres:17 psql "postgresql://postgres.$SB_REF@$SB_POOL:5432/postgres?sslmode=require"
```
```sql
create role meridiano_api login password '<senha forte gerada>';   -- sem createdb, sem bypassrls, sem ownership
```

- [ ] *Settings → API → Exposed schemas*: remover `public` (a migration 0017 revoga os grants de `anon`/`authenticated`/`service_role`; isto é o cinto-e-suspensório).
- [ ] Connection strings (só em variáveis de shell, `read -s`):
  - `cs-migrator` = `Host=$SB_POOL;Port=5432;Database=postgres;Username=postgres.$SB_REF;Password=<senha postgres>;SSL Mode=Require`
  - `cs-api` = igual com `Username=meridiano_api.$SB_REF;Password=<senha meridiano_api>`
  - `BACKUP_PGURL` = `postgresql://postgres.$SB_REF:<senha postgres>@$SB_POOL:5432/postgres?sslmode=require`

## 2. Cloudflare R2

- [ ] Buckets `meridiano-anexos` e `meridiano-backup` (localização automática).
- [ ] `meridiano-backup` → *Settings → Object lifecycle rules*: apagar objetos após **30 dias** (retenção do spec §11 é esta regra, não código).
- O dump inclui `data_protection_key` (chaves que assinam o cookie de sessão, XML sem cifra — migration 0018): quem lê o backup forja sessões. Token do bucket só no GitHub Actions; nunca compartilhar dump.
- [ ] *Manage R2 API Tokens*: token `meridiano-api` (Object Read & Write, só `meridiano-anexos`) → `r2-access`/`r2-secret`; token `meridiano-backup` (Object Read & Write, só `meridiano-backup`) → `R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY`.
- [ ] Endpoint S3: `https://$R2_ACCOUNT.r2.cloudflarestorage.com` (região `auto`, já é o default do `ArmazenamentoS3`).

## 3. Resend

- [ ] *Domains → Add* `$EMAIL_DOMINIO`; criar DKIM (TXT) e retorno (MX/TXT) no DNS; esperar **Verified**.
- [ ] *API Keys → Create* (`Sending access`, só este domínio) → `resend-key`.
- [ ] Remetente: `Meridiano <no-reply@$EMAIL_DOMINIO>`.
- Sem domínio (R8): pular; `resend-key` vazio; convites vão por link copiado da Equipe; resumo diário não sai. Registrar no BACKLOG.

## 4. GHCR

- [ ] Primeiro run do `ci` em `main` (após merge de `feat/fase-4`) publica `$IMG:<sha>` e `:latest`. O step `az` desse run **falha** até o item 8 — esperado.
- [ ] PAT clássico `read:packages` só para o ACA puxar imagem → `ghcr-pat`.
- [ ] *Package settings → Manage Actions access*: ligar o pacote ao repo `meridiano-api` (o `GITHUB_TOKEN` segue publicando).

## 5. Azure — base

```bash
RG=rg-meridiano; LOC=brazilsouth; CAE=cae-meridiano; APP=meridiano-api; IMG=ghcr.io/guipiva-dev/meridiano-api
az extension add --name containerapp --upgrade -y
az group create -n $RG -l $LOC
az containerapp env create -g $RG -n $CAE -l $LOC     # cria o Log Analytics junto; Serilog já escreve JSON compacto no console
```

## 6. Azure — API

Segredos lidos na hora: `read -s CS_API`, `read -s CS_MIGRATOR`, `read -s RESEND_KEY`, `read -s R2_ACCESS`, `read -s R2_SECRET`, `read -s GHCR_PAT`; `R2_ACCOUNT` e `EMAIL_DOMINIO` em variáveis normais.

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

- [ ] Primeiro boot aplica 0001–0017 no banco vazio: `az containerapp logs show -g $RG -n $APP --tail 200` mostra 17 `Executing Database Server script` e `Upgrade successful`. A linha `Cannot load library libgssapi_krb5.so.2` no boot é ruído do Npgsql (sonda GSS; auth é por senha) — ignorar.
- [ ] `curl https://$FQDN/health` → `Healthy`; `curl -sI https://$FQDN/ | head -1` → 200 (front embutido).

## 7. Azure — jobs (cron em UTC; BRT = UTC−3)

**Todos os jobs precisam das vars `Armazenamento__*`** mesmo sem usar S3: o `JobRunner` instancia todos os `IJob` e `ExpurgoAnexosJob` exige o cliente S3 (sem `Endpoint` o processo morre no boot, exit 139 — visto no smoke local). Sem `ConnectionStrings__Migrator` de propósito: só a API migra.

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

- [ ] `az containerapp job start -g $RG -n meridiano-job-ping`; `az containerapp job execution list -g $RG -n meridiano-job-ping -o table` → `Succeeded`; no banco `select nome, sucesso from job_execucao order by id desc limit 1` → `ping | t`.

Horários: ping 00:00 BRT (impede a pausa de 7 dias do Supabase) · recorrência 01:00 · pendências derivadas 02:00 · resumo diário 07:00 · expurgos dia 1 às 03:00/03:30.

## 8. CI → Azure (deploy automático)

```bash
az ad sp create-for-rbac -n sp-meridiano-ci --role Contributor --scopes $(az group show -n $RG --query id -o tsv) --sdk-auth \
  | gh secret set AZURE_CREDENTIALS -R guipiva-dev/meridiano-api
gh secret set BACKUP_PGURL -R guipiva-dev/meridiano-api          # cola a URL do item 1
gh secret set R2_ACCOUNT_ID -R guipiva-dev/meridiano-api
gh secret set R2_ACCESS_KEY_ID -R guipiva-dev/meridiano-api      # token do bucket de backup
gh secret set R2_SECRET_ACCESS_KEY -R guipiva-dev/meridiano-api
```

- [ ] `gh run rerun <id do último ci em main> -R guipiva-dev/meridiano-api`: step `az` verde; `az containerapp show -g $RG -n $APP --query properties.template.containers[0].image` = `$IMG:<sha>`; idem `az containerapp job show -g $RG -n meridiano-job-ping`.

A partir daqui **todo push em `main` do backend faz deploy** (API + 6 jobs). Antes de um push que contenha migration nova: seção 10.

## 9. Bootstrap da primeira agência

Roda **uma vez**, como `postgres` (precisa BYPASSRLS — `agencia` tem `force row level security`), pelo pooler em **modo sessão** (o script usa GUCs de sessão). Não manda e-mail; o link sai no `NOTICE`.

```bash
docker run --rm -it -v "$PWD/backend/scripts:/s:ro" postgres:17 psql \
  "postgresql://postgres.$SB_REF@$SB_POOL:5432/postgres?sslmode=require" \
  -v nome_agencia='<Nome da agência>' -v nome_dono='<Nome do dono>' -v email='<e-mail do dono>' -v base_url="https://$FQDN" \
  -f /s/bootstrap-agencia.sql
```

- [ ] Copiar o link `…/definir-senha?token=…` (72 h) e entregar ao Dono por canal seguro. Ele define a senha, entra e convida o resto pela tela Equipe.
- Reexecutar com o mesmo e-mail falha com `usuário … já existe` (sem duplicar). Nunca usar `scripts/seed-dev.sql` em produção.

## 10. Antes de todo deploy com migration nova — drill de restauração

Provado localmente em 2026-09-11. Serve de teste de "migração incremental em banco com dados" **e** de teste do backup.

```bash
# 1. dump de ontem (ou dispare um agora: gh workflow run backup -R guipiva-dev/meridiano-api)
aws s3 cp s3://meridiano-backup/meridiano-<data>.dump /tmp/m.dump --endpoint-url https://$R2_ACCOUNT.r2.cloudflarestorage.com
# 2. compose local zerado + extensões (o dump com -n public NÃO traz `create extension`; sem pg_trgm os índices GIN falham)
cd backend && docker compose down -v && docker compose up -d && sleep 8
docker compose exec -T postgres psql -U meridiano -d meridiano -c "create extension if not exists pgcrypto; create extension if not exists pg_trgm;"
# 3. restore (o único erro aceitável é `schema "public" already exists`)
docker run --rm -i -e PGPASSWORD=meridiano postgres:17 pg_restore -h host.docker.internal -U meridiano -d meridiano --no-owner --no-privileges < /tmp/m.dump
# 4. grants perdidos com --no-privileges
docker compose exec -T postgres psql -U meridiano -d meridiano -c "grant select, insert, update, delete on all tables in schema public to meridiano_api; grant usage, select on all sequences in schema public to meridiano_api; grant execute on all functions in schema public to meridiano_api;"
# 5. subir a imagem NOVA contra esse banco: DbUp deve aplicar só a migration nova, sem erro; login do Dono funciona
docker build -f backend/Dockerfile -t meridiano:smoke .    # na raiz viva-erp/ (os dois repos irmãos)
docker run --rm -p 8080:8080 -e ASPNETCORE_ENVIRONMENT=Production \
  -e "ConnectionStrings__Migrator=Host=host.docker.internal;Port=5432;Database=meridiano;Username=meridiano;Password=meridiano" \
  -e "ConnectionStrings__Api=Host=host.docker.internal;Port=5432;Database=meridiano;Username=meridiano_api;Password=meridiano_api" \
  -e Armazenamento__Endpoint=http://host.docker.internal:9000 -e Armazenamento__Bucket=meridiano-dev -e Armazenamento__AccessKey=meridiano -e Armazenamento__SecretKey=meridiano123 \
  -e Email__BaseUrl=http://localhost:8080 meridiano:smoke
# 6. apagar o dump e o banco local: rm /tmp/m.dump; docker compose down -v
```

Dado real nunca fica na máquina depois do drill.

## 11. Domínio custom (opcional, depois do piloto)

```bash
az containerapp hostname add -g $RG -n $APP --hostname app.$EMAIL_DOMINIO
az containerapp hostname bind -g $RG -n $APP --hostname app.$EMAIL_DOMINIO --environment $CAE --validation-method CNAME
az containerapp update -g $RG -n $APP --set-env-vars Email__BaseUrl=https://app.$EMAIL_DOMINIO
for j in ping recorrencia-despesas pendencias-derivadas resumo-diario-email expurgo-auditoria expurgo-anexos; do
  az containerapp job update -g $RG -n meridiano-job-$j --set-env-vars Email__BaseUrl=https://app.$EMAIL_DOMINIO; done
```

## 12. Smoke pós-deploy (T4 do plano) — registrar data e resultado

Feito **localmente** em 2026-09-11 (imagem `meridiano:smoke` contra o compose): 17 migrations em banco vazio ✓ · `/health` ✓ · front ✓ · carimbos `-03:00` ✓ · bootstrap + `definir-senha` + login ✓ · jobs `ping`/`pendencias_derivadas`/`resumo_diario_email` exit 0 com `sucesso = true` ✓ · drill dump→restore→"No new scripts need to be executed" ✓.

Em produção (pendente):
- [ ] Trilha do Dono: login → cliente "Smoke Teste" → anexo PDF (objeto em `meridiano-anexos`, download por URL assinada) → convite de colaborador de teste (e-mail chega, link com o FQDN) → excluir os dados de teste.
- [ ] TZ pelo pooler: `psql "<cs-api como URL>" -c "show timezone"` = `America/Sao_Paulo`. Se o Supavisor não repassar `PGTZ`, acrescentar `;Timezone=America/Sao_Paulo` em `cs-api` e `cs-migrator` (e anotar aqui).
- [ ] Jobs: `job start` de `pendencias_derivadas` e `resumo_diario_email` (com uma pendência de hoje) → e-mail chega; `expurgo_*` terminam `Succeeded` com 0 linhas.
- [ ] PostgREST fechado: `curl -i "https://$SB_REF.supabase.co/rest/v1/agencia?select=*" -H "apikey: <anon key>" -H "Authorization: Bearer <anon key>"` → 401/404/`permission denied`, **nunca** 200 com linhas. Idem `usuario`. Conferir que o SQL Editor do dashboard continua funcionando (roda como `postgres`).
- [ ] Backup real: `gh workflow run backup`; `aws s3 ls s3://meridiano-backup/ --endpoint-url …` lista o objeto; drill da seção 10 com ele.
- [ ] UptimeRobot: monitor HTTP em `https://$FQDN/health`, **30 min**, alerta para o Dono e para a Build Solutions. *Metrics → Replica count* volta a 0 entre pings.
- [ ] Custo após 48 h: Cost Management do RG ≈ 0; Supabase Usage < 10 % de 500 MB; R2 < 1 GB. Anotar os três números aqui.
