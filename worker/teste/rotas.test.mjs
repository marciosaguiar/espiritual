// As rotas do Worker, de ponta a ponta.
//
// POR QUE ESTE ARQUIVO EXISTE
//
// A rotina diária falhou duas noites seguidas com "O Worker respondeu 403:
// {...}", e a frase que vinha no corpo era "Sua entrada ainda não foi
// aprovada por um líder" — sobre uma conta que aparecia 👑 Líder na tela. A
// causa não era a aprovação de ninguém: era o ROBÔ do Worker sem acesso ao
// banco, e `lerDoc` devolvendo `null` do mesmo jeito para "não existe" e para
// "recusado".
//
// Nenhuma rota tinha teste. Estes medem justamente o que o log do job lê: o
// status e a frase. Um token do Firebase é assinado aqui mesmo, com um par de
// chaves gerado na hora, e o `fetch` global responde pelo Google e pelo
// Firestore — então nada sai do computador.

import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import servidor, { limparCacheDaSaude } from '../src/index.js';
import { limparCaches } from '../src/firebase.js';

const PROJETO = 'projeto-de-teste';
const JWKS = 'googleapis.com/service_accounts';
const TEXTO = new TextEncoder();

const ENV = {
  VAPID_PUBLIC: 'pub', VAPID_PRIVATE: 'priv', VAPID_ASSUNTO: 'mailto:a@b',
  FIREBASE_API_KEY: 'chave', FIREBASE_PROJECT_ID: PROJETO,
  ROBO_EMAIL: 'robo@teste', ROBO_SENHA: 'senha',
  ORIGENS: 'https://exemplo.test',
};

const LOGIN_OK = JSON.stringify({
  idToken: 'token-do-robo', expiresIn: '3600', localId: 'uid-do-robo',
});

function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

const KID = 'kid-de-teste';
let par = null;
let jwk = null;

/// Um ID token do Firebase assinado de verdade, para `conferirToken` aceitar.
async function tokenDe(uid) {
  if (!par) {
    par = await crypto.subtle.generateKey(
      {
        name: 'RSASSA-PKCS1-v1_5',
        modulusLength: 2048,
        publicExponent: new Uint8Array([1, 0, 1]),
        hash: 'SHA-256',
      },
      true,
      ['sign', 'verify'],
    );
    const { n, e, kty } = await crypto.subtle.exportKey('jwk', par.publicKey);
    jwk = { kid: KID, kty, n, e };
  }
  const agora = Math.floor(Date.now() / 1000);
  const cabecalho = b64url(TEXTO.encode(
    JSON.stringify({ alg: 'RS256', kid: KID })));
  const corpo = b64url(TEXTO.encode(JSON.stringify({
    aud: PROJETO,
    iss: `https://securetoken.google.com/${PROJETO}`,
    sub: uid,
    iat: agora - 10,
    exp: agora + 3600,
  })));
  const assinatura = await crypto.subtle.sign(
    { name: 'RSASSA-PKCS1-v1_5' },
    par.privateKey,
    TEXTO.encode(`${cabecalho}.${corpo}`),
  );
  return `${cabecalho}.${corpo}.${b64url(new Uint8Array(assinatura))}`;
}

let pedidosFeitos = 0;

/// O `fetch` do mundo: as chaves do Google, o login do robô e o Firestore.
function fingirMundo({ login = LOGIN_OK, loginStatus = 200, banco }) {
  pedidosFeitos = 0;
  globalThis.fetch = async (url, opcoes) => {
    pedidosFeitos++;
    const u = String(url);
    if (u.includes(JWKS)) {
      return new Response(JSON.stringify({ keys: [jwk] }), { status: 200 });
    }
    if (u.includes('identitytoolkit')) {
      return new Response(login, { status: loginStatus });
    }
    const r = banco ? banco(u, opcoes ?? {}) : { status: 200, corpo: '{}' };
    return new Response(r.corpo ?? '{}', { status: r.status ?? 200 });
  };
}

function docDeUsuario(campos) {
  return {
    status: 200,
    corpo: JSON.stringify({
      name: `projects/${PROJETO}/databases/(default)/documents/users/uid-1`,
      fields: campos,
    }),
  };
}

async function chamar(caminho, { metodo = 'GET', token, env = ENV } = {}) {
  const cabecalhos = { Origin: 'https://exemplo.test' };
  if (token) cabecalhos.Authorization = `Bearer ${token}`;
  const r = await servidor.fetch(
    new Request(`https://worker.test${caminho}`, { method: metodo, headers: cabecalhos }),
    env,
  );
  return { status: r.status, corpo: await r.json() };
}

beforeEach(() => {
  limparCaches();
  limparCacheDaSaude();
});

// ── /saude ────────────────────────────────────────────────────────────────

test('sem segredos, /saude diz quais faltam', async () => {
  fingirMundo({});
  const { status, corpo } = await chamar('/saude', {
    env: { ...ENV, ROBO_SENHA: '', VAPID_PRIVATE: '' },
  });
  assert.equal(status, 200);
  assert.equal(corpo.configurado, false);
  assert.deepEqual(corpo.falta, ['VAPID_PRIVATE', 'ROBO_SENHA']);
  assert.match(corpo.conserto, /Cloudflare/);
});

test('robô que não entra: /saude diz isso, e a raiz não diria', async () => {
  // A raiz respondia `{"configurado":true,"falta":[]}` enquanto tudo estava
  // recusado, porque ter o segredo preenchido não é o mesmo que ele servir.
  fingirMundo({ loginStatus: 400, login: '{"error":{"message":"INVALID_PASSWORD"}}' });
  const { corpo } = await chamar('/saude');
  assert.equal(corpo.configurado, true);
  assert.equal(corpo.entra, false);
  assert.match(corpo.robo, /entrar/i);
  assert.match(corpo.conserto, /ROBO_SENHA/);

  const raiz = await chamar('/');
  assert.equal(raiz.corpo.configurado, true);
  assert.equal(raiz.corpo.robo, undefined);
});

test('robô que entra e não lê o banco: /saude separa as duas coisas',
  async () => {
    fingirMundo({ banco: () => ({ status: 403, corpo: '{}' }) });
    const { corpo } = await chamar('/saude');
    assert.equal(corpo.entra, true);
    assert.match(corpo.robo, /não tem acesso ao banco/);
    assert.match(corpo.conserto, /ROBO_EMAIL/);
  });

test('robô que entra e não tem cadastro em users', async () => {
  // Conta criada direto no console do Firebase: ela não aparece em Membros, e
  // por isso ninguém consegue aprová-la pelo app.
  fingirMundo({ banco: () => ({ status: 404, corpo: '{}' }) });
  const { corpo } = await chamar('/saude');
  assert.match(corpo.robo, /NÃO TEM cadastro/);
  assert.match(corpo.conserto, /se cadastrar pelo app/);
});

test('robô aprovado mas não líder: /saude diz a função gravada', async () => {
  fingirMundo({
    banco: () => docDeUsuario({ role: { stringValue: 'levita' } }),
  });
  const { corpo } = await chamar('/saude');
  assert.match(corpo.robo, /"levita"/);
  assert.match(corpo.conserto, /promova/i);
});

test('robô líder: /saude não inventa conserto nenhum', async () => {
  // Aviso que fica na tela quando não há nada a fazer ensina a não olhar.
  fingirMundo({
    banco: () => docDeUsuario({ role: { stringValue: 'admin' } }),
  });
  const { corpo } = await chamar('/saude');
  assert.match(corpo.robo, /está líder/);
  assert.equal(corpo.conserto, undefined);
});

test('/saude não custa uma leitura por chamada', async () => {
  // É endereço público e sem login: um laço contra ele queimaria a cota de
  // leitura do dia.
  fingirMundo({ banco: () => docDeUsuario({ role: { stringValue: 'admin' } }) });
  await chamar('/saude');
  const depoisDaPrimeira = pedidosFeitos;
  assert.ok(depoisDaPrimeira > 0);
  const segunda = await chamar('/saude');
  assert.equal(pedidosFeitos, depoisDaPrimeira, 'a segunda chamada foi à rede');
  assert.equal(segunda.corpo.deCache, true);
});

// ── o que o job lê quando falha ───────────────────────────────────────────

test('robô sem acesso dá 503 com conserto, NUNCA 403 de não aprovado',
  async () => {
    // Este é o caso das duas noites perdidas. O que chegava ao log era 403 e
    // "Sua entrada ainda não foi aprovada por um líder", sobre uma conta
    // aprovada: a frase acusava quem pediu por um problema do robô.
    fingirMundo({ banco: () => ({ status: 403, corpo: '{}' }) });
    const { status, corpo } = await chamar('/testar', {
      metodo: 'POST', token: await tokenDe('uid-1'),
    });
    assert.equal(status, 503);
    assert.doesNotMatch(corpo.erro, /aprovad/i);
    assert.match(corpo.erro, /robô/i);
    assert.match(corpo.conserto, /ROBO_EMAIL/);
  });

test('conta sem cadastro no banco não é conta esperando aprovação',
  async () => {
    fingirMundo({ banco: () => ({ status: 404, corpo: '{}' }) });
    const { status, corpo } = await chamar('/testar', {
      metodo: 'POST', token: await tokenDe('uid-1'),
    });
    assert.equal(status, 403);
    assert.match(corpo.erro, /não tem cadastro/i);
  });

test('quem está pendente de verdade continua ouvindo que está pendente',
  async () => {
    // O conserto não pode ter apagado a mensagem certa: ela é verdadeira para
    // quem acabou de se cadastrar.
    fingirMundo({
      banco: () => docDeUsuario({ role: { stringValue: 'pendente' } }),
    });
    const { status, corpo } = await chamar('/testar', {
      metodo: 'POST', token: await tokenDe('uid-1'),
    });
    assert.equal(status, 403);
    assert.match(corpo.erro, /não foi aprovada/i);
  });

test('token de outro projeto continua sendo 401, não 403', async () => {
  // A diferença importa no log: 401 é o projeto/token, 403 é o cadastro.
  fingirMundo({});
  await tokenDe('uid-1');
  const { status } = await chamar('/testar', {
    metodo: 'POST', token: await tokenDe('uid-1'),
    env: { ...ENV, FIREBASE_PROJECT_ID: 'outro-projeto' },
  });
  assert.equal(status, 401);
});

test('erro inesperado vira 500 com resposta em JSON, não página da Cloudflare',
  async () => {
    // Sem a casca de fora, um erro aqui dentro virava a página de erro da
    // Cloudflare: o job lia HTML e o app, nada.
    fingirMundo({ banco: () => ({ status: 500, corpo: 'erro do Firestore' }) });
    const { status, corpo } = await chamar('/testar', {
      metodo: 'POST', token: await tokenDe('uid-1'),
    });
    assert.equal(status, 500);
    assert.match(corpo.erro, /servidor de avisos/i);
  });
