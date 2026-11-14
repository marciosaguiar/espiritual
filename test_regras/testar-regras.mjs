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
  assertSucceeds(setDoc(doc(novato(), 'users', OUTRO), perfil(OUTRO, 'Bruno', 'levita'))));

await teste('cadastrar-se como líder é recusado', () =>
  assertFails(setDoc(doc(novato(), 'users', OUTRO), perfil(OUTRO, 'Bruno', 'admin'))));

await teste('cadastrar no id de outra pessoa é recusado', () =>
  assertFails(setDoc(doc(novato(), 'users', 'uid-alheio'), perfil('uid-alheio', 'Falso', 'levita'))));

// uid próprio: o OUTRO já foi criado acima, e criar ali seria uma atualização.
await teste('cadastro com nome curto demais é recusado', () =>
  assertFails(setDoc(doc(env.authenticatedContext('uid-curto').firestore(), 'users', 'uid-curto'),
    perfil('uid-curto', 'Jo', 'levita'))));

await teste('não dá para encurtar o nome abaixo de 3 letras depois', () =>
  assertFails(updateDoc(doc(novato(), 'users', OUTRO), { name: 'Jo' })));

await teste('cadastro trazendo passwordHash é recusado', () =>
  assertFails(setDoc(doc(novato(), 'users', OUTRO),
    { ...perfil(OUTRO, 'Bruno', 'levita'), passwordHash: 'x' })));

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

console.log('\n── coleção desconhecida ──');
await teste('coleção sem regra fica bloqueada', () =>
  assertFails(setDoc(doc(lider(), 'qualquerCoisa', 'x'), { a: 1 })));

await env.cleanup();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou === 0 ? 0 : 1);
