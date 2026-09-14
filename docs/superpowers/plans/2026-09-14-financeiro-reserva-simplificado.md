# Financeiro da reserva simplificado — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Waves follow `.claude/rules/parallel-subagent-driven-development.md`: implementers do **not** commit; the controller commits per task.

**Goal:** Make the reservation and trip money screens readable: one calculated RAV, commission in % and R$ side by side, seller commission as % of the total commission, visible service fee, one vocabulary across tabs, and the reservation result shown as an equation.

**Architecture:** The money formulas in the database (`reserva` generated columns) stay as they are. The UI stops exposing `rav_operadora`, `rav_cliente_modo` and `fluxo_pagamento`; new reservations always send `rav_operadora = 0`, `rav_cliente_modo = via_operadora` and `fluxo_pagamento = cliente_paga_operadora`. Legacy values survive the round-trip untouched. The only schema change is `repasse.percentual` (migration 0026); `Rotinas.ReavaliarRepasseAsync` recalculates `repasse.valor` from it whenever the trip changes.

**Tech Stack:** .NET 10 Minimal API + Dapper + DbUp, PostgreSQL 17, xUnit + Testcontainers; React + Vite + TypeScript, Vitest, Playwright.

**Spec:** owner rulings of 2026-09-14, recorded below. The controller updates `regras-e-escopo-v2.md` and `schema-agencia-v2.sql` in Task 5. Context: `docs/benchmark/paxpro-2026-09-13.md`.

## Owner rulings (2026-09-14) — source of truth for this plan

1. The agency does not control supplier payments: every trip entered is already paid to the supplier. The **Fluxo** field leaves the screen.
2. The reservation commission has **% and R$ fields side by side**, each editable and recalculating the other. The trip shows the **average commission %** = Σ commission ÷ Σ reservation total (active reservations).
3. **Seller commission** (repasse, one per trip) has **% and R$** fields. The base is the trip's **total commission** = Σ (commission + RAV) of active reservations (cancelled with `comissao_mantida` counts). The service fee is not in the base. The **% is stored** and the value follows the base while the repasse is not paid or cancelled. Typing R$ by hand clears the %.
4. **One RAV, calculated:** total charged to the client defaults to the reservation total; `RAV = total charged to the client − reservation total`; `total commission = commission + RAV`. "RAV da operadora" and "RAV via operadora / retido" leave the screen (always via operadora).
5. **Service fee** goes to the main area with a visible explanation. `Agency revenue = total commission + service fee`.

## Global Constraints

- Portuguese in UI labels, domain names, endpoints and error messages; Conventional Commits in English with the session attribution footer.
- Money `numeric(12,2)`, BRL; JS money math in integer cents (`dominio/calculoReserva.ts` pattern). Rounding: half away from zero (`arredondar2`).
- Every tenant query runs inside `DbSessao` and filters `agencia_id` and `excluido_em is null`.
- Errors: `RegraDeNegocioException(codigo, mensagem)` → 422 with `codigo`.
- `Program.cs` is never edited.
- No EF, MediatR, AutoMapper, Repository pattern.
- Canonical commands: backend `cd backend && dotnet build -c Release`, `cd backend && dotnet format --verify-no-changes`, `cd backend && dotnet test` (Docker running). Frontend `cd frontend && npm run lint`, `npm run build`, `npx vitest run <path>`.
- UI labels, exact strings (used by tests):
  - Reservation form: `Total da reserva`, `Total cobrado do cliente`, `Comissão (%)`, `Comissão (R$)`, `RAV`, `Total da comissão`, `Taxa de serviço`.
  - Trip strip: `Total cobrado`, `Custo das reservas`, `Receita da agência`, `Comissão do vendedor`, `Despesas da viagem`, `Resultado da viagem`, `Receita recebida`.
  - Seller commission: `Comissão do vendedor (%)`, `Comissão do vendedor (R$)`.

## Repos and branches

`backend/` and `frontend/` are separate git repos. Before Wave 1 the controller creates the branch `feat/financeiro-simplificado` from `main` in **both** repos.

## Waves

| Wave | Tasks | Why together |
|---|---|---|
| 1 | Task 1 (backend), Task 2 (front domain) | Disjoint files, no dependency |
| 2 | Task 3 (reservation form), Task 4 (trip level) | Both consume Task 2; Task 4 consumes the Task 1 contract; disjoint files |
| 3 | Task 5 (docs, controller) | Needs final behaviour |

---

### Task 1: Seller commission percentage persisted and recalculated (backend)

**Agent:** `backend-specialist`. Reviewer: `code-reviewer`.
**Depends-on:** none.
**Files:**
- Create: `backend/src/Meridiano.Data/Migrations/0026_repasse_percentual.sql`
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagemDtos.cs` (`ViagemRequest`, `RepasseDto`)
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagensService.cs` (create ~26-56, `ValidarCabecalho` ~163, update ~87-95)
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagensEdicao.cs` (`TrocarVendedorAsync` 29-49, `AjustarRepasseValorAsync` 53-72)
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/Rotinas.cs` (`ReavaliarRepasseAsync` 10-28)
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagemLeitura.cs` (~54-55, `RepasseDto` read)
- Modify: `backend/src/Meridiano.Api/Modules/Repasses/RepassesService.cs` (`DefinirValorAsync` 90-114)
- Test: `backend/tests/Meridiano.Api.Tests/RepassePercentualTests.cs` (new, collection `"db"`)

**Interfaces:**
- Produces, HTTP JSON (camelCase):
  - `ViagemRequest.repassePercentual: number | null`. It is an optional last positional parameter `decimal? RepassePercentual = null`, so existing test call sites still compile.
  - `RepasseDto.percentual: number | null`, a new positional member after `Status`.
  - New 422 code `percentual_invalido` when the value is outside 0–100.

- [ ] **Step 1: Write the migration**

`0026_repasse_percentual.sql`:
```sql
-- Comissão do vendedor em % da comissão total da viagem (ruling 2026-09-14).
-- Nulo = valor digitado à mão (comportamento anterior). Com %, o valor é recalculado por Rotinas.ReavaliarRepasseAsync.
alter table repasse add column percentual numeric(5,2)
  constraint repasse_percentual_faixa check (percentual >= 0 and percentual <= 100);
```
The migration is an embedded resource: follow how `0025_*.sql` is included (csproj glob), and change nothing else.

- [ ] **Step 2: Write the failing integration tests**

Create `RepassePercentualTests.cs`. Copy the structure from `ViagensEditarTests.Put_com_repasse_pago_aceita_mesmo_valor_e_recusa_valor_diferente` (line ~419) and from `ViagensCriarTests.Cria_viagem_completa_numa_transacao_com_repasse_e_pendencias` (line ~76). Use the same fixture, login-as-owner helper, `Pedido(...)` builder and seller with `gera_repasse = true`.

Scenarios. Values are exact; reservations use `valorTotal 10000, valorComissao 1000, ravOperadora 0, valorCliente 10500, taxaServico 150, ravClienteModo "via_operadora"`, so commission + RAV = 1500 and the service fee is excluded.
1. `Criar_com_percentual_calcula_valor_sobre_comissao_mais_rav`: POST the trip with `repassePercentual = 10`, `repasseValor = null`. Then GET the trip: `repasse.valor == 150.00m`, `repasse.percentual == 10m`.
2. `Editar_reserva_recalcula_valor_do_repasse_com_percentual`: after scenario 1, PUT the trip with the reservation's `valorComissao = 2000` and the same `repassePercentual = 10`. Expect `repasse.valor == 250.00m`.
3. `Reserva_cancelada_sai_da_base`: a trip with two such reservations and 10 %, so the value is 300. Cancel one reservation without `comissao_mantida` (same endpoint/payload as `ViagensOperacoesTests`). Expect `repasse.valor == 150.00m`.
4. `Valor_digitado_limpa_percentual`: after scenario 1, PUT the trip with `repasseValor = 99`, `repassePercentual = null`. Expect `valor == 99m`, `percentual == null`. Then PUT the reservation commission change: value stays `99m`.
5. `Put_valor_do_repasse_limpa_percentual`: after scenario 1, call `PUT /repasses/{id}/valor` with `valor 80` (as in `RepassesTests.Define_valor_com_versao_renova_viagem_e_recusa_pago`). Expect `valor 80`, `percentual null`.
6. `Percentual_fora_de_0_a_100_e_422`: POST with `repassePercentual = 101` gives 422 with `codigo == "percentual_invalido"`; `-1` gives the same.
7. `Repasse_pago_nao_recalcula`: after scenario 1, pay the repasse through the batch endpoint (as in `RepassesTests.Paga_lote_tudo_ou_nada_com_data_e_competencia`), then raise the commission. Expect `valor` still `150m`. A PUT with `repassePercentual = 20` gives 422 `repasse_pago`; with the same `10` it returns 200.
8. `Base_negativa_vira_zero`: a reservation with `valorCliente 9000` (RAV −1000), `valorComissao 1000`, `ravClienteModo "retido_agencia"` (keeps esperado ≥ 0) and 10 %. Base = 0, so `valor == 0m`.

- [ ] **Step 3: Run the tests and verify they fail**

Run: `cd backend && dotnet test --filter FullyQualifiedName~RepassePercentualTests`
Expected: compilation error (`RepassePercentual` / `Percentual` missing) or FAIL.

- [ ] **Step 4: DTOs**

In `ViagemDtos.cs`, append `decimal? RepassePercentual = null` as the **last** parameter of `ViagemRequest` (after `Versao`). Change `RepasseDto` to `RepasseDto(Guid Id, decimal? Valor, string Status, decimal? Percentual)`. Fix the single construction site in `ViagemLeitura.cs` (~54): select `rp.percentual` and pass it.

- [ ] **Step 5: Validation**

In `ViagensService.ValidarCabecalho`, next to the `RepasseValor is < 0` check:
```csharp
if (req.RepassePercentual is < 0 or > 100)
    throw new RegraDeNegocioException("percentual_invalido", "Percentual deve ficar entre 0 e 100");
```

- [ ] **Step 6: Create, change seller, adjust**

- `ViagensService` create path. Where `repasseValor` is gated by `ViagemVerResultado`, gate `repassePercentual` the same way. A non-null percentual on a seller without `gera_repasse` gives `repasse_sem_vendedor` (same check as the value). The insert becomes `insert into repasse (..., valor, percentual) values (..., @valor, @percentual)`, with `valor = percentual is null ? repasseValor : null`. `ReavaliarRepasseAsync`, already called after the reservations are inserted, fills the value.
- `TrocarVendedorAsync(..., decimal? repasseValor, decimal? repassePercentual, ...)`: same rule for the insert; `repasse_sem_vendedor` when either is non-null and the seller does not generate repasse.
- `AjustarRepasseValorAsync(..., decimal? valor, decimal? percentual, ...)`:
  - Select `status, valor, percentual`.
  - No repasse and (valor or percentual non-null): `repasse_sem_vendedor`.
  - Pago: `if (percentual != atual.Percentual && percentual is not null || percentual is null && valor is not null && valor != atual.Valor) throw repasse_pago;` otherwise return.
  - Else: `update repasse set percentual = @percentual, valor = case when @percentual is null then @valor else valor end where ...`.
- Update `ViagensService` (~87-95) to pass `req.RepassePercentual` into both calls.

- [ ] **Step 7: Recalculate in `ReavaliarRepasseAsync`**

Add `Percentual` to the first select (`rp.percentual`). After the `pago` early return, and only when `!atual.Cancelada && atual.Percentual is not null`, run:
```csharp
await s.Conexao.ExecuteAsync(new CommandDefinition(
    """
    update repasse rp set valor = round(greatest(0, coalesce((
        select sum(r.valor_comissao + r.rav_operadora + r.rav_cliente)
          from reserva r
         where r.viagem_id = @viagemId and r.agencia_id = @agenciaId and r.excluido_em is null
           and (r.status <> 'cancelada' or r.comissao_mantida)), 0)) * rp.percentual / 100, 2)
     where rp.id = @id
    """, new { viagemId, agenciaId, id = atual.Id }, s.Transacao, cancellationToken: ct));
```
Place it **before** `if (novo == atual.Status) return;`, so the value updates even when the status does not change.

- [ ] **Step 8: Manual value clears the percentage**

In `RepassesService.DefinirValorAsync`, change the update to `set valor = @valor, percentual = null`.

- [ ] **Step 9: Run the tests**

Run: `cd backend && dotnet test --filter "FullyQualifiedName~RepassePercentualTests|FullyQualifiedName~RepassesTests|FullyQualifiedName~ViagensEditarTests|FullyQualifiedName~ViagensCriarTests|FullyQualifiedName~AuditoriaTests"`
Expected: PASS. Then run the full `cd backend && dotnet test`, `dotnet build -c Release` and `dotnet format --verify-no-changes`: all green.

- [ ] **Step 10: Report** the touched files to the controller (no commit). Controller commit: `feat(repasses): seller commission as stored percentage of trip total commission`.

---

### Task 2: Total commission in the calculation and single-RAV defaults (front domain)

**Agent:** `frontend-specialist`. Reviewer: `code-reviewer`.
**Depends-on:** none.
**Files:**
- Modify: `frontend/src/dominio/calculoReserva.ts`
- Test: `frontend/src/dominio/calculoReserva.test.ts`
- Modify: `frontend/src/components/Reserva/tipos.ts` (`reservaVazia` 49-77)
- Test: `frontend/src/components/Reserva/tipos.test.ts`
- Modify: `frontend/src/pages/viagens/validarReserva.ts` (10-20)
- Test: `frontend/src/pages/viagens/useNovaViagem.validacaoReserva.test.ts` (~80)

**Interfaces:**
- Produces: `ResultadoReserva.totalComissao: number | null`.
  - Value: `valorComissao + ravOperadora + ravCliente`.
  - `0` when cancelled without `comissaoMantida`.
  - `null` when `valorCliente === null` and not zeroed.
- Produces: `reservaVazia()` returns `ravOperadora: 0`, `ravClienteModo: "via_operadora"`, `fluxoPagamento: "cliente_paga_operadora"`.

- [ ] **Step 1: Failing tests**

Append to `calculoReserva.test.ts`:
```ts
test("totalComissao = comissão + RAV da operadora + RAV do cliente", () => {
  const r = calcularReserva({ valorTotal: 10000, valorComissao: 1000, ravOperadora: 0, valorCliente: 10500, taxaServico: 150, viaOperadora: true });
  expect(r.totalComissao).toBe(1500);
  expect(r.receitaPrevista).toBe(1650);
});
test("totalComissao com desconto (RAV negativo)", () => {
  const r = calcularReserva({ valorTotal: 10000, valorComissao: 1000, ravOperadora: 0, valorCliente: 9800, taxaServico: 0, viaOperadora: true });
  expect(r.totalComissao).toBe(800);
});
test("totalComissao null sem venda; 0 se cancelada sem comissão mantida", () => {
  const base = { valorTotal: 10000, valorComissao: 1000, ravOperadora: 0, taxaServico: 0, viaOperadora: true };
  expect(calcularReserva({ ...base, valorCliente: null }).totalComissao).toBeNull();
  expect(calcularReserva({ ...base, valorCliente: null, cancelada: true }).totalComissao).toBe(0);
});
```
In `tipos.test.ts`, change the default-values expectation (lines ~15-16) to `ravOperadora: 0`, `ravClienteModo: "via_operadora"`, `fluxoPagamento: "cliente_paga_operadora"`.

In `useNovaViagem.validacaoReserva.test.ts` (~80), change the expected message to `"Desconto maior que a comissão: o total da comissão ficaria negativo"`.

- [ ] **Step 2: Run and verify the tests fail**

Run: `cd frontend && npx vitest run src/dominio/calculoReserva.test.ts src/components/Reserva/tipos.test.ts src/pages/viagens/useNovaViagem.validacaoReserva.test.ts`
Expected: FAIL (`totalComissao` undefined, defaults and message differ).

- [ ] **Step 3: Implement**

`calculoReserva.ts`:
- Add `totalComissao: number | null;` to `ResultadoReserva` with the doc comment `/** comissão + RAV (ruling 2026-09-14). Receita = totalComissao + taxa de serviço. */`.
- In `calcularReserva`, add `const totalCom = zera ? 0 : com + rav + ravCliente;`.
- Return `totalComissao: cliValido ? totalCom / 100 : null`.

`tipos.ts` `reservaVazia`: `ravOperadora: 0`, `ravClienteModo: "via_operadora"` (fluxo already `cliente_paga_operadora`). Leave `deDto`/`paraRequest` untouched so legacy values round-trip.

`validarReserva.ts`: keep the condition and replace only the message string with `"Desconto maior que a comissão: o total da comissão ficaria negativo"`.

- [ ] **Step 4: Run the tests**

Run the Step 2 command; expected PASS. Then run `cd frontend && npx vitest run` (full): fix only the tests that asserted the old defaults (`duplicarReserva.test.ts`, `ReservationCard.test.tsx`, fixtures), changing expectations and not behaviour. Then `npm run lint`.

- [ ] **Step 5: Report** files (no commit). Controller commit: `feat(reserva): total commission in calculation and single-RAV defaults`.

---

### Task 3: Reservation form and result as an equation

**Agent:** `frontend-specialist`. Reviewer: `code-reviewer`.
**Depends-on:** Task 2.
**Files:**
- Modify: `frontend/src/components/Reserva/FinancialFields.tsx`
- Test: `frontend/src/components/Reserva/FinancialFields.test.tsx`
- Modify: `frontend/src/components/Reserva/ResultSummary.tsx`
- Create: `frontend/src/components/Reserva/ResultSummary.test.tsx`
- Modify: `frontend/src/components/Reserva/Reserva.module.css` (equation styles only)
- Modify: `frontend/src/components/Reserva/ReservaDetalheCard.tsx` (remove Fluxo, 42-45 and 155)
- Test: `frontend/src/components/Reserva/ReservaDetalheCard.test.tsx`, `ReservationCard.test.tsx` (label updates only)
- Modify: `frontend/e2e/nova-viagem.spec.ts:35` (label)

**Interfaces:**
- Consumes: `calcularReserva(...).totalComissao` and `.ravCliente` (Task 2).
- Consumes: `comissaoPorPercentual(p, total)`, `percentualDaComissao(valor, total)`, `parsearPercentual(texto)` from `@/lib/comissao`.
- Produces: none used by other tasks.

- [ ] **Step 1: Failing tests for the form**

In `FinancialFields.test.tsx`:
- Delete the test that toggles R$/% chips (L1 block, ~127-201) and the Fluxo tooltip expectation (~113).
- Add the following, using the file's existing `renderizar`/harness helper; if the helper name differs, reuse the one the current tests use:
```ts
test("comissão em % e R$ lado a lado: digitar % calcula R$", async () => {
  // valorTotal 10000
  await user.type(screen.getByLabelText("Comissão (%)"), "10");
  expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ valorComissao: 1000 }));
});
test("digitar R$ mostra o % derivado", () => {
  // value: valorTotal 10000, valorComissao 1250
  expect(screen.getByLabelText("Comissão (%)")).toHaveValue("12,5");
});
test("com % como âncora, mudar o total recalcula a comissão", async () => {
  // digita 10 no %, depois muda Total da reserva para 20000
  expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ valorTotal: 20000, valorComissao: 2000 }));
});
test("RAV e Total da comissão são calculados e não editáveis", () => {
  // valorTotal 10000, valorCliente 10500, valorComissao 1000
  expect(screen.getByLabelText("RAV")).toHaveAttribute("readonly");
  expect(screen.getByLabelText("RAV")).toHaveValue("R$ 500,00");
  expect(screen.getByLabelText("Total da comissão")).toHaveValue("R$ 1.500,00");
});
test("sem Fluxo, sem RAV da operadora, sem modo do RAV", () => {
  expect(screen.queryByLabelText(/Fluxo/)).toBeNull();
  expect(screen.queryByLabelText(/RAV da operadora/)).toBeNull();
  expect(screen.queryByLabelText(/RAV do cliente vem/)).toBeNull();
});
test("Taxa de serviço visível fora de '+ mais campos', com explicação", () => {
  const campo = screen.getByLabelText("Taxa de serviço");
  expect(campo.closest("details")).toBeNull();
  expect(screen.getByText("Cobrada do cliente por fora da reserva; soma direto na receita da agência.")).toBeVisible();
});
```
Match the `toHaveValue` money format to how the existing `MoneyInput` tests read values in this file; if `MoneyInput` renders raw digits, assert that format instead.

- [ ] **Step 2: Failing test for the equation**

`ResultSummary.test.tsx`:
```tsx
import { render, screen, within } from "@testing-library/react";
import { ResultSummary } from "./ResultSummary";
import { reservaVazia } from "./tipos";

test("mostra a conta: cobrado − reserva = RAV; + comissão = total; + taxa = receita", () => {
  render(<ResultSummary value={{ ...reservaVazia(0), valorTotal: 10000, valorCliente: 10500, valorComissao: 1000, taxaServico: 150 }} />);
  const linha = (rotulo: string) => screen.getByText(rotulo).closest("div")!;
  expect(within(linha("Total cobrado do cliente")).getByText("R$ 10.500,00")).toBeInTheDocument();
  expect(within(linha("Total da reserva")).getByText("R$ 10.000,00")).toBeInTheDocument();
  expect(within(linha("RAV")).getByText("R$ 500,00")).toBeInTheDocument();
  expect(within(linha("Comissão (10 %)")).getByText("R$ 1.000,00")).toBeInTheDocument();
  expect(within(linha("Total da comissão")).getByText("R$ 1.500,00")).toBeInTheDocument();
  expect(within(linha("Taxa de serviço")).getByText("R$ 150,00")).toBeInTheDocument();
  expect(within(linha("Receita da agência")).getByText("R$ 1.650,00")).toBeInTheDocument();
  expect(screen.queryByText("RAV da operadora")).toBeNull();
});
test("RAV da operadora legado aparece só quando > 0", () => {
  render(<ResultSummary value={{ ...reservaVazia(0), valorTotal: 10000, valorCliente: 10000, valorComissao: 1000, ravOperadora: 100 }} />);
  expect(screen.getByText("RAV da operadora")).toBeInTheDocument();
});
```
Check `reservaVazia`'s real signature in `tipos.ts` (`reservaVazia(taxaServicoPadrao)`) and pass what it needs.

- [ ] **Step 3: Run and verify the tests fail**

Run: `cd frontend && npx vitest run src/components/Reserva`
Expected: FAIL.

- [ ] **Step 4: Implement `FinancialFields.tsx`**

- Remove `OPCOES_RAV_CLIENTE`, `OPCOES_FLUXO`, the "RAV da operadora" field, the "RAV do cliente vem" select, the "Fluxo" select and the R$/% chip group. Drop unused imports (`FluxoPagamento`, `RavClienteModo`, `Select`, `Chip` if unused).
- Commission state, replacing `comissaoEmPct`:
```tsx
// % digitado vira âncora: mudar o total recalcula o R$. Digitar R$ solta a âncora e o % passa a ser derivado.
const [pctTexto, setPctTexto] = useState<string | null>(null);
const [erroPct, setErroPct] = useState<string | null>(null);
const pctDerivado = percentualDaComissao(value.valorComissao, value.valorTotal);
const pctMostrado = pctTexto ?? (pctDerivado === null ? "" : String(pctDerivado).replace(".", ","));

function mudarPct(texto: string) {
  const p = parsearPercentual(texto);
  if (p === "invalido") { setErroPct("Percentual inválido"); return; }
  if (p === "negativo" || (p !== null && p > 100)) { setErroPct("Percentual deve ficar entre 0 e 100"); return; }
  setErroPct(null);
  setPctTexto(texto);
  onChange({ valorComissao: p === null ? null : comissaoPorPercentual(p, value.valorTotal), comissaoSugerida: false });
}
function mudarValorComissao(v: number | null) {
  setPctTexto(null);
  setErroPct(null);
  onChange({ valorComissao: v, comissaoSugerida: false });
}
function mudarTotal(v: number | null) {
  const p = pctTexto === null ? null : parsearPercentual(pctTexto);
  onChange(typeof p === "number" ? { valorTotal: v, valorComissao: comissaoPorPercentual(p, v), comissaoSugerida: false } : { valorTotal: v });
}
const r = calcularReserva(paraValoresReserva(value));
```
(import `calcularReserva` from `@/dominio/calculoReserva` and `paraValoresReserva` from `./tipos`).

- Main grid order and labels (all `span-2` unless noted):
  1. `Total da reserva`: existing MoneyInput + onBlur logic, `onChange={mudarTotal}`. Tooltip unchanged.
  2. `Total cobrado do cliente`: the former "Venda ao cliente" field, same props. Tooltip: `"Quanto o cliente pagou no total. Começa igual ao total da reserva; mude se cobrou a mais (RAV) ou deu desconto."`
  3. `Comissão (%)`: `<Input inputMode="decimal" value={pctMostrado} readOnly={readOnly} onChange={(e) => mudarPct(e.target.value)} />`. Error `erroPct`. Helper `helperComissao` (existing). Tooltip: `"O que o fornecedor paga à agência (ex.: 10% de R$ 10.000 = R$ 1.000)."`
  4. `Comissão (R$)`: `<MoneyInput value={value.valorComissao} readOnly={readOnly} onChange={mudarValorComissao} />`. Error `erros.valorComissao`.
  5. `RAV`: `<MoneyInput value={r.ravCliente} readOnly calculated onChange={() => {}} tabIndex={-1} />`. Tooltip: `"Calculado: total cobrado do cliente − total da reserva (ex.: R$ 10.500 − R$ 10.000 = R$ 500). Negativo = desconto."` If `MoneyInput` does not forward `tabIndex`, forward it in the component only when that is a one-line change; otherwise omit `tabIndex`.
  6. `Total da comissão`: `<MoneyInput value={r.totalComissao} readOnly calculated onChange={() => {}} tabIndex={-1} />`. Tooltip `"Comissão + RAV."`
  7. `Taxa de serviço`: moved out of `<details>`. `helper="Cobrada do cliente por fora da reserva; soma direto na receita da agência."`. Tooltip unchanged (keeps the `ex.:` example).
  8. `Formas de pagamento`: unchanged.
- `<details>` keeps `Do total, quanto é taxa` (moved in) and `Observações`. Summary text: `+ mais campos (taxas do fornecedor, observações)`.
- Tooltip test at ~113: expect tooltips with `ex.:` on `Comissão (%)`, `RAV` and `Taxa de serviço` (3).

- [ ] **Step 5: Implement `ResultSummary.tsx` as an equation**

```tsx
import { MoneyValue } from "@/components";
import { calcularReserva } from "@/dominio/calculoReserva";
import { cx } from "@/lib/cx";
import s from "./Reserva.module.css";
import { paraValoresReserva, type ReservaForm } from "./tipos";

function Linha({ sinal, rotulo, valor, total }: { sinal: string; rotulo: string; valor: number | null; total?: boolean }) {
  return (
    <div className={cx(s.contaLinha, total && s.contaTotal)}>
      <span className={s.contaSinal} aria-hidden>{sinal}</span>
      <span>{rotulo}</span>
      <MoneyValue value={valor} emphasis={rotulo === "Receita da agência" ? "result" : undefined} />
    </div>
  );
}

/** Conta da reserva (ruling 2026-09-14): cobrado − reserva = RAV; comissão + RAV = total da comissão; + taxa = receita. */
export function ResultSummary({ value }: { value: ReservaForm }) {
  const r = calcularReserva(paraValoresReserva(value));
  const pct = r.percentualComissao === null ? "" : ` (${String(r.percentualComissao).replace(".", ",")} %)`;
  return (
    <div className={s.conta}>
      <Linha sinal="" rotulo="Total cobrado do cliente" valor={value.valorCliente} />
      <Linha sinal="−" rotulo="Total da reserva" valor={value.valorTotal} />
      <Linha sinal="=" rotulo="RAV" valor={r.ravCliente} total />
      <Linha sinal="+" rotulo={`Comissão${pct}`} valor={value.valorComissao} />
      {(value.ravOperadora ?? 0) > 0 && <Linha sinal="+" rotulo="RAV da operadora" valor={value.ravOperadora} />}
      <Linha sinal="=" rotulo="Total da comissão" valor={r.totalComissao} total />
      <Linha sinal="+" rotulo="Taxa de serviço" valor={value.taxaServico ?? 0} />
      <Linha sinal="=" rotulo="Receita da agência" valor={r.receitaPrevista} total />
    </div>
  );
}
```
`Reserva.module.css`: add styles, keeping the old `.result*` classes if other files still use them (grep first):
```css
.conta { display: grid; gap: var(--space-1); max-width: 28rem; }
.contaLinha { display: grid; grid-template-columns: 1.25rem 1fr auto; align-items: baseline; gap: var(--space-2); }
.contaSinal { color: var(--text-muted); text-align: center; }
.contaTotal { border-top: 1px solid var(--border-subtle); padding-top: var(--space-1); font-weight: 600; }
```
Use the token names that actually exist in `frontend/src/styles/tokens.css`. Grep for `--space-` and `--border` and pick the matching ones; do not invent tokens.

- [ ] **Step 6: `ReservaDetalheCard.tsx`**

Delete `ROTULO_FLUXO` and `<Leitura rotulo="Fluxo">…`. In `ReservaDetalheCard.test.tsx` and `ReservationCard.test.tsx`, keep the "Receita da agência" assertions (the label still exists) and remove any Fluxo assertion.

- [ ] **Step 7: e2e label**

`frontend/e2e/nova-viagem.spec.ts:35`: change `getByLabel("Venda ao cliente", { exact: true })` to `getByLabel("Total cobrado do cliente", { exact: true })`. Grep `e2e/` for any other `"Venda ao cliente"` or `"Comissão"` label lookup and update it to `"Comissão (R$)"` if it targets the input.

- [ ] **Step 8: Run**

Run: `cd frontend && npx vitest run src/components/Reserva src/pages/viagens`, then full `npx vitest run`, `npm run lint`, `npm run build`.
Expected: all green. If the harness environment has the app running, also run `npx playwright test e2e/nova-viagem.spec.ts`; otherwise report that it was not run.

- [ ] **Step 9: Report** files (no commit). Controller commit: `feat(reserva): single calculated RAV, commission % and R$, result as equation`.

---

### Task 4: Trip level — one vocabulary, average commission, seller commission %

**Agent:** `frontend-specialist`. Reviewer: `code-reviewer`.
**Depends-on:** Task 1 (JSON contract), Task 2 (`totalComissao`).
**Files:**
- Modify: `frontend/src/api/viagens.ts` (`ViagemRequest` ~134, `RepasseDto` 185-189)
- Modify: `frontend/src/components/Viagem/TripSummary.tsx`
- Test: `frontend/src/components/Viagem/TripSummary.test.tsx`
- Modify: `frontend/src/pages/viagens/useNovaViagem.ts` (`ViagemForm` 35, `VAZIO` 49, `paraForm` 71, `paraViagemRequest` 91, `repasseSugerido` 368-372, return object)
- Test: `frontend/src/pages/viagens/useNovaViagem.repasse.test.ts`
- Modify: `frontend/src/pages/viagens/DadosViagemSection.tsx` (89-104)
- Modify: `frontend/src/pages/viagens/NovaViagemPage.tsx` (props passed to `DadosViagemSection`, ~132)
- Test: `frontend/src/pages/viagens/NovaViagemPage.test.tsx` (~248)
- Modify: `frontend/src/pages/viagens/mapaErros.ts` (11-12)
- Modify: `frontend/src/pages/viagens/detalhe/ResumoTab.tsx`, `FinanceiroTab.tsx`, `fixtures.ts` (add `percentual: null` to the repasse fixture)
- Test: `frontend/src/pages/viagens/detalhe/ResumoTab.test.tsx`, `FinanceiroTab.test.tsx`
- Modify: `frontend/src/components/viagem/FaixaResumo.test.tsx` (stale label only)
- Modify: `frontend/e2e/api.ts:99`, `frontend/e2e/financeiro.ts:60` (add `repassePercentual: null` next to `repasseValor: null`)

**Interfaces:**
- Consumes: `repassePercentual` / `percentual` JSON (Task 1); `calcularReserva().totalComissao` (Task 2).
- Produces:
  - `somarReservas(reservas)` now also returns `totalComissao: number` and `comissaoMedia: number | null`.
  - `comissaoMedia` = `arredondar2(100 * Σ valorComissao / Σ valorTotal)` over non-cancelled reservations; `null` when Σ total = 0.

- [ ] **Step 1: Failing tests**

`TripSummary.test.tsx`:
```ts
test("somarReservas devolve total da comissão e comissão média ponderada", () => {
  const r = somarReservas([
    { valorTotal: 10000, valorComissao: 1000, ravOperadora: 0, valorCliente: 10500, taxaServico: 150, ravClienteModo: "via_operadora" },
    { valorTotal: 5000, valorComissao: 250, ravOperadora: 0, valorCliente: 5000, taxaServico: 0, ravClienteModo: "via_operadora" },
    { valorTotal: 9999, valorComissao: 999, ravOperadora: 0, valorCliente: 9999, taxaServico: 0, ravClienteModo: "via_operadora", status: "cancelada" },
  ]);
  expect(r.totalComissao).toBe(1750);
  expect(r.comissaoMedia).toBe(8.33); // 1250 / 15000
});
test("rótulos da faixa do formulário", () => {
  // render TripSummary with the reservations above, mostrarResultado true
  for (const rotulo of ["Total cobrado", "Custo das reservas", "Receita da agência", "Comissão do vendedor", "Despesas da viagem", "Resultado da viagem"])
    expect(screen.getByText(rotulo)).toBeInTheDocument();
  expect(screen.getByText("comissão média 8,33 %")).toBeInTheDocument();
});
```
Update the existing test at ~30 (reduced strip without `viagem.ver_resultado`): expect `Total cobrado`, `Custo das reservas`, `Receita da agência`; remove the stale `"Comissão da vendedora"` assertion.

`useNovaViagem.repasse.test.ts`, following the file's existing harness:
```ts
test("% do vendedor calcula o valor sobre a comissão total (sem taxa de serviço)", () => {
  // reserva: total 10000, cliente 10500, comissão 1000, taxa 150; vendedor geraRepasse
  // act: definirRepassePercentual(10)
  expect(result.current.baseRepasse).toBe(1500);
  expect(form.getValues("repassePercentual")).toBe(10);
  expect(result.current.repasseValorMostrado).toBe(150);
});
test("digitar R$ do vendedor limpa o %", () => {
  // act: definirRepassePercentual(10); definirRepasseValor(99)
  expect(form.getValues("repassePercentual")).toBeNull();
  expect(result.current.repasseValorMostrado).toBe(99);
});
test("sugestão usa o % padrão do vendedor sobre a comissão total", () => {
  // percentualPadrao 10, nada digitado
  expect(result.current.repasseSugerido).toBe(150);
});
```
Update the existing test F1 (null without client sale) so it still holds with the new base.

`ResumoTab.test.tsx` (~56): the label order becomes `["Total cobrado", "Custo das reservas", "Receita da agência", "Comissão do vendedor", "Despesas da viagem", "Resultado da viagem"]`. Line ~8 already expects "Receita da agência". Line ~48 expects the tooltip `/Comissões, RAV e taxas que já entraram/`.
`FinanceiroTab.test.tsx` (~148): expect `Receita da agência`, `Receita recebida` with the same tooltip regex, `Comissão do vendedor`, `Despesas da viagem`, `Resultado da viagem`.
`NovaViagemPage.test.tsx` (~248): expect labels `Comissão do vendedor (%)` and `Comissão do vendedor (R$)` on the form.
`FaixaResumo.test.tsx`: rename the stale `"Comissão da vendedora"` to `"Comissão do vendedor"`.

- [ ] **Step 2: Run and verify the tests fail**

Run: `cd frontend && npx vitest run src/components/Viagem src/pages/viagens src/components/viagem`
Expected: FAIL.

- [ ] **Step 3: API types**

`api/viagens.ts`:
- `ViagemRequest`: add `repassePercentual: number | null;` next to `repasseValor`.
- `RepasseDto`: add `percentual: number | null;`.

- [ ] **Step 4: `somarReservas` and the form strip (`TripSummary.tsx`)**

In the loop, accumulate `comissao += r.valorComissao ?? 0` for every non-cancelled reservation (before the `valorCliente === null` skip). Accumulate `totalComissao += calcularReserva({...}).totalComissao ?? 0` next to `receitaPrevista`; call `calcularReserva` once, into a `const r`. Return `totalComissao: arredondar2(totalComissao)` and `comissaoMedia: custo > 0 ? arredondar2((100 * comissao) / custo) : null`.
Labels:
- `Venda total` → `Total cobrado`
- `Custo dos fornecedores` → `Custo das reservas`
- `Receita das reservas` → `Receita da agência`
- In the full strip, add a `Receita da agência` item before `Comissão do vendedor`.

Under the receita item, when `comissaoMedia !== null`, render `<small>comissão média {String(comissaoMedia).replace(".", ",")} %</small>`.
Result tooltip: `"Receita da agência − comissão do vendedor − despesas vinculadas"`.

- [ ] **Step 5: `useNovaViagem.ts`**

- `ViagemForm`: add `repassePercentual: number | null`; `VAZIO`: `repassePercentual: null`.
- `paraForm`: `repassePercentual: dto.repasse?.percentual ?? null`.
- `paraViagemRequest`: `repassePercentual: v.repassePercentual`.
- Replace the `repasseSugerido` block:
```ts
const { totalComissao, incompleta } = somarReservas(reservas);
const repassePercentual = form.watch("repassePercentual");
// Base do vendedor = comissão total (comissão + RAV) das reservas ativas; taxa de serviço fora (ruling 2026-09-14).
const baseRepasse = incompleta ? null : totalComissao;
const repasseValorMostrado =
  repassePercentual !== null && baseRepasse !== null ? comissaoPorPercentual(repassePercentual, baseRepasse) : repasseValor;
const repasseSugerido =
  baseRepasse !== null && vendedorSelecionado?.geraRepasse && repasseValor === null && repassePercentual === null
    ? comissaoPorPercentual(vendedorSelecionado.percentualPadrao, baseRepasse)
    : null;
function definirRepassePercentual(p: number | null) {
  form.setValue("repassePercentual", p, { shouldDirty: true });
  form.setValue("repasseValor", p !== null && baseRepasse !== null ? comissaoPorPercentual(p, baseRepasse) : null, { shouldDirty: true });
}
function definirRepasseValor(v: number | null) {
  form.setValue("repassePercentual", null, { shouldDirty: true });
  form.setValue("repasseValor", v, { shouldDirty: true });
}
```
Import `comissaoPorPercentual` from `@/lib/comissao`; drop `receitaPrevista`/`arredondar2` imports if now unused. Return `baseRepasse`, `repasseValorMostrado`, `repasseSugerido`, `definirRepassePercentual`, `definirRepasseValor`. Keep `repasseValor` in the form: it is sent too, and the backend ignores it when the percentual is set.

- [ ] **Step 6: `DadosViagemSection.tsx` + `NovaViagemPage.tsx`**

Replace the single field (89-104) with two fields. Props gain `repassePercentual: number | null`, `repasseValorMostrado: number | null`, `onRepassePercentual: (p: number | null) => void`, `onRepasseValor: (v: number | null) => void`, and they replace the direct `form.setValue("repasseValor")`.
```tsx
{mostrarRepasse && (
  <>
    <Field label="Comissão do vendedor (%)" className="span-2"
      tooltip="Percentual sobre a comissão total da viagem (comissão + RAV, sem taxa de serviço). O valor acompanha as reservas até o repasse ser pago."
      helper={repasseSugerido === null ? undefined : `Sugerido: ${formatarDinheiro(repasseSugerido)}`}
      error={erros.repassePercentual}>
      <Input inputMode="decimal"
        value={pctRepasseTexto ?? (repassePercentual === null ? "" : String(repassePercentual).replace(".", ","))}
        onChange={(e) => mudarPctRepasse(e.target.value)} />
    </Field>
    <Field label="Comissão do vendedor (R$)" className="span-2" error={erros.repasseValor}>
      <MoneyInput value={repasseValorMostrado} onChange={(v) => { setPctRepasseTexto(null); onRepasseValor(v); }} />
    </Field>
  </>
)}
```
Local state and parser, the same validation as the reservation commission:
```tsx
const [pctRepasseTexto, setPctRepasseTexto] = useState<string | null>(null);
function mudarPctRepasse(texto: string) {
  const p = parsearPercentual(texto);
  if (p === "invalido" || p === "negativo" || (p !== null && p > 100)) return;
  setPctRepasseTexto(texto);
  onRepassePercentual(p);
}
```
`erros.repassePercentual`: add the key to the errors type where `repasseValor` is declared. `NovaViagemPage.tsx` passes the new hook values.
`mapaErros.ts`: map `percentual_invalido` to `repassePercentual`.

- [ ] **Step 7: Detail tabs**

`ResumoTab.tsx` `faixaDaViagem`, full strip:
```ts
const media = comissaoMedia(viagem.reservas);
itens: [
  { label: "Total cobrado", value: r.vendaTotal },
  { label: "Custo das reservas", value: r.custoFornecedores },
  { label: "Receita da agência", value: r.receitaPrevista,
    badge: media === null ? undefined : <small>comissão média {String(media).replace(".", ",")} %</small> },
  { label: "Comissão do vendedor", value: r.repasseValor, badge: /* unchanged */ },
  { label: "Despesas da viagem", value: r.despesasViagem },
  { label: "Resultado da viagem", value: r.resultado, destaque: true, tooltip: TOOLTIP_RESULTADO },
],
```
Export a helper from `TripSummary.tsx`, `comissaoMedia(reservas: { valorTotal?: number | null; valorComissao?: number | null; status?: string }[]): number | null`, computed the same way as in `somarReservas`, and reuse it inside `somarReservas`.
Reduced strip: labels `Total cobrado`, `Custo das reservas`, `Receita da agência`.
`TOOLTIP_RECEBIDA = "Comissões, RAV e taxas que já entraram no caixa (movimentos)"`.
`TOOLTIP_RESULTADO = "Receita da agência − comissão do vendedor − despesas vinculadas"`.
`FinanceiroTab.tsx` items: `Receita da agência`, `Receita recebida` (tooltip), `Comissão do vendedor` (badge), `Despesas da viagem`, `Resultado da viagem` (destaque).

- [ ] **Step 8: Run**

Run: `cd frontend && npx vitest run` (full), `npm run lint`, `npm run build`. Expected: green. Playwright specs that read strip labels: grep `e2e/` for `Venda total|Custo dos fornecedores|Receita prevista` and update them to the new labels.

- [ ] **Step 9: Report** files (no commit). Controller commit: `feat(viagem): unified money vocabulary, average commission, seller commission percentage`.

---

### Task 5: Spec and state (controller)

**Depends-on:** Tasks 1–4.
**Files:** `regras-e-escopo-v2.md`, `schema-agencia-v2.sql`, `docs/BACKLOG.md`, `CLAUDE.md` (state line), `docs/schema-v2-smoke.mjs` only if it creates `repasse`.

- [ ] **Step 1: Spec**
  - `regras-e-escopo-v2.md` §2 glossary "Repasse": "Valor pago ao vendedor externo por uma viagem. Informado em % da comissão total da viagem (comissão + RAV, sem taxa de serviço) e recalculado enquanto não pago, ou digitado em R$ (ruling 2026-09-14)."
  - §4.2: note that the UI exposes one RAV = `valor_cliente − valor_total`; `rav_operadora` and `rav_cliente_modo` stay in the schema for legacy data, and new reservations send `0`/`via_operadora`.
  - §4.3: every trip entered is already paid to the supplier; `fluxo_pagamento` is fixed at `cliente_paga_operadora` in the UI.
  - §5: `repasse.percentual`.
  - Rulings table: new line.
- [ ] **Step 2: Schema** — `schema-agencia-v2.sql`, `repasse` table: add `percentual numeric(5,2) constraint repasse_percentual_faixa check (percentual >= 0 and percentual <= 100)`.
- [ ] **Step 3: BACKLOG + CLAUDE.md state** — migrations 0001–0026, test counts from the final runs.
- [ ] **Step 4: Commit root** — `docs: financial screen simplification rulings (single RAV, seller commission %)`.
