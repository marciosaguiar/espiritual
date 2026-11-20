// Fotografa as telas do app em vários tamanhos, nos dois temas.
//
// COMO USAR
//
//   CAPTURAR_EM=/pasta/das/fotos flutter test ferramentas/captura/capturar_telas_test.dart
//
// Opcionais (separados por vírgula):
//
//   LARGURAS=375,768,1280,1920     (padrão: as quatro)
//   TELAS=inicio,escala,musica,hinarios,chat,perfil     (padrão: todas)
//   TEMAS=claro,escuro             (padrão: os dois)
//
// POR QUE EXISTE
//
// Não dá para conferir tela lendo código: a rodada de 375 px achou cinco
// defeitos que nenhum teste via, e a de tela larga precisa do mesmo olhar. Isto
// roda o app DE VERDADE — as telas, os providers e o tema são os do app —, só
// que sem Firebase: os providers recebem dados inventados
// (`dados_inventados.dart`), por isso não precisa de emulador, de rede, nem de
// navegador.
//
// O QUE ESTA FOTO NÃO É
//
// É o renderizador de testes do Flutter, com as fontes do app carregadas. A
// distribuição das telas, as cores e o texto são os reais; o desfoque do vidro,
// a suavização das letras e o comportamento de toque/rolagem de um navegador
// de verdade, não. Foto daqui prova que NADA ESTOURA nem fica cortado, e não
// substitui abrir o app num iPhone.
//
// Não roda no `flutter test` normal: fica fora da pasta `test/` de propósito,
// para ninguém esperar dezenas de fotos a cada commit.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:levitasync/presentation/screens/songs/hino_por_numero_screen.dart';
import 'package:levitasync/presentation/widgets/common/responsivo.dart';

import '../../test/utilitarios/app_inventado.dart';

final _chave = GlobalKey();

Future<void> _foto(WidgetTester t, String arquivo, Tamanho tam) async {
  final fronteira = t.renderObject<RenderRepaintBoundary>(find.byKey(_chave));
  await t.runAsync(() async {
    final imagem = await fronteira.toImage(pixelRatio: tam.escala);
    final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
    File(arquivo)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _tocar(WidgetTester t, Finder f) async {
  await t.tap(f.first, warnIfMissed: false);
  await assentar(t);
}

/// Cada tela: a aba em que o app abre e o que tocar até chegar nela.
class _Tela {
  final String nome;
  final int aba;
  final Future<void> Function(WidgetTester t)? depois;
  const _Tela(this.nome, this.aba, [this.depois]);
}

final _telas = <_Tela>[
  const _Tela('inicio', 0),
  // O culto aberto: ao lado do calendário em tela larga, por cima no celular.
  _Tela('escala', 2, (t) => _tocar(t, find.textContaining('Culto de quarta'))),
  _Tela('musica', 1,
      (t) => _tocar(t, find.textContaining('Grande é a tua fidelidade'))),
  // Hinários como a pessoa o encontra: com dedo (celular) o teclado; com
  // mouse (computador), direto na lista.
  _Tela('hinarios', 1, (t) => _tocar(t, find.text('Hinários'))),
  _Tela('hinarios-lista', 1, (t) async {
    await _tocar(t, find.text('Hinários'));
    if (find.text('Ver todos os hinos').evaluate().isNotEmpty) {
      await _tocar(t, find.text('Ver todos os hinos'));
    }
  }),
  _Tela('hinarios-busca', 1, (t) async {
    await _tocar(t, find.text('Hinários'));
    if (find.text('Ver todos os hinos').evaluate().isNotEmpty) {
      await _tocar(t, find.text('Ver todos os hinos'));
    }
    await t.enterText(
        find.descendant(
            of: find.byType(HinoPorNumeroScreen),
            matching: find.byType(TextField)),
        'promessa firmes');
    await assentar(t);
    await _tocar(t, find.text('Trazer'));
  }),
  // O iPad: tela larga, mas com o dedo — o teclado numérico volta.
  _Tela('hinarios-toque', 1, (t) async {
    EntradaDoUsuario.registrar(PointerDeviceKind.touch);
    await _tocar(t, find.text('Hinários'));
  }),
  const _Tela('chat', 3),
  const _Tela('perfil', 4),
  // Rolada: é quando o cabeçalho do Perfil encolhe, e onde o avatar ficava
  // cortado.
  _Tela('perfil-rolado', 4, (t) async {
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -110));
    await assentar(t);
  }),
  _Tela('perfil-recolhido', 4, (t) async {
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -400));
    await assentar(t);
  }),
  _Tela('projetar', 1, (t) async {
    await _tocar(t, find.textContaining('Grande é a tua fidelidade'));
    await _tocar(t, find.byTooltip('Mais opções'));
    await _tocar(t, find.text('Projetar a letra (tela cheia)'));
    await assentar(t);
  }),
];

void main() {
  final saida = Platform.environment['CAPTURAR_EM'];
  if (saida == null) {
    test('captura de telas', () {}, skip: 'defina CAPTURAR_EM=<pasta>');
    return;
  }

  List<String> lista(String chave, List<String> padrao) {
    final v = Platform.environment[chave];
    return v == null || v.trim().isEmpty
        ? padrao
        : v.split(',').map((e) => e.trim()).toList();
  }

  final larguras = lista('LARGURAS', ['375', '768', '1280', '1920'])
      .map(int.parse)
      .toList();
  final nomes = lista('TELAS', _telas.map((e) => e.nome).toList());
  final temas = lista('TEMAS', ['claro', 'escuro']);

  setUpAll(carregarFontes);

  for (final largura in larguras) {
    final tam = tamanhos[largura]!;
    for (final tema in temas) {
      for (final tela in _telas.where((e) => nomes.contains(e.nome))) {
        testWidgets('$largura ${tema.padRight(6)} ${tela.nome}', (t) async {
          addTearDown(t.view.reset);
          addTearDown(() => EntradaDoUsuario.registrar(PointerDeviceKind.mouse));
          EntradaDoUsuario.registrar(PointerDeviceKind.mouse);
          await montarApp(t,
              tam: tam, escuro: tema == 'escuro', aba: tela.aba, chave: _chave);
          if (tela.depois != null) await tela.depois!(t);
          await _foto(t, '$saida/$largura-$tema-${tela.nome}.png', tam);
          // Desmonta, para o relógio do MainScreen não ficar pendente.
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
