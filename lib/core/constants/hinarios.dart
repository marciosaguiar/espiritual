/// Os hinários que o app abre pelo número.
///
/// POR QUE É UMA LISTA, E NÃO UM CAMPO `numeroHarpa`
///
/// Na igreja o dirigente anuncia "hino 15 da Harpa" ou "125 do Cantor", sem
/// aviso, e quem vai tocar precisa chegar ao hino certo em segundos. Um campo
/// com o nome de um hinário resolveria o primeiro caso e deixaria o segundo
/// de fora — e acrescentar um hinário depois obrigaria a mexer no modelo, nas
/// regras do banco e na tela. Com `hinario` + `numero`, um hinário novo é uma
/// linha aqui embaixo.
///
/// O QUE ESTE ARQUIVO NÃO FAZ
///
/// Ele não guarda o TEXTO de hino nenhum, e isso é decisão, não falta de
/// tempo: a Harpa Cristã é obra editada, revisada e ampliada pela CPAD, e
/// 246 dos 640 hinos têm tradução de Paulo Leivas Macalão, morto em 1982 —
/// protegida até 2053. O Cantor Cristão está em situação melhor (os dois
/// maiores tradutores, Ginsburg e Entzminger, morreram em 1927 e 1930), mas
/// não há fonte licenciada do texto na numeração de hoje. Então o app sabe
/// NUMERAR e ACHAR hinos; o texto de cada um entra pelo cadastro do
/// ministério, do hinário que a igreja comprou.
library;

/// Um hinário impresso, do jeito que a igreja o chama.
class Hinario {
  /// O que vai gravado no banco. **Nunca mude um destes**: é o valor que está
  /// nas músicas já cadastradas, e trocá-lo faria o app perder os hinos que a
  /// igreja levou meses cadastrando.
  final String id;

  /// Como aparece na tela: "Harpa Cristã".
  final String nome;

  /// A sigla que entra no título da música: "HC 15 · Sou Grato".
  final String sigla;

  /// O último número que existe no hinário impresso.
  ///
  /// Serve a uma coisa só: dizer "não existe o hino 700". Por isso, na dúvida,
  /// vale o número MAIOR — ver [existe].
  final int ultimo;

  const Hinario({
    required this.id,
    required this.nome,
    required this.sigla,
    required this.ultimo,
  });

  /// O título que a música ganha no repertório: `HC 15 · Sou Grato`.
  ///
  /// A sigla fica gravada no nome de propósito: assim o hino se reconhece em
  /// toda tela que já mostra o nome da música — a escala, o chat, o lembrete
  /// da véspera — sem que nenhuma delas precise saber o que é um hinário.
  /// Quem ACHA o hino pelo número usa os campos `hinario` e `numero`, nunca o
  /// texto do título: título é para gente ler, campo é para máquina procurar.
  String tituloDe(int numero, String nomeDoHino) =>
      '$sigla $numero · ${nomeDoHino.trim()}';

  /// Este número existe no hinário impresso?
  ///
  /// O teto é generoso de propósito. A Harpa "Revisada e Ampliada" tem 640
  /// hinos, mas há edição de que saíram os quatro hinos pátrios, ficando 636 —
  /// e eu não tenho o livro na mão para decidir. Errar para MAIS é inofensivo:
  /// um número entre 637 e 640 que a igreja não tenha cai em "ainda não está
  /// no repertório", que é verdade. Errar para MENOS diria "não existe" sobre
  /// um hino que existe, e aí o app estaria mentindo no meio do culto.
  bool existe(int numero) => numero >= 1 && numero <= ultimo;

  /// Ainda pode vir mais dígito depois do que já foi digitado?
  ///
  /// É isto que permite abrir o hino SEM confirmar. Digitado "65" na Harpa,
  /// nenhum número de três dígitos começado em 65 existe (650 > 640): não há
  /// o que esperar, e o app abre na hora. Digitado "15", ainda pode virar
  /// 150, então o app espera um instante — curto — antes de abrir.
  bool podeCrescer(String digitado) {
    final n = int.tryParse(digitado);
    if (n == null || n == 0) return true;
    return n * 10 <= ultimo;
  }
}

/// A Harpa Cristã, hinário das Assembleias de Deus.
const harpaCrista = Hinario(
  id: 'harpa',
  nome: 'Harpa Cristã',
  sigla: 'HC',
  ultimo: 640,
);

/// O Cantor Cristão, hinário das igrejas batistas do Brasil.
const cantorCristao = Hinario(
  id: 'cantor',
  nome: 'Cantor Cristão',
  sigla: 'CC',
  ultimo: 581,
);

/// Os hinários que existem, na ordem em que foram acrescentados ao app.
///
/// Esta NÃO é a ordem da tela: quem decide isso é cada pessoa, arrastando os
/// cartões (ver [hinariosNaOrdem]). Aqui é só a lista de quem existe, e a
/// ordem de fábrica para quem nunca arrastou nada.
const hinariosDisponiveis = <Hinario>[harpaCrista, cantorCristao];

/// Os hinários na ordem escolhida pela pessoa.
///
/// POR QUE ISTO É UMA FUNÇÃO PURA, E NÃO A LISTA GRAVADA
///
/// O que fica no aparelho é só uma lista de ids, e ela envelhece de dois
/// jeitos — os dois silenciosos, que é o que torna isto perigoso:
///
/// 1. **Um hinário novo entra no app.** Ele não está na lista gravada, e se
///    esta função devolvesse apenas o que está gravado, o hinário novo
///    simplesmente NÃO APARECERIA para quem já tinha arrastado os cartões
///    uma vez. Ninguém ligaria uma coisa à outra. Por isso o que não está na
///    lista entra no fim, na ordem de fábrica.
/// 2. **Um id gravado não existe mais** (escrito errado, hinário retirado).
///    Ele é descartado, em vez de virar um cartão que não abre nada.
///
/// O primeiro da lista é o que a tela abre por padrão — é isso que faz
/// arrastar "Cantor Cristão" para cima valer como "eu uso o Cantor".
List<Hinario> hinariosNaOrdem(List<String> salva) {
  final saida = <Hinario>[];
  for (final id in salva) {
    final h = hinarioPorId(id);
    if (h != null && !saida.any((x) => x.id == h.id)) saida.add(h);
  }
  for (final h in hinariosDisponiveis) {
    if (!saida.any((x) => x.id == h.id)) saida.add(h);
  }
  return saida;
}

/// A lista com [id] movido [passos] para cima (negativo) ou para baixo.
///
/// Existe para o menu "Mover para cima/baixo", que é o caminho de quem não
/// consegue arrastar — e arrastar é um gesto que exige firmeza na mão. A
/// conta é pura porque errar aqui embaralha a lista de alguém sem erro
/// nenhum na tela; o índice é preso nas bordas, então "subir" no primeiro
/// devolve a mesma lista em vez de dar a volta.
List<String> movido(List<String> ordem, String id, int passos) {
  final i = ordem.indexOf(id);
  if (i < 0) return List<String>.from(ordem);
  var destino = i + passos;
  if (destino < 0) destino = 0;
  if (destino > ordem.length - 1) destino = ordem.length - 1;
  if (destino == i) return List<String>.from(ordem);
  final saida = List<String>.from(ordem);
  saida.removeAt(i);
  saida.insert(destino, id);
  return saida;
}

/// Em que ordem a lista de hinos de um hinário aparece.
///
/// É a mesma escolha para TODOS os hinários, de propósito: quem gosta de ver
/// por nome gosta disso na Harpa e no Cantor, e uma escolha por hinário seria
/// a pessoa descobrir, no meio do culto, que a lista está diferente da que
/// ela acabou de ver.
enum OrdemDosHinos {
  numero('numero', 'Pelo número'),
  nome('nome', 'Pelo nome (A–Z)'),
  maisTocados('tocados', 'Mais tocados no ministério'),
  favoritos('favoritos', 'Meus favoritos primeiro');

  /// O que vai gravado no aparelho. Curto e estável: trocar um destes faria a
  /// escolha de todo mundo voltar para "pelo número" sem aviso.
  final String id;

  /// Como a linha do menu se lê.
  final String rotulo;

  const OrdemDosHinos(this.id, this.rotulo);
}

/// A ordem com este id, ou "pelo número".
///
/// Valor desconhecido cai no PADRÃO, nunca lança: a chave vem do aparelho e
/// pode ter sobrado de uma versão futura do app, ou ter sido mexida à mão.
OrdemDosHinos ordemPorId(String? id) {
  for (final o in OrdemDosHinos.values) {
    if (o.id == id) return o;
  }
  return OrdemDosHinos.numero;
}

/// O hinário com este id, ou nulo.
///
/// Devolve nulo para id desconhecido em vez de chutar o primeiro da lista: um
/// documento com `hinario` escrito errado no console tem de aparecer como
/// música comum, não como hino do hinário errado.
Hinario? hinarioPorId(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final h in hinariosDisponiveis) {
    if (h.id == id) return h;
  }
  return null;
}
