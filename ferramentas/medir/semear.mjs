// Põe no emulador do Firebase (Auth + Firestore) os dados que
// `gerar_semente_test.dart` gerou, e cria a conta de quem vai entrar no app.
//
//   node ferramentas/medir/semear.mjs /tmp/semente.json
//
// Usa o acesso de dono do emulador (`Authorization: Bearer owner`), que
// ignora as regras: a semente é o banco que já existia ANTES do teste. Quem
// aplica as regras no teste é o app, lendo.

import fs from 'node:fs';

const PROJETO = process.env.PROJETO || 'espiritual-d2403';
const FIRESTORE = process.env.FIRESTORE || '127.0.0.1:8080';
const AUTH = process.env.AUTH || '127.0.0.1:9099';

const semente = JSON.parse(fs.readFileSync(process.argv[2] || '/tmp/semente.json', 'utf8'));

/// Um valor de JavaScript no formato de valor do Firestore (REST).
function valor(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (Array.isArray(v)) return { arrayValue: { values: v.map(valor) } };
  if (typeof v === 'object') {
    if ('$ts' in v) return { timestampValue: v.$ts };
    return { mapValue: { fields: campos(v) } };
  }
  throw new Error(`tipo sem conversão: ${typeof v}`);
}
const campos = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, valor(v)]));

async function chamar(url, corpo) {
  const r = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: 'Bearer owner' },
    body: JSON.stringify(corpo),
  });
  if (!r.ok) throw new Error(`${r.status} em ${url}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
}

// 0) Começa do zero: rodar duas vezes não pode dar duplicidade (nem deixar
//    lixo de uma medição na outra).
await fetch(`http://${FIRESTORE}/emulator/v1/projects/${PROJETO}/databases/(default)/documents`, { method: 'DELETE' });
await fetch(`http://${AUTH}/emulator/v1/projects/${PROJETO}/accounts`, { method: 'DELETE' });

// 1) A conta de quem entra, com o MESMO id da semente: assim o cadastro em
//    `users/u1` e o login apontam para a mesma pessoa.
const e = semente.entrar;
await chamar(`http://${AUTH}/identitytoolkit.googleapis.com/v1/projects/${PROJETO}/accounts`, {
  localId: e.id, email: e.email, password: e.senha, emailVerified: true,
});

// 2) Os documentos, em lotes de 400.
const raiz = `projects/${PROJETO}/databases/(default)/documents`;
for (let i = 0; i < semente.docs.length; i += 400) {
  const writes = semente.docs.slice(i, i + 400).map((d) => ({
    update: { name: `${raiz}/${d.path}`, fields: campos(d.data) },
  }));
  await chamar(`http://${FIRESTORE}/v1/${raiz}:commit`, { writes });
}
console.log(`semeado: 1 conta (${e.email}) e ${semente.docs.length} documentos`);
