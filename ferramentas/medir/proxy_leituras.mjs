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
  const t0 = Date.now();

  const servidor = http.createServer((req, res) => {
    if (cortado) { req.destroy(); return; }
    const alvo = http.request(
      { host, port: para, path: req.url, method: req.method, headers: req.headers },
      (resp) => {
        res.writeHead(resp.statusCode, resp.headers);
        let resto = '';
        resp.on('data', (pedaco) => {
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
    });
    req.pipe(alvo);
  });
  await new Promise((ok) => servidor.listen(de, host, ok));
  return {
    lidos: () => lidos,
    tokensEnviados: () => tokensEnviados,
    zerar: () => { lidos = 0; porMomento = []; },
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
