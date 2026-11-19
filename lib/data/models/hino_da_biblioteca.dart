import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/hinarios.dart';
import '../../core/utils/importar_hinario.dart';
import '../../core/utils/texto.dart';
import 'song_model.dart';

/// A letra de UM hino na biblioteca de hinários.
///
/// A biblioteca é o texto que o líder importou, guardado FORA de `songs` por
/// causa da cota de leitura: o app escuta `songs` inteira, e cada aparelho a
/// relê depois de 30 minutos parado — com 1.200 hinos ali dentro, um domingo
/// comum passaria das 50 mil leituras grátis do dia. Aqui o texto só é lido
/// quando alguém abre aquele hino. O hino só vira música (`SongModel`) quando
/// o ministério passa a USÁ-LO: escalar, favoritar, ter cifra e tom.
class HinoDaBiblioteca {
  /// O id do hinário (`harpa`, `cantor`).
  final String hinario;
  final int numero;
  final String titulo;
  final String letra;

  const HinoDaBiblioteca({
    required this.hinario,
    required this.numero,
    required this.titulo,
    required this.letra,
  });

  /// Lê o documento, ou devolve nulo se ele não serve.
  ///
  /// Nulo e não um hino vazio: um documento sem letra, mexido no console ou
  /// gravado pela metade, na tela seria uma página em branco com o título
  /// certo — o jeito mais silencioso de parecer que o hino não tem letra.
  /// Tratando como "não está na biblioteca", a tela diz o que fazer.
  static HinoDaBiblioteca? fromFirestore(
    String hinario,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final numero = data['numero'];
    final titulo = data['titulo'];
    final letra = data['letra'];
    if (numero is! num || titulo is! String || letra is! String) return null;
    if (titulo.trim().isEmpty || letra.trim().isEmpty) return null;
    return HinoDaBiblioteca(
      hinario: hinario,
      numero: numero.toInt(),
      titulo: titulo,
      letra: letra,
    );
  }

  /// O documento de um hino lido, como vai para o banco.
  ///
  /// Os campos são EXATAMENTE os que a regra `_hinoDaBibliotecaValido` aceita
  /// (`hasOnly`): um campo a mais e o banco recusa a importação inteira, com
  /// erro de permissão — depois de o líder colar o hinário e conferir a
  /// prévia. Um teste lê o `firestore.rules` e compara as duas listas.
  static Map<String, dynamic> paraFirestore(HinoLido h, String porQuemId) => {
        'numero': h.numero,
        'titulo': h.titulo,
        'letra': h.letra,
        'importadoPor': porQuemId,
        // A hora é do SERVIDOR, e a regra exige: com a do aparelho, um
        // relógio errado carimbaria o hino com a data errada.
        'importadoEm': FieldValue.serverTimestamp(),
      };

  /// O título como aparece no repertório: `HC 15 · Sou Grato`.
  String tituloNoRepertorio(Hinario h) => h.tituloDe(numero, titulo);

  /// Este hino como música do repertório.
  ///
  /// Mora aqui, e não na tela, porque é a regra que decide o que um hino
  /// "usado" carrega: o título com a sigla (que é o que o faz se reconhecer na
  /// escala e no chat), o nome do hinário como artista, e os DOIS campos
  /// `hinario` e `numero` — que é por onde o teclado o acha depois.
  ///
  /// O tom vem como `C` porque o texto do hinário não traz tom. É o mesmo
  /// padrão do cadastro à mão, e o líder muda quando colar a cifra.
  SongModel comoMusica(
    Hinario h, {
    required String id,
    required String? addedBy,
    required DateTime criadaEm,
  }) {
    return SongModel(
      id: id,
      name: tituloNoRepertorio(h),
      artist: h.nome,
      lyrics: letra,
      originalKey: 'C',
      createdAt: criadaEm,
      addedBy: addedBy,
      hinario: h.id,
      numero: numero,
    );
  }
}

/// Os títulos de um hinário na biblioteca: o que a tela mostra de uma vez.
///
/// É UM documento por hinário, e custa UMA leitura — enquanto as letras são
/// 640 documentos, lidos um por vez. É o índice que diz "o hino 15 existe na
/// biblioteca" sem gastar a leitura da letra.
class IndiceDoHinario {
  final String hinario;
  final Map<int, String> titulos;

  const IndiceDoHinario({required this.hinario, this.titulos = const {}});

  /// Hinário que ninguém importou ainda.
  const IndiceDoHinario.vazio(this.hinario) : titulos = const {};

  bool get vazio => titulos.isEmpty;
  int get total => titulos.length;

  bool tem(int numero) => titulos.containsKey(numero);
  String? tituloDe(int numero) => titulos[numero];

  /// Os números, em ordem.
  List<int> get numeros => titulos.keys.toList()..sort();

  /// Os números cujo título (ou o próprio número) combina com [busca].
  ///
  /// Ignora acento e maiúscula, como a busca do repertório: quem procura
  /// "gloria" quer achar "Glória". Em ordem de número, para a lista não
  /// dançar a cada letra digitada.
  ///
  /// Busca VAZIA devolve nada, e é de propósito: o índice tem até 640 hinos, e
  /// despejar 640 linhas sem ninguém ter pedido é parede. A tela só mostra a
  /// biblioteca quando a pessoa procura — e diz quantos hinos há, numa frase.
  ///
  /// [excluir] tira os que já estão no repertório, que a tela mostra à parte:
  /// o mesmo hino em duas linhas faria a pessoa achar que há dois.
  List<int> buscar(String busca, {Set<int> excluir = const {}}) {
    if (busca.trim().isEmpty) return const [];
    final saida = <int>[];
    for (final n in numeros) {
      if (excluir.contains(n)) continue;
      if (combina(busca, ['$n', titulos[n]!])) saida.add(n);
    }
    return saida;
  }

  /// Lê o documento do índice.
  ///
  /// Tolerante de propósito: chave que não é número e valor que não é texto
  /// são descartados, em vez de derrubar a tela. Um documento mexido no
  /// console tem de significar MENOS hinos na biblioteca, nunca um app que
  /// não abre.
  factory IndiceDoHinario.fromFirestore(
    String hinario,
    Map<String, dynamic>? data,
  ) {
    final bruto = data?['titulos'];
    if (bruto is! Map) return IndiceDoHinario.vazio(hinario);
    final saida = <int, String>{};
    bruto.forEach((k, v) {
      final n = int.tryParse(k.toString());
      if (n != null && n >= 1 && v is String && v.trim().isNotEmpty) {
        saida[n] = v;
      }
    });
    return IndiceDoHinario(hinario: hinario, titulos: saida);
  }

  /// Este índice com os [hinos] por cima.
  ///
  /// Hino que já estava tem o título trocado — é assim que re-importar
  /// corrige um título errado — e os que não estão no texto novo ficam. É
  /// isso que permite colar o hinário em partes: a segunda parte não apaga a
  /// primeira.
  IndiceDoHinario comHinos(Iterable<HinoLido> hinos) {
    final saida = Map<int, String>.of(titulos);
    for (final h in hinos) {
      saida[h.numero] = h.titulo;
    }
    return IndiceDoHinario(hinario: hinario, titulos: saida);
  }

  /// Como vai para o banco: chaves em texto, porque mapa do Firestore só tem
  /// chave de texto.
  Map<String, String> paraFirestore() =>
      {for (final e in titulos.entries) '${e.key}': e.value};

  /// O documento do índice, como vai para o banco.
  ///
  /// Mesmo contrato do hino: os campos são os que `_indiceValido` aceita, e o
  /// `total` TEM de ser o tamanho da lista — a regra confere, porque um
  /// número que mente apareceria na tela como "640 hinos" sobre um índice de
  /// 300.
  Map<String, dynamic> paraDocumento(String porQuemId) => {
        'titulos': paraFirestore(),
        'total': total,
        'atualizadoEm': FieldValue.serverTimestamp(),
        'atualizadoPor': porQuemId,
      };
}

/// A lista em pedaços de no máximo [tamanho].
///
/// A importação grava em lotes, e o Firestore recusa lote com mais de 500
/// escritas. Mora aqui como função pura porque errar a borda — 400 certos
/// virando dois lotes de 399 e 1, ou um hino perdido no resto — não dá erro
/// nenhum: o hinário apareceria faltando um número, sem ninguém saber por quê.
List<List<T>> emPedacos<T>(List<T> lista, int tamanho) {
  assert(tamanho > 0);
  final saida = <List<T>>[];
  for (var i = 0; i < lista.length; i += tamanho) {
    final fim = i + tamanho < lista.length ? i + tamanho : lista.length;
    saida.add(lista.sublist(i, fim));
  }
  return saida;
}
