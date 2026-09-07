# Sistema de Gestão de Agência de Viagens — Regras e Escopo v1

Documento consolidado das decisões tomadas até aqui. Serve de referência para o
desenvolvimento e de contexto para qualquer sessão futura.

---

## 1. O que o sistema é

Backoffice de **vendas, comissões e operação** de uma agência de viagens de
lazer. Não é ERP e não vende: as vendas continuam sendo feitas nos sites das
operadoras e consolidadoras, e são lançadas aqui de forma detalhada para
alimentar relatórios e dashboard.

Piloto: uma agência. **O sistema nasce multiempresa** — tem chance de virar
produto da Build Solutions, e incluir `agencia_id` depois significaria migrar
dados reais e reescrever todas as policies.

Consequências já aplicadas no schema: `agencia_id` em usuário, cliente,
fornecedor, viagem e despesa; RLS filtrando por agência em toda tabela;
`security_invoker` nas views (sem isso a view ignora a RLS e vaza dado entre
agências); código da viagem sequencial **por agência**, nunca global; e anexos
separados por pasta de agência no storage.

---

## 2. Modelo central

Três níveis:

| Nível | O que é | Quem enxerga |
|---|---|---|
| **Viagem** | O processo. Uma viagem = um cliente, um destino, um período | O cliente |
| **Reserva** | Uma por portal/compra. Localizador, custo, comissão | A operadora |
| **Serviço** | Aéreo, hotel, seguro, passeio | O viajante |

Uma viagem que usou 4 portais = 1 viagem, 4 reservas, N serviços.

---

## 3. Regras financeiras

### Lançamento
Digitados: **valor total, taxas, valor da comissão** e o que o cliente pagou.
O percentual da comissão é **calculado**, serve só para comparar operadoras.

### Tipos de receita
- **comissão** — paga pela operadora
- **markup** — diferença entre custo e venda (passeio direto, transfer)
- **taxa de serviço** — valor fixo sem custo por trás (passaporte, assessoria)

Isso faz a venda sem operadora deixar de ser exceção.

### Os dois RAVs
- **RAV da operadora** — incentivo pago por ela, somado à comissão, na mesma venda
- **RAV do cliente** — o que se cobra acima do valor da operadora, **calculado**
  pela diferença entre o que o cliente pagou e o que a operadora cobrou

Ex.: pedido de R$ 10.000, cliente paga R$ 10.500 → RAV do cliente = R$ 500,
sem ninguém digitar. Se o valor for negativo, é desconto concedido — que hoje
some na planilha.

### Previsão de pagamento da comissão
Cadastrada por fornecedor em janelas de fechamento (ex.: vendas de 1 a 14 pagam
dia 20; de 15 a 31 pagam dia 05 do mês seguinte). A data prevista é **gravada**,
não recalculada, e continua editável.

### Repasse ao vendedor externo
- Percentual sobre o **lucro da viagem**, calculado no nível viagem
- Só é liberado depois que a comissão da operadora entra
  (`bloqueado` → `a_pagar` → `pago`)
- Entra na DRE como despesa
- Dono e agentes internos têm `gera_repasse = false`; a remuneração do dono é
  pró-labore, lançada como despesa fixa — nunca como repasse

### Sem parcelamento próprio
A agência não parcela. Apenas flags de pago/recebido.

### Imposto
Empresa é MEI: o DAS é despesa fixa recorrente, não alíquota. Dashboard
monitora a receita acumulada no ano contra o teto (R$ 81.000 em 2026), com
alerta em 80%.

> **A confirmar com o contador:** se a receita bruta do MEI é só a comissão ou o
> valor total da viagem, e como registrar o repasse ao vendedor externo.

---

## 4. Visibilidade

**O vendedor externo vê apenas o valor do repasse dele.** Não vê comissão,
custo, resultado da agência nem o próprio percentual.

Implementação: ele **não tem acesso às tabelas** `viagem` e `reserva`. Acessa
só as views `vw_minha_viagem` e `vw_reserva_vendedor`, onde as colunas
sensíveis não existem. Esconder campo na interface não protege nada — a API do
Postgres é acessível direto do navegador.

**Vendedor é posição na viagem; perfil é permissão.** Quando o dono vende, ele
aparece como vendedor e continua vendo tudo, porque o perfil dele é Dono.

### Perfis iniciais
Dono, Financeiro, Agente, Vendedor externo, Contador — com permissões nomeadas
(`modulo.acao`), grupos e override por usuário. Negar sempre vence conceder.

As permissões que importam não são as de CRUD, são as de **visibilidade de
valor**: `reserva.ver_custo`, `viagem.ver_resultado`, `financeiro.ver_dre`,
`cliente.ver_documento`.

---

## 5. Status — dois eixos

Uma viagem pode estar concluída e com comissão pendente ao mesmo tempo. Por
isso, dois status calculados, nunca digitados:

- **Operacional:** sem_reserva → em_emissao → confirmada → em_viagem →
  concluida (+ cancelada, único manual)
- **Financeiro:** a_receber → parcial → quitada (+ atrasada)

---

## 6. Usuários e login

- Cadastro público desligado. O dono convida por e-mail.
- `usuario` tem id próprio e `auth_user_id` **opcional** — vendedor externo que
  não usa o sistema existe como usuário sem login.
- O vendedor da viagem já vem preenchido com o usuário logado. Trocar exige a
  permissão `viagem.definir_vendedor`; o vendedor externo não a tem.
- Usuário nunca é excluído, apenas inativado.

---

## 7. Auditoria e controles administrativos

- **Log técnico** campo a campo, por trigger, nas tabelas que importam
  (viagem, reserva, serviço, despesa, usuário). Retenção de 12 a 24 meses.
- **Timeline legível** na tela da viagem, derivada do log — sem ela ninguém
  consulta auditoria.
- **Soft delete** em tudo que tem valor financeiro.
- **Motivo obrigatório** ao alterar valor conciliado, cancelar ou excluir.
- **Trava de mês fechado**: editar reserva de período conciliado exige
  permissão específica.
- **Log de acesso a documento pessoal** (LGPD).
- Anexos em bucket privado, com URL assinada e data de descarte programada.

Descartado por ser controle de empresa grande: aprovação em duas etapas e
segregação de funções.

---

## 8. Escopo

### Versão 1 — a operação e o dinheiro
Login, usuários, perfis e permissões · clientes e CRM básico · fornecedores com
regra de pagamento · viagem, reserva e serviço · comissão com previsão e
conciliação · repasse do vendedor · anexos (cliente, viagem, reserva) ·
dashboard · busca global · agenda e tarefas automáticas · resumo diário por
e-mail · auditoria · exportação CSV.

### Versão 1.1 — depois de um mês de uso real
Despesas e DRE simplificada · crédito e reembolso com validade · checklist de
requisitos do destino · remarcação com histórico completo · metas por vendedor ·
automações de recompra do CRM · modelo de importação.

### Fora de escopo
Orçamento e cotação (feitos fora do sistema) · geração de voucher e guia
(continua no fluxo atual) · integração com operadoras · gateway de pagamento ·
API oficial do WhatsApp · emissão de bilhete.

---

## 9. Operacional confirmado

Histórico de alteração e remarcação · reembolso e crédito · checklist de
requisitos do destino (visto, vacina, validade de passaporte, seguro) · dados
operacionais do aéreo (bilhete, localizador da cia, voo, horário, bagagem,
assento) · contato de emergência do fornecedor · ocasião da viagem (lua de mel,
aniversário) · anexo por reserva · transferência de viagem entre agentes.

Descartado: data-limite de pagamento à operadora e vencimento de opção/bloqueio.

### Campos específicos pedidos
- NFSe: `falta_emitir` / `emitido` / `nao_precisa`, com tomador (cliente ou
  operadora), número e data de emissão
- Forma de pagamento do cliente por reserva, com indicação de **de quem é o cartão**
- Datas: pagamento da comissão da operadora, pagamento do repasse ao vendedor,
  emissão da NFSe

### Aviso de viagem duplicada
Ao criar viagem para cliente que já tem viagem não concluída: aviso com três
saídas — abrir a existente, **adicionar a reserva nela** ou criar assim mesmo.
Nunca bloqueio. Aviso mais forte se as datas se sobrepõem.

---

## 10. Infraestrutura

**Desenvolvimento local primeiro**, com Supabase CLI:

```
supabase init
supabase start                 # Postgres + Auth + Storage + Studio em Docker
supabase migration new nome    # migrations versionadas no Git
supabase db reset              # recria o banco do zero
supabase link && supabase db push   # aplica em produção
```

Nunca editar SQL direto em produção. Enquanto for local, dado real de cliente
não sai da máquina.

**Produção:** Supabase (banco, Auth e Storage) + API em **ASP.NET Core**, na
infraestrutura da Build Solutions.

Supabase free: 500 MB de banco, 1 GB de storage, 50 mil usuários ativos, uso
comercial permitido. Dois cuidados: projetos free **pausam após uma semana sem
atividade** — o job diário resolve; e **não há backup automático** — agendar
`pg_dump` semanal. Se o storage apertar, Cloudflare R2 tem 10 GB grátis por mês
sem custo de egress.

### Stack

| Camada | Escolha |
|---|---|
| API | ASP.NET Core Minimal API + Npgsql + Dapper |
| Banco | Postgres (Supabase) |
| Auth | Supabase Auth — JWT validado na API |
| Storage | Supabase Storage, bucket privado com URL assinada |
| Front | React + Vite + TypeScript, ou Blazor WebAssembly |
| Deploy front | Estático (Cloudflare Pages) — PWA para uso no celular |
| E-mail | Resend, para o resumo diário |

C# foi escolhido por familiaridade e por ser o padrão da casa — num projeto
mantido por anos, fluência na linguagem vale mais que stack "ideal".

**O ponto de atenção da API própria:** com credencial de serviço, a autorização
sai do banco e passa a depender do código C#, e um `if` esquecido vira
vazamento. Para manter as duas camadas, cada requisição abre a transação com
`SET LOCAL role authenticated` e as claims do usuário — assim a RLS continua
valendo através da API.

**Isolar Auth e Storage atrás de interfaces** desde o começo. Migrar o Postgres
para infra própria depois é direto; trocar autenticação e storage é o que dá
trabalho.

Alertas: dentro do sistema e resumo diário por e-mail.

---

## 11. O risco número um

**Tempo de lançamento.** Se registrar uma viagem de 4 portais levar 20 minutos,
a piloto abandona em três semanas. Medir isso no primeiro teste real e tratar
como requisito, não como detalhe. Campos pré-preenchidos, busca rápida e
teclado sem mouse valem mais que qualquer relatório extra.
