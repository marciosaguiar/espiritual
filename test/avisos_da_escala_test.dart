import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/services/avisos_service.dart';

/// Os avisos que não são do chat: "você foi escalado" e o lembrete da
/// véspera.
///
/// As duas contas que podem errar em silêncio: quem recebe o aviso de
/// escalado (avisar quem já estava escalado ensina a pessoa a ignorar as
/// próximas), e quais tipos de aviso estão ligados num aparelho.
void main() {
  ScaleLevita levita(String id, {bool confirmado = false}) => ScaleLevita(
        userId: id,
        userName: id,
        instrument: 'vocalist',
        confirmed: confirmado,
      );

  group('quem entrou na escala', () {
    test('só quem não estava antes', () {
      final novos = quemEntrouNaEscala(
        [levita('ana'), levita('joao')],
        [levita('ana'), levita('joao'), levita('pedro')],
      );
      expect(novos, ['pedro']);
    });

    test('ninguém novo: lista vazia, e nenhum aviso sai', () {
      expect(
          quemEntrouNaEscala(
              [levita('ana')], [levita('ana')]),
          isEmpty);
    });

    test('quem SAIU não conta', () {
      // Tirar alguém da escala não é motivo de aviso de escalado.
      expect(
          quemEntrouNaEscala(
              [levita('ana'), levita('joao')], [levita('ana')]),
          isEmpty);
    });

    test('trocar a função de quem já estava NÃO avisa de novo', () {
      // Era o caso mais provável de aviso repetido: o líder abre o diálogo,
      // muda o instrumento de alguém e salva.
      final antes = [levita('ana')];
      final depois = [
        ScaleLevita(
            userId: 'ana',
            userName: 'Ana',
            instrument: 'keyboard',
            confirmed: true),
      ];
      expect(quemEntrouNaEscala(antes, depois), isEmpty);
    });

    test('escala que estava vazia avisa todo mundo', () {
      expect(
          quemEntrouNaEscala(
              const [], [levita('ana'), levita('joao')]),
          ['ana', 'joao']);
    });

    test('a mesma pessoa duas vezes na lista nova vira UM aviso', () {
      expect(
          quemEntrouNaEscala(const [], [levita('ana'), levita('ana')]),
          ['ana']);
    });

    test('id vazio é ignorado', () {
      // Documento torto não pode virar uma chamada ao servidor com id vazio.
      expect(quemEntrouNaEscala(const [], [levita('')]), isEmpty);
    });
  });

  group('quais tipos de aviso estão ligados', () {
    test('mapa vazio ou ausente: TODOS ligados', () {
      // Isto importa de verdade: todo aparelho inscrito antes desta mudança
      // não tem o campo, e se a falta valesse como "desligado" o ministério
      // pararia de receber aviso de uma hora para outra, sem ninguém ter
      // mexido em nada.
      expect(AvisosService.tiposLigados(null), TipoDeAviso.values.toSet());
      expect(AvisosService.tiposLigados(<String, Object?>{}),
          TipoDeAviso.values.toSet());
    });

    test('só o que está explicitamente falso fica desligado', () {
      final ligados = AvisosService.tiposLigados({'chat': false});
      expect(ligados.contains(TipoDeAviso.chat), isFalse);
      expect(ligados.contains(TipoDeAviso.escalado), isTrue);
      expect(ligados.contains(TipoDeAviso.vespera), isTrue);
    });

    test('todos desligados', () {
      // O mapa sai de `TipoDeAviso.values`, não escrito à mão: este teste
      // quebrou quando entrou o quarto tipo ("novo pedido de entrada"),
      // dizendo que havia defeito onde havia só um tipo novo.
      final tudoDesligado = {
        for (final t in TipoDeAviso.values) t.chave: false,
      };
      expect(AvisosService.tiposLigados(tudoDesligado), isEmpty);
    });

    test('valor estranho conta como ligado, não como desligado', () {
      for (final lixo in ['false', 0, null, 'sim', <String>[]]) {
        final ligados = AvisosService.tiposLigados({'chat': lixo});
        expect(ligados.contains(TipoDeAviso.chat), isTrue, reason: '$lixo');
      }
    });

    test('mapa que não é mapa não derruba a tela', () {
      for (final lixo in ['chat', 42, <String>['chat']]) {
        expect(AvisosService.tiposLigados(lixo), TipoDeAviso.values.toSet(),
            reason: '$lixo');
      }
    });

    test('a chave gravada no banco não é o nome do enum por acidente', () {
      // O banco não pode quebrar porque alguém renomeou uma constante no
      // Dart: a chave é declarada à mão.
      expect(TipoDeAviso.chat.chave, 'chat');
      expect(TipoDeAviso.escalado.chave, 'escalado');
      expect(TipoDeAviso.vespera.chave, 'vespera');
    });

    test('cada tipo tem um rótulo em português para a tela', () {
      for (final t in TipoDeAviso.values) {
        expect(t.rotulo.trim(), isNotEmpty);
        expect(t.rotulo, isNot(equals(t.chave)));
      }
    });
  });
}
