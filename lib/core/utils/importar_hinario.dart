/// Ler um hinário colado: achar onde começa cada hino.
///
/// O líder cola o texto do hinário que a igreja tem direito de usar, e o app
/// separa em hinos. Este arquivo é só a CONTA — função pura, sem tela e sem
/// banco —, porque é a parte que erra em silêncio: um hino que perde a
/// primeira estrofe, ou que engole o seguinte, aparece inteiro na tela e
/// ninguém percebe até o culto.
///
/// O QUE O APP NÃO SABE: como é o arquivo da pessoa. Cada fonte escreve o
/// começo do hino de um jeito ("15 - Sou Grato", "HINO 15", o número sozinho
/// numa linha). Então não há um formato só: o app tenta todos e fica com o que
/// achou MAIS hinos de verdade ([FormatoDoHinario]). E, como errar de formato
/// é possível, ninguém grava nada sem antes ver o resultado — ver
/// [ResultadoDaLeitura.frase].
///
/// O PROBLEMA QUE MAIS ENGANA: o número da ESTROFE. Num hinário, "2." pode ser
/// a segunda estrofe do hino 1 ou o começo do hino 2. Por isso o formato é
/// escolhido para o texto INTEIRO, e não linha a linha: o formato "15 - Título"
/// acha 640 hinos com letra; o "15. Título" acharia só estrofes, números de 1
/// a 6, e perderia.
///
/// O QUE O TEXTO REAL DA HARPA ENSINOU (e nenhum teste inventado previa): o
/// cabeçalho é "15. TÍTULO EM MAIÚSCULAS", com ponto, e do hino 200 em diante a
/// fonte numera as ESTROFES com ponto também ("1. palavras…"). No formato
/// "ponto" cada uma dessas estrofes virava um "hino" e cortava o cabeçalho de
/// verdade, que ficava sem letra. O título em maiúsculas é o que separa um do
/// outro, então o formato [FormatoDoHinario.caixaAlta] passou a aceitar o ponto.
/// E, como a fonte tem erros de digitação, a ORDEM dos números também vale:
/// um "442" entre o 541 e o 543 é o 542 escrito errado, e não pode apagar o
/// 442 de verdade.
library;

import '../constants/hinarios.dart';

/// Os jeitos de escrever o começo de um hino que o app reconhece.
///
/// A ORDEM É O DESEMPATE: se dois formatos acharem o mesmo número de hinos,
/// vale o primeiro da lista — do mais característico ao mais ambíguo.
enum FormatoDoHinario {
  hino('Hino 15  (o título na mesma linha ou na linha de baixo)'),
  traco('15 - Título'),
  caixaAlta('15 TÍTULO   ou   15. TÍTULO  (o título todo em maiúsculas)'),
  ponto('15. Título   ou   15) Título'),
  sozinho('O número sozinho numa linha, e o título na linha de baixo');

  /// Como o formato aparece escrito na tela, para a pessoa se reconhecer.
  final String exemplo;
  const FormatoDoHinario(this.exemplo);
}

/// Um hino que o app entendeu.
class HinoLido {
  final int numero;
  final String titulo;
  final String letra;

  const HinoLido({
    required this.numero,
    required this.titulo,
    required this.letra,
  });
}

/// Letra com menos que isto (sem contar espaço) não é letra: é um sumário, ou
/// um começo de hino que o texto não continuou. Não entra, e aparece na lista
/// de [ResultadoDaLeitura.curtos].
const int minimoDeLetra = 20;

/// Nenhum hino tem tanto texto. Passar disto quase sempre é o hino seguinte
/// que não foi reconhecido, e a letra engoliu o resto — o último hino levando
/// o índice do livro junto, por exemplo. Fica de fora e aparece em
/// [ResultadoDaLeitura.grandes], em vez de entrar com lixo no fim.
const int maximoDeLetra = 6000;

/// Linha mais comprida que isto não é título: é verso.
const int maximoDoTitulo = 90;

/// Um cabeçalho cujo número parece escrito errado.
///
/// Aparece quando um número repetido está ESCRITO fora da ordem e a posição
/// dele diz qual era o número de verdade: um "442" entre o 541 e o 543 só pode
/// ser o 542. O app NÃO corrige sozinho — trocar o número de um hino em
/// silêncio seria o mesmo erro de trocar a letra —, mas diz exatamente onde
/// está a linha para a pessoa consertar.
class NumeroSuspeito {
  /// O número que está escrito no texto.
  final int escrito;

  /// O número que a posição indica.
  final int provavel;

  /// O título do hino, como entraria na lista. Pode ser vazio.
  final String titulo;

  const NumeroSuspeito({
    required this.escrito,
    required this.provavel,
    required this.titulo,
  });
}

/// Um número que falta, mas que aparece no texto numa linha que NÃO foi
/// reconhecida como começo de hino.
///
/// É o defeito mais silencioso da leitura: o cabeçalho não é reconhecido, e o
/// hino anterior **engole o texto inteiro dele** — que entra na letra errada,
/// sem erro nenhum, enquanto a frase só diz "Falta o 584". Aqui o app aponta a
/// linha e o hino que a levou, para a pessoa consertar o texto.
class LinhaPerdida {
  /// O número que falta e que a linha parece trazer.
  final int numero;

  /// A linha como está no texto, já sem espaço nas pontas.
  final String linha;

  /// O hino em cuja letra a linha foi parar. Nulo se veio antes do primeiro.
  final int? dentroDe;

  const LinhaPerdida({
    required this.numero,
    required this.linha,
    required this.dentroDe,
  });
}

/// O rodapé de site que veio colado depois do último hino, e que o app TIROU.
///
/// Quem copia um hinário de um site leva junto o que está em volta: o nome do
/// site no começo e, no fim, o nome de novo e uma lista de endereços. Sem o
/// corte, tudo isso entrava na letra do último hino — e a prévia, que mostra
/// o começo de cada amostra, não deixava ver. O corte é DECLARADO (a tela diz
/// quantas linhas e a partir de qual), porque tirar texto em silêncio é o
/// mesmo erro de deixar entrar: a pessoa precisa poder conferir.
class RodapeTirado {
  /// O hino em cuja letra o rodapé teria entrado: o último do texto.
  final int hino;

  /// Quantas linhas (não vazias) saíram.
  final int linhas;

  /// A primeira delas, como está no texto.
  final String primeira;

  const RodapeTirado({
    required this.hino,
    required this.linhas,
    required this.primeira,
  });
}

/// O que o app entendeu do texto colado.
class ResultadoDaLeitura {
  /// O formato que achou mais hinos. Nulo quando não achou nenhum.
  final FormatoDoHinario? formato;

  /// Os hinos que podem ser gravados, em ordem de número, sem repetição.
  final List<HinoLido> hinos;

  /// Números que faltam ENTRE o primeiro e o último achados.
  ///
  /// Não conta o que está fora desse intervalo: quem colou só os hinos de 1 a
  /// 50 não tem "590 faltando", tem 50 achados. Colar o hinário em partes é
  /// o jeito normal de fazer isto.
  final List<int> faltando;

  /// Números que apareceram mais de uma vez. O app fica com a ocorrência que
  /// SERVE (letra de tamanho de hino), prefere a que está na ordem certa dos
  /// números e, no empate, a de letra mais comprida: a outra costuma ser o
  /// sumário.
  final List<int> repetidos;

  /// Números que parecem escritos errados: ver [NumeroSuspeito]. Não entram.
  final List<NumeroSuspeito> suspeitos;

  /// Números que faltam mas aparecem numa linha não reconhecida: ver
  /// [LinhaPerdida]. O texto deles está na letra de outro hino.
  final List<LinhaPerdida> perdidos;

  /// Achados, mas sem letra que chegue: não entram.
  final List<int> curtos;

  /// Achados, mas com letra grande demais para ser um hino: não entram.
  final List<int> grandes;

  /// Entraram, mas o título não foi reconhecido — ficou "Hino N".
  final List<int> semTitulo;

  /// Linhas que pareciam começo de hino com um número que o hinário não tem.
  final int foraDoLimite;

  /// O rodapé de site que saiu do fim do último hino, se havia.
  final RodapeTirado? rodape;

  /// Quantos dos hinos que entram vieram com a letra TODA EM MAIÚSCULAS.
  /// Conta o que veio no texto, antes de qualquer conversão: é o que a tela
  /// precisa para oferecer a conversão e dizer de quantos hinos se trata.
  final int emCaixaAlta;

  /// A letra desses hinos já foi convertida para maiúsculas e minúsculas.
  /// Só é verdade se alguém pediu E havia o que converter.
  final bool convertida;

  const ResultadoDaLeitura({
    required this.formato,
    required this.hinos,
    this.faltando = const [],
    this.repetidos = const [],
    this.suspeitos = const [],
    this.perdidos = const [],
    this.curtos = const [],
    this.grandes = const [],
    this.semTitulo = const [],
    this.foraDoLimite = 0,
    this.rodape,
    this.emCaixaAlta = 0,
    this.convertida = false,
  });

  /// O resultado de um texto em que nada foi reconhecido.
  static const vazio = ResultadoDaLeitura(formato: null, hinos: []);

  bool get achouAlgo => hinos.isNotEmpty;

  int? get primeiro => hinos.isEmpty ? null : hinos.first.numero;
  int? get ultimoAchado => hinos.isEmpty ? null : hinos.last.numero;

  /// A frase que a tela mostra: o que foi achado e o que falta.
  ///
  /// Mora aqui, e não na tela, porque são os casos de borda que a fazem soar
  /// como gente — "Falta o 4" e "Faltam o 4 e o 17" não são a mesma frase, e
  /// "Achei 1 hino" não é "Achei 1 hinos".
  String get frase {
    if (hinos.isEmpty) {
      return 'Não achei nenhum hino neste texto.';
    }
    final n = hinos.length;
    final sb = StringBuffer(n == 1 ? 'Achei 1 hino' : 'Achei $n hinos');
    if (n > 1) {
      sb.write(', do $primeiro ao $ultimoAchado');
    } else {
      sb.write(': o $primeiro');
    }
    sb.write('.');
    if (faltando.isNotEmpty) {
      sb.write(faltando.length == 1 ? ' Falta ' : ' Faltam ');
      sb.write(listaDeNumeros(faltando));
      sb.write('.');
    }
    return sb.toString();
  }

  /// "o 4", "o 4 e o 17", "o 4, o 17 e o 203" — e, passando de [maximo],
  /// "o 4, o 17, … e mais 9". Lista de 200 números não se lê.
  static String listaDeNumeros(List<int> numeros, {int maximo = 6}) {
    if (numeros.isEmpty) return '';
    final mostrar = numeros.take(maximo).map((n) => 'o $n').toList();
    final sobra = numeros.length - mostrar.length;
    if (sobra > 0) return '${mostrar.join(', ')} e mais $sobra';
    if (mostrar.length == 1) return mostrar.first;
    return '${mostrar.sublist(0, mostrar.length - 1).join(', ')} '
        'e ${mostrar.last}';
  }
}

/// A conta de ler o texto.
class ImportarHinario {
  const ImportarHinario._();

  /// Lê [texto] como um hinário de [hinario].
  ///
  /// [formato] força um formato, para quem viu que o app escolheu o errado.
  /// Sem ele, vale o que achou mais hinos.
  ///
  /// [converterCaixaAlta] passa para maiúsculas e minúsculas a letra dos hinos
  /// que vieram TODA EM MAIÚSCULAS ([letraEmMinusculas]). Desligado por padrão
  /// aqui, que é a função pura: quem pede é a tela, que mostra o resultado
  /// antes de gravar e deixa desligar.
  static ResultadoDaLeitura analisar(
    String texto,
    Hinario hinario, {
    FormatoDoHinario? formato,
    bool converterCaixaAlta = false,
  }) {
    final linhas = _linhasLimpas(texto);

    FormatoDoHinario? escolhido;
    List<_Candidato> candidatosEscolhidos = const [];
    Map<int, _Trecho> melhores = const {};
    var melhorPontos = 0;
    int? rodapeEscolhido;

    final opcoes = formato != null
        ? <FormatoDoHinario>[formato]
        : FormatoDoHinario.values;
    var trechosEscolhidos = const <_Trecho>[];
    for (final f in opcoes) {
      final candidatos = _candidatos(linhas, f);
      // O rodapé depende de onde o ÚLTIMO hino começa, que muda com o formato.
      final rodapeDesde = _rodapeDesde(linhas, candidatos);
      final trechos = _trechos(linhas, candidatos, hinario,
          fimDoTexto: rodapeDesde ?? linhas.length);
      final melhoresDeste = _melhoresPorNumero(trechos, hinario);
      // Só conta letra que SERVE: um formato que "acha" hino com 12 mil
      // caracteres de letra achou o hino seguinte colado, não um hino.
      final pontos = melhoresDeste.values.where((t) => t.serve).length;
      // `>` e não `>=`: no empate vale o primeiro da lista. Formato forçado
      // vale sempre, mesmo sem achar nada: a tela precisa poder dizer "neste
      // formato não achei hino", e não "formato nenhum".
      if (pontos > melhorPontos || formato != null) {
        melhorPontos = pontos;
        escolhido = f;
        candidatosEscolhidos = candidatos;
        trechosEscolhidos = trechos;
        melhores = melhoresDeste;
        rodapeEscolhido = rodapeDesde;
      }
    }

    if (escolhido == null) return ResultadoDaLeitura.vazio;

    // Quantas vezes cada número apareceu, para avisar dos repetidos.
    final vezes = <int, int>{};
    for (final t in trechosEscolhidos) {
      if (hinario.existe(t.numero)) {
        vezes[t.numero] = (vezes[t.numero] ?? 0) + 1;
      }
    }

    final hinos = <HinoLido>[];
    final curtos = <int>[];
    final grandes = <int>[];
    final semTitulo = <int>[];
    var emCaixaAlta = 0;
    final numeros = melhores.keys.toList()..sort();
    for (final n in numeros) {
      final t = melhores[n]!;
      if (t.tamanho < minimoDeLetra) {
        curtos.add(n);
        continue;
      }
      if (t.tamanho > maximoDeLetra) {
        grandes.add(n);
        continue;
      }
      var titulo = tituloLimpo(t.titulo);
      if (titulo.isEmpty) {
        titulo = 'Hino $n';
        semTitulo.add(n);
      }
      var letra = _letraLimpa(t.corpo);
      if (letraGritada(letra)) {
        emCaixaAlta++;
        if (converterCaixaAlta) letra = letraEmMinusculas(letra);
      }
      hinos.add(HinoLido(numero: n, titulo: titulo, letra: letra));
    }

    // O que saiu do fim do texto, para a tela DIZER que saiu.
    RodapeTirado? rodape;
    if (rodapeEscolhido != null && candidatosEscolhidos.isNotEmpty) {
      final fora = linhas.sublist(rodapeEscolhido).where((l) => l.isNotEmpty);
      if (fora.isNotEmpty) {
        rodape = RodapeTirado(
          hino: candidatosEscolhidos.last.numero,
          linhas: fora.length,
          primeira: fora.first,
        );
      }
    }

    // Só o que está ENTRE o primeiro e o último achados pode "faltar".
    final faltando = <int>[];
    if (hinos.length > 1) {
      final achados = hinos.map((h) => h.numero).toSet();
      for (var n = hinos.first.numero; n <= hinos.last.numero; n++) {
        if (!achados.contains(n)) faltando.add(n);
      }
    }

    final foraDoLimite =
        candidatosEscolhidos.where((c) => !hinario.existe(c.numero)).length;

    // Número que FALTA mas aparece no texto, numa linha que não foi reconhecida
    // como começo de hino: o texto dele foi parar na letra do hino anterior,
    // e a frase sozinha só diria "Falta o 584". Só números de 10 para cima:
    // abaixo disso a linha "4. palavras…" é uma estrofe, e todo hino que
    // faltasse acusaria a própria estrofe.
    final perdidos = <LinhaPerdida>[];
    final procurar = faltando.where((n) => n >= 10).toSet();
    if (procurar.isNotEmpty) {
      final reLinha = RegExp(r'^(\d{1,4})\s*[.)]\s*\S');
      final lugares = candidatosEscolhidos.map((c) => c.linha).toSet();
      var k = -1; // o último candidato que começa antes desta linha
      for (var i = 0; i < linhas.length; i++) {
        while (k + 1 < candidatosEscolhidos.length &&
            candidatosEscolhidos[k + 1].linha <= i) {
          k++;
        }
        if (lugares.contains(i)) continue;
        final m = reLinha.firstMatch(linhas[i]);
        if (m == null) continue;
        final n = int.parse(m.group(1)!);
        if (!procurar.contains(n) || perdidos.any((p) => p.numero == n)) continue;
        perdidos.add(LinhaPerdida(
          numero: n,
          linha: linhas[i],
          dentroDe: k >= 0 ? candidatosEscolhidos[k].numero : null,
        ));
      }
    }

    // Número repetido, de letra que serve, que ficou de fora porque está FORA
    // DA ORDEM, e cujo lugar no texto deixa só UM número possível entre os
    // vizinhos (541 · 442 · 543 → 542): provável erro de digitação. Só se o
    // número de verdade não foi achado em outro lugar.
    final achados = hinos.map((h) => h.numero).toSet();
    final suspeitos = <NumeroSuspeito>[];
    for (final t in trechosEscolhidos) {
      if (!hinario.existe(t.numero) || !t.serve || t.emOrdem) continue;
      if (identical(melhores[t.numero], t)) continue; // este entrou
      final a = t.antes;
      final d = t.depois;
      if (a == null || d == null || d - a != 2) continue;
      if (achados.contains(a + 1)) continue;
      final nome = tituloLimpo(t.titulo);
      suspeitos.add(NumeroSuspeito(
        escrito: t.numero,
        provavel: a + 1,
        titulo: nome,
      ));
    }

    return ResultadoDaLeitura(
      formato: escolhido,
      hinos: hinos,
      faltando: faltando,
      repetidos: (vezes.entries.where((e) => e.value > 1).map((e) => e.key)
          .toList()
        ..sort()),
      suspeitos: suspeitos,
      perdidos: perdidos,
      curtos: curtos,
      grandes: grandes,
      semTitulo: semTitulo,
      foraDoLimite: foraDoLimite,
      rodape: rodape,
      emCaixaAlta: emCaixaAlta,
      convertida: converterCaixaAlta && emCaixaAlta > 0,
    );
  }

  // ── Limpeza ───────────────────────────────────────────────────────────────

  /// O texto em linhas, sem as sujeiras invisíveis de quem copia de PDF, de
  /// site e de documento.
  ///
  /// Espaço que não é espaço (NBSP), caractere de largura zero e hífen
  /// invisível não aparecem na tela, mas fazem "15 - Sou Grato" deixar de
  /// casar com o padrão — e o hino some sem nenhum erro.
  static List<String> _linhasLimpas(String texto) {
    final t = texto
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\f', '\n')
        .replaceAll(RegExp('[​-‍⁠﻿­]'), '')
        .replaceAll(' ', ' ')
        .replaceAll('\t', ' ');
    return t.split('\n').map((l) => l.trim()).toList();
  }

  /// O título como vai aparecer: sem pontilhado de índice, sem marcação, e —
  /// se veio todo em maiúsculas — em maiúsculas e minúsculas.
  static String tituloLimpo(String bruto) {
    var t = bruto
        // "Sou Grato ........ 23": o pontilhado do sumário, com a página.
        .replaceAll(RegExp(r'\s*(\.\s*){3,}\s*\d*\s*$'), '')
        .replaceAll(RegExp(r'^[\s*_#]+'), '')
        .replaceAll(RegExp(r'[\s*_#.]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_quaseTodoMaiusculo(t)) t = emTituloBonito(t);
    return t;
  }

  static final _letra = RegExp(r'\p{L}', unicode: true);

  static bool _temLetra(String s) => _letra.hasMatch(s);

  /// Tem pelo menos três letras e quase todas são maiúsculas?
  ///
  /// "Quase" é de propósito. Texto copiado de PDF e de site tem erro de
  /// digitação, e "ALELUIA! JÁ CRElO" (um L minúsculo no lugar do I) é um
  /// título todo em maiúsculas para quem lê. Exigir ZERO minúsculas fazia esse
  /// cabeçalho não ser reconhecido — e, sem cabeçalho, o hino anterior engolia
  /// o texto dele inteiro, sem erro nenhum. 80% separa o título (quase tudo
  /// maiúsculo) de uma frase de estrofe, que tem uma maiúscula no começo e o
  /// resto em minúscula.
  static bool _quaseTodoMaiusculo(String s, {int minimoDeLetras = 3}) {
    var letras = 0;
    var maiusculas = 0;
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      if (c.toLowerCase() == c.toUpperCase()) continue; // não é letra
      letras++;
      if (c == c.toUpperCase()) maiusculas++;
    }
    return letras >= minimoDeLetras && maiusculas / letras >= 0.8;
  }

  // ── Letra toda em maiúsculas ──────────────────────────────────────────────

  /// "[1]", "[côro]": o marcador de estrofe, sozinho na linha.
  static final _reMarcador = RegExp(r'^\[[^\]]*\]$');

  /// A letra veio TODA EM MAIÚSCULAS?
  ///
  /// Decide pelo HINO, não pela linha: um "AMÉM! AMÉM!" gritado no fim de um
  /// hino normal não é o hino gritando, e converter só aquela linha a deixaria
  /// diferente das de cima. Passando de 80% das linhas (as que têm pelo menos
  /// três letras; marcadores de estrofe não contam), o hino é gritado.
  static bool letraGritada(String letra) {
    var total = 0;
    var gritadas = 0;
    for (final l in letra.split('\n')) {
      final t = l.trim();
      if (t.isEmpty || _reMarcador.hasMatch(t)) continue;
      var letras = 0;
      for (final r in t.runes) {
        final c = String.fromCharCode(r);
        if (c.toLowerCase() != c.toUpperCase()) letras++;
      }
      if (letras < 3) continue;
      total++;
      if (_quaseTodoMaiusculo(t)) gritadas++;
    }
    return total > 0 && gritadas / total >= 0.8;
  }

  /// Nomes que levam inicial maiúscula em qualquer lugar da frase.
  ///
  /// Só entram palavras que, num hinário, quase nunca são outra coisa. Fica de
  /// fora o que também é palavra comum ("santo", "amigo", "guia", "luz") e o
  /// que se escreve minúsculo em português (judeus, fariseus, brasileiro,
  /// céu). Um nome que não esteja aqui sai em minúscula — é o erro possível
  /// desta conversão, e por isso ela é opcional e a tela mostra o resultado
  /// antes de gravar.
  static const _nomes = {
    // Deus e Cristo
    'deus', 'jesus', 'cristo', 'jeová', 'emanuel', 'messias', 'senhor', 'pai',
    'rei', 'salvador', 'redentor', 'criador', 'benfeitor', 'consolador',
    'libertador', 'mestre', 'cordeiro', 'pastor', 'advogado', 'mediador',
    'capitão', 'trindade', 'nazareno', 'bíblia', 'sustentador', 'defensor',
    'instruidor', 'santificador', 'sacerdote', 'príncipe', 'autor',
    // Gente e lugares da Bíblia
    'satanás', 'satã', 'sião', 'jerusalém', 'belém', 'calvário', 'gólgota',
    'israel', 'jordão', 'canaã', 'babilônia', 'egito', 'sinai', 'getsêmani',
    'nazaré', 'galileia', 'jericó', 'judá', 'adão', 'eva', 'abraão', 'isaque',
    'jacó', 'josé', 'moisés', 'davi', 'salomão', 'elias', 'daniel', 'samuel',
    'belsazar', 'pilatos', 'lázaro', 'ebenézer',
    // O Brasil, que os hinos cantam
    'brasil', 'tiradentes', 'ipiranga', 'amapá', 'recife', 'cuiabá', 'ceará',
    'pará', 'amazonas', 'minas', 'acre', 'brasília', 'panamá', 'canadá',
    'china', 'japão', 'europa',
  };

  /// Expressões em que cada palavra (menos as miúdas) leva maiúscula: "santo"
  /// sozinho é adjetivo ("santo amor") e continua minúsculo, mas em "Espírito
  /// Santo" não.
  static const _expressoes = [
    ['espírito', 'santo'],
    ['santo', 'espírito'],
    ['todo', 'poderoso'],
    ['deus', 'homem'],
    ['santo', 'de', 'israel'],
    ['são', 'paulo'],
    ['rio', 'grande'],
    ['mato', 'grosso'],
    ['grão', 'pará'],
  ];

  static const _particulas = {'de', 'da', 'do', 'dos', 'das'};

  /// "Filho" é o Filho de Deus ou é gente? Num hinário as duas coisas se
  /// escrevem igual: "o filho do glorioso Deus" e "vem, filho, vem!" (o
  /// pródigo). Só vira maiúscula com um sinal claro — "Deus Filho", "querido
  /// filho", "filho de Deus". Sem sinal fica minúscula: errar para este lado é
  /// o erro mais barato, e a pessoa corrige em Editar música.
  static bool _filhoDeDeus(List<String> p, int i) {
    if (i > 0 && const {'deus', 'querido', 'amado', 'bendito', 'único',
        'unigênito', 'próprio'}.contains(p[i - 1])) {
      return true;
    }
    if (i + 1 < p.length &&
        const {'amado', 'bendito', 'eterno', 'querido', 'unigênito', 'único',
            'divino'}.contains(p[i + 1])) {
      return true;
    }
    // "filho de Deus", "filho do santo Deus": "de/do" e, até duas palavras
    // depois, "Deus".
    if (i + 2 < p.length && (p[i + 1] == 'de' || p[i + 1] == 'do')) {
      return p.skip(i + 2).take(2).contains('deus');
    }
    return false;
  }

  /// "Espírito" é o Espírito Santo em quase todo hino ("o dom do Espírito",
  /// "teu Espírito"). A exceção é a alma de quem canta: "meu espírito".
  static bool _espiritoSanto(List<String> p, int i) =>
      !(i > 0 && const {'meu', 'nosso', 'vosso', 'este', 'esse', 'um'}
          .contains(p[i - 1]));

  static final _rePalavra = RegExp(r'\p{L}+', unicode: true);

  /// Letra gritada em maiúsculas e minúsculas: "VEM, SENHOR JESUS!" →
  /// "Vem, Senhor Jesus!".
  ///
  /// A inicial maiúscula vai no começo de cada estrofe, depois de ponto final,
  /// de exclamação e de interrogação, e nos nomes de [_nomes] e de
  /// [_expressoes]. Vírgula e reticências NÃO abrem frase: a linha de baixo de
  /// "pois hoje tem festa," continua minúscula, como num hino impresso.
  ///
  /// Mexe SÓ no que é gritado: marcadores de estrofe ("[1]", "[côro]") e
  /// linhas que já vieram em maiúsculas e minúsculas ficam exatamente como
  /// estão, e um hino que não é gritado volta igual. Por isso converter duas
  /// vezes dá o mesmo que converter uma.
  static String letraEmMinusculas(String letra) {
    if (!letraGritada(letra)) return letra;
    final saida = <String>[];
    var abreFrase = true;
    var vemFala = false; // a linha de cima terminou em dois-pontos
    for (final bruta in letra.split('\n')) {
      final t = bruta.trim();
      if (t.isEmpty || _reMarcador.hasMatch(t)) {
        saida.add(bruta);
        abreFrase = true; // estrofe nova
        vemFala = false;
        continue;
      }
      // "O Mestre diz:" e, na linha de baixo, a fala entre aspas: a fala
      // começa com maiúscula, como se a frase tivesse fechado.
      final abre = abreFrase || (vemFala && _reAspasDeAbrir.hasMatch(t));
      if (!_quaseTodoMaiusculo(t, minimoDeLetras: 1)) {
        saida.add(bruta);
        abreFrase = _fechaFrase(t);
      } else {
        final convertida = _fraseEmMinusculas(t, abre);
        saida.add(convertida);
        abreFrase = _fechaFrase(convertida);
      }
      vemFala = _terminaEmDoisPontos(t);
    }
    return saida.join('\n');
  }

  static final _reAspasDeAbrir = RegExp(r'^["“‘]');

  /// Qualquer aspas, de abrir ou de fechar: na fonte de verdade o fecha-aspas
  /// vem como “ (`vou.“`), e tratar só o ” deixava a frase seguinte em
  /// minúscula.
  static final _reAspasNoFim = RegExp(r'["“”‘’»«)\s]+$');

  static bool _terminaEmDoisPontos(String linha) =>
      linha.replaceFirst(_reAspasNoFim, '').endsWith(':');

  /// A linha termina uma frase? ("." "!" "?", e não "...")
  static bool _fechaFrase(String linha) {
    final s = linha.replaceFirst(_reAspasNoFim, '');
    if (s.endsWith('..')) return false;
    return s.endsWith('.') || s.endsWith('!') || s.endsWith('?');
  }

  /// Entre duas palavras há o fim de uma frase? Reticências não valem; dois
  /// pontos só valem quando abrem uma fala entre aspas.
  static bool _abreFraseEntre(String intervalo) {
    final sem = intervalo.replaceAll(RegExp(r'\.{2,}'), '');
    return RegExp(r'[.!?]').hasMatch(sem) ||
        RegExp(r':\s*["“‘]').hasMatch(intervalo);
  }

  static String _fraseEmMinusculas(String linha, bool abreFrase) {
    final baixa = linha.toLowerCase();
    final ms = _rePalavra.allMatches(baixa).toList();
    final palavras = [for (final m in ms) m.group(0)!];

    // Palavras de expressão ("Espírito Santo"): só se coladas, com espaço ou
    // hífen no meio — "espírito" e "santo" em lugares diferentes não contam.
    final deExpressao = <int>{};
    for (final ex in _expressoes) {
      for (var i = 0; i + ex.length <= palavras.length; i++) {
        var casa = true;
        for (var j = 0; j < ex.length && casa; j++) {
          if (palavras[i + j] != ex[j]) casa = false;
          if (casa && j > 0) {
            final entre = baixa.substring(ms[i + j - 1].end, ms[i + j].start);
            if (!RegExp(r'^[\s-]+$').hasMatch(entre)) casa = false;
          }
        }
        if (!casa) continue;
        for (var j = 0; j < ex.length; j++) {
          if (!_particulas.contains(ex[j])) deExpressao.add(i + j);
        }
      }
    }

    final sb = StringBuffer();
    var fim = 0;
    var abre = abreFrase;
    for (var i = 0; i < ms.length; i++) {
      final m = ms[i];
      final entre = baixa.substring(fim, m.start);
      sb.write(entre);
      if (i > 0 && _abreFraseEntre(entre)) abre = true;
      final w = palavras[i];
      final maiuscula = abre ||
          _nomes.contains(w) ||
          deExpressao.contains(i) ||
          (w == 'filho' && _filhoDeDeus(palavras, i)) ||
          (w == 'espírito' && _espiritoSanto(palavras, i));
      sb.write(maiuscula ? '${w[0].toUpperCase()}${w.substring(1)}' : w);
      abre = false;
      fim = m.end;
    }
    sb.write(baixa.substring(fim));
    return sb.toString();
  }

  /// Palavras que, no meio do título, ficam em minúscula: "Grande é o Senhor",
  /// e não "Grande É O Senhor".
  static const _miudas = {
    'a', 'as', 'o', 'os', 'e', 'é', 'de', 'da', 'das', 'do', 'dos', 'em',
    'na', 'nas', 'no', 'nos', 'ao', 'aos', 'à', 'às', 'com', 'por', 'para',
    'pra', 'que', 'um', 'uma', 'ou', 'se', 'me', 'te', 'meu', 'minha',
  };

  /// "CHUVAS DE GRAÇA" → "Chuvas de Graça".
  ///
  /// Título todo em maiúsculas, num app que se lê no celular, parece gritar —
  /// e vira texto que o app não consegue ordenar do jeito que a pessoa espera.
  static String emTituloBonito(String s) {
    final palavras = s.toLowerCase().split(' ');
    final saida = <String>[];
    for (var i = 0; i < palavras.length; i++) {
      final p = palavras[i];
      if (p.isEmpty) continue;
      if (i > 0 && _miudas.contains(p)) {
        saida.add(p);
      } else {
        saida.add(_capitalizar(p));
      }
    }
    return saida.join(' ');
  }

  /// Primeira letra maiúscula, também depois de hífen ("Casa-Grande").
  static String _capitalizar(String p) {
    final sb = StringBuffer();
    var inicio = true;
    for (final r in p.runes) {
      final c = String.fromCharCode(r);
      sb.write(inicio ? c.toUpperCase() : c);
      inicio = c == '-';
    }
    return sb.toString();
  }

  /// A letra: sem linha em branco nas pontas e com no máximo UMA linha em
  /// branco entre as estrofes.
  static String _letraLimpa(List<String> linhas) {
    final saida = <String>[];
    var brancas = 0;
    for (final l in linhas) {
      if (l.isEmpty) {
        brancas++;
        continue;
      }
      if (brancas > 0 && saida.isNotEmpty) saida.add('');
      brancas = 0;
      saida.add(l);
    }
    return saida.join('\n');
  }

  // ── Achar onde cada hino começa ───────────────────────────────────────────

  static final _reTraco = RegExp(r'^(\d{1,4})\s*[-–—−:·•]\s*(\S.*)$');
  static final _rePonto = RegExp(r'^(\d{1,4})\s*[.)]\s+(\S.*)$');
  static final _reSozinho = RegExp(r'^(\d{1,4})$');
  // O ponto (ou parêntese) depois do número é OPCIONAL, pode vir COLADO no
  // título (`584.O PILOTO` — na fonte de verdade, e sem isto o hino inteiro
  // entrava na letra do anterior), e o título pode abrir com aspas: `301.
  // "VEM CEAR"` é um cabeçalho de verdade. O que separa o cabeçalho da estrofe
  // numerada ("1. palavras…", "2.Os encantos…") é o título em maiúsculas,
  // conferido em `_quaseTodoMaiusculo`, e não o formato do número.
  static final _reCaixaAlta = RegExp(
    r'^(\d{1,4})(?:\s*[.)]\s*|\s+)([\p{L}"“”‘’' "'" r'(].*)$',
    unicode: true,
  );
  static final _reHino = RegExp(
    r'^(?:hino|n[ºo°]|n[uú]mero|n\.)\.?\s*(\d{1,4})\s*(?:[-–—:.·)]\s*(.*))?$',
    caseSensitive: false,
    unicode: true,
  );

  static List<_Candidato> _candidatos(List<String> linhas, FormatoDoHinario f) {
    final saida = <_Candidato>[];
    for (var i = 0; i < linhas.length; i++) {
      final l = linhas[i];
      if (l.isEmpty) continue;
      switch (f) {
        case FormatoDoHinario.hino:
          final m = _reHino.firstMatch(l);
          if (m == null) continue;
          final inline = (m.group(2) ?? '').trim();
          saida.add(_Candidato(
            linha: i,
            numero: int.parse(m.group(1)!),
            titulo: inline.isEmpty ? null : inline,
            tituloNaProxima: inline.isEmpty,
          ));
        case FormatoDoHinario.traco:
          final m = _reTraco.firstMatch(l);
          if (m != null && _tituloPlausivel(m.group(2)!)) {
            saida.add(_Candidato(
                linha: i, numero: int.parse(m.group(1)!), titulo: m.group(2)));
          }
        case FormatoDoHinario.caixaAlta:
          final m = _reCaixaAlta.firstMatch(l);
          if (m != null &&
              _tituloPlausivel(m.group(2)!) &&
              _quaseTodoMaiusculo(m.group(2)!)) {
            saida.add(_Candidato(
                linha: i, numero: int.parse(m.group(1)!), titulo: m.group(2)));
          }
        case FormatoDoHinario.ponto:
          final m = _rePonto.firstMatch(l);
          if (m != null && _tituloPlausivel(m.group(2)!)) {
            saida.add(_Candidato(
                linha: i, numero: int.parse(m.group(1)!), titulo: m.group(2)));
          }
        case FormatoDoHinario.sozinho:
          final m = _reSozinho.firstMatch(l);
          if (m == null) continue;
          saida.add(_Candidato(
            linha: i,
            numero: int.parse(m.group(1)!),
            tituloNaProxima: true,
          ));
      }
    }
    return saida;
  }

  /// Serve de título? Tem letra e não é comprido como um verso.
  static bool _tituloPlausivel(String s) =>
      s.length <= maximoDoTitulo && _temLetra(s);

  /// Endereço de site: "http://…", "https://…" ou "www.…" em qualquer ponto da
  /// linha (inclusive dentro de um link de Markdown). Verso de hino não tem.
  static final _reEndereco =
      RegExp(r'(?:https?://|www\.)\S', caseSensitive: false);

  /// De que linha em diante o texto é rodapé de site, ou nulo.
  ///
  /// O rodapé começa no primeiro endereço DEPOIS do começo do último hino. Se a
  /// linha logo acima dele repete uma linha de antes do primeiro hino (o nome
  /// do site, que abre e fecha a página), o rodapé começa nela: sem isso o nome
  /// ficaria na letra do último hino, sozinho, sem nada que o explique.
  ///
  /// Só o FIM do texto conta. Um endereço no meio de um hino não corta nada:
  /// cortar do meio até o fim apagaria hinos de verdade.
  static int? _rodapeDesde(List<String> linhas, List<_Candidato> cands) {
    if (cands.isEmpty) return null;
    final ultima = cands.last.linha;
    int? endereco;
    for (var i = ultima + 1; i < linhas.length; i++) {
      if (_reEndereco.hasMatch(linhas[i])) {
        endereco = i;
        break;
      }
    }
    if (endereco == null) return null;

    String chave(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final abertura = {
      for (var i = 0; i < cands.first.linha; i++)
        if (linhas[i].length >= 8) chave(linhas[i]),
    };
    var acima = endereco - 1;
    while (acima > ultima && linhas[acima].isEmpty) {
      acima--;
    }
    if (acima > ultima && abertura.contains(chave(linhas[acima]))) {
      return acima;
    }
    return endereco;
  }

  /// Corta o texto em trechos: cada um vai do começo de um hino ao começo do
  /// seguinte — QUALQUER seguinte do mesmo formato, mesmo de número que o
  /// hinário não tem. Assim um rodapé "2024 - CPAD" encerra o último hino em
  /// vez de ser colado na letra dele.
  static List<_Trecho> _trechos(
    List<String> linhas,
    List<_Candidato> cands,
    Hinario hinario, {
    required int fimDoTexto,
  }) {
    // Os vizinhos de cada candidato, só entre os que têm número de hinário:
    // um rodapé "2024 - EDITORA" corta o último hino, mas não conta como
    // vizinho de ninguém na ordem dos números.
    final antes = List<int?>.filled(cands.length, null);
    final depois = List<int?>.filled(cands.length, null);
    int? ultimo;
    for (var k = 0; k < cands.length; k++) {
      antes[k] = ultimo;
      if (hinario.existe(cands[k].numero)) ultimo = cands[k].numero;
    }
    ultimo = null;
    for (var k = cands.length - 1; k >= 0; k--) {
      depois[k] = ultimo;
      if (hinario.existe(cands[k].numero)) ultimo = cands[k].numero;
    }

    final saida = <_Trecho>[];
    for (var k = 0; k < cands.length; k++) {
      final c = cands[k];
      // O último hino vai até o fim do texto — menos o rodapé do site.
      final fim = k + 1 < cands.length ? cands[k + 1].linha : fimDoTexto;
      var inicio = c.linha + 1;
      var titulo = c.titulo ?? '';

      if (c.tituloNaProxima) {
        // O título é a primeira linha não vazia logo abaixo, se couber como
        // título. Senão o hino fica sem título, e a linha é letra.
        final limite = (c.linha + 4) < fim ? c.linha + 4 : fim;
        for (var j = c.linha + 1; j < limite; j++) {
          if (linhas[j].isEmpty) continue;
          if (_tituloPlausivel(linhas[j])) {
            titulo = linhas[j];
            inicio = j + 1;
          }
          break;
        }
      }

      final corpo = inicio < fim ? linhas.sublist(inicio, fim) : <String>[];
      var tamanho = 0;
      for (final l in corpo) {
        tamanho += l.replaceAll(RegExp(r'\s'), '').length;
      }
      saida.add(_Trecho(
        numero: c.numero,
        titulo: titulo,
        corpo: corpo,
        tamanho: tamanho,
        antes: antes[k],
        depois: depois[k],
      ));
    }
    return saida;
  }

  /// Para cada número do hinário, o trecho que fica. Quando um número aparece
  /// mais de uma vez, vale, nesta ordem:
  ///
  /// 1. **Letra que serve** ([_Trecho.serve]) ganha de letra que não serve.
  ///    É isto que faz o sumário perder para o hino de verdade — a linha do
  ///    sumário "15 - Sou Grato ..... 23" é candidata a hino 15 como qualquer
  ///    outra, mas tem a letra de uma linha só — e também impede que um
  ///    candidato cujo texto vai até o fim do arquivo (12 mil caracteres)
  ///    derrube o hino de verdade, que passaria a "grande demais" e sumiria.
  /// 2. **O que está na ordem certa dos números** ([_Trecho.emOrdem]). Um
  ///    "442" escrito entre o 541 e o 543 é o 542 digitado errado; como costuma
  ///    ter mais letra que o 442 de verdade, sem esta regra ele o substituiria
  ///    em silêncio.
  /// 3. **A letra mais comprida.**
  static Map<int, _Trecho> _melhoresPorNumero(
    List<_Trecho> trechos,
    Hinario hinario,
  ) {
    final m = <int, _Trecho>{};
    for (final t in trechos) {
      if (!hinario.existe(t.numero)) continue;
      final atual = m[t.numero];
      if (atual == null || _ganha(t, atual)) m[t.numero] = t;
    }
    return m;
  }

  /// [a] é melhor que [b] para o mesmo número? Os critérios estão em
  /// [_melhoresPorNumero]. Empate total deixa o primeiro do texto.
  static bool _ganha(_Trecho a, _Trecho b) {
    if (a.serve != b.serve) return a.serve;
    if (a.serve && a.emOrdem != b.emOrdem) return a.emOrdem;
    return a.tamanho > b.tamanho;
  }
}

class _Candidato {
  /// Índice da linha em que o hino começa.
  final int linha;
  final int numero;

  /// O título, quando está na mesma linha do número.
  final String? titulo;

  /// O título é a linha de baixo.
  final bool tituloNaProxima;

  const _Candidato({
    required this.linha,
    required this.numero,
    this.titulo,
    this.tituloNaProxima = false,
  });
}

class _Trecho {
  final int numero;
  final String titulo;
  final List<String> corpo;

  /// Tamanho da letra sem contar espaço, para comparar trechos.
  final int tamanho;

  /// O número do candidato anterior e do seguinte (só dos que o hinário tem).
  /// Nulos nas pontas do texto.
  final int? antes;
  final int? depois;

  const _Trecho({
    required this.numero,
    required this.titulo,
    required this.corpo,
    required this.tamanho,
    this.antes,
    this.depois,
  });

  /// A letra tem tamanho de hino: nem curta demais (sumário), nem grande
  /// demais (o hino seguinte colado).
  bool get serve => tamanho >= minimoDeLetra && tamanho <= maximoDeLetra;

  /// O número deste candidato cabe entre os vizinhos: maior que o anterior e
  /// menor que o seguinte. Quem está nas pontas do texto está em ordem.
  bool get emOrdem =>
      (antes == null || antes! < numero) && (depois == null || depois! > numero);
}
