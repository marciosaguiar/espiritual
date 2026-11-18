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

/// A causa provável e o conserto, a partir do status e do corpo.
export function porQueRecusou(status, corpo) {
  const texto = String(corpo ?? '');

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
  if (status === 403 && /aprovad/i.test(texto)) {
    return 'O CADASTRO DO ROBÔ NÃO ESTÁ APROVADO. Ele entra como gente, e '
      + 'nasce "pendente" como todo mundo: aprove-o em Membros, ou no '
      + 'console (Firestore → users → o documento dele → role: admin).';
  }
  if (status === 403) {
    return 'O ROBÔ NÃO É LÍDER. Esta rota é só de líder, e o cadastro dele '
      + 'está como levita: no console, Firestore → users → o documento dele '
      + '→ role: admin.';
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
    const r = await fetch(`${worker}/`);
    const t = await r.text();
    if (!r.ok) return `a raiz do Worker respondeu ${r.status}`;
    const d = JSON.parse(t);
    if (d.configurado) return 'está no ar e com todos os segredos';
    return `está no ar, mas FALTAM os segredos: ${(d.falta ?? []).join(', ')}`;
  } catch (e) {
    return `não respondeu (${String(e).slice(0, 80)}) — o endereço em `
      + 'avisos_config.dart aponta para o Worker certo?';
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
