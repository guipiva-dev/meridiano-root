# Reteste da homologação — rodada 3 (2026-09-13)

Ambiente: `https://mediterraneo-app.bspdv.com.br` (piloto local via Cloudflare Tunnel, build `main` backend `86f0b54` / frontend `fa33f4f`, migration 0023 aplicada). Ferramenta: Playwright. Perfis: Dono, Vendedor externo.

| # | Achado | Resultado | Evidência |
|---|---|---|---|
| 1 | A03 venda ao cliente vazia | PASS | Total 10.000 → venda pré-preenchida `R$ 10.000,00` (sugerida); receita 1.500 correta |
| 2 | A02 taxa > total | PASS | Inline "Taxas não podem passar do total"; não salva |
| 3 | A12 esperado negativo (form e Remarcar) | PASS | Inline "Com RAV via operadora a venda não pode ficar abaixo do custo" nos dois |
| 4 | A21 CPF em cliente legado | PASS | Campo CPF presente em Carlos Mendes |
| 5 | A01 lista @1366 | PASS | Tabela 1083 px = contêiner; 7 colunas; `rem` 16 px |
| 6 | P01/P02 vendedor externo | PASS | `/fornecedores` "Sem permissão", API 403, sem item no menu; "Seu repasse R$ 100,00" na própria viagem |
| 7 | A13 excedente sem checkbox | PASS | Alerta "Marque 'Registrar mesmo assim'…" + foco no checkbox |
| 8 | M01 rótulos "recebido" | PASS | Conciliação "Comissões recebidas no mês · só operadora" 8.752; Fechamento "entradas de caixa" 8.952; Relatório "− repasses pagos · R$ 20,00" |
| 9 | B01 upload | PASS | Após `Armazenamento__Endpoint=https://mediterraneo-storage.bspdv.com.br`: `PUT` no host público → 200; CSP `connect-src` inclui o host; "Abrir" baixa do host público |
| 10 | A35 repasse de viagem cancelada | PASS | VG-2026-0005 fora dos abertos; KPI bloqueado só R$ 100 |
| — | Último Dono (P04) | não exercitado ao vivo (único Dono) — coberto por `Nao_pode_inativar_o_ultimo_dono` | |
| + | Cabeçalhos | PASS | CSP, `nosniff`, HSTS presentes no HTML |
| + | `document.title` | PASS | "Viagens · Meridiano", "VG-2026-0021 · QA Reteste 3 · Meridiano" |

Sobras corrigidas no ato: plural "1 viagens" nos KPIs de Repasses (frontend `fa33f4f`). Dados criados: VG-2026-0021 "QA Reteste 3" (1 reserva CVC, 4 anexos `voucher-qa.pdf` de teste).

Operação: MinIO exposto no tunnel como `mediterraneo-storage.bspdv.com.br` (→ `localhost:9000`); endpoint configurado como variável de usuário do Windows `Armazenamento__Endpoint` (o JSON de dev continua `localhost:9000`).
