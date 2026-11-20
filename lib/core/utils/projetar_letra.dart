/// Projetar a letra: dividir em slides, entender as teclas, escolher o tamanho.
///
/// POR QUE ISTO É PURO
///
/// Quem projeta está de pé, com a igreja olhando para a tela. Um slide que
/// corta uma estrofe ao meio, uma linha que some, ou uma tecla que não faz o
/// que se espera aparece para todo mundo — e nenhuma dessas falhas dá erro.
/// Por isso a conta não lê tela, relógio nem provider, e tem teste.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'cifra_colada.dart';
import 'texto.dart';

/// Um slide: uma estrofe (ou refrão), com o rótulo dela.
class SlideDeLetra {
  /// "1", "2", "Refrão", "Côro". Nulo quando o texto não marca a parte.
  final String? rotulo;
  final List<String> linhas;

  const SlideDeLetra({this.rotulo, required this.linhas});
}

final _marcador = RegExp(r'^\[(.+)\]$');
final _palavraDeParte = RegExp(r'^(refrao|coro|ponte|pre-refrao)\s*:?\s*$');
final _numeroDeEstrofe = RegExp(r'^(\d{1,2})[.)]?\s+(\S.*)$');

String _rotuloDe(String bruto) {
  final t = bruto.trim();
  if (RegExp(r'^\d{1,2}$').hasMatch(t)) return t;
  final sem = semAcento(t);
  if (sem.startsWith('refrao')) return 'Refrão';
  if (sem.startsWith('coro')) return 'Côro';
  if (sem.startsWith('pre-refrao')) return 'Pré-refrão';
  if (sem.startsWith('ponte')) return 'Ponte';
  return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
}

/// Divide [letra] em slides, um por estrofe.
///
/// - **Nunca mostra cifra**: se o texto for uma cifra, só a letra entra.
/// - **O número da estrofe sai do texto e vira o rótulo** ("1 Eu vi…" → rótulo
///   "1", linha "Eu vi…"), e `REFRÃO`, `[côro]` e `[2]` também são rótulos, não
///   versos: não se canta "refrão".
/// - **Uma estrofe comprida é partida** em slides de no máximo
///   [maximoDeLinhas], sem cortar verso e sem perder nem repetir nenhum.
/// - Letra vazia não tem slide nenhum — a tela diz isso, em vez de ficar preta.
List<SlideDeLetra> dividirEmSlides(String letra, {int maximoDeLinhas = 6}) {
  final pura = CifraColada.letraDe(letra);
  final blocos = <({String? rotulo, List<String> linhas})>[];
  String? rotulo;
  var linhas = <String>[];

  void fechar() {
    if (linhas.isNotEmpty) blocos.add((rotulo: rotulo, linhas: linhas));
    linhas = <String>[];
    rotulo = null;
  }

  for (final bruta in pura.split('\n')) {
    final linha = bruta.trim();
    if (linha.isEmpty) {
      fechar();
      continue;
    }
    final m = _marcador.firstMatch(linha);
    if (m != null) {
      fechar();
      rotulo = _rotuloDe(m.group(1)!);
      continue;
    }
    if (_palavraDeParte.hasMatch(semAcento(linha))) {
      fechar();
      rotulo = _rotuloDe(linha.replaceAll(':', ''));
      continue;
    }
    // O número só vale como rótulo NO COMEÇO de um bloco: "5 pães e 2 peixes"
    // no meio de uma estrofe é verso.
    if (linhas.isEmpty && rotulo == null) {
      final n = _numeroDeEstrofe.firstMatch(linha);
      if (n != null) {
        rotulo = n.group(1);
        linhas.add(n.group(2)!.trim());
        continue;
      }
    }
    linhas.add(linha);
  }
  fechar();

  final slides = <SlideDeLetra>[];
  for (final b in blocos) {
    for (var i = 0; i < b.linhas.length; i += maximoDeLinhas) {
      final fim = math.min(i + maximoDeLinhas, b.linhas.length);
      slides.add(SlideDeLetra(rotulo: b.rotulo, linhas: b.linhas.sublist(i, fim)));
    }
  }
  return slides;
}

/// O que cada tecla faz, para quem projeta ou conduz com o teclado.
enum AcaoDoPalco {
  proxima,
  anterior,
  primeira,
  ultima,
  sair,
  telaCheia,
  proximaMusica,
  musicaAnterior,
}

/// A ação de uma tecla, ou nulo se ela não faz nada aqui.
///
/// As teclas são as de quem passa slides: espaço, setas, Page Down/Up e Enter
/// avançam; Shift+espaço volta; Esc sai. **Enter avança** de propósito: o botão
/// "próximo" dos controles de apresentador costuma mandar Enter ou Page Down.
/// Shift+seta troca de música, para o Modo ao vivo.
AcaoDoPalco? acaoDaTecla(LogicalKeyboardKey k, {bool shift = false}) {
  if (shift && k == LogicalKeyboardKey.arrowRight) {
    return AcaoDoPalco.proximaMusica;
  }
  if (shift && k == LogicalKeyboardKey.arrowLeft) {
    return AcaoDoPalco.musicaAnterior;
  }
  if (shift && k == LogicalKeyboardKey.space) return AcaoDoPalco.anterior;

  if (k == LogicalKeyboardKey.space ||
      k == LogicalKeyboardKey.arrowRight ||
      k == LogicalKeyboardKey.arrowDown ||
      k == LogicalKeyboardKey.pageDown ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter) {
    return AcaoDoPalco.proxima;
  }
  if (k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.pageUp ||
      k == LogicalKeyboardKey.backspace) {
    return AcaoDoPalco.anterior;
  }
  if (k == LogicalKeyboardKey.home) return AcaoDoPalco.primeira;
  if (k == LogicalKeyboardKey.end) return AcaoDoPalco.ultima;
  if (k == LogicalKeyboardKey.escape) return AcaoDoPalco.sair;
  if (k == LogicalKeyboardKey.keyF) return AcaoDoPalco.telaCheia;
  return null;
}

/// O maior tamanho de fonte em que todas as [linhas] cabem em [largura] ×
/// [altura], entre 18 e 200.
///
/// Letra projetada é lida de longe: quanto maior, melhor — até onde a linha
/// mais comprida ainda cabe sem quebrar e as linhas todas cabem na altura. É
/// uma estimativa (a Poppins tem ~0,58 de largura média por caractere), e é
/// assim de propósito: medir texto de verdade custaria um layout por slide.
double tamanhoDaFonte({
  required List<String> linhas,
  required double largura,
  required double altura,
}) {
  final maiorLinha = linhas.fold<int>(1, (m, l) => math.max(m, l.length));
  final porLargura = (largura * 0.88) / (maiorLinha * 0.58);
  final porAltura = (altura * 0.70) / (math.max(linhas.length, 1) * 1.32);
  return math.min(porLargura, porAltura).clamp(18.0, 200.0).toDouble();
}
