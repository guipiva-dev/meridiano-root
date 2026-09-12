# Correções da auditoria de homologação 2026-09-12 (rodada 2)

Fonte: `Auditoria_Homologacao_Meridiano_2026-09-12.docx` (27 achados). A auditoria rodou em 11/09 ~21h–23h BRT, **antes** do merge das correções da rodada 1 (backend `b27bc35`, frontend `b8bfef8`, 12/09 01:27 BRT). Triagem contra `main` atual:

**Já fechados em `main` (sem ação):** ALT-03 (CPF dígito), ALT-05 (e-mail persiste — round trip verificado), ALT-06 (CNPJ grupo), ALT-08 (MoneyInput), MED-01 (título de edição), MED-05 (fuso da auditoria, `set_config('TimeZone')`), MED-08 (Ajuda/Notificações removidos), ALT-15 parcial (despesa excluir, fornecedor/colaborador inativar).

**Por design (sem ação, registrar em BACKLOG):** ALT-11 (`taxa_servico` é independente de `valor_total`, §4.2); ALT-14 (repasse é digitado pelo dono, nunca recalculado — §5, "Repasse já pago de viagem cancelada: registrado como está"); MEL-01 (`design-system-contrato.md:92` — sem "Salvando…", só `● Alterações não salvas → ✓ Salvo às HH:MM`; modais fecham como feedback); BLQ-01 (502 do Cloudflare Tunnel local — operação, não código).

**Corrigir:** ALT-01, ALT-02, ALT-04, ALT-07, ALT-09 (rótulo), ALT-10, ALT-12, ALT-13, ALT-15 (grupo UI, cliente), MED-02, MED-03, MED-04, MED-06, MED-07, MED-09, MEL-02.

Branch `fix/homologacao-2` em backend e frontend. Global: seguir `.superpowers/sdd/regras-implementador.md`. Limites de texto (MED-03/ALT-12), usados por back e front: `destino` 120, `localizador` 40, `nome` (pessoa/grupo/fornecedor/usuário) 150, `cidade` 80, `titulo` (pendência) 150, `descricao` (despesa/pendência/serviço) 200, `observacoes`/`motivo`/`descricao` longa 2000. Backend: 422 `texto_longo` com mensagem "<campo> deve ter no máximo N caracteres".

## Backend

### Task B1 — Validações de cadastro (ALT-02, ALT-04, ALT-07)
Files: `backend/src/Meridiano.Api/Modules/Pessoas/DocumentosService.cs`, `backend/src/Meridiano.Api/Modules/Pessoas/ClientesService.cs`, `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresService.cs`, `backend/src/Meridiano.Api/Modules/Comum/Guardas.cs` (só adicionar helpers), `backend/tests/Meridiano.Api.Tests/DocumentosTests.cs`, `backend/tests/Meridiano.Api.Tests/ClientesTests.cs`, `backend/tests/Meridiano.Api.Tests/FornecedoresTests.cs`
Depends-on: none
- ALT-02: `DocumentosService.Validar` — `numero` obrigatório para todo tipo (422 `numero_obrigatorio`). Hoje `DocumentosService.cs:89-95` aceita vazio.
- ALT-04: telefone/whatsapp de cliente — além da contagem de dígitos (`ClientesService.cs:141-146`), rejeitar qualquer caractere fora de `[0-9 ()+-.]` (422 `telefone_invalido`) e **persistir só dígitos** (normalizar com `+` inicial preservado se houver). Hoje `Limpar()` só faz trim.
- ALT-07: fornecedor — `telefone` mesma regra (helper compartilhado em `Guardas`, ex. `Guardas.Telefone(string?)` retornando normalizado ou lançando); `site` deve ser `Uri.TryCreate(..., Absolute)` com scheme http/https — aceitar sem scheme prefixando `https://` na normalização (422 `site_invalido` se ainda inválido). Comissão 0–100 e prazo > 0 já corretos, não mexer.
- Testes de integração para cada regra (RED → GREEN).

### Task B2 — Transferência por perfil + filtro de auditoria (ALT-10, MED-06)
Files: `backend/src/Meridiano.Api/Modules/Viagens/ViagensOperacoes.cs`, `backend/src/Meridiano.Api/Modules/Admin/UsuarioService.cs`, `backend/src/Meridiano.Api/Modules/Auditoria/AuditoriaSql.cs`, `backend/tests/Meridiano.Api.Tests/ViagensTransferenciaTests.cs` (criar se não existir; se existir teste de transferência em outro arquivo, usar esse), `backend/tests/Meridiano.Api.Tests/AuditoriaTests.cs`
Depends-on: none
- ALT-10: `TransferirAsync` (`ViagensOperacoes.cs:187-203`) só aceita `agente_id` com perfil `dono` ou `agente` (§7.1: só eles lançam). Outro perfil → 422 `perfil_nao_opera`. `GET /usuarios/vendedores` continua listando todos os ativos (o vendedor de viagem pode ser `vendedor_externo`); o front filtra pelo `perfil` já exposto no DTO. Não filtrar no back.
- MED-06: `AuditoriaSql.cs:106` filtro `valores`: `a.acao in ('INSERT','UPDATE')`.
- Testes: transferir para vendedor_externo → 422; para agente → 200; filtro `valores` encontra INSERT de reserva.

### Task B3 — Cliente: excluir (ALT-15)
Files: `backend/src/Meridiano.Api/Modules/Pessoas/ClientesEndpoints.cs`, `backend/src/Meridiano.Api/Modules/Pessoas/ClientesService.cs`, `backend/tests/Meridiano.Api.Tests/ClientesTests.cs`
Depends-on: B1
- `DELETE /clientes/{id}` → soft delete (`excluido_em = now()`), permissão `Permissao.ClienteEditar` (ou a que hoje guarda o PUT). Bloqueado com 422 `cliente_com_vinculos` se a pessoa é titular ou passageiro de viagem não excluída, ou tem movimento/crédito. Seguir o padrão de `DespesasService.cs:150-159`. Documentos/pendências/atendimentos da pessoa: não tocar (ficam soft-orfãos; lista já filtra `excluido_em is null`).
- Testes: excluir sem vínculo → 204 e some da lista; com viagem → 422.

### Task B4 — Limites de texto (MED-03, ALT-12)
Files: `backend/src/Meridiano.Api/Modules/Comum/Guardas.cs`, `backend/src/Meridiano.Api/Modules/Viagens/ViagensService.cs`, `backend/src/Meridiano.Api/Modules/Viagens/ReservaGravacao.cs`, `backend/src/Meridiano.Api/Modules/Pessoas/ClientesService.cs`, `backend/src/Meridiano.Api/Modules/Grupos/GruposService.cs`, `backend/src/Meridiano.Api/Modules/Fornecedores/FornecedoresService.cs`, `backend/src/Meridiano.Api/Modules/Pendencias/*Service.cs`, `backend/src/Meridiano.Api/Modules/Despesas/DespesasService.cs`, `backend/tests/Meridiano.Api.Tests/LimitesTextoTests.cs` (novo)
Depends-on: B1, B3
- Helper `Guardas.Texto(string? valor, int max, string campo)` → 422 `texto_longo` **com extensão ProblemDetails `campo` = nome do campo em camelCase** (o front mapeia por `extensions.campo`; ver como `RegraDeNegocioException` já expõe `codigo` e adicionar `campo` da mesma forma — pode exigir tocar `Infra/` do tratamento de erros: autorizado). Aplicar nos pontos de validação existentes (criar/editar) com os limites do cabeçalho do plano. Sem migration (dados de QA já violam; limite só na API).
- Um teste por módulo (destino 121 chars → 422 `texto_longo`; 120 → ok).

## Frontend

### Task F1 — Nova viagem: validação de reserva e Fechar (ALT-01, ALT-13)
Files: `frontend/src/pages/viagens/useNovaViagem.ts`, `frontend/src/pages/viagens/NovaViagemPage.tsx`, `frontend/src/pages/viagens/mapaErros.ts`, `frontend/src/pages/viagens/*.test.ts(x)` (os existentes desses arquivos), `frontend/src/components/Reserva/tipos.ts` (só se precisar de tipo de erro)
Depends-on: none
- ALT-01: `validar()` (`useNovaViagem.ts:98-105`) valida cada reserva: `fornecedorId` obrigatório, `valorTotal` > 0, tipos de serviço ≥ 1 (usar os campos que `BookingFields` já exibe como obrigatórios); erros por reserva passados ao `ReservationCard` (hoje `erros={{}}` em `NovaViagemPage.tsx:166`). Mapear códigos de reserva do back (`referencia_invalida` para fornecedor etc.) em `mapaErros.ts` quando houver campo.
- ALT-13: "Fechar" (`NovaViagemPage.tsx:76-83`) navega para `/viagens/${id}` quando a viagem existe, senão `/viagens`. Nunca `nav(-1)`.
- Testes Vitest: salvar com reserva sem fornecedor não chama API e mostra erro no campo; Fechar após salvar navega para a viagem criada.

### Task F2 — Formulários de cadastro (ALT-02, ALT-04, ALT-07)
Files: `frontend/src/components/Cadastros/pessoa/DocumentoModal.tsx` (+ test), `frontend/src/pages/clientes/DadosPessoaForm.tsx` (+ test), `frontend/src/pages/fornecedores/DadosFornecedorForm.tsx` (+ test), `frontend/src/lib/validacao.ts` (criar ou reutilizar onde `cpfValido` mora — checar; helpers `telefoneValido`, `siteValido`)
Depends-on: none
- Documento: `numero` obrigatório (erro inline, Salvar bloqueado). WhatsApp/telefone: rejeitar letras (regex `^[0-9 ()+\-.]{10,}$` após trim), erro inline. Fornecedor: telefone idem; site: aceitar URL http/https ou domínio simples (`exemplo.com.br`) — mesma tolerância do back (B1) que prefixa `https://`.
- Mensagens coerentes com o back (`telefone_invalido`, `site_invalido`, `numero_obrigatorio`) já mapeadas se o form usa `mapaErros`.

### Task F3 — Detalhe da viagem (ALT-09, ALT-10, MED-09, MEL-02)
Files: `frontend/src/pages/viagens/detalhe/CabecalhoViagem.tsx`, `frontend/src/pages/viagens/detalhe/TransferirModal.tsx`, `frontend/src/pages/viagens/detalhe/ViagemPage.tsx`, `frontend/src/pages/viagens/detalhe/ResumoTab.tsx`, `frontend/src/components/Reserva/FinancialFields.tsx`, testes existentes desses arquivos
Depends-on: none
- ALT-09: badge financeiro do cabeçalho (`CabecalhoViagem.tsx:46`) ganha prefixo "Comissão: " (é `fase_financeira` = comissão da operadora, §6) e `title` explicando "Situação da comissão dos fornecedores nas reservas ativas".
- ALT-10: `TransferirModal.tsx:44` filtra candidatos por `perfil` ∈ {`dono`,`agente`} (valores do DTO `VendedorDto.perfil`; conferir snake_case).
- MED-09: contador de reservas na aba e no Resumo mostra "Ativas N · Total M" quando M > N (`ViagemPage.tsx:64`, `ResumoTab.tsx:82`).
- MEL-02: `Field tooltip=` em Comissão, Taxa de serviço e Fluxo em `FinancialFields.tsx` — uma frase cada, com exemplo (ver `docs/design-system-contrato.md:31,43`).

### Task F4 — Lista, layout e CSV (MED-02, MED-07, ALT-12, MED-04)
Files: `frontend/src/pages/viagens/lista/ViagensPage.tsx`, `frontend/src/pages/viagens/lista/ViagensPage.module.css`, `frontend/src/components/Page/PageHeader.tsx`, `frontend/src/components/Page/Page.module.css`, `frontend/src/pages/viagens/detalhe/Viagem.module.css`, `frontend/src/lib/download.ts`, `frontend/src/pages/relatorios/RelatoriosPage.tsx`, testes existentes desses arquivos
Depends-on: none
- MED-02: `.linha1` — `select`/botões com `flex: none`; só o input absorve folga.
- MED-07: subtítulo e contadores das abas mostram "—" enquanto `listaQ.isLoading` (`ViagensPage.tsx:61,110,128`).
- ALT-12: `PageHeader` título com `min-width:0; overflow-wrap:anywhere`; `.head` filhos `min-width:0`; `Viagem.module.css` `.codigo`/`.linhaTitulo` `overflow-wrap:anywhere`. Teste: renderizar título de 150 chars sem `scrollWidth > clientWidth` (jsdom não mede layout — se inviável, teste só que as classes estão aplicadas; Playwright fica para o humano).
- MED-04: `download.ts` passa a `fetch(url, {credentials:"same-origin"})`; `!ok` → lança `Error` com mensagem do ProblemDetails; `ok` → blob + object URL + clique no anchor + revoke. `RelatoriosPage` mostra estado "Gerando…" no botão e `Alert` de erro em falha.

### Task F5 — Limites de texto + excluir grupo (MED-03, ALT-15 grupo)
Files: `frontend/src/components/Cadastros/mapaErrosCadastro.ts` (+ test), `frontend/src/pages/clientes/DadosPessoaForm.tsx`, `frontend/src/pages/fornecedores/DadosFornecedorForm.tsx`, `frontend/src/pages/grupos/GrupoPage.tsx` (+ form do grupo), `frontend/src/pages/viagens/NovaViagemPage.tsx` (campo destino/observações), `frontend/src/components/Reserva/BookingFields.tsx` (localizador), `frontend/src/components/Financeiro/DespesaModal.tsx`, `frontend/src/components/Pendencias/*Modal*.tsx` (se existir), `frontend/src/api/grupos.ts`, testes existentes
Depends-on: F1, F2 (mesmos arquivos)
- Mapear `whatsapp_invalido` → `whatsapp` em `frontend/src/components/Cadastros/mapaErrosCadastro.ts` (código novo do back, B1).
- `maxLength` nos inputs com os limites do cabeçalho do plano; contador "N/M" só em `observacoes` (2000). Mapear `texto_longo` em `mapaErros` genérico se existir.
- MED-04 (resto): `frontend/src/pages/auditoria/AuditoriaPage.tsx` troca `baixar()` por `baixarComFeedback` de `lib/download.ts` com o mesmo feedback de erro (arquivo autorizado).
- ALT-15 grupo: botão "Excluir grupo" em `GrupoPage.tsx` (kebab ou ação secundária) com confirmação (`ConfirmDialog` existente) chamando `DELETE /grupos/{id}` (já existe no back; conferir cliente em `api/grupos.ts`), depois navega para a lista. Teste Vitest.

### Task F6 — Excluir cliente (ALT-15 cliente)
Files: `frontend/src/api/clientes.ts`, `frontend/src/pages/clientes/PessoaPage.tsx` (+ test)
Depends-on: B3, F5
- Ação "Excluir cliente" com confirmação; 422 `cliente_com_vinculos` mostrado em `Alert` com a mensagem do back; sucesso → lista de clientes.

## Ondas
- Onda 1: B1, B2, F1, F2, F3, F4
- Onda 2: B3, F5
- Onda 3: B4, F6
