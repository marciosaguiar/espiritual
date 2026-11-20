/// O que dizer à pessoa sobre a internet — e, principalmente, QUANDO calar.
///
/// A regra deste arquivo é a do pedido: o aviso só aparece quando FAZ
/// diferença. Com internet e nada pendente, a resposta é "nada". Alarme que
/// toca à toa ensina a pessoa a não ler o alarme.
///
/// Função pura, com `agora` de fora, como as outras contas de tempo do app.
library;

class SituacaoDaRede {
  final bool online;

  /// Desde quando o aparelho está sem internet (nulo se está com).
  final DateTime? offlineDesde;

  /// A última vez que se SABE que os dados estavam em dia com o banco.
  final DateTime? ultimaConferencia;

  /// Quantas ações esperam para ser enviadas, e desde quando.
  final int pendentes;
  final DateTime? pendenteDesde;

  const SituacaoDaRede({
    required this.online,
    this.offlineDesde,
    this.ultimaConferencia,
    this.pendentes = 0,
    this.pendenteDesde,
  });
}

/// Quanto tempo sem internet até valer a pena avisar. Abaixo disso é o
/// elevador, o túnel, a troca de wi-fi.
const Duration esperaAntesDeAvisarOffline = Duration(seconds: 10);

/// Quanto tempo uma ação pode ficar pendente, COM internet, sem aparecer.
/// O normal é enviar em menos de um segundo.
const Duration esperaAntesDeAvisarEnvio = Duration(seconds: 5);

/// Dados mais velhos que isto, estando offline, ganham "atualizado há X".
/// Antes disso a informação não ajuda e só pesa.
const Duration idadeQueImporta = Duration(minutes: 30);

/// O texto da faixa, ou nulo se não há o que dizer.
String? textoDaFaixa(SituacaoDaRede s, DateTime agora) {
  if (s.online) {
    if (s.pendentes > 0 &&
        s.pendenteDesde != null &&
        agora.difference(s.pendenteDesde!) >= esperaAntesDeAvisarEnvio) {
      return s.pendentes == 1
          ? 'Enviando 1 alteração…'
          : 'Enviando ${s.pendentes} alterações…';
    }
    return null;
  }

  final desde = s.offlineDesde;
  if (desde != null && agora.difference(desde) < esperaAntesDeAvisarOffline) {
    return null;
  }

  final partes = <String>[
    'Sem internet. O app está mostrando o que já baixou.',
  ];
  final idade = idadeDosDados(s.ultimaConferencia, agora);
  if (idade != null) partes.add('Atualizado $idade.');
  if (s.pendentes > 0) {
    partes.add(s.pendentes == 1
        ? '1 alteração sua espera a internet.'
        : '${s.pendentes} alterações suas esperam a internet.');
  }
  return partes.join(' ');
}

/// "há 2 h", "há 3 dias" — ou nulo quando é recente demais para importar (ou
/// quando não se sabe).
String? idadeDosDados(DateTime? ultima, DateTime agora) {
  if (ultima == null) return null;
  final d = agora.difference(ultima);
  if (d < idadeQueImporta) return null;
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  final dias = d.inDays;
  return dias == 1 ? 'há 1 dia' : 'há $dias dias';
}
