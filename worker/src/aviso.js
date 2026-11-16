// O que o aviso diz, e quem deve receber. Funções puras, porque é aqui que
// dá para errar sem ninguém ver: um aviso em branco, ou um aviso indo para
// quem pediu silêncio.

/// Quanto tempo depois de gravada uma mensagem ainda pode gerar aviso.
///
/// É a trava contra alguém pegar o id de uma mensagem antiga — do chat, que
/// todo aprovado lê — e usá-lo para fazer o Worker avisar o ministério de
/// novo. Dois minutos cobrem uma conexão ruim e nada além disso.
export const JANELA_DO_AVISO_MS = 2 * 60 * 1000;

/// O título e o corpo do aviso, a partir da mensagem gravada.
///
/// O título é só o nome porque é assim que o Android e o iPhone desenham:
/// nome em negrito, recado embaixo. Lido em voz alta dá "Fulano: começo da
/// mensagem", que é o que foi pedido.
export function textoDoAviso(mensagem, { mencionou = false } = {}) {
  const nome = (mensagem?.userName ?? '').trim() || 'Alguém';
  // Quem foi mencionado recebe um aviso DIFERENTE, e é por isso que o leque
  // de envio sai em dois: o mesmo texto para os dois grupos não diria à
  // pessoa por que ela foi acordada com o chat silenciado.
  const marca = mencionou ? '📣 ' : '';

  if (mensagem?.audioId) {
    return {
      titulo: nome,
      corpo: `${marca}${mencionou ? 'mencionou você · ' : ''}🎤 Mensagem de voz`,
    };
  }

  // Quebras de linha viram espaço: o aviso é uma linha só, e um recado
  // colado de outro lugar chegaria com um buraco no meio.
  const texto = String(mensagem?.text ?? '').replace(/\s+/g, ' ').trim();
  if (!texto) {
    // Não deveria acontecer — a regra do banco exige texto ou áudio —, mas
    // um aviso em branco é pior que um aviso genérico.
    return { titulo: nome, corpo: `${marca}Mandou uma mensagem` };
  }

  const limite = 120;
  const corpo = texto.length > limite
    ? `${texto.slice(0, limite - 1).trimEnd()}…`
    : texto;

  const prefixo = mencionou ? `${marca}mencionou você: ` : '';
  if (mensagem?.linkedSongName) {
    return {
      titulo: nome,
      corpo: `${prefixo}🎵 ${mensagem.linkedSongName} · ${corpo}`,
    };
  }
  return { titulo: nome, corpo: `${prefixo}${corpo}` };
}

/// A data e a hora de um culto, em português e no fuso de Brasília.
///
/// O Worker roda em qualquer lugar do mundo, então a hora NÃO pode sair do
/// relógio dele: um culto de domingo 19h apareceria como sábado 22h para
/// metade do ministério.
export function quandoEhOCulto(iso, agoraMs) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const fuso = 'America/Sao_Paulo';
  const hora = new Intl.DateTimeFormat('pt-BR', {
    timeZone: fuso, hour: '2-digit', minute: '2-digit',
  }).format(d);

  // "amanhã" e "hoje" são mais claros que a data, e é o que o lembrete da
  // véspera precisa dizer.
  const dia = (x) => new Intl.DateTimeFormat('en-CA', {
    timeZone: fuso, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(x);
  const agora = new Date(agoraMs ?? Date.now());
  const amanha = new Date(agora.getTime() + 86400000);
  if (dia(d) === dia(agora)) return `hoje às ${hora}`;
  if (dia(d) === dia(amanha)) return `amanhã às ${hora}`;

  const data = new Intl.DateTimeFormat('pt-BR', {
    timeZone: fuso, weekday: 'long', day: '2-digit', month: '2-digit',
  }).format(d);
  return `${data} às ${hora}`;
}

/// "Você foi escalado": o aviso que o líder dispara ao salvar a escala.
export function textoDeEscalado(culto, funcao, agoraMs) {
  const tipo = (culto?.serviceType ?? '').trim() || 'Culto';
  const quando = quandoEhOCulto(culto?.date, agoraMs);
  const onde = funcao ? ` · ${funcao}` : '';
  return {
    titulo: 'Você foi escalado',
    corpo: `${tipo} ${quando}${onde}`.trim(),
  };
}

/// O lembrete da véspera, com as músicas — e pedindo a confirmação de quem
/// ainda não confirmou.
export function textoDaVespera({ culto, confirmado, musicas = [], agoraMs }) {
  const tipo = (culto?.serviceType ?? '').trim() || 'Culto';
  const quando = quandoEhOCulto(culto?.date, agoraMs);
  const lista = musicas.filter(Boolean).slice(0, 3).join(', ');
  const resto = musicas.length > 3 ? ` +${musicas.length - 3}` : '';

  const partes = [`${tipo} ${quando}`.trim()];
  if (lista) partes.push(`🎵 ${lista}${resto}`);
  // O pedido de confirmação vem por ÚLTIMO de propósito: é a única parte que
  // pede ação, e no aviso curto do celular o fim é o que fica mais perto do
  // dedo que vai tocar.
  if (!confirmado) partes.push('Toque para confirmar sua presença');

  return {
    titulo: confirmado ? 'Lembrete do culto' : 'Confirme sua presença',
    corpo: partes.join(' · '),
  };
}

/// Este aparelho deve receber o aviso desta mensagem?
///
/// Um "não" aqui não é erro: é alguém que desligou os avisos, pediu silêncio
/// ou é o próprio autor da mensagem.
export function deveAvisar(inscricao, opcoes = {}) {
  const { autorId, agoraMs, mencionados = [], tipo = 'chat' } = opcoes;
  if (!inscricao) return false;
  if (autorId && inscricao.userId === autorId) return false;
  if (!inscricao.endpoint || !inscricao.p256dh || !inscricao.auth) return false;

  // Cada tipo de aviso se liga à parte: mensagem de chat chega a toda hora,
  // "você foi escalado" chega raro e importa. CHAVE AUSENTE É LIGADA —
  // aparelho inscrito antes desta mudança não tem o campo, e se a falta
  // valesse como "desligado" o ministério pararia de receber aviso de uma
  // hora para outra, sem ninguém ter mexido em nada.
  const tipos = inscricao.tipos;
  if (tipos && typeof tipos === 'object' && tipos[tipo] === false) {
    return false;
  }

  // AVISOS DESLIGADOS É DESLIGADO, inclusive para menção. Quem desligou fez
  // uma escolha sobre o app todo; furá-la seria o app decidindo por cima da
  // pessoa, e ela não teria como se proteger a não ser desinstalando.
  if (inscricao.avisosLigados === false) return false;

  // "Silenciar até amanhã" é TEMPORÁRIO: é "não me acorde por bobagem", não
  // "não me chame". Ser chamado pelo nome fura esse silêncio — é o caso de
  // "@Ana, você consegue vir às 18h?" na véspera.
  const mencionado = Array.isArray(mencionados) &&
    mencionados.includes(inscricao.userId);
  if (mencionado) return true;

  const ate = inscricao.silenciarAte;
  if (ate) {
    const quando = Date.parse(ate);
    if (!Number.isNaN(quando) && quando > (agoraMs ?? Date.now())) return false;
  }
  return true;
}

/// Quem recebe o aviso de "novo pedido de entrada".
///
/// Só os LÍDERES: são eles que aprovam. Robô fora, como em todo o resto — ele
/// não usa o app, não tem inscrição e não aprova ninguém.
///
/// Está aqui, separado da rota, porque é a parte que erra em silêncio: mandar
/// para o ministério inteiro (todos leriam "alguém quer entrar" sem poder
/// fazer nada) ou para ninguém (o líder nunca sabe) dão a mesma resposta
/// "enviado" no final.
export function quemAvisaDoPedido(pessoas, inscricoes, opcoes = {}) {
  const lideres = new Set(
    (Array.isArray(pessoas) ? pessoas : [])
      // `bot !== true` e não `!bot`: campo ausente é gente, que é o caso de
      // todo cadastro antigo.
      .filter((p) => p && p.role === 'admin' && p.bot !== true)
      .map((p) => p._id),
  );
  return (Array.isArray(inscricoes) ? inscricoes : []).filter(
    (i) => i && lideres.has(i.userId)
        && deveAvisar(i, { ...opcoes, tipo: 'pedido' }),
  );
}

/// Limite por remetente, na memória deste isolate.
///
/// É de propósito simples: a Cloudflare roda vários isolates, então o limite
/// de verdade é por isolate e não é exato. A trava que segura abuso é outra —
/// token verificado, remetente aprovado e a mensagem tem de existir, ser
/// dele e ter acabado de ser escrita. Isto aqui é o cinto: impede que um
/// script em laço queime a cota de leitura do Firestore.
const contagem = new Map();

export function dentroDoLimite(autorId, maximoPorMinuto = 30, agoraMs) {
  const agora = agoraMs ?? Date.now();
  const janela = 60 * 1000;
  const antes = contagem.get(autorId) ?? [];
  const recentes = antes.filter((t) => agora - t < janela);
  if (recentes.length >= maximoPorMinuto) {
    contagem.set(autorId, recentes);
    return false;
  }
  recentes.push(agora);
  contagem.set(autorId, recentes);
  // Não deixa o mapa crescer para sempre num isolate de vida longa.
  if (contagem.size > 500) {
    for (const [quem, quando] of contagem) {
      if (!quando.some((t) => agora - t < janela)) contagem.delete(quem);
    }
  }
  return true;
}

export function esquecerLimites() {
  contagem.clear();
}
