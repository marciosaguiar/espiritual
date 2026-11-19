import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/message_model.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/user_model.dart';
import 'package:levitasync/presentation/widgets/home/pendencias.dart';

/// As pendências do Início.
///
/// O Início responde UMA pergunta — "o que eu preciso fazer agora?" — e cada
/// cartão só existe quando há mesmo algo a fazer. Cartão que aparece com
/// nada pendente ensina a passar o olho por cima de todos os outros,
/// inclusive dos que importam. Então o que estes testes guardam é
/// principalmente o que NÃO deve aparecer.

final AGORA = DateTime(2026, 11, 19, 10, 0);
const EU = 'eu';
const OUTRO = 'outro';

MessageModel msg(String de, DateTime quando, {String texto = 'oi'}) =>
    MessageModel(
      id: '$de-${quando.millisecondsSinceEpoch}',
      userId: de,
      userName: de,
      text: texto,
      timestamp: quando,
    );

ScaleModel culto(DateTime quando,
        {List<ScaleLevita> levitas = const [], bool cancelado = false}) =>
    ScaleModel(
      id: ScaleModel.idPara(quando),
      date: quando,
      createdAt: DateTime(2026),
      levitas: levitas,
      canceled: cancelado,
    );

UserModel pessoa(String id, UserRole papel, {bool robo = false}) => UserModel(
      id: id,
      name: id,
      email: '$id@levitas.app',
      role: papel,
      instruments: const [UserInstrument.vocalist],
      createdAt: DateTime(2026),
      bot: robo,
    );

void main() {
  group('mensagens não lidas', () {
    test('conta só as de outra pessoa, depois da última visita', () {
      final mensagens = [
        msg(OUTRO, AGORA.subtract(const Duration(hours: 3))),
        msg(EU, AGORA.subtract(const Duration(hours: 1))),
        msg(OUTRO, AGORA.subtract(const Duration(minutes: 30))),
        msg(OUTRO, AGORA.subtract(const Duration(minutes: 10))),
      ];
      final visto = AGORA.subtract(const Duration(hours: 2));
      expect(naoLidas(mensagens, EU, visto), 2);
    });

    test('mensagem minha NUNCA conta', () {
      // Ninguém tem mensagem não lida de si mesmo, e contá-la faria o aviso
      // aparecer logo depois de a pessoa mandar algo.
      final mensagens = [msg(EU, AGORA)];
      expect(naoLidas(mensagens, EU, AGORA.subtract(const Duration(days: 1))),
          0);
    });

    test('nunca abriu o chat neste aparelho: ZERO, não "tudo"', () {
      // Estrear o app com "47 mensagens novas" não é notícia, é parede.
      final mensagens = List.generate(
          47, (i) => msg(OUTRO, AGORA.subtract(Duration(minutes: i))));
      expect(naoLidas(mensagens, EU, null), 0);
    });

    test('chat em dia não acende nada', () {
      final mensagens = [msg(OUTRO, AGORA.subtract(const Duration(hours: 5)))];
      expect(naoLidas(mensagens, EU, AGORA.subtract(const Duration(hours: 1))),
          0);
    });

    test('conversa vazia não acende nada', () {
      expect(naoLidas(const [], EU, AGORA), 0);
    });
  });

  group('culto sem escala', () {
    test('acha os futuros vazios, do mais próximo para o mais longe', () {
      final cultos = [
        culto(AGORA.add(const Duration(days: 7))),
        culto(AGORA.add(const Duration(days: 2))),
      ];
      final r = cultosSemEscala(cultos, AGORA);
      expect(r.length, 2);
      expect(r.first.date.day, AGORA.add(const Duration(days: 2)).day);
    });

    test('culto que JÁ TEM gente escalada não é pendência', () {
      final cultos = [
        culto(AGORA.add(const Duration(days: 2)), levitas: [
          ScaleLevita(userId: EU, userName: '', instrument: 'bass'),
        ]),
      ];
      expect(cultosSemEscala(cultos, AGORA), isEmpty);
    });

    test('culto CANCELADO não é pendência', () {
      // Ninguém precisa escalar quem não vai tocar.
      final cultos = [
        culto(AGORA.add(const Duration(days: 2)), cancelado: true),
      ];
      expect(cultosSemEscala(cultos, AGORA), isEmpty);
    });

    test('culto que JÁ PASSOU não é pendência', () {
      // Cobrar escala de um culto de ontem é pedir o impossível, e é o tipo
      // de aviso que nunca sai da tela.
      final cultos = [culto(AGORA.subtract(const Duration(days: 2)))];
      expect(cultosSemEscala(cultos, AGORA), isEmpty);
    });
  });

  group('pedidos de entrada', () {
    test('conta quem está esperando', () {
      final pessoas = [
        pessoa('a', UserRole.pendente),
        pessoa('b', UserRole.levita),
        pessoa('c', UserRole.pendente),
        pessoa('d', UserRole.admin),
      ];
      expect(quantosPendentes(pessoas), 2);
    });

    test('robô pendente NÃO conta', () {
      // O robô se cadastra pelo app e fica pendente até ser aprovado. Contá-lo
      // mandaria o líder a Membros procurar uma pessoa que não existe.
      final pessoas = [pessoa('robo', UserRole.pendente, robo: true)];
      expect(quantosPendentes(pessoas), 0);
    });

    test('removido não é pendente', () {
      final pessoas = [pessoa('x', UserRole.removido)];
      expect(quantosPendentes(pessoas), 0);
    });

    test('ministério sem ninguém esperando não acende nada', () {
      expect(quantosPendentes(const []), 0);
    });
  });
}
