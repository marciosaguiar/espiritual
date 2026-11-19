import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/avisos_config.dart';
import '../../core/platform/avisos.dart';
import '../models/saude_model.dart';

/// Lê a saúde do sistema: o Worker e os carimbos das rotinas.
///
/// Duas fontes, de propósito. O Worker responde pelo que é dele (segredos,
/// cadastro do robô) e isso não custa nada — Cloudflare, sem login, com
/// resposta guardada 5 minutos do lado dele. Os carimbos dizem quando cada
/// rotina rodou pela última vez, e isso o Worker não tem como saber: quem
/// roda as rotinas é o GitHub.
class SaudeService {
  SaudeService._();

  /// Os nomes dos documentos em `saude`. Lista fechada, igual à da regra.
  static const List<String> rotinas = ['cultos', 'vespera', 'faxina'];

  /// Pergunta ao Worker como ele está.
  ///
  /// Devolve nulo quando NÃO DEU para perguntar — e quem chama trata isso
  /// como "não sei", nunca como "está quebrado". Celular sem internet não é
  /// sistema com defeito.
  static Future<SaudeDoWorker?> doWorker() async {
    if (!AvisosConfig.configurado) return null;
    try {
      final r = await buscarJson('${AvisosConfig.worker}/saude');
      if (r.status != 200) return null;
      final d = jsonDecode(r.corpo);
      if (d is! Map) return null;
      return SaudeDoWorker.fromJson(Map<String, dynamic>.from(d));
    } catch (_) {
      // Leitura com valor padrão seguro: sem resposta, a tela diz que não
      // conseguiu falar com ele.
      return null;
    }
  }

  /// Os carimbos de "rodou às tantas", um por rotina.
  ///
  /// São três leituras, uma vez por abertura e só para o líder. Com o cache
  /// persistente ligado, a maioria delas nem vai ao servidor.
  static Future<Map<String, CarimboDeSaude>> carimbos() async {
    final saida = <String, CarimboDeSaude>{};
    try {
      final col = await FirebaseFirestore.instance.collection('saude').get();
      for (final doc in col.docs) {
        final d = doc.data();
        final em = (d['em'] as Timestamp?)?.toDate();
        if (em == null) continue;
        saida[doc.id] = CarimboDeSaude(
          em: em,
          // Campo ausente conta como SUCESSO, porque é o que um carimbo
          // antigo significa: ele só era escrito quando a rotina terminava
          // bem. Tratar a falta como falha pintaria de vermelho um sistema
          // saudável no dia da atualização.
          ok: d['ok'] as bool? ?? true,
          detalhe: d['detalhe'] as String? ?? '',
        );
      }
    } catch (_) {
      // Sem os carimbos, as linhas das rotinas aparecem como "não sei".
    }
    return saida;
  }
}
