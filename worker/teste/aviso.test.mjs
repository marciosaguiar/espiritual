import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  textoDoAviso, textoDeEscalado, textoDaVespera, quandoEhOCulto,
  deveAvisar, dentroDoLimite, esquecerLimites, quemAvisaDoPedido,
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
  assert.equal(
    deveAvisar(inscricao({ userId: 'u1' }), { autorId: 'u1' }), false);
  assert.equal(
    deveAvisar(inscricao({ userId: 'u2' }), { autorId: 'u1' }), true);
});

test('avisos desligados: não recebe', () => {
  assert.equal(
    deveAvisar(inscricao({ avisosLigados: false }), { autorId: 'u1' }), false);
  assert.equal(
    deveAvisar(inscricao({ avisosLigados: true }), { autorId: 'u1' }), true);
  // Campo faltando é inscrição antiga, de antes do liga-desliga: recebe.
  assert.equal(deveAvisar(inscricao(), { autorId: 'u1' }), true);
});

test('silêncio vale até a hora marcada, e não depois', () => {
  const agora = Date.UTC(2026, 10, 16, 22, 0, 0);
  const amanha = new Date(Date.UTC(2026, 10, 17, 10, 0, 0)).toISOString();
  const ontem = new Date(Date.UTC(2026, 10, 15, 10, 0, 0)).toISOString();
  assert.equal(deveAvisar(inscricao({ silenciarAte: amanha }), { autorId: 'u1', agoraMs: agora }), false);
  assert.equal(deveAvisar(inscricao({ silenciarAte: ontem }), { autorId: 'u1', agoraMs: agora }), true);
  // Data estragada não pode virar silêncio para sempre.
  assert.equal(deveAvisar(inscricao({ silenciarAte: 'qualquer coisa' }), { autorId: 'u1', agoraMs: agora }), true);
});

test('inscrição sem as chaves é descartada antes de tentar cifrar', () => {
  assert.equal(deveAvisar(inscricao, { autorId: 'u1' }), false);
  assert.equal(deveAvisar(inscricao, { autorId: 'u1' }), false);
  assert.equal(deveAvisar(null, { autorId: 'u1' }), false);
});

// ── Menção: fura o silêncio, mas não o desligado ────────────────────────────

test('mencionado recebe mesmo com o chat silenciado até amanhã', () => {
  // "Silenciar até amanhã" é "não me acorde por bobagem", não "não me
  // chame" — o caso de "@Ana, você consegue vir às 18h?" na véspera.
  const agora = Date.UTC(2026, 10, 16, 22, 0, 0);
  const amanha = new Date(Date.UTC(2026, 10, 17, 10, 0, 0)).toISOString();
  const i = inscricao({ silenciarAte: amanha });
  assert.equal(deveAvisar(i, { autorId: 'u1', agoraMs: agora }), false);
  assert.equal(deveAvisar(i, { autorId: 'u1', agoraMs: agora, mencionados: ['u2'] }), true);
});

test('avisos DESLIGADOS continuam desligados, mesmo mencionada', () => {
  // Quem desligou fez uma escolha sobre o app todo; furá-la seria o app
  // decidindo por cima da pessoa, e ela não teria como se proteger a não ser
  // desinstalando.
  const i = inscricao({ avisosLigados: false });
  assert.equal(deveAvisar(i, { autorId: 'u1', mencionados: ['u2'] }), false);
});

test('menção de outra pessoa não libera o meu silêncio', () => {
  const agora = Date.UTC(2026, 10, 16, 22, 0, 0);
  const amanha = new Date(Date.UTC(2026, 10, 17, 10, 0, 0)).toISOString();
  const i = inscricao({ silenciarAte: amanha });
  assert.equal(deveAvisar(i, { autorId: 'u1', agoraMs: agora, mencionados: ['u9'] }), false);
});

test('o autor não recebe nem se mencionar a si mesmo', () => {
  const i = inscricao({ userId: 'u1' });
  assert.equal(deveAvisar(i, { autorId: 'u1', mencionados: ['u1'] }), false);
});

test('lista de menções estragada não derruba o envio', () => {
  const i = inscricao();
  for (const ruim of [null, 'u2', 42, {}]) {
    assert.equal(deveAvisar(i, { autorId: 'u1', mencionados: ruim }), true);
  }
});

test('o texto de quem foi mencionado diz que foi', () => {
  const m = { userName: 'Márcio', text: 'você consegue vir às 18h?' };
  assert.deepEqual(textoDoAviso(m, { mencionou: true }), {
    titulo: 'Márcio',
    corpo: '📣 mencionou você: você consegue vir às 18h?',
  });
  // E o texto normal continua igual, para quem não foi mencionado.
  assert.deepEqual(textoDoAviso(m), {
    titulo: 'Márcio',
    corpo: 'você consegue vir às 18h?',
  });
});

test('menção em mensagem de voz também se anuncia', () => {
  const r = textoDoAviso({ userName: 'Ana', audioId: 'a1' },
    { mencionou: true });
  assert.match(r.corpo, /mencionou você/);
  assert.match(r.corpo, /🎤/);
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

// ── Tipos de aviso, "você foi escalado" e o lembrete da véspera ─────────────

test('cada tipo se liga à parte', () => {
  const so = (tipos) => inscricao({ tipos });
  assert.equal(deveAvisar(so({ chat: false }), { tipo: 'chat' }), false);
  assert.equal(deveAvisar(so({ chat: false }), { tipo: 'escalado' }), true);
  assert.equal(deveAvisar(so({ escalado: false }), { tipo: 'escalado' }), false);
  assert.equal(deveAvisar(so({ vespera: false }), { tipo: 'vespera' }), false);
  assert.equal(deveAvisar(so({ vespera: false }), { tipo: 'chat' }), true);
});

test('CHAVE AUSENTE É LIGADA — aparelho inscrito antes da mudança', () => {
  // Se a falta valesse como "desligado", o ministério inteiro pararia de
  // receber aviso de uma hora para outra, sem ninguém ter mexido em nada.
  assert.equal(deveAvisar(inscricao(), { tipo: 'escalado' }), true);
  assert.equal(deveAvisar(inscricao({ tipos: {} }), { tipo: 'vespera' }), true);
  for (const lixo of [null, 'chat', 42, []]) {
    assert.equal(deveAvisar(inscricao({ tipos: lixo }), { tipo: 'chat' }), true,
      `tipos: ${JSON.stringify(lixo)}`);
  }
});

test('o liga-desliga geral continua acima dos tipos', () => {
  assert.equal(
    deveAvisar(inscricao({ avisosLigados: false, tipos: { escalado: true } }),
      { tipo: 'escalado' }),
    false);
});

test('a hora do culto sai no fuso de Brasília, não do servidor', () => {
  // O Worker roda em qualquer lugar do mundo. Um culto de domingo 19h em
  // Brasília apareceria como sábado 22h para metade do ministério se a hora
  // saísse do relógio dele.
  const domingo19h = '2026-11-22T22:00:00.000Z'; // 19h em Brasília (UTC-3)
  // Quarta-feira: longe o bastante para não cair em "amanhã".
  const quarta = Date.parse('2026-11-18T15:00:00.000Z');
  assert.equal(quandoEhOCulto(domingo19h, quarta), 'domingo, 22/11 às 19:00');

  // E a virada do dia pelo fuso: 23h em Brasília é 02h do dia seguinte em
  // UTC. Sem o fuso fixo, este culto apareceria no dia errado.
  const sabado23h = '2026-11-22T02:00:00.000Z';
  assert.equal(quandoEhOCulto(sabado23h, quarta), 'sábado, 21/11 às 23:00');
});

test('"amanhã" e "hoje" em vez da data', () => {
  const domingo8h = '2026-11-22T11:00:00.000Z'; // 8h em Brasília
  const sabadoTarde = Date.parse('2026-11-21T20:00:00.000Z');
  assert.equal(quandoEhOCulto(domingo8h, sabadoTarde), 'amanhã às 08:00');
  const domingoCedo = Date.parse('2026-11-22T09:00:00.000Z');
  assert.equal(quandoEhOCulto(domingo8h, domingoCedo), 'hoje às 08:00');
});

test('data estragada não derruba o aviso', () => {
  assert.equal(quandoEhOCulto('nunca'), '');
  assert.equal(quandoEhOCulto(undefined), '');
});

test('"você foi escalado" diz o culto, quando, e a função', () => {
  const culto = { serviceType: 'Culto', date: '2026-11-22T22:00:00.000Z' };
  const agora = Date.parse('2026-11-21T15:00:00.000Z');
  assert.deepEqual(textoDeEscalado(culto, 'teclado', agora), {
    titulo: 'Você foi escalado',
    corpo: 'Culto amanhã às 19:00 · teclado',
  });
  // Sem função, não sobra um " · " solto no fim.
  assert.equal(textoDeEscalado(culto, '', agora).corpo, 'Culto amanhã às 19:00');
});

test('o lembrete da véspera pede confirmação de quem não confirmou', () => {
  const culto = { serviceType: 'Culto', date: '2026-11-22T22:00:00.000Z' };
  const agora = Date.parse('2026-11-21T20:00:00.000Z');
  const naoConfirmou = textoDaVespera({
    culto, confirmado: false, musicas: ['Bondade de Deus'], agoraMs: agora,
  });
  assert.equal(naoConfirmou.titulo, 'Confirme sua presença');
  assert.match(naoConfirmou.corpo, /Toque para confirmar/);
  // E o pedido vem no FIM: é a parte que pede ação.
  assert.ok(naoConfirmou.corpo.endsWith('Toque para confirmar sua presença'));

  const confirmou = textoDaVespera({
    culto, confirmado: true, musicas: ['Bondade de Deus'], agoraMs: agora,
  });
  assert.equal(confirmou.titulo, 'Lembrete do culto');
  assert.doesNotMatch(confirmou.corpo, /confirmar/);
});

test('o lembrete traz as músicas, e corta a lista longa', () => {
  const culto = { serviceType: 'Culto', date: '2026-11-22T22:00:00.000Z' };
  const agora = Date.parse('2026-11-21T20:00:00.000Z');
  const r = textoDaVespera({
    culto,
    confirmado: true,
    musicas: ['Uma', 'Duas', 'Três', 'Quatro', 'Cinco'],
    agoraMs: agora,
  });
  assert.match(r.corpo, /🎵 Uma, Duas, Três \+2/);
});

test('culto sem música não deixa um "🎵" vazio', () => {
  const r = textoDaVespera({
    culto: { serviceType: 'Ensaio', date: '2026-11-22T22:00:00.000Z' },
    confirmado: true,
    musicas: [],
    agoraMs: Date.parse('2026-11-21T20:00:00.000Z'),
  });
  assert.doesNotMatch(r.corpo, /🎵/);
  assert.match(r.corpo, /^Ensaio amanhã/);
});

test('culto sem tipo escrito vira "Culto"', () => {
  const agora = Date.parse('2026-11-21T20:00:00.000Z');
  assert.match(
    textoDaVespera({ culto: { date: '2026-11-22T22:00:00.000Z' },
      confirmado: true, agoraMs: agora }).corpo,
    /^Culto /);
});


// ── Quem recebe "novo pedido de entrada" ────────────────────────────────────
//
// Esta é a parte que erra em silêncio: mandar para o ministério inteiro, ou
// para ninguém, dá a mesma resposta no fim. Daí os testes serem sobre quem
// sobra na lista.

const PESSOAS = [
  { _id: 'lider1', role: 'admin' },
  { _id: 'lider2', role: 'admin' },
  { _id: 'levita1', role: 'levita' },
  { _id: 'pendente1', role: 'pendente' },
  { _id: 'removido1', role: 'removido' },
  { _id: 'robo', role: 'admin', bot: true },
];

function sub(userId, extra = {}) {
  return {
    _id: `s-${userId}`, userId,
    endpoint: 'https://push.exemplo/x', p256dh: 'p', auth: 'a',
    ...extra,
  };
}

test('só os líderes recebem', () => {
  const alvos = quemAvisaDoPedido(PESSOAS, [
    sub('lider1'), sub('lider2'), sub('levita1'),
    sub('pendente1'), sub('removido1'),
  ]);
  assert.deepEqual(alvos.map((i) => i.userId), ['lider1', 'lider2']);
});

test('o robô não recebe, mesmo sendo admin', () => {
  // Ele é líder no banco porque é assim que entra, sem chave de
  // administrador. Mas não usa o app: um aviso para ele é um aviso perdido.
  const alvos = quemAvisaDoPedido(PESSOAS, [sub('robo'), sub('lider1')]);
  assert.deepEqual(alvos.map((i) => i.userId), ['lider1']);
});

test('líder antigo, sem o campo bot, continua recebendo', () => {
  // `bot !== true` e não `!bot`: cadastro antigo não tem o campo, e tratá-lo
  // como robô deixaria justamente os líderes humanos de fora.
  const alvos = quemAvisaDoPedido([{ _id: 'lider1', role: 'admin' }],
    [sub('lider1')]);
  assert.equal(alvos.length, 1);
});

test('líder que desligou este tipo de aviso não recebe', () => {
  const alvos = quemAvisaDoPedido(PESSOAS, [
    sub('lider1', { tipos: { pedido: false } }),
    sub('lider2'),
  ]);
  assert.deepEqual(alvos.map((i) => i.userId), ['lider2']);
});

test('CHAVE AUSENTE É LIGADA: quem tem outros tipos gravados recebe', () => {
  // Todo aparelho inscrito antes desta mudança não tem a chave `pedido`. Se a
  // falta valesse "desligado", o líder nunca saberia de cadastro novo e
  // ninguém descobriria por quê.
  const alvos = quemAvisaDoPedido(PESSOAS,
    [sub('lider1', { tipos: { chat: false, vespera: true } })]);
  assert.equal(alvos.length, 1);
});

test('líder com os avisos desligados no aparelho não recebe', () => {
  const alvos = quemAvisaDoPedido(PESSOAS,
    [sub('lider1', { avisosLigados: false })]);
  assert.equal(alvos.length, 0);
});

test('silêncio até amanhã também vale aqui', () => {
  // Pedido de entrada não é urgente: quem pediu silêncio vê pela manhã. O
  // selo na tela Membros não depende de notificação nenhuma.
  const agoraMs = Date.parse('2026-11-16T23:00:00.000Z');
  const alvos = quemAvisaDoPedido(PESSOAS,
    [sub('lider1', { silenciarAte: '2026-11-17T10:00:00.000Z' })],
    { agoraMs });
  assert.equal(alvos.length, 0);
});

test('inscrição sem chaves de cifra é descartada', () => {
  const alvos = quemAvisaDoPedido(PESSOAS,
    [{ _id: 's1', userId: 'lider1', endpoint: 'https://x' }]);
  assert.equal(alvos.length, 0);
});

test('listas vazias ou tortas não derrubam o Worker', () => {
  assert.deepEqual(quemAvisaDoPedido([], []), []);
  assert.deepEqual(quemAvisaDoPedido(null, null), []);
  assert.deepEqual(quemAvisaDoPedido(PESSOAS, [null, sub('lider1')])
    .map((i) => i.userId), ['lider1']);
});
