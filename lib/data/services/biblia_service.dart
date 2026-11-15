import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../core/constants/livros_biblia.dart';

/// Uma tradução inteira, já lida do arquivo.
class Traducao {
  final String id;
  final String sigla;
  final String nome;

  /// O crédito que a licença exige. Vem dentro do arquivo de propósito: se um
  /// dia alguém copiar o texto para outro lugar, o crédito vai junto.
  final String credito;
  final String licenca;
  final String licencaUrl;

  /// Versículos por capítulo, por sigla de livro: `capitulos['jo']![2][15]`.
  final Map<String, List<List<String>>> capitulos;

  const Traducao({
    required this.id,
    required this.sigla,
    required this.nome,
    required this.credito,
    required this.licenca,
    required this.licencaUrl,
    required this.capitulos,
  });

  bool temLivro(String sigla) => capitulos.containsKey(sigla);

  int quantosCapitulos(String siglaLivro) =>
      capitulos[siglaLivro]?.length ?? 0;

  List<String> versiculos(String siglaLivro, int capitulo) {
    final livro = capitulos[siglaLivro];
    if (livro == null || capitulo < 1 || capitulo > livro.length) {
      return const [];
    }
    return livro[capitulo - 1];
  }

  /// Os livros desta tradução, na ordem canônica.
  List<LivroBiblia> get livros =>
      livrosDaBiblia.where((l) => temLivro(l.sigla)).toList();
}

/// O que o app oferece para ler. Acrescentar uma tradução é acrescentar uma
/// linha aqui e um arquivo em `assets/biblia` — nada de código novo.
///
/// Só entram textos cuja licença permita distribuir offline. NVI, ARA, NAA,
/// ARC e companhia pertencem a editoras e não podem estar aqui; para elas
/// existe o botão "Abrir no YouVersion".
class TraducaoDisponivel {
  final String id;
  final String sigla;
  final String nome;
  final String licencaCurta;

  /// Quanto a pessoa baixa ao abrir esta tradução pela primeira vez, já
  /// comprimido pelo servidor. Aparece na tela antes de ela decidir.
  final String tamanho;

  const TraducaoDisponivel({
    required this.id,
    required this.sigla,
    required this.nome,
    required this.licencaCurta,
    required this.tamanho,
  });
}

const List<TraducaoDisponivel> traducoesDisponiveis = [
  TraducaoDisponivel(
    id: 'blivre',
    sigla: 'BLIVRE',
    nome: 'Bíblia Livre',
    licencaCurta: 'Creative Commons Atribuição 3.0 Brasil',
    tamanho: '1,2 MB',
  ),
  TraducaoDisponivel(
    id: 'alm1911',
    sigla: 'ALM1911',
    nome: 'Almeida 1911',
    licencaCurta: 'Domínio público',
    tamanho: '1,2 MB',
  ),
];

/// Lê os textos bíblicos do arquivo e os guarda na memória.
///
/// O arquivo é um ativo do Flutter: na web ele só sai pela rede quando este
/// código o pede, então a Bíblia não pesa na abertura do app. Depois de
/// baixado uma vez, quem o guarda no aparelho é o nosso service worker
/// (`web/sw.js`), que trata qualquer arquivo do próprio site — por isso não
/// há download a programar aqui.
class BibliaService {
  BibliaService._();

  static final Map<String, Traducao> _naMemoria = {};

  /// Já foi lida nesta sessão? Serve para a tela saber se vai haver espera.
  static bool jaCarregada(String id) => _naMemoria.containsKey(id);

  static Future<Traducao> carregar(String id) async {
    final pronta = _naMemoria[id];
    if (pronta != null) return pronta;

    final texto = await rootBundle.loadString('assets/biblia/$id.json');
    final dados = jsonDecode(texto) as Map<String, dynamic>;

    final capitulos = <String, List<List<String>>>{};
    for (final livro in (dados['livros'] as List)) {
      final mapa = livro as Map<String, dynamic>;
      capitulos[mapa['s'] as String] = [
        for (final cap in (mapa['c'] as List))
          [for (final v in (cap as List)) '$v'],
      ];
    }

    final traducao = Traducao(
      id: id,
      sigla: dados['sigla'] as String? ?? id.toUpperCase(),
      nome: dados['nome'] as String? ?? id,
      credito: dados['credito'] as String? ?? '',
      licenca: dados['licenca'] as String? ?? '',
      licencaUrl: dados['licencaUrl'] as String? ?? '',
      capitulos: capitulos,
    );
    _naMemoria[id] = traducao;
    return traducao;
  }

  /// Endereço da busca do YouVersion com a referência já digitada.
  ///
  /// Só abre a página do site no navegador: o app não lê nada de lá, e é
  /// assim que quem prefere NVI ou ARA chega ao texto sem este projeto
  /// distribuir um texto que não pode.
  static Uri noYouVersion(String siglaLivro, int capitulo) {
    final referencia = '${nomeDoLivro(siglaLivro)} $capitulo';
    return Uri.https('www.bible.com', '/search/bible', {'q': referencia});
  }
}
