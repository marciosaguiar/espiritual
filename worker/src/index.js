// O mini-servidor dos avisos do LevitaSync, num Worker da Cloudflare.
//
// POR QUE EXISTE
//
// Aviso de mensagem nova precisa de alguém que esteja de pé quando o app
// está fechado — é o que faz a notificação aparecer com o celular no bolso.
// No Firebase isso seria uma Cloud Function, que exige o plano Blaze (cartão
// de crédito). O plano gratuito da Cloudflare dá 100 mil pedidos por dia; um
// ministério usa algumas centenas.
//
// O QUE ELE PODE, E O QUE NÃO PODE
//
// Ele NÃO recebe mensagem nem grava nada no chat: quem grava é o app, com as
// regras do Firestore valendo. O Worker só lê, confere e manda o aviso. Se
// ele cair, o chat continua inteiro — só não chega notificação.
//
// AS ROTAS
//
//   GET  /            diz se está de pé e o que falta configurar
//   POST /avisar      { mensagemId } + ID token → avisa o ministério
//   POST /testar      ID token → avisa só os aparelhos de quem pediu
//
// Nenhuma delas aceita nada sem o ID token do Firebase verificado.

import { conferirToken, lerDoc, lerColecao, apagarDoc } from './firebase.js';
import { importarChaveVapid, enviarAviso } from './push.js';
import {
  textoDoAviso, deveAvisar, dentroDoLimite, JANELA_DO_AVISO_MS,
} from './aviso.js';

const FUNCOES_APROVADAS = ['levita', 'admin'];

function cors(env, pedido) {
  const permitidas = String(env.ORIGENS ?? '').split(',').map((o) => o.trim())
    .filter(Boolean);
  const origem = pedido.headers.get('Origin') ?? '';
  // Eco só do que está na lista: `*` com Authorization não serve, e abrir
  // para qualquer origem deixaria qualquer site mandar o token de quem
  // estivesse logado.
  const liberada = permitidas.includes(origem) ? origem : (permitidas[0] ?? '');
  return {
    'Access-Control-Allow-Origin': liberada,
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function json(dados, status, cabecalhos) {
  return new Response(JSON.stringify(dados), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...cabecalhos },
  });
}

function faltaConfigurar(env) {
  return ['VAPID_PUBLIC', 'VAPID_PRIVATE', 'VAPID_ASSUNTO', 'FIREBASE_API_KEY',
    'FIREBASE_PROJECT_ID', 'ROBO_EMAIL', 'ROBO_SENHA']
    .filter((nome) => !env[nome]);
}

/// Quem pediu, se o token for válido E a pessoa estiver aprovada.
async function quemPediu(pedido, env) {
  const cabecalho = pedido.headers.get('Authorization') ?? '';
  if (!cabecalho.startsWith('Bearer ')) {
    return { erro: 'Faça login de novo.', status: 401 };
  }
  let dono;
  try {
    dono = await conferirToken(cabecalho.slice(7), env.FIREBASE_PROJECT_ID);
  } catch (e) {
    // O motivo exato vai para o log, não para a resposta: dizer "assinatura
    // não confere" a quem está tentando adivinhar só ajuda quem tenta.
    console.warn('[avisos] token recusado:', e.message);
    return { erro: 'Faça login de novo.', status: 401 };
  }

  const cadastro = await lerDoc(env, `users/${dono.uid}`);
  if (!cadastro || !FUNCOES_APROVADAS.includes(cadastro.role)) {
    return { erro: 'Sua entrada ainda não foi aprovada por um líder.', status: 403 };
  }
  return { uid: dono.uid, nome: cadastro.name ?? '' };
}

/// Manda o aviso para uma lista de inscrições e limpa as que morreram.
async function espalhar(env, inscricoes, aviso, vapid) {
  const carga = JSON.stringify(aviso);
  let enviados = 0;
  let mortos = 0;
  let falharam = 0;

  // Em paralelo: com 20 aparelhos e um serviço de push lento, em sequência
  // isso passaria do tempo de CPU do Worker.
  const resultados = await Promise.allSettled(inscricoes.map(async (i) => {
    const r = await enviarAviso(i, carga, vapid);
    if (r.morreu) {
      // Aparelho reinstalado ou dados do site limpos. A inscrição não volta
      // a funcionar nunca; deixá-la ali faria o Worker tentar para sempre.
      await apagarDoc(env, `pushSubs/${i._id}`);
      return 'morto';
    }
    return r.ok ? 'ok' : `falhou ${r.status}`;
  }));

  for (const r of resultados) {
    if (r.status === 'rejected') { falharam++; continue; }
    if (r.value === 'ok') enviados++;
    else if (r.value === 'morto') mortos++;
    else { falharam++; console.warn('[avisos]', r.value); }
  }
  return { enviados, mortos, falharam };
}

async function chaveVapid(env) {
  return {
    chave: await importarChaveVapid(env.VAPID_PUBLIC, env.VAPID_PRIVATE),
    publica: env.VAPID_PUBLIC,
    assunto: env.VAPID_ASSUNTO,
  };
}

export default {
  async fetch(pedido, env) {
    const cabecalhos = cors(env, pedido);
    const url = new URL(pedido.url);

    if (pedido.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cabecalhos });
    }

    if (url.pathname === '/' && pedido.method === 'GET') {
      const falta = faltaConfigurar(env);
      return json({
        app: 'LevitaSync — avisos do chat',
        configurado: falta.length === 0,
        falta,
      }, 200, cabecalhos);
    }

    const falta = faltaConfigurar(env);
    if (falta.length) {
      console.error('[avisos] faltam segredos:', falta.join(', '));
      return json({ erro: 'Os avisos ainda não foram configurados.' }, 503, cabecalhos);
    }

    if (pedido.method !== 'POST') {
      return json({ erro: 'não existe' }, 404, cabecalhos);
    }

    const dono = await quemPediu(pedido, env);
    if (dono.erro) return json({ erro: dono.erro }, dono.status, cabecalhos);

    if (!dentroDoLimite(dono.uid, Number(env.LIMITE_POR_MINUTO ?? 30))) {
      return json({ erro: 'Muitas mensagens seguidas. Espere um minuto.' },
        429, cabecalhos);
    }

    // ── Avisar o ministério de uma mensagem nova ───────────────────────────
    if (url.pathname === '/avisar') {
      let corpo = {};
      try { corpo = await pedido.json(); } catch (_) { /* corpo vazio */ }
      const mensagemId = String(corpo.mensagemId ?? '');
      if (!/^[A-Za-z0-9_-]{1,64}$/.test(mensagemId)) {
        return json({ erro: 'mensagemId inválido' }, 400, cabecalhos);
      }

      const mensagem = await lerDoc(env, `messages/${mensagemId}`);
      if (!mensagem) return json({ erro: 'mensagem não existe' }, 404, cabecalhos);

      // As três conferências que fazem o aviso não ser um megafone aberto:
      // a mensagem existe, é de quem está pedindo, e acabou de ser escrita.
      if (mensagem.userId !== dono.uid) {
        return json({ erro: 'a mensagem não é sua' }, 403, cabecalhos);
      }
      const quando = Date.parse(mensagem.timestamp ?? '');
      if (Number.isNaN(quando) || Date.now() - quando > JANELA_DO_AVISO_MS) {
        return json({ erro: 'mensagem antiga demais para avisar' }, 409, cabecalhos);
      }

      // Quem foi mencionado recebe mesmo com o chat silenciado, e com um
      // texto diferente — então o leque sai em dois grupos.
      const mencionados = Array.isArray(mensagem.mencoes)
        ? mensagem.mencoes.filter((x) => typeof x === 'string')
        : [];

      const todas = await lerColecao(env, 'pushSubs');
      const alvos = todas.filter(
        (i) => deveAvisar(i, dono.uid, undefined, mencionados));
      if (!alvos.length) {
        return json({ enviados: 0, mortos: 0, falharam: 0, ninguem: true },
          200, cabecalhos);
      }

      const chave = await chaveVapid(env);
      const chamados = alvos.filter((i) => mencionados.includes(i.userId));
      const demais = alvos.filter((i) => !mencionados.includes(i.userId));

      const partes = [];
      if (demais.length) {
        partes.push(await espalhar(
          env, demais, textoDoAviso(mensagem), chave));
      }
      if (chamados.length) {
        partes.push(await espalhar(
          env, chamados, textoDoAviso(mensagem, { mencionou: true }), chave));
      }

      const resultado = partes.reduce(
        (a, b) => ({
          enviados: a.enviados + b.enviados,
          mortos: a.mortos + b.mortos,
          falharam: a.falharam + b.falharam,
        }),
        { enviados: 0, mortos: 0, falharam: 0 });
      return json({ ...resultado, mencionados: chamados.length },
        200, cabecalhos);
    }

    // ── Testar nos próprios aparelhos ──────────────────────────────────────
    if (url.pathname === '/testar') {
      const todas = await lerColecao(env, 'pushSubs');
      // Aqui o filtro é o contrário: SÓ os aparelhos de quem pediu, e sem
      // olhar silêncio nem liga-desliga — é um teste, a pessoa está
      // esperando ver a notificação aparecer.
      const meus = todas.filter((i) => i.userId === dono.uid
        && i.endpoint && i.p256dh && i.auth);
      if (!meus.length) {
        return json({
          erro: 'Este aparelho não está inscrito. Toque em "Ativar avisos".',
        }, 409, cabecalhos);
      }
      const resultado = await espalhar(env, meus, {
        titulo: 'LevitaSync',
        corpo: 'Teste de aviso — está funcionando.',
        teste: true,
      }, await chaveVapid(env));
      return json(resultado, 200, cabecalhos);
    }

    return json({ erro: 'não existe' }, 404, cabecalhos);
  },
};
