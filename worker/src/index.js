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
//   GET  /saude        diz se o ROBÔ dele entra e está aprovado
//   POST /avisar      { mensagemId } + ID token → avisa o ministério
//   POST /testar      ID token → avisa só os aparelhos de quem pediu
//
// Nenhuma delas aceita nada sem o ID token do Firebase verificado.

import {
  conferirToken, lerDoc, lerColecao, apagarDoc, consultarPorData, gravarDoc,
  criarDocSeNaoExiste, uidDoRobo, RoboSemAcesso,
} from './firebase.js';
import {
  cultosFaltando, agoraEmBrasilia, instanteDe, somarDias,
} from './agenda.js';
import { importarChaveVapid, enviarAviso } from './push.js';
import {
  textoDoAviso, textoDeEscalado, textoDaVespera, deveAvisar, dentroDoLimite,
  quemAvisaDoPedido, lideresInscritos, textoDaConfirmacao,
  JANELA_DO_AVISO_MS,
} from './aviso.js';

const FUNCOES_APROVADAS = ['levita', 'admin'];

/// O diagnóstico do robô, guardado por 5 minutos (ver a rota `/saude`).
let saudeEmCache = null; // { em: ms, dados }

/// Só para o teste: a saúde fica guardada 5 minutos, e cada caso precisa
/// começar do zero.
export function limparCacheDaSaude() {
  saudeEmCache = null;
}

async function saudeDoRobo(env) {
  const falta = faltaConfigurar(env);
  const agora = Date.now();
  if (saudeEmCache && agora - saudeEmCache.em < 5 * 60 * 1000) {
    return { ...saudeEmCache.dados, deCache: true };
  }

  const dados = { configurado: falta.length === 0, falta, entra: false };
  if (falta.length) {
    dados.robo = 'não dá para conferir sem os segredos';
    dados.conserto = `faltam na Cloudflare: ${falta.join(', ')}`;
  } else {
    try {
      const uid = await uidDoRobo(env);
      dados.entra = true;
      const cadastro = await lerDoc(env, `users/${uid}`);
      if (!cadastro) {
        // Entra no Authentication e não existe no banco: é o que acontece com
        // uma conta criada direto no console. Ela não aparece em Membros, e
        // por isso ninguém consegue aprová-la pelo app.
        dados.robo = 'entra, mas NÃO TEM cadastro em users';
        dados.conserto = 'o robô precisa se cadastrar pelo app (uma vez) e '
          + 'ser aprovado como líder em Membros.';
      } else if (cadastro.role !== 'admin') {
        dados.robo = `entra, e o cadastro dele está "${cadastro.role}"`;
        dados.conserto = 'as rotas de escala e agenda são só de líder: '
          + 'promova o robô a líder em Membros.';
      } else {
        dados.robo = 'entra e está líder';
      }
    } catch (e) {
      // `entra` não é recalculado aqui: ele só vira true depois do login, e é
      // justamente a diferença entre "não entra" e "entra e não lê".
      if (e instanceof RoboSemAcesso) {
        dados.robo = e.message;
        dados.conserto = e.conserto;
      } else {
        console.error('[avisos] /saude:', e?.stack ?? String(e));
        dados.robo = 'não deu para conferir';
        dados.conserto = 'o motivo está no log do Worker: '
          + 'cd worker && npx wrangler tail';
      }
    }
  }
  saudeEmCache = { em: agora, dados };
  return dados;
}

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
  // Documento ausente NÃO é falta de aprovação, e dizer que é manda a pessoa
  // procurar o líder por um problema que nenhum líder resolve: é conta do
  // Authentication sem cadastro no banco — o caso de uma conta criada direto
  // no console do Firebase, que nunca passou pelo cadastro do app, e que por
  // isso também não aparece em Membros.
  if (!cadastro) {
    return {
      erro: 'Esta conta não tem cadastro no ministério.',
      status: 403,
    };
  }
  if (!FUNCOES_APROVADAS.includes(cadastro.role)) {
    return { erro: 'Sua entrada ainda não foi aprovada por um líder.', status: 403 };
  }
  return {
    uid: dono.uid,
    nome: cadastro.name ?? '',
    lider: cadastro.role === 'admin',
  };
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

// As rotas. O `export default` no fim do arquivo é só a casca que pega o que
// escapar daqui: sem ela, um erro aqui dentro virava página de erro da
// Cloudflare, e o log do job dizia "500" sem dizer de quê.
const rotas = {
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

    // ── /saude ────────────────────────────────────────────────────────────
    //
    // A raiz diz se os SEGREDOS estão lá; isto diz se eles FUNCIONAM. A
    // diferença custou duas noites: a raiz respondia
    // `{"configurado":true,"falta":[]}` enquanto toda chamada era recusada,
    // porque ter ROBO_EMAIL preenchido não é o mesmo que o robô conseguir
    // entrar, e conseguir entrar não é o mesmo que o cadastro dele estar
    // aprovado no banco.
    //
    // Sem login, porque quem precisa dela é um job às 3 da manhã e um leigo
    // abrindo um endereço no celular. Não devolve nada sigiloso: se o robô
    // entra, e a função do cadastro DELE. O que ela custa — um login e uma
    // leitura — fica guardado por 5 minutos, senão um laço contra um endereço
    // público queimaria a cota de leitura do dia.
    if (url.pathname === '/saude' && pedido.method === 'GET') {
      return json(await saudeDoRobo(env), 200, cabecalhos);
    }

    const falta = faltaConfigurar(env);
    if (falta.length) {
      console.error('[avisos] faltam segredos:', falta.join(', '));
      return json({ erro: 'Os avisos ainda não foram configurados.' }, 503, cabecalhos);
    }

    if (pedido.method !== 'POST') {
      return json({ erro: 'não existe' }, 404, cabecalhos);
    }

    // ── "Novo pedido de entrada" ──────────────────────────────────────────
    //
    // A ÚNICA rota que atende quem NÃO está aprovado — e tem de ser: quem
    // acabou de se cadastrar está `pendente`, e é justamente desse cadastro
    // que o líder precisa saber. Por isso ela vem ANTES do `quemPediu`, que
    // recusa quem não é aprovado, com conferência própria e mais estreita.
    if (url.pathname === '/pedido') {
      const cabecalho = pedido.headers.get('Authorization') ?? '';
      if (!cabecalho.startsWith('Bearer ')) {
        return json({ erro: 'Faça login de novo.' }, 401, cabecalhos);
      }
      let quem;
      try {
        quem = await conferirToken(cabecalho.slice(7), env.FIREBASE_PROJECT_ID);
      } catch (e) {
        console.warn('[avisos] token recusado:', e.message);
        return json({ erro: 'Faça login de novo.' }, 401, cabecalhos);
      }
      if (!dentroDoLimite(quem.uid, Number(env.LIMITE_POR_MINUTO ?? 30))) {
        return json({ erro: 'Espere um minuto.' }, 429, cabecalhos);
      }

      // Só quem está ESPERANDO avisa que está esperando. Um aprovado que
      // chamasse esta rota mandaria ao líder um aviso sem pedido nenhum por
      // trás — e o líder abriria Membros para achar o nada.
      const cadastro = await lerDoc(env, `users/${quem.uid}`);
      if (!cadastro || cadastro.role !== 'pendente') {
        return json({ erro: 'não há pedido de entrada nesta conta' },
          403, cabecalhos);
      }

      // UM aviso por cadastro, para sempre, e a marca vem ANTES das leituras.
      //
      // Ela faz o papel da janela de 2 minutos das outras rotas, que aqui não
      // serviria: o único carimbo disponível é o `createdAt` do cadastro, e
      // ele vem do RELÓGIO DO APARELHO — um celular adiantado valeria por
      // dias, um atrasado nunca avisaria. A marca não depende de relógio.
      //
      // E ela é o que impede o pior caso de custo: sem marca, uma conta
      // pendente em laço faria duas leituras de coleção por chamada (~30
      // documentos) e queimaria a cota de leitura do dia. Com marca, a
      // segunda chamada custa uma leitura e volta.
      const marca = `pedidosAvisados/${quem.uid}`;
      if (await lerDoc(env, marca)) {
        return json({ jaAvisado: true }, 200, cabecalhos);
      }

      // Quem recebe é função pura e testada (`quemAvisaDoPedido`): só
      // líderes, sem robô, respeitando o liga-desliga do tipo.
      const pessoas = await lerColecao(env, 'users');
      const todas = await lerColecao(env, 'pushSubs');
      const alvos = quemAvisaDoPedido(pessoas, todas);
      const nome = String(cadastro.name ?? '').trim() || 'Alguém';

      let resultado = { enviados: 0, mortos: 0, falharam: 0 };
      if (alvos.length) {
        resultado = await espalhar(env, alvos, {
          titulo: 'Novo pedido de entrada',
          corpo: `${nome} quer entrar no ministério`,
          abrir: 'membros',
          // Etiqueta por pessoa: dois cadastros no mesmo dia são dois avisos
          // na tela, não um substituindo o outro. Perder um nome aqui seria
          // perder o pedido de alguém.
          etiqueta: `levita-pedido-${quem.uid}`,
        }, await chaveVapid(env));
      }

      // A marca é gravada mesmo quando ninguém recebeu — inclusive quando
      // nenhum líder tem aviso ligado. É a trava de custo acima; o pedido não
      // se perde, porque o selo na tela Membros não depende de notificação.
      await gravarDoc(env, marca, {
        userId: quem.uid, nome, em: new Date(), lideres: alvos.length,
      });
      return json({ ...resultado, lideres: alvos.length }, 200, cabecalhos);
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
      const alvos = todas.filter((i) => deveAvisar(i, {
        autorId: dono.uid,
        mencionados,
        tipo: 'chat',
      }));
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

    // ── "Você foi escalado" ───────────────────────────────────────────────
    //
    // Quem decide quem é recém-escalado é o APP, que sabe quem estava na
    // lista antes. Aqui se confere que esses ids estão DE FATO no culto e que
    // a escalação mudou agora — então uma lista inventada não avisa ninguém
    // que não foi escalado de verdade.
    if (url.pathname === '/escalado') {
      if (!dono.lider) {
        return json({ erro: 'Só o líder escala.' }, 403, cabecalhos);
      }
      let corpo = {};
      try { corpo = await pedido.json(); } catch (_) { /* corpo vazio */ }
      const cultoId = String(corpo.cultoId ?? '');
      if (!/^[A-Za-z0-9_-]{1,64}$/.test(cultoId)) {
        return json({ erro: 'cultoId inválido' }, 400, cabecalhos);
      }
      const novos = Array.isArray(corpo.novos)
        ? corpo.novos.filter((x) => typeof x === 'string').slice(0, 50)
        : [];
      if (!novos.length) return json({ enviados: 0 }, 200, cabecalhos);

      const culto = await lerDoc(env, `scales/${cultoId}`);
      if (!culto) return json({ erro: 'culto não existe' }, 404, cabecalhos);

      const mexido = Date.parse(culto.levitasEm ?? '');
      if (Number.isNaN(mexido) || Date.now() - mexido > JANELA_DO_AVISO_MS) {
        // A mesma trava do chat: sem ela, o id de um culto antigo — que todo
        // aprovado lê — reavisaria o ministério a qualquer momento.
        return json({ erro: 'a escala não mudou agora' }, 409, cabecalhos);
      }

      // Só quem está na escala, e com a função que ficou lá.
      const escalados = Array.isArray(culto.levitas) ? culto.levitas : [];
      const funcaoDe = new Map();
      for (const l of escalados) {
        if (l && typeof l.userId === 'string') {
          funcaoDe.set(l.userId, l.instrument ?? '');
        }
      }
      const alvosId = novos.filter((id) => funcaoDe.has(id));
      if (!alvosId.length) {
        return json({ enviados: 0, foraDaEscala: true }, 200, cabecalhos);
      }

      const todas = await lerColecao(env, 'pushSubs');
      const vapid = await chaveVapid(env);
      let total = { enviados: 0, mortos: 0, falharam: 0 };

      // Um envio por pessoa, porque o texto traz a FUNÇÃO dela naquele culto.
      for (const id of alvosId) {
        const seus = todas.filter((i) => i.userId === id &&
          deveAvisar(i, { autorId: dono.uid, tipo: 'escalado' }));
        if (!seus.length) continue;
        const r = await espalhar(env, seus, {
          ...textoDeEscalado(culto, funcaoDe.get(id)),
          abrir: 'culto',
          cultoId,
        }, vapid);
        total = {
          enviados: total.enviados + r.enviados,
          mortos: total.mortos + r.mortos,
          falharam: total.falharam + r.falharam,
        };
      }
      return json(total, 200, cabecalhos);
    }

    // ── Lembrete da véspera ───────────────────────────────────────────────
    //
    // Chamado uma vez por dia pelo job do GitHub Actions, que entra como o
    // robô líder — a mesma conta da faxina do chat. Não há segredo novo: o
    // robô prova quem é com o ID token do Firebase, como qualquer pessoa.
    if (url.pathname === '/vespera') {
      if (!dono.lider) {
        return json({ erro: 'Só o líder dispara o lembrete.' }, 403, cabecalhos);
      }
      let corpo = {};
      try { corpo = await pedido.json(); } catch (_) { /* corpo vazio */ }

      // De 00:00 a 00:00 do dia seguinte, em Brasília (UTC-3). O fuso é fixo
      // de propósito: a igreja é uma só, e "amanhã" é o amanhã dela — não o
      // do datacenter onde o Worker acordou.
      const agora = new Date();
      const amanhaBr = new Date(agora.getTime() + 86400000);
      const dia = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'America/Sao_Paulo',
        year: 'numeric', month: '2-digit', day: '2-digit',
      }).format(amanhaBr);
      const de = new Date(`${dia}T00:00:00-03:00`);
      const ate = new Date(de.getTime() + 86400000);

      // Trava de uma vez por dia: o job pode rodar duas vezes (nova
      // tentativa, disparo à mão) e ninguém merece dois lembretes.
      const trava = `avisosDaVespera/${dia}`;
      if (corpo.forcar !== true) {
        const jaFoi = await lerDoc(env, trava);
        if (jaFoi) {
          return json({ jaEnviado: true, dia }, 200, cabecalhos);
        }
      }

      const cultos = await consultarPorData(env, 'scales', 'date', de, ate);
      const doDia = cultos.filter((c) => c.canceled !== true);
      if (!doDia.length) {
        await gravarDoc(env, trava, { dia, cultos: 0, em: new Date() });
        return json({ dia, cultos: 0, enviados: 0 }, 200, cabecalhos);
      }

      const todas = await lerColecao(env, 'pushSubs');
      const vapid = await chaveVapid(env);
      // Nome das músicas, lido uma vez por música em todos os cultos do dia.
      const nomes = new Map();
      for (const culto of doDia) {
        for (const ref of (Array.isArray(culto.songs) ? culto.songs : [])) {
          const id = ref && ref.songId;
          if (typeof id === 'string' && id && !nomes.has(id)) {
            const musica = await lerDoc(env, `songs/${id}`);
            nomes.set(id, musica?.name ?? '');
          }
        }
      }

      let total = { enviados: 0, mortos: 0, falharam: 0 };
      let pessoas = 0;
      for (const culto of doDia) {
        const musicas = (Array.isArray(culto.songs) ? culto.songs : [])
          .map((ref) => nomes.get(ref && ref.songId) || '')
          .filter(Boolean);
        for (const l of (Array.isArray(culto.levitas) ? culto.levitas : [])) {
          if (!l || typeof l.userId !== 'string') continue;
          const seus = todas.filter((i) => i.userId === l.userId &&
            deveAvisar(i, { tipo: 'vespera' }));
          if (!seus.length) continue;
          pessoas++;
          const r = await espalhar(env, seus, {
            ...textoDaVespera({
              culto,
              confirmado: l.confirmed === true,
              musicas,
            }),
            abrir: 'culto',
            cultoId: culto._id,
          }, vapid);
          total = {
            enviados: total.enviados + r.enviados,
            mortos: total.mortos + r.mortos,
            falharam: total.falharam + r.falharam,
          };
        }
      }

      await gravarDoc(env, trava,
        { dia, cultos: doDia.length, pessoas, em: new Date() });
      return json({ dia, cultos: doDia.length, pessoas, ...total },
        200, cabecalhos);
    }

    // ── Testar nos próprios aparelhos ──────────────────────────────────────
    // ── "Ana confirmou" / "Ana não vai poder ir" ──────────────────────────
    //
    // Quem chama é a própria pessoa, logo depois de confirmar. O aviso vai só
    // para os líderes: são eles que remontam a escala quando alguém desmarca.
    if (url.pathname === '/confirmou') {
      let corpo = {};
      try { corpo = await pedido.json(); } catch (_) { /* corpo vazio */ }
      const cultoId = String(corpo.cultoId ?? '');
      if (!/^[A-Za-z0-9_-]{1,64}$/.test(cultoId)) {
        return json({ erro: 'cultoId inválido' }, 400, cabecalhos);
      }

      const culto = await lerDoc(env, `scales/${cultoId}`);
      if (!culto) return json({ erro: 'culto não existe' }, 404, cabecalhos);

      // Três conferências, as mesmas do chat em espírito: a pessoa está DE
      // FATO escalada, o estado que ela diz é o que está gravado, e a
      // confirmação é de agora.
      const levitas = Array.isArray(culto.levitas) ? culto.levitas : [];
      const meu = levitas.find((l) => l && l.userId === dono.uid);
      if (!meu) {
        return json({ erro: 'você não está nesta escala' }, 403, cabecalhos);
      }
      // Lê do DOCUMENTO, não do corpo do pedido: assim o texto do aviso não
      // pode dizer o contrário do que está gravado.
      const confirmou = meu.confirmed === true;

      const quando = Date.parse(culto.confirmadoEm ?? '');
      if (Number.isNaN(quando) || Date.now() - quando > JANELA_DO_AVISO_MS) {
        // Sem o carimbo recente, o id de um culto antigo — que todo aprovado
        // lê — reavisaria o líder a qualquer momento.
        return json({ erro: 'confirmação antiga demais para avisar' },
          409, cabecalhos);
      }

      const pessoas = await lerColecao(env, 'users');
      const todas = await lerColecao(env, 'pushSubs');
      const alvos = lideresInscritos(pessoas, todas, {
        tipo: 'confirmacao',
        // Um líder que confirma a própria presença não se avisa.
        excluirId: dono.uid,
      });
      if (!alvos.length) {
        return json({ enviados: 0, ninguem: true }, 200, cabecalhos);
      }

      const resultado = await espalhar(env, alvos, {
        ...textoDaConfirmacao({
          nome: dono.nome, culto, confirmou,
        }),
        abrir: 'culto',
        cultoId,
        // Confirmação pode ser substituída: o líder só precisa saber que
        // mexeu, e a contagem está no app. DESMARCAR não: é um instrumento
        // faltando no domingo, e perder um nome aí seria perder a única
        // notícia que pede ação.
        etiqueta: confirmou
          ? `levita-confirma-${cultoId}`
          : `levita-desmarca-${cultoId}-${dono.uid}`,
      }, await chaveVapid(env));

      return json({ ...resultado, confirmou }, 200, cabecalhos);
    }

    // ── Gerar os cultos da agenda fixa ────────────────────────────────────
    //
    // A mesma conta roda no app quando um líder o abre. O problema é esse: se
    // nenhum líder abrir o app por algumas semanas, os cultos param de ser
    // criados e a escala seca sem ninguém perceber. Aqui ela roda uma vez por
    // dia, sem depender de ninguém.
    if (url.pathname === '/agenda') {
      if (!dono.lider) {
        return json({ erro: 'Só o líder gera a agenda.' }, 403, cabecalhos);
      }
      let corpo = {};
      try { corpo = await pedido.json(); } catch (_) { /* corpo vazio */ }
      const semanas = Math.min(Math.max(Number(corpo.semanas ?? 4) || 4, 1), 8);

      const agenda = await lerDoc(env, 'config/agendaFixa');
      const slots = Array.isArray(agenda?.slots) ? agenda.slots : [];
      if (!slots.length) {
        // Agenda fixa não configurada é o estado normal de um ministério que
        // ainda não a usa: resposta tranquila, não erro.
        return json({ semSlots: true, criados: 0 }, 200, cabecalhos);
      }

      // Os cultos que JÁ existem, por consulta de data — não a coleção
      // inteira. Um ano são ~260 cultos, e listar todos custaria 260 leituras
      // por dia para olhar as próximas 4 semanas. Cancelado conta como
      // existente, de propósito: ele não volta a ser criado.
      const agora = agoraEmBrasilia();
      const de = instanteDe({ ...agora, hora: 0, minuto: 0 });
      const ate = instanteDe({ ...somarDias(agora, 7 * semanas + 1),
        hora: 0, minuto: 0 });
      const existentes = await consultarPorData(env, 'scales', 'date', de, ate);

      const equipes = {};
      for (const e of await lerColecao(env, 'teams')) equipes[e._id] = e;

      const aCriar = cultosFaltando({
        slots,
        equipes,
        existentes: existentes.map((c) => c._id),
        semanas,
        criadoPor: dono.uid,
      });

      let criados = 0;
      let jaExistiam = 0;
      const falhas = [];
      for (const culto of aCriar) {
        try {
          const novo = await criarDocSeNaoExiste(
            env, `scales/${culto.id}`, culto.campos);
          if (novo) criados++;
          else jaExistiam++;
        } catch (e) {
          // Uma falha não para o resto: amanhã tenta de novo, e os cultos que
          // deram certo já estão lá. Parar no primeiro erro deixaria a escala
          // com um buraco no meio.
          falhas.push(`${culto.id}: ${e.message}`);
        }
      }

      return json({
        criados,
        jaExistiam,
        pretendidos: aCriar.length,
        falhas: falhas.slice(0, 5),
      }, 200, cabecalhos);
    }

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

export default {
  async fetch(pedido, env) {
    try {
      return await rotas.fetch(pedido, env);
    } catch (e) {
      const cabecalhos = cors(env, pedido);
      if (e instanceof RoboSemAcesso) {
        // 503, e não 403: o problema é do servidor de avisos, não de quem
        // pediu. Devolver 403 aqui é o que fazia o líder ler que ele não
        // estava aprovado.
        console.error('[avisos]', e.message, '| CONSERTO:', e.conserto);
        return json({ erro: e.message, conserto: e.conserto }, 503, cabecalhos);
      }
      // O motivo exato fica no log do Worker; a resposta não o repete, porque
      // ela aparece na tela de quem tocou em "Testar aviso".
      console.error('[avisos] erro não tratado:', e?.stack ?? String(e));
      return json({ erro: 'Erro no servidor de avisos.' }, 500, cabecalhos);
    }
  },
};
