# Redesign da viagem — Fase 2 (detalhe) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`). Execução em ondas conforme `.claude/rules/parallel-subagent-driven-development.md`: **implementadores não commitam**; o controlador commita por task. Regras comuns: `.superpowers/sdd/regras-implementador.md`.

**Goal:** Reconstruir o detalhe da viagem com cabeçalho fixo, abas + painel lateral fixo (sem aba Resumo) e reservas em lista densa, corrigindo a regressão do `ReservaDetalheCard`.

**Architecture:** `ViagemPage` vira grid (conteúdo com abas + `PainelViagem` sticky). `PainelViagem` absorve a faixa, passageiros e próximas pendências do antigo `ResumoTab`. `ReservaDetalheCard` passa a usar as classes de linha densa de `Reserva.module.css` e agrupa ações em `MenuAcoes`. `CabecalhoViagem` ganha trilha e menu "Mais ações"; o sticky fica na página.

**Tech Stack:** React + TS, CSS Modules com tokens, TanStack Query, Vitest + Testing Library, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-15-redesign-viagem-fase2-design.md`

## Global Constraints

- Só `frontend/`. Branch `feat/redesign-viagem-f2` (controlador cria de `develop`). Sem push.
- Só tokens (`npm run lint` inclui `lint:tokens`): sem hex, sem `font-size`, `@media` só com 700/1024/1280/1366/1440 (para "abaixo de X": `@media not all and (min-width: X)`).
- `Button`: 5 variantes. **Nesta tela `business` só em "Editar" do cabeçalho.**
- Nomes acessíveis preservados: heading "Titular · Destino"; tabs "Reservas", "Financeiro", "Pendências", "Documentos", "Timeline"; region "Reserva N"; botões "Expandir"/"Recolher", "Marcar emitida"/"Voltar a em emissão", "Editar", "+ Adicionar reserva", "Usar crédito…", "Tentar de novo". Itens de menu (role `menuitem`): "Transferir", "Cancelar viagem…", "Remarcar…", "NFSe…", "Duplicar", "Cancelar reserva…". Botões de menu: "Mais ações" (cabeçalho), "Mais ações da reserva" (cada reserva).
- Permissões inalteradas: `viagem.transferir`, `viagem.editar`, `viagem.ver_resultado` (via `resumo`), `reserva.ver_valores` (`verValores`), `auditoria.ver`, `anexo.enviar`, `viagem.criar`.
- Não mudar: `useOperacao`, modais de `components/ViagemOperacoes`, `ListaServicos`, `ListaPendencias`, `FinanceiroTab` (só import de `Bloco`), `ReservationCard`, `ResultSummary`, `FaixaResumo`, `TripSummary`.
- Commits Conventional Commits em inglês com rodapé:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Ad2nkxMcpVC3pWQeu2yyRA
  ```
- Comandos: `cd frontend && npm run lint && npm run typecheck && npx vitest run && npm run build`; E2E `npx playwright test e2e/viagens.spec.ts e2e/nova-viagem.spec.ts e2e/styleguide.spec.ts` (API :5000 e Vite :5173 já rodando).

## Ondas

| Onda | Tasks | Motivo |
|---|---|---|
| 1 | T1, T2, T3 | arquivos disjuntos |
| 2 | T4 | monta a página com T1–T3 |
| 3 | T5 | E2E + docs sobre tudo |

---

### Task 1: `ReservaDetalheCard` em linha densa (corrige regressão)

**Files:**
- Modify: `frontend/src/components/Reserva/ReservaDetalheCard.tsx`
- Modify: `frontend/src/components/Reserva/ReservaDetalhe.module.css`
- Modify/Create: `frontend/src/components/Reserva/ReservaDetalheCard.test.tsx`
- **Não editar** `Reserva.module.css` (classes compartilhadas com o formulário; só consumir).
**Depends-on:** none

**Interfaces:**
- Props de `ReservaDetalheCard` inalteradas.
- Consome de `Reserva.module.css`: `reserva`, `aberta`, `cancelada`, `linha`, `num`, `quem`, `fornecedor`, `servicos`, `localizador`, `status`, `valores`, `valor`, `receita`, `chevron`, `chevronAberto`, `corpo`, `resultado`, `resultadoReceita`.
- Consome `MenuAcoes` de `@/components/Menu/MenuAcoes` (`{ label, itens: { label, onClick, tone? }[] }`).

- [ ] **Step 1: Testes** (substituir asserções que dependam do layout antigo; manter as de comportamento). Cobrir:

```tsx
test("linha recolhida: region 'Reserva 1', fornecedor, localizador, status e valores só com verValores", () => {
  render(<ReservaDetalheCard {...base({ verValores: true })} />);
  const region = screen.getByRole("region", { name: "Reserva 1" });
  expect(region).toHaveTextContent(RESERVA.fornecedorNome);
  expect(region).toHaveTextContent(/receita R\$/);
  render(<ReservaDetalheCard {...base({ verValores: false, indice: 2 })} />);
  expect(screen.getByRole("region", { name: "Reserva 2" })).not.toHaveTextContent(/receita R\$/);
});

test("aberta: ações visíveis Marcar emitida e Editar; demais no menu 'Mais ações da reserva'", async () => {
  const user = userEvent.setup();
  const onCancelar = vi.fn();
  render(<ReservaDetalheCard {...base({ aberta: true, podeEditar: true, onCancelar, onDuplicar: vi.fn() })} />);
  expect(screen.getByRole("button", { name: "Marcar emitida" })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Editar" })).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Cancelar reserva…" })).toBeNull();
  await user.click(screen.getByRole("button", { name: "Mais ações da reserva" }));
  for (const item of ["Remarcar…", "NFSe…", "Duplicar", "Cancelar reserva…"])
    expect(screen.getByRole("menuitem", { name: item })).toBeInTheDocument();
  await user.click(screen.getByRole("menuitem", { name: "Cancelar reserva…" }));
  expect(onCancelar).toHaveBeenCalledTimes(1);
});

test("cancelada: sem Marcar emitida/Editar; menu só com Duplicar quando onDuplicar", async () => {
  const user = userEvent.setup();
  render(<ReservaDetalheCard {...base({ aberta: true, podeEditar: true, reserva: { ...RESERVA, status: "cancelada" }, onDuplicar: vi.fn() })} />);
  expect(screen.queryByRole("button", { name: "Marcar emitida" })).toBeNull();
  await user.click(screen.getByRole("button", { name: "Mais ações da reserva" }));
  expect(screen.getAllByRole("menuitem").map((i) => i.textContent)).toEqual(["Duplicar"]);
});

test("histórico de alterações só consulta a API ao abrir o details", async () => {
  // fetch stub contando chamadas a /alteracoes: 0 com o card aberto; 1 depois de clicar em "Histórico de alterações"
});

test("resultado em texto só com verValores", () => {
  render(<ReservaDetalheCard {...base({ aberta: true, verValores: true })} />);
  expect(screen.getByLabelText("Resultado desta reserva")).toHaveTextContent("Receita da agência");
});
```

  Use `RESERVA_1` de `src/pages/viagens/detalhe/fixtures.ts` como `RESERVA` e monte `base()` com os props obrigatórios (`indice: 1`, `verValores`, `podeEditar: false`, `aberta: false`, callbacks `vi.fn()`); envolva em `QueryClientProvider` + `MemoryRouter` (o card usa `useQueryClient`/`useParams`). Complete o teste do histórico com `vi.stubGlobal("fetch", …)` contando URLs com `/alteracoes`.

- [ ] **Step 2:** `npx vitest run src/components/Reserva/ReservaDetalheCard.test.tsx` → FAIL.

- [ ] **Step 3: Implementação** — substituir o JSX e o componente `Historico`:

```tsx
function Historico({ reservaId }: { reservaId: string }) {
  const [aberto, setAberto] = useState(false);
  return (
    <details
      className={s.historicoDetalhes}
      onToggle={(e) => {
        setAberto(e.currentTarget.open);
      }}
    >
      <summary>Histórico de alterações</summary>
      {aberto && <HistoricoLista reservaId={reservaId} />}
    </details>
  );
}
// HistoricoLista = conteúdo atual de Historico (useQuery + Skeleton/Alert/lista), sem mudança.
```

```tsx
  const itensMenu: ItemMenu[] = [
    ...(podeEditar && !cancelada
      ? [
          { label: "Remarcar…", onClick: onRemarcar },
          { label: "NFSe…", onClick: onNfse },
        ]
      : []),
    ...(onDuplicar ? [{ label: "Duplicar", onClick: onDuplicar }] : []),
    ...(podeEditar && !cancelada ? [{ label: "Cancelar reserva…", onClick: onCancelar, tone: "danger" as const }] : []),
  ];
  const r0 = deDto(reserva);
  const calc = calcularReserva(paraValoresReserva(r0));

  return (
    <section aria-labelledby={idTitulo} className={cx(r.reserva, aberta && r.aberta, cancelada && r.cancelada)}>
      <header className={r.linha}>
        <span id={idTitulo} className={r.num} aria-label={`Reserva ${indice}`}>
          {indice}
        </span>
        <span className={r.quem}>
          <span className={r.fornecedor}>{reserva.fornecedorNome}</span>
          {servicos && <span className={r.servicos}>{servicos}</span>}
        </span>
        <span className={r.localizador}>{reserva.localizador}</span>
        <span className={r.status}>
          <StatusBadge entidade="reserva" valor={reserva.status} />
        </span>
        <span className={r.valores}>
          {verValores && (
            <>
              <span className={r.valor}>
                <MoneyValue value={reserva.valorCliente ?? null} />
              </span>
              <small className={r.receita}>receita {formatarDinheiro(reserva.receitaPrevista ?? 0)}</small>
            </>
          )}
        </span>
        <Button
          variant="tertiary"
          size="sm"
          aria-expanded={aberta}
          icon={<ChevronDown size={16} className={cx(r.chevron, aberta && r.chevronAberto)} />}
          onClick={onToggle}
        >
          {aberta ? "Recolher" : "Expandir"}
        </Button>
      </header>

      {aberta && (
        <div className={r.corpo}>
          <div className={s.grid}>{/* 5 × <Leitura> atuais, sem mudança */}</div>
          {verValores && (
            <p className={r.resultado} aria-label="Resultado desta reserva">
              <span>RAV <MoneyValue value={calc.ravCliente} /></span>
              <span aria-hidden>·</span>
              <span>Total da comissão <MoneyValue value={calc.totalComissao} /></span>
              <span aria-hidden>·</span>
              <span className={r.resultadoReceita}>
                Receita da agência <MoneyValue value={reserva.receitaPrevista ?? calc.receitaPrevista} emphasis="result" />
              </span>
            </p>
          )}
          {/* bloco de cancelamento atual, sem mudança */}
          <div className={s.secao}>
            <span className={s.rotulo}>Serviços</span>
            <ListaServicos reserva={reserva} podeEditar={podeEditar && !cancelada} />
          </div>
          <Historico reservaId={reserva.id} />
          {/* alertas de conflito/erro do status atuais, sem mudança */}
          {((podeEditar && !cancelada) || itensMenu.length > 0) && (
            <div className={s.acoes}>
              {podeEditar && !cancelada && (
                <>
                  <Button variant="secondary" size="sm" loading={status.salvando} onClick={() => { void mudarStatus(); }}>
                    {emitida ? "Voltar a em emissão" : "Marcar emitida"}
                  </Button>
                  <Button variant="secondary" size="sm" onClick={onEditar}>Editar</Button>
                </>
              )}
              <MenuAcoes label="Mais ações da reserva" itens={itensMenu} />
            </div>
          )}
        </div>
      )}
    </section>
  );
```

  Imports: `ChevronDown` (lucide-react), `cx` (`@/lib/cx`), `calcularReserva` (`@/dominio/calculoReserva`), `paraValoresReserva` e `deDto` (`./tipos`), `MenuAcoes`/`ItemMenu` (`@/components/Menu/MenuAcoes`). Remover import de `ResultSummary` se ficar sem uso. A receita exibida prefere `reserva.receitaPrevista` do servidor (fonte oficial do detalhe).

- [ ] **Step 4: CSS** `ReservaDetalhe.module.css`: `.grid` vira `repeat(5, minmax(0, 1fr))` (≥1280) e `repeat(3, …)` abaixo (`@media not all and (min-width: 1280px)`); `.acoes` vira `justify-content: flex-start; align-items: center` com `border-top` e `padding-top: var(--space-4)`; acrescentar:

```css
.secao {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}
.historicoDetalhes summary {
  font: var(--type-label);
  color: var(--color-text-link);
  cursor: pointer;
}
.historicoDetalhes[open] summary {
  margin-bottom: var(--space-2);
}
```

- [ ] **Step 5:** `npx vitest run src/components/Reserva src/pages/viagens/detalhe/ReservasTab.test.tsx` → PASS (ajuste só asserções de layout em `ReservasTab.test.tsx` que quebrem, ex. botão "Cancelar reserva…" virar menuitem; listar no relatório). `npm run lint && npm run typecheck`.
- [ ] **Step 6:** Reportar. Não commitar. Commit do controlador: `fix(reserva): detail reservation card uses dense row layout and action menu`.

---

### Task 2: `PainelViagem` + `Bloco` em arquivo próprio

**Files:**
- Create: `frontend/src/pages/viagens/detalhe/PainelViagem.tsx`, `PainelViagem.module.css`, `PainelViagem.test.tsx`
- Create: `frontend/src/pages/viagens/detalhe/Bloco.tsx`
- Modify (só a linha de import de `Bloco`/`TOOLTIP_RECEBIDA`): `FinanceiroTab.tsx`, `MovimentosViagem.tsx`, `DespesasViagem.tsx`
- **Não editar** `ResumoTab.tsx`/`ResumoTab.test.tsx` (T4 remove).
**Depends-on:** none

**Interfaces:**
- Produces:

```ts
export function PainelViagem(props: {
  viagem: ViagemDto;
  verValores: boolean;
  pendencias: PendenciaDto[];
  onVerPendencias: () => void;
}): JSX.Element;
```
  Raiz `<aside aria-label="Resumo da viagem" className={s.painel}>`. Classe `s.painel` com `position: sticky; top: calc(var(--topbar-h) + var(--topo-h, 0px) + var(--space-4))`; em `@media not all and (min-width: 1280px)` fica `position: static`.
- `Bloco.tsx` exporta `Bloco` e `TOOLTIP_RECEBIDA` com código idêntico ao de `ResumoTab.tsx` (classes de `./Viagem.module.css`).

- [ ] **Step 1: Testes** — migrar os casos de `ResumoTab.test.tsx` que tratam de faixa, passageiros e "Seu repasse" para `PainelViagem.test.tsx` (mesmas fixtures `./fixtures`), trocando `<ResumoTab …/>` por `<PainelViagem viagem=… verValores=… pendencias={[]} onVerPendencias={noop} />`. Casos obrigatórios:
  1. faixa reduzida sem resumo com `verValores` (tem "Receita da agência", não tem "Resultado da viagem");
  2. faixa completa com "Receita recebida", "Comissão do vendedor", tooltip "Comissões, RAV e taxas que já entraram" (`role="tooltip"`);
  3. ordem dos rótulos: Total cobrado, Custo das reservas, Receita da agência, Comissão do vendedor, Despesas da viagem, Resultado da viagem, Receita recebida; "comissão média N %";
  4. U06: sem `verValores` e sem resumo, sem "Receita da agência";
  5. passageiro: "111.444.777-35 · nasc. 05/05/1980" / só "nasc." / sem linha; badge "Titular";
  6. P02 "Seu repasse" com "R$ 300,00" e "Bloqueado";
  7. pendências: mostra só as 2 abertas mais próximas por `dataPrevista`, "Nenhuma pendência aberta nesta viagem." quando vazio, botão "Ver todas" chama `onVerPendencias`;
  8. `getByRole("complementary", { name: "Resumo da viagem" })`.
  Não migrar os testes do bloco "Reservas · clique para abrir" (bloco deixa de existir).

- [ ] **Step 2:** `npx vitest run src/pages/viagens/detalhe/PainelViagem.test.tsx` → FAIL.

- [ ] **Step 3: Implementação** `PainelViagem.tsx`:

```tsx
import type { PendenciaDto } from "@/api/pendencias";
import type { ReservaDto, ViagemDto } from "@/api/viagens";
import { Button, MoneyValue } from "@/components";
import { Badge, StatusBadge, Tooltip } from "@/components/display";
import { comissaoMedia, rotuloComissaoMedia } from "@/components/viagem";
import { formatarData } from "@/lib/datas";
import { formatarCpf } from "@/lib/documentos";
import { CircleHelp } from "lucide-react";
import type { ReactNode } from "react";
import { TOOLTIP_RECEBIDA } from "./Bloco";
import s from "./PainelViagem.module.css";

const TOOLTIP_RESULTADO = "Receita da agência − comissão do vendedor − despesas vinculadas";

function Kpi({ rotulo, tooltip, valor, nota, destaque }: { rotulo: string; tooltip?: string; valor: number | null; nota?: ReactNode; destaque?: boolean }) {
  return (
    <div className={destaque ? `${s.kpi} ${s.destaque}` : s.kpi}>
      <dt>
        {rotulo}
        {tooltip && (
          <Tooltip text={tooltip}>
            <CircleHelp size={16} aria-hidden />
          </Tooltip>
        )}
      </dt>
      <dd>
        <MoneyValue value={valor} emphasis={destaque ? "result" : undefined} />
        {nota}
      </dd>
    </div>
  );
}

function BlocoViagem({ viagem, verValores }: { viagem: ViagemDto; verValores: boolean }) {
  const r = viagem.resumo;
  if (r) {
    const media = comissaoMedia(viagem.reservas);
    return (
      <dl className={s.kpis}>
        <Kpi rotulo="Total cobrado" valor={r.vendaTotal} />
        <Kpi rotulo="Custo das reservas" valor={r.custoFornecedores} />
        <Kpi rotulo="Receita da agência" valor={r.receitaPrevista} nota={media === null ? undefined : <small className={s.nota}>{rotuloComissaoMedia(media)}</small>} />
        <Kpi rotulo="Comissão do vendedor" valor={r.repasseValor} nota={r.repasseStatus ? <StatusBadge entidade="repasse" valor={r.repasseStatus} /> : undefined} />
        <Kpi rotulo="Despesas da viagem" valor={r.despesasViagem} />
        <Kpi rotulo="Resultado da viagem" tooltip={TOOLTIP_RESULTADO} valor={r.resultado} destaque />
        <Kpi rotulo="Receita recebida" tooltip={TOOLTIP_RECEBIDA} valor={r.receitaRecebida} />
      </dl>
    );
  }
  if (verValores) {
    const ativas = viagem.reservas.filter((x) => x.status !== "cancelada");
    const soma = (campo: (res: ReservaDto) => number | undefined) => ativas.reduce((t, res) => t + (campo(res) ?? 0), 0);
    return (
      <dl className={s.kpis}>
        <Kpi rotulo="Total cobrado" valor={soma((res) => res.valorCliente)} />
        <Kpi rotulo="Custo das reservas" valor={soma((res) => res.valorTotal)} />
        <Kpi rotulo="Receita da agência" valor={soma((res) => res.receitaPrevista)} destaque />
      </dl>
    );
  }
  if (viagem.repasse) {
    return (
      <dl className={s.kpis}>
        <Kpi rotulo="Seu repasse" valor={viagem.repasse.valor} nota={<StatusBadge entidade="repasse" valor={viagem.repasse.status} />} />
      </dl>
    );
  }
  return null;
}

export function PainelViagem({ viagem, verValores, pendencias, onVerPendencias }: { viagem: ViagemDto; verValores: boolean; pendencias: PendenciaDto[]; onVerPendencias: () => void }) {
  const proximas = pendencias
    .filter((p) => p.status === "aberta")
    .sort((a, b) => a.dataPrevista.localeCompare(b.dataPrevista))
    .slice(0, 2);
  const temNumeros = Boolean(viagem.resumo) || verValores || Boolean(viagem.repasse);
  return (
    <aside aria-label="Resumo da viagem" className={s.painel}>
      {temNumeros && (
        <section className={s.bloco}>
          <h2 className={s.titulo}>Viagem</h2>
          <BlocoViagem viagem={viagem} verValores={verValores} />
        </section>
      )}
      <section className={s.bloco}>
        <h2 className={s.titulo}>Passageiros · {viagem.passageiros.length}</h2>
        <ul className={s.lista}>
          {viagem.passageiros.map((p) => {
            const meta = [p.cpf && formatarCpf(p.cpf), p.dataNascimento && `nasc. ${formatarData(p.dataNascimento)}`].filter(Boolean).join(" · ");
            return (
              <li key={p.clienteId} className={s.item}>
                <span className={s.itemTexto}>
                  <span className={s.itemTitulo}>{p.nome}</span>
                  {meta && <span className={s.itemMeta}>{meta}</span>}
                </span>
                {p.titular && <Badge tone="neutral">Titular</Badge>}
              </li>
            );
          })}
        </ul>
      </section>
      <section className={s.bloco}>
        <h2 className={s.titulo}>Próximas pendências</h2>
        {proximas.length === 0 ? (
          <p className={s.nota}>Nenhuma pendência aberta nesta viagem.</p>
        ) : (
          <ul className={s.lista}>
            {proximas.map((p) => (
              <li key={p.id} className={s.item}>
                <span className={s.itemTexto}>
                  <span className={s.itemTitulo}>{p.clienteNome ? `${p.titulo} — ${p.clienteNome}` : p.titulo}</span>
                  <span className={s.itemMeta}>
                    até {formatarData(p.dataPrevista)} · {p.origem === "automatica" ? "automática" : "manual"}
                    {p.responsavelNome ? ` · ${p.responsavelNome}` : ""}
                  </span>
                </span>
                {p.prioridade === "urgente" && <StatusBadge entidade="prioridade" valor="urgente" />}
              </li>
            ))}
          </ul>
        )}
        <Button variant="tertiary" size="sm" onClick={onVerPendencias}>
          Ver todas
        </Button>
      </section>
    </aside>
  );
}
```

  Ajuste caminhos de import (`Tooltip`, `rotuloComissaoMedia`, `comissaoMedia`) conforme os barrels existentes (ver imports atuais de `ResumoTab.tsx` e `TripSummary.tsx`).

- [ ] **Step 4: CSS** `PainelViagem.module.css` (espelha o painel da Fase 1 em `components/Viagem/Viagem.module.css`):

```css
.painel {
  position: sticky;
  top: calc(var(--topbar-h) + var(--topo-h, 0px) + var(--space-4));
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  padding: var(--space-4);
  background: var(--color-bg-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
}
.bloco {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}
.bloco + .bloco {
  padding-top: var(--space-4);
  border-top: 1px solid var(--color-border);
}
.titulo {
  margin: 0;
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
  display: inline-flex;
  align-items: center;
  gap: var(--space-1);
  font: var(--type-body);
  color: var(--color-text-secondary);
}
.kpi dd {
  margin: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: var(--space-1);
  font: var(--type-label);
  font-variant-numeric: tabular-nums;
}
.destaque {
  padding-block: var(--space-3);
  border-block: 1px solid var(--color-border);
}
.destaque dd {
  font: var(--type-section);
}
.nota {
  margin: 0;
  font: var(--type-helper);
  color: var(--color-text-muted);
}
.lista {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  margin: 0;
  padding: 0;
  list-style: none;
}
.item {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-2);
}
.itemTexto {
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.itemTitulo {
  font: var(--type-label);
  color: var(--color-text-primary);
  overflow-wrap: anywhere;
}
.itemMeta {
  font: var(--type-helper);
  color: var(--color-text-secondary);
  font-variant-numeric: tabular-nums;
}
@media not all and (min-width: 1280px) {
  .painel {
    position: static;
  }
}
```

- [ ] **Step 5: `Bloco.tsx`** — copiar `Bloco` e `TOOLTIP_RECEBIDA` de `ResumoTab.tsx` (idênticos) e trocar os imports em `FinanceiroTab.tsx`, `MovimentosViagem.tsx`, `DespesasViagem.tsx` para `./Bloco`.
- [ ] **Step 6:** `npx vitest run src/pages/viagens/detalhe` (ResumoTab.test continua verde, pois ResumoTab ainda existe) · `npm run lint && npm run typecheck`.
- [ ] **Step 7:** Reportar. Não commitar. Commit do controlador: `feat(viagem): trip detail side panel with figures, passengers and next pending items`.

---

### Task 3: `CabecalhoViagem` com trilha e menu "Mais ações"

**Files:**
- Modify: `frontend/src/pages/viagens/detalhe/CabecalhoViagem.tsx`, `CabecalhoViagem.test.tsx`
- Create: `frontend/src/pages/viagens/detalhe/CabecalhoViagem.module.css`
**Depends-on:** none

**Interfaces:**
- Props inalteradas (`viagem`, `pode`, `onTransferir`, `onCancelar`). Renderiza fragmento: `<nav aria-label="Trilha">` + `PageHeader` + alerta de cancelada. **Sem sticky** (a página envolve).

- [ ] **Step 1: Testes** (manter os existentes de título/subtítulo/badges/A24; ajustar os de botões):

```tsx
test("com viagem.editar e transferir: Editar visível; Transferir e Cancelar viagem… no menu Mais ações", async () => {
  const user = userEvent.setup();
  const onCancelar = vi.fn();
  renderCab({ pode: () => true, onCancelar });
  expect(screen.getByRole("button", { name: "Editar" })).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Cancelar viagem…" })).toBeNull();
  await user.click(screen.getByRole("button", { name: "Mais ações" }));
  expect(screen.getByRole("menuitem", { name: "Transferir" })).toBeInTheDocument();
  await user.click(screen.getByRole("menuitem", { name: "Cancelar viagem…" }));
  expect(onCancelar).toHaveBeenCalledTimes(1);
});

test("sem permissões: sem Editar e sem menu", () => {
  renderCab({ pode: () => false });
  expect(screen.queryByRole("button", { name: "Editar" })).toBeNull();
  expect(screen.queryByRole("button", { name: "Mais ações" })).toBeNull();
});

test("viagem cancelada: sem ações e com alerta", () => {
  renderCab({ pode: () => true, viagem: { ...VIAGEM, cancelada: true, canceladaEm: "2026-09-10T10:00:00Z", motivoCancelamento: "desistiu" } });
  expect(screen.queryByRole("button", { name: "Editar" })).toBeNull();
  expect(screen.queryByRole("button", { name: "Mais ações" })).toBeNull();
  expect(screen.getByText(/desistiu/)).toBeInTheDocument();
});

test("trilha: link Viagens e código", () => {
  renderCab({ pode: () => true });
  const trilha = screen.getByRole("navigation", { name: "Trilha" });
  expect(within(trilha).getByRole("link", { name: "Viagens" })).toHaveAttribute("href", "/viagens");
  expect(trilha).toHaveTextContent(VIAGEM.codigo);
});
```
  `renderCab` = helper do arquivo com `MemoryRouter` (use o padrão atual do teste). Checar se já existe teste que exija `variant="primary"` em Editar e ajustar.

- [ ] **Step 2:** `npx vitest run src/pages/viagens/detalhe/CabecalhoViagem.test.tsx` → FAIL.
- [ ] **Step 3: Implementação** — no retorno, antes do `PageHeader`:

```tsx
      <nav aria-label="Trilha" className={c.trilha}>
        <Link to="/viagens">Viagens</Link>
        <span aria-hidden>/</span>
        <span>{viagem.codigo}</span>
      </nav>
```
  e `actions`:

```tsx
  const podeEditar = pode("viagem.editar") && !viagem.cancelada;
  const itens: ItemMenu[] = [
    ...(pode("viagem.transferir") && !viagem.cancelada ? [{ label: "Transferir", onClick: onTransferir }] : []),
    ...(podeEditar ? [{ label: "Cancelar viagem…", onClick: onCancelar, tone: "danger" as const }] : []),
  ];
  // actions:
  <>
    <MenuAcoes label="Mais ações" itens={itens} />
    {podeEditar && (
      <Button variant="business" onClick={() => { void nav(`/viagens/${viagem.id}/editar`); }}>
        Editar
      </Button>
    )}
  </>
```
  Imports: `Link` (react-router), `MenuAcoes`/`ItemMenu`, `c` de `./CabecalhoViagem.module.css`.
- [ ] **Step 4: CSS** `CabecalhoViagem.module.css`:

```css
.trilha {
  display: flex;
  gap: var(--space-2);
  font: var(--type-helper);
  color: var(--color-text-muted);
}
.trilha a {
  color: var(--color-text-link);
}
```
- [ ] **Step 5:** `npx vitest run src/pages/viagens/detalhe/CabecalhoViagem.test.tsx` → PASS · `npm run lint && npm run typecheck`.
- [ ] **Step 6:** Reportar. Não commitar. Commit do controlador: `feat(viagem): detail header with breadcrumb, Edit as primary action and more-actions menu`.

---

### Task 4: `ViagemPage` — layout, abas sem Resumo, aba Reservas em lista

**Files:**
- Modify: `frontend/src/pages/viagens/detalhe/ViagemPage.tsx`, `ViagemPage.test.tsx`
- Modify: `frontend/src/pages/viagens/detalhe/useViagem.ts`, `useViagem.test.ts`
- Modify: `frontend/src/pages/viagens/detalhe/ReservasTab.tsx`, `ReservasTab.test.tsx`
- Modify: `frontend/src/pages/viagens/detalhe/Viagem.module.css`
- Delete: `frontend/src/pages/viagens/detalhe/ResumoTab.tsx`, `ResumoTab.test.tsx`
**Depends-on:** T1, T2, T3

**Interfaces:** consome `PainelViagem` (T2), `CabecalhoViagem` (T3), `ReservaDetalheCard` (T1), `Bloco` já em `./Bloco`.

- [ ] **Step 1: Testes**
  - `useViagem.test.ts`: sem `tab` → `tab === "reservas"`; `?tab=resumo` → `"reservas"`; `setTab("reservas")` remove `tab` da URL; `setTab("financeiro")` grava `tab=financeiro`; `?reserva=r2` → `"reservas"` e `reservaAberta === "r2"` (ajustar teste existente `?tab=resumo&reserva=r2`).
  - `ViagemPage.test.tsx`: tabs na ordem "Reservas", "Financeiro", "Pendências", "Documentos", "Timeline" (com permissões); sem tab "Resumo"; `getByRole("complementary", { name: "Resumo da viagem" })` presente; sem `navigation` "Seções do módulo" (Subnav); "Ver todas" do painel troca para a aba Pendências.
  - `ReservasTab.test.tsx`: "+ Adicionar reserva" não é `business` (checar que não tem a classe do variant business, ou simplesmente que existe e continua navegando — manter F03); estado vazio "Nenhuma reserva ainda." com botão quando `podeEditar`; ajustes de "Cancelar reserva…" para menuitem.

- [ ] **Step 2:** rodar os três arquivos → FAIL.

- [ ] **Step 3: `useViagem.ts`**

```ts
  const abaUrl = params.get("tab");
  const tab = reservaAberta ? "reservas" : abaUrl && abaUrl !== "resumo" ? abaUrl : "reservas";
  // setTab: if (t === "reservas") p.delete("tab"); else p.set("tab", t);
```

- [ ] **Step 4: `ViagemPage.tsx`** — remover `ResumoTab`/`Subnav`/`subnavs`; tabs sem "resumo"; fallback `"reservas"`; layout:

```tsx
  const topoRef = useRef<HTMLDivElement>(null);
  const areaRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const topo = topoRef.current;
    const area = areaRef.current;
    if (!topo || !area) return;
    const ro = new ResizeObserver(() => {
      area.style.setProperty("--topo-h", `${topo.offsetHeight}px`);
    });
    ro.observe(topo);
    return () => {
      ro.disconnect();
    };
  }, [viagem?.id]);
```
  (hooks antes dos `return` de carregando/erro). Render:

```tsx
    <Page titulo={`${viagem.codigo} · ${viagem.destino}`}>
      <div ref={topoRef} className={s.topo}>
        <CabecalhoViagem … />
      </div>
      <div ref={areaRef} className={s.area}>
        <div className={s.principal}>
          <Tabs tabs={tabs} active={tab} onChange={v.setTab}>
            {/* painéis atuais sem o de resumo */}
          </Tabs>
        </div>
        <PainelViagem
          viagem={viagem}
          verValores={v.verValores}
          pendencias={pendenciasQ.data ?? []}
          onVerPendencias={() => { v.setTab("pendencias"); }}
        />
      </div>
      <ModaisViagem … />
    </Page>
```
  Skeleton de carregamento: `<div className={s.area}><div className={s.principal}><Skeleton lines={2} /><Skeleton lines={6} /></div><Skeleton lines={8} /></div>`.
  Abaixo de 1280 o painel deve ficar **acima** das abas: em CSS, `.area` vira 1 coluna e o painel ganha `order: -1` (seletor `.area > aside`).

- [ ] **Step 5: `ReservasTab.tsx`** — envolver `ordenadas.map(...)` + card duplicado num `<div className={s.listaReservas}>`; card duplicado deixa de usar `s.bloco` próprio (fica dentro do container); "+ Adicionar reserva" `variant="secondary"` dentro de `<div className={s.adicionar}>` no fim do container; se `viagem.reservas.length === 0`: `<p className={s.vazio}>Nenhuma reserva ainda. Toda viagem precisa de ao menos uma reserva.</p>` dentro do container.

- [ ] **Step 6: CSS** `detalhe/Viagem.module.css` — remover `.resumo`, `.split` e sua media, `.linhaClicavel` (confirmar por grep que só `ResumoTab` usava; `.linha*`, `.numero`, `.passageiroMeta` idem — remover só o que ficar sem uso em `src/`); acrescentar:

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
.area {
  display: grid;
  grid-template-columns: minmax(0, 1fr) var(--painel-viagem-w);
  align-items: start;
  gap: var(--space-6);
}
.principal {
  min-width: 0;
}
.listaReservas {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: var(--card-radius);
  overflow: hidden;
}
.adicionar {
  padding: var(--space-3) var(--space-4);
  border-top: 1px solid var(--color-border);
}
@media not all and (min-width: 1440px) {
  .area {
    grid-template-columns: minmax(0, 1fr) var(--painel-viagem-w-xl);
  }
}
@media not all and (min-width: 1280px) {
  .area {
    grid-template-columns: minmax(0, 1fr);
  }
  .area > aside {
    order: -1;
  }
}
@media (max-width: 1024px) {
  .topo {
    position: static;
  }
}
```
  `.vazio` já existe (reusar). `.reservas` continua (gap entre aviso de crédito, lista e duplicada).

- [ ] **Step 7:** apagar `ResumoTab.tsx` e `ResumoTab.test.tsx`; `grep -rn "ResumoTab" frontend/src` deve voltar vazio.
- [ ] **Step 8:** `npm run lint && npm run typecheck && npx vitest run && npm run build`.
- [ ] **Step 9:** Reportar. Não commitar. Commit do controlador: `feat(viagem): trip detail workspace with side panel, no summary tab and dense reservation list`.

---

### Task 5: E2E, docs e verificação

**Files:** `frontend/e2e/viagens.spec.ts`, `docs/BACKLOG.md`
**Depends-on:** T4

- [ ] **Step 1:** `viagens.spec.ts` l.29: trocar clique no botão por

```ts
    await page.getByRole("button", { name: "Mais ações da reserva" }).first().click();
    await page.getByRole("menuitem", { name: "Cancelar reserva…" }).click();
```
  (l.27 "tab Reservas" pode ficar — já é a aba inicial; manter clique para robustez).
- [ ] **Step 2:** `npx playwright test e2e/viagens.spec.ts e2e/nova-viagem.spec.ts e2e/styleguide.spec.ts` → 8 + 24 PASS (styleguide não usa o detalhe; se mudar, investigar antes de atualizar).
- [ ] **Step 3:** BACKLOG — seção "Redesign viagem — Fase 2 (2026-09-15)": rulings (aba Resumo removida, `?tab=resumo` cai em Reservas; Editar laranja; Transferir/Cancelar no menu), regressão da Fase 1 corrigida, pendências para Fase 3.
- [ ] **Step 4:** Reportar. Não commitar. Commits do controlador: `test(e2e): cancel reservation through actions menu` (frontend) e `docs(backlog): trip redesign phase 2` (root).
- [ ] **Controlador (não delegado):** conferência visual por screenshot em 1440/1366/1280/1024: detalhe (Reservas com uma aberta, reserva cancelada, perfil sem valores se houver conta de teste, menu aberto) e formulário da Fase 1 com reserva aberta.
