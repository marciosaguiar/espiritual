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

  static Future<ArrangementModel?> ler(String songId) async {
    try {
      final texto = await Armazem.ler(_chave(songId));
      if (texto == null) return null;
      return ArrangementModel.fromJson(
          Map<String, dynamic>.from(jsonDecode(texto) as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardar(ArrangementModel a) async {
    try {
      await Armazem.gravar(_chave(a.songId), jsonEncode(a.toJson()));
    } catch (_) {}
  }

  /// A música não tem cifra (o servidor disse): guarda isso também, para a
  /// preparação não perguntar de novo a cada dia por uma música sem cifra.
  static Future<void> guardarAusencia(String songId) async {
    try {
      await Armazem.gravar(_chave(songId), 'sem');
    } catch (_) {}
  }

  /// Já se sabe a resposta para esta música (tem cifra guardada, ou foi
  /// confirmado que não tem)?
  static Future<bool> jaSabe(String songId) async {
    try {
      return await Armazem.ler(_chave(songId)) != null;
    } catch (_) {
      return false;
    }
  }

  static Future<int> quantas() async {
    try {
      var n = 0;
      for (final k in await Armazem.chaves(_prefixo)) {
        if (await Armazem.ler(k) != 'sem') n++;
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
