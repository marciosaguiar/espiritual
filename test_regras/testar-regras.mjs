// Testa firestore.rules contra o motor de verdade (emulador), não no olho.
//
// Rodar:  npm test   (sobe o emulador, roda e derruba)
// Ou, com o emulador ja no ar em 127.0.0.1:8080:  node testar-regras.mjs

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs, addDoc,
  serverTimestamp,
} from 'firebase/firestore';
import { readFileSync } from 'node:fs';

const env = await initializeTestEnvironment({
  projectId: 'levitas-teste',
  firestore: {
    rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    host: '127.0.0.1',
    port: 8080,
  },
});

const LIDER = 'uid-lider';
const LEVITA = 'uid-levita';
const OUTRO = 'uid-outro';

// Perfil como o app realmente o grava (UserModel.toFirestore).
function perfil(uid, nome, role) {
  return {
    id: uid,
    name: nome,
    nameLower: nome.toLowerCase(),
    email: `${nome.toLowerCase()}@levitas.app`,
    role,
    instrument: 'vocalist',
    photoUrl: null,            // <- é sempre gravado, e é nulo
    favoriteSongs: [],
    createdAt: new Date(),
  };
}

async function semear() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', LIDER), perfil(LIDER, 'Marcio', 'admin'));
    await setDoc(doc(db, 'users', LEVITA), perfil(LEVITA, 'Ana', 'levita'));
    await setDoc(doc(db, 'songs', 's1'), {
      id: 's1', name: 'Digno és', artist: 'Hillsong', lyrics: 'a',
      originalKey: 'G', links: [], isOfflineAvailable: false,
      createdAt: new Date(), addedBy: null,
    });
    await setDoc(doc(db, 'scales', 'c1'), {
      id: 'c1', date: new Date(2026, 10, 15, 9, 0), serviceType: 'Culto',
      songs: [], observations: '', createdBy: LIDER, createdAt: new Date(),
      levitas: [
        { userId: LEVITA, userName: 'Ana', instrument: 'vocalist', confirmed: false },
      ],
    });
  });
}

const lider = () => env.authenticatedContext(LIDER).firestore();
const levita = () => env.authenticatedContext(LEVITA).firestore();
const novato = () => env.authenticatedContext(OUTRO).firestore();
const deslogado = () => env.unauthenticatedContext().firestore();

let passou = 0, falhou = 0;
async function teste(nome, fn) {
  try {
    await fn();
    console.log(`  ok   ${nome}`);
    passou++;
  } catch (e) {
    console.log(`  FALHA ${nome}`);
    console.log(`        ${String(e.message).split('\n')[0].slice(0, 160)}`);
    falhou++;
  }
}

await env.clearFirestore();
await semear();

console.log('\n── cadastro ──');
await teste('cadastro novo é aceito (photoUrl nulo incluído)', () =>
  assertSucceeds(setDoc(doc(novato(), 'users', OUTRO), perfil(OUTRO, 'Bruno', 'pendente'))));

await teste('cadastrar-se já como levita é recusado', () =>
  assertFails(setDoc(doc(env.authenticatedContext('uid-esperto').firestore(),
    'users', 'uid-esperto'), perfil('uid-esperto', 'Esperto', 'levita'))));

await teste('cadastrar-se como líder é recusado', () =>
  assertFails(setDoc(doc(novato(), 'users', OUTRO), perfil(OUTRO, 'Bruno', 'admin'))));

await teste('cadastrar no id de outra pessoa é recusado', () =>
  assertFails(setDoc(doc(novato(), 'users', 'uid-alheio'), perfil('uid-alheio', 'Falso', 'pendente'))));

// uid próprio: o OUTRO já foi criado acima, e criar ali seria uma atualização.
await teste('cadastro com nome curto demais é recusado', () =>
  assertFails(setDoc(doc(env.authenticatedContext('uid-curto').firestore(), 'users', 'uid-curto'),
    perfil('uid-curto', 'Jo', 'pendente'))));

await teste('não dá para encurtar o nome abaixo de 3 letras depois', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO), { name: 'Jo' })));

await teste('cadastro trazendo passwordHash é recusado', () =>
  assertFails(setDoc(doc(novato(), 'users', OUTRO),
    { ...perfil(OUTRO, 'Bruno', 'pendente'), passwordHash: 'x' })));

console.log('\n── sem login ──');
await teste('deslogado não lê usuários', () =>
  assertFails(getDoc(doc(deslogado(), 'users', LIDER))));
await teste('deslogado não lê músicas', () =>
  assertFails(getDocs(collection(deslogado(), 'songs'))));
await teste('deslogado não lê o chat', () =>
  assertFails(getDocs(collection(deslogado(), 'messages'))));

console.log('\n── funções ──');
await teste('levita não se promove a líder', () =>
  assertFails(updateDoc(doc(levita(), 'users', LEVITA), { role: 'admin' })));
await teste('levita edita o próprio instrumento', () =>
  assertSucceeds(updateDoc(doc(levita(), 'users', LEVITA), { instrument: 'guitar' })));
await teste('levita escolhe "Eu canto" no perfil', () =>
  assertSucceeds(updateDoc(doc(levita(), 'users', LEVITA), { leitura: 'canto' })));
await teste('modo de leitura só aceita canto ou toco', () =>
  assertFails(updateDoc(doc(levita(), 'users', LEVITA), { leitura: 'admin' })));
await teste('levita não edita o perfil de outra pessoa', () =>
  assertFails(updateDoc(doc(levita(), 'users', LIDER), { instrument: 'drums' })));
await teste('líder promove um levita', () =>
  assertSucceeds(updateDoc(doc(lider(), 'users', LEVITA), { role: 'admin' })));
await teste('ninguém apaga conta', () =>
  assertFails(deleteDoc(doc(lider(), 'users', LEVITA))));

// desfaz a promoção acima
await env.withSecurityRulesDisabled(async (ctx) =>
  setDoc(doc(ctx.firestore(), 'users', LEVITA), perfil(LEVITA, 'Ana', 'levita')));

console.log('\n── músicas ──');
await teste('levita lê o repertório', () =>
  assertSucceeds(getDocs(collection(levita(), 'songs'))));
await teste('levita não cria música', () =>
  assertFails(setDoc(doc(levita(), 'songs', 's2'),
    { id: 's2', name: 'Nova', artist: '', lyrics: '', originalKey: 'C' })));
await teste('líder cria música', () =>
  assertSucceeds(setDoc(doc(lider(), 'songs', 's2'),
    { id: 's2', name: 'Nova', artist: '', lyrics: '', originalKey: 'C',
      links: [], isOfflineAvailable: false, createdAt: new Date(), addedBy: LIDER })));
await teste('levita NÃO apaga música', () =>
  assertFails(deleteDoc(doc(levita(), 'songs', 's1'))));
await teste('líder apaga música', () =>
  assertSucceeds(deleteDoc(doc(lider(), 'songs', 's2'))));

// ─────────────────────────────────────────────────────────────────────────────
// Quem pode apagar música
//
// O repertório inteiro sumiu do banco uma vez, sem ninguém assumir. Estes
// testes fixam a resposta de "quem conseguiria", para a pergunta não precisar
// ser investigada de novo: só o líder, e mais ninguém.
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── apagar música ──');

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const id of ['s-lider', 's-levita', 's-pendente', 's-removido', 's-deslogado']) {
    await setDoc(doc(db, 'songs', id), {
      id, name: 'Digno', artist: 'x', lyrics: '', originalKey: 'G',
      links: [], isOfflineAvailable: false, createdAt: new Date(), addedBy: LIDER,
    });
  }
  // PENDENTE e REMOVIDO, cada um no seu estado, para não depender da ordem
  // dos testes anteriores.
  await setDoc(doc(db, 'users', 'uid-pendente'), perfil('uid-pendente', 'Pedro', 'pendente'));
  await setDoc(doc(db, 'users', 'uid-removido'), perfil('uid-removido', 'Rita', 'removido'));
});

const pendente = () => env.authenticatedContext('uid-pendente').firestore();
const removido = () => env.authenticatedContext('uid-removido').firestore();

await teste('levita não apaga música de ninguém', () =>
  assertFails(deleteDoc(doc(levita(), 'songs', 's-levita'))));

await teste('pendente não apaga música', () =>
  assertFails(deleteDoc(doc(pendente(), 'songs', 's-pendente'))));

await teste('removido não apaga música', () =>
  assertFails(deleteDoc(doc(removido(), 'songs', 's-removido'))));

await teste('deslogado não apaga música', () =>
  assertFails(deleteDoc(doc(deslogado(), 'songs', 's-deslogado'))));

await teste('levita também não apaga o arranjo', () =>
  assertFails(deleteDoc(doc(levita(), 'songs', 's-levita', 'arrangements', 'a1'))));

await teste('levita não esvazia a música por update', () =>
  assertFails(updateDoc(doc(levita(), 'songs', 's-levita'), { name: '', lyrics: '' })));

await teste('o líder apaga', () =>
  assertSucceeds(deleteDoc(doc(lider(), 'songs', 's-lider'))));

console.log('\n── arranjos ──');
await teste('levita lê o arranjo', () =>
  assertSucceeds(getDocs(collection(levita(), 'songs', 's1', 'arrangements'))));
await teste('levita não grava arranjo', () =>
  assertFails(setDoc(doc(levita(), 'songs', 's1', 'arrangements', 'a1'),
    { id: 'a1', songId: 's1', churchKey: 'G', chords: 'x' })));
await teste('líder grava arranjo', () =>
  assertSucceeds(setDoc(doc(lider(), 'songs', 's1', 'arrangements', 'a1'),
    { id: 'a1', songId: 's1', name: 'Padrão', churchKey: 'G', chords: '[G]x',
      structure: [], bpm: 0, notes: '', approvedBy: LIDER, updatedAt: new Date() })));

console.log('\n── minhas preferências ──');
await teste('salvo a minha preferência', () =>
  assertSucceeds(setDoc(doc(levita(), 'users', LEVITA, 'songPrefs', 's1'),
    { songId: 's1', semitones: 2, notes: 'segunda voz', capo: 0, updatedAt: new Date() })));
await teste('nem o líder lê a anotação de outra pessoa', () =>
  assertFails(getDoc(doc(lider(), 'users', LEVITA, 'songPrefs', 's1'))));

console.log('\n── escala ──');
await teste('levita lê o culto', () =>
  assertSucceeds(getDoc(doc(levita(), 'scales', 'c1'))));
await teste('levita confirma presença (só o campo levitas)', () =>
  assertSucceeds(updateDoc(doc(levita(), 'scales', 'c1'), {
    levitas: [{ userId: LEVITA, userName: 'Ana', instrument: 'vocalist', confirmed: true }],
  })));
await teste('levita NÃO muda o repertório do culto', () =>
  assertFails(updateDoc(doc(levita(), 'scales', 'c1'), { songs: [{ songId: 's1' }] })));
await teste('levita NÃO remarca o culto', () =>
  assertFails(updateDoc(doc(levita(), 'scales', 'c1'), { date: new Date() })));
await teste('levita NÃO apaga o culto', () =>
  assertFails(deleteDoc(doc(levita(), 'scales', 'c1'))));
await teste('líder muda o repertório', () =>
  assertSucceeds(updateDoc(doc(lider(), 'scales', 'c1'), { songs: [{ songId: 's1' }] })));
await teste('líder cria culto', () =>
  assertSucceeds(setDoc(doc(lider(), 'scales', 'c2'),
    { id: 'c2', date: new Date(), serviceType: 'Ensaio', songs: [], levitas: [],
      observations: '', createdBy: LIDER, createdAt: new Date() })));
await teste('levita NÃO cria culto', () =>
  assertFails(setDoc(doc(levita(), 'scales', 'c3'),
    { id: 'c3', date: new Date(), serviceType: 'Culto', songs: [], levitas: [],
      observations: '', createdBy: LEVITA, createdAt: new Date() })));

console.log('\n── chat ──');
await teste('envio mensagem em meu nome', () =>
  assertSucceeds(addDoc(collection(levita(), 'messages'),
    { id: 'm1', userId: LEVITA, userName: 'Ana', text: 'oi', type: 'text',
      linkedSongId: null, linkedSongName: null, timestamp: new Date() })));
await teste('não envio em nome de outra pessoa', () =>
  assertFails(addDoc(collection(levita(), 'messages'),
    { id: 'm2', userId: LIDER, userName: 'Marcio', text: 'falso', type: 'text',
      timestamp: new Date() })));
await teste('mensagem vazia é recusada', () =>
  assertFails(addDoc(collection(levita(), 'messages'),
    { id: 'm3', userId: LEVITA, userName: 'Ana', text: '', type: 'text',
      timestamp: new Date() })));

await env.withSecurityRulesDisabled(async (ctx) =>
  setDoc(doc(ctx.firestore(), 'messages', 'fixa'),
    { id: 'fixa', userId: LEVITA, userName: 'Ana', text: 'oi', type: 'text',
      timestamp: new Date() }));
await teste('mensagem enviada não se edita', () =>
  assertFails(updateDoc(doc(levita(), 'messages', 'fixa'), { text: 'mudou' })));
await teste('mensagem enviada não se apaga (nem pelo líder)', () =>
  assertFails(deleteDoc(doc(lider(), 'messages', 'fixa'))));

console.log('\n── digitando ──');
await teste('escrevo no meu próprio "digitando"', () =>
  assertSucceeds(setDoc(doc(levita(), 'typing', LEVITA),
    { userId: LEVITA, userName: 'Ana', typing: true, updatedAt: new Date() })));
await teste('não escrevo no "digitando" de outra pessoa', () =>
  assertFails(setDoc(doc(levita(), 'typing', LIDER),
    { userId: LIDER, userName: 'Marcio', typing: true, updatedAt: new Date() })));

console.log('\n── equipes ──');
await teste('levita lê as equipes (os nomes aparecem na escala)', () =>
  assertSucceeds(getDocs(collection(levita(), 'teams'))));
await teste('levita NÃO cria equipe', () =>
  assertFails(setDoc(doc(levita(), 'teams', 't1'),
    { id: 't1', name: 'Equipe Manhã', members: [], updatedAt: new Date() })));
await teste('líder cria equipe', () =>
  assertSucceeds(setDoc(doc(lider(), 'teams', 't1'),
    { id: 't1', name: 'Equipe Manhã',
      members: [{ userId: LEVITA, instrument: 'vocalist' }],
      createdBy: LIDER, updatedAt: new Date() })));
await teste('equipe sem nome é recusada', () =>
  assertFails(setDoc(doc(lider(), 'teams', 't2'),
    { id: 't2', name: '', members: [], updatedAt: new Date() })));
await teste('levita NÃO apaga equipe', () =>
  assertFails(deleteDoc(doc(levita(), 'teams', 't1'))));
await teste('líder apaga equipe', () =>
  assertSucceeds(deleteDoc(doc(lider(), 'teams', 't1'))));

console.log('\n── agenda fixa ──');
const agenda = {
  slots: [
    { id: 'qua-0800', weekday: 3, hour: 8, minute: 0, name: 'Culto', teamId: 't1' },
    { id: 'dom-1900', weekday: 7, hour: 19, minute: 0, name: 'Culto', teamId: 't2' },
  ],
  updatedAt: new Date(),
};
await teste('levita lê a agenda fixa', () =>
  assertSucceeds(getDoc(doc(levita(), 'config', 'agendaFixa'))));
await teste('levita NÃO escreve a agenda fixa', () =>
  assertFails(setDoc(doc(levita(), 'config', 'agendaFixa'), agenda)));
await teste('líder escreve a agenda fixa', () =>
  assertSucceeds(setDoc(doc(lider(), 'config', 'agendaFixa'), agenda)));
await teste('agenda com lista gigante é recusada', () =>
  assertFails(setDoc(doc(lider(), 'config', 'agendaFixa'),
    { slots: Array.from({ length: 31 }, (_, i) => ({ id: 's' + i, weekday: 1 })),
      updatedAt: new Date() })));

console.log('\n── culto gerado pela agenda ──');
// Id determinístico, como o app monta: data_hora.
const CULTO_GERADO = '2026-11-15_0800';
const doGerado = (extra = {}) => ({
  id: CULTO_GERADO,
  date: new Date(2026, 10, 15, 8, 0),
  serviceType: 'Culto',
  songs: [], levitas: [], observations: '',
  createdBy: LIDER, createdAt: new Date(),
  fromSlot: 'dom-0800', teamId: 't1',
  manuallyEdited: false, canceled: false,
  ...extra,
});
await teste('levita NÃO gera culto', () =>
  assertFails(setDoc(doc(levita(), 'scales', CULTO_GERADO), doGerado())));
await teste('líder gera culto com id determinístico', () =>
  assertSucceeds(setDoc(doc(lider(), 'scales', CULTO_GERADO), doGerado())));
await teste('líder cancela o culto', () =>
  assertSucceeds(updateDoc(doc(lider(), 'scales', CULTO_GERADO),
    { canceled: true })));
await teste('levita NÃO cancela o culto', () =>
  assertFails(updateDoc(doc(levita(), 'scales', CULTO_GERADO),
    { canceled: false })));
await teste('levita NÃO marca o culto como editado à mão', () =>
  assertFails(updateDoc(doc(levita(), 'scales', CULTO_GERADO),
    { manuallyEdited: true })));
await teste('levita NÃO troca a equipe do culto', () =>
  assertFails(updateDoc(doc(levita(), 'scales', CULTO_GERADO),
    { teamId: 'outra' })));
await teste('levita ainda confirma presença no culto gerado', () =>
  assertSucceeds(updateDoc(doc(levita(), 'scales', CULTO_GERADO), {
    levitas: [{ userId: LEVITA, userName: 'Ana',
                instrument: 'vocalist', confirmed: true }],
  })));

// ─────────────────────────────────────────────────────────────────────────────
// Aprovação do líder
//
// É a trava de entrada do app, e é toda feita aqui nas regras — esconder os
// botões não adiantaria, porque qualquer pessoa pode falar direto com o banco
// pela API. Por isso o que importa é o que está abaixo, e não o que a tela
// mostra. OUTRO ('Bruno') foi criado como pendente lá em cima.
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── pendente não enxerga nada ──');

await teste('pendente lê o PRÓPRIO cadastro (senão o app abre vazio sem explicar)', () =>
  assertSucceeds(getDoc(doc(novato(), 'users', OUTRO))));

await teste('pendente não lê o cadastro de outra pessoa', () =>
  assertFails(getDoc(doc(novato(), 'users', LIDER))));

await teste('pendente não lista os membros', () =>
  assertFails(getDocs(collection(novato(), 'users'))));

await teste('pendente não lê o repertório', () =>
  assertFails(getDoc(doc(novato(), 'songs', 's1'))));

await teste('pendente não lê o arranjo da igreja', () =>
  assertFails(getDocs(collection(novato(), 'songs', 's1', 'arrangements'))));

await teste('pendente não lê os cultos', () =>
  assertFails(getDoc(doc(novato(), 'scales', 'c1'))));

await teste('pendente não lê as equipes', () =>
  assertFails(getDocs(collection(novato(), 'teams'))));

await teste('pendente não lê a agenda fixa', () =>
  assertFails(getDoc(doc(novato(), 'config', 'agendaFixa'))));

await teste('pendente não lê o chat', () =>
  assertFails(getDocs(collection(novato(), 'messages'))));

await teste('pendente não manda mensagem no chat', () =>
  assertFails(addDoc(collection(novato(), 'messages'),
    { userId: OUTRO, userName: 'Bruno', text: 'oi', createdAt: serverTimestamp() })));

await teste('pendente não se mete na lista de presença de um culto', () =>
  assertFails(updateDoc(doc(novato(), 'scales', 'c1'), {
    levitas: [{ userId: OUTRO, userName: 'Bruno', instrument: 'vocalist', confirmed: true }],
  })));

console.log('\n── pendente não se aprova sozinho ──');

await teste('pendente não vira levita por conta própria', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO), { role: 'levita' })));

await teste('pendente não vira líder por conta própria', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO), { role: 'admin' })));

await teste('pendente não escreve nem no próprio cadastro', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO), { name: 'Bruno Silva' })));

await teste('levita comum não aprova ninguém', () =>
  assertFails(updateDoc(doc(levita(), 'users', OUTRO), { role: 'levita' })));

await teste('função inventada é recusada', () =>
  assertFails(updateDoc(doc(lider(), 'users', OUTRO), { role: 'chefe' })));

console.log('\n── o líder decide ──');

await teste('líder recusa a entrada (vira removido)', () =>
  assertSucceeds(updateDoc(doc(lider(), 'users', OUTRO), { role: 'removido' })));

await teste('removido continua sem ler o repertório', () =>
  assertFails(getDoc(doc(novato(), 'songs', 's1'))));

await teste('removido ainda lê o próprio cadastro (é o que explica a tela)', () =>
  assertSucceeds(getDoc(doc(novato(), 'users', OUTRO))));

await teste('líder volta atrás e aprova', () =>
  assertSucceeds(updateDoc(doc(lider(), 'users', OUTRO), { role: 'levita' })));

await teste('aprovado passa a ler o repertório', () =>
  assertSucceeds(getDoc(doc(novato(), 'songs', 's1'))));

await teste('aprovado passa a ler os cultos', () =>
  assertSucceeds(getDoc(doc(novato(), 'scales', 'c1'))));

await teste('aprovado passa a mandar mensagem no chat', () =>
  assertSucceeds(addDoc(collection(novato(), 'messages'),
    { userId: OUTRO, userName: 'Bruno', text: 'cheguei', createdAt: serverTimestamp() })));

await teste('aprovado continua sem criar música (isso é do líder)', () =>
  assertFails(setDoc(doc(novato(), 'songs', 's-novo'),
    { id: 's-novo', name: 'Nova', artist: 'x', lyrics: '', originalKey: 'C',
      links: [], isOfflineAvailable: false, createdAt: new Date(), addedBy: OUTRO })));


// ─────────────────────────────────────────────────────────────────────────────
// Sair e ser removido do ministério
//
// A esta altura OUTRO ('Bruno') já foi aprovado e é levita.
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── remoção pelo líder ──');

await teste('levita não remove ninguém', () =>
  assertFails(updateDoc(doc(levita(), 'users', OUTRO),
    { role: 'removido', removedAt: serverTimestamp(), removedBy: LEVITA })));

await teste('levita não remove o líder', () =>
  assertFails(updateDoc(doc(levita(), 'users', LIDER),
    { role: 'removido', removedAt: serverTimestamp(), removedBy: LEVITA })));

await teste('líder remove um levita', () =>
  assertSucceeds(updateDoc(doc(lider(), 'users', OUTRO),
    { role: 'removido', removedAt: serverTimestamp(), removedBy: LIDER })));

await teste('removido não lê o repertório', () =>
  assertFails(getDoc(doc(novato(), 'songs', 's1'))));

await teste('removido não lê os cultos', () =>
  assertFails(getDoc(doc(novato(), 'scales', 'c1'))));

await teste('removido não lê as equipes', () =>
  assertFails(getDocs(collection(novato(), 'teams'))));

await teste('removido não lê o chat', () =>
  assertFails(getDocs(collection(novato(), 'messages'))));

await teste('removido não manda mensagem', () =>
  assertFails(addDoc(collection(novato(), 'messages'),
    { userId: OUTRO, userName: 'Bruno', text: 'voltei', createdAt: serverTimestamp() })));

await teste('removido não confirma presença', () =>
  assertFails(updateDoc(doc(novato(), 'scales', 'c1'), {
    levitas: [{ userId: OUTRO, userName: 'Bruno', instrument: 'vocalist', confirmed: true }],
  })));

await teste('removido lê o PRÓPRIO cadastro (é o que explica a tela)', () =>
  assertSucceeds(getDoc(doc(novato(), 'users', OUTRO))));

console.log('\n── removido não se devolve ──');

await teste('removido não se devolve para levita', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO),
    { role: 'levita', removedAt: null, removedBy: null })));

await teste('removido não se promove a líder', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO), { role: 'admin' })));

await teste('removido não volta para pendente para tentar de novo', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO), { role: 'pendente' })));

await teste('removido não apaga o carimbo de saída', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO), { removedBy: null })));

await teste('levita não devolve o acesso de ninguém', () =>
  assertFails(updateDoc(doc(levita(), 'users', OUTRO),
    { role: 'levita', removedAt: null, removedBy: null })));

await teste('líder devolve o acesso', () =>
  assertSucceeds(updateDoc(doc(lider(), 'users', OUTRO),
    { role: 'levita', removedAt: null, removedBy: null })));

await teste('devolvido volta a ler o repertório', () =>
  assertSucceeds(getDoc(doc(novato(), 'songs', 's1'))));

console.log('\n── sair por conta própria ──');

await teste('levita sai sozinho do ministério', () =>
  assertSucceeds(updateDoc(doc(novato(), 'users', OUTRO),
    { role: 'removido', removedAt: serverTimestamp(), removedBy: OUTRO })));

await teste('quem saiu não entra de volta sozinho', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO),
    { role: 'levita', removedAt: null, removedBy: null })));

await teste('ninguém "sai" no lugar de outra pessoa', () =>
  assertFails(updateDoc(doc(levita(), 'users', LIDER),
    { role: 'removido', removedAt: serverTimestamp(), removedBy: LIDER })));

await teste('saindo com o removedBy de outra pessoa é recusado', () =>
  assertFails(updateDoc(doc(levita(), 'users', LEVITA),
    { role: 'removido', removedAt: serverTimestamp(), removedBy: OUTRO })));

await teste('carimbo de saída com tipo errado é recusado', () =>
  assertFails(updateDoc(doc(lider(), 'users', LEVITA),
    { role: 'removido', removedAt: 'ontem', removedBy: LIDER })));

await teste('conta apagada pelo app continua proibida', () =>
  assertFails(deleteDoc(doc(lider(), 'users', OUTRO))));


console.log('\n── coleção desconhecida ──');
await teste('coleção sem regra fica bloqueada', () =>
  assertFails(setDoc(doc(lider(), 'qualquerCoisa', 'x'), { a: 1 })));

await env.cleanup();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou === 0 ? 0 : 1);
