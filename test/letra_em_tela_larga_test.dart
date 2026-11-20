// A letra numa tela larga: ocupa a área de leitura, alinhada à esquerda, e
// respeita as quebras de linha do texto.
//
// O defeito: a letra aparecia como uma coluna de ~360 px boiando no MEIO da
// tela. Um `SingleChildScrollView` dentro de um `Column` encolhe até a largura
// do que tem dentro (a linha mais comprida) e o `Column` o centraliza. No
// celular ninguém via, porque a linha já enche a tela — e nenhum teste de
// layout tinha uma tela larga com letra de linhas curtas.
//
// TODO o texto é inventado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/constants/hinarios.dart';
import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/presentation/screens/songs/hino_da_biblioteca_screen.dart';
import 'package:levitasync/presentation/screens/songs/song_detail_screen.dart';
import 'package:levitasync/presentation/widgets/common/responsivo.dart';

import 'utilitarios/app_inventado.dart';
import 'utilitarios/fontes.dart';

/// Quanto a letra pode estar afastada da borda da área de leitura: o recuo de
/// 20 px da tela, com uma folga. Centralizada, ela ficaria a centenas de px.
const _recuoMaximo = 24.0;

/// Uma letra com linhas de verdade comprida, como as de um hinário.
final _letraLonga = [
  for (var i = 1; i <= 6; i++)
    '$i O Senhor é o meu pastor e nada me faltará, em verdes pastos me faz '
        'descansar',
].join('\n');

/// A altura que o texto teria SEM nenhum limite de largura: o que ele ocupa
/// quando só quebra onde o texto quebra. Se o parágrafo desenhado for mais
/// alto que isto, alguma linha foi quebrada à força.
double _alturaSemQuebrar(WidgetTester t, Finder f) {
  final w = t.widget<Text>(f);
  final p = TextPainter(
    text: TextSpan(text: w.data, style: w.style),
    textDirection: TextDirection.ltr,
  )..layout();
  return p.height;
}

void main() {
  setUpAll(carregarFontesDoApp);

  for (final largura in [1280, 1920, 2400]) {
    final tam = tamanhos[largura]!;

    group('a $largura px', () {
      testWidgets('a música aberta ao lado: a letra começa na borda da leitura, '
          'não no meio da tela', (t) async {
        addTearDown(t.view.reset);
        await montarApp(t, tam: tam, aba: 1);
        await t.tap(find.text('Aliança eterna').first);
        await assentar(t);

        final detalhe = t.getRect(find.byType(SongDetailScreen));
        final letra = t.getRect(find.textContaining('Firmes na promessa'));
        expect(letra.left - detalhe.left, lessThanOrEqualTo(_recuoMaximo),
            reason: 'a letra boia no meio da tela, longe da borda');
      });

      testWidgets('o hino da biblioteca: largura da leitura e sem quebrar '
          'linha à toa', (t) async {
        addTearDown(t.view.reset);
        await montarApp(
          t,
          tam: tam,
          // Do mesmo jeito que o painel o mostra: numa coluna de leitura.
          casa: Scaffold(
            body: ColunaCentral(
              largura: 900,
              child: HinoDaBibliotecaScreen(
                hinario: harpaCrista,
                hino: HinoDaBiblioteca(
                  hinario: 'harpa',
                  numero: 23,
                  titulo: 'Pastor de todos',
                  letra: _letraLonga,
                ),
              ),
            ),
          ),
        );

        final detalhe = t.getRect(find.byType(HinoDaBibliotecaScreen));
        final letra = find.textContaining('O Senhor é o meu pastor');
        expect(t.getRect(letra).left - detalhe.left,
            lessThanOrEqualTo(_recuoMaximo),
            reason: 'o hino boia no meio da tela');
        // Nenhuma linha quebrou no meio da frase: o parágrafo desenhado tem a
        // altura de seis linhas, e não a de nove ou dez.
        expect(t.getSize(letra).height,
            closeTo(_alturaSemQuebrar(t, letra), 1),
            reason: 'uma linha do hino quebrou onde o texto não quebra');
      });
    });
  }
}
