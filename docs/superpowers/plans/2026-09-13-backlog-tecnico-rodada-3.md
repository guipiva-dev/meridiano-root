# Backlog técnico da rodada 3 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar os 8 deferidos técnicos da rodada 3 (`docs/BACKLOG.md` "Homologação 2026-09-12 (rodada 3)") e 4 pedidos do dono (CPF + nascimento obrigatórios no cliente; documento e nascimento visíveis ao selecionar passageiro; hover dos chips; forma de pagamento "Dinheiro").

**Architecture:** Correções pontuais em módulos existentes; nenhum arquivo novo além de testes e um hook (`useScrollShadow`). Backend: 2 tasks em `Auth/` e `Modules/Repasses/`. Frontend: 6 tasks disjuntas em componentes/páginas já existentes.

**Tech Stack:** C#/.NET 10 Minimal API + Dapper + Postgres (Testcontainers, xUnit); React + Vite + TypeScript (Vitest + Testing Library, CSS modules, biome/eslint, `scripts/check-tokens.mjs`).

**Spec:** `regras-e-escopo-v2.md` (§7.3 auditoria de usuário; §5 repasse; §4.2 receita) e `docs/design-system-contrato.md`.

## Global Constraints

- Seguir `.superpowers/sdd/regras-implementador.md`: implementador **não commita**; `dotnet build/test` sempre com `--artifacts-path E:/workspace/viva-erp/.superpowers/artifacts/<task>`; Bash só em foreground (`run_in_background:false`).
- Branch `fix/backlog-r3` em `backend/` e `frontend/` (criar a partir de `main`: backend `86f0b54`, frontend `fa33f4f`).
- Português nos nomes de domínio; erros `RegraDeNegocioException(codigo, mensagem)` → 422; toda query Dapper filtra `agencia_id` e `excluido_em is null`.
- CSS: só tokens de `frontend/src/styles/tokens.css`; breakpoints permitidos 700/1024/1280/1366/1440; nenhum `font-size` solto (`npm run lint` roda `check-tokens.mjs`).
- Gate final por repo: backend `dotnet build -c Release && dotnet test && dotnet format --verify-no-changes`; frontend `npm run lint && npm run typecheck && npm run test && npm run build`.
- **Fora deste plano (decisão de design/produto):** 3 CTAs "Nova viagem", laranja × azul, validação sequencial do cadastro, Enter no Remarcar, motivo ao corrigir movimento, AC02 (não reproduzido), `Page` sem limpar título (já resolvido em `fa33f4f`: `PageHeader`/`Page` restauram "Meridiano" no unmount).

**Ondas (regra `parallel-subagent-driven-development`):** Onda 1 = B1 ∥ B2 ∥ B3 ∥ B4 ∥ F1 ∥ F2 ∥ F3 ∥ F4 ∥ F5 ∥ F6 ∥ F8 (todos com `Files` disjuntos, `Depends-on: none`); Onda 2 = F7 (depende de B3: `dataNascimento` no DTO de busca). Controlador commita por task com pathspec.

**Decisões do controlador para os pedidos novos:** "Documento" obrigatório = **CPF** (passaporte continua em Documentos); obrigatório em POST e PUT — cliente legado sem CPF/nascimento passa a exigir preenchimento na próxima edição (é o objetivo). Hover dos chips muda no componente `Chip` compartilhado (serviços vendidos, formas de pagamento, filtros) para manter consistência. "Dinheiro" entra na reserva (`formas_pagamento`); movimentos já tinham.

---

## Backend

### Task B1: Auditoria de convite (reenviar/revogar)

**Files:**
- Modify: `backend/src/Meridiano.Api/Auth/ConviteService.cs` (`ReenviarAsync` ~L59, `RevogarAsync` ~L85-96)
- Test: `backend/tests/Meridiano.Api.Tests/EquipeTests.cs`

Depends-on: none

**Interfaces:**
- Consumes: `DbSessao` (`sessoes.AbrirAsync(ctx, ct)`), tabela `auditoria (agencia_id, tabela, registro_id, acao, alteracoes jsonb, motivo, usuario_id)`.
- Produces: uma linha em `auditoria` com `tabela = 'usuario'`, `acao = 'UPDATE'`, `alteracoes = {"convite": {"de": "...", "para": "..."}}` por reenvio/revogação. `fn_auditoria` ignora `convite_token`/`convite_expira_em` de propósito (segredo), por isso o insert é manual.

- [ ] **Step 1: Teste RED**

```csharp
[Fact]
public async Task Reenviar_e_revogar_convite_gravam_auditoria()
{
    var dono = await Login("dono@viva.dev");
    var criado = await dono.PostAsJsonAsync("/api/v1/usuarios", new { nome = "Aud Convite", email = "aud.convite@teste.dev", perfil = "agente" });
    var id = (await criado.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

    (await dono.PostAsync($"/api/v1/usuarios/{id}/convite", null)).EnsureSuccessStatusCode();
    (await dono.DeleteAsync($"/api/v1/usuarios/{id}/convite")).EnsureSuccessStatusCode();

    var linhas = await Db.QueryAsync<string>(
        "select alteracoes->'convite'->>'para' from auditoria where tabela = 'usuario' and registro_id = @id and alteracoes ? 'convite' order by id",
        new { id });
    Assert.Equal(new[] { "enviado", "revogado" }, linhas.ToArray());
}
```
(Usar os helpers de login/`Db` já existentes em `EquipeTests.cs`; se o POST `/usuarios` exigir outros campos, copiar o payload de `Convida_reenvia_e_bloqueia_quem_ja_tem_acesso`.)

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd backend && dotnet test --artifacts-path E:/workspace/viva-erp/.superpowers/artifacts/B1 --filter "FullyQualifiedName~Reenviar_e_revogar_convite_gravam_auditoria"`
Expected: FAIL — `Assert.Equal` com sequência vazia.

- [ ] **Step 3: Helper privado em `ConviteService`**

```csharp
private static Task RegistrarAuditoriaConviteAsync(DbSessao s, ContextoSessao ctx, Guid usuarioId, string de, string para) =>
    s.Conexao.ExecuteAsync(
        """
        insert into auditoria (agencia_id, tabela, registro_id, acao, alteracoes, motivo, usuario_id)
        values (@agencia, 'usuario', @usuarioId, 'UPDATE',
                jsonb_build_object('convite', jsonb_build_object('de', @de, 'para', @para)),
                null, @ator)
        """,
        new { agencia = ctx.AgenciaId, usuarioId, de, para, ator = ctx.UsuarioId }, s.Transacao);
```
Chamar antes de `s.ConfirmarAsync(ct)`: em `ReenviarAsync` → `("pendente"|"sem_acesso" conforme o estado lido, "enviado")` (se o serviço não lê o estado anterior, usar `de = "sem_acesso"`); em `RevogarAsync` → `("pendente", "revogado")`.

- [ ] **Step 4: Rodar e ver passar** — mesmo comando do Step 2. Expected: PASS.

- [ ] **Step 5: Conferir a Auditoria renderiza** — `GET /api/v1/auditoria` já monta título "Colaborador alterado" por `tabela = 'usuario'` (ver `Modules/Auditoria/AuditoriaSql.cs`); nada a mudar. Rodar `--filter "FullyQualifiedName~AuditoriaTests"`.

- [ ] **Step 6: Reportar arquivos tocados** (controlador commita: `git add src/Meridiano.Api/Auth/ConviteService.cs tests/Meridiano.Api.Tests/EquipeTests.cs && git commit -m "fix(auth): audit row on invite resend/revoke"`).

### Task B2: `DefinirValorAsync` recusa repasse cancelado

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Repasses/RepassesService.cs` (`DefinirValorAsync` ~L95-101)
- Test: `backend/tests/Meridiano.Api.Tests/RepassesTests.cs`

Depends-on: none

**Interfaces:**
- Produces: 422 `repasse_cancelado` ("Repasse de viagem cancelada não recebe valor") para `status = 'cancelado'`, ao lado do existente `repasse_pago`.

- [ ] **Step 1: Teste RED**

```csharp
[Fact]
public async Task Definir_valor_em_repasse_cancelado_e_422()
{
    // Reaproveitar o cenário de RepassesTests que cancela a viagem e vê o repasse virar 'cancelado' (B5 da rodada 3).
    var (dono, repasseId) = await CriarViagemComRepasseCanceladoAsync();
    var resp = await dono.PutAsJsonAsync($"/api/v1/repasses/{repasseId}/valor", new { valor = 100m });
    Assert.Equal(HttpStatusCode.UnprocessableEntity, resp.StatusCode);
    var pd = await resp.Content.ReadFromJsonAsync<JsonElement>();
    Assert.Equal("repasse_cancelado", pd.GetProperty("codigo").GetString());
}
```
(`CriarViagemComRepasseCanceladoAsync`: extrair do teste existente que cancela a viagem — não duplicar o setup.)

- [ ] **Step 2: Rodar e ver falhar** — `--filter "FullyQualifiedName~Definir_valor_em_repasse_cancelado_e_422"`. Expected: FAIL (200).

- [ ] **Step 3: Implementar**

```csharp
if (alvo.Status == "pago") throw new RegraDeNegocioException("repasse_pago", "Repasse já pago");
if (alvo.Status == "cancelado") throw new RegraDeNegocioException("repasse_cancelado", "Repasse de viagem cancelada não recebe valor");
```

- [ ] **Step 4: Rodar e ver passar.** Depois `--filter "FullyQualifiedName~RepassesTests"` inteiro.

- [ ] **Step 5: Reportar arquivos** (commit do controlador: `fix(repasses): reject value on cancelled repasse`).

### Task B3: CPF e data de nascimento obrigatórios no cliente; nascimento na busca

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Pessoas/ClientesService.cs` (`ValidarAsync`/`Validado` ~L180-230)
- Modify: `backend/src/Meridiano.Api/Modules/Pessoas/PessoaDtos.cs` (L6 `ClienteBuscaDto`)
- Modify: `backend/src/Meridiano.Api/Modules/Pessoas/PessoasService.cs` (query de `/clientes/busca` — adicionar `data_nascimento`)
- Test: `backend/tests/Meridiano.Api.Tests/ClientesTests.cs`, `backend/tests/Meridiano.Api.Tests/Fixtures/*` (helper que cria cliente — passar CPF válido e nascimento em todos os usos)

Depends-on: none

**Interfaces:**
- Produces: 422 `cpf_obrigatorio` ("Informe o CPF") e `data_nascimento_obrigatoria` ("Informe a data de nascimento") em POST e PUT `/clientes`. Regra do PUT sem permissão de documento (`Editar_sem_permissao_de_documento_preserva_o_cpf`): o CPF **efetivo** é `req.Cpf ?? cpf gravado`; só 422 se ambos vazios. `ClienteBuscaDto` ganha `DateOnly? DataNascimento` (sempre serializado, pode ser null para legados).

- [ ] **Step 1: Testes RED (`ClientesTests.cs`)**

```csharp
[Fact]
public async Task Cliente_exige_cpf_e_data_de_nascimento()
{
    var dono = await Login("dono@viva.dev");
    var semCpf = await dono.PostAsJsonAsync("/api/v1/clientes", new { nome = "Sem CPF", dataNascimento = "1990-01-01" });
    Assert.Equal(HttpStatusCode.UnprocessableEntity, semCpf.StatusCode);
    Assert.Equal("cpf_obrigatorio", (await semCpf.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("codigo").GetString());
    var semNasc = await dono.PostAsJsonAsync("/api/v1/clientes", new { nome = "Sem Nasc", cpf = "11144477735" });
    Assert.Equal("data_nascimento_obrigatoria", (await semNasc.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("codigo").GetString());
}

[Fact]
public async Task Busca_de_clientes_traz_data_de_nascimento()
{
    var dono = await Login("dono@viva.dev");
    await dono.PostAsJsonAsync("/api/v1/clientes", new { nome = "Busca Nasc", cpf = "11144477735", dataNascimento = "1990-01-01" });
    var r = await dono.GetFromJsonAsync<JsonElement>("/api/v1/clientes/busca?q=Busca%20Nasc");
    Assert.Equal("1990-01-01", r.EnumerateArray().First().GetProperty("dataNascimento").GetString());
}
```

- [ ] **Step 2: Rodar e ver falhar** — `--filter "FullyQualifiedName~Cliente_exige_cpf|FullyQualifiedName~Busca_de_clientes_traz"`.

- [ ] **Step 3: Implementar** — em `ValidarAsync` (após normalizar `cpf`): `var cpfEfetivo = cpf ?? cpfGravadoQuandoSemPermissao; if (string.IsNullOrWhiteSpace(cpfEfetivo)) throw new RegraDeNegocioException("cpf_obrigatorio", "Informe o CPF"); if (req.DataNascimento is null) throw new RegraDeNegocioException("data_nascimento_obrigatoria", "Informe a data de nascimento");` (manter as validações existentes de CPF inválido/duplicado e nascimento futuro). `ClienteBuscaDto(Guid Id, string Nome, string? Telefone, string? Cpf, DateOnly? DataNascimento)` (manter o `JsonIgnore` do `Cpf`); adicionar `data_nascimento` ao `select` da busca.

- [ ] **Step 4: Atualizar fixtures** — todo helper/teste que cria cliente sem CPF/nascimento passa a enviar CPF válido único (gerar por índice, ex. `GerarCpf(i)` já existente ou criar em `Fixtures/`) e `dataNascimento = "1980-05-05"`. Rodar `dotnet test` completo (artifacts B3) até verde.

- [ ] **Step 5: Reportar arquivos** (commit: `feat(clientes): cpf and birth date required; busca returns birth date`).

### Task B4: Forma de pagamento "Dinheiro" na reserva

**Files:**
- Create: `backend/src/Meridiano.Data/Migrations/0024_forma_pagamento_dinheiro.sql`
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ReservaGravacao.cs` (L13 `FormasPagamento`)
- Test: `backend/tests/Meridiano.Api.Tests/ViagensCriarTests.cs`

Depends-on: none

**Interfaces:**
- Produces: `formas_pagamento` aceita `'dinheiro'`; DTOs não mudam (array de strings).

- [ ] **Step 1: Teste RED** — em `ViagensCriarTests`, criar viagem com reserva `formasPagamento: ["dinheiro"]` → 201 e GET devolve `["dinheiro"]`.
- [ ] **Step 2: Rodar e ver falhar** — 422 `formas_pagamento_invalido`.
- [ ] **Step 3: Migration**

```sql
-- 0024: "dinheiro" como forma de pagamento da reserva (pedido do piloto, 2026-09-13).
alter table reserva drop constraint reserva_formas_pagamento_check;
alter table reserva add constraint reserva_formas_pagamento_check
  check (formas_pagamento <@ array['pix','boleto','cartao','dinheiro']);
```
(Conferir o nome real com `select conname from pg_constraint where conrelid = 'reserva'::regclass and conname like '%formas%'` num teste ou no compose; se diferir, usar o nome encontrado.) `ReservaGravacao.FormasPagamento = ["pix", "boleto", "cartao", "dinheiro"]`.
- [ ] **Step 4: Rodar e ver passar**; `--filter "FullyQualifiedName~ViagensCriarTests"`.
- [ ] **Step 5: Reportar arquivos** (commit: `feat(reservas): dinheiro as payment method (migration 0024)`).

## Frontend

### Task F1: Venda vazia não entra na receita da viagem nem no repasse sugerido

**Files:**
- Modify: `frontend/src/components/Viagem/TripSummary.tsx` (`somarReservas` L18-45)
- Modify: `frontend/src/pages/viagens/useNovaViagem.ts` (L368-372 `repasseSugerido`)
- Test: `frontend/src/components/Viagem/TripSummary.test.tsx`, `frontend/src/pages/viagens/useNovaViagem.test.ts`

Depends-on: none

**Interfaces:**
- Produces: `somarReservas(reservas)` passa a devolver `{ vendaTotal, custo, receitaPrevista, incompleta: boolean }` — `incompleta = true` quando alguma reserva ativa tem `valorCliente === null`; essa reserva contribui 0 em `vendaTotal` e **é pulada** em `receitaPrevista` (hoje contribui um negativo). `repasseSugerido` fica `null` enquanto `incompleta`.

- [ ] **Step 1: Teste RED (`TripSummary.test.tsx`)**

```tsx
test("reserva sem venda ao cliente não puxa a receita para negativo", () => {
  const r = somarReservas([
    { status: "pendente", valorTotal: 10000, valorComissao: 1000, ravOperadora: 0, valorCliente: null, taxaServico: 0, ravClienteModo: "via_operadora" },
    { status: "pendente", valorTotal: 2000, valorComissao: 200, ravOperadora: 0, valorCliente: 2000, taxaServico: 0, ravClienteModo: "retido_agencia" },
  ] as ReservaValores[]);
  expect(r.receitaPrevista).toBe(200);
  expect(r.incompleta).toBe(true);
});
```
E em `useNovaViagem.test.ts`: vendedor externo com `geraRepasse` + reserva com venda `null` → `repasseSugerido` é `null`; ao preencher venda → número.

- [ ] **Step 2: Rodar e ver falhar** — `npx vitest run src/components/Viagem/TripSummary.test.tsx src/pages/viagens/useNovaViagem.test.ts`.

- [ ] **Step 3: Implementar**

```ts
let incompleta = false;
for (const r of reservas) {
  if (r.status === "cancelada") continue;
  const valorTotal = r.valorTotal ?? 0;
  custo += valorTotal;
  if (r.valorCliente === null || r.valorCliente === undefined) { incompleta = true; continue; }
  vendaTotal += r.valorCliente;
  receitaPrevista += calcularReserva({ valorTotal, valorComissao: r.valorComissao ?? 0, ravOperadora: r.ravOperadora ?? 0, valorCliente: r.valorCliente, taxaServico: r.taxaServico ?? 0, viaOperadora: r.ravClienteModo === "via_operadora" }).receitaPrevista ?? 0;
}
return { vendaTotal: arredondar2(vendaTotal), custo: arredondar2(custo), receitaPrevista: arredondar2(receitaPrevista), incompleta };
```
`useNovaViagem.ts`: `const { receitaPrevista, incompleta } = somarReservas(reservas); const repasseSugerido = !incompleta && vendedorSelecionado?.geraRepasse && repasseValor === null ? arredondar2(...) : null;`. Em `TripSummary`, quando `incompleta`, o item "Resultado da viagem" mostra `MoneyValue value={null}` ("—") com `title="Preencha a venda ao cliente das reservas"`.

- [ ] **Step 4: Rodar e ver passar**, depois `npm run typecheck` (callers de `somarReservas` continuam compatíveis — campo novo é aditivo).

- [ ] **Step 5: Reportar arquivos** (commit: `fix(viagem): empty venda excluded from trip totals and repasse suggestion`).

### Task F2: Regras — todas as versões futuras visíveis

**Files:**
- Modify: `frontend/src/pages/fornecedores/RegrasTab.tsx` (`classificarRegras` L36-47 e o bloco que renderiza `proxima`)
- Test: `frontend/src/pages/fornecedores/RegrasTab.test.tsx`

Depends-on: none

**Interfaces:**
- Produces: `classificarRegras` devolve `{ proximas: VersaoRegraDto[], vigente, anteriores }` (era `proxima` singular).

- [ ] **Step 1: Teste RED** — fornecedor com `regras` = [`vigenteDesde: 2027-02-01`, `2027-01-01`, `2026-01-01 (vigente: true)`]: renderiza dois cabeçalhos "Próxima versão (a partir de 01/01/2027)" e "(a partir de 01/02/2027)", em ordem crescente de data.

- [ ] **Step 2: Rodar e ver falhar** — `npx vitest run src/pages/fornecedores/RegrasTab.test.tsx`.

- [ ] **Step 3: Implementar**

```ts
proximas: fornecedor.regras.filter((r) => classificar(r) === "proxima").sort((a, b) => a.vigenteDesde.localeCompare(b.vigenteDesde)),
```
e no JSX: `{proximas.map((p) => <section key={p.vigenteDesde}>…título "Próxima versão (a partir de {formatarData(p.vigenteDesde)})"…</section>)}` reaproveitando o bloco atual de `proxima`.

- [ ] **Step 4: Rodar e ver passar** (inclusive os testes existentes de "Próxima versão" com uma só).

- [ ] **Step 5: Reportar arquivos** (commit: `fix(fornecedores): list every future rule version`).

### Task F3: Alerta "marque Registrar mesmo assim" some ao marcar

**Files:**
- Modify: `frontend/src/components/Financeiro/useMutacaoFinanceira.ts` (expor `confirmarExcedenteMarcado()` que faz `setPrecisaConfirmarExcedente(false)`)
- Modify: `frontend/src/components/Financeiro/ReceberModal.tsx` (L36-48, L119)
- Test: `frontend/src/components/Financeiro/ReceberModal.test.tsx`, `frontend/src/components/Financeiro/useMutacaoFinanceira.test.ts`

Depends-on: none

- [ ] **Step 1: Teste RED (`ReceberModal.test.tsx`)** — mock 422 `recebimento_acima_esperado` → aparece "Marque 'Registrar mesmo assim' para confirmar"; `await user.click(checkbox)` → `queryByText(/Marque 'Registrar mesmo assim'/)` é `null`.

- [ ] **Step 2: Rodar e ver falhar** — `npx vitest run src/components/Financeiro/ReceberModal.test.tsx`.

- [ ] **Step 3: Implementar** — no hook: `function confirmarExcedenteMarcado() { setPrecisaConfirmarExcedente(false); }` devolvido junto com `precisaConfirmarExcedente`; no modal, no `onChange` do checkbox de `AvisoExcedente`: `if (marcado) m.confirmarExcedenteMarcado();`.

- [ ] **Step 4: Rodar e ver passar** — os dois arquivos de teste.

- [ ] **Step 5: Reportar arquivos** (commit: `fix(financeiro): clear excess hint once the checkbox is ticked`).

### Task F4: `useFormularioCadastro` expõe erro de carga (remove `useQuery` duplicado)

**Files:**
- Modify: `frontend/src/components/Cadastros/useFormularioCadastro.ts` (retorno L92-101: adicionar `erroCarga: dtoQ.error`)
- Modify: `frontend/src/pages/clientes/usePessoa.ts` (remover `clienteQ` L124-128; `erroCarga: v.erroCarga` do form)
- Test: `frontend/src/pages/clientes/PessoaPage.test.tsx` (já cobre "Pessoa não encontrada ou excluída."), `frontend/src/components/Cadastros/useFormularioCadastro.test.ts` (se existir; senão criar com um caso: `obter` rejeita com `ValidationError nao_encontrado` → `erroCarga` é essa instância)

Depends-on: none

- [ ] **Step 1: Teste RED** — no `useFormularioCadastro.test.ts`, `renderHook` com `obter: () => Promise.reject(new ValidationError(...))`; `await waitFor(() => expect(result.current.erroCarga).toBeInstanceOf(ValidationError))`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar** — adicionar `erroCarga: dtoQ.error` ao objeto retornado; em `usePessoa.ts` apagar o `clienteQ` e usar `erroCarga: v.erroCarga`. Apagar o comentário estale de L45 (`Sem 'cliente.ver_documento' o DTO nem traz 'cpf'`), substituindo por "CPF: campo visível por permissão (`cliente.ver_documento`), não pela presença da chave".
- [ ] **Step 4: Rodar e ver passar** — `npx vitest run src/pages/clientes src/components/Cadastros`.
- [ ] **Step 5: Reportar arquivos** (commit: `refactor(clientes): load error from useFormularioCadastro`).

### Task F5: Sombra de rolagem do DataTable cobrindo o cabeçalho

**Files:**
- Create: `frontend/src/components/DataTable/useScrollShadow.ts`
- Modify: `frontend/src/components/DataTable/DataTable.tsx` (aplicar classes no `.wrap`), `frontend/src/components/DataTable/DataTable.module.css` (trocar o truque de `background-attachment` por `::after` controlado por classe)
- Test: `frontend/src/components/DataTable/useScrollShadow.test.ts`, `frontend/src/components/DataTable/DataTable.test.tsx`

Depends-on: none

**Interfaces:**
- Produces: `useScrollShadow(ref: RefObject<HTMLElement>): { direita: boolean }` — `direita` = `el.scrollWidth - el.clientWidth - el.scrollLeft > 1`; atualiza em `scroll` e `ResizeObserver` (com fallback quando `ResizeObserver` não existe no jsdom).

- [ ] **Step 1: Teste RED (`useScrollShadow.test.ts`)** — elemento fake com `scrollWidth 1000, clientWidth 500, scrollLeft 0` → `direita === true`; após `scrollLeft = 500` + evento `scroll` → `false`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar**

```ts
export function useScrollShadow(ref: RefObject<HTMLElement | null>) {
  const [direita, setDireita] = useState(false);
  useEffect(() => {
    const el = ref.current; if (!el) return;
    const medir = () => setDireita(el.scrollWidth - el.clientWidth - el.scrollLeft > 1);
    medir();
    el.addEventListener("scroll", medir, { passive: true });
    const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(medir) : null;
    ro?.observe(el);
    return () => { el.removeEventListener("scroll", medir); ro?.disconnect(); };
  }, [ref]);
  return { direita };
}
```
CSS: remover as camadas `background-image`/`background-attachment` de `.wrap`; adicionar `.wrap { position: relative; } .wrap.comSombra::after { content: ""; position: absolute; inset: 0 0 0 auto; width: 1.5rem; pointer-events: none; background: linear-gradient(to left, var(--table-scroll-shadow), transparent); }`. Em `DataTable.tsx`: `const wrapRef = useRef<HTMLDivElement>(null); const { direita } = useScrollShadow(wrapRef);` e `className={cx(s.wrap, direita && s.comSombra)}`.
- [ ] **Step 4: Rodar e ver passar** — `npx vitest run src/components/DataTable` + `npm run lint` (`check-tokens`).
- [ ] **Step 5: Reportar arquivos** (commit: `fix(datatable): scroll shadow overlays header too`).

### Task F6: `enviarArquivo` trata URL inválida

**Files:**
- Modify: `frontend/src/api/anexos.ts` (L41-43)
- Test: `frontend/src/api/anexos.test.ts`

Depends-on: none

- [ ] **Step 1: Teste RED** — `await expect(enviarArquivo("nao-e-url", file)).rejects.toThrow("URL de upload inválida")`.
- [ ] **Step 2: Rodar e ver falhar** — hoje lança `TypeError: Invalid URL`.
- [ ] **Step 3: Implementar**

```ts
let host: string;
try { host = new URL(urlUpload).host; } catch { throw new Error("URL de upload inválida — fale com o suporte."); }
```
- [ ] **Step 4: Rodar e ver passar** — `npx vitest run src/api/anexos.test.ts`.
- [ ] **Step 5: Reportar arquivos** (commit: `fix(anexos): invalid signed URL surfaces a readable error`).

### Task F7: Cliente — CPF e nascimento obrigatórios; passageiro selecionado mostra documento e nascimento

**Files:**
- Modify: `frontend/src/pages/clientes/DadosPessoaForm.tsx` (+ `DadosPessoaForm.test.tsx`)
- Modify: `frontend/src/components/Viagem/PessoaInlineModal.tsx` (+ test) — adicionar campo "Nascimento" (`<Input type="date">`), CPF e nascimento obrigatórios
- Modify: `frontend/src/components/Viagem/PassageirosField.tsx` (+ test) — chip do passageiro selecionado mostra linha secundária `111.444.777-35 · nasc. 05/05/1980`
- Modify: `frontend/src/api/clientes.ts` (`ClienteBuscaDto.dataNascimento?: string`)
- Modify: `frontend/src/components/Cadastros/mapaErrosCadastro.ts` (`cpf_obrigatorio` → `cpf`, `data_nascimento_obrigatoria` → `dataNascimento`)

Depends-on: B3 (campo `dataNascimento` na busca)

- [ ] **Step 1: Testes RED** — `DadosPessoaForm`: salvar sem CPF → erro inline "Informe o CPF" e sem chamada à API; sem nascimento → "Informe a data de nascimento"; labels com asterisco (`required`). `PessoaInlineModal`: campo "Nascimento" existe e é obrigatório. `PassageirosField`: opção selecionada com `cpf: "11144477735", dataNascimento: "1980-05-05"` renderiza "111.444.777-35" e "05/05/1980" no chip.
- [ ] **Step 2: Rodar e ver falhar** — `npx vitest run src/pages/clientes/DadosPessoaForm.test.tsx src/components/Viagem`.
- [ ] **Step 3: Implementar** — `Field label="CPF" required`, `Field label="Nascimento" required`; validação local antes do submit (`erros.cpf`/`erros.dataNascimento`) reutilizando o padrão de `erros.nome`; chip: abaixo do nome, `<span className={s.chipMeta}>{formatarCpf(c.cpf)} · nasc. {formatarData(c.dataNascimento)}</span>` (só os presentes; usar o helper de data já existente em `@/lib`). CSS `chipMeta` com `font: var(--type-helper); color: var(--color-text-secondary)`. Quando o usuário **não** tem `cliente.ver_documento`, `cpf` vem ausente → mostrar só nascimento.
- [ ] **Step 4: Rodar e ver passar** + `npm run lint` + `npm run typecheck`.
- [ ] **Step 5: Reportar arquivos** (commit: `feat(clientes,viagem): cpf/birth required, passenger chip shows document and birth date`).

### Task F8: Hover dos chips e forma "Dinheiro"

**Files:**
- Modify: `frontend/src/components/Chip/Chip.module.css` (L14-16 `.chip:hover`)
- Modify: `frontend/src/api/viagens.ts` (L88-95 `FORMAS_PAGAMENTO`/`ROTULO_FORMA`)
- Modify: `frontend/src/dominio/status.ts` (L149 mapa de forma: adicionar `dinheiro: { texto: "Dinheiro", tone: "neutral" }`)
- Test: `frontend/src/components/Reserva/FinancialFields.test.tsx` (chip "Dinheiro" existe e alterna), `frontend/src/components/Chip/Chip.test.tsx` (só garante que o CSS module exporta `.chip`/`.on`)

Depends-on: none

- [ ] **Step 1: Teste RED** — `FinancialFields`: `getByRole("button", { name: "Dinheiro" })` existe; clicar → `onChange` com `formasPagamento: ["dinheiro"]`.
- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar** — `FORMAS_PAGAMENTO = ["pix", "boleto", "cartao", "dinheiro"] as const`, `ROTULO_FORMA.dinheiro = "Dinheiro"`; CSS:

```css
.chip:hover {
  background: var(--color-info-soft);
  border-color: var(--color-action);
  color: var(--color-action);
}
.on:hover {
  background: var(--color-action-hover);
  border-color: var(--color-action-hover);
  color: var(--chip-on-text);
}
```
(tokens existentes em `tokens.css`; conferir que `--color-info-soft`/`--color-action`/`--color-action-hover` existem — sim, usados por `--table-row-hover` e botões).
- [ ] **Step 4: Rodar e ver passar** + `npm run lint` (`check-tokens`).
- [ ] **Step 5: Reportar arquivos** (commit: `feat(ui): chip hover contrast; dinheiro payment chip`).

---

## Fechamento

- Gate completo nos dois repos (Global Constraints), merge `fix/backlog-r3` → `main` (`--no-ff`), push.
- `regras-e-escopo-v2.md` §4.1 (`formas_pagamento[]` — pix, boleto, cartão, **dinheiro**), §3 cliente (CPF e nascimento obrigatórios), `schema-agencia-v2.sql` (check de `formas_pagamento`), `docs/deploy.md`/`CLAUDE.md` migrations → 0024.
- `docs/BACKLOG.md`: remover os 8 itens da lista "Backlog (deferidos com motivo)" da rodada 3; manter os de design/produto.
- `CLAUDE.md` estado: contagem de testes nova + refs de commit.

## Self-review

- Cobertura: 4 pedidos do dono → B3+F7 (obrigatórios + exibição), F8 (hover + dinheiro), B4 (dinheiro na API). 8 deferidos técnicos → B1 (auditoria convite), B2 (repasse cancelado), F1 (transitório negativo), F2 (versões futuras), F3 (alerta persiste), F4 (`useQuery` duplicado), F5 (sombra no `th`), F6 (`new URL`). "Page não limpa título" já resolvido — registrado em Global Constraints.
- Placeholders: nenhum "TBD"; setups de teste reaproveitam helpers existentes nomeados.
- Tipos: `somarReservas` ganha `incompleta` (F1) e é consumido só em `useNovaViagem.ts`/`TripSummary.tsx`; `classificarRegras` muda `proxima` → `proximas` só dentro de `RegrasTab.tsx`; `useScrollShadow` novo, só em `DataTable.tsx`.
