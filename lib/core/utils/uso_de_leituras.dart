/// A conta das leituras do Firestore que o app provoca — e a rede de proteção
/// que depende dela.
///
/// O plano grátis dá 50 mil leituras por dia para o ministério inteiro. Um
/// domingo movimentado é onde isso aperta, e é por isso que o app MEDE o que
/// gasta, mostra ao líder quando passa de 60% e se segura sozinho em 80%.
///
/// **É uma ESTIMATIVA, e isto está dito em toda tela que a mostra.** O app não
/// vê a fatura: vê os documentos que chegam. A fatura de verdade está no painel
/// de uso do Firebase, e a página "como conferir" do CLAUDE.md diz como
/// compará-las. Por isso o contador guarda DUAS contas, uma com a regra dos 30
/// minutos e outra sem ela: a que ficar mais perto do painel diz se a regra vale.
library;

/// O limite grátis de leituras por dia.
const int limiteGratisDeLeituras = 50000;

/// Quanto tempo uma escuta pode ficar desligada e voltar cobrando só o que
/// mudou. Passado isto, o Firebase a trata como consulta NOVA.
const Duration prazoDaEscuta = Duration(minutes: 30);

/// O custo de uma notificação do servidor, nas duas contas.
///
/// - **comRegra**: a regra dos 30 minutos vale. A primeira notificação de uma
///   escuta que (re)começa depois de MAIS de 30 minutos custa o resultado
///   inteiro; dentro do prazo, só o que mudou.
/// - **semRegra**: a pior hipótese. Toda (re)ligação custa o resultado inteiro.
///
/// Notificação que não é a primeira custa só o que mudou, nas duas.
/// Consulta nenhuma custa menos de 1 leitura, mesmo vazia.
({int comRegra, int semRegra}) custoDaNotificacao({
  required bool recomeco,
  required DateTime? ultimaSincronia,
  required DateTime agora,
  required int totalDeDocumentos,
  required int mudancas,
}) {
  int minimo1(int n) => n < 1 ? 1 : n;
  if (!recomeco) {
    return (comRegra: mudancas, semRegra: mudancas);
  }
  final dentroDoPrazo =
      ultimaSincronia != null && agora.difference(ultimaSincronia) <= prazoDaEscuta;
  return (
    comRegra: minimo1(dentroDoPrazo ? mudancas : totalDeDocumentos),
    semRegra: minimo1(totalDeDocumentos),
  );
}

/// O dia da COTA do Firebase: vira à meia-noite do horário do Pacífico, não à
/// de Brasília (cinco horas antes, ou quatro no horário de verão americano).
/// Um domingo de culto, das 8h às 21h, cai inteiro num dia só; mas contar o dia
/// pelo relógio do aparelho trocaria de dia no meio da noite errada.
///
/// O horário de verão dos EUA vai do segundo domingo de março ao primeiro de
/// novembro (a conta é a vigente desde 2007).
String diaDaCota(DateTime agora) {
  final utc = agora.toUtc();
  final verao = _noHorarioDeVeraoDosEua(utc);
  final local = utc.subtract(Duration(hours: verao ? 7 : 8));
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

bool _noHorarioDeVeraoDosEua(DateTime utc) {
  // 2h da manhã local do domingo da virada; em UTC, 10h (PST) na entrada e
  // 9h (PDT) na saída. Basta a precisão de horas.
  final entrada = _enesimoDomingo(utc.year, 3, 2).add(const Duration(hours: 10));
  final saida = _enesimoDomingo(utc.year, 11, 1).add(const Duration(hours: 9));
  return !utc.isBefore(entrada) && utc.isBefore(saida);
}

DateTime _enesimoDomingo(int ano, int mes, int n) {
  var d = DateTime.utc(ano, mes, 1);
  while (d.weekday != DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return d.add(Duration(days: 7 * (n - 1)));
}

/// Em que ponto do dia o uso está.
enum NivelDeUso {
  /// Tudo como sempre.
  normal,

  /// Passou de 60%: o líder é avisado (Saúde do sistema).
  alerta,

  /// Passou de 80%: o app se segura sozinho (modo de economia).
  economia,
}

const double limiteDoAlerta = 0.60;
const double limiteDaEconomia = 0.80;

NivelDeUso nivelDeUso(int leituras) {
  final p = leituras / limiteGratisDeLeituras;
  if (p >= limiteDaEconomia) return NivelDeUso.economia;
  if (p >= limiteDoAlerta) return NivelDeUso.alerta;
  return NivelDeUso.normal;
}

/// O que o contador guarda por dia (um documento, `usoDiario/{dia}`).
class UsoDoDia {
  /// A conta com a regra dos 30 minutos: a que o app usa para se proteger.
  final int leituras;

  /// A pior hipótese, sem a regra.
  final int semRegra;

  /// Quantas vezes o app abriu (ou voltou depois de mais de 30 min).
  final int aberturas;

  /// De onde vieram as leituras (`cultos`, `chat`, `musicas`…).
  final Map<String, int> porFonte;

  const UsoDoDia({
    this.leituras = 0,
    this.semRegra = 0,
    this.aberturas = 0,
    this.porFonte = const {},
  });

  double get percentual => leituras / limiteGratisDeLeituras;
  NivelDeUso get nivel => nivelDeUso(leituras);

  factory UsoDoDia.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const UsoDoDia();
    int n(Object? v) => v is num ? v.toInt() : 0;
    final f = d['porFonte'];
    return UsoDoDia(
      leituras: n(d['leituras']),
      semRegra: n(d['leiturasSemRegra']),
      aberturas: n(d['aberturas']),
      porFonte: f is Map
          ? {for (final e in f.entries) '${e.key}': n(e.value)}
          : const {},
    );
  }

  /// Este uso mais o que ainda não foi gravado.
  UsoDoDia somando(UsoDoDia mais) => UsoDoDia(
        leituras: leituras + mais.leituras,
        semRegra: semRegra + mais.semRegra,
        aberturas: aberturas + mais.aberturas,
        porFonte: {
          ...porFonte,
          for (final e in mais.porFonte.entries)
            e.key: (porFonte[e.key] ?? 0) + e.value,
        },
      );
}

/// A frase para o líder, sem número de erro: o que está acontecendo e o que o
/// app vai fazer.
String frasesDoUso(UsoDoDia uso) {
  final mil = (uso.leituras / 1000).toStringAsFixed(1).replaceAll('.', ',');
  final pct = (uso.percentual * 100).round();
  switch (uso.nivel) {
    case NivelDeUso.normal:
      return 'Hoje o app usou cerca de $mil mil das 50 mil leituras grátis '
          '($pct%).';
    case NivelDeUso.alerta:
      return 'Hoje o app já usou cerca de $mil mil das 50 mil leituras grátis '
          '($pct%). Se passar de 80% ele entra sozinho em modo de economia.';
    case NivelDeUso.economia:
      return 'Hoje o app já usou cerca de $mil mil das 50 mil leituras grátis '
          '($pct%). Está em modo de economia: não baixa nada de fundo até '
          'amanhã.';
  }
}
