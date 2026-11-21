// Um proxy entre o app e o emulador do Firestore que CONTA os documentos que o
// banco entrega — que é o que o Firebase cobra como leitura.
//
//   const p = await iniciarProxy({ de: 8081, para: 8080 });
//   p.zerar(); ... p.lidos() ...; p.parar();
//
// Como conta: o Firestore web fala por WebChannel (HTTP em pedaços), e cada
// documento entregue por uma consulta chega como um item `"documentChange"`
// (e `"documentDelete"` quando some do resultado). Conto as ocorrências no
// corpo das respostas, guardando as últimas letras de cada pedaço para a
// palavra que cai na emenda não escapar.
//
// O QUE ISTO NÃO É: o emulador não implementa a regra dos 30 minutos (consulta
// religada depois de mais de 30 min sem token válido = leitura de tudo de
// novo). Quem mede aqui é "quantos documentos o servidor mandou nesta
// abertura"; a regra dos 30 minutos entra na CONTA do relatório, não aqui.

import http from 'node:http';

const PALAVRAS = ['"documentChange"', '"documentDelete"'];

// Para dizer DE ONDE vêm os documentos: cada `documentChange` traz o caminho do
// documento (`projects/.../documents/scales/2026-11-22_0800`). O caminho vira a
// COLEÇÃO trocando os ids por `*` (`hinarios/*/hinos`), que é o que importa
// para achar quem está lendo demais.
const CAMINHO = /"documentChange":\{"document":\{"name":"projects\/[^"\/]*\/databases\/[^"\/]*\/documents\/([^"]+)"[\s\S]*?"targetIds":\[([\d,]+)\]/g;
function colecaoDe(caminho) {
  const partes = caminho.split('/');
  partes.pop(); // o id do documento
  return partes.map((x, i) => (i % 2 === 1 ? '*' : x)).join('/') || '(raiz)';
}

export async function iniciarProxy({ de, para, host = '127.0.0.1' }) {
  let cortado = false; // rede "desligada": nada passa
  let lidos = 0;
  // Quantas vezes o APP mandou um "resumeToken" ao banco (é o que o servidor de
  // verdade usa para entregar só o que mudou). O emulador pode ignorá-lo —
  // e então uma abertura "quente" aqui custa como uma fria, sem que isso seja
  // o que acontece em produção. Contar os tokens enviados prova de quem é a
  // diferença.
  let tokensEnviados = 0;
  let porMomento = []; // [ms, total]
  let porColecao = {}; // { 'scales': 20, ... } — só documentChange
  // Cada (consulta, documento) entregue UMA vez. O emulador às vezes reenvia o
  // resultado inteiro de uma consulta (observado: a lista de pessoas chegando
  // duas vezes, 270 ms depois, com um só pedido do app), e isso infla `lidos`
  // sem o app ter pedido nada a mais. `distintos` é a demanda do app; `lidos` é
  // o que o emulador mandou — a verdade de produção está entre os dois.
  let distintos = new Set();
  const t0 = Date.now();

  const servidor = http.createServer((req, res) => {
    if (cortado) { req.destroy(); return; }
    const alvo = http.request(
      { host, port: para, path: req.url, method: req.method, headers: req.headers },
      (resp) => {
        res.writeHead(resp.statusCode, resp.headers);
        let resto = '';
        let acum = ''; // o corpo inteiro desta resposta, para achar os caminhos
        let posCaminho = 0;
        resp.on('data', (pedaco) => {
          acum += pedaco.toString('latin1');
          if (process.env.DEBUG_RESET) {
            const t = pedaco.toString('latin1');
            for (const palavra of ['"RESET"', '"CURRENT"', '"NO_CHANGE"', '"ADD"', '"REMOVE"']) {
              let k = 0, j = -1;
              while ((j = t.indexOf(palavra, j + 1)) !== -1) k++;
              if (k) console.log(`   STREAM +${Date.now() - t0}ms ${palavra} x${k}`);
            }
          }
          CAMINHO.lastIndex = posCaminho;
          let m;
          while ((m = CAMINHO.exec(acum)) !== null) {
            distintos.add(`${m[2]}|${m[1]}`);
            const col = colecaoDe(m[1]);
            if (process.env.DEBUG_DOCS === col) console.log(`   DOC +${Date.now() - t0}ms ${m[1]}`);
            porColecao[col] = (porColecao[col] || 0) + 1;
            posCaminho = CAMINHO.lastIndex;
          }
          const texto = resto + pedaco.toString('latin1');
          for (const p of PALAVRAS) {
            let i = -1;
            while ((i = texto.indexOf(p, i + 1)) !== -1) {
              // Só conto o que NÃO caiu na cauda já contada no pedaço anterior.
              if (i + p.length > resto.length) {
                lidos++;
                porMomento.push([Date.now() - t0, lidos]);
              }
            }
          }
          resto = texto.slice(-20);
          res.write(pedaco);
        });
        resp.on('end', () => res.end());
      },
    );
    alvo.on('error', () => { try { res.destroy(); } catch {} });
    req.on('data', (c) => {
      const t = c.toString('latin1');
      if (t.includes('resumeToken')) tokensEnviados++;
      // Só para depurar de onde vem uma coleção: DEBUG_PEDIDO=users mostra o
      // corpo dos pedidos que citam essa coleção.
      if (process.env.DEBUG_PEDIDO) {
        let d = t;
        try { d = decodeURIComponent(t.replace(/\+/g, ' ')); } catch {}
        // Cada addTarget do pedido que cita a coleção, com a hora.
        for (const seg of d.split('"addTarget"').slice(1)) {
          if (seg.includes(`"collectionId":"${process.env.DEBUG_PEDIDO}"`)) {
            console.log(`   ALVO +${Date.now() - t0}ms`, seg.replace(/\s+/g, ' ').slice(0, 330));
          }
        }
      }
    });
    req.pipe(alvo);
  });
  await new Promise((ok) => servidor.listen(de, host, ok));
  return {
    lidos: () => lidos,
    tokensEnviados: () => tokensEnviados,
    zerar: () => { lidos = 0; porMomento = []; porColecao = {}; distintos = new Set(); },
    // Documentos distintos por consulta (ver `distintos` acima).
    distintos: () => distintos.size,
    // Quantos documentos vieram de cada coleção (soma = `lidos()` menos os
    // `documentDelete`, que não trazem caminho).
    porColecao: () => ({ ...porColecao }),
    cortar: (v) => { cortado = !!v; },
    linhaDoTempo: () => porMomento,
    parar: () => servidor.close(),
  };
}

// Como programa: deixa o proxy de pé (só repassa e conta), para os medidores
// que não o sobem sozinhos (`medir_abertura.mjs`).
//
//   node ferramentas/medir/proxy_leituras.mjs 8081 8080
if (process.argv[1] && process.argv[1].endsWith('proxy_leituras.mjs')) {
  const [de = '8081', para = '8080'] = process.argv.slice(2);
  const p = await iniciarProxy({ de: Number(de), para: Number(para) });
  console.log(`proxy ${de} -> ${para}`);
  process.on('SIGTERM', () => { console.log(`documentos entregues: ${p.lidos()}`); process.exit(0); });
}
