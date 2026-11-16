import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/scale_model.dart';

/// "Levar para o culto": o recado do chat vira uma linha nas observações.
///
/// O combinado nascia no chat — "domingo entra sem bateria", "a Ana leva o
/// cabo" — e morria lá: em 30 dias a mensagem some, e quem abre o culto no
/// domingo não vê nada.
void main() {
  final quando = DateTime(2026, 11, 16, 20, 30);

  group('a linha que entra', () {
    test('assina com o nome e a data, no formato dd/MM', () {
      expect(
        ScaleModel.comObservacaoNova('', 'entra sem bateria',
            autor: 'Márcio', quando: quando),
        '— Márcio, 16/11: entra sem bateria',
      );
    });

    test('mês e dia de um dígito saem com zero à esquerda', () {
      expect(
        ScaleModel.comObservacaoNova('', 'teste',
            autor: 'Ana', quando: DateTime(2026, 2, 5)),
        '— Ana, 05/02: teste',
      );
    });

    test('a observação que já existia FICA, e a nova vai no fim', () {
      final novo = ScaleModel.comObservacaoNova(
        '— Ana, 10/11: a Ana leva o cabo',
        'entra sem bateria',
        autor: 'Márcio',
        quando: quando,
      );
      expect(novo, '— Ana, 10/11: a Ana leva o cabo\n'
          '— Márcio, 16/11: entra sem bateria');
    });

    test('quebra de linha do chat vira espaço', () {
      // Recado colado de outro lugar chegaria com buracos no meio da
      // observação, e uma linha por pedaço.
      expect(
        ScaleModel.comObservacaoNova('', 'primeira\n\nsegunda   terceira',
            autor: 'Ana', quando: quando),
        '— Ana, 16/11: primeira segunda terceira',
      );
    });

    test('sem nome, "Alguém" — nunca uma linha sem assinatura', () {
      expect(
        ScaleModel.comObservacaoNova('', 'teste', autor: '  ', quando: quando),
        '— Alguém, 16/11: teste',
      );
    });

    test('observação antiga sem quebra no fim não gruda na nova', () {
      final novo = ScaleModel.comObservacaoNova(
          'combinado antigo   \n\n', 'novo', autor: 'Ana', quando: quando);
      expect(novo, 'combinado antigo\n— Ana, 16/11: novo');
    });
  });

  group('o que NÃO entra', () {
    test('texto vazio ou só espaço devolve nulo', () {
      expect(
          ScaleModel.comObservacaoNova('', '   ',
              autor: 'Ana', quando: quando),
          isNull);
      expect(
          ScaleModel.comObservacaoNova('', '\n\n',
              autor: 'Ana', quando: quando),
          isNull);
    });

    test('o que estoura o teto devolve nulo, e a tela explica', () {
      // A regra do banco limita `observations` a 5000. Tentar gravar mais
      // voltaria um erro de permissão, que não explica nada a ninguém.
      final cheio = 'x' * (ScaleModel.limiteDasObservacoes - 10);
      expect(
        ScaleModel.comObservacaoNova(cheio, 'mais um recado',
            autor: 'Ana', quando: quando),
        isNull,
      );
    });

    test('o que cabe por pouco ENTRA', () {
      final quase = 'x' * 4900;
      final novo = ScaleModel.comObservacaoNova(quase, 'ok',
          autor: 'Ana', quando: quando);
      expect(novo, isNotNull);
      expect(novo!.length, lessThanOrEqualTo(ScaleModel.limiteDasObservacoes));
    });
  });
}
