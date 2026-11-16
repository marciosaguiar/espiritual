// Apaga as mensagens de chat que passaram dos 30 dias.
//
// POR QUE ISTO EXISTE, E NÃO UMA POLÍTICA DE TTL DO FIRESTORE
//
// O Firestore tem TTL — um campo de data e ele apaga sozinho. Mas a própria
// documentação do Firebase lista "TTL deletes" entre os recursos SEM cota
// gratuita: exige faturamento ativo, ou seja, plano Blaze. Este projeto fica
// no Spark de propósito. Então a faxina é esta, com exclusões comuns, que no
// Spark têm cota (20 mil por dia, muito acima do que um ministério gera).
//
// COMO ELA ENTRA NO BANCO
//
// Entrando como um líder comum, com e-mail e senha, e não com chave de
// administrador. A diferença importa: a chave de administrador ignora todas
// as regras de segurança e, se vazar, dá acesso a tudo. Este robô obedece às
// mesmas regras que qualquer líder — se vazar, troca-se a senha e acabou.
//
// O QUE ELA NUNCA APAGA
//
// Mensagem fixada. A regra está gravada no próprio documento: `expiraEm` é
// nulo quando fixada, e a consulta só pega quem tem `expiraEm` no passado.
// A faxina não decide nada; ela executa o que o app escreveu.
//
// Medido no emulador antes de confiar: com documentos de `expiraEm` nulo,
// no passado, no futuro e sem o campo, a consulta `expiraEm <= agora`
// devolve SÓ o do passado. Null e campo ausente ficam de fora. Ainda assim
// há a conferência de `fixada` logo antes de apagar, abaixo — porque o
// estrago, se um dia essa semântica mudar, seria apagar exatamente o que as
// pessoas pediram para guardar.
//
// Sem os segredos configurados, não faz nada e diz isso. Ver o README do
// repositório para quais segredos criar.

import { initializeApp } from 'firebase/app';
import {
  getAuth, signInWithEmailAndPassword,
} from 'firebase/auth';
import {
  getFirestore, collection, query, where, orderBy, limit, getDocs,
  writeBatch, Timestamp,
} from 'firebase/firestore';

const CONFIG = {
  apiKey: process.env.FIREBASE_API_KEY,
  projectId: process.env.FIREBASE_PROJECT_ID,
  authDomain: `${process.env.FIREBASE_PROJECT_ID}.firebaseapp.com`,
};
const EMAIL = process.env.FAXINA_EMAIL;
const SENHA = process.env.FAXINA_SENHA;

// Quantas apagar por vez. O limite do Firestore é 500 por lote; 400 deixa
// folga e mantém cada rodada curta.
const POR_LOTE = 400;

if (!CONFIG.apiKey || !CONFIG.projectId || !EMAIL || !SENHA) {
  console.log('Faxina não configurada: faltam segredos. Nada foi feito.');
  console.log('Precisa de FIREBASE_API_KEY, FIREBASE_PROJECT_ID, '
    + 'FAXINA_EMAIL e FAXINA_SENHA.');
  process.exit(0);
}

const app = initializeApp(CONFIG);
const auth = getAuth(app);
const db = getFirestore(app);

const quem = await signInWithEmailAndPassword(auth, EMAIL, SENHA);
console.log('Entrou como', quem.user.uid);

const agora = Timestamp.now();

/// Apaga o que venceu numa coleção. Devolve quantos.
///
/// `audios` e `messages` carregam o mesmo `expiraEm`, posto pelo app, e
/// fixar a mensagem tira o prazo dos dois. Então a mesma varredura serve
/// para as duas, e nenhuma precisa consultar a outra.
async function limpar(colecao) {
  let apagados = 0;
  // Em volta, porque uma rodada pode não dar conta de tudo depois de uma
  // parada longa. Para quando não houver mais nada vencido.
  for (;;) {
    const vencidos = await getDocs(query(
      collection(db, colecao),
      where('expiraEm', '<=', agora),
      orderBy('expiraEm'),
      limit(POR_LOTE),
    ));
    if (vencidos.empty) break;

    const lote = writeBatch(db);
    let neste = 0;
    for (const d of vencidos.docs) {
      // A trava que não depende da consulta: fixada não se apaga, ponto.
      // Vale para o áudio também, que perde o prazo junto com a mensagem.
      if (d.data().fixada === true) {
        console.warn(`  PULANDO fixada que veio na consulta: ${d.id}`);
        continue;
      }
      lote.delete(d.ref);
      neste++;
    }
    if (neste > 0) await lote.commit();

    apagados += neste;
    console.log(`  ${colecao}: ${apagados}`);
    if (vencidos.size < POR_LOTE) break;
  }
  return apagados;
}

// Os áudios primeiro. Se a rodada morrer no meio, sobra mensagem apontando
// para áudio que já foi — uma bolha que diz "não está mais disponível", que
// é melhor do que áudio órfão de meio mega que ninguém alcança para apagar.
const audios = await limpar('audios');
const mensagens = await limpar('messages');

console.log(audios + mensagens === 0
  ? 'Nada vencido. Conversa em dia.'
  : `${mensagens} mensagens e ${audios} áudios apagados.`);
process.exit(0);
