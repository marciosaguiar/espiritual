import 'dart:async';

import '../../core/platform/rede.dart';
import '../../core/utils/crypto_utils.dart';
import '../../core/utils/fila_de_envio.dart';
import '../../core/utils/fusao_de_edicao.dart';
import '../models/arrangement_model.dart';
import '../models/aviso_de_sincronia.dart';
import 'app_firebase.dart';
import 'avisos_de_sincronia.dart';
import 'avisos_service.dart';
import 'firestore_service.dart';

/// A fila de envio do app, com o que cada tipo de ação faz ao chegar a hora.
///
/// Quem usa são os providers: eles põem o item na fila e mostram o resultado
/// (ou o "pendente"). Quem decide o que é "tentar depois" e o que é "o banco
/// recusou de vez" é `FirestoreService.ehTransitorio`.
class FilaService {
  FilaService._();

  static final FilaDeEnvio fila = FilaDeEnvio(
    // Sem Firebase pronto não há como enviar: o item espera, e `iniciar` o
    // acorda quando o banco ligar.
    estaOnline: () => Rede.online && AppFirebase.ligado,
    aoAvisar: (avisos) => AvisosDeSincronia.instancia.adicionar(avisos),
    executores: {
      TipoDeAcao.presenca: _enviarPresenca,
      TipoDeAcao.musica: _enviarMusica,
      TipoDeAcao.arranjo: _enviarArranjo,
    },
  );

  static bool _iniciada = false;
  static StreamSubscription<bool>? _assinatura;
  static Timer? _relogio;

  static Future<void>? _carregando;

  /// Lê do aparelho o que ficou pendente e os recados guardados. NÃO precisa
  /// do Firebase: é o que deixa a primeira tela já mostrar a presença
  /// "pendente" de uma confirmação feita sem sinal, antes de o banco ligar.
  static Future<void> carregar() => _carregando ??= Future.wait(
      [fila.carregar(), AvisosDeSincronia.instancia.carregar()]).then((_) {});

  /// Começa a enviar o que está pendente e fica de olho na internet.
  /// Chamar quando o Firebase estiver pronto (o envio precisa dele).
  static Future<void> iniciar() async {
    if (_iniciada) return;
    _iniciada = true;
    await carregar();
    _assinatura = Rede.mudancas.listen((online) {
      if (online) fila.acordar();
    });
    // De tempos em tempos tenta o que está esperando, respeitando a espera
    // de cada item. Cobre o sinal que volta sem o navegador avisar.
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) {
      if (fila.pendentes > 0) fila.processar();
    });
    if (fila.pendentes > 0) unawaited(fila.acordar());
  }

  /// A pessoa saiu (ou perdeu o acesso): o que ela deixou na fila e os
  /// recados dela vão embora com a sessão.
  static Future<void> descartarTudo() async {
    await fila.limpar();
    await AvisosDeSincronia.instancia.limpar();
  }

  static void parar() {
    _assinatura?.cancel();
    _relogio?.cancel();
    _iniciada = false;
  }

  /// A pessoa está esperando a resposta na tela? Então o erro aparece na
  /// hora, e um aviso guardado seria repetir a notícia.
  static bool _alguemEsperando(ItemDaFila item) =>
      item.tentativas == 0 &&
      DateTime.now().difference(item.criadoEm) < const Duration(seconds: 12);

  static Future<ResultadoDoEnvio> _enviarPresenca(ItemDaFila item) async {
    final culto = item.dados['culto'] as String;
    final userId = item.dados['userId'] as String;
    final confirmado = item.dados['confirmado'] as bool;
    final r = await FirestoreService.confirmPresence(culto, userId, confirmado);
    if (r.success) {
      // Avisa os líderes DEPOIS de gravar, como sempre: quem desmarca tira um
      // instrumento do domingo. (Se a confirmação só chegou depois de 2 min,
      // o servidor dos avisos recusa — é a trava dele, e está certa.)
      AvisosService.avisarConfirmacao(culto);
      return const ResultadoDoEnvio.enviado();
    }
    if (!r.definitivo) return ResultadoDoEnvio.depois(r.error);

    final rotulo = (item.dados['rotulo'] as String?) ?? 'o culto';
    return ResultadoDoEnvio.descartado(
      r.error ?? 'Não foi possível confirmar.',
      avisos: _alguemEsperando(item)
          ? const []
          : [
              AvisoDeSincronia(
                id: CryptoUtils.generateId(),
                tipo: TipoDeRecado.acaoNaoEnviada,
                criadoEm: DateTime.now(),
                titulo: confirmado
                    ? 'Sua confirmação não foi enviada'
                    : 'Seu cancelamento de presença não foi enviado',
                texto: '$rotulo: ${r.error}',
                alvo: culto,
              ),
            ],
    );
  }

  static Future<ResultadoDoEnvio> _enviarMusica(ItemDaFila item) async {
    final songId = item.dados['songId'] as String;
    final r = await FirestoreService.editarCamposDaMusica(songId, item.campos);
    return _resultadoDaEdicao(item, r, alvo: 'musica');
  }

  static Future<ResultadoDoEnvio> _enviarArranjo(ItemDaFila item) async {
    final songId = item.dados['songId'] as String;
    final arranjoId = item.dados['arranjoId'] as String;
    // Guardado como JSON (hora em texto); o banco quer a hora de verdade.
    final criar = item.dados['criar'] == null
        ? null
        : ArrangementModel.fromJson(
                Map<String, dynamic>.from(item.dados['criar'] as Map))
            .toFirestore();
    final r = await FirestoreService.editarCamposDoArranjo(
        songId, arranjoId, item.campos,
        criar: criar);
    return _resultadoDaEdicao(item, r, alvo: 'arranjo:$arranjoId');
  }

  static ResultadoDoEnvio _resultadoDaEdicao(
    ItemDaFila item,
    ResultadoDaEdicao r, {
    required String alvo,
  }) {
    final rotulo = (item.dados['rotulo'] as String?) ?? 'a música';
    final songId = item.dados['songId'] as String;

    if (!r.ok) {
      if (!r.definitivo) return ResultadoDoEnvio.depois(r.erro);
      return ResultadoDoEnvio.descartado(
        r.erro ?? 'Não foi possível salvar.',
        avisos: _alguemEsperando(item)
            ? const []
            : [
                AvisoDeSincronia(
                  id: CryptoUtils.generateId(),
                  tipo: TipoDeRecado.acaoNaoEnviada,
                  criadoEm: DateTime.now(),
                  titulo: 'Sua alteração em "$rotulo" não foi salva',
                  texto: r.erro ?? '',
                  songId: songId,
                ),
              ],
      );
    }
    if (r.perdas.isEmpty) return const ResultadoDoEnvio.enviado();

    // Parte (ou tudo) da edição perdeu para quem chegou antes: avisa, com o
    // que ficou e o que era da pessoa.
    final linhas = r.perdas
        .map((p) =>
            '${rotuloDoCampo(p.campo)}: você pôs "${resumoDoValor(p.minha)}", '
            'mas outra pessoa já tinha mudado para "${resumoDoValor(p.atual)}". '
            'Ficou "${resumoDoValor(p.atual)}".')
        .join('\n');
    final parcial = r.aplicados.isNotEmpty;
    return ResultadoDoEnvio.enviado(avisos: [
      AvisoDeSincronia(
        id: CryptoUtils.generateId(),
        tipo: TipoDeRecado.edicaoPerdida,
        criadoEm: DateTime.now(),
        titulo: parcial
            ? 'Parte da sua alteração em "$rotulo" não foi aplicada'
            : 'Sua alteração em "$rotulo" não foi aplicada',
        texto: linhas,
        songId: songId,
        alvo: alvo,
        perdas: r.perdas,
      ),
    ]);
  }

  /// "Aplicar a minha mesmo assim": põe de novo na fila só os campos que
  /// perderam, agora contra o valor que ficou no banco.
  static Future<void> reaplicar(AvisoDeSincronia aviso) async {
    if (!aviso.podeReaplicar) return;
    final campos = {
      for (final p in aviso.perdas)
        p.campo: CampoEditado(base: p.atual, novo: p.minha),
    };
    final alvo = aviso.alvo ?? 'musica';
    final ehArranjo = alvo.startsWith('arranjo:');
    final item = ItemDaFila.edicao(
      id: CryptoUtils.generateId(),
      tipo: ehArranjo ? TipoDeAcao.arranjo : TipoDeAcao.musica,
      songId: aviso.songId!,
      campos: campos,
      agora: DateTime.now(),
      extra: {
        if (ehArranjo) 'arranjoId': alvo.substring('arranjo:'.length),
        'rotulo': aviso.titulo,
      },
    );
    await AvisosDeSincronia.instancia.remover(aviso.id);
    await fila.enfileirar(item, espera: const Duration(seconds: 2));
  }
}
