import { PGlite } from "@electric-sql/pglite";
import { pg_trgm } from "@electric-sql/pglite/contrib/pg_trgm";
import { pgcrypto } from "@electric-sql/pglite/contrib/pgcrypto";
import { readFileSync } from "node:fs";

const db = new PGlite({ extensions: { pg_trgm, pgcrypto } });
const schema = readFileSync("E:/workspace/viva-erp/schema-agencia-v2.sql", "utf8");

try {
  await db.exec(schema);
  console.log("schema OK");
} catch (e) {
  console.error("SCHEMA ERROR:", e.message);
  process.exit(1);
}

// smoke: dono do schema ignora RLS aqui (pglite roda como superuser), então testamos só integridade + fórmulas
const r = async (sql, params) => (await db.query(sql, params)).rows;

const [ag] = await r(`insert into agencia (nome) values ('Piloto') returning id`);
await db.exec(`set app.agencia_id = '${ag.id}'`);
const [u] = await r(`insert into usuario (agencia_id, nome, email, perfil) values ($1,'Dono','dono@x.com','dono') returning id`, [ag.id]);
await db.exec(`set app.usuario_id = '${u.id}'`);
const [c] = await r(`insert into cliente (agencia_id, nome, cpf) values ($1,'Maria','12345678901') returning id`, [ag.id]);
const [f] = await r(`insert into fornecedor (agencia_id, nome, percentual_comissao_padrao) values ($1,'CVC',10) returning id`, [ag.id]);
const [v] = await r(`insert into viagem (agencia_id, cliente_id, vendedor_id, destino, data_ida, data_volta) values ($1,$2,$3,'Lisboa', current_date+30, current_date+40) returning id, codigo`, [ag.id, c.id, u.id]);
console.log("codigo viagem:", v.codigo);

// Exemplo B: RAV via operadora
const [rb] = await r(`insert into reserva (agencia_id, viagem_id, fornecedor_id, valor_total, valor_comissao, rav_operadora, valor_cliente, rav_cliente_modo)
  values ($1,$2,$3,10000,1000,100,10500,'via_operadora') returning rav_cliente, valor_esperado_operadora, receita_prevista, id`, [ag.id, v.id, f.id]);
console.assert(+rb.rav_cliente === 500 && +rb.valor_esperado_operadora === 1600 && +rb.receita_prevista === 1600, "exemplo B", rb);

// Exemplo C: RAV retido
const [rc] = await r(`insert into reserva (agencia_id, viagem_id, fornecedor_id, valor_total, valor_comissao, rav_operadora, valor_cliente, rav_cliente_modo)
  values ($1,$2,$3,10000,1000,100,10500,'retido_agencia') returning valor_esperado_operadora, receita_prevista, id`, [ag.id, v.id, f.id]);
console.assert(+rc.valor_esperado_operadora === 1100 && +rc.receita_prevista === 1600, "exemplo C", rc);

// Exemplo D: markup
const [rd] = await r(`insert into reserva (agencia_id, viagem_id, fornecedor_id, tipo_receita, valor_total, valor_cliente, fluxo_pagamento)
  values ($1,$2,$3,'markup',800,1000,'cliente_paga_agencia') returning valor_esperado_operadora, receita_prevista, id`, [ag.id, v.id, f.id]);
console.assert(+rd.valor_esperado_operadora === 0 && +rd.receita_prevista === 200, "exemplo D", rd);

// movimentos + view financeira
await db.exec(`set app.motivo = ''`);
await r(`insert into movimento_financeiro (agencia_id, reserva_id, tipo, valor) values ($1,$2,'recebimento_cliente',500)`, [ag.id, rc.id]);
await r(`insert into movimento_financeiro (agencia_id, reserva_id, tipo, valor) values ($1,$2,'recebimento_cliente',1000),($1,$2,'pagamento_fornecedor',-800)`, [ag.id, rd.id]);
const fin = await r(`select reserva_id, recebido_operadora, recebido_cliente, receita_recebida, aguardando_operadora, conciliada from vw_reserva_financeiro where reserva_id in ($1,$2,$3) order by receita_recebida`, [rb.id, rc.id, rd.id]);
console.log("vw_reserva_financeiro:", fin);
const dRow = fin.find(x => x.reserva_id === rd.id);
console.assert(+dRow.receita_recebida === 200 && dRow.conciliada === true, "markup recebida/conciliada", dRow);

// sinal errado deve falhar
let failed = false;
try { await r(`insert into movimento_financeiro (agencia_id, reserva_id, tipo, valor) values ($1,$2,'recebimento_operadora',-5)`, [ag.id, rb.id]); } catch { failed = true; }
console.assert(failed, "check de sinal");

// fase
const fase = await r(`select fase_operacional, fase_financeira from vw_fase_viagem where viagem_id = $1`, [v.id]);
console.log("fase:", fase[0]);
console.assert(fase[0].fase_operacional === 'em_emissao' && fase[0].fase_financeira === 'a_receber', "fases", fase[0]);

// cancelamento zera esperado/prevista
const [canc] = await r(`update reserva set status='cancelada', cancelada_em=now(), motivo_cancelamento='desistiu', desfecho_cancelamento='credito' where id=$1 returning valor_esperado_operadora, receita_prevista`, [rb.id]);
console.assert(+canc.valor_esperado_operadora === 0 && +canc.receita_prevista === 0, "cancelamento", canc);

// auditoria capturou motivo e usuario
await db.exec(`set app.motivo = 'teste de motivo'`);
await r(`update reserva set valor_comissao = 1200 where id=$1`, [rc.id]);
const aud = await r(`select tabela, acao, alteracoes, motivo, usuario_id from auditoria where registro_id=$1 order by id desc limit 1`, [rc.id]);
console.log("auditoria:", JSON.stringify(aud[0]));
console.assert(aud[0].motivo === 'teste de motivo' && aud[0].usuario_id === u.id && aud[0].alteracoes.valor_comissao && !aud[0].alteracoes.receita_prevista, "auditoria");

// outras views compilam
for (const vw of ['vw_resultado_viagem','vw_comissao_pendente','vw_receber_cliente','vw_agenda','vw_dashboard_mensal','vw_caixa_mensal','vw_teto_mei','vw_ranking_fornecedor']) {
  await r(`select * from ${vw} limit 1`);
}
const teto = await r(`select * from vw_teto_mei`);
console.log("teto:", teto);
console.log("ALL OK");
