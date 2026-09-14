# Redesign da viagem — Fase 1 (Nova viagem / Edição) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execução em ondas segue `.claude/rules/parallel-subagent-driven-development.md`: **implementadores não commitam**; o controlador commita por task.

**Goal:** Reconstruir a tela Nova viagem / Edição como área de trabalho com painel financeiro fixo e reservas em lista densa, e passar a exigir ida, volta e ao menos uma reserva para salvar a viagem.

**Architecture:** `NovaViagemPage` vira grid de 2 colunas (conteúdo + `TripSummary` reescrito como painel vertical sticky; abaixo de 1280 px o mesmo elemento vira barra sticky no rodapé — um único nó no DOM, só CSS muda). `ReservationCard` vira linha densa com corpo expandido no lugar; valores calculados saem dos inputs e viram texto. A regra "viagem só salva completa" é validada em `useNovaViagem.validar` e em `ViagensService` (422 com `codigo`).

**Tech Stack:** React 19 + Vite + TypeScript, react-hook-form, TanStack Query, CSS Modules com tokens (`frontend/src/styles/tokens.css`), Vitest + Testing Library, Playwright; .NET 10 Minimal API + Dapper, xUnit + Testcontainers.

**Spec:** `docs/superpowers/specs/2026-09-14-redesign-viagem-fase1-design.md`

## Global Constraints

- Três repos git independentes: root `E:\workspace\viva-erp`, `backend/`, `frontend/`. Branch de trabalho **`feat/redesign-viagem-f1`** criada a partir de `develop` em `backend/` e `frontend/` antes da Onda 1 (controlador). Sem push.
- Proibido em componente: hex, `font-size` literal, margin arbitrária, cor custom em botão (`npm run lint:tokens` falha). Só tokens semânticos/componente.
- `Button` tem 5 variantes (`business` · `primary` · `secondary` · `tertiary` · `danger`). **Nesta tela, `business` só em "Salvar viagem".**
- Português em textos, nomes de domínio e mensagens. Commits Conventional Commits em inglês com rodapé:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Ad2nkxMcpVC3pWQeu2yyRA
  ```
- Não mudar: `MoneyInput`, `calcularReserva`, `useSalvamento`, `useRepasseVendedor`, lógica de âncora %/R$, A03/A04/A05/ALT-01/ALT-13, `paraViagemRequest` (canceladas fora do PUT), `ReservaDetalheCard`, `FaixaResumo`, `ResultSummary` (conteúdo).
- Nomes acessíveis que continuam idênticos: region "Reserva N"; labels "Fornecedor", "Localizador", "Total da reserva", "Total cobrado do cliente", "Comissão (%)", "Comissão (R$)", "Destino", "Tipo", "Ida", "Volta", "Passageiros", "Comissão do vendedor (%)", "Comissão do vendedor (R$)"; botões "Salvar viagem", "Fechar", "Expandir"/"Recolher", "Remover reserva", "+ Adicionar reserva", "+ pessoa", "+ novo"; chip "Aéreo"; texto "✓ Salvo".
- Mensagens novas (exatas): "Informe a data de ida" · "Informe a data de volta" · "Adicione ao menos uma reserva". Códigos: `data_ida_obrigatoria` · `data_volta_obrigatoria` · `reserva_obrigatoria`.
- Comandos canônicos: front `cd frontend && npm run lint` · `npm run typecheck` · `npm run test` · `npm run build` · `npx playwright test e2e/nova-viagem.spec.ts`; back `cd backend && dotnet format --verify-no-changes` · `dotnet build -c Release` · `dotnet test` (Docker rodando).

## Ondas

| Onda | Tasks | Motivo |
|---|---|---|
| 1 | T1, T2, T3, T4 | arquivos disjuntos, sem dependência |
| 2 | T5 | usa `Viagem.module.css` (T4 mexe) |
| 3 | T6 | monta a página com T2–T5 |
| 4 | T7 | E2E, docs e verificação visual sobre tudo |

---

### Task 1: API — viagem só salva com ida, volta e reserva

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagensService.cs` (`ValidarCabecalho` ~l.150-169, `CriarAsync` ~l.20, `AtualizarAsync` ~l.110-116)
- Create: `backend/tests/Meridiano.Api.Tests/ViagemCompletaTests.cs`
- Modify: testes existentes que falharem por criar/editar viagem sem datas ou sem reserva (esperado: `ViagensCriarTests.cs`, `ViagensEditarTests.cs`, `ViagensOperacoesTests.cs`, `RepassePercentualTests.cs`, `CreditosTests.cs` e outros que postem em `/api/viagens`)

**Interfaces:**
- Produces: 422 ProblemDetails com `codigo` `data_ida_obrigatoria` / `data_volta_obrigatoria` / `reserva_obrigatoria` em `POST /api/viagens` e `PUT /api/viagens/{id}`.

- [ ] **Step 1: Ler um teste de criação existente** — abrir `backend/tests/Meridiano.Api.Tests/ViagensCriarTests.cs` e copiar o padrão de cenário (`Cenario`, `Pedido(...)`, cliente HTTP logado, asserção de 422 com `codigo`). O novo arquivo usa exatamente esse padrão (coleção xUnit `"db"`).

- [ ] **Step 2: Escrever os testes que falham** em `ViagemCompletaTests.cs`, cobrindo:
  1. `POST` sem `dataIda` → 422 `data_ida_obrigatoria`.
  2. `POST` sem `dataVolta` → 422 `data_volta_obrigatoria`.
  3. `POST` com datas e `reservas = []` → 422 `reserva_obrigatoria`; nenhuma linha em `viagem` criada (contar antes/depois).
  4. `PUT` de viagem existente enviando `dataIda = null` → 422 `data_ida_obrigatoria`.
  5. `PUT` de viagem cuja única reserva foi cancelada (cancelar via endpoint de cancelamento de reserva usado em `ViagensOperacoesTests.cs`), enviando `reservas = []` (o front omite canceladas) → **200**.
  6. `AdicionarReserva` (`POST /api/viagens/{id}/reservas`) continua 200 (regra não se aplica).

  Para "viagem existente" use o helper de criação do próprio arquivo de cenário, sempre com `dataIda = $"{Ano}-04-18"`, `dataVolta = $"{Ano}-04-28"` e uma reserva válida.

- [ ] **Step 3: Rodar e ver falhar**
  Run: `cd backend && dotnet test --filter FullyQualifiedName~ViagemCompletaTests`
  Expected: 1–4 FAIL (status 201/200 em vez de 422); 5–6 PASS.

- [ ] **Step 4: Implementar em `ValidarCabecalho`** — logo **depois** das checagens de titular (para os testes `sem_titular`/`dois_titulares`/`sem_passageiro` continuarem recebendo o próprio código) e antes das de repasse:

```csharp
        if (req.DataIda is null) throw new RegraDeNegocioException("data_ida_obrigatoria", "Informe a data de ida");
        if (req.DataVolta is null) throw new RegraDeNegocioException("data_volta_obrigatoria", "Informe a data de volta");
```

  E mover a linha `datas_incoerentes` para depois dessas duas (continua igual no conteúdo). Atenção ao teste `volta_antes_da_ida` em `ViagensCriarTests.cs`: ele tem as duas datas, então segue recebendo `datas_incoerentes`; os que não têm datas mas esperam `sem_titular`/`sem_passageiro` só passam se as checagens de passageiro vierem antes — confirme a ordem final:
  destino → textos → tipo → **passageiros/titular** → **ida/volta obrigatórias** → **datas incoerentes** → repasse.

- [ ] **Step 5: Implementar em `CriarAsync`** — logo após `req = ValidarCabecalho(req)` (antes de abrir sessão/inserts):

```csharp
        if (req.Reservas is not { Length: > 0 }) throw new RegraDeNegocioException("reserva_obrigatoria", "Adicione ao menos uma reserva");
```

  (Se `Reservas` não for array, usar `req.Reservas is null || !req.Reservas.Any()`.)

- [ ] **Step 6: Implementar em `AtualizarAsync`** — depois do `foreach (var r in reservas)` que insere/atualiza e **antes** de `Rotinas.ReavaliarRepasseAsync`:

```csharp
        // O PUT omite reservas canceladas (imutáveis), então "ao menos uma reserva" é contado no banco, qualquer status.
        var totalReservas = await s.Conexao.ExecuteScalarAsync<int>(new CommandDefinition(
            "select count(*)::int from reserva where viagem_id = @id and agencia_id = @agencia and excluido_em is null",
            new { id, agencia = ctx.AgenciaId }, s.Transacao, cancellationToken: ct));
        if (totalReservas == 0) throw new RegraDeNegocioException("reserva_obrigatoria", "Adicione ao menos uma reserva");
```

  Confirmar no schema (`backend/src/Meridiano.Data/Migrations/*.sql`, `grep "create table reserva"`) que a tabela é `reserva` com `viagem_id`, `agencia_id`, `excluido_em`; ajustar nomes se diferirem.

- [ ] **Step 7: Rodar os novos testes**
  Run: `cd backend && dotnet test --filter FullyQualifiedName~ViagemCompletaTests`
  Expected: 6 PASS.

- [ ] **Step 8: Rodar a suíte inteira e corrigir fixtures**
  Run: `cd backend && dotnet test`
  Para cada falha com `data_ida_obrigatoria` / `data_volta_obrigatoria` / `reserva_obrigatoria`: o teste não é sobre essa regra → ajustar o **pedido do teste** (nunca a regra) para enviar `dataIda`/`dataVolta` válidas e ao menos uma reserva válida, reaproveitando o helper de reserva do próprio arquivo. Não mudar asserções de outros comportamentos. Repetir até verde (esperado: 341+6 API, 39 domínio).

- [ ] **Step 9: Lint e build**
  Run: `cd backend && dotnet format --verify-no-changes && dotnet build -c Release`
  Expected: sem mudanças de formato; build sem warnings.

- [ ] **Step 10: Reportar ao controlador** — lista de arquivos tocados. **Não commitar.** Controlador commita no repo `backend/`: `feat(viagens): require dates and at least one reservation to save a trip`.

---

### Task 2: `useNovaViagem` — validação completa, expandir sem sujar, contador de erros

**Files:**
- Modify: `frontend/src/pages/viagens/useNovaViagem.ts` (`validar` l.104-111, `alternarReserva` l.215-220, retorno l.379-406)
- Modify: `frontend/src/pages/viagens/mapaErros.ts` (l.4-15)
- Modify: `frontend/src/pages/viagens/useNovaViagem.harness.ts` (`viagemDto`: `dataVolta`)
- Create: `frontend/src/pages/viagens/useNovaViagem.completa.test.ts`
- Modify: testes `useNovaViagem*.test.ts` que passarem a falhar por falta de datas/reserva

**Interfaces:**
- Produces (usado por T6):
  - `erros.dataIda`, `erros.dataVolta`, `erros.reservas` (string) no retorno de `useNovaViagem`.
  - `totalErros: number` — `Object.keys(erros).length` + soma das chaves de `errosReservas`.
  - `alternarReserva(i)` não altera `form.formState.isDirty`.

- [ ] **Step 1: Escrever os testes que falham** — `useNovaViagem.completa.test.ts`:

```ts
import { act } from "@testing-library/react";
import { chamadas, esperar, montar, reiniciar } from "./useNovaViagem.harness";

beforeEach(reiniciar);
afterEach(() => {
  vi.unstubAllGlobals();
});

function preencherCabecalho(result: ReturnType<typeof montar>["result"]) {
  act(() => {
    result.current.form.setValue("destino", "Lisboa");
    result.current.form.setValue("passageiros", [{ clienteId: "c1", nome: "Carlos", titular: true }]);
  });
}

test("salvar sem ida, volta e reserva não chama a API e aponta os três erros", async () => {
  const { result } = montar();
  await esperar.agencia(result);
  preencherCabecalho(result);

  let ok = true;
  await act(async () => {
    ok = await result.current.salvar();
  });

  expect(ok).toBe(false);
  expect(result.current.erros.dataIda).toBe("Informe a data de ida");
  expect(result.current.erros.dataVolta).toBe("Informe a data de volta");
  expect(result.current.erros.reservas).toBe("Adicione ao menos uma reserva");
  expect(result.current.totalErros).toBe(3);
  expect(chamadas.some((c) => c.metodo === "POST")).toBe(false);
});

test("volta antes da ida continua com a mensagem própria", async () => {
  const { result } = montar();
  await esperar.agencia(result);
  preencherCabecalho(result);
  act(() => {
    result.current.form.setValue("dataIda", "2026-05-10");
    result.current.form.setValue("dataVolta", "2026-05-01");
  });

  await act(async () => {
    await result.current.salvar();
  });

  expect(result.current.erros.dataVolta).toBe("Volta antes da ida");
});

test("erro de reserva some ao adicionar a primeira reserva", async () => {
  const { result } = montar();
  await esperar.agencia(result);
  preencherCabecalho(result);
  await act(async () => {
    await result.current.salvar();
  });
  expect(result.current.erros.reservas).toBeDefined();

  act(() => {
    result.current.adicionarReserva();
  });

  expect(result.current.erros.reservas).toBeUndefined();
});

test("reserva cancelada conta como reserva para salvar", async () => {
  const { result } = montar("v9");
  await esperar.viagem(result);
  act(() => {
    const [r] = result.current.form.getValues("reservas");
    result.current.form.setValue("reservas", [{ ...r!, status: "cancelada" }]);
    result.current.form.setValue("dataVolta", "2026-04-28");
  });

  await act(async () => {
    await result.current.salvar();
  });

  expect(result.current.erros.reservas).toBeUndefined();
  expect(chamadas.some((c) => c.metodo === "PUT")).toBe(true);
});

test("expandir/recolher reserva não marca alterações não salvas", async () => {
  const { result } = montar("v9");
  await esperar.viagem(result);

  act(() => {
    result.current.alternarReserva(0);
  });

  expect(result.current.form.getValues("reservas")[0]?.aberta).toBe(true);
  expect(result.current.form.formState.isDirty).toBe(false);
  expect(result.current.salvamento.estado).not.toBe("dirty");
});
```

- [ ] **Step 2: Rodar e ver falhar**
  Run: `cd frontend && npx vitest run src/pages/viagens/useNovaViagem.completa.test.ts`
  Expected: FAIL (erros indefinidos, `totalErros` indefinido, isDirty true).

- [ ] **Step 3: Implementar `validar`**

```ts
/** Campos que a tela cobra antes de gastar uma ida ao servidor (spec §4.1; ruling 2026-09-14: viagem só salva completa). */
function validar(v: ViagemForm): Record<string, string> {
  const e: Record<string, string> = {};
  if (!v.destino.trim()) e.destino = "Informe o destino";
  if (v.passageiros.length === 0) e.passageiros = "Adicione ao menos um passageiro";
  if (!v.vendedorId) e.vendedorId = "Escolha quem vendeu";
  if (!v.dataIda) e.dataIda = "Informe a data de ida";
  if (!v.dataVolta) e.dataVolta = "Informe a data de volta";
  else if (v.dataIda && v.dataVolta < v.dataIda) e.dataVolta = "Volta antes da ida";
  // Qualquer status conta: viagem com todas as reservas canceladas continua editável.
  if (v.reservas.length === 0) e.reservas = "Adicione ao menos uma reserva";
  return e;
}
```

- [ ] **Step 4: Implementar `alternarReserva` sem sujar**

```ts
  // Abrir/recolher é estado de tela, não edição: não pode acender "Alterações não salvas".
  const alternarReserva = useCallback(
    (i: number) => {
      form.setValue(
        "reservas",
        form.getValues("reservas").map((r, j) => (j === i ? { ...r, aberta: !r.aberta } : r)),
      );
    },
    [form],
  );
```

- [ ] **Step 5: Expor `totalErros`** — depois do cálculo de `errosReservas`:

```ts
  const totalErros =
    Object.keys(erros).length + errosReservas.reduce((n, e) => n + Object.keys(e).length, 0);
```

  e adicionar `totalErros,` ao objeto retornado (ao lado de `erros`, `errosReservas`).

- [ ] **Step 6: `mapaErros.ts`** — acrescentar em `CAMPO_POR_CODIGO`:

```ts
  data_ida_obrigatoria: "dataIda",
  data_volta_obrigatoria: "dataVolta",
  reserva_obrigatoria: "reservas",
```

- [ ] **Step 7: Harness** — em `viagemDto`, `dataVolta: null` → `dataVolta: "2026-04-28"`.

- [ ] **Step 8: Rodar os novos testes**
  Run: `cd frontend && npx vitest run src/pages/viagens/useNovaViagem.completa.test.ts`
  Expected: 5 PASS.

- [ ] **Step 9: Rodar todos os testes do hook e corrigir setups**
  Run: `cd frontend && npx vitest run src/pages/viagens`
  Testes que salvam só com destino+passageiro (ex.: "422 esperado_negativo…" em `useNovaViagem.validacaoReserva.test.ts`, e os de `useNovaViagem.test.ts`) passam a parar na validação local. Corrigir o **setup** do teste acrescentando antes de `salvar()`:

```ts
  act(() => {
    result.current.form.setValue("dataIda", "2026-04-18");
    result.current.form.setValue("dataVolta", "2026-04-28");
    result.current.adicionarReserva();
  });
  act(() => {
    result.current.atualizarReserva(0, { fornecedorId: "f1", valorTotal: 1000, valorCliente: 1000 });
  });
```

  `NovaViagemPage.test.tsx` fica para T6 (não mexer aqui). Esperado ao final: tudo verde em `src/pages/viagens` exceto `NovaViagemPage.test.tsx`.

- [ ] **Step 10: Typecheck + lint**
  Run: `cd frontend && npm run typecheck && npm run lint`
  Expected: sem erros.

- [ ] **Step 11: Reportar arquivos ao controlador. Não commitar.** Commit do controlador: `feat(viagens): require dates and a reservation before saving; expanding a reservation no longer marks the form dirty`.

---

### Task 3: `ReservationCard` — linha densa + corpo expandido, resultado em texto

**Files:**
- Modify: `frontend/src/components/Reserva/ReservationCard.tsx`
- Modify: `frontend/src/components/Reserva/BookingFields.tsx` (spans)
- Modify: `frontend/src/components/Reserva/FinancialFields.tsx` (remove RAV/Total da comissão como input; spans; tooltip da taxa)
- Modify: `frontend/src/components/Reserva/Reserva.module.css`
- Modify: `frontend/src/components/Reserva/ReservationCard.test.tsx`, `FinancialFields.test.tsx`, `BookingFields.test.tsx` (se referenciarem o que mudou)

**Interfaces:**
- Consumes: nada novo. Props de `ReservationCard` **inalteradas** (`ReservasTab` continua usando).
- Produces: `section[aria-labelledby]` com nome "Reserva N"; `header` = linha densa; corpo só quando `value.aberta`; parágrafo `aria-label="Resultado desta reserva"` com RAV, Total da comissão e Receita da agência.

- [ ] **Step 1: Atualizar/escrever testes** em `ReservationCard.test.tsx`:
  - Substituir o teste "aberta mostra o ResultSummary…" por:

```tsx
test("aberta mostra o resultado em texto: RAV, total da comissão e receita (3000/300/20/3200 via_operadora)", () => {
  render(<ReservationCard {...base({ value: reservaPreenchida(true) })} />);
  const resultado = screen.getByLabelText("Resultado desta reserva");
  expect(resultado).toHaveTextContent("RAV");
  expect(resultado).toHaveTextContent("Total da comissão");
  expect(resultado).toHaveTextContent("Receita da agência");
  expect(within(resultado).getByText("R$ 520,00")).toBeInTheDocument();
  // calculado não é input
  expect(screen.queryByLabelText("RAV")).toBeNull();
  expect(screen.queryByLabelText("Total da comissão")).toBeNull();
});

test("recolhida com erro mostra marcador 'com erro' na linha", () => {
  render(<ReservationCard {...base({ erros: { fornecedorId: "Escolha o fornecedor" } })} />);
  const header = screen.getByRole("region", { name: "Reserva 1" }).querySelector("header");
  expect(header).toHaveTextContent("com erro");
});

test("aberta não mostra marcador de erro na linha (o erro está no campo)", () => {
  render(
    <ReservationCard {...base({ value: reservaPreenchida(true), erros: { fornecedorId: "Escolha o fornecedor" } })} />,
  );
  const header = screen.getByRole("region", { name: "Reserva 1" }).querySelector("header");
  expect(header).not.toHaveTextContent("com erro");
});
```

  - Manter os demais (nome "Reserva 1", "receita —", Expandir chama onToggle, Remover fora do header, cancelada read-only, maxLength 40).
  - Em `FinancialFields.test.tsx`, remover/ajustar asserções sobre inputs "RAV"/"Total da comissão" (agora inexistentes) — o valor passa a ser coberto pelo teste acima.

- [ ] **Step 2: Rodar e ver falhar**
  Run: `cd frontend && npx vitest run src/components/Reserva`
  Expected: FAIL nos testes novos.

- [ ] **Step 3: `ReservationCard.tsx`** — substituir o JSX retornado:

```tsx
import { ChevronDown, CircleAlert, Trash2 } from "lucide-react";
import { useId } from "react";
import { type FornecedorDto, ROTULO_SERVICO } from "@/api/viagens";
import { Button, MoneyValue } from "@/components";
import { Alert, StatusBadge } from "@/components/display";
import { calcularReserva } from "@/dominio/calculoReserva";
import { cx } from "@/lib/cx";
import { BookingFields } from "./BookingFields";
import { FinancialFields } from "./FinancialFields";
import s from "./Reserva.module.css";
import { paraValoresReserva, type ReservaForm } from "./tipos";

// (interface ReservationCardProps inalterada)

export function ReservationCard({ indice, value, onChange, onToggle, onRemover, fornecedores, onNovoFornecedor, erros, avisoDuplicada }: ReservationCardProps) {
  const idTitulo = useId();
  const fornecedor = fornecedores.find((f) => f.id === value.fornecedorId);
  const resultado = calcularReserva(paraValoresReserva(value));
  const servicos = value.tiposServico.map((t) => ROTULO_SERVICO[t]).join(" · ");
  const percentualSugerido = fornecedor?.percentualComissaoPadrao ?? null;
  const cancelada = value.status === "cancelada";
  const comErro = !value.aberta && Object.values(erros).some(Boolean);

  // <section> com nome acessível já tem role="region" implícito; getByRole("region", { name: "Reserva N" }).
  return (
    <section aria-labelledby={idTitulo} className={cx(s.reserva, value.aberta && s.aberta, cancelada && s.cancelada)}>
      <header className={s.linha}>
        <span id={idTitulo} className={s.num}>
          <span className={s.srOnly}>Reserva </span>
          {indice}
        </span>
        <span className={s.quem}>
          <span className={s.fornecedor}>{fornecedor?.nome ?? "Sem fornecedor"}</span>
          {servicos && <span className={s.servicos}>{servicos}</span>}
        </span>
        <span className={s.localizador}>{value.localizador}</span>
        <span className={s.status}>
          <StatusBadge entidade="reserva" valor={value.status} />
          {comErro && (
            <span className={s.marcaErro}>
              <CircleAlert size={16} aria-hidden /> com erro
            </span>
          )}
        </span>
        <span className={s.valor}>
          <MoneyValue value={value.valorCliente} />
        </span>
        <small className={s.receita}>
          receita <MoneyValue value={resultado.receitaPrevista} />
        </small>
        <Button
          variant="tertiary"
          size="sm"
          aria-expanded={value.aberta}
          icon={<ChevronDown size={16} className={cx(s.chevron, value.aberta && s.chevronAberto)} />}
          onClick={onToggle}
        >
          {value.aberta ? "Recolher" : "Expandir"}
        </Button>
      </header>
      {value.aberta && (
        <div className={s.corpo}>
          {avisoDuplicada && <Alert tone="warning">{avisoDuplicada}</Alert>}
          <BookingFields value={value} onChange={onChange} fornecedores={fornecedores} onNovoFornecedor={onNovoFornecedor} erros={erros} readOnly={cancelada} />
          <FinancialFields value={value} onChange={onChange} percentualSugerido={percentualSugerido} erros={erros} readOnly={cancelada} />
          <div className={s.rodapeReserva}>
            <p className={s.resultado} aria-label="Resultado desta reserva">
              <span>RAV <MoneyValue value={resultado.ravCliente} /></span>
              <span aria-hidden>·</span>
              <span>Total da comissão <MoneyValue value={resultado.totalComissao} /></span>
              <span aria-hidden>·</span>
              <span className={s.resultadoReceita}>Receita da agência <MoneyValue value={resultado.receitaPrevista} emphasis="result" /></span>
            </p>
            {!cancelada && (
              <Button variant="tertiary" size="sm" className={s.remover} icon={<Trash2 size={16} />} onClick={onRemover}>
                Remover reserva
              </Button>
            )}
          </div>
        </div>
      )}
    </section>
  );
}
```

  Verificar: `Button` aceita `icon` e `className` (ver `components/Button/Button.tsx`); `MoneyValue` aceita `emphasis="result"` (já usado em `ResultSummary`). Se `ChevronDown` receber `className` quebrar tipos, envolver num `<span className=…>`. Formatar com `npx biome check --write src/components/Reserva`.

- [ ] **Step 4: `BookingFields.tsx`** — só as classes: Fornecedor `span-4`, Localizador `span-3`, Data da compra `span-2`, NFSe `span-3`; Serviços continua `span-12`.

- [ ] **Step 5: `FinancialFields.tsx`**
  - Remover os dois `<Field label="RAV">` e `<Field label="Total da comissão">` e a constante `r = calcularReserva(...)` + import de `calcularReserva` se ficar sem uso.
  - Spans: Total da reserva `span-3`, Total cobrado do cliente `span-3`, Comissão (%) `span-2`, Comissão (R$) `span-2`, Taxa de serviço `span-2`, Formas de pagamento `span-12`.
  - Taxa de serviço: remover `helper` e usar
    `tooltip="Valor fixo cobrado do cliente por fora da reserva, sem custo por trás (ex.: assessoria, visto). Soma direto na receita da agência."`

- [ ] **Step 6: `Reserva.module.css`** — substituir `.card`, `.header` (+ media), `.numId`, `.total`, `.receitaSmall`, `.body`, `.footer`, `.group`, `.eyebrow` por (manter `.chips`, `.mono`, `.fornecedorRow`, `.mais`, `.control`, `.conta*`):

```css
.reserva {
  background: var(--color-bg-surface);
  border-top: 1px solid var(--color-border);
}
.reserva:first-child {
  border-top: 0;
}
.linha {
  display: grid;
  grid-template-columns: 2rem minmax(0, 1fr) 7rem 9rem 7.5rem 8rem auto;
  align-items: center;
  gap: var(--space-3);
  min-height: var(--table-row-h);
  padding: var(--space-2) var(--space-4);
}
.linha:hover {
  background: var(--table-row-hover);
}
.aberta > .linha {
  background: var(--color-bg-subtle);
}
.num {
  font: var(--type-label);
  color: var(--color-text-muted);
  font-variant-numeric: tabular-nums;
}
.srOnly {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip: rect(0 0 0 0);
  white-space: nowrap;
}
.quem {
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.fornecedor {
  font: var(--type-component);
  color: var(--color-text-heading);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.servicos {
  font: var(--type-helper);
  color: var(--color-text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.localizador {
  font: var(--type-code);
  color: var(--color-text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
}
.status {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: var(--space-1);
}
.marcaErro {
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
  font: var(--type-helper);
  color: var(--color-danger-text);
}
.valor {
  font: var(--type-label);
  color: var(--color-text-primary);
  text-align: right;
  font-variant-numeric: tabular-nums;
}
.receita {
  font: var(--type-helper);
  color: var(--color-text-muted);
  text-align: right;
  font-variant-numeric: tabular-nums;
}
.chevron {
  transition: transform 120ms ease;
}
.chevronAberto {
  transform: rotate(180deg);
}
.cancelada .quem,
.cancelada .valor,
.cancelada .localizador {
  color: var(--color-text-muted);
}
.corpo {
  display: flex;
  flex-direction: column;
  gap: var(--space-6);
  padding: var(--space-4) var(--space-4) var(--space-4) calc(2rem + var(--space-4) + var(--space-3));
  background: var(--color-bg-subtle);
  border-top: 1px solid var(--color-border);
}
.rodapeReserva {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: var(--space-4);
  padding-top: var(--space-4);
  border-top: 1px solid var(--color-border);
}
.resultado {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--space-2);
  font: var(--type-body);
  color: var(--color-text-secondary);
  font-variant-numeric: tabular-nums;
}
.resultadoReceita {
  font: var(--type-label);
  color: var(--color-text-primary);
}
.remover {
  margin-left: auto;
  color: var(--color-danger-text);
}
@media (max-width: 1023px) {
  .linha {
    grid-template-columns: 2rem minmax(0, 1fr) 9rem 7.5rem auto;
  }
  .localizador,
  .receita {
    display: none;
  }
  .corpo {
    padding-left: var(--space-4);
  }
}
```

  Se `lint:tokens` recusar `120ms`/`rem` literais, trocar a transição por nenhuma e as colunas por `minmax` equivalentes aceitos pelo script (ver `frontend/scripts/check-tokens.mjs`).

- [ ] **Step 7: Rodar testes do componente**
  Run: `cd frontend && npx vitest run src/components/Reserva src/pages/viagens/detalhe/ReservasTab.test.tsx`
  Expected: PASS (ReservasTab usa o card isolado e continua verde).

- [ ] **Step 8: Typecheck + lint**
  Run: `cd frontend && npm run typecheck && npm run lint`

- [ ] **Step 9: Reportar arquivos. Não commitar.** Commit do controlador: `feat(reserva): dense reservation row with inline body and text-only calculated values`.

---

### Task 4: `TripSummary` → painel vertical da viagem

**Files:**
- Modify: `frontend/src/components/Viagem/TripSummary.tsx` (componente; `somarReservas`, `comissaoMedia`, `rotuloComissaoMedia` inalterados)
- Modify: `frontend/src/components/Viagem/Viagem.module.css` (bloco `/* TripSummary */` l.106-148)
- Modify: `frontend/src/components/Viagem/TripSummary.test.tsx`
- Modify: `frontend/src/pages/styleguide/StyleguidePage.tsx` (~l.292, remover `onAdicionarReserva`)
- Modify: `frontend/src/styles/tokens.css` (tokens do painel)

**Interfaces:**
- Produces (usado por T6):

```ts
interface TripSummaryProps {
  reservas: ReservaValores[];
  repasseValor: number | null;
  despesas: number;
  mostrarResultado?: boolean;
  /** Bloco da reserva aberta (título + ResultSummary), montado pela página. Ausente = dica "Abra uma reserva…". */
  detalheReserva?: ReactNode;
  /** Rodapé do painel (atalhos). */
  rodape?: ReactNode;
}
```
  Raiz: `<aside aria-label="Resumo da viagem" className={s.painel}>`. Classes de responsividade ficam no CSS do componente: `.painel` sticky no topo ≥1280; `< 1280` sticky no rodapé mostrando só Total cobrado, Receita e Resultado (`.soLargo` escondido).
- Tokens novos: `--painel-viagem-w: 340px;` `--painel-viagem-w-xl: 300px;` na seção COMPONENTES de `tokens.css`.

- [ ] **Step 1: Atualizar testes** em `TripSummary.test.tsx`:
  - Remover `onAdicionarReserva={vi.fn()}` de todos os renders e a asserção do botão "+ Adicionar reserva" (l.58).
  - Substituir o teste de incompleta (l.106-121) por:

```tsx
test("reserva incompleta mostra '—' no resultado e aponta a primeira reserva sem total cobrado", () => {
  const completa: ReservaValores = { valorTotal: 1000, valorComissao: 100, ravOperadora: 0, valorCliente: 1000, taxaServico: 0, ravClienteModo: "retido_agencia" };
  const semVenda: ReservaValores = { ...completa, valorCliente: null };
  render(<TripSummary reservas={[completa, semVenda]} repasseValor={0} despesas={0} />);
  expect(screen.getByText("Preencha o total cobrado da Reserva 2")).toBeInTheDocument();
  expect(screen.getByTestId("resultado-viagem")).toHaveTextContent("—");
});

test("sem detalheReserva mostra a dica para abrir uma reserva", () => {
  render(<TripSummary reservas={[]} repasseValor={0} despesas={0} />);
  expect(screen.getByText("Abra uma reserva para ver o cálculo")).toBeInTheDocument();
});

test("renderiza detalheReserva e rodape quando passados", () => {
  render(<TripSummary reservas={[]} repasseValor={0} despesas={0} detalheReserva={<p>Reserva 1 · CVC</p>} rodape={<p>atalhos</p>} />);
  expect(screen.getByText("Reserva 1 · CVC")).toBeInTheDocument();
  expect(screen.getByText("atalhos")).toBeInTheDocument();
  expect(screen.queryByText("Abra uma reserva para ver o cálculo")).toBeNull();
});

test("é um aside com nome 'Resumo da viagem'", () => {
  render(<TripSummary reservas={[]} repasseValor={0} despesas={0} />);
  expect(screen.getByRole("complementary", { name: "Resumo da viagem" })).toBeInTheDocument();
});
```

- [ ] **Step 2: Rodar e ver falhar**
  Run: `cd frontend && npx vitest run src/components/Viagem/TripSummary.test.tsx`

- [ ] **Step 3: Implementar o componente** (substitui `TripSummaryProps` e `TripSummary`; imports: `type ReactNode` de `react`, remover `Button`):

```tsx
export function TripSummary({ reservas, repasseValor, despesas, mostrarResultado = true, detalheReserva, rodape }: TripSummaryProps) {
  const { vendaTotal, custo, receitaPrevista, comissaoMedia: media, incompleta } = somarReservas(reservas);
  const resultado = arredondar2(receitaPrevista - (repasseValor ?? 0) - despesas);
  const primeiraIncompleta = reservas.findIndex((r) => r.status !== "cancelada" && r.valorCliente === null);
  return (
    <aside aria-label="Resumo da viagem" className={s.painel}>
      <section className={s.painelBloco}>
        <h2 className={s.painelTitulo}>Viagem</h2>
        <dl className={s.kpis}>
          <div className={s.kpi}>
            <dt>Total cobrado</dt>
            <dd><MoneyValue value={vendaTotal} /></dd>
          </div>
          <div className={cx(s.kpi, s.soLargo)}>
            <dt>Custo das reservas</dt>
            <dd><MoneyValue value={custo} /></dd>
          </div>
          <div className={s.kpi}>
            <dt>Receita da agência</dt>
            <dd>
              <MoneyValue value={receitaPrevista} />
              {media !== null && <small className={cx(s.kpiNota, s.soLargo)}>{rotuloComissaoMedia(media)}</small>}
            </dd>
          </div>
          {mostrarResultado && (
            <>
              <div className={cx(s.kpi, s.soLargo)}>
                <dt>Comissão do vendedor</dt>
                <dd><MoneyValue value={repasseValor} /></dd>
              </div>
              <div className={cx(s.kpi, s.soLargo)}>
                <dt>Despesas da viagem</dt>
                <dd><MoneyValue value={despesas} /></dd>
              </div>
              <div className={cx(s.kpi, s.resultado)}>
                <dt>
                  Resultado da viagem{" "}
                  <Tooltip text="Receita da agência − comissão do vendedor − despesas vinculadas">
                    <CircleHelp size={16} aria-hidden />
                  </Tooltip>
                </dt>
                <dd data-testid="resultado-viagem">
                  <MoneyValue value={incompleta ? null : resultado} emphasis="result" />
                </dd>
              </div>
              {incompleta && primeiraIncompleta >= 0 && (
                <p className={cx(s.kpiNota, s.soLargo)}>Preencha o total cobrado da Reserva {primeiraIncompleta + 1}</p>
              )}
            </>
          )}
        </dl>
      </section>
      <section className={cx(s.painelBloco, s.soLargo)}>
        {detalheReserva ?? <p className={s.kpiNota}>Abra uma reserva para ver o cálculo</p>}
      </section>
      {rodape && <div className={cx(s.painelRodape, s.soLargo)}>{rodape}</div>}
    </aside>
  );
}
```

  Import `cx` de `@/lib/cx`. O teste "rótulos da faixa do formulário" (l.162) continua válido (os rótulos existem no DOM; `.soLargo` só esconde por CSS). O teste "reserva cancelada fica fora…" espera 2× "R$ 520,00" (receita + resultado) — continua.

- [ ] **Step 4: CSS** — substituir o bloco `/* TripSummary */` (`.summaryStrip` … media 1366) por:

```css
/* TripSummary — painel da viagem (≥1280 lateral sticky; <1280 barra sticky no rodapé) */
.painel {
  position: sticky;
  top: calc(var(--topbar-h) + var(--space-4));
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  padding: var(--space-4);
  background: var(--color-bg-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
}
.painelBloco {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}
.painelBloco + .painelBloco {
  padding-top: var(--space-4);
  border-top: 1px solid var(--color-border);
}
.painelTitulo {
  font: var(--type-caption);
  letter-spacing: var(--tracking-caps);
  text-transform: uppercase;
  color: var(--color-text-muted);
}
.kpis {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  margin: 0;
}
.kpi {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  gap: var(--space-3);
}
.kpi dt {
  font: var(--type-body);
  color: var(--color-text-secondary);
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
}
.kpi dd {
  margin: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  font: var(--type-label);
  font-variant-numeric: tabular-nums;
}
.kpiNota {
  font: var(--type-helper);
  color: var(--color-text-muted);
}
.resultado {
  padding-top: var(--space-3);
  border-top: 1px solid var(--color-border);
}
.resultado dd {
  font: var(--type-section);
}
.painelRodape {
  padding-top: var(--space-3);
  border-top: 1px solid var(--color-border);
  font: var(--type-helper);
  color: var(--color-text-muted);
}
@media (max-width: 1279px) {
  .painel {
    top: auto;
    bottom: 0;
    flex-direction: row;
    align-items: center;
    padding: var(--space-3) var(--space-4);
    border-radius: 0;
    border-width: 1px 0 0;
    z-index: 5;
  }
  .painelBloco {
    flex: 1;
  }
  .painelTitulo,
  .soLargo {
    display: none;
  }
  .kpis {
    flex-direction: row;
    justify-content: flex-end;
    gap: var(--space-8);
  }
  .kpi {
    flex-direction: column;
    align-items: flex-end;
    gap: 0;
  }
  .resultado {
    padding-top: 0;
    border-top: 0;
  }
}
```

  Manter `.extra` se `FaixaResumo` ainda usar (grep `s.extra` antes de remover). `.summaryStrip`, `.item`, `.sep` são usados por `FaixaResumo.tsx` — **grep antes**: se `FaixaResumo` importa `Viagem.module.css` e usa essas classes, não remover essas três classes (só `.addReserva` e sua media).

- [ ] **Step 5: tokens.css** — na seção COMPONENTES, depois de `--content-max`:

```css
  --painel-viagem-w:    340px;  /* painel lateral do formulário de viagem ≥1440 */
  --painel-viagem-w-xl: 300px;  /* 1280–1439 */
```

- [ ] **Step 6: StyleguidePage** — remover a prop `onAdicionarReserva` do `<TripSummary …>` (~l.292).

- [ ] **Step 7: Rodar testes + typecheck + lint**
  Run: `cd frontend && npx vitest run src/components/Viagem src/pages/styleguide && npm run typecheck && npm run lint`
  Expected: PASS. (`NovaViagemPage.tsx` ainda passa `onAdicionarReserva` → typecheck falha **só** ali; aceitável, T6 corrige. Reportar isso.)

- [ ] **Step 8: Reportar arquivos. Não commitar.** Commit do controlador (junto de T6 se o typecheck estiver vermelho no meio): `feat(viagem): trip summary becomes a sticky side panel`.

---

### Task 5: Bloco "Viagem" compacto + chip de passageiro em linha

**Depends-on:** T4 (arquivo `Viagem.module.css`)

**Files:**
- Modify: `frontend/src/pages/viagens/DadosViagemSection.tsx`
- Modify: `frontend/src/components/Viagem/PassageirosField.tsx` (chip)
- Modify: `frontend/src/components/Viagem/Viagem.module.css` (seção PassageirosField)
- Modify: `frontend/src/pages/viagens/NovaViagem.module.css` (classes do bloco; **só** acrescentar — T6 reescreve o resto)
- Create: `frontend/src/lib/noites.ts`, `frontend/src/lib/noites.test.ts`

**Interfaces:**
- Produces: `export function noites(ida: string, volta: string): number | null` (datas `yyyy-mm-dd`; `null` se alguma vazia/inválida ou volta < ida).
- `DadosViagemSection` props **inalteradas**. Ida e Volta com `required`.

- [ ] **Step 1: Teste do helper** — `src/lib/noites.test.ts`:

```ts
import { noites } from "./noites";

test("conta noites entre ida e volta", () => {
  expect(noites("2026-10-13", "2026-10-25")).toBe(12);
  expect(noites("2026-10-13", "2026-10-13")).toBe(0);
});

test("null com data vazia ou volta antes da ida", () => {
  expect(noites("", "2026-10-25")).toBeNull();
  expect(noites("2026-10-25", "2026-10-13")).toBeNull();
});

test("atravessa horário de verão sem erro de arredondamento", () => {
  expect(noites("2026-02-20", "2026-02-23")).toBe(3);
});
```

- [ ] **Step 2: Rodar e ver falhar** — `cd frontend && npx vitest run src/lib/noites.test.ts`

- [ ] **Step 3: Implementar** — `src/lib/noites.ts`:

```ts
/** Noites entre duas datas yyyy-mm-dd (UTC puro: sem fuso nem horário de verão). */
export function noites(ida: string, volta: string): number | null {
  if (!ida || !volta) return null;
  const a = Date.parse(`${ida}T00:00:00Z`);
  const b = Date.parse(`${volta}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b) || b < a) return null;
  return Math.round((b - a) / 86_400_000);
}
```

- [ ] **Step 4: Teste de componente** — acrescentar em `frontend/src/pages/viagens/NovaViagemPage.test.tsx`? **Não** (é de T6). Criar `frontend/src/pages/viagens/DadosViagemSection.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import { renderHook } from "@testing-library/react";
import { useForm } from "react-hook-form";
import { DadosViagemSection } from "./DadosViagemSection";
import type { ViagemForm } from "./useNovaViagem";

function montar(valores: Partial<ViagemForm>, erros: Record<string, string> = {}) {
  const { result } = renderHook(() =>
    useForm<ViagemForm>({
      defaultValues: {
        destino: "", tipo: "internacional", dataIda: "", dataVolta: "", vendedorId: "", agenteId: "",
        ocasiao: "", observacoes: "", passageiros: [], repasseValor: null, repassePercentual: null, reservas: [],
        ...valores,
      },
    }),
  );
  render(
    <DadosViagemSection
      form={result.current}
      vendedores={[]}
      mostrarRepasse={false}
      repasseSugerido={null}
      repasseValorMostrado={null}
      onRepassePercentual={() => undefined}
      onRepasseValor={() => undefined}
      erros={erros}
      buscarClientes={() => Promise.resolve([])}
      onNovaPessoa={() => undefined}
    />,
  );
}

test("Ida e Volta são obrigatórias", () => {
  montar({});
  expect(screen.getByLabelText(/^Ida/)).toBeRequired();
  expect(screen.getByLabelText(/^Volta/)).toBeRequired();
});

test("mostra noites calculadas como texto quando as duas datas existem", () => {
  montar({ dataIda: "2026-10-13", dataVolta: "2026-10-25" });
  expect(screen.getByText("12 noites")).toBeInTheDocument();
});

test("erros de data aparecem nos campos", () => {
  montar({}, { dataIda: "Informe a data de ida", dataVolta: "Informe a data de volta" });
  expect(screen.getByLabelText(/^Ida/)).toHaveAccessibleDescription("Informe a data de ida");
  expect(screen.getByLabelText(/^Volta/)).toHaveAccessibleDescription("Informe a data de volta");
});
```

  Verificar como `Field required` expõe obrigatório: se só desenha asterisco sem `required`/`aria-required` no input, trocar `toBeRequired()` por `toHaveAttribute("aria-required", "true")` conforme `Field.tsx`/`Input.tsx`; se nenhum dos dois existir, passar `required` direto no `DateInput`.

- [ ] **Step 5: Implementar `DadosViagemSection`** — trocar o JSX do retorno:

```tsx
  const dataIda = form.watch("dataIda");
  const dataVolta = form.watch("dataVolta");
  const qtdNoites = noites(dataIda, dataVolta);
  return (
    <div className={s.bloco}>
      <h2 className={s.blocoTitulo}>Viagem</h2>
      <div className="grid-form">
        <div className="span-7">
          <PassageirosField
            value={passageiros}
            onChange={(v) => { form.setValue("passageiros", v, { shouldDirty: true }); }}
            buscar={buscarClientes}
            onNovaPessoa={onNovaPessoa}
            erro={erros.passageiros}
            dataIda={dataIda}
          />
        </div>
        <Field label="Destino" required className="span-5" error={erros.destino}>
          <Input autoComplete="off" maxLength={120} {...form.register("destino")} />
        </Field>
        <Field label="Tipo" className="span-2">
          <Select options={TIPOS} {...form.register("tipo")} />
        </Field>
        <Field label="Ida" required className="span-2" error={erros.dataIda}>
          <DateInput {...form.register("dataIda")} />
        </Field>
        <Field
          label="Volta"
          required
          className="span-3"
          error={erros.dataVolta}
          helper={qtdNoites === null ? undefined : `${qtdNoites} ${qtdNoites === 1 ? "noite" : "noites"}`}
        >
          <DateInput {...form.register("dataVolta")} />
        </Field>
        <Field label="Vendedor" required className="span-5" error={erros.vendedorId}>
          <Select options={vendedores.map((v) => ({ value: v.id, label: v.nome }))} placeholder="Selecione" {...form.register("vendedorId")} />
        </Field>
        {mostrarRepasse && (
          /* campos % e R$ atuais, com className "span-3" cada — conteúdo idêntico ao de hoje */
        )}
        <details className={s.mais}>
          <summary>Ocasião e observações</summary>
          {/* conteúdo idêntico ao de hoje */}
        </details>
      </div>
    </div>
  );
```

  Os dois blocos marcados como "idêntico ao de hoje" são o JSX atual de `DadosViagemSection.tsx` l.114-147 (repasse, trocando `span-2` → `span-3`) e l.150-157 (ocasião/observações) — copiar sem mudar lógica. Import `noites` de `@/lib/noites`. Se o helper do `Field` competir com `error`, o `Field` já prioriza erro (confirmar em `Field.tsx`).
  Se o teste "noites como texto" pedir `getByText("12 noites")` e o helper estiver no `aria-describedby`, está ok (texto visível).

- [ ] **Step 6: CSS em `NovaViagem.module.css`** — acrescentar (sem remover nada):

```css
.bloco {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding: var(--space-4);
  background: var(--color-bg-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
}
.blocoTitulo {
  font: var(--type-caption);
  letter-spacing: var(--tracking-caps);
  text-transform: uppercase;
  color: var(--color-text-muted);
}
```

- [ ] **Step 7: Chip de passageiro em linha** — em `PassageirosField.tsx`, dentro do `<li>`:

```tsx
                  <span className={s.passTexto}>
                    <span className={s.passNome}>{p.nome}</span>
                    {meta && <span className={s.chipMeta}>{meta}</span>}
                  </span>
                  {p.titular && <Badge tone="neutral">Titular</Badge>}
```

  Import `Badge` de `@/components/display` (confirmar caminho no barrel). Em `Viagem.module.css`:
  - `.passTexto`: `flex-direction: row; align-items: baseline; gap: var(--space-2);` (remover `flex-direction: column`).
  - `.avatar`: `width: 24px; height: 24px;`.
  - `.buscaWrap`: `max-width: none;`.
  O texto do meta continua exatamente `CPF · nasc. dd/mm/aaaa · N anos` (teste existente em `NovaViagemPage.test.tsx` l.345 depende dele).

- [ ] **Step 8: Rodar testes + typecheck + lint**
  Run: `cd frontend && npx vitest run src/lib/noites.test.ts src/pages/viagens/DadosViagemSection.test.tsx src/components/Viagem && npm run lint`
  Expected: PASS.

- [ ] **Step 9: Reportar arquivos. Não commitar.** Commit do controlador: `feat(viagens): compact trip block with required dates, nights and inline passenger chips`.

---

### Task 6: `NovaViagemPage` — área de trabalho, cabeçalho fixo, painel, estados

**Depends-on:** T2, T3, T4, T5

**Files:**
- Modify: `frontend/src/pages/viagens/NovaViagemPage.tsx`
- Modify: `frontend/src/pages/viagens/NovaViagem.module.css` (remover `.rodape`/`.rodape kbd`; manter `.mais`, `.textarea`, `.bloco*`)
- Modify: `frontend/src/pages/viagens/NovaViagemPage.test.tsx`

**Interfaces:**
- Consumes: `v.totalErros`, `v.erros.reservas` (T2); `ReservationCard` (T3); `TripSummary({ reservas, repasseValor, despesas, mostrarResultado, detalheReserva, rodape })` (T4); `DadosViagemSection` (T5); `ResultSummary` de `@/components/reserva` (barrel — confirmar export).

- [ ] **Step 1: Atualizar testes** em `NovaViagemPage.test.tsx`:
  - Teste l.94: trocar `getByRole("heading", { name: "Dados da viagem" })` por `getByRole("heading", { name: "Viagem" })` e manter o botão "+ Adicionar reserva".
  - `viagemEdicao()`: `dataIda: "2026-04-18"`, `dataVolta: "2026-04-28"`, e `reservas: [reservaDtoValida]` com o mesmo shape de `viagemDto` em `useNovaViagem.harness.ts` (id `r1`, fornecedor `f1`, `valorTotal: 3000`, `valorCliente: 3200`). Isso mantém o teste ALT-13 (Fechar após salvar) chegando ao PUT.
  - Novos:

```tsx
test("sem reservas mostra estado vazio com a ação de adicionar", async () => {
  montar();
  await screen.findByRole("heading", { name: /Nova viagem/ });
  expect(screen.getByText(/Nenhuma reserva ainda/)).toBeInTheDocument();
});

test("salvar incompleto mostra 'N campos precisam de atenção' e o erro de reserva no estado vazio", async () => {
  montar();
  await screen.findByRole("heading", { name: /Nova viagem/ });
  fireEvent.click(screen.getByRole("button", { name: "Salvar viagem" }));
  expect(await screen.findByRole("button", { name: /campos precisam de atenção/ })).toBeInTheDocument();
  expect(screen.getByText("Adicione ao menos uma reserva")).toBeInTheDocument();
  expect(urls.some((u) => u.startsWith("POST"))).toBe(false);
});

test("clicar no aviso de atenção leva o foco ao primeiro campo inválido", async () => {
  montar();
  await screen.findByRole("heading", { name: /Nova viagem/ });
  fireEvent.click(screen.getByRole("button", { name: "Salvar viagem" }));
  fireEvent.click(await screen.findByRole("button", { name: /campos precisam de atenção/ }));
  expect(document.activeElement).toHaveAttribute("aria-invalid", "true");
});

test("painel da viagem é o único lugar com o resumo e o botão de adicionar fica fora dele", async () => {
  montar();
  await screen.findByRole("heading", { name: /Nova viagem/ });
  const painel = screen.getByRole("complementary", { name: "Resumo da viagem" });
  expect(within(painel).queryByRole("button", { name: "+ Adicionar reserva" })).toBeNull();
});
```

  - Teste "rótulo 'Comissão do vendedor' no resumo" (l.248) continua válido.

- [ ] **Step 2: Rodar e ver falhar** — `cd frontend && npx vitest run src/pages/viagens/NovaViagemPage.test.tsx`

- [ ] **Step 3: Implementar a página** — manter hooks, atalhos e modais atuais (l.17-54, l.185-213); trocar o bloco de render (l.56-183):

```tsx
  const abertaReserva = abertaIndice >= 0 ? reservas[abertaIndice] : undefined;
  const fornecedorAberta = v.fornecedores.find((f) => f.id === abertaReserva?.fornecedorId);

  function focarPrimeiroErro() {
    const alvo =
      document.querySelector<HTMLElement>('[aria-invalid="true"]') ??
      document.getElementById(idErroReservas);
    alvo?.focus();
  }

  if (v.carregando) {
    return (
      <Page>
        <div className={s.area}>
          <div className={s.principal}>
            <Skeleton lines={2} />
            <Skeleton lines={6} />
            <Skeleton lines={4} />
          </div>
          <Skeleton lines={8} />
        </div>
      </Page>
    );
  }

  return (
    <Page dirty={dirty} titulo={v.viagem?.codigo ?? "Nova viagem"} onSalvarESair={v.salvar}>
      <div className={s.topo}>
        <nav aria-label="Trilha" className={s.trilha}>
          <Link to="/viagens">Viagens</Link>
          {v.viagem && (
            <>
              <span aria-hidden>/</span>
              <Link to={`/viagens/${v.viagem.id}`}>{v.viagem.codigo}</Link>
            </>
          )}
        </nav>
        <PageHeader
          title={titulo}
          subtitle={partes.length > 0 ? partes.join(" · ") : undefined}
          meta={v.viagem ? <Badge tone="neutral">{v.viagem.codigo}</Badge> : undefined}
          status={<StatusBadge entidade="fase_viagem" valor={v.viagem?.faseOperacional ?? "sem_reserva"} />}
          dirty={dirty}
          salvoEm={v.salvamento.salvoEm}
          actions={
            <>
              {v.totalErros > 0 && (
                <Button variant="tertiary" size="sm" className={s.atencao} onClick={focarPrimeiroErro}>
                  {v.totalErros === 1 ? "1 campo precisa de atenção" : `${v.totalErros} campos precisam de atenção`}
                </Button>
              )}
              <Button variant="tertiary" onClick={v.fechar}>Fechar</Button>
              <Tooltip text="Ctrl+S">
                <Button variant="business" loading={v.salvamento.estado === "saving"} onClick={() => { void v.salvar(); }}>
                  Salvar viagem
                </Button>
              </Tooltip>
            </>
          }
        />
        {v.conflito && ( /* Alert de conflito atual, l.91-109, sem mudança */ )}
        {v.erroBloco !== null && <Alert tone="danger">{v.erroBloco}</Alert>}
      </div>

      {!id && semelhante && titular && ( /* AvisoViagemSemelhante atual, l.113-125, sem mudança */ )}

      <div className={s.area}>
        <div className={s.principal}>
          <DadosViagemSection /* props atuais, l.128-141, sem mudança */ />

          <section aria-labelledby={idTituloReservas} className={s.reservas}>
            <header className={s.reservasTopo}>
              <h2 id={idTituloReservas} className={s.blocoTitulo}>
                Reservas{reservas.length > 0 && ` · ${reservas.length}`}
              </h2>
            </header>
            {reservas.length === 0 ? (
              <p
                id={idErroReservas}
                tabIndex={-1}
                className={cx(s.vazio, v.erros.reservas && s.vazioErro)}
                aria-invalid={v.erros.reservas ? true : undefined}
              >
                {v.erros.reservas ?? "Nenhuma reserva ainda."}{" "}
                Toda viagem precisa de ao menos uma reserva: fornecedor, localizador e valores.
              </p>
            ) : (
              <div className={s.lista}>
                {reservas.map((r, i) => ( /* ReservationCard atual, l.144-168, sem mudança */ ))}
              </div>
            )}
            <div className={s.adicionar}>
              <Button variant="secondary" onClick={v.adicionarReserva}>+ Adicionar reserva</Button>
              <span className={s.dica}><kbd>Ctrl</kbd>+<kbd>Enter</kbd></span>
            </div>
          </section>
        </div>

        <TripSummary
          reservas={reservas}
          repasseValor={v.repasseValorMostrado}
          despesas={v.viagem?.resumo?.despesasViagem ?? 0}
          mostrarResultado={verResultado}
          detalheReserva={
            abertaReserva && (
              <>
                <h2 className={s.blocoTitulo}>
                  Reserva {abertaIndice + 1}{fornecedorAberta ? ` · ${fornecedorAberta.nome}` : ""}
                </h2>
                <ResultSummary value={abertaReserva} />
              </>
            )
          }
          rodape={
            <ul className={s.atalhos}>
              <li><kbd>Ctrl</kbd>+<kbd>S</kbd> salvar</li>
              <li><kbd>Ctrl</kbd>+<kbd>Enter</kbd> adicionar reserva</li>
              <li><kbd>Esc</kbd> recolher</li>
              <li><kbd>Ctrl</kbd>+<kbd>K</kbd> buscar</li>
            </ul>
          }
        />
      </div>
      {/* PessoaInlineModal e FornecedorInlineModal atuais, sem mudança */}
    </Page>
  );
```

  Notas de implementação:
  - `idTituloReservas = useId()` e `idErroReservas = useId()` no topo do componente (antes do `if (v.carregando)` — hooks não podem ficar depois de return condicional).
  - Imports: `Link` de `react-router`; `useId` de `react`; `Tooltip` de `@/components/display`; `ResultSummary` de `@/components/reserva`; `cx` de `@/lib/cx`; remover `Section` se sem uso.
  - O texto do estado vazio com erro deve conter **exatamente** "Adicione ao menos uma reserva" como nó próprio para `getByText` (se o `getByText` exato falhar por causa do texto concatenado, envolver `v.erros.reservas` em `<strong>`).
  - Se `Tooltip` envolvendo o `Button` alterar o nome acessível de "Salvar viagem", usar `title="Ctrl+S"` no botão em vez de `Tooltip`.
  - `aria-invalid` num `<p>` é inválido para jsx-a11y: se o lint reclamar, remover `aria-invalid` do `<p>` e manter o fallback por `getElementById` em `focarPrimeiroErro` (o teste de foco usa o primeiro input inválido, que existe — Ida/Volta).

- [ ] **Step 4: CSS da página** — `NovaViagem.module.css`: remover `.rodape` e `.rodape kbd`; acrescentar:

```css
.topo {
  position: sticky;
  top: var(--topbar-h);
  z-index: 6;
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  padding-block: var(--space-3);
  background: var(--color-bg-page);
  border-bottom: 1px solid var(--color-border);
}
.trilha {
  display: flex;
  gap: var(--space-2);
  font: var(--type-helper);
  color: var(--color-text-muted);
}
.trilha a {
  color: var(--color-text-link);
}
.atencao {
  color: var(--color-danger-text);
}
.area {
  display: grid;
  grid-template-columns: minmax(0, 1fr) var(--painel-viagem-w);
  align-items: start;
  gap: var(--space-6);
}
.principal {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  min-width: 0;
}
.reservas {
  background: var(--color-bg-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  overflow: hidden;
}
.reservasTopo {
  padding: var(--space-3) var(--space-4);
  border-bottom: 1px solid var(--color-border);
}
.vazio {
  padding: var(--space-6) var(--space-4);
  font: var(--type-body);
  color: var(--color-text-secondary);
}
.vazioErro {
  color: var(--color-danger-text);
}
.adicionar {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-3) var(--space-4);
  border-top: 1px solid var(--color-border);
}
.dica,
.atalhos {
  font: var(--type-helper);
  color: var(--color-text-muted);
}
.atalhos {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  margin: 0;
  padding: 0;
  list-style: none;
}
.dica kbd,
.atalhos kbd {
  padding: 0 var(--space-1);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  background: var(--color-bg-subtle);
  font: var(--type-code);
}
@media (max-width: 1439px) {
  .area {
    grid-template-columns: minmax(0, 1fr) var(--painel-viagem-w-xl);
  }
}
@media (max-width: 1279px) {
  .area {
    grid-template-columns: minmax(0, 1fr);
  }
}
```

  `Page` já tem `gap` e `padding`; o `.topo` sticky precisa de fundo opaco (`--color-bg-page`) para o conteúdo não aparecer por baixo. Se `Page` limitar largura em `--content-max: 1400px`, está ok.

- [ ] **Step 5: Rodar testes da página**
  Run: `cd frontend && npx vitest run src/pages/viagens`
  Expected: PASS.

- [ ] **Step 6: Suíte completa + lint + typecheck + build**
  Run: `cd frontend && npm run lint && npm run typecheck && npm run test && npm run build`
  Expected: tudo verde (esperado ~849 + novos).

- [ ] **Step 7: Verificação visual rápida** — com API :5000 e `npx vite --port 5173 --host 127.0.0.1`, abrir `/viagens/nova` e `/viagens/{id}/editar` em 1440 e 1366: cabeçalho gruda ao rolar, painel gruda à direita, abrir reserva mostra "Reserva N · Fornecedor" no painel, expandir não acende "Alterações não salvas". Em 1200: painel vira barra no rodapé com 3 números. Anotar problemas no relatório.

- [ ] **Step 8: Reportar arquivos. Não commitar.** Commit do controlador: `feat(viagens): trip form workspace with sticky header, side panel and empty/attention states`.

---

### Task 7: E2E, contrato de design, docs e verificação final

**Depends-on:** T1, T6

**Files:**
- Modify: `frontend/e2e/nova-viagem.spec.ts`
- Modify: `docs/design-system-contrato.md` (l.7, l.34, l.64)
- Modify: `frontend/src/styles/tokens.css` (comentário de `--color-action-business`, l.41)
- Modify: `regras-e-escopo-v2.md` (seção de viagem)
- Modify: `docs/BACKLOG.md` (seção nova "Redesign viagem — Fase 1 (2026-09-14)")

- [ ] **Step 1: E2E** — em `nova-viagem.spec.ts`, teste "aviso de viagem semelhante…": a primeira viagem precisa de reserva para salvar. Depois de preencher Volta (l.82), antes de `Control+S`:

```ts
  await reserva(page, 1, "CVC", "CNC-0501", "2000", "2000");
```

  O teste de 4 reservas não muda (já preenche ida, volta e reservas). `getByText("R$ 17.600,00")` agora vem do painel — manter.

- [ ] **Step 2: Rodar E2E** (API + seed de E2E conforme `frontend/playwright.config.ts`)
  Run: `cd frontend && npx playwright test e2e/nova-viagem.spec.ts e2e/viagens.spec.ts`
  Expected: PASS; anotar `tempo-4-reservas-s` e comparar com 6,2 s @1280 / 7,7 s @1440 (se o config roda um viewport só, rodar também com `--project` correspondente ou ajustar viewport via env conforme o config). Regressão > 10 % = investigar antes de seguir.

- [ ] **Step 3: Contrato de design** — `docs/design-system-contrato.md`:
  - l.7: `laranja = ação de negócio (uma por tela)` → `laranja = ação principal da tela (uma por tela)`.
  - l.34: substituir a frase de `business` por: "`business` só para a **ação principal** da tela — a que conclui o trabalho naquele contexto (ex.: Salvar viagem no formulário de viagem). Uma por tela. Nunca em voltar, abrir, exportar, nem em ações repetidas por item."
  - l.64: substituir a lista por: "lista de viagens → "+ Nova viagem"; Nova viagem / Edição → "Salvar viagem" ("+ Adicionar reserva" é `secondary`); repasses → "Pagar"; conciliação → "Marcar recebidas". Ruling 2026-09-14 (redesign da viagem, design descongelado)."
  - Acrescentar em §4.5 (congelamento) uma linha: "2026-09-14: descongelado pelo dono para o redesign da viagem (Fases 1–3, spec `docs/superpowers/specs/2026-09-14-redesign-viagem-fase1-design.md`)."
- [ ] **Step 4: tokens.css l.41** — comentário vira `/* Button business: ação principal, UMA por tela (Salvar viagem, Nova viagem) */`.
- [ ] **Step 5: `regras-e-escopo-v2.md`** — na seção de lançamento/edição de viagem, acrescentar: "**Viagem só salva completa (ruling 2026-09-14):** salvar (criar ou editar) exige data de ida, data de volta e ao menos uma reserva de qualquer status (cancelada conta). Não se aplica a operações de reserva, adicionar reserva pelo detalhe, cancelar ou transferir viagem. Viagens antigas incompletas só são barradas no próximo salvamento; sem migration."
- [ ] **Step 6: BACKLOG** — seção "Redesign viagem — Fase 1 (2026-09-14)": rulings (design descongelado; laranja = ação principal; viagem só salva completa), bug corrigido (expandir reserva sujava o form), pendências Fase 2/3 (detalhe: `ReservasTab` ainda usa `business` em "+ Adicionar reserva" e "Cancelar viagem…" como `danger` sólido competindo com "Editar"; card "Viagens" solto entre cabeçalho e abas; `FaixaResumo` quebra "Receita recebida").
- [ ] **Step 7: Screenshots de verificação** — Playwright MCP ou script, salvando em `.playwright-mcp/` (ignorado): 1920, 1440, 1366, 1280, 1024 × (nova vazia · nova com erro de validação · edição com 2 reservas e uma aberta · edição com reserva cancelada). Revisar contra a spec §1–§6 e o checklist visual do pedido (hierarquia, excesso de borda/card, números em destaque, ação principal clara). Corrigir o que destoar antes de fechar (volta para T3/T4/T5/T6 conforme o arquivo).
- [ ] **Step 8: Verificação final completa**
  Run: `cd frontend && npm run lint && npm run typecheck && npm run test && npm run build` e `cd backend && dotnet format --verify-no-changes && dotnet build -c Release && dotnet test`
  Expected: tudo verde.
- [ ] **Step 9: Reportar. Não commitar.** Commits do controlador: `frontend` → `test(e2e): trip form requires a reservation`; root → `docs: trip redesign phase 1 rulings, design contract and backlog`.
