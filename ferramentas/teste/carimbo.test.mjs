// O carimbo de "rodou às tantas horas".
//
// POR QUE ISTO TEM TESTE
//
// É código novo que fala com o Firestore por REST, e as duas coisas que ele
// precisa acertar erram em silêncio:
//
// 1. A HORA. Se o carimbo gravasse a hora do runner do GitHub, um relógio
//    torto faria o cartão "Saúde do sistema" dizer "rodou hoje" sobre uma
//    rotina parada há uma semana. Alarme que mente é pior que alarme nenhum,
//    e o jeito de garantir isso é conferir que o pedido pede a hora do
//    SERVIDOR (`setToServerValue: REQUEST_TIME`), não que manda uma data.
//
// 2. NÃO DERRUBAR A ROTINA. Quando o carimbo falha, o trabalho de verdade já
//    foi feito: os cultos foram criados, os avisos foram mandados. Lançar
//    aqui transformaria um problema de anotação numa execução perdida.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { carimbar, ROTINAS } from '../carimbo.mjs';

const ENV = { projectId: 'projeto-de-teste', idToken: 'token-de-teste' };

/// Troca o `fetch` global e guarda o que foi pedido.
function fingirFetch({ status = 200, corpo = '{}' } = {}) {
  const feitos = [];
  globalThis.fetch = async (url, opcoes) => {
    feitos.push({ url: String(url), opcoes: opcoes ?? {} });
    return new Response(corpo, { status });
  };
  return feitos;
}

function corpoDe(pedido) {
  return JSON.parse(pedido.opcoes.body);
}

test('a hora vem do SERVIDOR, nunca do runner', async () => {
  const feitos = fingirFetch();
  const r = await carimbar({ ...ENV, qual: 'vespera', ok: true, detalhe: 'x' });
  assert.equal(r.ok, true);

  const escrita = corpoDe(feitos[0]).writes[0];
  assert.deepEqual(escrita.updateTransforms, [
    { fieldPath: 'em', setToServerValue: 'REQUEST_TIME' },
  ]);
  // E `em` NÃO vai nos campos: se fosse, o robô estaria mandando uma data, e
  // a regra do banco (que exige `request.time`) recusaria tudo.
  assert.equal(escrita.update.fields.em, undefined);
  assert.deepEqual(escrita.updateMask.fieldPaths, ['ok', 'detalhe']);
});

test('grava no documento certo, na coleção certa', async () => {
  const feitos = fingirFetch();
  await carimbar({ ...ENV, qual: 'faxina', ok: true, detalhe: '' });
  const escrita = corpoDe(feitos[0]).writes[0];
  assert.match(escrita.update.name,
    /projects\/projeto-de-teste\/databases\/\(default\)\/documents\/saude\/faxina$/);
  assert.match(feitos[0].url, /documents:commit$/);
});

test('o carimbo de FALHA é gravado como falha', async () => {
  // É ele que faz o cartão ficar vermelho em vez de só envelhecer: uma
  // rotina que falha todo dia na mesma hora pareceria "rodou hoje".
  const feitos = fingirFetch();
  await carimbar({
    ...ENV, qual: 'cultos', ok: false, detalhe: 'o Worker respondeu 403',
  });
  const campos = corpoDe(feitos[0]).writes[0].update.fields;
  assert.equal(campos.ok.booleanValue, false);
  assert.match(campos.detalhe.stringValue, /403/);
});

test('rotina desconhecida não é gravada', async () => {
  // A lista é fechada nos três lugares: aqui, na regra do banco e no app.
  const feitos = fingirFetch();
  const r = await carimbar({ ...ENV, qual: 'qualquer-coisa', ok: true });
  assert.equal(r.ok, false);
  assert.match(r.erro, /desconhecida/);
  assert.equal(feitos.length, 0, 'nem tentou falar com o banco');
});

test('sem projeto ou sem token, não tenta', async () => {
  const feitos = fingirFetch();
  assert.equal((await carimbar({ idToken: 'x', qual: 'faxina' })).ok, false);
  assert.equal((await carimbar({ projectId: 'p', qual: 'faxina' })).ok, false);
  assert.equal(feitos.length, 0);
});

test('o detalhe é cortado no teto da regra', async () => {
  // A regra recusa texto acima de 300. Estourar devolveria 403, que no log
  // de um job de madrugada não explica nada.
  const feitos = fingirFetch();
  await carimbar({ ...ENV, qual: 'faxina', ok: true, detalhe: 'x'.repeat(500) });
  const campos = corpoDe(feitos[0]).writes[0].update.fields;
  assert.equal(campos.detalhe.stringValue.length, 300);
});

test('banco que recusa NÃO lança: devolve o motivo', async () => {
  fingirFetch({ status: 403, corpo: 'permissao negada' });
  const r = await carimbar({ ...ENV, qual: 'faxina', ok: true });
  assert.equal(r.ok, false);
  assert.match(r.erro, /403/);
});

test('rede que cai NÃO lança', async () => {
  globalThis.fetch = async () => { throw new Error('sem rede'); };
  const r = await carimbar({ ...ENV, qual: 'faxina', ok: true });
  assert.equal(r.ok, false);
  assert.match(r.erro, /sem rede/);
});

test('detalhe ausente não vira "undefined" no banco', async () => {
  const feitos = fingirFetch();
  await carimbar({ ...ENV, qual: 'faxina', ok: true });
  assert.equal(corpoDe(feitos[0]).writes[0].update.fields.detalhe.stringValue,
    '');
});

test('as três rotinas são as que o app e a regra conhecem', () => {
  assert.deepEqual(ROTINAS, ['cultos', 'vespera', 'faxina']);
});
