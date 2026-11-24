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
/// Só entram textos cuja licença permita distribuir offline. NVI, NTLH, ARA,
/// NAA, ARC e companhia pertencem a editoras e não podem estar aqui; para elas
/// existe [traducoesExternas], que abre o mesmo capítulo no YouVersion.
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

/// Uma tradução que NÃO mora no app: abre o capítulo no YouVersion.
///
/// O texto delas é de editoras (Biblica, Sociedade Bíblica do Brasil), e
/// guardá-lo no aparelho ou no banco é copiar a obra — por isso o app só aponta
/// para quem tem o direito de publicá-la. Custa internet, e a tela diz isso.
class TraducaoExterna {
  /// Nome interno, que não depende do número do YouVersion: se o site
  /// renumerar uma versão, só `codigoNoYouVersion` precisa mudar.
  final String id;
  final String sigla;

  /// O nome que a pessoa conhece. "Linguagem de Hoje" é como o ministério
  /// chama a NTLH — a sigla sozinha não diz nada a quem não é da área.
  final String nome;

  /// Quem publica. Aparece na tela: é de quem é o texto.
  final String editora;

  /// O número da versão no endereço `bible.com/pt/bible/<número>/...`.
  final int codigoNoYouVersion;

  const TraducaoExterna({
    required this.id,
    required this.sigla,
    required this.nome,
    required this.editora,
    required this.codigoNoYouVersion,
  });
}

/// A PRIMEIRA é a padrão (a NVI): a tela a põe em destaque, como o botão
/// principal. A ordem é fixa de propósito — lista que muda de lugar faz a
/// pessoa tocar na linha errada.
///
/// Os números foram conferidos no próprio bible.com (24/11/2026): cada um
/// abre João 3 na versão da sigla. NVI 129 é da Biblica; as outras quatro são
/// da Sociedade Bíblica do Brasil. Há versões repetidas com a mesma sigla
/// (NVI 4360, NTLH 4539 "edição católica", ARC 3407 de Portugal) que NÃO são
/// as usadas aqui.
const List<TraducaoExterna> traducoesExternas = [
  TraducaoExterna(
    id: 'nvi',
    sigla: 'NVI',
    nome: 'Nova Versão Internacional',
    editora: 'Biblica',
    codigoNoYouVersion: 129,
  ),
  TraducaoExterna(
    id: 'ntlh',
    sigla: 'NTLH',
    nome: 'Linguagem de Hoje',
    editora: 'Sociedade Bíblica do Brasil',
    codigoNoYouVersion: 211,
  ),
  TraducaoExterna(
    id: 'ara',
    sigla: 'ARA',
    nome: 'Almeida Revista e Atualizada',
    editora: 'Sociedade Bíblica do Brasil',
    codigoNoYouVersion: 1608,
  ),
  TraducaoExterna(
    id: 'arc',
    sigla: 'ARC',
    nome: 'Almeida Revista e Corrigida',
    editora: 'Sociedade Bíblica do Brasil',
    codigoNoYouVersion: 212,
  ),
  TraducaoExterna(
    id: 'naa',
    sigla: 'NAA',
    nome: 'Nova Almeida Atualizada',
    editora: 'Sociedade Bíblica do Brasil',
    codigoNoYouVersion: 1840,
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

  /// O MESMO capítulo, aberto no YouVersion, na tradução escolhida (a NVI,
  /// quando nenhuma é dita).
  ///
  /// É a ponte para as traduções que este app não pode trazer para dentro:
  /// NVI, NTLH, ARA, ARC e NAA são de editoras, e distribuí-las exigiria
  /// licença. Em vez de fingir que não existem, o app leva a pessoa ao capítulo
  /// certo, no site de quem tem o direito de publicá-lo.
  ///
  /// Os códigos de três letras do livro são o padrão USFM. Conferidos no
  /// próprio site: /pt/bible/129/JHN.3 abre João 3 em NVI, e
  /// /pt/bible/129/SNG.2 abre Cântico dos Cânticos 2.
  static Uri noYouVersion(String siglaLivro, int capitulo,
      {TraducaoExterna? em}) {
    final livro = livroPorSigla(siglaLivro);
    if (livro == null || livro.usfm.isEmpty) {
      // Livro que não conhecemos: a busca pelo nome ainda leva a algum lugar
      // útil, em vez de a um endereço inventado que daria página de erro.
      return Uri.https('www.bible.com', '/search/bible',
          {'q': '${nomeDoLivro(siglaLivro)} $capitulo'});
    }
    final versao = (em ?? traducoesExternas.first).codigoNoYouVersion;
    return Uri.https(
        'www.bible.com', '/pt/bible/$versao/${livro.usfm}.$capitulo');
  }
}
