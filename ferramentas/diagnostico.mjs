// Por que o Worker recusou, em português, e o que fazer a respeito.
//
// POR QUE ISTO EXISTE
//
// A rotina diária falhou duas noites seguidas e o log dizia só
// "O Worker respondeu 403: {...}". Status não é diagnóstico: cada um desses
// números tem uma causa diferente e um conserto diferente, e nenhum deles
// está no código do app — estão na Cloudflare, no console do Firebase ou no
// cadastro do robô.
//
// Um job que falha sem dizer o que fazer é a mesma falha silenciosa que este
// projeto combate dentro do app: ninguém abre log de Worker por esporte.

/// O conserto que o PRÓPRIO Worker mandou, se mandou.
///
/// Ele sabe mais que a tabela abaixo, que adivinha pelo número: a resposta
/// vem de dentro, com o nome do segredo ou do cadastro que está errado.
function consertoDoCorpo(texto) {
  try {
    const d = JSON.parse(texto);
    if (!d || !d.conserto) return '';
    return `${d.erro ?? 'O Worker recusou.'} CONSERTO: ${d.conserto}`;
  } catch (_) {
    // Corpo que não é JSON (página de erro da Cloudflare, por exemplo): a
    // tabela por status resolve.
    return '';
  }
}

/// A causa provável e o conserto, a partir do status e do corpo.
export function porQueRecusou(status, corpo) {
  const texto = String(corpo ?? '');

  const doWorker = consertoDoCorpo(texto);
  if (doWorker) return doWorker;

  if (status === 404) {
    return 'A ROTA NÃO EXISTE no Worker publicado. O código no repositório '
      + 'está à frente do que está no ar: rode `cd worker && npx wrangler '
      + 'deploy`.';
  }
  if (status === 503) {
    return 'O WORKER ESTÁ SEM SEGREDOS. Falta pelo menos um de VAPID_PUBLIC, '
      + 'VAPID_PRIVATE, VAPID_ASSUNTO, FIREBASE_API_KEY, '
      + 'FIREBASE_PROJECT_ID, ROBO_EMAIL ou ROBO_SENHA. A linha "como está o '
      + 'Worker" abaixo diz exatamente quais.';
  }
  if (status === 401) {
    return 'O WORKER NÃO ACEITOU O LOGIN DO ROBÔ. O token é de um projeto do '
      + 'Firebase e o Worker espera outro: confira se FIREBASE_PROJECT_ID na '
      + 'Cloudflare é o mesmo projeto do app.';
  }
  if (status === 403 && /não tem cadastro/i.test(texto)) {
    return 'A CONTA DO JOB EXISTE NO AUTHENTICATION, MAS NÃO NO BANCO. É o '
      + 'que acontece com conta criada direto no console do Firebase: ela não '
      + 'aparece em Membros e ninguém consegue aprová-la. O robô precisa se '
      + 'cadastrar pelo app, uma vez, e ser aprovado como líder.';
  }
  if (status === 403 && /aprovad/i.test(texto)) {
    return 'O CADASTRO DE QUEM O JOB USA NÃO ESTÁ APROVADO. Atenção: a conta '
      + 'do job é FAXINA_EMAIL (segredo do GitHub), que pode NÃO ser a conta '
      + 'que você vê aprovada em Membros. Confira /saude: se o robô da '
      + 'Cloudflare estiver bom, o engano está no segredo do GitHub.';
  }
  if (status === 403) {
    return 'A CONTA DO JOB ESTÁ APROVADA, MAS NÃO É LÍDER. Esta rota é só de '
      + 'líder: promova em Membros a conta de FAXINA_EMAIL (segredo do '
      + 'GitHub), que é a que o job usa.';
  }
  if (status === 429) {
    return 'Limite por minuto. Espere um minuto e rode de novo; se repetir '
      + 'sem ninguém ter disparado nada, há algo chamando o Worker em laço.';
  }
  if (status >= 500) {
    return 'O WORKER DEU ERRO POR DENTRO. O motivo fica no log dele, não '
      + 'aqui: rode `cd worker && npx wrangler tail` e dispare a rotina de '
      + 'novo para ver a linha do erro.';
  }
  return 'Status inesperado. O corpo da resposta acima é o que o Worker '
    + 'tinha a dizer.';
}

/// Pergunta ao Worker se ele está configurado.
///
/// A rota `/` responde sem login e diz `configurado` e `falta` — então ela
/// resolve sozinha o caso mais comum (segredo faltando na Cloudflare) sem
/// ninguém abrir painel nenhum.
export async function comoEstaOWorker(worker) {
  try {
    const r = await fetch(`${worker}/saude`);
    // Worker publicado antes desta rota existir.
    if (r.status === 404) {
      return (await comoEstaARaiz(worker)) + ' — e o Worker no ar é anterior '
        + 'à rota /saude, que diria se o robô dele entra e está aprovado: '
        + '`cd worker && npx wrangler deploy`';
    }
    const t = await r.text();
    if (!r.ok) return `/saude respondeu ${r.status}`;
    const d = JSON.parse(t);
    if (!d.configurado) {
      return `está no ar, mas FALTAM os segredos: ${(d.falta ?? []).join(', ')}`;
    }
    const partes = [`está no ar, com os segredos, e o robô ${d.robo}`];
    if (d.conserto) partes.push(`CONSERTO: ${d.conserto}`);
    return partes.join(' — ');
  } catch (e) {
    return `não respondeu (${String(e).slice(0, 80)}) — o endereço em `
      + 'avisos_config.dart aponta para o Worker certo?';
  }
}

/// A raiz, que só diz se os segredos estão preenchidos.
async function comoEstaARaiz(worker) {
  try {
    const r = await fetch(`${worker}/`);
    const t = await r.text();
    if (!r.ok) return `a raiz do Worker respondeu ${r.status}`;
    const d = JSON.parse(t);
    if (d.configurado) return 'está no ar e com todos os segredos';
    return `está no ar, mas FALTAM os segredos: ${(d.falta ?? []).join(', ')}`;
  } catch (e) {
    return `não respondeu (${String(e).slice(0, 80)})`;
  }
}

/// Imprime o diagnóstico completo de uma resposta ruim.
export async function explicarFalha(worker, status, corpo) {
  console.error(`O Worker respondeu ${status}: ${corpo}`);
  console.error('');
  console.error('CAUSA PROVÁVEL: ' + porQueRecusou(status, corpo));
  console.error('');
  console.error('Como está o Worker: ' + (await comoEstaOWorker(worker)));
}
