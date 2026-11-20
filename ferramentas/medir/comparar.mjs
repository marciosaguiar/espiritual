// Compara duas medições de `medir_abertura.mjs` (antes e depois) em tabela.
//
//   node ferramentas/medir/comparar.mjs antes.json depois.json
//
// Mostra a MEDIANA de cada marca, para cada tipo de abertura, e o que foi
// baixado — que é onde se vê se uma mudança tirou tempo de verdade ou só
// mudou o tempo de lugar.

import fs from 'node:fs';

const [a, d] = process.argv.slice(2).map((p) => JSON.parse(fs.readFileSync(p, 'utf8')));

const med = (xs) => {
  const v = xs.filter((x) => typeof x === 'number').sort((p, q) => p - q);
  return v.length ? v[Math.floor(v.length / 2)] : null;
};
const seg = (ms) => (ms == null ? '—' : (ms / 1000).toFixed(1) + ' s');
const marca = (lista, nome) => med(lista.map((x) => x.marcas?.[nome]));
const kb = (lista, tipo) => med(lista.map((x) => x.rede?.[tipo]?.kb ?? 0));
const totalKb = (lista) => med(lista.map((x) => Object.values(x.rede || {}).reduce((s, t) => s + t.kb, 0)));

function bloco(titulo, la, ld, marcas) {
  console.log(`\n${titulo}`);
  console.log('  ' + 'momento'.padEnd(30) + 'antes'.padStart(9) + 'depois'.padStart(9) + 'diferença'.padStart(12));
  const linha = (nome, x, y) => {
    const dif = x != null && y != null ? ((y - x) / 1000).toFixed(1) + ' s' : '';
    console.log('  ' + nome.padEnd(30) + seg(x).padStart(9) + seg(y).padStart(9) + dif.padStart(12));
  };
  linha('tela de abertura (HTML)', med(la.map((x) => x.fcp)), med(ld.map((x) => x.fcp)));
  for (const [rotulo, nome] of marcas) linha(rotulo, marca(la, nome), marca(ld, nome));
  const ca = totalKb(la), cd = totalKb(ld);
  console.log('  ' + 'baixado (KB, página)'.padEnd(30) + String(ca ?? '—').padStart(9) + String(cd ?? '—').padStart(9) + String(ca != null && cd != null ? cd - ca : '').padStart(12));
  const tipos = new Set([...la, ...ld].flatMap((x) => Object.keys(x.rede || {})));
  for (const t of [...tipos].sort()) {
    const x = kb(la, t), y = kb(ld, t);
    if (!x && !y) continue;
    console.log('    ' + t.padEnd(28) + String(x).padStart(9) + String(y).padStart(9) + String(y - x).padStart(12));
  }
}

console.log(`perfil: ${a.perfil} → ${d.perfil}; repetições: ${a.repeticoes} → ${d.repeticoes}`);
bloco('PRIMEIRA ABERTURA (nada guardado; cai na tela de entrar)', a.frias, d.frias, [
  ['Dart começou (main)', 'dart-main'], ['Firebase pronto', 'firebase-pronto'],
  ['1ª tela do app (Flutter)', 'flutter-first-frame'],
]);
bloco('DEPOIS DE ENTRAR (primeira vez com dados, vindos do banco)', a.logins, d.logins, [
  ['escutas começaram', 'escutas-iniciando'], ['músicas chegaram', 'musicas-recebidas'],
  ['cultos chegaram', 'cultos-recebidos'], ['Início com dados', 'inicio-com-dados'],
]);
bloco('ABRIR DE NOVO (já usa o app: cache + sessão guardados)', a.quentes, d.quentes, [
  ['Dart começou (main)', 'dart-main'], ['Firebase pronto', 'firebase-pronto'],
  ['1ª tela do app (Flutter)', 'flutter-first-frame'], ['escutas começaram', 'escutas-iniciando'],
  ['músicas chegaram', 'musicas-recebidas'], ['cultos chegaram', 'cultos-recebidos'],
  ['Início com dados', 'inicio-com-dados'],
]);
