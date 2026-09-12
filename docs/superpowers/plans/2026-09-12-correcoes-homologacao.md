# Correções da homologação de 11/09/2026 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Every implementer reads `.superpowers/sdd/regras-implementador.md` first.

**Goal:** Fechar os 41 achados do relatório de homologação (1 bloqueador, 4 altos, 16 médios, 16 baixos, 4 melhorias) para liberar o piloto.

**Architecture:** Correções cirúrgicas nos módulos existentes (vertical slices). Backend introduz `Relogio.Hoje()` (fuso da agência) e `SET TIME ZONE` na `DbSessao` para eliminar o "hoje em UTC" sem recriar views; validadores de CPF/CNPJ no Domain; endpoint novo `PUT /reservas/{id}/status`; contratos novos de 422 que o front consome. Frontend corrige máscara monetária, estados de erro, rótulos, ações por fase e responsividade.

**Tech Stack:** .NET 10 Minimal API + Dapper + DbUp + xUnit/Testcontainers · React + Vite + TS + Vitest.

**Spec:** `regras-e-escopo-v2.md` (§4, §6.1, §7.3, §8, §9) · relatório: artifact "Homologação Meridiano" (11/09/2026) · `docs/design-system-contrato.md`.

## Global Constraints

- Branch `fix/homologacao` em `backend/` e `frontend/` (repos independentes). Root não commita código.
- Implementadores **não commitam**; controlador commita por task com pathspec. Ver `.superpowers/sdd/regras-implementador.md`.
- `dotnet build/test` sempre com `--artifacts-path E:/workspace/viva-erp/.superpowers/artifacts/<task>`.
- Backend ≤ 4 implementadores simultâneos; frontend ≤ 5.
- Português nos nomes de domínio/erros; `RegraDeNegocioException(codigo, mensagem)` → 422; UI nunca mostra enum cru (§6.1).
- Nada de EF/MediatR/etc. Sem dependência nova.
- TDD: teste RED antes da implementação; suíte completa verde ao final de cada task.

## Achados fora de código (operação — controlador registra em `docs/BACKLOG.md` / `docs/deploy.md`)

- **#01 Bloqueador — anexos apontam para `http://localhost:9000`**: a base de homologação roda o compose local atrás do Cloudflare Tunnel; `Armazenamento__Endpoint` precisa ser uma URL alcançável pelo navegador (expor MinIO no tunnel, ex. `https://mediterraneo-minio.bspdv.com.br`, ou usar R2). Código só ganha a limpeza de anexos pendentes (Task B5) e mensagem de erro (Task F7). Adicionar ao runbook: smoke de upload.
- **#05 Alto — jobs diários não rodaram**: não há scheduler no compose local. Adicionar ao runbook: `docker compose` service/cron chamando `dotnet run -- job pendencias-derivadas` etc., ou o ACA Jobs em nuvem. Sem código.

---

## Contratos novos (front e back implementam em paralelo a partir daqui)

| Contrato | Definição |
|---|---|
| `PUT /api/v1/reservas/{id}/status` | Body `{ "status": "emitida" \| "pendente", "versao": "<xmin da viagem>" }`. Reserva cancelada → 422 `reserva_cancelada`. Devolve `ViagemDto` completo (mesmo do GET). Auditoria: "emitiu a reserva {localizador}" / "voltou a reserva {localizador} para emissão". Permissão `viagem.editar`. |
| `POST /movimentos` acima do esperado | Se `tipo = recebimento_operadora` e `Σ(recebimento_operadora+estorno_operadora) + valor > valor_esperado_operadora` e body **não** traz `"confirmarExcedente": true` → 422 `recebimento_acima_esperado` com `extensions.excedente` (decimal). Com `confirmarExcedente: true` grava. Mesmo em `PUT /movimentos/{id}` e no lote (lote sempre igual ao esperado — não muda). |
| `POST /reservas/{id}/remarcar` | Body ganha `novoValorCliente?: decimal`. Se enviado, atualiza `valor_cliente` na mesma transação (log de alteração registra também "venda R$ a → R$ b"). |
| `PUT /reservas/{id}/nfse` | `status = emitido` exige `tomador` → 422 `nfse_incompleta` (mensagem: "NFSe emitida exige número, data de emissão e tomador"). |
| Crédito | `validade < hoje` → 422 `credito_validade_passada` (cancelar reserva e cancelar viagem). |
| Numérico | `PostgresException 22003` → 422 `valor_fora_do_limite` ("Valor acima do limite de R$ 9.999.999.999,99"). |
| `POST /auth/login` | Após 5 falhas seguidas do mesmo e-mail em 15 min → 429 `conta_bloqueada` com `extensions.tenteEm` (segundos). Bloqueio: 1 min, 5 min, 15 min (progressivo por número de falhas ≥5, ≥8, ≥11). Sucesso zera. |
| `GET /agenda` | Ganha `proximas: PendenciaDto[]` = abertas com `data > hoje+7` e `≤ hoje+30`. `creditos` exclui `validade < hoje`. |
| `POST /despesas` | `recorrente = true` com `viagemId` → 422 `recorrente_com_viagem` ("Despesa ligada a viagem não pode repetir todo mês"). |
| Cadastros | CPF/CNPJ com dígito inválido → 422 `cpf_invalido` / `cnpj_invalido`. Telefone/WhatsApp: 10–11 dígitos após limpar → senão 422 `telefone_invalido`. Nome duplicado (case-insensitive) de fornecedor → 409 `fornecedor_duplicado`; de grupo → 409 `grupo_duplicado`. |
| CSV relatórios | Colunas Tipo/Status/Situação/Serviços com rótulos humanos ("Nacional", "Em emissão", "Recebida", "Aéreo, Hospedagem"). |

---

## Backend — Onda 1a (paralelo, ≤4)

### Task B2+B7: Cadastros — validadores CPF/CNPJ, telefone, nomes únicos

**Files:**
- Create: `backend/src/Meridiano.Domain/Comum/DocumentosBrasil.cs` (`static bool CpfValido(string digitos)`, `static bool CnpjValido(string digitos)` — algoritmo padrão de dígitos verificadores; rejeita sequências repetidas)
- Create: `backend/tests/Meridiano.Domain.Tests/DocumentosBrasilTests.cs`
- Modify: `backend/src/Meridiano.Api/Modules/Pessoas/ClientesService.cs:128-176` (usar `CpfValido`; telefone/whatsapp 10–11 dígitos; e-mail regex simples `^[^@\s]+@[^@\s]+\.[^@\s]+$`)
- Modify: `backend/src/Meridiano.Api/Modules/Grupos/GruposService.cs:176-191` (CNPJ) + checagem de nome duplicado
- Modify: `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresService.cs:107-117` (CNPJ) + nome duplicado
- Create: `backend/src/Meridiano.Data/Migrations/0019_nomes_unicos.sql` — `create unique index ux_fornecedor_agencia_nome on fornecedor(agencia_id, lower(nome)) where excluido_em is null;` idem `ux_grupo_cliente_agencia_nome`. **Antes**, no mesmo script, renomear duplicados existentes (`nome || ' (2)'`) para a migration não falhar em bases com lixo.
- Modify tests: `backend/tests/Meridiano.Api.Tests/ClientesTests.cs`, `GruposTests.cs`, `FornecedoresTests.cs` (se existirem; senão criar seguindo o padrão de `ClientesTests.cs`)

- [ ] Testes unitários RED: `111.111.111-11` inválido, `123.456.789-00` inválido, um CPF válido gerado (ex. `529.982.247-25`), CNPJ `12.345.678/0001-00` inválido, `11.222.333/0001-81` válido.
- [ ] Integração RED: POST cliente CPF inválido → 422 `cpf_invalido`; telefone `abc` → 422 `telefone_invalido`; POST fornecedor "cvc" quando existe "CVC" → 409 `fornecedor_duplicado`; grupo idem.
- [ ] Implementar; migration; suíte verde; `dotnet format --verify-no-changes`.

### Task B3: Movimentos — excedente confirmado, limite numérico, guarda de viagem cancelada

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Financeiro/MovimentosService.cs` (`LancarAsync`, `CorrigirAsync`, `Validar`)
- Modify: `backend/src/Meridiano.Api/Modules/Financeiro/FinanceiroDtos.cs` (campo `bool? ConfirmarExcedente` no DTO de lançamento/correção — nome exato do arquivo: verificar em `Modules/Financeiro/`)
- Modify: `backend/src/Meridiano.Api/Infra/TratadorDeExcecoes.cs:13-24` (case `"22003"` → 422 `valor_fora_do_limite`)
- Modify: `backend/tests/Meridiano.Api.Tests/MovimentosTests.cs`

- [ ] RED: lançar `recebimento_operadora` 2.000 em reserva esperado 1.600 sem confirmação → 422 `recebimento_acima_esperado`, `extensions.excedente == 400`; com `confirmarExcedente: true` → 201. Corrigir para cima idem. Lançar em reserva de viagem `cancelada` (tipos de entrada) → 422 `viagem_cancelada`; `estorno_operadora`/`reembolso_cliente` continuam permitidos. Valor `99999999999` → 422 `valor_fora_do_limite` (validar em `Validar`: `valor > 9_999_999_999.99m`), e o mapeamento 22003 coberto por teste que força o erro no banco (ex. `valor_reembolso` via outro caminho — se inviável, teste unitário do `TratadorDeExcecoes`).
- [ ] GREEN; suíte; format.

### Task B4: Reservas — status emitida, remarcar com venda, NFSe tomador, crédito validade, viagem cancelada

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagensOperacoesEndpoints.cs` (novo `PUT /reservas/{id}/status`)
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagensOperacoes.cs` (`DefinirStatusAsync`, `RemarcarAsync` com `NovoValorCliente`, `DefinirNfseAsync` exige tomador, `TransferirAsync` recusa viagem cancelada → 422 `viagem_cancelada`)
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/ViagemDtos.cs` (DTOs `DefinirStatusReservaRequest`, campo `NovoValorCliente` em remarcar)
- Modify: `backend/src/Meridiano.Api/Modules/Viagens/Creditos.cs:11-26` (validade ≥ hoje → senão 422 `credito_validade_passada`; usar `DateOnly.FromDateTime(DateTime.UtcNow.AddHours(-3))` **provisório** com comentário `// ponytail: Relogio.Hoje() chega na Task B1` — B1 substitui)
- Modify: `backend/src/Meridiano.Api/Modules/Auditoria/Frases.cs` (frases "emitiu a reserva …" / "voltou a reserva … para emissão"; "venda R$ a → R$ b" na remarcação)
- Modify: `backend/tests/Meridiano.Api.Tests/ViagensOperacoesTests.cs` (ou o arquivo de testes existente do módulo — verificar nome)

- [ ] RED: PUT status emitida → 200, `reservas[0].status == "emitida"`, `faseOperacional == "confirmada"` quando todas emitidas; reserva cancelada → 422; versão stale → 409. Remarcar com `novoValorCliente` atualiza `valorCliente` e registra alteração. NFSe emitido sem tomador → 422 `nfse_incompleta`. Cancelar com crédito validade ontem → 422 `credito_validade_passada`. Transferir viagem cancelada → 422 `viagem_cancelada`.
- [ ] GREEN; suíte; format.

### Task B5: Anexos — allowlist de tipo e limpeza de pendentes

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Anexos/AnexosService.cs` (`IniciarAsync`: allowlist por extensão+mime: `pdf, jpg, jpeg, png, webp, heic, doc, docx, xls, xlsx, txt`; fora → 422 `tipo_arquivo_nao_permitido`)
- Modify: `backend/src/Meridiano.Api/Jobs/ExpurgoAnexosJob.cs` (também `delete from anexo where confirmado_em is null and criado_em < now() - interval '1 day'`; sem storage — nunca chegou lá)
- Modify: `backend/tests/Meridiano.Api.Tests/AnexosTests.cs`

- [ ] RED: `malware.exe` (`application/x-msdownload`) → 422; `voucher.pdf` → 201. Job apaga pendente de 2 dias, mantém pendente de 1 h e confirmado.
- [ ] GREEN; suíte; format.

## Backend — Onda 1b (paralelo, ≤4)

### Task B6: Despesas — recorrente × viagem, resultado só com pagas, guarda de viagem cancelada

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Despesas/DespesasService.cs` (criar/editar: `recorrente && viagemId != null` → 422 `recorrente_com_viagem`; `ReferenciasAsync`: viagem cancelada → 422 `viagem_cancelada`; `GerarProximaAsync` não precisa mudar — a regra acima impede)
- Create: `backend/src/Meridiano.Data/Migrations/0020_resultado_viagem_despesas_pagas.sql` (recriar a view de `0011_resultado_com_despesas_e_recorrencia.sql:22,30` com `sum(valor) filter (where pago)` — manter demais colunas idênticas; `create or replace view`)
- Modify: `backend/tests/Meridiano.Api.Tests/DespesasTests.cs`

- [ ] RED: POST recorrente com viagem → 422; despesa a pagar ligada à viagem não entra em `despesasViagem`/`resultado` do GET viagem; ao marcar paga, entra.
- [ ] GREEN; suíte; format.

### Task B8: Login — bloqueio progressivo por conta e mensagens de campo

**Files:**
- Modify: `backend/src/Meridiano.Api/Auth/LoginService.cs` (antes de validar senha: contar falhas em `log_acesso` para o e-mail desde o último sucesso, janela 15 min; ≥5 → 429 `conta_bloqueada` com `tenteEm`; `tenteEm` = 60/300/900 s conforme faixa, contado do último registro de falha)
- Modify: `backend/src/Meridiano.Api/Auth/AuthEndpoints.cs:15` (422 com `campos: { email: "Informe o e-mail", senha: "Informe a senha" }` em `extensions`, código `campos_obrigatorios`)
- Modify: `backend/tests/Meridiano.Api.Tests/AuthTests.cs`

- [ ] RED: 5 falhas → 6ª tentativa com senha certa → 429 `conta_bloqueada`; após `tenteEm` (manipular `log_acesso.criado_em` no teste) entra. Login vazio → 422 com `extensions.campos.email`.
- [ ] GREEN; suíte; format. `log_acesso` já tem RLS `insert with check (true)` — leitura da contagem acontece antes do tenant: usar a conexão de login (sem `DbSessao`), como o insert já faz.

### Task B10: Relatórios — CSV com rótulos humanos

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Relatorios/RelatoriosService.cs` (só o gerador de CSV; `DateTime.Today` das linhas 52/61/83 **não** mexer — Task B1)
- Create: `backend/src/Meridiano.Domain/Comum/Rotulos.cs` (mapa único `TipoViagem`, `StatusReserva`, `SituacaoComissao`, `TipoServico` → texto, espelhando §6.1 e `frontend/src/dominio/status.ts`)
- Modify: `backend/tests/Meridiano.Api.Tests/RelatoriosTests.cs`

- [ ] RED: CSV contém `Nacional;…;Em emissão;…;Recebida;…;Aéreo, Hospedagem` para a fixture.
- [ ] GREEN; suíte; format.

## Backend — Onda 2 (sozinha)

### Task B1: Fuso horário da agência — `Relogio.Hoje()` e `SET TIME ZONE`

**Files:**
- Create: `backend/src/Meridiano.Domain/Comum/Relogio.cs` — `public static class Relogio { public const string FusoPadrao = "America/Sao_Paulo"; public static DateOnly Hoje(TimeProvider? tp = null) => DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc((tp ?? TimeProvider.System).GetUtcNow().UtcDateTime, TimeZoneInfo.FindSystemTimeZoneById(FusoPadrao))); }` — `// ponytail: fuso fixo; agencia.config.fuso quando houver agência fora do Brasil`.
- Create: `backend/tests/Meridiano.Domain.Tests/RelogioTests.cs` (UTC `2026-09-12T00:48Z` → `2026-09-11`).
- Modify: `backend/src/Meridiano.Data/Sessao/DbSessao.cs` — na abertura da sessão, junto dos `set_config`, executar `set time zone 'America/Sao_Paulo'` (assim `current_date`/`now()::date` das views `vw_fase_viagem`, `vw_comissao_pendente`, `vw_agenda` e do `AgendaSql.Creditos` passam a ser o dia local).
- Modify (substituir `DateTime.Today` / `DateOnly.FromDateTime(DateTime.Now|UtcNow)` por `Relogio.Hoje()`): `Jobs/ResumoDiarioEmailJob.cs:29`, `Modules/Agenda/AgendaService.cs:18,69`, `Modules/Despesas/DespesasService.cs:165,248`, `Modules/Fechamento/FechamentoService.cs:17,38,70`, `Modules/Financeiro/ConciliacaoService.cs:100,123`, `Modules/Financeiro/MovimentosService.cs:144,202`, `Modules/Fornecedores/FornecedoresLeitura.cs:59,91`, `Modules/Pessoas/ClientesService.cs:158`, `Modules/Relatorios/RelatoriosService.cs:52,61,83`, `Modules/Repasses/RepassesService.cs:57,116`, `Modules/Viagens/Creditos.cs` (remover provisório da B4).
- Modify: `backend/tests/Meridiano.Api.Tests/PendenciasTests.cs` (ou Agenda): com `TimeProvider` fake em `2026-09-12T00:30Z`, pendência `2026-09-11` **não** é `atrasada`; com `2026-09-12T03:30Z` é. Registrar `TimeProvider.System` no DI se ainda não houver e injetar onde `Relogio.Hoje(tp)` for chamado nos serviços (mínimo: Agenda/Pendências para o teste).

- [ ] RED unit + integração; GREEN; suíte completa; format.

## Backend — Onda 3

### Task B9: Agenda — próximas 30 dias e créditos vencidos fora

**Files:**
- Modify: `backend/src/Meridiano.Api/Modules/Agenda/AgendaService.cs` (bucket `Proximas`: `> hoje+7 && <= hoje+30`; chamar `PendenciasAsync(ateDias: 30)` e repartir)
- Modify: `backend/src/Meridiano.Api/Modules/Agenda/AgendaSql.cs:77-91` (`validade >= current_date`)
- Modify: `backend/src/Meridiano.Api/Modules/Agenda/AgendaDtos.cs`
- Modify: `backend/tests/Meridiano.Api.Tests/AgendaTests.cs`

- [ ] RED: pendência em hoje+20 aparece em `proximas`; crédito vencido não aparece em `creditos`.
- [ ] GREEN; suíte; format.

---

## Frontend — Onda 1 (paralelo, ≤5): F1, F2, F3, F4, F5

### Task F1: MoneyInput — seleção no foco, sem negativo silencioso, limite

**Files:**
- Modify: `frontend/src/components/Input/MoneyInput.tsx`, `frontend/src/lib/dinheiro.ts`, testes `MoneyInput.test.tsx` / `dinheiro.test.ts`

- [ ] RED: focar por clique num campo `R$ 0,00` e digitar `300` → `R$ 300,00` (selecionar tudo no `onFocus`, inclusive por mouse — usar `requestAnimationFrame(() => input.select())`); texto `0,00300` nunca vira 3.000 (parsear: se houver mais de um separador decimal ou dígitos após 2 casas sem separador de milhar coerente, tratar como inválido → manter valor anterior e marcar erro `aria-invalid`); `-50` com `allowNegative=false` → não aceita o caractere e mostra `Valor não pode ser negativo` (prop `onErro` ou estado interno com `aria-describedby`); mais de 10 dígitos inteiros → bloqueia.
- [ ] GREEN; `npm run test -- MoneyInput dinheiro`; lint; typecheck.

### Task F2: Nova viagem — erros que somem, título, datas, rótulos

**Files:**
- Modify: `frontend/src/pages/viagens/useNovaViagem.ts` (limpar `locais[campo]` e `daApi.campos[campo]` no `onChange` do campo; validação local `dataVolta < dataIda` → "Volta antes da ida"; reavaliar `semelhante` ao mudar datas mesmo após `dispensadoPara`, exibindo variante "datas se sobrepõem")
- Modify: `frontend/src/pages/viagens/NovaViagemPage.tsx` (título `"{titular} · {destino}"` quando há `id`; "Vendedor:" sem "(a)")
- Modify: `frontend/src/pages/viagens/DadosViagemSection.tsx:89` e `frontend/src/components/Viagem/TripSummary.tsx:78` ("Comissão do vendedor")
- Modify: `frontend/src/pages/viagens/mapaErros.ts` (sem mudança de contrato; só se precisar expor `limparErro`)
- Testes: `useNovaViagem.test.ts`, `NovaViagemPage.test.tsx`

- [ ] RED/GREEN conforme acima; lint; typecheck.

### Task F3: Reserva — marcar emitida, remarcar com venda, NFSe, crédito, plural

**Files:**
- Modify: `frontend/src/api/viagens.ts` (`definirStatusReserva(viagemId, reservaId, { status, versao })`; `remarcar` body `novoValorCliente?`)
- Modify: `frontend/src/components/Reserva/ReservaDetalheCard.tsx:160-175` (botão "Marcar emitida" quando `pendente`; "Voltar a em emissão" quando `emitida`; some quando cancelada; invalida a query da viagem)
- Modify: `frontend/src/components/ViagemOperacoes/RemarcarModal.tsx` (campo "Nova venda ao cliente" opcional, pré-preenchido com o atual; aviso inline `Venda abaixo do custo: RAV do cliente ficará negativo` quando `novoValor > venda`)
- Modify: `frontend/src/components/ViagemOperacoes/NfseModal.tsx` (tomador obrigatório se Emitida — erro local + mapear 422)
- Modify: `frontend/src/components/ViagemOperacoes/DesfechoFields.tsx` (validade `min = hoje`; erro local "Validade não pode estar no passado"; mapear `credito_validade_passada`)
- Modify: `frontend/src/components/ViagemOperacoes/CancelarViagemModal.tsx:96-102` ("Cancela 1 reserva ativa" / "N reservas ativas")
- Testes correspondentes `*.test.tsx`

- [ ] RED/GREEN; lint; typecheck.

### Task F4: Detalhe da viagem — rótulos, movimentos, fase cancelada, timeline

**Files:**
- Create: `frontend/src/lib/plural.ts` — `plural(n, "reserva", "reservas")` → `"1 reserva"` / `"2 reservas"`.
- Modify: `frontend/src/pages/viagens/detalhe/FinanceiroTab.tsx:30,32` e `ResumoTab.tsx:37,44` ("Receita recebida" com tooltip "soma de todos os movimentos"; "Comissão do vendedor")
- Modify: `frontend/src/pages/viagens/detalhe/MovimentosViagem.tsx:74` (`reserva {localizador ?? fornecedor}`); garantir que o botão "Excluir…" (motivo obrigatório) aparece ao lado de "Editar" para quem tem `financeiro.movimentar` — verificar por que não aparecia (linhas 111-113) e corrigir
- Modify: `frontend/src/pages/viagens/detalhe/CabecalhoViagem.tsx` (Transferir escondido se `cancelada`; "Vendedor:"; usar `plural`)
- Modify: `frontend/src/pages/viagens/detalhe/DespesasViagem.tsx:61` e `MovimentosViagem.tsx:52-62` (em viagem cancelada: "+ Despesa" some; "+ Lançar movimento" só oferece `estorno_operadora`/`reembolso_cliente` — passar prop `tiposPermitidos` ao `MovimentoModal` **sem editar** `MovimentoModal.tsx` se ele já aceitar opções; se não aceitar, editar `frontend/src/components/Financeiro/MovimentoModal.tsx` — autorizado)
- Modify: `frontend/src/components/Auditoria/LinhaEvento.tsx:20`, `frontend/src/components/Auditoria/valorDoCampo.ts`, `frontend/src/components/Auditoria/DetalhesEventoModal.tsx`, `frontend/src/pages/viagens/detalhe/TimelineTab.tsx` (subtítulo passa por `mapas.movimento_tipo`/`mapas.reserva` etc. de `src/dominio/status.ts` quando o valor for uma chave conhecida; campo `valor` (sem prefixo) e qualquer número com nome monetário formatado como dinheiro; datas ISO → `dd/mm/aaaa`)
- Testes correspondentes

- [ ] RED/GREEN; lint; typecheck.

### Task F5: Conciliação — excedente, vazios, selecionar todas

**Files:**
- Modify: `frontend/src/components/Financeiro/ReceberModal.tsx` (aviso quando `valor > saldo`: "R$ X acima do esperado" + checkbox "Registrar mesmo assim" → envia `confirmarExcedente: true`)
- Modify: `frontend/src/components/Financeiro/useMutacaoFinanceira.ts` (mapear 422 `recebimento_acima_esperado` → mostrar aviso em vez de erro genérico)
- Modify: `frontend/src/components/DataTable/Paginacao.tsx:19` (total 0 → não renderiza)
- Modify: `frontend/src/pages/financeiro/conciliacao/ConciliacaoPage.tsx:71` (`pior: N dias` só se `> 0`; `plural` para "reservas · operadoras" — importar de `src/lib/plural.ts` criado na F4: **se ainda não existir ao começar, criar localmente o mesmo arquivo com a mesma assinatura e avisar no relatório**)
- Modify: `frontend/src/pages/financeiro/conciliacao/TabelaConciliacao.tsx`, `useConciliacao.ts` (checkbox de cabeçalho "selecionar todas elegíveis")
- Testes correspondentes

- [ ] RED/GREEN; lint; typecheck.

## Frontend — Onda 2 (paralelo, ≤5): F6, F7, F8, F9

### Task F6: Pendências e Agenda

**Files:**
- Modify: `frontend/src/components/Pendencias/LinhaPendencia.tsx:49-53` (separador ` · ` antes do responsável)
- Modify: `frontend/src/pages/agenda/CreditosTab.tsx` (meses negativos → "vencido")
- Modify: `frontend/src/pages/agenda/PendenciasAgenda.tsx`, `frontend/src/api/agenda.ts` (seção "Próximos 30 dias" recolhida por padrão, a partir de `proximas`)
- Testes

- [ ] RED/GREEN; lint; typecheck.

### Task F7: Anexos, Clientes, Nova pessoa inline, Documentos

**Files:**
- Modify: `frontend/src/components/Anexos/AnexarModal.tsx` (`accept` com a allowlist da B5; erro local "Tipo de arquivo não permitido (PDF, imagens, Office)"; falha no PUT → mensagem "Não foi possível enviar o arquivo. Verifique a conexão e tente de novo." + botão "Tentar de novo" que repete só o PUT/confirmar; mapear 422 `tipo_arquivo_nao_permitido`)
- Modify: `frontend/src/pages/clientes/Clientes.module.css`, `frontend/src/pages/clientes/FiltrosClientes.tsx` (busca com `min-width: 240px; flex: 1`; select `max-width: 280px` + `text-overflow: ellipsis`)
- Modify: `frontend/src/pages/clientes/ClientesPage.tsx:83-92` (label "Nova pessoa" — o ícone já é o "+")
- Modify: `frontend/src/components/Viagem/PessoaInlineModal.tsx` (`autoFocus` no Nome; erros de API no campo: `cpf_invalido`→cpf, `email_invalido`→email, `telefone_invalido`→telefone, conflito de CPF→cpf)
- Modify: `frontend/src/components/Cadastros/pessoa/DocumentosPessoa.tsx` + `DocumentoModal.tsx` — **verificar** o comportamento observado (POST `documentos` 201 imediato ao clicar "+ Documento" na `PessoaPage`); se o POST acontece antes do Salvar, mover para o submit; teste cobrindo "clicar + Documento não chama a API"
- Testes

- [ ] RED/GREEN; lint; typecheck.

### Task F8: Shell — header morto, mobile, tabs, 404, login local

**Files:**
- Modify: `frontend/src/shell/GlobalHeader.tsx:38-39` (remover Notificações e Ajuda), `GlobalHeader.module.css` (≤1024px: esconder nome, manter "Sair" visível; sem overflow)
- Modify: `frontend/src/shell/AppShell.module.css` (`main { min-width: 0 }`; conteúdo não pode ultrapassar viewport)
- Modify: `frontend/src/components/Tabs/Tabs.module.css` (`.list { overflow-x: auto; scrollbar-width: thin }`)
- Modify: `frontend/src/components/DataTable/DataTable.module.css` (wrapper `overflow-x: auto`) — verificar nome do arquivo
- Create: `frontend/src/shell/NaoEncontrada.tsx`; Modify `frontend/src/shell/rotasModulos.tsx:31-39` (usar o novo; texto "Página não encontrada · Confira o endereço ou volte para Viagens")
- Modify: `frontend/src/pages/acesso/LoginPage.tsx`, `EsqueciSenhaPage.tsx` (validação local: "Informe o e-mail" / "Informe a senha" no campo; mapear 429 `conta_bloqueada` → "Muitas tentativas. Tente em N min.")
- Testes; Playwright `e2e` existente deve continuar verde (`npx playwright test e2e/viagens.spec.ts` — se houver assert em Notificações/Ajuda, ajustar)

- [ ] RED/GREEN; lint; typecheck; build.

### Task F9: Despesa, cadastros (nome/CNPJ/CPF), fornecedores plural

**Files:**
- Modify: `frontend/src/components/Financeiro/DespesaModal.tsx` ("Repete todo mês" desabilitado com ajuda "Despesa ligada a viagem não repete" quando há viagem; mapear 422 `recorrente_com_viagem`)
- Modify: `frontend/src/lib/documentos.ts` (`cpfValido`, `cnpjValido` — mesmo algoritmo da B2) + `documentos.test.ts`
- Modify: `frontend/src/pages/fornecedores/DadosFornecedorForm.tsx`, `frontend/src/pages/grupos/GrupoPage.tsx`, `frontend/src/components/Cadastros/GrupoInlineModal.tsx`, `frontend/src/components/Cadastros/mapaErrosCadastro.ts` (nome obrigatório local; CNPJ inválido local; mapear 409 `fornecedor_duplicado`/`grupo_duplicado` → campo nome "Já existe com esse nome")
- Modify: `frontend/src/pages/clientes/DadosPessoaForm.tsx` (CPF inválido local)
- Modify: `frontend/src/pages/fornecedores/FornecedoresPage.tsx` ("1 dia após a compra" — usar `plural` de `src/lib/plural.ts`)
- Testes

- [ ] RED/GREEN; lint; typecheck.

---

## Fechamento (controlador)

- [ ] Backend: `dotnet build -c Release && dotnet test && dotnet format --verify-no-changes` verde na branch.
- [ ] Frontend: `npm run lint && npm run typecheck && npm run test && npm run build` verde; Playwright `nova-viagem`/`viagens`/`financeiro`.
- [ ] Merge `fix/homologacao` em `main` nos dois repos; atualizar `docs/BACKLOG.md` (achados operacionais #01/#05, "Não testado: perfis") e `docs/deploy.md` (endpoint público do storage; agendamento dos jobs; smoke de upload).
- [ ] Re-homologar na base de testes: repetir os 41 passos do relatório.
