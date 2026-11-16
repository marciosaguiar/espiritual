import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/avisos_config.dart';
import '../../core/platform/avisos.dart';
import 'auth_service.dart';
import 'local_storage_service.dart';

/// Os tipos de aviso que o app manda.
///
/// Cada um se liga e desliga à parte, porque são incômodos diferentes:
/// mensagem de chat chega a toda hora, "você foi escalado" chega raro e
/// importa, e o lembrete da véspera chega uma vez e é o que faz a pessoa não
/// esquecer o culto. Quem desliga o chat raramente quer desligar os outros
/// dois.
enum TipoDeAviso {
  chat('chat', 'Mensagem nova no chat'),
  escalado('escalado', 'Quando eu for escalado'),
  vespera('vespera', 'Lembrete na véspera do culto'),

  /// Só o líder recebe — é ele que aprova. Aparece em Perfil só para ele,
  /// porque um liga-desliga de algo que nunca chega é só confusão.
  pedido('pedido', 'Novo pedido de entrada (líder)'),

  /// Também só o líder: é ele que remonta a escala quando alguém desmarca.
  confirmacao('confirmacao', 'Alguém confirma ou desmarca (líder)');

  const TipoDeAviso(this.chave, this.rotulo);

  /// Como é gravado no banco. Nome fixo, independente do nome do enum: o
  /// banco não pode quebrar porque alguém renomeou uma constante no Dart.
  final String chave;
  final String rotulo;
}

/// O estado dos avisos NESTE aparelho, como a tela precisa ver.
enum EstadoDosAvisos {
  /// O endereço do Worker e a chave ainda são os de exemplo.
  naoConfigurado,

  /// iPhone no Safari, sem o app na tela de início: o Push nem existe ali.
  precisaInstalar,

  /// Navegador velho, ou aparelho sem suporte nenhum.
  semSuporte,

  /// Nunca pediu: é o caso do botão "Ativar avisos".
  podeAtivar,

  /// A pessoa negou. Negado não se pergunta de novo — só nas configurações
  /// do navegador.
  negado,

  /// Inscrito e recebendo.
  ligado,

  /// Inscrito, mas a pessoa desligou os avisos no Perfil.
  desligado,
}

/// Avisos de mensagem nova: inscrever o aparelho e pedir o envio.
///
/// COMO O AVISO SAI
///
/// O app grava a mensagem no Firestore — isso é o que importa, e acontece
/// com as regras do banco valendo. Depois, e só depois, ele pede ao Worker
/// que avise os outros. Se o pedido falhar, a mensagem já está lá: o chat de
/// quem está com o app aberto recebe na hora, e quem está com o app fechado
/// perde só a notificação.
///
/// É por isso que `avisarDoChat` NÃO devolve erro para a tela: um balão
/// vermelho dizendo "não avisei" depois de a mensagem ter sido enviada com
/// sucesso assustaria sem nada a fazer a respeito. O caminho que mostra erro
/// é o botão "Testar aviso", no Perfil, que existe justamente para isso.
class AvisosService {
  AvisosService._();

  static const String _colecao = 'pushSubs';
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Quanto tempo o pedido ao Worker pode demorar.
  ///
  /// Curto de propósito: ninguém espera para ver a própria mensagem na tela.
  static const Duration _paciencia = Duration(seconds: 8);

  // ── O estado, para a tela ─────────────────────────────────────────────────

  /// Em que pé estão os avisos neste aparelho, e até quando está silenciado.
  ///
  /// `instalado` vem de `install.dart` e separa os dois casos do iPhone: sem
  /// o app na tela de início não há o que ativar, só o que instalar.
  static Future<
      ({
        EstadoDosAvisos estado,
        DateTime? silenciadoAte,
        Set<TipoDeAviso> ligados,
      })> situacao({
    required bool instalado,
  }) async {
    ({
      EstadoDosAvisos estado,
      DateTime? silenciadoAte,
      Set<TipoDeAviso> ligados,
    }) so(EstadoDosAvisos e) => (
          estado: e,
          silenciadoAte: null,
          // Sem registro, todos ligados: é o padrão de quem acabou de
          // ativar, e é o que o Worker assume na falta do campo.
          ligados: TipoDeAviso.values.toSet(),
        );

    if (!AvisosConfig.configurado) return so(EstadoDosAvisos.naoConfigurado);
    if (!avisosSuportados) {
      return so(instalado
          ? EstadoDosAvisos.semSuporte
          : EstadoDosAvisos.precisaInstalar);
    }

    final permissao = permissaoDeAvisos();
    if (permissao == 'denied') return so(EstadoDosAvisos.negado);
    if (permissao != 'granted') return so(EstadoDosAvisos.podeAtivar);

    final inscricao = await inscricaoAtual();
    if (inscricao == null) return so(EstadoDosAvisos.podeAtivar);

    final registro = await _meuRegistro();
    if (registro == null) return so(EstadoDosAvisos.podeAtivar);

    final ate = (registro['silenciarAte'] as Timestamp?)?.toDate();
    return (
      estado: (registro['avisosLigados'] == false)
          ? EstadoDosAvisos.desligado
          : EstadoDosAvisos.ligado,
      // Silêncio que já passou não é silêncio: mostrar "até ontem" faria a
      // pessoa achar que o botão travou.
      silenciadoAte:
          (ate != null && ate.isAfter(DateTime.now())) ? ate : null,
      ligados: tiposLigados(registro['tipos']),
    );
  }

  static Future<Map<String, dynamic>?> _meuRegistro() async {
    try {
      final doc = await _db
          .collection(_colecao)
          .doc(LocalStorageService.idDoAparelho)
          .get();
      return doc.exists ? doc.data() : null;
    } catch (_) {
      // Sem rede, ou a regra recusou: a tela trata como "pode ativar", que
      // é o pior caso seguro — oferecer de novo não estraga nada.
      return null;
    }
  }

  /// Até quando "silenciar até amanhã" silencia.
  ///
  /// Não é meia-noite: às 23h50 isso silenciaria por dez minutos e a pessoa
  /// acharia que o botão não funciona. É o próximo 7h da manhã que esteja a
  /// mais de uma hora de distância — de madrugada, vale o 7h de hoje.
  ///
  /// Recebe `agora` como parâmetro para o teste poder ficar na virada do dia
  /// e na virada do mês, que é onde este tipo de conta quebra.
  static DateTime silenciarAte(DateTime agora) {
    var alvo = DateTime(agora.year, agora.month, agora.day, 7);
    while (alvo.difference(agora) < const Duration(hours: 1)) {
      alvo = DateTime(alvo.year, alvo.month, alvo.day + 1, 7);
    }
    return alvo;
  }

  // ── Ativar e desativar ────────────────────────────────────────────────────

  /// Pede a permissão, inscreve e grava. Devolve null se deu, ou o motivo.
  ///
  /// Tem de ser chamado de dentro de um toque: o iPhone não abre a caixa de
  /// permissão fora de um gesto da pessoa.
  static Future<String?> ativar({
    required String userId,
    required String userName,
  }) async {
    if (!AvisosConfig.configurado) {
      return 'Os avisos ainda não foram configurados neste app.';
    }
    if (!avisosSuportados) {
      return 'Este aparelho não recebe avisos. No iPhone, instale o app na '
          'tela de início primeiro.';
    }

    final r = await inscrever(AvisosConfig.chavePublica);
    if (r.inscricao == null) {
      switch (r.falha) {
        case 'negado':
          return 'Você recusou os avisos. Para liberar, vá nos ajustes do '
              'navegador, em Notificações.';
        case 'sem-suporte':
          return 'Este aparelho não recebe avisos.';
        default:
          return 'Não consegui ativar os avisos. Tente de novo.';
      }
    }

    return _gravar(
      userId: userId,
      userName: userName,
      inscricao: r.inscricao!,
      ligados: true,
    );
  }

  /// Quais tipos estão ligados, a partir do mapa gravado.
  ///
  /// CHAVE AUSENTE É LIGADA. Isto importa de verdade: todo aparelho inscrito
  /// antes desta mudança não tem o campo, e se a falta significasse
  /// "desligado" o ministério inteiro pararia de receber aviso de uma hora
  /// para outra, sem ninguém ter mexido em nada.
  static Set<TipoDeAviso> tiposLigados(Object? bruto) {
    final mapa = bruto is Map ? bruto : const {};
    return TipoDeAviso.values
        .where((t) => mapa[t.chave] != false)
        .toSet();
  }

  /// Liga ou desliga UM tipo de aviso neste aparelho.
  static Future<String?> ligarTipo(TipoDeAviso tipo, bool ligado) async {
    try {
      await _db.collection(_colecao).doc(LocalStorageService.idDoAparelho)
          .update({
        // Caminho de ponto: grava só a própria chave, e não o mapa inteiro —
        // senão um aparelho antigo, sem o campo, apagaria o que outro
        // aparelho da mesma pessoa tivesse configurado.
        'tipos.${tipo.chave}': ligado,
        'atualizadoEm': Timestamp.now(),
      });
      return null;
    } on FirebaseException catch (e) {
      return 'Não consegui salvar: ${e.message ?? e.code}';
    }
  }

  /// Liga ou desliga sem desinscrever.
  ///
  /// Desligar mantém a inscrição e marca o registro: religar depois é um
  /// toque, sem pedir permissão de novo — e pedir de novo é o que a pessoa
  /// não pode fazer se um dia negar.
  static Future<String?> ligar(bool ligados) async {
    try {
      await _db.collection(_colecao).doc(LocalStorageService.idDoAparelho)
          .update({
        'avisosLigados': ligados,
        // Religar limpa o silêncio: foi um toque dizendo "quero receber".
        if (ligados) 'silenciarAte': null,
        'atualizadoEm': Timestamp.now(),
      });
      return null;
    } on FirebaseException catch (e) {
      return 'Não consegui salvar: ${e.message ?? e.code}';
    }
  }

  /// Silencia até amanhã de manhã.
  static Future<String?> silenciar(DateTime agora) async {
    try {
      await _db.collection(_colecao).doc(LocalStorageService.idDoAparelho)
          .update({
        'silenciarAte': Timestamp.fromDate(silenciarAte(agora)),
        'atualizadoEm': Timestamp.now(),
      });
      return null;
    } on FirebaseException catch (e) {
      return 'Não consegui salvar: ${e.message ?? e.code}';
    }
  }

  /// Confere e regrava a inscrição deste aparelho, se já houver uma.
  ///
  /// Roda na abertura do app. É o que conserta sozinho dois casos: o
  /// navegador trocou a inscrição (o service worker reinscreve, mas não tem
  /// login para gravar), e a pessoa mudou de nome no perfil.
  static Future<void> conferirNaAbertura({
    required String userId,
    required String userName,
  }) async {
    if (!AvisosConfig.configurado || !avisosSuportados) return;
    if (permissaoDeAvisos() != 'granted') return;
    final inscricao = await inscricaoAtual();
    if (inscricao == null) return;

    final registro = await _meuRegistro();
    final igual = registro != null &&
        registro['endpoint'] == inscricao.endpoint &&
        registro['p256dh'] == inscricao.p256dh &&
        registro['userId'] == userId &&
        registro['userName'] == userName;
    if (igual) return;

    await _gravar(
      userId: userId,
      userName: userName,
      inscricao: inscricao,
      // Não religa quem desligou: só atualiza o endereço.
      ligados: registro?['avisosLigados'] as bool? ?? true,
      silenciarAte: registro?['silenciarAte'] as Timestamp?,
    );
  }

  static Future<String?> _gravar({
    required String userId,
    required String userName,
    required InscricaoDeAviso inscricao,
    required bool ligados,
    Timestamp? silenciarAte,
  }) async {
    try {
      await _db.collection(_colecao).doc(LocalStorageService.idDoAparelho).set({
        'userId': userId,
        'userName': userName,
        'endpoint': inscricao.endpoint,
        'p256dh': inscricao.p256dh,
        'auth': inscricao.auth,
        'avisosLigados': ligados,
        'silenciarAte': silenciarAte,
        'atualizadoEm': Timestamp.now(),
      });
      return null;
    } on FirebaseException catch (e) {
      return 'Não consegui salvar a inscrição: ${e.message ?? e.code}';
    }
  }

  /// Apaga a inscrição deste aparelho. Usado ao sair ou ao perder o acesso.
  static Future<void> esquecerEsteAparelho() async {
    try {
      await desinscrever();
      await _db
          .collection(_colecao)
          .doc(LocalStorageService.idDoAparelho)
          .delete();
    } catch (_) {
      // Sair do app não pode falhar por causa disto. O Worker apaga a
      // inscrição sozinho na primeira vez que o serviço de push a recusar.
    }
  }

  // ── Pedir o envio ─────────────────────────────────────────────────────────

  /// Pede ao Worker que avise o ministério de uma mensagem já gravada.
  ///
  /// Não devolve erro: ver o comentário da classe. Falha vai para o console.
  static Future<void> avisarDoChat(String mensagemId) async {
    if (!AvisosConfig.configurado) return;
    try {
      final resposta = await _chamar('/avisar', {'mensagemId': mensagemId});
      if (resposta.status < 200 || resposta.status >= 300) {
        debugPrint('[avisos] worker respondeu ${resposta.status}: '
            '${resposta.corpo}');
      }
    } catch (e) {
      debugPrint('[avisos] não avisei: $e');
    }
  }

  /// Pede ao Worker que avise quem ACABOU de ser escalado num culto.
  ///
  /// Como o aviso do chat: não devolve erro. A escala já está salva, e um
  /// balão vermelho dizendo "não avisei" depois de o líder ter salvo com
  /// sucesso assustaria sem nada a fazer a respeito.
  ///
  /// Quem decide quem é "recém-escalado" é o APP, que sabe quem estava na
  /// lista antes; o Worker confere que esses ids estão de fato no culto e que
  /// a escalação mudou agora — então uma lista inventada não avisa ninguém
  /// que não foi escalado de verdade.
  static Future<void> avisarEscalados(
      String cultoId, List<String> novos) async {
    if (!AvisosConfig.configurado || novos.isEmpty) return;
    try {
      final r = await _chamar('/escalado', {
        'cultoId': cultoId,
        'novos': novos,
      });
      if (r.status < 200 || r.status >= 300) {
        debugPrint('[avisos] escalado: ${r.status} ${r.corpo}');
      }
    } catch (e) {
      debugPrint('[avisos] não avisei os escalados: $e');
    }
  }

  /// Avisa os líderes de que alguém confirmou ou desmarcou a presença.
  ///
  /// Chamada logo depois da confirmação, pela própria pessoa. Não devolve
  /// erro: a confirmação já está gravada e aparece na tela de todo mundo. Um
  /// balão vermelho dizendo "não avisei" assustaria quem acabou de confirmar,
  /// sem nada a fazer a respeito.
  ///
  /// Quem decide o texto é o Worker, lendo o estado DO DOCUMENTO — então o
  /// aviso nunca pode dizer o contrário do que está gravado.
  static Future<void> avisarConfirmacao(String cultoId) async {
    if (!AvisosConfig.configurado) return;
    try {
      final r = await _chamar('/confirmou', {'cultoId': cultoId});
      if (r.status < 200 || r.status >= 300) {
        debugPrint('[avisos] confirmação: ${r.status} ${r.corpo}');
      }
    } catch (e) {
      debugPrint('[avisos] não avisei da confirmação: $e');
    }
  }

  /// Avisa os líderes de que alguém acabou de pedir para entrar.
  ///
  /// Chamada logo depois do cadastro, por quem está `pendente` — é a única
  /// chamada ao Worker feita por quem ainda não foi aprovado, e por isso a
  /// rota dele tem conferência própria (o cadastro tem de existir e estar
  /// pendente, e cada cadastro avisa UMA vez na vida).
  ///
  /// Não devolve erro: a conta já foi criada e o pedido já aparece na tela
  /// Membros do líder. Um balão vermelho dizendo "não avisei" assustaria
  /// quem acabou de se cadastrar, sem nada a fazer a respeito.
  static Future<void> avisarPedidoDeEntrada() async {
    if (!AvisosConfig.configurado) return;
    try {
      final r = await _chamar('/pedido', const {});
      if (r.status < 200 || r.status >= 300) {
        debugPrint('[avisos] pedido de entrada: ${r.status} ${r.corpo}');
      }
    } catch (e) {
      debugPrint('[avisos] não avisei do pedido de entrada: $e');
    }
  }

  /// Manda um aviso de teste só para os aparelhos de quem pediu.
  ///
  /// Este caminho DEVOLVE o erro, porque é o único jeito de uma pessoa leiga
  /// descobrir que os avisos não estão funcionando.
  static Future<String?> testar() async {
    if (!AvisosConfig.configurado) {
      return 'Os avisos ainda não foram configurados neste app.';
    }
    try {
      final resposta = await _chamar('/testar', const {});
      if (resposta.status >= 200 && resposta.status < 300) {
        final enviados = _campo(resposta.corpo, 'enviados');
        if (enviados == '0' || enviados == null) {
          return 'O servidor aceitou, mas nenhum aparelho recebeu. Ative os '
              'avisos neste aparelho e tente de novo.';
        }
        return null;
      }
      final erro = _campo(resposta.corpo, 'erro');
      if (erro != null && erro.isNotEmpty) return erro;
      if (resposta.status == 0) {
        return 'Não consegui falar com o servidor dos avisos. Confira a '
            'internet e o endereço do Worker.';
      }
      return 'O servidor dos avisos respondeu ${resposta.status}.';
    } catch (e) {
      return 'Não consegui falar com o servidor dos avisos: $e';
    }
  }

  /// Um campo da resposta do Worker, ou null se não vier.
  static String? _campo(String corpo, String nome) {
    try {
      final m = jsonDecode(corpo) as Map<String, dynamic>;
      final v = m[nome];
      return v?.toString();
    } catch (_) {
      // O Worker responde JSON em tudo, mas um proxy no meio pode devolver
      // HTML. Melhor dizer o status que mostrar "FormatException" à pessoa.
      return null;
    }
  }

  static Future<({int status, String corpo})> _chamar(
      String caminho, Map<String, Object?> corpo) async {
    final conta = AuthService.currentAuthUser;
    if (conta == null) throw Exception('sem login');
    // O token é a única coisa que prova ao Worker quem está pedindo. Ele
    // vence em uma hora, então é pedido na hora de usar, nunca guardado.
    final token = await conta.getIdToken();
    if (token == null) throw Exception('sem token');
    return chamarWorker(
      '${AvisosConfig.worker}$caminho',
      token,
      jsonEncode(corpo),
    ).timeout(_paciencia);
  }
}
