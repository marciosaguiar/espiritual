/// A lista de TODOS os hinos de um hinário, em ordem, e a busca nela.
///
/// POR QUE ISTO É UM ARQUIVO À PARTE, E PURO
///
/// A tela de hinários mostrava dois pedaços: os hinos do repertório (com
/// busca e ordem) e, só quando a pessoa digitava, até 30 títulos da
/// biblioteca. Para "ver todos os hinos" é preciso uma lista só, com os dois
/// juntos, e quem junta, filtra e ordena é a parte que erra em silêncio — uma
/// lista fora de ordem ou uma busca que não acha o hino que está lá não dá
/// erro nenhum, a pessoa apenas não encontra o hino com a igreja esperando.
/// Por isso nada aqui lê provider, relógio ou banco: recebe tudo de fora e
/// tem teste.
library;

import '../../data/models/hino_da_biblioteca.dart';
import '../../data/models/song_model.dart';
import '../constants/hinarios.dart';
import 'texto.dart';

/// Um hino na lista: o que a linha mostra e o que a busca lê.
class ItemDeHino {
  final int numero;

  /// O nome, SEM o "HC 15 · " que o app grava no título da música.
  final String titulo;

  /// A música do repertório, quando o hino já foi posto nele. Nula para o hino
  /// que só está na biblioteca — que abre para ler, sem tom nem cifra.
  final SongModel? musica;

  /// A letra, para a busca por trecho, quando o app a tem em memória: a do
  /// repertório, ou a que o aparelho baixou. Nula não quer dizer "sem letra":
  /// quer dizer que a busca não a enxerga.
  final String? letra;

  ItemDeHino({
    required this.numero,
    required this.titulo,
    this.musica,
    this.letra,
  });

  bool get noRepertorio => musica != null;

  /// Tudo o que a busca lê, já sem acento e em minúsculas. Calculado uma vez:
  /// com 640 hinos, tirar o acento de 640 letras a cada tecla digitada
  /// pesaria num celular velho.
  late final String palheiro =
      semAcento('$numero $titulo ${musica?.artist ?? ''} ${letra ?? ''}');

  /// O nome pronto para ordenar (sem acento, sem pontuação). Calculado uma
  /// vez, e não a cada comparação do `sort`.
  late final String nomeParaOrdenar = nomeComparavel(titulo);
}

/// Os hinos do hinário [hinario]: os do repertório mais os que só estão na
/// biblioteca, em ordem de número.
///
/// Hino que está nos dois aparece UMA vez, como o do repertório (é o que abre
/// com tom e cifra). [letras] são as letras que o aparelho já baixou; a letra
/// do repertório vale mais, porque pode ter sido corrigida pelo líder.
List<ItemDeHino> itensDoHinario({
  required String hinario,
  required List<SongModel> repertorio,
  required IndiceDoHinario indice,
  Map<int, String> letras = const {},
}) {
  final porNumero = <int, ItemDeHino>{};

  for (final n in indice.titulos.keys) {
    porNumero[n] = ItemDeHino(
      numero: n,
      titulo: indice.titulos[n]!,
      letra: letras[n],
    );
  }
  for (final m in repertorio) {
    final n = m.numero;
    if (m.hinario != hinario || n == null) continue;
    porNumero[n] = ItemDeHino(
      numero: n,
      titulo: nomeSemHinario(m.name),
      musica: m,
      letra: m.lyrics.trim().isNotEmpty ? m.lyrics : letras[n],
    );
  }

  final saida = porNumero.values.toList()
    ..sort((a, b) => a.numero.compareTo(b.numero));
  return saida;
}

final _soDigitos = RegExp(r'^\d+$');

List<String> _palavrasDa(String busca) => semAcento(busca)
    .split(RegExp(r'\s+'))
    .where((p) => p.isNotEmpty)
    .toList();

/// Os itens que combinam com a busca.
///
/// - **Só dígitos procuram pelo NÚMERO**, e só por ele: "1" apareceria como
///   número de estrofe em quase toda letra, e a lista inteira viraria
///   resultado. Digitar "15" mostra o 15 e os que começam com 15 (150, 151…).
/// - **Texto procura em tudo** — número, nome, artista e letra —, ignorando
///   acento e maiúscula, e **cada palavra tem de aparecer, em qualquer
///   ordem**. É como a pessoa lembra o hino: "firme promessas", mesmo que a
///   letra diga "Firmes nas promessas".
List<ItemDeHino> filtrarItens(List<ItemDeHino> itens, String busca) {
  final limpa = busca.trim();
  if (limpa.isEmpty) return itens;
  if (_soDigitos.hasMatch(limpa)) {
    return itens.where((i) => '${i.numero}'.startsWith(limpa)).toList();
  }
  final palavras = _palavrasDa(limpa);
  return itens
      .where((i) => palavras.every((p) => i.palheiro.contains(p)))
      .toList();
}

/// A linha de letra em que a busca apareceu, para mostrar embaixo do título.
///
/// É o que faz "firme nas promessas" ser reconhecido: a pessoa vê o verso que
/// lembrava, e não só um título que não diz nada. Vale a linha em que estão
/// TODAS as palavras; se estão espalhadas, a linha da primeira. Devolve a
/// linha como está escrita, sem o número da estrofe, e cortada com reticências
/// se for comprida.
String? trechoDaBusca(String? letra, String busca, {int maximo = 70}) {
  if (letra == null || letra.trim().isEmpty) return null;
  final limpa = busca.trim();
  if (limpa.isEmpty || _soDigitos.hasMatch(limpa)) return null;
  final palavras = _palavrasDa(limpa);
  if (palavras.isEmpty) return null;

  final linhas = letra.split('\n');
  String? primeira;
  for (final linha in linhas) {
    final sem = semAcento(linha);
    if (sem.trim().isEmpty) continue;
    if (palavras.every(sem.contains)) return _aparar(linha, maximo);
    primeira ??= sem.contains(palavras.first) ? linha : null;
  }
  return primeira == null ? null : _aparar(primeira, maximo);
}

final _numeroDeEstrofe = RegExp(r'^\s*\d{1,2}[.)]?\s+');

String _aparar(String linha, int maximo) {
  var t = linha.replaceFirst(_numeroDeEstrofe, '').trim();
  if (t.length > maximo) t = '${t.substring(0, maximo - 1).trimRight()}…';
  return t;
}

/// Os mesmos itens, na ordem pedida. Não mexe na lista de entrada.
///
/// **O número é sempre o desempate**, e pelo mesmo motivo das outras listas
/// do app: em "mais tocados" o caso comum é zero em quase todos, e sem
/// desempate a lista dançaria a cada abertura, fazendo a pessoa tocar na
/// linha errada.
///
/// - **Mais tocados** vale só para quem está no repertório; hino que só está
///   na biblioteca conta zero, que é a verdade.
/// - **Nome** ordena pelo NOME, sem acento e sem maiúscula: "Ó vem" cai no O,
///   e não depois do Z, onde o código do "Ó" o jogaria.
List<ItemDeHino> ordenarItens(
  List<ItemDeHino> itens,
  OrdemDosHinos ordem, {
  Map<String, int> vezesTocadas = const {},
  Set<String> favoritas = const {},
}) {
  final saida = List<ItemDeHino>.from(itens);
  int porNumero(ItemDeHino a, ItemDeHino b) => a.numero.compareTo(b.numero);
  String nome(ItemDeHino i) => i.nomeParaOrdenar;
  int vezes(ItemDeHino i) =>
      i.musica == null ? 0 : (vezesTocadas[i.musica!.id] ?? 0);
  bool fav(ItemDeHino i) => i.musica != null && favoritas.contains(i.musica!.id);

  switch (ordem) {
    case OrdemDosHinos.numero:
      saida.sort(porNumero);
    case OrdemDosHinos.nome:
      saida.sort((a, b) {
        final c = nome(a).compareTo(nome(b));
        return c != 0 ? c : porNumero(a, b);
      });
    case OrdemDosHinos.nomeDescendente:
      saida.sort((a, b) {
        final c = nome(b).compareTo(nome(a));
        return c != 0 ? c : porNumero(a, b);
      });
    case OrdemDosHinos.maisTocados:
      saida.sort((a, b) {
        final c = vezes(b).compareTo(vezes(a));
        return c != 0 ? c : porNumero(a, b);
      });
    case OrdemDosHinos.favoritos:
      saida.sort((a, b) {
        final fa = fav(a) ? 0 : 1;
        final fb = fav(b) ? 0 : 1;
        return fa != fb ? fa.compareTo(fb) : porNumero(a, b);
      });
  }
  return saida;
}
