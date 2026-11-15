import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/livros_biblia.dart';
import 'package:levitasync/data/services/biblia_service.dart';

/// A Bíblia é um arquivo de dados grande que ninguém relê. Estes testes são o
/// que impede um erro silencioso ali — um livro faltando, uma sigla que não
/// casa com o nome, um crédito que some e leva a licença junto.
void main() {
  group('a tabela dos 66 livros', () {
    test('tem 39 no Antigo e 27 no Novo', () {
      expect(livrosDaBiblia.length, 66);
      expect(livrosDaBiblia.where((l) => l.ehAntigo).length, 39);
      expect(livrosDaBiblia.where((l) => !l.ehAntigo).length, 27);
    });

    test('nenhuma sigla repetida e nenhum nome vazio', () {
      final siglas = livrosDaBiblia.map((l) => l.sigla).toList();
      expect(siglas.toSet().length, siglas.length);
      for (final l in livrosDaBiblia) {
        expect(l.nome.trim(), isNotEmpty, reason: 'sigla ${l.sigla}');
        expect(l.sigla.trim(), isNotEmpty);
      }
    });

    test('a busca acha sem acento, que é como se digita no celular', () {
      String buscavelDe(String nome) =>
          LivroBiblia('x', nome, Testamento.novo).buscavel;
      expect(buscavelDe('Gênesis'), 'genesis');
      expect(buscavelDe('João'), 'joao');
      expect(buscavelDe('Êxodo'), 'exodo');
      expect(buscavelDe('1 Coríntios'), '1 corintios');
    });

    test('sigla desconhecida devolve a própria sigla, e não vazio', () {
      // Uma tradução futura com um livro a mais tem de aparecer na tela,
      // ainda que sem nome bonito, em vez de sumir.
      expect(nomeDoLivro('xx'), 'xx');
      expect(nomeDoLivro('jo'), 'João');
    });
  });

  group('os arquivos das traduções', () {
    for (final t in traducoesDisponiveis) {
      test('${t.sigla}: 66 livros, e cada sigla casa com a tabela', () {
        final arquivo = File('assets/biblia/${t.id}.json');
        expect(arquivo.existsSync(), isTrue,
            reason: 'falta assets/biblia/${t.id}.json — '
                'rode: bash ferramentas/baixar-biblia.sh');

        final dados =
            jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
        final livros = dados['livros'] as List;
        expect(livros.length, 66);

        final conhecidas = livrosDaBiblia.map((l) => l.sigla).toSet();
        for (final livro in livros) {
          final sigla = (livro as Map<String, dynamic>)['s'] as String;
          expect(conhecidas, contains(sigla),
              reason: 'sigla "$sigla" não está em livros_biblia.dart');
          final caps = livro['c'] as List;
          expect(caps, isNotEmpty, reason: '$sigla sem capítulos');
          for (final cap in caps) {
            expect(cap, isNotEmpty, reason: '$sigla com capítulo vazio');
          }
        }
      });

      test('${t.sigla}: o crédito da licença está no arquivo', () {
        // A Bíblia Livre é Creative Commons Atribuição: distribuir o texto
        // sem o crédito descumpre a licença. O crédito viaja dentro do
        // arquivo para não se perder numa cópia.
        final dados = jsonDecode(
                File('assets/biblia/${t.id}.json').readAsStringSync())
            as Map<String, dynamic>;
        expect((dados['credito'] as String?) ?? '', isNotEmpty);
        expect((dados['licenca'] as String?) ?? '', isNotEmpty);
        expect(dados['sigla'], t.sigla);
      });
    }

    test('nenhuma tradução de editora entrou na lista', () {
      // NVI, ARA, NAA, ARC e companhia pertencem a editoras: achar o arquivo
      // na internet não dá direito de distribuir.
      const proibidas = ['NVI', 'ARA', 'NAA', 'ARC', 'ACF', 'NTLH', 'NVT'];
      for (final t in traducoesDisponiveis) {
        expect(proibidas, isNot(contains(t.sigla)));
        expect(t.licencaCurta.trim(), isNotEmpty);
      }
    });
  });

  group('o link do YouVersion', () {
    test('abre o MESMO capítulo, na NVI', () {
      // Conferido no próprio site: /pt/bible/129/JHN.3 é João 3 em NVI.
      final u = BibliaService.noYouVersion('jo', 3);
      expect(u.host, 'www.bible.com');
      expect(u.path, '/pt/bible/129/JHN.3');
    });

    test('usa o código USFM, que nem sempre lembra o nome', () {
      // Cantares é SNG, Filipenses é PHP: errar aqui levaria a pessoa a um
      // capítulo de outro livro, sem nenhum aviso.
      expect(BibliaService.noYouVersion('ct', 2).path, '/pt/bible/129/SNG.2');
      expect(BibliaService.noYouVersion('fp', 4).path, '/pt/bible/129/PHP.4');
      expect(BibliaService.noYouVersion('1co', 13).path,
          '/pt/bible/129/1CO.13');
    });

    test('todos os 66 livros têm código, senão o botão cai na busca', () {
      for (final l in livrosDaBiblia) {
        expect(l.usfm, isNotEmpty, reason: 'livro ${l.sigla} sem USFM');
        expect(l.usfm.length, inInclusiveRange(3, 3),
            reason: '${l.sigla}: "${l.usfm}" não é um código de três letras');
      }
    });

    test('livro desconhecido não vira endereço inventado', () {
      // Melhor uma busca que leva a algum lugar do que uma página de erro.
      final u = BibliaService.noYouVersion('xx', 1);
      expect(u.path, '/search/bible');
      expect(u.queryParameters['q'], 'xx 1');
    });
  });
}
