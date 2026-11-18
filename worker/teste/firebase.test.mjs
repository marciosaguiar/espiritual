// A conversa do Worker com o Firestore.
//
// POR QUE ESTE ARQUIVO EXISTE
//
// Era o ÚNICO arquivo do Worker sem teste nenhum — e era justamente o que
// fala com o banco. O defeito que ele deixou passar custou duas noites de
// rotina falhando sem dizer nada: `lerDoc` devolvia `null` tanto para "o
// documento não existe" quanto para "o Firestore RECUSOU a leitura", e quem
// chamava traduzia o `null` para "Sua entrada ainda não foi aprovada por um
// líder".
//
// O resultado era uma frase sobre QUEM PEDIU para um problema do cadastro do
// ROBÔ: o líder lia que não estava aprovado enquanto a tela dele mostrava
// 👑 Líder. Nenhum teste podia pegar isso, porque não havia teste.
//
// Não precisa de emulador nem de Flutter: o `fetch` é trocado por um de
// mentira, e o que se mede é a tradução de status para erro.

import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  lerDoc, lerColecao, apagarDoc, uidDoRobo, simplificar, limparCaches,
  RoboSemAcesso,
} from '../src/firebase.js';

const ENV = {
  FIREBASE_API_KEY: 'chave-de-teste',
  FIREBASE_PROJECT_ID: 'projeto-de-teste',
  ROBO_EMAIL: 'robo@teste',
  ROBO_SENHA: 'senha',
};

const LOGIN_OK = JSON.stringify({
  idToken: 'token-do-robo', expiresIn: '3600', localId: 'uid-do-robo',
});

/// Troca o `fetch` global por um que responde conforme a função dada.
function fingirFetch(responder) {
  globalThis.fetch = async (url, opcoes) => {
    const r = responder(String(url), opcoes ?? {});
    return new Response(r.corpo ?? '', { status: r.status ?? 200 });
  };
}

/// Responde o login do robô e deixa o resto com `aoBanco`.
function roboEntra(aoBanco) {
  fingirFetch((url, opcoes) => {
    if (url.includes('identitytoolkit')) return { status: 200, corpo: LOGIN_OK };
    return aoBanco(url, opcoes);
  });
}

/// O erro que a chamada levantou.
///
/// `assert.rejects` não devolve o erro, e é dentro dele que está tudo o que
/// importa aqui: a classe, a mensagem e o conserto.
async function erroDe(chamada) {
  try {
    await chamada();
  } catch (e) {
    return e;
  }
  assert.fail('não levantou erro nenhum');
}

function doc(campos) {
  return JSON.stringify({
    name: 'projects/p/databases/(default)/documents/users/uid-1',
    fields: campos,
  });
}

// A sessão do robô fica guardada entre chamadas, como no Worker de verdade.
// Sem limpar, o segundo caso reusaria o token do primeiro e nunca passaria
// pelo login.
beforeEach(() => limparCaches());

test('documento que não existe vale null', async () => {
  roboEntra(() => ({ status: 404, corpo: '{}' }));
  assert.equal(await lerDoc(ENV, 'users/ninguem'), null);
});

test('leitura RECUSADA não vale null, e não fala de aprovação', async () => {
  // O defeito inteiro em um teste. 403 é o Firestore dizendo que o ROBÔ não
  // pode ler — não que a pessoa esteja esperando aprovação.
  roboEntra(() => ({ status: 403, corpo: '{}' }));
  const e = await erroDe(() => lerDoc(ENV, 'users/uid-1'));
  assert.ok(e instanceof RoboSemAcesso, `veio ${e.name}: ${e.message}`);
  assert.match(e.message, /robô/i);
  assert.doesNotMatch(e.message, /aprovad/i);
});

test('o conserto da recusa aponta a Cloudflare, não o Membros de quem pediu',
  async () => {
    // Ler `users` exige `souEu(userId) || aprovado()`: com robô e chamador
    // sendo contas diferentes, quem precisa estar aprovado é o ROBÔ. E um
    // FIREBASE_API_KEY de outro projeto dá exatamente o mesmo 403.
    roboEntra(() => ({ status: 403, corpo: '{}' }));
    const e = await erroDe(() => lerDoc(ENV, 'users/uid-1'));
    assert.match(e.conserto, /ROBO_EMAIL/);
    assert.match(e.conserto, /FIREBASE_PROJECT_ID/);
  });

test('listar e apagar recusados também apontam o robô', async () => {
  // Sem isto, a mesma mentira voltaria por outra porta: `apagarDoc` devolvia
  // `false` numa recusa e ninguém via, e `lerColecao` virava 500 genérico.
  roboEntra(() => ({ status: 403, corpo: '{}' }));
  const e1 = await erroDe(() => lerColecao(ENV, 'pushSubs'));
  assert.ok(e1 instanceof RoboSemAcesso, `veio ${e1.name}`);
  limparCaches();
  roboEntra(() => ({ status: 403, corpo: '{}' }));
  const e2 = await erroDe(() => apagarDoc(ENV, 'pushSubs/x'));
  assert.ok(e2 instanceof RoboSemAcesso, `veio ${e2.name}`);
});

test('inscrição que já não está lá conta como apagada', async () => {
  roboEntra(() => ({ status: 404, corpo: '{}' }));
  assert.equal(await apagarDoc(ENV, 'pushSubs/x'), true);
});

test('robô que não consegue entrar diz isso, sem repetir o Google', async () => {
  // A resposta do Google conta se o e-mail existe. Ela fica no log do Worker;
  // na mensagem que volta, nunca.
  fingirFetch((url) => {
    if (url.includes('identitytoolkit')) {
      return { status: 400, corpo: '{"error":{"message":"EMAIL_NOT_FOUND"}}' };
    }
    return { status: 200, corpo: '{}' };
  });
  const e = await erroDe(() => lerDoc(ENV, 'users/uid-1'));
  assert.ok(e instanceof RoboSemAcesso, `veio ${e.name}`);
  assert.match(e.message, /entrar/i);
  assert.doesNotMatch(e.message, /EMAIL_NOT_FOUND/);
  assert.match(e.conserto, /ROBO_SENHA/);
});

test('o uid do robô sai do próprio login', async () => {
  // É o que permite ao Worker conferir o cadastro DELE em /saude.
  roboEntra(() => ({ status: 200, corpo: '{}' }));
  assert.equal(await uidDoRobo(ENV), 'uid-do-robo');
});

test('a função chega do banco como o texto exato, sem tradução', async () => {
  // A hipótese "o papel gravado é líder e o código espera admin" morre aqui:
  // `simplificar` devolve o `stringValue` como está. Se a tela mostra
  // 👑 Líder, o documento tem "admin" literal.
  roboEntra(() => ({
    status: 200, corpo: doc({ role: { stringValue: 'admin' } }),
  }));
  const d = await lerDoc(ENV, 'users/uid-1');
  assert.equal(d.role, 'admin');
  assert.equal(d._id, 'uid-1');
});

test('simplificar não inventa função quando o campo não vem', () => {
  // Campo ausente tem de significar MENOS acesso, nunca o acesso normal — a
  // mesma regra do `?? 'levita'` que já custou caro no app.
  const d = simplificar(JSON.parse(doc({ name: { stringValue: 'Faxina' } })));
  assert.equal(d.role, undefined);
});
