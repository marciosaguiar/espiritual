// Quais cultos da agenda fixa ainda não existem. Funções puras.
//
// POR QUE ISTO EXISTE EM DOIS LUGARES
//
// A mesma conta já vive no app (`FirestoreService.servicosFaltando`), e roda
// quando um líder abre o app. O problema é justamente esse: se nenhum líder
// abrir o app por algumas semanas, os cultos param de ser criados e a escala
// seca sem ninguém perceber. Então ela roda também aqui, uma vez por dia, sem
// depender de ninguém.
//
// Duas contas iguais em linguagens diferentes é um risco de verdade: se uma
// calcular o id do culto de um jeito e a outra de outro, nascem duplicatas —
// dois domingos das 8h na lista, cada um com metade da equipe. É por isso que
// existe `test/dados/agenda_contrato.json`: os mesmos dados de entrada e os
// mesmos ids esperados, conferidos pelos dois lados. Mexer num gerador sem
// mexer no outro faz o teste do outro falhar.
//
// O FUSO É FIXO, DE BRASÍLIA
//
// O app faz a conta no relógio do aparelho, que para este ministério é
// Brasília. O Worker acorda em qualquer datacenter do mundo: em UTC, "quarta
// às 19h30" cairia na quinta de madrugada, com outro id. Então tudo aqui é
// hora de parede de Brasília, e a conta de semana em semana é feita em cima
// dela — nunca somando 7×24 horas a um instante, que é onde horário de verão
// quebraria (o Brasil não tem desde 2019, mas a conta não depende disso).

const FUSO = 'America/Sao_Paulo';

/// O relógio de parede de Brasília no instante [agoraMs].
///
/// `diaDaSemana` segue o Dart: 1 = segunda … 7 = domingo. O `Intl` responde
/// o nome em inglês, que é a única forma estável de perguntar isso sem
/// embutir uma tabela de fusos.
export function agoraEmBrasilia(agoraMs) {
  const d = new Date(agoraMs ?? Date.now());
  const partes = new Intl.DateTimeFormat('en-US', {
    timeZone: FUSO,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false,
    weekday: 'short',
  }).formatToParts(d);

  const p = {};
  for (const { type, value } of partes) p[type] = value;

  const dias = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };
  return {
    ano: Number(p.year),
    mes: Number(p.month),
    dia: Number(p.day),
    // `hour12: false` devolve 24 para a meia-noite em alguns ambientes.
    hora: Number(p.hour) % 24,
    minuto: Number(p.minute),
    diaDaSemana: dias[p.weekday] ?? 7,
  };
}

const d2 = (v) => String(v).padStart(2, '0');

/// O id do culto, igual ao do app: `2026-11-15_0800`.
///
/// É ele que impede duplicata — dois geradores calculando o mesmo id escrevem
/// o mesmo documento, e o segundo é recusado pela pré-condição.
export function idDoCulto({ ano, mes, dia, hora, minuto }) {
  return `${String(ano).padStart(4, '0')}-${d2(mes)}-${d2(dia)}`
    + `_${d2(hora)}${d2(minuto)}`;
}

/// O instante de um relógio de parede de Brasília.
///
/// `-03:00` fixo: o Brasil não tem horário de verão desde 2019. Se um dia
/// voltar, é esta linha que muda — e é por isso que ela está num lugar só.
export function instanteDe({ ano, mes, dia, hora, minuto }) {
  return new Date(
    `${String(ano).padStart(4, '0')}-${d2(mes)}-${d2(dia)}`
    + `T${d2(hora)}:${d2(minuto)}:00-03:00`);
}

/// Quantos dias tem um mês (ano bissexto incluído).
function diasNoMes(ano, mes) {
  return [31, (ano % 4 === 0 && ano % 100 !== 0) || ano % 400 === 0 ? 29 : 28,
    31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mes - 1];
}

/// Soma dias a um relógio de parede, sem passar por instante nenhum.
export function somarDias({ ano, mes, dia, hora, minuto }, quantos) {
  let [a, m, d] = [ano, mes, dia + quantos];
  while (d > diasNoMes(a, m)) {
    d -= diasNoMes(a, m);
    m += 1;
    if (m > 12) { m = 1; a += 1; }
  }
  while (d < 1) {
    m -= 1;
    if (m < 1) { m = 12; a -= 1; }
    d += diasNoMes(a, m);
  }
  return { ano: a, mes: m, dia: d, hora, minuto };
}

/// O dia da semana de um relógio de parede (1 = segunda … 7 = domingo).
///
/// Conta de calendário, sem `Date`: construir um `Date` aqui traria o fuso de
/// volta e é exatamente o que esta função evita.
export function diaDaSemanaDe({ ano, mes, dia }) {
  // Zeller, com domingo = 0 ajustado para 7 no fim.
  const m = mes < 3 ? mes + 12 : mes;
  const a = mes < 3 ? ano - 1 : ano;
  const k = a % 100;
  const j = Math.floor(a / 100);
  const h = (dia + Math.floor((13 * (m + 1)) / 5) + k + Math.floor(k / 4)
    + Math.floor(j / 4) + 5 * j) % 7;
  // h: 0 = sábado, 1 = domingo, 2 = segunda …
  return ((h + 5) % 7) + 1;
}

/// A próxima data, de hoje em diante, que cai no dia da semana do horário.
export function proximaData(slot, agora) {
  const diff = (slot.weekday - diaDaSemanaDe(agora) + 7) % 7;
  const dia = somarDias(agora, diff);
  return { ...dia, hora: slot.hour, minuto: slot.minute };
}

/// `{a: b}` só com as chaves que importam, para comparar relógios de parede.
function depois(x, y) {
  const n = (p) => ((p.ano * 100 + p.mes) * 100 + p.dia) * 10000
    + p.hora * 100 + p.minuto;
  return n(x) > n(y);
}

/// Os cultos das próximas [semanas] semanas que ainda não existem.
///
/// `existentes` são os ids que já estão no banco — inclusive os cancelados,
/// que continuam existindo de propósito, e por isso não voltam a ser criados.
///
/// Devolve `{id, campos}` pronto para gravar, com a equipe padrão escalada e
/// **todos como não confirmados**: ser escalado não é ter dito que vai.
export function cultosFaltando({
  slots = [],
  equipes = {},
  existentes = [],
  agoraMs,
  semanas = 4,
  criadoPor = '',
} = {}) {
  if (!Array.isArray(slots) || slots.length === 0) return [];

  const agora = agoraEmBrasilia(agoraMs);
  const limite = somarDias(agora, 7 * semanas);
  const jaExistem = new Set(existentes);
  const aCriar = [];

  for (const slot of slots) {
    if (!slot || typeof slot.weekday !== 'number') continue;
    let quando = proximaData(slot, agora);
    while (!depois(quando, limite)) {
      const id = idDoCulto(quando);
      // `depois(quando, agora)` descarta o culto de hoje que já passou.
      if (depois(quando, agora) && !jaExistem.has(id)) {
        aCriar.push({ id, campos: documentoDoCulto(slot, quando, id, equipes, criadoPor) });
        jaExistem.add(id);
      }
      quando = somarDias(quando, 7);
    }
  }

  aCriar.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return aCriar;
}

/// O documento do culto, no mesmo formato que o app grava.
///
/// Campo a campo igual ao `ScaleModel.toFirestore`: um campo faltando aqui
/// faria o app ler o padrão e, nos casos de `canceled` e `manuallyEdited`,
/// isso seria "não cancelado" e "não editado" — que por sorte é o certo para
/// um culto novo. Mesmo assim vão todos escritos, porque depender de sorte
/// na leitura é como um campo novo passa a faltar sem ninguém ver.
export function documentoDoCulto(slot, quando, id, equipes = {}, criadoPor = '') {
  const equipe = equipes[slot.teamId] ?? null;
  const membros = equipe && Array.isArray(equipe.members) ? equipe.members : [];
  return {
    id,
    date: instanteDe(quando),
    serviceType: (slot.name ?? '').trim() || 'Culto',
    songs: [],
    levitas: membros
      .filter((m) => m && typeof m.userId === 'string' && m.userId)
      .map((m) => ({
        userId: m.userId,
        // O app grava vazio aqui e resolve o nome pelo cadastro: nome copiado
        // no culto fica errado quando a pessoa corrige o próprio nome.
        userName: '',
        instrument: typeof m.instrument === 'string' ? m.instrument : 'other',
        confirmed: false,
      })),
    observations: '',
    createdBy: criadoPor,
    createdAt: new Date(),
    fromSlot: typeof slot.id === 'string' ? slot.id : '',
    teamId: typeof slot.teamId === 'string' ? slot.teamId : '',
    manuallyEdited: false,
    canceled: false,
    faltando: [],
  };
}
