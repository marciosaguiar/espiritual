// Testa a cifra do Web Push fazendo o papel do APARELHO que recebe.
//
// É o único jeito de saber que isto funciona sem um iPhone na mão: o teste
// gera um par de chaves como o navegador geraria ao se inscrever, pede ao
// `push.js` para cifrar, e então DECIFRA pelo caminho do RFC 8291. Se o
// texto voltar igual, um aparelho de verdade também abre.
//
// Um erro aqui não apareceria no envio: o serviço de push aceita os bytes e
// responde 201, o aviso chega ao aparelho, e some sem nada na tela.
//
//   node --test worker/teste/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cifrar, autorizacaoVapid, importarChaveVapid,
  b64urlParaBytes, bytesParaB64url,
} from '../src/push.js';

const TEXTO = new TextEncoder();
const DECODER = new TextDecoder();

function juntar(...pedacos) {
  const total = pedacos.reduce((n, p) => n + p.length, 0);
  const saida = new Uint8Array(total);
  let i = 0;
  for (const p of pedacos) { saida.set(p, i); i += p.length; }
  return saida;
}

async function hkdf(salt, ikm, info, bytes) {
  const k = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt, info }, k, bytes * 8));
}

/// Uma inscrição como a que `pushManager.subscribe()` devolveria.
async function inscricaoDeMentira() {
  const par = await crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const publica = new Uint8Array(await crypto.subtle.exportKey('raw', par.publicKey));
  const authSecret = crypto.getRandomValues(new Uint8Array(16));
  return {
    endpoint: 'https://fcm.googleapis.com/fcm/send/abc123',
    p256dh: bytesParaB64url(publica),
    auth: bytesParaB64url(authSecret),
    _par: par,
    _publica: publica,
    _authSecret: authSecret,
  };
}

/// O lado do aparelho: desmonta o corpo e devolve o texto claro.
async function decifrarComoOAparelho(corpo, inscricao) {
  const salt = corpo.slice(0, 16);
  const idlen = corpo[20];
  const asPublica = corpo.slice(21, 21 + idlen);
  const cifrado = corpo.slice(21 + idlen);

  const nossa = await crypto.subtle.importKey(
    'raw', asPublica, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const segredo = new Uint8Array(await crypto.subtle.deriveBits(
    { name: 'ECDH', public: nossa }, inscricao._par.privateKey, 256));

  const ikm = await hkdf(
    inscricao._authSecret,
    segredo,
    juntar(TEXTO.encode('WebPush: info'), new Uint8Array([0]),
      inscricao._publica, asPublica),
    32);
  const cek = await hkdf(salt, ikm,
    juntar(TEXTO.encode('Content-Encoding: aes128gcm'), new Uint8Array([0])), 16);
  const nonce = await hkdf(salt, ikm,
    juntar(TEXTO.encode('Content-Encoding: nonce'), new Uint8Array([0])), 12);

  const chave = await crypto.subtle.importKey(
    'raw', cek, { name: 'AES-GCM' }, false, ['decrypt']);
  const claro = new Uint8Array(await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce }, chave, cifrado));
  // O último byte é o delimitador 0x02.
  assert.equal(claro[claro.length - 1], 2, 'falta o delimitador de registro');
  return DECODER.decode(claro.slice(0, -1));
}

test('o aparelho decifra o que o Worker cifrou', async () => {
  const inscricao = await inscricaoDeMentira();
  const aviso = JSON.stringify({
    titulo: 'Márcio',
    corpo: 'quem leva o cabo do teclado hoje?',
  });
  const corpo = await cifrar(aviso, inscricao.p256dh, inscricao.auth);
  assert.equal(await decifrarComoOAparelho(corpo, inscricao), aviso);
});

test('acento e emoji chegam inteiros', async () => {
  // O começo da mensagem vai no aviso, e mensagem de voz vira "🎤". Um erro
  // de bytes aqui apareceria como aviso em branco, não como erro.
  const inscricao = await inscricaoDeMentira();
  const aviso = JSON.stringify({ titulo: 'João', corpo: '🎤 Mensagem de voz · ação' });
  const corpo = await cifrar(aviso, inscricao.p256dh, inscricao.auth);
  assert.equal(await decifrarComoOAparelho(corpo, inscricao), aviso);
});

test('o cabeçalho tem o tamanho que o RFC manda', async () => {
  const inscricao = await inscricaoDeMentira();
  const corpo = await cifrar('oi', inscricao.p256dh, inscricao.auth);
  assert.equal(corpo[20], 65, 'o keyid tem de ter 65 bytes');
  const rs = new DataView(corpo.buffer, corpo.byteOffset + 16, 4).getUint32(0);
  assert.equal(rs, 4096);
  // salt 16 + rs 4 + idlen 1 + chave 65 + ("oi" + 0x02) 3 + tag 16
  assert.equal(corpo.length, 16 + 4 + 1 + 65 + 3 + 16);
});

test('cada envio usa um salt e uma chave novos', async () => {
  // Reaproveitar o par de chaves ou o salt entre envios é um furo clássico
  // no AES-GCM: dois textos com o mesmo nonce entregam a chave.
  const inscricao = await inscricaoDeMentira();
  const a = await cifrar('mesmo texto', inscricao.p256dh, inscricao.auth);
  const b = await cifrar('mesmo texto', inscricao.p256dh, inscricao.auth);
  assert.notDeepEqual(a.slice(0, 16), b.slice(0, 16), 'salt repetido');
  assert.notDeepEqual(a.slice(21, 86), b.slice(21, 86), 'chave repetida');
});

test('inscrição com chave estragada é recusada na hora', async () => {
  const dezesseis = bytesParaB64url(new Uint8Array(16));
  await assert.rejects(() => cifrar('oi', 'curtademais', dezesseis), /p256dh/);
  const i = await inscricaoDeMentira();
  await assert.rejects(() => cifrar('oi', i.p256dh, dezesseis.slice(0, 8)), /auth/);
  // Chave cortada no copiar-e-colar: o erro diz o que olhar.
  await assert.rejects(() => cifrar('oi', i.p256dh, 'nao!'), /base64url inválido/);
});

test('o VAPID assina, e a assinatura confere com a chave pública', async () => {
  // As duas cadeias saem do `npx web-push generate-vapid-keys`. Aqui elas
  // são geradas na hora, no mesmo formato.
  const par = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const publica = new Uint8Array(await crypto.subtle.exportKey('raw', par.publicKey));
  const jwk = await crypto.subtle.exportKey('jwk', par.privateKey);

  const chave = await importarChaveVapid(
    bytesParaB64url(publica), jwk.d);
  const cabecalho = await autorizacaoVapid(
    'https://web.push.apple.com/abc/def',
    'mailto:ministerio@exemplo.org',
    chave,
    bytesParaB64url(publica),
    Date.UTC(2026, 10, 16, 12, 0, 0),
  );

  assert.match(cabecalho, /^vapid t=[\w-]+\.[\w-]+\.[\w-]+, k=[\w-]+$/);
  const jwt = cabecalho.slice('vapid t='.length).split(', k=')[0];
  const [h, c, s] = jwt.split('.');

  const corpo = JSON.parse(new TextDecoder().decode(b64urlParaBytes(c)));
  // `aud` é a ORIGEM, sem o caminho: com o caminho, o Apple Push responde 400.
  assert.equal(corpo.aud, 'https://web.push.apple.com');
  assert.equal(corpo.sub, 'mailto:ministerio@exemplo.org');
  assert.equal(corpo.exp, Math.floor(Date.UTC(2026, 10, 16, 12, 0, 0) / 1000) + 43200);
  assert.deepEqual(JSON.parse(new TextDecoder().decode(b64urlParaBytes(h))),
    { typ: 'JWT', alg: 'ES256' });

  const confere = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    par.publicKey,
    b64urlParaBytes(s),
    new TextEncoder().encode(`${h}.${c}`),
  );
  assert.ok(confere, 'o serviço de push recusaria esta assinatura');
});

test('chave de VAPID no formato errado para antes de tentar enviar', async () => {
  await assert.rejects(() => importarChaveVapid('AAAA', 'AAAA'), /65 bytes/);
  const publica = bytesParaB64url(juntar(new Uint8Array([4]), new Uint8Array(64)));
  await assert.rejects(() => importarChaveVapid(publica, 'AAAA'), /32 bytes/);
});
