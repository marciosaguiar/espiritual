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
  serverTimestamp, Bytes,
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
await teste('líder também não apaga música (só tira do repertório)', () =>
  assertFails(deleteDoc(doc(lider(), 'songs', 's2'))));

// ─────────────────────────────────────────────────────────────────────────────
// Quem pode apagar música
//
// O repertório inteiro sumiu do banco uma vez, sem ninguém assumir. Estes
// testes fixam a resposta de "quem conseguiria", para a pergunta não precisar
// ser investigada de novo: só o líder, e mais ninguém.
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Tirar música do repertório
//
// O repertório inteiro sumiu do banco uma vez, sem ninguém assumir. Apagar
// deixou de existir no app: ficou "tirar do repertório", que é um campo, como
// cancelar culto. Estes testes fixam quem consegue mexer nesse campo — e que
// apagar está fechado para todos, líder incluído.
// ─────────────────────────────────────────────────────────────────────────────
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const id of ['s-lider', 's-levita', 's-pendente', 's-removido', 's-deslogado']) {
    await setDoc(doc(db, 'songs', id), {
      id, name: 'Digno', artist: 'x', lyrics: '', originalKey: 'G',
      links: [], isOfflineAvailable: false, createdAt: new Date(), addedBy: LIDER,
      archived: false, archivedAt: null, archivedBy: null,
    });
  }
  await setDoc(doc(db, 'songs', 's-lider', 'arrangements', 'a1'), {
    id: 'a1', songId: 's-lider', chords: 'G C D', churchKey: 'G', notes: '',
    createdAt: new Date(),
  });
  // Cada estado no seu próprio uid, para não depender da ordem dos testes.
  await setDoc(doc(db, 'users', 'uid-pendente'), perfil('uid-pendente', 'Pedro', 'pendente'));
  await setDoc(doc(db, 'users', 'uid-removido'), perfil('uid-removido', 'Rita', 'removido'));
});

const pendente = () => env.authenticatedContext('uid-pendente').firestore();
const removido = () => env.authenticatedContext('uid-removido').firestore();

console.log('\n── tirar música do repertório ──');

await teste('levita não arquiva música', () =>
  assertFails(updateDoc(doc(levita(), 'songs', 's-levita'),
    { archived: true, archivedAt: serverTimestamp(), archivedBy: LEVITA })));

await teste('pendente não arquiva música', () =>
  assertFails(updateDoc(doc(pendente(), 'songs', 's-pendente'),
    { archived: true, archivedAt: serverTimestamp(), archivedBy: 'uid-pendente' })));

await teste('removido não arquiva música', () =>
  assertFails(updateDoc(doc(removido(), 'songs', 's-removido'),
    { archived: true, archivedAt: serverTimestamp(), archivedBy: 'uid-removido' })));

await teste('deslogado não arquiva música', () =>
  assertFails(updateDoc(doc(deslogado(), 'songs', 's-deslogado'),
    { archived: true })));

await teste('o líder tira do repertório', () =>
  assertSucceeds(updateDoc(doc(lider(), 'songs', 's-lider'),
    { archived: true, archivedAt: serverTimestamp(), archivedBy: LIDER })));

await teste('levita não devolve ao repertório', () =>
  assertFails(updateDoc(doc(levita(), 'songs', 's-lider'),
    { archived: false, archivedAt: null, archivedBy: null })));

await teste('o líder devolve ao repertório', () =>
  assertSucceeds(updateDoc(doc(lider(), 'songs', 's-lider'),
    { archived: false, archivedAt: null, archivedBy: null })));

await teste('archived com tipo errado é recusado', () =>
  assertFails(updateDoc(doc(lider(), 'songs', 's-lider'), { archived: 'sim' })));

await teste('carimbo de arquivamento com tipo errado é recusado', () =>
  assertFails(updateDoc(doc(lider(), 'songs', 's-lider'),
    { archived: true, archivedAt: 'ontem', archivedBy: LIDER })));

console.log('\n── apagar música não existe mais ──');

await teste('NEM O LÍDER apaga música', () =>
  assertFails(deleteDoc(doc(lider(), 'songs', 's-lider'))));

await teste('nem o líder apaga o arranjo', () =>
  assertFails(deleteDoc(doc(lider(), 'songs', 's-lider', 'arrangements', 'a1'))));

await teste('levita continua sem apagar música', () =>
  assertFails(deleteDoc(doc(levita(), 'songs', 's-levita'))));

await teste('removido continua sem apagar música', () =>
  assertFails(deleteDoc(doc(removido(), 'songs', 's-removido'))));

await teste('o líder ainda consegue corrigir o nome da música', () =>
  assertSucceeds(updateDoc(doc(lider(), 'songs', 's-lider'), { name: 'Digno É' })));

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
// Mudou de propósito: a conversa some depois de 30 dias, e quem apaga é uma
// faxina que entra como líder. O que continua proibido é reescrever o texto,
// que é o que estava em jogo aqui.
await teste('levita não apaga mensagem enviada', () =>
  assertFails(deleteDoc(doc(levita(), 'messages', 'fixa'))));

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


// ─────────────────────────────────────────────────────────────────────────────
// Chat: fixar e a faxina dos 30 dias
//
// A conversa some depois de 30 dias; a fixada fica. Quem apaga é uma faxina
// que entra como líder, então o líder precisa poder apagar mensagem — e só
// ele. E nem ele reescreve o que alguém disse.
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── chat: fixar e apagar ──');

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const id of ['m-lider', 'm-levita', 'm-apagar']) {
    await setDoc(doc(db, 'messages', id), {
      id, userId: LEVITA, userName: 'Ana', text: 'ensaio às 19h',
      type: 'text', linkedSongId: null, linkedSongName: null,
      timestamp: new Date(), fixada: false, fixadaPor: null,
      expiraEm: new Date(Date.now() + 30 * 864e5),
    });
  }
});

await teste('levita não fixa mensagem', () =>
  assertFails(updateDoc(doc(levita(), 'messages', 'm-levita'),
    { fixada: true, fixadaPor: LEVITA, expiraEm: null })));

await teste('pendente não fixa mensagem', () =>
  assertFails(updateDoc(doc(pendente(), 'messages', 'm-levita'),
    { fixada: true, fixadaPor: 'uid-pendente', expiraEm: null })));

await teste('o líder fixa, e o prazo some junto', () =>
  assertSucceeds(updateDoc(doc(lider(), 'messages', 'm-lider'),
    { fixada: true, fixadaPor: LIDER, expiraEm: null })));

await teste('fixar sem tirar o prazo é recusado', () =>
  assertFails(updateDoc(doc(lider(), 'messages', 'm-levita'),
    { fixada: true, fixadaPor: LIDER, expiraEm: new Date() })));

await teste('desafixar sem devolver o prazo é recusado', () =>
  assertFails(updateDoc(doc(lider(), 'messages', 'm-lider'),
    { fixada: false, fixadaPor: null, expiraEm: null })));

await teste('o líder desafixa devolvendo o prazo', () =>
  assertSucceeds(updateDoc(doc(lider(), 'messages', 'm-lider'),
    { fixada: false, fixadaPor: null, expiraEm: new Date(Date.now() + 864e5) })));

await teste('NEM O LÍDER reescreve o texto de uma mensagem', () =>
  assertFails(updateDoc(doc(lider(), 'messages', 'm-levita'),
    { text: 'eu nunca disse isso' })));

await teste('o autor também não reescreve o próprio texto', () =>
  assertFails(updateDoc(doc(levita(), 'messages', 'm-levita'),
    { text: 'na verdade era 20h' })));

await teste('levita não apaga mensagem (nem a própria)', () =>
  assertFails(deleteDoc(doc(levita(), 'messages', 'm-levita'))));

await teste('removido não apaga mensagem', () =>
  assertFails(deleteDoc(doc(removido(), 'messages', 'm-apagar'))));

await teste('o líder apaga — é como a faxina dos 30 dias funciona', () =>
  assertSucceeds(deleteDoc(doc(lider(), 'messages', 'm-apagar'))));

await teste('pendente não lê o chat', () =>
  assertFails(getDocs(collection(pendente(), 'messages'))));

await teste('removido não lê o chat', () =>
  assertFails(getDocs(collection(removido(), 'messages'))));

// ─────────────────────────────────────────────────────────────────────────────
// Mensagens de voz
//
// Os bytes ficam numa coleção à parte, para o chat não baixar áudio a cada
// abertura. O que estes testes fixam: quem pode mandar, quem pode ouvir, e
// que um áudio grande demais é recusado ANTES de estourar o limite do banco.
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── mensagens de voz ──');

// `Bytes` e não `Uint8Array` cru: o SDK recusa o array solto com
// "Unsupported field value", e o teste falharia por motivo errado.
const bytesDe = (quantos) =>
  Bytes.fromUint8Array(new Uint8Array(quantos).fill(7));
const audio = (dono, bytes, extra = {}) => ({
  id: 'a1', mensagemId: 'm1', userId: dono,
  bytes, tipo: 'audio/mp4', duracaoMs: 5000,
  criadoEm: new Date(), expiraEm: new Date(Date.now() + 30 * 864e5),
  ...extra,
});

await teste('aprovado manda áudio', () =>
  assertSucceeds(setDoc(doc(levita(), 'audios', 'a-ok'),
    audio(LEVITA, bytesDe(50 * 1024)))));

await teste('áudio de 800 KiB ainda passa', () =>
  assertSucceeds(setDoc(doc(levita(), 'audios', 'a-limite'),
    audio(LEVITA, bytesDe(819200)))));

await teste('áudio acima do limite é recusado', () =>
  assertFails(setDoc(doc(levita(), 'audios', 'a-grande'),
    audio(LEVITA, bytesDe(819201)))));

await teste('áudio vazio é recusado', () =>
  assertFails(setDoc(doc(levita(), 'audios', 'a-vazio'),
    audio(LEVITA, bytesDe(0)))));

await teste('áudio mais longo que 2 minutos é recusado', () =>
  assertFails(setDoc(doc(levita(), 'audios', 'a-longo'),
    audio(LEVITA, bytesDe(1024), { duracaoMs: 130000 }))));

await teste('não dá para mandar áudio em nome de outra pessoa', () =>
  assertFails(setDoc(doc(levita(), 'audios', 'a-falso'),
    audio(LIDER, bytesDe(1024)))));

await teste('áudio sem prazo é recusado (a faxina nunca o alcançaria)', () =>
  assertFails(setDoc(doc(levita(), 'audios', 'a-sem-prazo'),
    audio(LEVITA, bytesDe(1024), { expiraEm: null }))));

await teste('pendente não manda áudio', () =>
  assertFails(setDoc(doc(pendente(), 'audios', 'a-pend'),
    audio('uid-pendente', bytesDe(1024)))));

await teste('removido não manda áudio', () =>
  assertFails(setDoc(doc(removido(), 'audios', 'a-rem'),
    audio('uid-removido', bytesDe(1024)))));

await teste('aprovado ouve o áudio', () =>
  assertSucceeds(getDoc(doc(lider(), 'audios', 'a-ok'))));

await teste('pendente não ouve áudio', () =>
  assertFails(getDoc(doc(pendente(), 'audios', 'a-ok'))));

await teste('removido não ouve áudio', () =>
  assertFails(getDoc(doc(removido(), 'audios', 'a-ok'))));

await teste('deslogado não ouve áudio', () =>
  assertFails(getDoc(doc(deslogado(), 'audios', 'a-ok'))));

await teste('ninguém reescreve os bytes de um áudio', () =>
  assertFails(updateDoc(doc(levita(), 'audios', 'a-ok'),
    { bytes: bytesDe(10) })));

await teste('o líder mexe no prazo (é o que fixar faz)', () =>
  assertSucceeds(updateDoc(doc(lider(), 'audios', 'a-ok'),
    { expiraEm: null })));

await teste('levita não mexe no prazo de um áudio', () =>
  assertFails(updateDoc(doc(levita(), 'audios', 'a-ok'),
    { expiraEm: new Date() })));

await teste('o autor apaga o próprio áudio', () =>
  assertSucceeds(deleteDoc(doc(levita(), 'audios', 'a-limite'))));

await teste('ninguém apaga áudio alheio', () =>
  assertFails(deleteDoc(doc(novato(), 'audios', 'a-ok'))));

await teste('o líder apaga — é como a faxina limpa os vencidos', () =>
  assertSucceeds(deleteDoc(doc(lider(), 'audios', 'a-ok'))));

console.log('\n── a bolha do áudio ──');

await teste('mensagem de voz entra sem texto, por ter audioId', () =>
  assertSucceeds(setDoc(doc(levita(), 'messages', 'm-voz'), {
    id: 'm-voz', userId: LEVITA, userName: 'Ana', text: '', type: 'audio',
    linkedSongId: null, linkedSongName: null, timestamp: new Date(),
    audioId: 'a-ok', audioDuracaoMs: 5000, audioTipo: 'audio/mp4',
    fixada: false, fixadaPor: null, expiraEm: new Date(Date.now() + 864e5),
  })));

await teste('mensagem sem texto E sem áudio é recusada', () =>
  assertFails(setDoc(doc(levita(), 'messages', 'm-vazia'), {
    id: 'm-vazia', userId: LEVITA, userName: 'Ana', text: '', type: 'text',
    linkedSongId: null, linkedSongName: null, timestamp: new Date(),
    fixada: false, fixadaPor: null, expiraEm: new Date(Date.now() + 864e5),
  })));

console.log('\n── coleção desconhecida ──');
await teste('coleção sem regra fica bloqueada', () =>
  assertFails(setDoc(doc(lider(), 'qualquerCoisa', 'x'), { a: 1 })));

await env.cleanup();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou === 0 ? 0 : 1);
