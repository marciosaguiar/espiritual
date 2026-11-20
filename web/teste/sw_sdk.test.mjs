// O service worker e o SDK do Firebase: o app só abre sem internet se o SDK,
// que mora em www.gstatic.com, estiver guardado no aparelho.
//
// TODO o conteúdo é inventado.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const CODIGO = readFileSync(join(AQUI, '..', 'sw.js'), 'utf8');
const SDK = 'https://www.gstatic.com/firebasejs/10.11.1/';

/// Um `caches` de mentira, com o que o service worker usa.
function cachesDeMentira() {
  const caixas = new Map();
  const caixa = (nome) => {
    if (!caixas.has(nome)) caixas.set(nome, new Map());
    const m = caixas.get(nome);
    const chave = (p) => (typeof p === 'string' ? p : p.url);
    return {
      match: async (p) => m.get(chave(p)),
      put: async (p, r) => { m.set(chave(p), r); },
      add: async (p) => { m.set(String(p), { ok: true }); },
    };
  };
  return {
    caixas,
    open: async (n) => caixa(n),
    keys: async () => [...caixas.keys()],
    delete: async (n) => caixas.delete(n),
  };
}

function montar({ rede }) {
  const ouvintes = {};
  const caches = cachesDeMentira();
  const idas = [];
  const self = {
    addEventListener: (n, f) => { (ouvintes[n] ??= []).push(f); },
    skipWaiting() {},
    location: { origin: 'https://exemplo.app' },
    registration: {},
    clients: { claim: async () => {} },
  };
  const fetch = async (p) => {
    const url = typeof p === 'string' ? p : p.url;
    idas.push(url);
    return rede(url);
  };
  new Function('self', 'caches', 'fetch', 'console', CODIGO)(
      self, caches, fetch, { warn() {}, log() {} });

  const pedir = async (url, extra = {}) => {
    let resposta;
    let tratou = false;
    const evento = {
      request: { url, method: 'GET', mode: 'cors', ...extra },
      respondWith(p) { tratou = true; resposta = p; },
    };
    for (const f of ouvintes.fetch ?? []) f(evento);
    return { tratou, resposta: tratou ? await resposta : undefined };
  };
  const disparar = async (nome) => {
    const esperas = [];
    const evento = { waitUntil: (p) => esperas.push(p) };
    for (const f of ouvintes[nome] ?? []) f(evento);
    await Promise.all(esperas);
  };
  return { caches, idas, pedir, disparar };
}

const ok = (corpo = 'codigo') => ({
  ok: true, status: 200, type: 'cors', corpo,
  clone() { return this; },
});

test('na instalação, guarda os três arquivos do SDK', async () => {
  const sw = montar({ rede: (u) => ok(u) });
  await sw.disparar('install');
  const caixa = sw.caches.caixas.get('sdk-firebase-10.11.1');
  assert.ok(caixa, 'a caixa do SDK existe');
  for (const a of ['firebase-app.js', 'firebase-auth.js', 'firebase-firestore.js']) {
    assert.ok(caixa.has(SDK + a), `${a} foi guardado`);
  }
});

test('SEM INTERNET, o SDK vem do cache (é isso que deixa o app abrir)', async () => {
  const sw = montar({ rede: (u) => ok(u) });
  await sw.disparar('install');
  sw.idas.length = 0;
  // A rede cai.
  const semRede = montar({ rede: () => { throw new Error('sem rede'); } });
  // Mesma caixa, outra "rede": copia o conteúdo guardado.
  semRede.caches.caixas.set('sdk-firebase-10.11.1', sw.caches.caixas.get('sdk-firebase-10.11.1'));
  const r = await semRede.pedir(SDK + 'firebase-app.js');
  assert.equal(r.tratou, true);
  assert.equal(r.resposta.corpo, SDK + 'firebase-app.js');
  assert.deepEqual(semRede.idas, [], 'nem tentou a rede');
});

test('o que ainda não está guardado vem da rede e passa a ficar', async () => {
  const sw = montar({ rede: (u) => ok(u) });
  const r = await sw.pedir(SDK + 'firebase-app.js');
  assert.equal(r.resposta.corpo, SDK + 'firebase-app.js');
  assert.ok(sw.caches.caixas.get('sdk-firebase-10.11.1').has(SDK + 'firebase-app.js'));
});

test('resposta que não é completa e boa NÃO vai para o cache (o cache vem '
    + 'antes da rede: uma ruim ficaria para sempre)', async () => {
  const sw = montar({ rede: () => ({ ok: false, status: 503, clone() { return this; } }) });
  await sw.pedir(SDK + 'firebase-app.js');
  assert.equal(sw.caches.caixas.get('sdk-firebase-10.11.1').has(SDK + 'firebase-app.js'), false);
  const parcial = montar({ rede: () => ({ ok: true, status: 206, clone() { return this; } }) });
  await parcial.pedir(SDK + 'firebase-app.js');
  assert.equal(parcial.caches.caixas.get('sdk-firebase-10.11.1').has(SDK + 'firebase-app.js'), false);
});

test('outro endereço de fora do domínio continua NÃO sendo tratado', async () => {
  const sw = montar({ rede: (u) => ok(u) });
  const r = await sw.pedir('https://www.gstatic.com/outra-coisa.js');
  assert.equal(r.tratou, false);
  const outra = await sw.pedir('https://www.gstatic.com/firebasejs/9.0.0/firebase-app.js');
  assert.equal(outra.tratou, false, 'outra versão não é a nossa');
  const post = await sw.pedir(SDK + 'firebase-app.js', { method: 'POST' });
  assert.equal(post.tratou, false);
});

test('trocar a versão do app NÃO apaga a caixa do SDK; versão velha do SDK sai',
    async () => {
  const sw = montar({ rede: (u) => ok(u) });
  await sw.disparar('install');
  sw.caches.caixas.set('levitasync-antiga', new Map());
  sw.caches.caixas.set('sdk-firebase-9.0.0', new Map());
  await sw.disparar('activate');
  assert.ok(sw.caches.caixas.has('sdk-firebase-10.11.1'), 'a atual fica');
  assert.equal(sw.caches.caixas.has('sdk-firebase-9.0.0'), false, 'a velha sai');
  assert.equal(sw.caches.caixas.has('levitasync-antiga'), false);
});

test('a versão do SDK é a mesma no index.html, no sw.js e no pubspec.lock', () => {
  const index = readFileSync(join(AQUI, '..', 'index.html'), 'utf8');
  const lock = readFileSync(join(AQUI, '..', '..', 'pubspec.lock'), 'utf8');
  const noIndex = [...index.matchAll(/firebasejs\/([0-9.]+)\//g)].map((m) => m[1]);
  const noSw = /VERSAO_DO_SDK = '([0-9.]+)'/.exec(CODIGO)[1];
  const bloco = /firebase_core_web:[\s\S]*?version: "([0-9.]+)"/.exec(lock)[1];
  assert.ok(noIndex.length >= 3);
  for (const v of noIndex) assert.equal(v, noSw, 'index.html e sw.js dizem a mesma versão');
  // firebase_core_web 2.17.5 traz o SDK 10.11.1 (ver o comentário do index.html).
  assert.equal(bloco, '2.17.5', 'o lock mudou: confira a versão do SDK e atualize os três lugares');
});

test('navegar para uma IMAGEM não troca o index.html guardado (o app abriria '
    + 'como imagem, para sempre)', async () => {
  const sw = montar({
    rede: (u) => ({
      ok: true, status: 200, type: 'basic', corpo: u,
      headers: { get: (h) => (u.endsWith('.png') ? 'image/png' : 'text/html; charset=utf-8') },
      clone() { return this; },
    }),
  });
  const caixa = await sw.caches.open('levitasync-desenvolvimento');
  await caixa.put('index.html', { corpo: 'APP', ok: true });
  await sw.pedir('https://exemplo.app/icons/Icon-192.png', { mode: 'navigate' });
  await new Promise((r) => setTimeout(r, 20));
  assert.equal((await caixa.match('index.html')).corpo, 'APP');
  // E uma página HTML de verdade continua atualizando o guardado.
  await sw.pedir('https://exemplo.app/', { mode: 'navigate' });
  await new Promise((r) => setTimeout(r, 20));
  assert.equal((await caixa.match('index.html')).corpo, 'https://exemplo.app/');
});
