// Web Push à mão: VAPID (RFC 8292) e a cifra da mensagem (RFC 8291).
//
// POR QUE À MÃO, E NÃO COM A BIBLIOTECA `web-push`
//
// A `web-push` do npm usa o módulo `crypto` do Node, que não existe num
// Worker da Cloudflare. O Worker tem a WebCrypto do navegador, que faz tudo
// o que é preciso: ECDH em P-256, HKDF-SHA256, AES-128-GCM e ECDSA. São
// ~120 linhas, e são as mesmas em qualquer lugar que tenha WebCrypto —
// inclusive no Node, que é onde elas são testadas (`teste/cifra.test.mjs`).
//
// POR QUE NÃO O FCM
//
// Porque não é preciso. O Web Push com VAPID é padrão: funciona no Chrome,
// no Firefox e no Safari — e no Safari do iPhone, em PWA instalado, desde o
// iOS 16.4. Usar o FCM exigiria uma chave de conta de serviço do Google, que
// é exatamente o tipo de credencial que este projeto evita.

const TEXTO = new TextEncoder();

export function bytesParaB64url(bytes) {
  let s = '';
  const b = new Uint8Array(bytes);
  for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function b64urlParaBytes(texto) {
  const s = String(texto).replace(/-/g, '+').replace(/_/g, '/');
  let cru;
  try {
    cru = atob(s + '='.repeat((4 - (s.length % 4)) % 4));
  } catch (e) {
    // Uma chave truncada no banco chegaria aqui como "Invalid character",
    // que não diz NADA sobre onde consertar. Vale dizer o tamanho: é quase
    // sempre um copiar-e-colar que perdeu o fim.
    throw new Error(`base64url inválido (${String(texto).length} caracteres)`);
  }
  const bytes = new Uint8Array(cru.length);
  for (let i = 0; i < cru.length; i++) bytes[i] = cru.charCodeAt(i);
  return bytes;
}

function juntar(...pedacos) {
  const total = pedacos.reduce((n, p) => n + p.length, 0);
  const saida = new Uint8Array(total);
  let i = 0;
  for (const p of pedacos) { saida.set(p, i); i += p.length; }
  return saida;
}

/// `info` do HKDF no formato do RFC 8188: o rótulo e um zero no fim.
function rotulo(texto) {
  return juntar(TEXTO.encode(texto), new Uint8Array([0]));
}

async function hkdf(salt, ikm, info, bytes) {
  const chave = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, [
    'deriveBits',
  ]);
  const bits = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt, info },
    chave,
    bytes * 8,
  );
  return new Uint8Array(bits);
}

/// A chave do VAPID, pronta para assinar.
///
/// O `npx web-push generate-vapid-keys` devolve duas cadeias em base64url: a
/// privada são 32 bytes crus, e a pública são 65 (0x04 e depois x e y). A
/// WebCrypto não importa os 32 bytes crus, só JWK — então o x e o y saem da
/// chave pública, que é o que estava faltando para montar o JWK.
export async function importarChaveVapid(publicaB64, privadaB64) {
  const publica = b64urlParaBytes(publicaB64);
  const privada = b64urlParaBytes(privadaB64);
  if (publica.length !== 65 || publica[0] !== 4) {
    throw new Error('VAPID_PUBLIC não tem 65 bytes começando em 0x04');
  }
  if (privada.length !== 32) {
    throw new Error('VAPID_PRIVATE não tem 32 bytes');
  }
  return crypto.subtle.importKey(
    'jwk',
    {
      kty: 'EC',
      crv: 'P-256',
      x: bytesParaB64url(publica.slice(1, 33)),
      y: bytesParaB64url(publica.slice(33, 65)),
      d: bytesParaB64url(privada),
      ext: true,
    },
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
}

/// O cabeçalho `Authorization` que prova ao serviço de push quem envia.
///
/// O `aud` é a ORIGEM do endpoint, não o endpoint inteiro: o Apple Push
/// recusa com 400 se vier o caminho também.
export async function autorizacaoVapid(endpoint, assunto, chave, publicaB64, agoraMs) {
  const agora = Math.floor((agoraMs ?? Date.now()) / 1000);
  const cabecalho = { typ: 'JWT', alg: 'ES256' };
  const corpo = {
    aud: new URL(endpoint).origin,
    // 12 horas. O máximo que a especificação aceita é 24; metade disso dá
    // folga para o relógio do servidor de push estar adiantado.
    exp: agora + 12 * 60 * 60,
    sub: assunto,
  };
  const parte = (o) => bytesParaB64url(TEXTO.encode(JSON.stringify(o)));
  const semAssinatura = `${parte(cabecalho)}.${parte(corpo)}`;
  const assinatura = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    chave,
    TEXTO.encode(semAssinatura),
  );
  // A WebCrypto já devolve r||s cru, que é o que o JWT quer. A `web-push`
  // tem de converter de DER aqui; nós não.
  const jwt = `${semAssinatura}.${bytesParaB64url(assinatura)}`;
  return `vapid t=${jwt}, k=${publicaB64}`;
}

/// Cifra o aviso para UM aparelho (RFC 8291, `aes128gcm`).
///
/// Só quem tem a chave privada daquela inscrição abre — nem o Google nem a
/// Apple, que só repassam os bytes. É por isso que o texto do aviso pode
/// trazer o começo da mensagem sem o serviço de push poder lê-lo.
export async function cifrar(textoClaro, p256dhB64, authB64, saltDado, parDado) {
  const uaPublica = b64urlParaBytes(p256dhB64);
  const authSecret = b64urlParaBytes(authB64);
  if (uaPublica.length !== 65) throw new Error('p256dh inválido');
  if (authSecret.length !== 16) throw new Error('auth inválido');

  const par = parDado ?? await crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPublica = new Uint8Array(
    await crypto.subtle.exportKey('raw', par.publicKey));

  const chaveDoAparelho = await crypto.subtle.importKey(
    'raw', uaPublica, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const segredo = new Uint8Array(await crypto.subtle.deriveBits(
    { name: 'ECDH', public: chaveDoAparelho }, par.privateKey, 256));

  // A ordem aqui é do RFC e não é simétrica: primeiro a chave do aparelho,
  // depois a nossa. Trocar as duas gera um segredo que o aparelho não
  // reproduz, e o aviso chega e não abre — sem erro nenhum no envio.
  const ikm = await hkdf(
    authSecret,
    segredo,
    juntar(TEXTO.encode('WebPush: info'), new Uint8Array([0]), uaPublica, asPublica),
    32,
  );

  const salt = saltDado ?? crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, rotulo('Content-Encoding: aes128gcm'), 16);
  const nonce = await hkdf(salt, ikm, rotulo('Content-Encoding: nonce'), 12);

  const chaveAes = await crypto.subtle.importKey(
    'raw', cek, { name: 'AES-GCM' }, false, ['encrypt']);
  // O 0x02 é o delimitador de "último registro". Sem ele o aparelho
  // descarta a mensagem por achar que falta pedaço.
  const claro = juntar(TEXTO.encode(textoClaro), new Uint8Array([2]));
  const cifrado = new Uint8Array(await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce }, chaveAes, claro));

  const rs = new Uint8Array(4);
  new DataView(rs.buffer).setUint32(0, 4096);
  return juntar(salt, rs, new Uint8Array([asPublica.length]), asPublica, cifrado);
}

/// Manda o aviso. Devolve o status, para quem chama decidir o que fazer.
///
/// 404 e 410 querem dizer que aquela inscrição morreu — o aparelho foi
/// reinstalado, ou a pessoa limpou os dados do site. Quem chama apaga.
export async function enviarAviso(inscricao, textoClaro, vapid, agoraMs) {
  const corpo = await cifrar(textoClaro, inscricao.p256dh, inscricao.auth);
  const resposta = await fetch(inscricao.endpoint, {
    method: 'POST',
    headers: {
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      // 4 horas: se o aparelho estiver desligado mais que isso, o recado de
      // combinação já não serve para nada.
      TTL: '14400',
      Urgency: 'high',
      Authorization: await autorizacaoVapid(
        inscricao.endpoint, vapid.assunto, vapid.chave, vapid.publica, agoraMs),
    },
    body: corpo,
  });
  return {
    status: resposta.status,
    morreu: resposta.status === 404 || resposta.status === 410,
    ok: resposta.status >= 200 && resposta.status < 300,
  };
}
