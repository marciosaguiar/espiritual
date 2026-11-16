import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  textoDoAviso, deveAvisar, dentroDoLimite, esquecerLimites,
} from '../src/aviso.js';
import { conferirToken, limparCaches, simplificar } from '../src/firebase.js';

// ── O texto do aviso ────────────────────────────────────────────────────────

test('mensagem de texto: nome e o começo do recado', () => {
  assert.deepEqual(
    textoDoAviso({ userName: 'Márcio', text: 'quem leva o cabo hoje?' }),
    { titulo: 'Márcio', corpo: 'quem leva o cabo hoje?' });
});

test('mensagem de voz: o microfone, não um aviso em branco', () => {
  assert.deepEqual(
    textoDoAviso({ userName: 'Ana', text: '', audioId: 'a1' }),
    { titulo: 'Ana', corpo: '🎤 Mensagem de voz' });
});

test('recado comprido é cortado com reticência', () => {
  const r = textoDoAviso({ userName: 'Ana', text: 'a'.repeat(300) });
  assert.equal(r.corpo.length, 120);
  assert.ok(r.corpo.endsWith('…'));
});

test('quebra de linha vira espaço', () => {
  // Um recado colado de outro lugar chegaria com buraco no meio do aviso.
  assert.equal(
    textoDoAviso({ userName: 'Ana', text: 'ensaio\n\n  às   19h' }).corpo,
    'ensaio às 19h');
});

test('sem nome, não fica "undefined" na tela', () => {
  assert.equal(textoDoAviso({ text: 'oi' }).titulo, 'Alguém');
  assert.equal(textoDoAviso({ userName: '   ', text: 'oi' }).titulo, 'Alguém');
});

test('sem texto e sem áudio, diz algo em vez de nada', () => {
  assert.equal(textoDoAviso({ userName: 'Ana' }).corpo, 'Mandou uma mensagem');
});

test('mensagem com música mostra a música', () => {
  assert.equal(
    textoDoAviso({ userName: 'Ana', text: 'essa no domingo', linkedSongName: 'Bondade de Deus' }).corpo,
    '🎵 Bondade de Deus · essa no domingo');
});

// ── Quem recebe ─────────────────────────────────────────────────────────────

const inscricao = (extra = {}) => ({
  _id: 'd1', userId: 'u2', endpoint: 'https://fcm.googleapis.com/x',
  p256dh: 'p', auth: 'a', ...extra,
});

test('o autor não recebe aviso da própria mensagem', () => {
  assert.equal(deveAvisar(inscricao({ userId: 'u1' }), 'u1'), false);
  assert.equal(deveAvisar(inscricao({ userId: 'u2' }), 'u1'), true);
});

test('avisos desligados: não recebe', () => {
  assert.equal(deveAvisar(inscricao({ avisosLigados: false }), 'u1'), false);
  assert.equal(deveAvisar(inscricao({ avisosLigados: true }), 'u1'), true);
  // Campo faltando é inscrição antiga, de antes do liga-desliga: recebe.
  assert.equal(deveAvisar(inscricao(), 'u1'), true);
});

test('silêncio vale até a hora marcada, e não depois', () => {
  const agora = Date.UTC(2026, 10, 16, 22, 0, 0);
  const amanha = new Date(Date.UTC(2026, 10, 17, 10, 0, 0)).toISOString();
  const ontem = new Date(Date.UTC(2026, 10, 15, 10, 0, 0)).toISOString();
  assert.equal(deveAvisar(inscricao({ silenciarAte: amanha }), 'u1', agora), false);
  assert.equal(deveAvisar(inscricao({ silenciarAte: ontem }), 'u1', agora), true);
  // Data estragada não pode virar silêncio para sempre.
  assert.equal(deveAvisar(inscricao({ silenciarAte: 'qualquer coisa' }), 'u1', agora), true);
});

test('inscrição sem as chaves é descartada antes de tentar cifrar', () => {
  assert.equal(deveAvisar(inscricao({ p256dh: '' }), 'u1'), false);
  assert.equal(deveAvisar(inscricao({ endpoint: undefined }), 'u1'), false);
  assert.equal(deveAvisar(null, 'u1'), false);
});

// ── O limite por remetente ──────────────────────────────────────────────────

test('trinta por minuto passam, o trinta e um não', () => {
  esquecerLimites();
  const agora = Date.now();
  for (let i = 0; i < 30; i++) {
    assert.ok(dentroDoLimite('u1', 30, agora + i), `o ${i + 1}º deveria passar`);
  }
  assert.equal(dentroDoLimite('u1', 30, agora + 31), false);
  // Um minuto depois, a janela andou.
  assert.ok(dentroDoLimite('u1', 30, agora + 61000));
});

test('o limite é por pessoa', () => {
  esquecerLimites();
  for (let i = 0; i < 30; i++) dentroDoLimite('u1', 30);
  assert.equal(dentroDoLimite('u1', 30), false);
  assert.ok(dentroDoLimite('u2', 30));
});

// ── O ID token ──────────────────────────────────────────────────────────────

const PROJETO = 'levitasync-exemplo';
const AGORA = Date.UTC(2026, 10, 16, 12, 0, 0);

function b64url(bytes) {
  let s = '';
  const b = new Uint8Array(bytes);
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function googleDeMentira() {
  const par = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify']);
  const jwk = await crypto.subtle.exportKey('jwk', par.publicKey);
  const buscar = async () => new Response(
    JSON.stringify({ keys: [{ ...jwk, kid: 'k1', alg: 'RS256', use: 'sig' }] }),
    { headers: { 'cache-control': 'max-age=3600' } });

  const assinar = async (corpo, kid = 'k1', alg = 'RS256') => {
    const cab = b64url(new TextEncoder().encode(JSON.stringify({ alg, kid, typ: 'JWT' })));
    const car = b64url(new TextEncoder().encode(JSON.stringify(corpo)));
    const s = await crypto.subtle.sign(
      { name: 'RSASSA-PKCS1-v1_5' }, par.privateKey,
      new TextEncoder().encode(`${cab}.${car}`));
    return `${cab}.${car}.${b64url(s)}`;
  };
  return { buscar, assinar };
}

const tokenBom = (extra = {}) => ({
  aud: PROJETO,
  iss: `https://securetoken.google.com/${PROJETO}`,
  sub: 'uid-do-marcio',
  email: 'alguem@exemplo.org',
  iat: Math.floor(AGORA / 1000) - 60,
  exp: Math.floor(AGORA / 1000) + 3600,
  ...extra,
});

test('token legítimo é aceito, e diz de quem é', async () => {
  limparCaches();
  const g = await googleDeMentira();
  const dono = await conferirToken(await g.assinar(tokenBom()), PROJETO,
    { agoraMs: AGORA, buscar: g.buscar });
  assert.equal(dono.uid, 'uid-do-marcio');
});

test('token de OUTRO projeto Firebase é recusado', async () => {
  // Sem esta conferência, qualquer conta Firebase do mundo mandaria aviso
  // para o ministério: o endereço do Worker é público.
  limparCaches();
  const g = await googleDeMentira();
  await assert.rejects(
    async () => conferirToken(await g.assinar(tokenBom({ aud: 'outro-projeto' })),
      PROJETO, { agoraMs: AGORA, buscar: g.buscar }),
    /outro projeto/);
});

test('emissor trocado é recusado', async () => {
  limparCaches();
  const g = await googleDeMentira();
  await assert.rejects(
    async () => conferirToken(await g.assinar(tokenBom({ iss: 'https://exemplo.org' })),
      PROJETO, { agoraMs: AGORA, buscar: g.buscar }),
    /emissor/);
});

test('token vencido é recusado', async () => {
  limparCaches();
  const g = await googleDeMentira();
  await assert.rejects(
    async () => conferirToken(
      await g.assinar(tokenBom({ exp: Math.floor(AGORA / 1000) - 3600 })),
      PROJETO, { agoraMs: AGORA, buscar: g.buscar }),
    /vencido/);
});

test('token com os dados trocados depois de assinado é recusado', async () => {
  // O ataque de verdade: pegar o próprio token e reescrever de quem ele é.
  // Se isto passasse, qualquer aprovado mandaria aviso em nome de outro.
  limparCaches();
  const g = await googleDeMentira();
  const [cabecalho, , assinatura] = (await g.assinar(tokenBom())).split('.');
  const outroCorpo = b64url(new TextEncoder().encode(
    JSON.stringify(tokenBom({ sub: 'uid-de-outra-pessoa' }))));
  await assert.rejects(
    async () => conferirToken(`${cabecalho}.${outroCorpo}.${assinatura}`,
      PROJETO, { agoraMs: AGORA, buscar: g.buscar }),
    /assinatura não confere/);
});

test('"alg: none" é recusado antes de qualquer conta', async () => {
  // O ataque de sempre contra JWT: trocar o algoritmo por nenhum.
  limparCaches();
  const g = await googleDeMentira();
  await assert.rejects(
    async () => conferirToken(await g.assinar(tokenBom(), 'k1', 'none'), PROJETO,
      { agoraMs: AGORA, buscar: g.buscar }),
    /alg inesperado/);
});

test('token sem usuário é recusado', async () => {
  limparCaches();
  const g = await googleDeMentira();
  await assert.rejects(
    async () => conferirToken(await g.assinar(tokenBom({ sub: '' })), PROJETO,
      { agoraMs: AGORA, buscar: g.buscar }),
    /sem usuário/);
});

test('lixo no lugar do token não derruba o Worker', async () => {
  limparCaches();
  const g = await googleDeMentira();
  for (const ruim of ['', 'abc', 'a.b', null, undefined, 'a.b.c.d']) {
    await assert.rejects(async () => conferirToken(ruim, PROJETO,
      { agoraMs: AGORA, buscar: g.buscar }));
  }
});

// ── A tradução do Firestore REST ────────────────────────────────────────────

test('o documento do Firestore vira objeto simples', () => {
  const doc = simplificar({
    name: 'projects/p/databases/(default)/documents/pushSubs/aparelho-1',
    fields: {
      userId: { stringValue: 'u1' },
      avisosLigados: { booleanValue: true },
      duracaoMs: { integerValue: '7000' },
      silenciarAte: { timestampValue: '2026-11-17T10:00:00Z' },
      nada: { nullValue: null },
      lista: { arrayValue: { values: [{ stringValue: 'a' }] } },
    },
  });
  assert.deepEqual(doc, {
    _id: 'aparelho-1', userId: 'u1', avisosLigados: true, duracaoMs: 7000,
    silenciarAte: '2026-11-17T10:00:00Z', nada: null, lista: ['a'],
  });
});

test('documento vazio não explode', () => {
  // Sem campos, devolve só o id vazio em vez de lançar: quem chama já
  // conferiu se o documento existe, e um throw aqui derrubaria o leque todo.
  assert.deepEqual(simplificar(null), { _id: '' });
  assert.deepEqual(simplificar({ name: 'a/b/c' }), { _id: 'c' });
});
