// Acrescenta à semente os dois hinários (índice + uma letra por hino) e uma
// cifra por música, para MEDIR a preparação em segundo plano com o banco do
// tamanho de verdade: 640 + 581 hinos e as cifras do repertório.
//
//   node ferramentas/medir/semear_biblioteca.mjs /tmp/semente.json
//
// Roda DEPOIS de `semear.mjs` (que começa apagando tudo).
//
// TODO o texto é INVENTADO aqui, de propósito: nada de hino ou cifra de
// verdade entra neste repositório, nem como dado de teste.

import fs from 'node:fs';

const PROJETO = process.env.PROJETO || 'espiritual-d2403';
const FIRESTORE = process.env.FIRESTORE || '127.0.0.1:8080';
const raiz = `projects/${PROJETO}/databases/(default)/documents`;

function valor(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(valor) } };
  if ('$ts' in v) return { timestampValue: v.$ts };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, valor(x)])) } };
}
const campos = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, valor(v)]));

async function lote(writes) {
  for (let i = 0; i < writes.length; i += 400) {
    const r = await fetch(`http://${FIRESTORE}/v1/${raiz}:commit`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: 'Bearer owner' },
      body: JSON.stringify({ writes: writes.slice(i, i + 400) }),
    });
    if (!r.ok) throw new Error(`${r.status}: ${(await r.text()).slice(0, 300)}`);
  }
}

const palavras = ['luz', 'paz', 'rio', 'monte', 'campo', 'aurora', 'caminho', 'fonte', 'abrigo', 'semente', 'ponte', 'vale'];
const titulo = (n) => `${palavras[n % 12]} ${palavras[(n * 7) % 12]} ${n}`.replace(/^./, (c) => c.toUpperCase());
const letra = (n) => Array.from({ length: 3 }, (_, e) =>
  `${e + 1}\n` + Array.from({ length: 4 }, (_, l) => `Verso inventado ${n}.${e + 1}.${l + 1} sobre ${palavras[(n + e + l) % 12]}`).join('\n')).join('\n\n');

const writes = [];
const agora = new Date().toISOString();
for (const [id, total] of [['harpa', 640], ['cantor', 581]]) {
  const titulos = {};
  for (let n = 1; n <= total; n++) titulos[String(n)] = titulo(n);
  writes.push({ update: { name: `${raiz}/hinarios/${id}`, fields: campos({
    titulos, total, atualizadoEm: { $ts: agora }, atualizadoPor: 'u1' }) } });
  for (let n = 1; n <= total; n++) {
    writes.push({ update: { name: `${raiz}/hinarios/${id}/hinos/${n}`, fields: campos({
      numero: n, titulo: titulo(n), letra: letra(n), importadoPor: 'u1', importadoEm: { $ts: agora } }) } });
  }
}
// Uma cifra (arranjo) por música do repertório.
const semente = JSON.parse(fs.readFileSync(process.argv[2] || '/tmp/semente.json', 'utf8'));
let cifras = 0;
for (const d of semente.docs.filter((x) => /^songs\/[^/]+$/.test(x.path))) {
  const id = d.path.split('/')[1];
  writes.push({ update: { name: `${raiz}/songs/${id}/arrangements/ar-${id}`, fields: campos({
    id: `ar-${id}`, songId: id, name: 'Padrão', churchKey: 'G',
    chords: `G      C\nCifra inventada da música ${id}\nD      G\nOutro verso inventado`,
    structure: [], bpm: 72, notes: '', approvedBy: 'u1', updatedAt: { $ts: agora } }) } });
  cifras++;
}
await lote(writes);
console.log(`semeado: hinários (640 + 581 hinos), ${cifras} cifras`);
