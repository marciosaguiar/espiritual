import 'dart:convert';
import 'dart:typed_data';

import '../../core/platform/armazem.dart';
import '../../core/utils/plano_do_cache.dart';

/// Os áudios do chat que ESTE aparelho já ouviu, com limite de espaço.
///
/// Áudio só é baixado quando a pessoa toca no play (cada abertura do chat
/// baixando tudo seria meio mega por minuto de voz, no 4G de quem só queria ler
/// um recado). Ouvido uma vez, fica aqui: tocar de novo — ou tocar dentro da
/// igreja, sem sinal — é uma leitura de disco, sem cobrar nenhuma leitura do
/// banco.
///
/// O LIMITE é de [limiteDeBytes]: o iPhone apaga o que um site guardou quando
/// falta espaço, e um app que enche o aparelho pede para ser apagado inteiro.
/// Passando do limite, sai o que foi ouvido há mais tempo (`planejarDespejo`).
///
/// Nada aqui lança: guardar que falha é só ouvir pela rede da próxima vez.
class AudiosLocais {
  const AudiosLocais._();

  /// 12 MB de som. Uma mensagem típica (10 s) tem ~40 KB: cabem centenas. O
  /// teto de uma mensagem é 800 KiB, então até quinze mensagens de dois
  /// minutos cabem.
  static const int limiteDeBytes = 12 * 1024 * 1024;

  static const String _prefixo = 'audio:';
  static const String _chaveDoIndice = 'audio-indice';

  static String _chave(String id) => '$_prefixo$id';

  static Future<Map<String, Map<String, dynamic>>> _lerIndice() async {
    try {
      final t = await Armazem.ler(_chaveDoIndice);
      if (t == null) return {};
      final j = jsonDecode(t) as Map;
      return {
        for (final e in j.entries)
          '${e.key}': Map<String, dynamic>.from(e.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _gravarIndice(Map<String, Map<String, dynamic>> m) =>
      Armazem.gravar(_chaveDoIndice, jsonEncode(m));

  /// O áudio guardado, ou nulo. Ler conta como uso (sai por último).
  static Future<({Uint8List bytes, String tipo})?> ler(String id,
      {DateTime? agora}) async {
    try {
      final t = await Armazem.ler(_chave(id));
      if (t == null) return null;
      final j = jsonDecode(t) as Map;
      final bytes = base64Decode(j['b'] as String);
      final indice = await _lerIndice();
      if (indice.containsKey(id)) {
        indice[id]!['u'] = (agora ?? DateTime.now()).toUtc().toIso8601String();
        await _gravarIndice(indice);
      }
      return (bytes: bytes, tipo: j['t'] as String? ?? 'audio/mp4');
    } catch (_) {
      return null;
    }
  }

  /// Guarda o áudio, soltando os mais antigos se não couber. Devolve se
  /// guardou.
  static Future<bool> guardar(String id, Uint8List bytes, String tipo,
      {DateTime? agora, int limite = limiteDeBytes}) async {
    try {
      final quando = agora ?? DateTime.now();
      final indice = await _lerIndice();
      indice.remove(id); // regravar o mesmo não conta duas vezes
      final itens = [
        for (final e in indice.entries)
          ItemDoCache(
            e.key,
            (e.value['b'] as num?)?.toInt() ?? 0,
            DateTime.tryParse('${e.value['u']}') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
      ];
      final saem =
          planejarDespejo(itens: itens, novoTamanho: bytes.length, limite: limite);
      if (saem == null) return false;
      for (final s in saem) {
        await Armazem.apagar(_chave(s));
        indice.remove(s);
      }
      final ok = await Armazem.gravar(
          _chave(id), jsonEncode({'t': tipo, 'b': base64Encode(bytes)}));
      if (!ok) return false;
      indice[id] = {'b': bytes.length, 'u': quando.toUtc().toIso8601String()};
      await _gravarIndice(indice);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Quantos bytes de som estão guardados.
  static Future<int> bytesGuardados() async => (await _lerIndice())
      .values
      .fold<int>(0, (s, v) => s + ((v['b'] as num?)?.toInt() ?? 0));

  static Future<void> esquecerTodos() async {
    for (final k in await Armazem.chaves(_prefixo)) {
      await Armazem.apagar(k);
    }
    await Armazem.apagar(_chaveDoIndice);
  }
}
