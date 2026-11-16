import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/scale_model.dart';

/// "3 de 7 confirmaram", e quem falta.
///
/// A pergunta que o líder faz no sábado à noite é quantos já disseram que vêm
/// — e ele respondia isso abrindo o culto e contando os nomes verdes na mão.
ScaleLevita levita(String id, {String nome = '', bool ok = false}) =>
    ScaleLevita(
        userId: id, userName: nome, instrument: 'other', confirmed: ok);

ScaleModel culto(List<ScaleLevita> levitas) => ScaleModel(
      id: '2026-11-22_1900',
      date: DateTime(2026, 11, 22, 19),
      createdAt: DateTime(2026, 11, 16),
      levitas: levitas,
    );

void main() {
  group('a frase da contagem', () {
    test('o caso comum', () {
      final c = culto([
        levita('a', ok: true),
        levita('b', ok: true),
        levita('c', ok: true),
        levita('d'),
        levita('e'),
        levita('f'),
        levita('g'),
      ]);
      expect(c.textoDaConfirmacao, '3 de 7 confirmaram');
      expect(c.todosConfirmaram, isFalse);
    });

    test('ninguém ainda — e não "0 de 7"', () {
      // "0 de 7 confirmaram" é uma conta; "ninguém confirmou ainda" é uma
      // frase. Quem lê é voluntário leigo.
      expect(culto([levita('a'), levita('b')]).textoDaConfirmacao,
          'Ninguém confirmou ainda');
    });

    test('todos — a notícia que o líder quer ler de longe', () {
      final c = culto([levita('a', ok: true), levita('b', ok: true)]);
      expect(c.textoDaConfirmacao, 'Todos confirmaram');
      expect(c.todosConfirmaram, isTrue);
    });

    test('uma pessoa só não vira "1 de 1 confirmaram"', () {
      expect(culto([levita('a', ok: true)]).textoDaConfirmacao, 'Confirmado');
      expect(culto([levita('a')]).textoDaConfirmacao,
          'Ninguém confirmou ainda');
    });

    test('culto sem ninguém escalado não finge contagem', () {
      final c = culto([]);
      expect(c.textoDaConfirmacao, 'Ninguém escalado');
      // E NÃO "todos confirmaram": zero de zero não é escala pronta, é escala
      // vazia — e o verde ali diria ao líder que não há nada a fazer.
      expect(c.todosConfirmaram, isFalse);
    });
  });

  group('quem falta, pelo nome', () {
    const nomes = {'a': 'Ana', 'b': 'Bruno', 'c': 'Carla', 'd': 'Davi'};

    test('uma pessoa', () {
      final c = culto([levita('a', ok: true), levita('b')]);
      expect(c.faltamConfirmar(nomes), 'Falta confirmar: Bruno');
    });

    test('duas e três saem com "e" antes da última', () {
      expect(culto([levita('a'), levita('b')]).faltamConfirmar(nomes),
          'Falta confirmar: Ana e Bruno');
      expect(
          culto([levita('a'), levita('b'), levita('c')])
              .faltamConfirmar(nomes),
          'Falta confirmar: Ana, Bruno e Carla');
    });

    test('mais que o limite viram "e mais 1"', () {
      // A lista inteira de uma escala de 12 viraria um parágrafo no cartão do
      // Início, e quem lê quer a primeira informação sem rolar a tela.
      expect(
          culto([levita('a'), levita('b'), levita('c'), levita('d')])
              .faltamConfirmar(nomes),
          'Falta confirmar: Ana, Bruno, Carla e mais 1');
    });

    test('ninguém faltando é texto vazio, não "Falta confirmar:"', () {
      expect(culto([levita('a', ok: true)]).faltamConfirmar(nomes), '');
      expect(culto([]).faltamConfirmar(nomes), '');
    });
  });

  group('o nome vem do CADASTRO, não da cópia dentro do culto', () {
    test('cadastro manda sobre a cópia velha', () {
      // A pessoa corrigiu o próprio nome: o culto montado antes guarda o
      // antigo. Resolver por id é a mesma razão por que a escala guarda
      // referência de música e nunca cópia.
      final l = levita('a', nome: 'Ana Silv');
      expect(l.nomeCom(const {'a': 'Ana Silva'}), 'Ana Silva');
    });

    test('sem cadastro, vale a cópia', () {
      expect(levita('a', nome: 'Ana').nomeCom(const {}), 'Ana');
    });

    test('CULTO GERADO PELA AGENDA FIXA: cópia vazia, nome do cadastro', () {
      // O gerador monta o culto a partir da equipe, que guarda só ids, e
      // grava `userName` vazio — nos dois geradores (app e Worker).
      expect(levita('a').nomeCom(const {'a': 'Ana'}), 'Ana');
    });

    test('nem cadastro nem cópia não deixa linha em branco', () {
      // Alguém que saiu e cujo documento ficou. Linha vazia o líder leria
      // como "não tem ninguém aqui".
      expect(levita('fantasma').nomeCom(const {}), 'Alguém');
    });

    test('A INICIAL NUNCA INDEXA TEXTO VAZIO', () {
      // A tela do culto fazia `userName[0]`, e `''[0]` LANÇA: todo culto
      // criado pela agenda fixa com equipe padrão derrubava a tela inteira,
      // no meio da lista de escalados.
      expect(levita('a').inicialCom(const {}), 'A'); // "Alguém"
      expect(levita('a', nome: 'ana').inicialCom(const {}), 'A');
      expect(levita('a').inicialCom(const {'a': 'Bruno'}), 'B');
      // Espaço em branco é tão vazio quanto vazio.
      expect(levita('a', nome: '   ').inicialCom(const {}), 'A');
    });
  });
}
