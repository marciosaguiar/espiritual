import 'package:cloud_firestore/cloud_firestore.dart';

import 'message_model.dart';
import 'user_model.dart';

/// Até quando uma pessoa já leu o chat.
///
/// UM documento por pessoa, não um carimbo por mensagem. Marcar cada mensagem
/// como lida por cada pessoa seria 15 escritas por mensagem num ministério de
/// 15 — a cota gratuita do Spark acabaria numa tarde de conversa. Com um
/// documento por pessoa, abrir o chat custa UMA escrita, e os dois tiques
/// saem de comparar horários.
class LeituraDoChat {
  final String userId;
  final String userName;
  final DateTime lidoAte;

  const LeituraDoChat({
    required this.userId,
    required this.userName,
    required this.lidoAte,
  });

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'userName': userName,
        // A hora é do SERVIDOR, e a regra exige. Com a hora do aparelho,
        // bastaria adiantar o relógio para ganhar dois tiques azuis em
        // mensagem que ninguém leu.
        'lidoAte': FieldValue.serverTimestamp(),
      };

  factory LeituraDoChat.fromFirestore(Map<String, dynamic> data) {
    return LeituraDoChat(
      userId: data['userId'] as String? ?? '',
      userName: data['userName'] as String? ?? '',
      // Sem o carimbo do servidor ainda, vale o começo dos tempos: é melhor
      // mostrar "ainda não viu" e corrigir num instante do que mostrar dois
      // tiques azuis para quem não viu nada.
      lidoAte: (data['lidoAte'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Quem viu uma mensagem minha, e quem ainda não.
///
/// Função pura, e é a que decide o segundo tique azul. `aprovados` já vem sem
/// os robôs e sem quem saiu do ministério — um robô na lista deixaria os dois
/// tiques azuis impossíveis para sempre, porque robô não abre o chat.
({List<LeituraDoChat> viram, List<String> naoViram}) quemViu({
  required MessageModel mensagem,
  required List<LeituraDoChat> leituras,
  required List<UserModel> aprovados,
}) {
  final porId = {for (final l in leituras) l.userId: l};
  final viram = <LeituraDoChat>[];
  final naoViram = <String>[];

  for (final pessoa in aprovados) {
    // O autor não se conta: ele obviamente viu o que escreveu, e aparecer na
    // lista "visto por" junto dos outros confunde.
    if (pessoa.id == mensagem.userId) continue;
    if (pessoa.bot) continue;

    final leitura = porId[pessoa.id];
    // `isBefore` nos dois lados: quem abriu o chat no mesmo instante da
    // mensagem conta como tendo visto.
    if (leitura != null && !leitura.lidoAte.isBefore(mensagem.timestamp)) {
      viram.add(LeituraDoChat(
        userId: pessoa.id,
        // O nome vem do cadastro, não do documento de leitura: quem mudou de
        // nome aparece com o atual.
        userName: pessoa.name,
        lidoAte: leitura.lidoAte,
      ));
    } else {
      naoViram.add(pessoa.name);
    }
  }
  return (viram: viram, naoViram: naoViram);
}

/// Todos os aprovados já viram? É o que acende os dois tiques azuis.
///
/// Ministério de uma pessoa só (ou mensagem num chat onde ninguém mais entrou
/// ainda) NÃO acende: não há ninguém para ver, e dois tiques azuis ali
/// significariam "todo mundo viu" quando não houve ninguém.
bool vistaPorTodos({
  required MessageModel mensagem,
  required List<LeituraDoChat> leituras,
  required List<UserModel> aprovados,
}) {
  final r = quemViu(
      mensagem: mensagem, leituras: leituras, aprovados: aprovados);
  if (r.viram.isEmpty && r.naoViram.isEmpty) return false;
  return r.naoViram.isEmpty;
}
