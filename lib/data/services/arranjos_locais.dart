import 'dart:convert';

import '../../core/platform/armazem.dart';
import '../models/arrangement_model.dart';

/// As cifras (arranjos) que este aparelho já tem, no armazém local.
///
/// A cifra mora no arranjo, uma subcoleção da música, e só era lida quando
/// alguém abria a música. Guardar uma cópia aqui faz a música abrir COM A
/// CIFRA na hora, sem internet e sem esperar o Firebase ligar.
///
/// Só entra o que o servidor confirmou. Alteração que ainda espera a internet
/// fica por cima, na tela (`SongsProvider.arranjoComPendencias`), e nunca
/// aqui: guardar o que pode ser recusado faria a cifra errada voltar na
/// próxima abertura.
class ArranjosLocais {
  const ArranjosLocais._();

  static const String _prefixo = 'arr:';
  static String _chave(String songId) => '$_prefixo$songId';

  /// A cifra guardada, ou nulo (não há, ou a música não tem cifra).
  static Future<ArrangementModel?> ler(String songId) async =>
      (await lerComIdade(songId))?.arranjo;

  /// A cifra guardada e de QUANDO ela é — o servidor confirmou nesse instante.
  /// Nulo quando não há resposta guardada. `arranjo` nulo com resposta
  /// guardada quer dizer "o servidor disse que esta música não tem cifra".
  static Future<({ArrangementModel? arranjo, DateTime em})?> lerComIdade(
      String songId) async {
    try {
      final texto = await Armazem.ler(_chave(songId));
      if (texto == null) return null;
      final j = jsonDecode(texto);
      if (j is! Map) return null; // formato de antes desta versão: ignora
      final em = DateTime.tryParse('${j['em']}');
      if (em == null) return null;
      final a = j['a'];
      return (
        arranjo: a is Map
            ? ArrangementModel.fromJson(Map<String, dynamic>.from(a))
            : null,
        em: em,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardar(ArrangementModel a, {DateTime? agora}) async {
    try {
      await Armazem.gravar(
          _chave(a.songId),
          jsonEncode({
            'em': (agora ?? DateTime.now()).toUtc().toIso8601String(),
            'a': a.toJson(),
          }));
    } catch (_) {}
  }

  /// A música não tem cifra (o servidor disse): guarda isso também, para a
  /// preparação não perguntar de novo a cada dia por uma música sem cifra.
  static Future<void> guardarAusencia(String songId, {DateTime? agora}) async {
    try {
      await Armazem.gravar(
          _chave(songId),
          jsonEncode({
            'em': (agora ?? DateTime.now()).toUtc().toIso8601String(),
            'a': null,
          }));
    } catch (_) {}
  }

  /// Já se sabe a resposta para esta música (tem cifra guardada, ou foi
  /// confirmado que não tem)?
  static Future<bool> jaSabe(String songId) async =>
      (await lerComIdade(songId)) != null;

  /// Até quando uma resposta guardada dispensa perguntar ao servidor de novo.
  ///
  /// Cada abertura de música custava UMA leitura do banco, mesmo com a cifra
  /// já na tela. Dentro deste prazo a cópia basta; depois dele, o servidor é
  /// consultado em segundo plano — então uma cifra corrigida por outro líder
  /// chega na abertura seguinte, e nunca fica velha de um dia para o outro.
  static const Duration validade = Duration(minutes: 15);

  static bool aindaVale(DateTime em, DateTime agora) =>
      agora.difference(em) < validade;

  static Future<int> quantas() async {
    try {
      var n = 0;
      for (final k in await Armazem.chaves(_prefixo)) {
        final t = await Armazem.ler(k);
        if (t == null) continue;
        final j = jsonDecode(t);
        if (j is Map && j['a'] is Map) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> esquecerTodas() async {
    for (final k in await Armazem.chaves(_prefixo)) {
      await Armazem.apagar(k);
    }
  }
}
