// "Rodou às tantas horas": o carimbo que as rotinas deixam no banco.
//
// POR QUE ISTO EXISTE
//
// Os robôs falharam em silêncio por dias. A rotina diária batia num 403, o
// motivo ficava no log do Worker, e ninguém abre log de Worker — então a
// escala parou de ser criada e o lembrete da véspera parou de chegar, sem
// nada vermelho em lugar nenhum. A causa era uma chave digitada errada na
// Cloudflare, e ela esperou dias por alguém que fosse olhar.
//
// Com o carimbo, o app sabe responder "quando foi a última vez que isto
// rodou" — e o cartão "Saúde do sistema", no Perfil do líder, fica vermelho
// quando passa de 36 horas. O silêncio deixou de ser invisível.
//
// A HORA É DO SERVIDOR, e a regra do banco exige
//
// Com a hora do runner do GitHub, um relógio torto faria o carimbo parecer
// mais novo do que é — e aí a tela diria "rodou hoje" sobre uma rotina que
// não roda há uma semana. O alarme que mente é pior que alarme nenhum. Por
// isso a gravação usa `setToServerValue: REQUEST_TIME`, que é o mesmo
// mecanismo do `serverTimestamp()` dos aplicativos, e a regra recusa
// qualquer outro valor em `em`.
//
// FALHAR AQUI NÃO DERRUBA A ROTINA
//
// Quando o carimbo não consegue ser gravado, o trabalho de verdade já foi
// feito: os cultos foram criados, os avisos foram mandados. Derrubar o job
// por causa do registro transformaria um problema de anotação em uma
// execução perdida.

const RAIZ = 'https://firestore.googleapis.com/v1';

/// Os nomes permitidos, iguais aos da regra do banco e do app.
export const ROTINAS = ['cultos', 'vespera', 'faxina'];

/// Grava `saude/<qual>` como o robô (um líder comum).
///
/// Devolve `{ ok, erro }` em vez de lançar: quem chama decide, e a decisão é
/// sempre "segue em frente".
export async function carimbar({ projectId, idToken, qual, ok, detalhe }) {
  if (!ROTINAS.includes(qual)) {
    return { ok: false, erro: `rotina desconhecida: ${qual}` };
  }
  if (!projectId || !idToken) {
    return { ok: false, erro: 'sem projeto ou sem token' };
  }

  const caminho =
    `projects/${projectId}/databases/(default)/documents/saude/${qual}`;

  // O texto entra cortado em 300 para casar com o teto da regra: estourar
  // devolveria 403, que não explica nada no log de um job.
  const texto = String(detalhe ?? '').slice(0, 300);

  try {
    const r = await fetch(`${RAIZ}/projects/${projectId}/databases/(default)/documents:commit`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${idToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        writes: [
          {
            update: {
              name: caminho,
              fields: {
                ok: { booleanValue: ok === true },
                detalhe: { stringValue: texto },
              },
            },
            // Só estes dois campos vêm do robô; `em` vem do servidor.
            updateMask: { fieldPaths: ['ok', 'detalhe'] },
            updateTransforms: [
              { fieldPath: 'em', setToServerValue: 'REQUEST_TIME' },
            ],
          },
        ],
      }),
    });
    if (!r.ok) {
      const corpo = await r.text();
      return { ok: false, erro: `${r.status} ${corpo.slice(0, 200)}` };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, erro: String(e?.message ?? e) };
  }
}

/// Carimba e escreve uma linha no log, sem nunca derrubar o job.
export async function carimbarEDizer(dados) {
  const r = await carimbar(dados);
  if (r.ok) {
    console.log(`Carimbo de "${dados.qual}" gravado.`);
  } else {
    // Vai para o log como aviso, não como erro: o trabalho de verdade já foi
    // feito, e o único prejuízo é o cartão de saúde ficar sem a data.
    console.warn(`Não gravei o carimbo de "${dados.qual}": ${r.erro}`);
    console.warn('O cartão "Saúde do sistema" vai mostrar esta rotina como '
      + 'sem registro. A rotina em si rodou.');
  }
  return r;
}
