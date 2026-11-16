// O gerador de cultos do Worker, contra o MESMO contrato que o app.
//
// `test/dados/agenda_contrato.json` tem os dados de entrada e os ids
// esperados, e é lido pelos dois lados: aqui e em
// `test/agenda_fixa_test.dart`. Se uma das duas contas mudar sem a outra,
// nascem duplicatas no banco — dois domingos das 8h, cada um com metade da
// equipe escalada — e é o teste do outro lado que acusa.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  cultosFaltando, idDoCulto, agoraEmBrasilia, instanteDe, somarDias,
  diaDaSemanaDe, proximaData, documentoDoCulto,
} from '../src/agenda.js';

const AQUI = dirname(fileURLToPath(import.meta.url));
const CONTRATO = JSON.parse(readFileSync(
  join(AQUI, '..', '..', 'test', 'dados', 'agenda_contrato.json'), 'utf8'));

/// O relógio de parede do contrato, como instante.
///
/// `-03:00` porque o contrato é em hora de Brasília: é assim que o mesmo
/// "2026-11-16T20:00" vira o mesmo id nos dois lados.
const instante = (parede) => Date.parse(`${parede}:00-03:00`);

// ── O contrato, caso por caso ───────────────────────────────────────────────

for (const caso of CONTRATO.casos) {
  test(`contrato: ${caso.nome}`, () => {
    const faltando = cultosFaltando({
      slots: caso.slots,
      equipes: {},
      existentes: caso.existentes,
      agoraMs: instante(caso.agora),
      semanas: caso.semanas,
    });
    assert.deepEqual(faltando.map((c) => c.id), caso.esperado);
  });
}

test('contrato: o documento criado tem os mesmos campos', () => {
  const bloco = CONTRATO.documentoEsperado;
  const { caso, esperado } = bloco;
  const faltando = cultosFaltando({
    slots: [caso.slot],
    equipes: { [caso.equipe.id]: caso.equipe },
    existentes: [],
    agoraMs: instante(caso.agora),
    semanas: caso.semanas,
  });
  assert.ok(faltando.length > 0);
  const campos = faltando[0].campos;

  assert.equal(campos.id, esperado.id);
  assert.equal(campos.serviceType, esperado.serviceType);
  assert.equal(campos.fromSlot, esperado.fromSlot);
  assert.equal(campos.teamId, esperado.teamId);
  assert.equal(campos.manuallyEdited, esperado.manuallyEdited);
  assert.equal(campos.canceled, esperado.canceled);
  assert.equal(campos.observations, esperado.observations);
  assert.deepEqual(campos.songs, esperado.songs);
  assert.deepEqual(campos.faltando, esperado.faltando);
  assert.deepEqual(campos.levitas, esperado.levitas);
  // A data do culto é o instante daquele relógio de parede em Brasília.
  assert.equal(campos.date.toISOString(), '2026-11-18T11:00:00.000Z');
});

// ── O fuso, que é onde isto quebraria sem ninguém ver ───────────────────────

test('o Worker usa Brasília, não o fuso onde acordou', () => {
  // 2026-11-19T01:00Z é ainda dia 18 em Brasília, às 22h. Em UTC seria dia
  // 19 — e um culto de quarta 19h30 viraria quinta, com outro id, duplicando
  // o que o app já criou.
  const p = agoraEmBrasilia(Date.parse('2026-11-19T01:00:00Z'));
  assert.deepEqual(p, {
    ano: 2026, mes: 11, dia: 18, hora: 22, minuto: 0, diaDaSemana: 3,
  });
});

test('meia-noite em Brasília não vira 24h nem pula o dia', () => {
  // `hour12: false` devolve "24" para a meia-noite em parte dos ambientes, e
  // 24 no id daria `2026-11-18_2400` — um culto que não existe.
  const p = agoraEmBrasilia(Date.parse('2026-11-18T03:00:00Z'));
  assert.equal(p.dia, 18);
  assert.equal(p.hora, 0);
  assert.equal(idDoCulto({ ...p, hora: 0, minuto: 0 }), '2026-11-18_0000');
});

test('o instante de um relógio de parede volta no mesmo relógio', () => {
  for (const parede of [
    { ano: 2026, mes: 11, dia: 18, hora: 8, minuto: 0 },
    { ano: 2026, mes: 12, dia: 31, hora: 19, minuto: 30 },
    { ano: 2027, mes: 1, dia: 1, hora: 0, minuto: 0 },
    { ano: 2028, mes: 2, dia: 29, hora: 20, minuto: 0 },
  ]) {
    const volta = agoraEmBrasilia(instanteDe(parede).getTime());
    assert.deepEqual(
      { ano: volta.ano, mes: volta.mes, dia: volta.dia,
        hora: volta.hora, minuto: volta.minuto },
      parede);
  }
});

// ── Conta de calendário ─────────────────────────────────────────────────────

test('o id tem o formato do app, com zeros à esquerda', () => {
  assert.equal(
    idDoCulto({ ano: 2026, mes: 1, dia: 5, hora: 8, minuto: 0 }),
    '2026-01-05_0800');
  assert.equal(
    idDoCulto({ ano: 2026, mes: 11, dia: 15, hora: 19, minuto: 30 }),
    '2026-11-15_1930');
});

test('dia da semana: 1 = segunda … 7 = domingo, como no Dart', () => {
  // 15/11/2026 é domingo — é o exemplo que está no CLAUDE.md.
  assert.equal(diaDaSemanaDe({ ano: 2026, mes: 11, dia: 15 }), 7);
  assert.equal(diaDaSemanaDe({ ano: 2026, mes: 11, dia: 16 }), 1);
  assert.equal(diaDaSemanaDe({ ano: 2026, mes: 11, dia: 18 }), 3);
  // Viradas: 29/02/2028 é terça, 01/01/2027 é sexta.
  assert.equal(diaDaSemanaDe({ ano: 2028, mes: 2, dia: 29 }), 2);
  assert.equal(diaDaSemanaDe({ ano: 2027, mes: 1, dia: 1 }), 5);
});

test('somar dias atravessa mês, ano e fevereiro bissexto', () => {
  assert.deepEqual(
    somarDias({ ano: 2026, mes: 12, dia: 28, hora: 8, minuto: 0 }, 7),
    { ano: 2027, mes: 1, dia: 4, hora: 8, minuto: 0 });
  assert.deepEqual(
    somarDias({ ano: 2028, mes: 2, dia: 27, hora: 8, minuto: 0 }, 3),
    { ano: 2028, mes: 3, dia: 1, hora: 8, minuto: 0 });
  assert.deepEqual(
    somarDias({ ano: 2027, mes: 2, dia: 27, hora: 8, minuto: 0 }, 3),
    { ano: 2027, mes: 3, dia: 2, hora: 8, minuto: 0 });
  // Muitos dias de uma vez: a geração soma 7×semanas.
  assert.deepEqual(
    somarDias({ ano: 2026, mes: 11, dia: 16, hora: 8, minuto: 0 }, 56),
    { ano: 2027, mes: 1, dia: 11, hora: 8, minuto: 0 });
});

test('a próxima data cai no dia da semana do horário, na hora dele', () => {
  const slot = { id: 'dom-1900', weekday: 7, hour: 19, minute: 0 };
  // Numa segunda, o próximo domingo é seis dias depois.
  assert.deepEqual(
    proximaData(slot, { ano: 2026, mes: 11, dia: 16, hora: 20, minuto: 0 }),
    { ano: 2026, mes: 11, dia: 22, hora: 19, minuto: 0 });
  // No próprio domingo, é hoje — quem decide se já passou é quem chama.
  assert.deepEqual(
    proximaData(slot, { ano: 2026, mes: 11, dia: 22, hora: 23, minuto: 0 }),
    { ano: 2026, mes: 11, dia: 22, hora: 19, minuto: 0 });
});

// ── Entradas tortas não derrubam o Worker ───────────────────────────────────

test('horário sem dia da semana é ignorado, e o resto continua', () => {
  // Documento mexido no console, ou meio gravado: um horário torto não pode
  // impedir a criação dos outros cultos da semana.
  const faltando = cultosFaltando({
    slots: [
      { id: 'torto', name: 'Culto' },
      { id: 'qua-0800', weekday: 3, hour: 8, minute: 0, name: 'Culto' },
    ],
    existentes: [],
    agoraMs: instante('2026-11-16T20:00'),
    semanas: 1,
  });
  assert.deepEqual(faltando.map((c) => c.id), ['2026-11-18_0800']);
});

test('equipe que não existe não derruba nem escala ninguém', () => {
  const faltando = cultosFaltando({
    slots: [{ id: 'q', weekday: 3, hour: 8, minute: 0, teamId: 'fantasma' }],
    equipes: {},
    existentes: [],
    agoraMs: instante('2026-11-16T20:00'),
    semanas: 1,
  });
  assert.equal(faltando.length, 1);
  assert.deepEqual(faltando[0].campos.levitas, []);
});

test('membro sem userId é descartado', () => {
  const doc = documentoDoCulto(
    { id: 'q', weekday: 3, hour: 8, minute: 0, teamId: 'e1' },
    { ano: 2026, mes: 11, dia: 18, hora: 8, minuto: 0 },
    '2026-11-18_0800',
    { e1: { members: [{ instrument: 'bass' }, { userId: 'u1' }] } },
  );
  assert.deepEqual(doc.levitas, [
    { userId: 'u1', userName: '', instrument: 'other', confirmed: false },
  ]);
});

test('nome do culto em branco vira "Culto"', () => {
  const doc = documentoDoCulto(
    { id: 'q', weekday: 3, hour: 8, minute: 0, name: '   ' },
    { ano: 2026, mes: 11, dia: 18, hora: 8, minuto: 0 },
    '2026-11-18_0800',
  );
  assert.equal(doc.serviceType, 'Culto');
});

test('nenhum horário, nada a criar', () => {
  assert.deepEqual(cultosFaltando({}), []);
  assert.deepEqual(cultosFaltando({ slots: null }), []);
});
