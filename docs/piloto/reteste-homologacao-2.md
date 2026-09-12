# Reteste da homologação — rodada 2 (2026-09-12)

Ambiente: `https://mediterraneo-app.bspdv.com.br` (build de 12/09 14:47 BRT, backend `dd14855`, frontend `1a7a6a7`).

## Contas (senha `meridiano123` em todas; 5 erros em 15 min bloqueiam a conta)

| E-mail | Perfil | O que deve ver/fazer (§7.1) |
|---|---|---|
| `dono@viva.dev` | Dono | Tudo |
| `ana.agente@viva.dev` | Agente | Lança viagens/reservas/clientes/fornecedores; **não** vê resultado da agência nem repasse |
| `financeiro@viva.dev` | Financeiro | Movimentos, conciliação, repasses, fechamento; **não** lança viagem |
| `contador@viva.dev` | Contador | Relatórios e auditoria, somente leitura |
| `ana@viva.dev` | Vendedor externo | Só as próprias viagens e clientes delas; nada de lançar |

## Corrigidos — retestar

| ID | O que conferir |
|---|---|
| ALT-01 | Reserva sem fornecedor: Salvar mostra erro no card da reserva, sem "Erro interno" |
| ALT-02 | Documento sem número não salva (botão desabilitado + erro) |
| ALT-04 | WhatsApp/telefone com letras → erro inline; salvo aparece com máscara |
| ALT-07 | Fornecedor: telefone/telefone de emergência com letras e site `nao-e-url` → erro inline |
| ALT-09 | Cabeçalho da viagem mostra "Comissão: Recebida" com tooltip explicando que é a comissão dos fornecedores |
| ALT-10 | Transferir: Vendedora Externa não aparece na lista; via API (`POST/PUT /viagens` com `agenteId` dela) → 422 `perfil_nao_opera` |
| ALT-12 | Destino 150 chars não é mais possível (limite 120); título com 120 chars quebra sem overflow horizontal |
| ALT-13 | Criar viagem a partir de outra viagem, salvar, Fechar → abre a viagem recém-criada |
| ALT-15 | Cliente e grupo têm "Excluir" com confirmação; cliente com viagem → mensagem "vínculos"; despesa excluir, fornecedor/colaborador inativar já existiam |
| MED-02 | Busca da lista de viagens mantém largura com filtros aplicados |
| MED-03 | Limites: destino 120, localizador 40, nome 150, cidade 80, título 150, descrição 200, observações 2000 (contador) |
| MED-04 | Exportar CSV (Relatórios e Auditoria) baixa o arquivo; com sessão expirada mostra erro na tela, não navega |
| MED-06 | Auditoria › "Valores de reserva" lista os eventos "Reserva lançada" |
| MED-07 | Recarregar a lista: contadores mostram "—" até carregar, nunca "0 viagens" |
| MED-09 | Viagem com reserva cancelada: aba e Resumo mostram "Ativas 0 · Total 1" |
| MEL-02 | Tooltips "?" em Comissão, Taxa de serviço e Fluxo |

## Já corrigidos antes da auditoria (build anterior) — confirmar de passagem
ALT-03 (CPF), ALT-05 (e-mail persiste), ALT-06 (CNPJ grupo), ALT-08 (valor monetário), MED-01 (título "Editar"), MED-05 (fuso da auditoria), MED-08 (Ajuda/Notificações removidos).

## Não é defeito (por regra do produto)
- ALT-11: taxa de serviço é independente do custo (§4.2) — não há teto.
- ALT-14: repasse é digitado pelo dono e nunca recalculado; cancelamento não o zera (§5).
- MEL-01: o padrão é `● Alterações não salvas → ✓ Salvo às HH:MM` no cabeçalho; modais fecham como confirmação.
- BLQ-01: 502 era queda do túnel local, não da aplicação.

## Ainda não coberto
Responsividade móvel/tablet (o auditor não conseguiu mudar o viewport) — testar em celular real ou DevTools.
