/// O app em telas de tamanhos diferentes: o que muda de lugar, e o que não.
///
/// A REGRA: UM APP SÓ, NÃO DUAS VERSÕES
///
/// O celular a 375 px continua sendo o que sempre foi — a barra de baixo,
/// uma tela de cada vez. Nada aqui muda ele. O que existe é um jeito de as
/// MESMAS telas se comportarem melhor quando sobra espaço:
///
/// - a barra de navegação vai para o lado ([Porte.navegacaoLateral]);
/// - a leitura ganha uma largura máxima confortável ([ColunaCentral]);
/// - lista e conteúdo ficam lado a lado, em vez de uma tela empilhar sobre a
///   outra ([MestreDetalhe]) — para o líder montar escala e repertório sem ir
///   e voltar.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'glass.dart';

/// As larguras em que o app muda de jeito. Estão todas aqui para ninguém
/// escrever "900" no meio de uma tela e esquecer por quê.
class Porte {
  const Porte._();

  /// A partir daqui a barra de baixo vira navegação lateral. 720 é entre o
  /// celular grande (até ~430) e o tablet em pé (768): onde a barra de baixo,
  /// esticada, passa a parecer uma régua.
  static const double navegacaoLateral = 720;

  /// A partir daqui a navegação lateral ganha o nome ao lado do ícone.
  static const double navegacaoLarga = 1100;

  /// Largura do CONTEÚDO (já sem a navegação) a partir da qual lista e
  /// detalhe ficam lado a lado. Abaixo disso cada painel ficaria apertado
  /// demais para ser lido.
  static const double doisPaineis = 880;

  /// Largura máxima de uma coluna de leitura (chat, perfil, música).
  static const double colunaDeLeitura = 760;

  /// Largura máxima de uma tela de painéis (Início).
  static const double colunaLarga = 1180;

  /// A janela é larga o bastante para a navegação lateral?
  static bool lateral(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= navegacaoLateral;
}

/// Centraliza [child] com no máximo [largura] de largura.
///
/// Texto de 2.400 px de largura não se lê: o olho se perde na volta da linha.
/// É isto que impede o chat e o perfil de esticarem num monitor.
class ColunaCentral extends StatelessWidget {
  final double largura;
  final Widget child;

  const ColunaCentral({
    super.key,
    this.largura = Porte.colunaDeLeitura,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: largura),
        child: child,
      ),
    );
  }
}

// ─── Dedo ou mouse ────────────────────────────────────────────────────────

/// Como a pessoa está usando o aparelho: com o dedo ou com o mouse.
///
/// POR QUE ISTO EXISTE
///
/// O teclado numérico na tela serve a quem toca, e atrapalha quem tem um
/// teclado de verdade: num computador, digitar "15" e Enter é mais rápido que
/// procurar o 1 e o 5 com o mouse. Mas o navegador não diz se há tela de
/// toque — um iPad grande e um monitor de 1920 px têm a mesma largura. O que
/// se pode saber é o que a pessoa USOU por último.
///
/// A regra: tela estreita (celular) é sempre toque; tela larga começa como
/// mouse, e vira toque no primeiro toque de dedo — e volta a mouse no
/// primeiro movimento do mouse.
class EntradaDoUsuario {
  const EntradaDoUsuario._();

  static final ValueNotifier<bool> _toque = ValueNotifier<bool>(false);

  /// Muda quando a pessoa passa do mouse para o dedo, ou o contrário.
  static ValueListenable<bool> get toque => _toque;

  static void registrar(PointerDeviceKind tipo) {
    final dedo =
        tipo == PointerDeviceKind.touch || tipo == PointerDeviceKind.stylus;
    if (_toque.value != dedo) _toque.value = dedo;
  }

  /// Só para os testes.
  @visibleForTesting
  static void definir(bool dedo) => _toque.value = dedo;

  /// Esta pessoa, agora, usa o dedo?
  static bool usaToque(BuildContext context) =>
      MediaQuery.sizeOf(context).width < Porte.navegacaoLateral ||
      _toque.value;
}

/// Olha os ponteiros que passam por cima do app e conta ao
/// [EntradaDoUsuario]. Vai uma vez só, em volta de tudo.
class OuvinteDeEntrada extends StatelessWidget {
  final Widget child;
  const OuvinteDeEntrada({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => EntradaDoUsuario.registrar(e.kind),
      onPointerHover: (e) => EntradaDoUsuario.registrar(e.kind),
      child: child,
    );
  }
}

/// Reconstrói [builder] quando a largura da janela ou o jeito de usar mudam.
class ConformeAEntrada extends StatelessWidget {
  final Widget Function(BuildContext context, bool toque) builder;
  const ConformeAEntrada({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EntradaDoUsuario.toque,
      builder: (ctx, _, __) => builder(ctx, EntradaDoUsuario.usaToque(ctx)),
    );
  }
}

// ─── Mouse: realce e mãozinha ─────────────────────────────────────────────

/// Dá a um bloco clicável o que o mouse espera: a mãozinha e um realce quando
/// passa por cima. Num celular não faz nada (não há "passar por cima").
class AoPassarOMouse extends StatefulWidget {
  final Widget Function(BuildContext context, bool passando) builder;
  final VoidCallback? onTap;

  const AoPassarOMouse({super.key, required this.builder, this.onTap});

  @override
  State<AoPassarOMouse> createState() => _AoPassarOMouseState();
}

class _AoPassarOMouseState extends State<AoPassarOMouse> {
  bool _passando = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _passando = true),
      onExit: (_) => setState(() => _passando = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(context, _passando),
      ),
    );
  }
}

// ─── Lista e detalhe lado a lado ──────────────────────────────────────────

/// O painel da direita de um [MestreDetalhe]: onde as telas "abertas por
/// cima" aparecem quando há espaço para isso.
class PainelDeDetalhe extends InheritedWidget {
  final GlobalKey<NavigatorState> _navegador;

  const PainelDeDetalhe._(this._navegador, {required super.child});

  /// O painel que está em volta de [context], ou nulo no celular — onde as
  /// telas abrem por cima, como sempre.
  static PainelDeDetalhe? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PainelDeDetalhe>();

  /// Mostra [builder] no painel, no lugar do que estava lá.
  Future<T?> abrir<T>(WidgetBuilder builder) {
    final estado = _navegador.currentState;
    if (estado == null) return Future.value(null);
    return estado.pushAndRemoveUntil<T>(
      PageRouteBuilder<T>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 140),
        reverseTransitionDuration: const Duration(milliseconds: 100),
        pageBuilder: (ctx, _, __) =>
            ColunaCentral(largura: 900, child: builder(ctx)),
        transitionsBuilder: (_, animacao, __, filho) =>
            FadeTransition(opacity: animacao, child: filho),
      ),
      (r) => r.isFirst,
    );
  }

  /// Fecha o que está no painel e volta ao "escolha um item".
  void fechar() => _navegador.currentState?.popUntil((r) => r.isFirst);

  /// Há algo aberto no painel?
  bool get aberto => _navegador.currentState?.canPop() ?? false;

  @override
  bool updateShouldNotify(PainelDeDetalhe old) => old._navegador != _navegador;
}

/// Abre [builder] como se abre uma tela neste app: por cima, no celular — e
/// no painel da direita, quando a tela é larga o bastante para ter um.
///
/// É o que permite trocar um `Navigator.push` por esta chamada sem a tela que
/// chama precisar saber em que tamanho de janela está.
Future<T?> abrirTela<T>(BuildContext context, WidgetBuilder builder) {
  final painel = PainelDeDetalhe.maybeOf(context);
  if (painel != null) return painel.abrir<T>(builder);
  return Navigator.push<T>(context, GlassPageRoute<T>(builder: builder));
}

/// Lista à esquerda, detalhe à direita — ou só a lista, se a tela é estreita.
///
/// O líder que monta a escala precisa ver a lista de cultos E o culto aberto;
/// com uma tela empilhando sobre a outra, cada culto é um vai-e-volta.
class MestreDetalhe extends StatefulWidget {
  /// A lista.
  final Widget mestre;

  /// O que o painel da direita diz enquanto nada está aberto.
  final String vazioTitulo;
  final String vazioTexto;
  final IconData vazioIcone;

  /// Largura MÁXIMA da lista quando há dois painéis (ela cresce com a janela,
  /// até aqui).
  final double larguraDoMestre;

  const MestreDetalhe({
    super.key,
    required this.mestre,
    required this.vazioTitulo,
    required this.vazioTexto,
    this.vazioIcone = Icons.touch_app_outlined,
    this.larguraDoMestre = 440,
  });

  @override
  State<MestreDetalhe> createState() => _MestreDetalheState();
}

class _MestreDetalheState extends State<MestreDetalhe> {
  final _navegador = GlobalKey<NavigatorState>();

  /// Segura o estado da lista quando a janela cruza a largura de dois painéis
  /// (redimensionar, girar o tablet): sem isto, a busca digitada e a posição
  /// da rolagem se perderiam.
  final _chaveDoMestre = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final mestre = KeyedSubtree(key: _chaveDoMestre, child: widget.mestre);
        if (c.maxWidth < Porte.doisPaineis) return mestre;

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return PainelDeDetalhe._(
          _navegador,
          child: Row(
            children: [
              SizedBox(
                width: (c.maxWidth * 0.36).clamp(360.0, widget.larguraDoMestre),
                child: mestre,
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.08),
              ),
              Expanded(
                child: Navigator(
                  key: _navegador,
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (_, __, ___) => _SemNadaAberto(
                      titulo: widget.vazioTitulo,
                      texto: widget.vazioTexto,
                      icone: widget.vazioIcone,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SemNadaAberto extends StatelessWidget {
  final String titulo;
  final String texto;
  final IconData icone;

  const _SemNadaAberto({
    required this.titulo,
    required this.texto,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cor = isDark ? Colors.white54 : Colors.black45;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 44, color: cor),
              const SizedBox(height: 14),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                texto,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13.5,
                  height: 1.45,
                  color: cor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
