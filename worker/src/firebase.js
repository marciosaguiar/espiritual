// O que o Worker precisa do Firebase, por REST.
//
// Duas coisas diferentes, e a diferença importa:
//
// 1. CONFERIR QUEM PEDIU. O app manda o ID token da pessoa. O Worker só
//    confia nele depois de verificar a assinatura com as chaves públicas do
//    Google. Sem isso, qualquer um na internet mandaria aviso para o
//    ministério inteiro — o endereço do Worker é público.
//
// 2. LER O BANCO. O Worker entra como um LÍDER COMUM, com e-mail e senha,
//    igual à faxina do chat. Não com chave de conta de serviço: aquela chave
//    ignora todas as regras do Firestore e, se vazar, dá acesso a tudo. A
//    senha do robô se troca e acabou.

const JWKS =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

const TEXTO = new TextEncoder();

function b64urlParaBytes(texto) {
  const s = String(texto).replace(/-/g, '+').replace(/_/g, '/');
  const cru = atob(s + '='.repeat((4 - (s.length % 4)) % 4));
  const bytes = new Uint8Array(cru.length);
  for (let i = 0; i < cru.length; i++) bytes[i] = cru.charCodeAt(i);
  return bytes;
}

function jsonDeB64url(texto) {
  return JSON.parse(new TextDecoder().decode(b64urlParaBytes(texto)));
}

// ── 1. Conferir o ID token ──────────────────────────────────────────────────

let chavesEmCache = null; // { chaves: Map, vence: ms }

async function chavesDoGoogle(buscar) {
  const agora = Date.now();
  if (chavesEmCache && chavesEmCache.vence > agora) return chavesEmCache.chaves;

  const resposta = await (buscar ?? fetch)(JWKS);
  if (!resposta.ok) throw new Error(`não li as chaves do Google (${resposta.status})`);
  const { keys } = await resposta.json();

  const chaves = new Map();
  for (const jwk of keys ?? []) {
    chaves.set(jwk.kid, await crypto.subtle.importKey(
      'jwk',
      { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    ));
  }

  // O Google troca essas chaves de tempo em tempo e diz no cabeçalho por
  // quanto tempo valem. Guardar para sempre faria o Worker parar de aceitar
  // logins de um dia para o outro, sem nada ter mudado aqui.
  const controle = resposta.headers.get('cache-control') ?? '';
  const casa = /max-age=(\d+)/.exec(controle);
  const segundos = casa ? Math.min(Number(casa[1]), 86400) : 3600;
  chavesEmCache = { chaves, vence: agora + segundos * 1000 };
  return chaves;
}

/// Verifica o ID token e devolve `{ uid, email }`, ou lança.
///
/// `agoraMs` e `buscar` existem para o teste: um token tem hora de validade,
/// e um teste que dependesse do relógio de verdade passaria hoje e falharia
/// amanhã.
export async function conferirToken(token, projeto, { agoraMs, buscar } = {}) {
  const partes = String(token ?? '').split('.');
  if (partes.length !== 3) throw new Error('token malformado');
  const [cabecalhoB64, corpoB64, assinaturaB64] = partes;

  const cabecalho = jsonDeB64url(cabecalhoB64);
  if (cabecalho.alg !== 'RS256') throw new Error(`alg inesperado: ${cabecalho.alg}`);
  if (!cabecalho.kid) throw new Error('token sem kid');

  const chaves = await chavesDoGoogle(buscar);
  const chave = chaves.get(cabecalho.kid);
  // Um kid desconhecido quase sempre é cache velho, não token falso: as
  // chaves podem ter acabado de girar.
  if (!chave) throw new Error('kid desconhecido');

  const confere = await crypto.subtle.verify(
    { name: 'RSASSA-PKCS1-v1_5' },
    chave,
    b64urlParaBytes(assinaturaB64),
    TEXTO.encode(`${cabecalhoB64}.${corpoB64}`),
  );
  if (!confere) throw new Error('assinatura não confere');

  const c = jsonDeB64url(corpoB64);
  const agora = Math.floor((agoraMs ?? Date.now()) / 1000);
  // 60 s de folga para o relógio do celular, que costuma estar torto.
  const folga = 60;

  // O `aud` é o que amarra o token a ESTE projeto. Sem conferir, um token
  // válido de qualquer outro projeto Firebase do mundo passaria.
  if (c.aud !== projeto) throw new Error('token de outro projeto');
  if (c.iss !== `https://securetoken.google.com/${projeto}`) {
    throw new Error('emissor errado');
  }
  if (!c.sub) throw new Error('token sem usuário');
  if (typeof c.exp !== 'number' || c.exp + folga < agora) {
    throw new Error('token vencido');
  }
  if (typeof c.iat === 'number' && c.iat - folga > agora) {
    throw new Error('token do futuro');
  }
  return { uid: c.sub, email: c.email ?? null };
}

// ── 2. Ler o banco como o robô ──────────────────────────────────────────────

let sessaoDoRobo = null; // { token, vence: ms }

async function tokenDoRobo(env, agoraMs) {
  const agora = agoraMs ?? Date.now();
  if (sessaoDoRobo && sessaoDoRobo.vence > agora) return sessaoDoRobo.token;

  const resposta = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${env.FIREBASE_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: env.ROBO_EMAIL,
        password: env.ROBO_SENHA,
        returnSecureToken: true,
      }),
    },
  );
  if (!resposta.ok) {
    const erro = await resposta.text();
    // Nunca devolver isto ao app: a resposta do Google diz se o e-mail
    // existe. Fica no log do Worker, que só o Márcio vê.
    throw new Error(`robô não entrou: ${resposta.status} ${erro.slice(0, 200)}`);
  }
  const { idToken, expiresIn } = await resposta.json();
  const segundos = Number(expiresIn ?? 3600);
  // Renova 5 minutos antes de vencer: um token que expira no meio do leque
  // de envio deixaria metade do ministério sem aviso.
  sessaoDoRobo = { token: idToken, vence: agora + (segundos - 300) * 1000 };
  return idToken;
}

function raiz(env) {
  return `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}` +
    '/databases/(default)/documents';
}

/// Tira o documento do formato do Firestore REST, que embrulha cada valor.
export function simplificar(doc) {
  const campos = doc?.fields ?? {};
  const saida = { _id: String(doc?.name ?? '').split('/').pop() };
  for (const [nome, valor] of Object.entries(campos)) {
    saida[nome] = valorSimples(valor);
  }
  return saida;
}

function valorSimples(v) {
  if (v == null) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('mapValue' in v) {
    const m = {};
    for (const [k, x] of Object.entries(v.mapValue.fields ?? {})) m[k] = valorSimples(x);
    return m;
  }
  if ('arrayValue' in v) return (v.arrayValue.values ?? []).map(valorSimples);
  // bytesValue e referenceValue não são usados aqui; devolver cru é melhor
  // que devolver undefined e virar "campo faltando" mais adiante.
  return v;
}

/// Um documento, ou null se não existe.
export async function lerDoc(env, caminho) {
  const token = await tokenDoRobo(env);
  const r = await fetch(`${raiz(env)}/${caminho}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (r.status === 404 || r.status === 403) return null;
  if (!r.ok) throw new Error(`Firestore ${r.status} em ${caminho}`);
  return simplificar(await r.json());
}

/// Todos os documentos de uma coleção, seguindo as páginas.
export async function lerColecao(env, colecao, maximo = 2000) {
  const token = await tokenDoRobo(env);
  const saida = [];
  let pagina = '';
  do {
    const url = `${raiz(env)}/${colecao}?pageSize=300` +
      (pagina ? `&pageToken=${encodeURIComponent(pagina)}` : '');
    const r = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!r.ok) throw new Error(`Firestore ${r.status} ao listar ${colecao}`);
    const dados = await r.json();
    for (const doc of dados.documents ?? []) saida.push(simplificar(doc));
    pagina = dados.nextPageToken ?? '';
  } while (pagina && saida.length < maximo);
  return saida;
}

/// Apaga um documento. Usado nas inscrições que o serviço de push recusou.
export async function apagarDoc(env, caminho) {
  const token = await tokenDoRobo(env);
  const r = await fetch(`${raiz(env)}/${caminho}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  });
  return r.ok || r.status === 404;
}

/// Só para o teste: esquece o que está em cache entre casos.
export function limparCaches() {
  chavesEmCache = null;
  sessaoDoRobo = null;
}
