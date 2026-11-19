/// O que fazer com o que outro app compartilhou com o LevitaSync.
///
/// POR QUE ISTO NÃO É ÓBVIO
///
/// No Android, "compartilhar" manda coisas diferentes conforme de onde a
/// pessoa veio. Do botão de compartilhar de um site chega só o ENDEREÇO da
/// página. De "selecionar tudo → compartilhar" chega o TEXTO inteiro, que é
/// a cifra. Os dois casos são úteis, de jeitos diferentes:
///
/// - com a cifra, o cadastro abre com ela colada e o tom já lido;
/// - com o endereço, o cadastro abre com o link guardado na música, para
///   quem for tocar abrir a cifra depois.
///
/// O app NÃO BAIXA a página do endereço. Primeiro porque o dono pediu
/// explicitamente que nada fosse buscado automaticamente; segundo porque
/// copiar a cifra de um site para dentro do app é exatamente o que a licença
/// dele não permite. O endereço entra como link, que é o que o app já faz
/// com o Cifra Club e o YouTube.
library;

import 'cifra_colada.dart';

/// O que preencher no cadastro a partir de um compartilhamento.
class VeioCompartilhado {
  /// O texto da cifra, quando o que chegou é uma cifra. Nulo caso contrário.
  final String? cifra;

  /// O nome da música, já limpo do que o site pendura no título.
  final String titulo;

  /// O endereço da página, quando chegou um.
  final String link;

  const VeioCompartilhado({
    this.cifra,
    this.titulo = '',
    this.link = '',
  });

  /// Veio algo aproveitável?
  bool get temAlgo =>
      (cifra != null && cifra!.trim().isNotEmpty) ||
      titulo.isNotEmpty ||
      link.isNotEmpty;
}

/// Decide o que fazer com o compartilhamento. Função pura.
VeioCompartilhado comoUsarCompartilhado({
  String titulo = '',
  String texto = '',
  String endereco = '',
}) {
  final limpo = texto.trim();

  // O endereço pode vir no campo próprio ou dentro do texto: o Android não
  // garante qual, e sites diferentes mandam de jeitos diferentes.
  var link = endereco.trim();
  if (link.isEmpty && _ehSoEndereco(limpo)) link = limpo;

  // É cifra? Basta a análise que o app já usa no campo "Colar cifra" — não
  // uma segunda heurística escrita só para este caminho, que é o jeito de as
  // duas discordarem um dia.
  String? cifra;
  if (limpo.isNotEmpty && !_ehSoEndereco(limpo)) {
    final r = CifraColada.analisar(limpo);
    if (r.temAcordes || r.letra.trim().length >= 40) cifra = limpo;
  }

  return VeioCompartilhado(
    cifra: cifra,
    titulo: tituloLimpo(titulo),
    link: link,
  );
}

/// O título sem o rabicho que os sites penduram nele.
///
/// O Cifra Club compartilha "Sou Grato - Joshua Coleman | Cifra Club", e
/// deixar isso virar o nome da música encheria o repertório de nomes com o
/// nome do site dentro.
String tituloLimpo(String bruto) {
  var t = bruto.trim();
  if (t.isEmpty) return '';
  final barra = t.indexOf('|');
  if (barra > 0) t = t.substring(0, barra).trim();
  // "Nome - Artista": fica só o nome. O artista a pessoa confirma na tela,
  // porque " - " também aparece em nome de música de verdade.
  final traco = t.indexOf(' - ');
  if (traco > 0) t = t.substring(0, traco).trim();
  return t;
}

/// O texto é só um endereço, e nada mais?
bool _ehSoEndereco(String t) {
  if (t.contains('\n')) return false;
  if (!t.startsWith('http://') && !t.startsWith('https://')) return false;
  return !t.trim().contains(' ');
}
