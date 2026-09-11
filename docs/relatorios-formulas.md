# Meridiano — Fórmulas dos Relatórios

> Fonte: plano `superpowers/plans/2026-09-11-fase-3-6-agenda-relatorios-equipe-auditoria.md`, rulings R6/R7 (Fase 3.6, 2026-09-11). O SQL vive em `backend/src/Meridiano.Api/Modules/Relatorios/RelatoriosSql.cs` com este texto em comentário. Endpoints: `GET /api/v1/relatorios/resumo?ano&vendedorId` e `GET /api/v1/relatorios/csv?ano&vendedorId` (`relatorio.ver`: Dono, Financeiro, Contador). Validar com três viagens reais da planilha antes de fechar a Fase 3 (spec §12; checklist em `BACKLOG.md`).

**Três eixos, nunca somados entre si:** *competência* (`reserva.data_compra`), *caixa* (`movimento_financeiro.data_movimento`), *despesas* (`despesa.pago_em`). `vw_resultado_viagem` não entra em nenhum número mensal/anual.

Universo **U(ano, vendedor)** = reservas `r` com `r.excluido_em is null`, viagem `v` com `v.excluido_em is null`, `extract(year from r.data_compra) = ano`, `[v.vendedor_id = @vendedorId]`. **U_ativo** = U sem `r.status = 'cancelada'`.

| Número | Eixo | Fórmula |
|---|---|---|
| `VendaAno`, `Reservas`, `Viagens` | competência | `sum(r.valor_cliente)`, `count(*)`, `count(distinct r.viagem_id)` sobre U_ativo |
| `ReceitaPrevista` | competência | `sum(r.receita_prevista)` sobre U_ativo (cancelada sem `comissao_mantida` já vale 0 na coluna gerada) |
| `ReceitaRecebida` | caixa | `sum(m.valor)` de `movimento_financeiro m` (`excluido_em is null`, **os 5 tipos**, sinal do banco) com `extract(year from m.data_movimento) = ano`, join `reserva r`/`viagem v` não excluídas, `[v.vendedor_id]`; reserva cancelada **entra** (caixa é caixa) |
| `RecebidoDeAnosAnteriores` | caixa | mesma soma restrita a `extract(year from r.data_compra) < ano` (é um recorte de `ReceitaRecebida`, não uma parcela à parte) |
| `DespesasPagas`, `DespesasFixas`, `DespesasViagens` | despesas | `sum(valor)` de `despesa` paga (`pago and extract(year from pago_em) = ano`, `excluido_em is null`); fixas = `categoria = 'fixo'`; viagens = `viagem_id is not null`; com `vendedorId`: só `viagem_id in (viagens do vendedor)` e fixas = 0 |
| `ResultadoOperacional` | misto explícito | `ReceitaRecebida − DespesasPagas` (rótulo da tela: "receita recebida − despesas pagas") |
| `MargemOperacionalPct` | — | `round(100 * ResultadoOperacional / VendaAno, 1)`, `null` se `VendaAno = 0` |
| `MargemComercialPct` | — | `round(100 * ReceitaPrevista / VendaAno, 1)`, `null` se `VendaAno = 0` |
| `TetoMei` | caixa | linha de `vw_teto_mei` para `ano` (ignora vendedor); `null` se não há movimentos no ano; `Alerta = PercentualTeto >= 80` |
| `ReceitaPorMes[m]` | competência × caixa | `Prevista` = `sum(r.receita_prevista)` de U_ativo com `extract(month from r.data_compra) = m`; `Recebida` = soma de caixa com `extract(month from m.data_movimento) = m`; 12 linhas sempre |
| `NacionalInternacional` | competência | por `v.tipo`: `Venda = sum(valor_cliente)`, `Pct = round(100 * Venda / VendaAno, 1)` (0 se venda 0), `MargemPct = round(100 * sum(receita_prevista) / Venda, 1)` (`null` se 0); sempre as duas linhas |
| `Fornecedores` | competência | por `r.fornecedor_id` sobre U_ativo: `Reservas`, `Volume = sum(valor_cliente)`, `Receita = sum(receita_prevista)`, `MargemPct = round(100 * Receita / Volume, 1)`; `order by Receita desc limit 10` |
| `Servicos` | competência | `select t, count(*) from U_ativo, unnest(r.tipos_servico) t group by t` — reserva com N tipos conta em N linhas; os 9 tipos sempre presentes (0 quando ausentes), ordem `Reservas desc` |
| `Ate` | — | ano corrente → nome do mês corrente ("abril"); ano passado → "dezembro" |
| `Anos` | — | `distinct extract(year from data_compra)` ∪ ano corrente, desc |

CSV (`/relatorios/csv`): uma linha por reserva de **U** (inclui canceladas): `Código;Cliente;Destino;Tipo;Vendedor;Fornecedor;Localizador;Compra;Status;Venda;Custo;Comissão;RAV operadora;RAV cliente;Taxa de serviço;Receita prevista;Comissão recebida;Previsão comissão;Situação;Serviços` (`Situação` = `SituacaoComissao` da conciliação; `Comissão recebida` = `recebido_operadora` da reserva; `Serviços` = tipos separados por `, `). Ordem `data_compra, codigo`. UTF-8 com BOM, `;`, decimal com vírgula, datas `dd/MM/yyyy`.

## Exemplo numérico (teste `RelatoriosTests.Resumo_do_ano_separa_competencia_caixa_e_despesas`)

Cenário (`ano` = ano corrente; `valor_total = valor_cliente`, logo `rav_cliente = 0` e `receita_prevista = valor_comissao`; teto MEI configurado em 81.000):

| Viagem | Vendedor | Tipo | Reserva | Compra | Venda | Comissão | Serviços |
|---|---|---|---|---|---|---|---|
| A | Ana | internacional | CVC `ABC123` | 10/01/ano | 10.000 | 1.000 | aéreo, hospedagem |
| A | Ana | internacional | Decolar | 12/01/ano | 2.000 | 200 | seguro |
| A | Ana | internacional | CVC **cancelada** | 15/01/ano | 3.000 | 300 → 0 | — |
| B | Marcos | nacional | CVC | 05/03/ano | 5.000 | 300 | hospedagem |
| C | Ana | nacional | CVC | 20/12/**ano−1** | 4.000 | 400 | — |

Movimentos: A/CVC `recebimento_operadora` +1.000 (10/02), +200 (10/04), `estorno_operadora` −100 (10/05); C/CVC `recebimento_operadora` +400 (20/01/ano). Despesas: Aluguel 800 `fixo` paga 05/02; Motorista 150 `operacional` paga 08/03 ligada à viagem B; DAS 75,90 `imposto` **não paga**.

Resultado de `GET /relatorios/resumo` (sem vendedor):

| Número | Valor | Conta |
|---|---|---|
| `VendaAno` / `Reservas` / `Viagens` | 17.000 / 3 / 2 | 10.000 + 2.000 + 5.000 (cancelada e ano−1 fora) |
| `ReceitaPrevista` | 1.500 | 1.000 + 200 + 300 |
| `ReceitaRecebida` | 1.500 | 1.000 + 200 − 100 + 400 (o 400 é da reserva C, comprada no ano anterior) |
| `RecebidoDeAnosAnteriores` | 400 | recorte da linha acima |
| `DespesasPagas` / `Fixas` / `Viagens` | 950 / 800 / 150 | DAS não paga fica fora |
| `ResultadoOperacional` | 550 | 1.500 − 950 |
| `MargemOperacionalPct` | 3,2 | 100 × 550 / 17.000 |
| `MargemComercialPct` | 8,8 | 100 × 1.500 / 17.000 |
| `TetoMei` | 1.500 / 81.000 / 1,9 % / sem alerta | caixa do ano |
| `ReceitaPorMes` | jan 1.200 / 400 · fev 0 / 1.000 · mar 300 / 0 · abr 0 / 200 · mai 0 / −100 | prevista por `data_compra` × recebida por `data_movimento` |
| `NacionalInternacional` | internacional 12.000 · 70,6 % · margem 10,0 — nacional 5.000 · 29,4 % · margem 6,0 | margem = prevista / venda do tipo |
| `Fornecedores` | CVC 2 reservas · 15.000 · 1.300 · 8,7 % — Decolar 1 · 2.000 · 200 · 10,0 % | ordem por receita |
| `Servicos` | hospedagem 2 · aéreo 1 · seguro 1 · os outros 6 = 0 | reserva A/CVC conta em duas barras |

Com `vendedorId = Ana`: venda 12.000, 2 reservas, 1 viagem, recebido 1.500 (400 de anos anteriores), despesas 0 (nenhuma ligada a viagem dela; fixas = 0), teto MEI **igual** (1.500 / 81.000). Com `vendedorId = Marcos`: venda 5.000, recebido 0, despesas pagas 150 = despesas de viagens 150. Com `ano = ano−1`: venda 4.000, 1 reserva, recebido 0 (o 400 entrou no ano corrente), `TetoMei = null`, `Ate = "dezembro"`.
