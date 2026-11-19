/// A saúde do sistema, em português de gente.
///
/// POR QUE ISTO EXISTE
///
/// Os robôs falharam em silêncio por dias. A rotina diária batia num 403, o
/// log do Worker dizia o motivo, e ninguém abre log de Worker — então a
/// escala parou de ser criada e o lembrete da véspera parou de chegar sem
/// que nada vermelho aparecesse em lugar nenhum. A causa final era uma
/// `FIREBASE_API_KEY` digitada errada na Cloudflare, e ela esperou dias por
/// alguém que fosse olhar.
///
/// Um robô que falha calado é pior que um robô que não existe: quem conta
/// com ele para avisar o ministério não tem como saber que parou. Daí esta
/// tela — e o aviso vermelho no Início quando algo não roda há mais de um
/// dia.
library;

/// O que o Worker respondeu em `GET /saude`.
///
/// Nulo em `SaudeDoSistema.worker` significa "não consegui falar com ele", que
/// NÃO é a mesma coisa que "ele está quebrado": pode ser a internet do
/// celular. Confundir os dois acenderia alarme vermelho no avião.
class SaudeDoWorker {
  /// Todos os segredos estão preenchidos na Cloudflare?
  final bool configurado;

  /// Quais faltam, quando faltam.
  final List<String> falta;

  /// O robô consegue entrar na conta dele?
  final bool entra;

  /// A frase que o próprio Worker escreveu sobre o robô.
  final String robo;

  /// O conserto, quando ele sabe qual é.
  final String? conserto;

  const SaudeDoWorker({
    required this.configurado,
    this.falta = const [],
    required this.entra,
    required this.robo,
    this.conserto,
  });

  /// O robô está líder? Vem da frase do Worker, que é quem leu o cadastro.
  ///
  /// Comparação por texto porque é o que a rota devolve, e o Worker é a
  /// fonte: ele entrou no banco e leu o documento. Repetir a leitura aqui
  /// custaria uma leitura de Firestore por abertura do app, para saber o que
  /// já está na resposta.
  bool get roboLider => robo.contains('está líder');

  factory SaudeDoWorker.fromJson(Map<String, dynamic> d) => SaudeDoWorker(
        configurado: d['configurado'] == true,
        falta: (d['falta'] as List?)?.map((f) => '$f').toList() ?? const [],
        entra: d['entra'] == true,
        robo: (d['robo'] as String?) ?? '',
        conserto: d['conserto'] as String?,
      );
}

/// "Rodou às tantas horas", gravado por um robô ao terminar bem.
class CarimboDeSaude {
  final DateTime em;
  final bool ok;
  final String detalhe;

  const CarimboDeSaude({
    required this.em,
    required this.ok,
    this.detalhe = '',
  });
}

enum EstadoDeSaude {
  /// Está como deveria.
  ok,

  /// Ainda não é problema, mas já passou da hora de olhar.
  alerta,

  /// Está quebrado, e alguém precisa mexer.
  ruim,

  /// Não deu para saber. Nunca acende alarme — ver [SaudeDoWorker].
  desconhecido,
}

/// Uma linha do cartão "Saúde do sistema".
class ItemDeSaude {
  final String titulo;
  final EstadoDeSaude estado;

  /// O que está acontecendo, em uma frase.
  final String detalhe;

  /// O que fazer a respeito. Nulo quando não há nada a fazer — e isso é
  /// regra, não descuido: instrução na tela quando está tudo bem ensina a
  /// pessoa a não ler as instruções.
  final String? oQueFazer;

  const ItemDeSaude({
    required this.titulo,
    required this.estado,
    required this.detalhe,
    this.oQueFazer,
  });
}

/// O retrato do sistema: as linhas do cartão e se há alarme.
class SaudeDoSistema {
  final List<ItemDeSaude> itens;

  const SaudeDoSistema(this.itens);

  /// Há algo que mereça o aviso vermelho no Início?
  ///
  /// SÓ `ruim`. `desconhecido` nunca acende: um celular sem internet não é um
  /// sistema quebrado, e alarme que mente é alarme que se aprende a ignorar.
  bool get temAlarme => itens.any((i) => i.estado == EstadoDeSaude.ruim);

  /// A primeira coisa quebrada, para o aviso do Início poder ser curto.
  ItemDeSaude? get pior {
    for (final i in itens) {
      if (i.estado == EstadoDeSaude.ruim) return i;
    }
    return null;
  }

  // ─── Os prazos ──────────────────────────────────────────────────────────
  //
  // Um job que roda uma vez por dia chega legitimamente perto das 24 h sem
  // ter falhado: ele vai rodar hoje de novo. Por isso o alerta é em 26 h — a
  // folga do atraso do GitHub — e o VERMELHO só em 36 h, que é quando uma
  // execução foi mesmo perdida. Acender em 24 h daria alarme falso todo dia,
  // pouco antes da hora do job, e essa é a maneira mais rápida de ensinar
  // alguém a ignorar a tela.

  static const Duration prazoDeAlerta = Duration(hours: 26);
  static const Duration prazoRuim = Duration(hours: 36);

  /// Monta o retrato. Função pura: recebe tudo, inclusive [agora].
  ///
  /// `agora` entra como parâmetro pelo mesmo motivo de `aindaVale` e
  /// `minhasProximasMusicas`: é conta de data, e conta de data quebra na
  /// virada do dia — que é exatamente onde o teste precisa poder ficar.
  static SaudeDoSistema avaliar({
    required SaudeDoWorker? worker,
    required Map<String, CarimboDeSaude> carimbos,
    required DateTime agora,
  }) {
    final itens = <ItemDeSaude>[];

    // ── O servidor dos avisos ──
    if (worker == null) {
      itens.add(const ItemDeSaude(
        titulo: 'Servidor dos avisos',
        estado: EstadoDeSaude.desconhecido,
        detalhe: 'Não consegui falar com ele agora.',
        oQueFazer: 'Pode ser a sua internet. Tente de novo mais tarde; se '
            'continuar assim, avise quem cuida do app.',
      ));
    } else if (!worker.configurado) {
      itens.add(ItemDeSaude(
        titulo: 'Servidor dos avisos',
        estado: EstadoDeSaude.ruim,
        detalhe: worker.falta.isEmpty
            ? 'Faltam configurações nele.'
            : 'Faltam configurações: ${worker.falta.join(', ')}.',
        oQueFazer: worker.conserto ??
            'Quem cuida do app precisa preencher isso na Cloudflare.',
      ));
    } else {
      itens.add(const ItemDeSaude(
        titulo: 'Servidor dos avisos',
        estado: EstadoDeSaude.ok,
        detalhe: 'No ar e configurado.',
      ));
    }

    // ── O robô ──
    if (worker != null) {
      if (!worker.entra) {
        itens.add(ItemDeSaude(
          titulo: 'Robô dos avisos',
          estado: EstadoDeSaude.ruim,
          detalhe: 'Ele não consegue entrar na conta dele.',
          oQueFazer: worker.conserto ??
              'Confira o e-mail e a senha do robô na Cloudflare.',
        ));
      } else if (!worker.roboLider) {
        itens.add(ItemDeSaude(
          titulo: 'Robô dos avisos',
          estado: EstadoDeSaude.ruim,
          detalhe: 'Ele entra, mas não é líder: ${worker.robo}.',
          oQueFazer: worker.conserto ??
              'Em Membros, na seção "Contas de robô", promova-o a líder.',
        ));
      } else {
        itens.add(const ItemDeSaude(
          titulo: 'Robô dos avisos',
          estado: EstadoDeSaude.ok,
          detalhe: 'Entra no banco e é líder.',
        ));
      }
    }

    // ── As rotinas ──
    itens.add(_daRotina(
      titulo: 'Criação dos cultos',
      carimbo: carimbos['cultos'],
      agora: agora,
      oQueFazerQuandoVelho:
          'Abra o app como líder, que ele cria os cultos que faltam na hora. '
          'Depois avise quem cuida do app: a rotina diária parou.',
    ));
    itens.add(_daRotina(
      titulo: 'Lembrete da véspera',
      carimbo: carimbos['vespera'],
      agora: agora,
      oQueFazerQuandoVelho:
          'Ninguém está recebendo o aviso do culto de amanhã. Avise quem '
          'cuida do app: a rotina diária parou.',
    ));
    itens.add(_daRotina(
      titulo: 'Faxina do chat',
      carimbo: carimbos['faxina'],
      agora: agora,
      oQueFazerQuandoVelho:
          'As mensagens antigas não estão sendo apagadas. Não é urgente, mas '
          'avise quem cuida do app.',
    ));

    return SaudeDoSistema(itens);
  }

  static ItemDeSaude _daRotina({
    required String titulo,
    required CarimboDeSaude? carimbo,
    required DateTime agora,
    required String oQueFazerQuandoVelho,
  }) {
    if (carimbo == null) {
      // Pode ser que nunca tenha rodado, ou que tenha rodado antes de o
      // carimbo existir. Dizer "quebrado" numa dessas seria mentira, e dizer
      // "ok" na outra também.
      return ItemDeSaude(
        titulo: titulo,
        estado: EstadoDeSaude.desconhecido,
        detalhe: 'Sem registro de execução.',
        oQueFazer: 'Se o app foi atualizado hoje, isto se resolve sozinho na '
            'próxima execução. Se continuar assim amanhã, avise quem cuida '
            'do app.',
      );
    }

    if (!carimbo.ok) {
      return ItemDeSaude(
        titulo: titulo,
        estado: EstadoDeSaude.ruim,
        detalhe: carimbo.detalhe.isEmpty
            ? 'A última execução falhou.'
            : 'A última execução falhou: ${carimbo.detalhe}',
        oQueFazer: oQueFazerQuandoVelho,
      );
    }

    final idade = agora.difference(carimbo.em);
    final quando = quandoFoi(carimbo.em, agora);
    if (idade >= prazoRuim) {
      return ItemDeSaude(
        titulo: titulo,
        estado: EstadoDeSaude.ruim,
        detalhe: 'Não roda desde $quando.',
        oQueFazer: oQueFazerQuandoVelho,
      );
    }
    if (idade >= prazoDeAlerta) {
      return ItemDeSaude(
        titulo: titulo,
        estado: EstadoDeSaude.alerta,
        detalhe: 'Última vez: $quando. Já passou da hora de hoje.',
        oQueFazer: 'Espere algumas horas. Se não rodar hoje, avise quem cuida '
            'do app.',
      );
    }
    return ItemDeSaude(
      titulo: titulo,
      estado: EstadoDeSaude.ok,
      detalhe: 'Rodou $quando.',
    );
  }

  /// "hoje às 17h37", "ontem às 17h37", "há 3 dias, em 16/11 às 17h37".
  ///
  /// Data crua ("2026-11-16T17:37") não é informação para quem só sabe usar
  /// WhatsApp: ela exige que a pessoa faça a conta de quantos dias são. A
  /// frase faz a conta por ela.
  static String quandoFoi(DateTime em, DateTime agora) {
    final hora = '${em.hour}h${em.minute.toString().padLeft(2, '0')}';
    final dias = _diasEntre(em, agora);
    if (dias == 0) return 'hoje às $hora';
    if (dias == 1) return 'ontem às $hora';
    final dia = em.day.toString().padLeft(2, '0');
    final mes = em.month.toString().padLeft(2, '0');
    return 'há $dias dias, em $dia/$mes às $hora';
  }

  /// Dias de CALENDÁRIO entre as duas datas.
  ///
  /// Não é `difference(...).inDays`: 23h de ontem para 1h de hoje dá zero em
  /// horas e um dia no calendário, e quem lê "ontem" quer dizer o dia de
  /// ontem, não 24 horas atrás.
  static int _diasEntre(DateTime a, DateTime b) {
    final dia1 = DateTime(a.year, a.month, a.day);
    final dia2 = DateTime(b.year, b.month, b.day);
    return dia2.difference(dia1).inDays;
  }
}
