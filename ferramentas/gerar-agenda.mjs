// Cria os cultos da agenda fixa que ainda não existem.
//
// POR QUE ISTO EXISTE
//
// O app já faz isso: quando um líder abre o app, ele cria os cultos das
// próximas 4 semanas que estão faltando. A fragilidade era justamente essa —
// se nenhum líder abrisse o app por algumas semanas, os cultos paravam de ser
// criados e a escala secava sem ninguém perceber. Férias, viagem, um mês
// corrido: a escala simplesmente não existia mais.
//
// Agora roda todo dia, sem depender de ninguém.
//
// O QUE ESTE SCRIPT FAZ, E O QUE ELE NÃO FAZ
//
// Ele NÃO cria culto nenhum. Quem cria é o Worker da Cloudflare, que entra
// com a conta do robô líder e tem a conta da agenda escrita em
// `worker/src/agenda.js`. Este script é só o despertador: entra como o robô,
// prova quem é, e chama a rota `/agenda`.
//
// POR QUE NÃO HÁ SEGREDO NOVO
//
// O robô se identifica com o ID token do Firebase, as mesmas credenciais que
// a faxina do chat e o lembrete da véspera já usam. E o endereço do Worker
// sai de `lib/core/constants/avisos_config.dart`, que está no repositório
// porque é público por natureza.
//
// Sem os segredos configurados, roda, diz que não está configurado e termina
// em verde — não enche a caixa de e-mail de falha.

import { readFileSync } from 'node:fs';
import { explicarFalha } from './diagnostico.mjs';
import { carimbarEDizer } from './carimbo.mjs';

const API_KEY = process.env.FIREBASE_API_KEY ?? '';
const PROJETO = process.env.FIREBASE_PROJECT_ID ?? '';
const EMAIL = process.env.FAXINA_EMAIL ?? '';
const SENHA = process.env.FAXINA_SENHA ?? '';

if (!API_KEY || !EMAIL || !SENHA) {
  console.log('Agenda fixa: segredos não configurados — nada a fazer.');
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
  console.log('Agenda fixa: o endereço do Worker ainda não foi preenchido em '
    + 'lib/core/constants/avisos_config.dart — nada a fazer.');
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

// 2. Pedir ao Worker que crie o que falta.
const resposta = await fetch(`${worker}/agenda`, {
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
  // O carimbo de FALHA é o que faz o cartão de saúde ficar vermelho em vez
  // de só envelhecer: sem ele, uma rotina que falha todo dia na mesma hora
  // pareceria "rodou ontem" para sempre.
  await carimbarEDizer({
    projectId: PROJETO,
    idToken,
    qual: 'cultos',
    ok: false,
    detalhe: `o Worker respondeu ${resposta.status}`,
  });
  process.exit(1);
}

const r = JSON.parse(texto);
if (r.semSlots) {
  // Estado normal de um ministério que ainda não usa a agenda fixa.
  console.log('Agenda fixa não configurada no app — nada a criar.');
} else {
  console.log(`Agenda fixa: ${r.criados ?? 0} culto(s) criado(s), `
    + `${r.jaExistiam ?? 0} já existia(m), de ${r.pretendidos ?? 0} `
    + 'previsto(s).');
  await carimbarEDizer({
    projectId: PROJETO,
    idToken,
    qual: 'cultos',
    ok: !(r.falhas?.length),
    detalhe: `${r.criados ?? 0} criado(s), ${r.jaExistiam ?? 0} já existia(m)`,
  });
  if (r.falhas?.length) {
    // Falha de um culto não derruba o job: amanhã tenta de novo, e os que
    // deram certo já estão lá. Mas fica no log para dar para investigar.
    console.error('Falhas:', r.falhas.join(' | '));
  }
}
