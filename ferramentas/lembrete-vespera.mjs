// Dispara o lembrete da véspera: avisa quem está escalado para amanhã.
//
// O QUE ESTE SCRIPT FAZ, E O QUE ELE NÃO FAZ
//
// Ele NÃO manda notificação. Quem manda é o Worker da Cloudflare, porque é
// lá que mora a chave privada do VAPID — e ela fica num lugar só. Este
// script é só o despertador: entra como o robô líder, prova quem é, e chama
// a rota `/vespera`. Toda a decisão (quais cultos são amanhã, quem está
// escalado, quem já confirmou, o texto) é do Worker.
//
// POR QUE NÃO HÁ SEGREDO NOVO
//
// O robô se identifica com o ID token do Firebase, igual a qualquer pessoa —
// as mesmas credenciais que a faxina do chat já usa. Um segredo
// compartilhado entre o GitHub e a Cloudflare seria uma coisa a mais para
// vazar, girar e esquecer.
//
// E O ENDEREÇO DO WORKER SAI DO PRÓPRIO REPOSITÓRIO
//
// Ele está em `lib/core/constants/avisos_config.dart`, commitado, porque é
// público por natureza. Lê-se dali em vez de pedir mais um segredo: assim,
// trocar o Worker no app troca também para este job, sem ninguém lembrar de
// atualizar duas coisas.
//
// Sem os segredos configurados, roda, diz que não está configurado e termina
// em verde — não enche a caixa de e-mail de falha.

import { readFileSync } from 'node:fs';
import { explicarFalha } from './diagnostico.mjs';

const API_KEY = process.env.FIREBASE_API_KEY ?? '';
const EMAIL = process.env.FAXINA_EMAIL ?? '';
const SENHA = process.env.FAXINA_SENHA ?? '';

if (!API_KEY || !EMAIL || !SENHA) {
  console.log('Lembrete da véspera: segredos não configurados — nada a fazer.');
  console.log('Faltando: ' + [
    !API_KEY && 'FIREBASE_API_KEY',
    !EMAIL && 'FAXINA_EMAIL',
    !SENHA && 'FAXINA_SENHA',
  ].filter(Boolean).join(', '));
  process.exit(0);
}

/// O endereço do Worker, lido do arquivo de configuração do app.
function enderecoDoWorker() {
  const caminho = new URL(
    '../lib/core/constants/avisos_config.dart', import.meta.url);
  const dart = readFileSync(caminho, 'utf8');
  const m = /worker\s*=\s*'([^']+)'/.exec(dart);
  const url = m ? m[1] : '';
  if (!url || url.includes('COLE-AQUI')) return '';
  return url.replace(/\/+$/, '');
}

const worker = enderecoDoWorker();
if (!worker) {
  console.log('Lembrete da véspera: o endereço do Worker ainda não foi '
    + 'preenchido em lib/core/constants/avisos_config.dart — nada a fazer.');
  process.exit(0);
}

// 1. Entrar como o robô líder.
const entrada = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: EMAIL, password: SENHA, returnSecureToken: true,
    }),
  },
);
if (!entrada.ok) {
  // O corpo da resposta diz se o e-mail existe; fica fora do log.
  console.error(`O robô não conseguiu entrar (${entrada.status}).`);
  console.error('');
  console.error('CAUSA PROVÁVEL: e-mail ou senha do robô errados nos '
    + 'segredos do GitHub (FAXINA_EMAIL, FAXINA_SENHA), ou a conta dele não '
    + 'existe mais no Firebase Authentication. São os MESMOS segredos da '
    + 'faxina do chat: se aquela rotina está passando, não é isto.');
  process.exit(1);
}
const { idToken } = await entrada.json();

// 2. Pedir ao Worker que mande os lembretes.
const resposta = await fetch(`${worker}/vespera`, {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${idToken}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({}),
});
const texto = await resposta.text();

if (!resposta.ok) {
  // Status não é diagnóstico: cada número tem uma causa e um conserto
  // diferentes, nenhum deles no código do app.
  await explicarFalha(worker, resposta.status, texto);
  process.exit(1);
}

const r = JSON.parse(texto);
if (r.jaEnviado) {
  // A trava de uma vez por dia. Rodar de novo não manda dois lembretes.
  console.log(`Lembrete de ${r.dia} já havia sido enviado hoje. Nada a fazer.`);
} else {
  console.log(`Lembrete de ${r.dia}: ${r.cultos ?? 0} culto(s), `
    + `${r.pessoas ?? 0} pessoa(s), ${r.enviados ?? 0} aviso(s) entregue(s), `
    + `${r.falharam ?? 0} falha(s), ${r.mortos ?? 0} inscrição(ões) morta(s).`);
}
