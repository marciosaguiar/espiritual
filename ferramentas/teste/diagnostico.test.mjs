// O diagnóstico das rotinas diárias.
//
// Isto existe porque a rotina falhou duas noites seguidas dizendo só
// "O Worker respondeu 403". Cada status tem uma causa e um conserto
// diferentes, e nenhum deles está no código do app — estão na Cloudflare, no
// console do Firebase ou no cadastro do robô. O teste garante que cada número
// continue levando ao conserto certo.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { porQueRecusou } from '../diagnostico.mjs';

test('404 manda publicar o Worker', () => {
  // O caso mais provável depois de uma entrega: o código está no repositório
  // e a rota ainda não está no ar.
  assert.match(porQueRecusou(404, ''), /wrangler deploy/);
});

test('503 manda olhar os segredos da Cloudflare', () => {
  const r = porQueRecusou(503, '{"erro":"Os avisos ainda não foram configurados."}');
  assert.match(r, /SEM SEGREDOS/);
  assert.match(r, /VAPID_PRIVATE/);
});

test('401 aponta o projeto errado, não a senha', () => {
  // O token é válido; o que não bate é o projeto que o Worker espera.
  const r = porQueRecusou(401, '{"erro":"Faça login de novo."}');
  assert.match(r, /FIREBASE_PROJECT_ID/);
});

test('403 de "não aprovado" e 403 de "não é líder" dão consertos diferentes',
  () => {
    const naoAprovado = porQueRecusou(403,
      '{"erro":"Sua entrada ainda não foi aprovada por um líder."}');
    const naoLider = porQueRecusou(403,
      '{"erro":"Só o líder dispara o lembrete."}');
    assert.match(naoAprovado, /NÃO ESTÁ APROVADO/);
    assert.match(naoLider, /NÃO É LÍDER/);
    assert.notEqual(naoAprovado, naoLider);
  });

test('429 diz para esperar, e quando desconfiar', () => {
  assert.match(porQueRecusou(429, ''), /laço/);
});

test('500 manda ler o log do Worker, que é onde o motivo está', () => {
  assert.match(porQueRecusou(500, ''), /wrangler tail/);
});

test('status inesperado não inventa causa', () => {
  // Melhor dizer "não sei, olhe o corpo" que apontar o conserto errado.
  const r = porQueRecusou(418, 'sou um bule');
  assert.match(r, /inesperado/);
});

test('todo status conhecido devolve texto útil, nunca vazio', () => {
  for (const s of [401, 403, 404, 429, 500, 502, 503, 418]) {
    const r = porQueRecusou(s, '');
    assert.ok(r.length > 40, `status ${s} devolveu "${r}"`);
  }
});
