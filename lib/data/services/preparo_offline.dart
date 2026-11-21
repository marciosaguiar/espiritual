import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../core/constants/hinarios.dart';
import '../../core/platform/armazem.dart';
import '../../core/platform/rede.dart';
import '../../core/utils/memoria_do_aparelho.dart';
import '../../core/utils/orcamento_de_leituras.dart';
import '../../core/utils/snapshot_local.dart';
import '../models/arrangement_model.dart';
import '../models/hino_da_biblioteca.dart';
import 'arranjos_locais.dart';
import 'audios_locais.dart';
import 'firestore_service.dart';
import 'hinos_locais.dart';
import 'local_storage_service.dart';
import 'modo_economia.dart';

/// O que a preparação fez, para o teste e para o log.
class RelatorioDoPreparo {
  final int cifras;
  final int hinos;
  final int leiturasGastas;
  final bool biblia;
  final String? parouPor;

  const RelatorioDoPreparo({
    this.cifras = 0,
    this.hinos = 0,
    this.leiturasGastas = 0,
    this.biblia = false,
    this.parouPor,
  });

  @override
  String toString() =>
      'cifras=$cifras hinos=$hinos leituras=$leiturasGastas biblia=$biblia'
      '${parouPor == null ? '' : ' parou=$parouPor'}';
}

typedef LerCifraNoBanco = Future<({ArrangementModel? arranjo, bool ok})>
    Function(String songId);
typedef LerIndiceNoBanco = Future<({IndiceDoHinario? indice, String? error})>
    Function(String hinarioId);
typedef LerPaginaNoBanco
    = Future<({List<HinoDaBiblioteca>? hinos, String? error})> Function(
        String hinarioId, {required int depoisDe, required int limite});

/// Deixa o app pronto para o culto sem sinal: traz, AOS POUCOS e em segundo
/// plano, as cifras, as letras dos hinos e a Bíblia.
///
/// O LIMITE É A COTA GRÁTIS. São 50 mil leituras por dia para o ministério
/// inteiro, e baixar tudo de uma vez em cada um dos 30 aparelhos seria ~36
/// mil só nisso — acabada a cota, o app inteiro para de ler. Então cada
/// aparelho tem um ORÇAMENTO diário (`OrcamentoDeLeituras`): gasta até o
/// limite, para, e continua amanhã de onde parou. A ordem é a do que mais
/// serve: primeiro as cifras do repertório (uma leitura por música), depois as
/// letras dos hinos, hinário por hinário, na ordem que a pessoa escolheu.
///
/// Só conta aqui o que ESTA classe lê. O que a pessoa causa — abrir uma
/// música, trazer um hinário porque pediu — não passa pelo orçamento.
///
/// Segurança de repetição: pode rodar a qualquer hora, quantas vezes for. O
/// progresso e o gasto do dia ficam no armazém, e o que já está guardado não é
/// pedido de novo.
class PreparoOffline {
  static const String chaveDoOrcamento = 'preparo:orcamento';
  static const String chaveDoProgresso = 'preparo:progresso';
  static const String chaveDaBiblia = 'preparo:biblia:';
  static const String chaveDasMarcas = 'marca-aparelho';

  /// Quantos hinos por consulta. Pequeno o bastante para o orçamento do dia
  /// acabar sem desperdício, grande o bastante para não ser uma consulta por
  /// hino.
  static const int hinosPorPagina = 50;

  final DateTime Function() agora;
  final bool Function() online;
  final LerCifraNoBanco lerCifra;
  final LerIndiceNoBanco lerIndice;
  final LerPaginaNoBanco lerPagina;
  final Future<void> Function(String traducaoId) baixarBiblia;
  final int limiteDiario;
  final bool Function() economia;

  PreparoOffline({
    DateTime Function()? agora,
    bool Function()? online,
    LerCifraNoBanco? lerCifra,
    LerIndiceNoBanco? lerIndice,
    LerPaginaNoBanco? lerPagina,
    Future<void> Function(String)? baixarBiblia,
    this.limiteDiario = OrcamentoDeLeituras.limiteDiario,
    bool Function()? economia,
  })  : economia = economia ?? (() => ModoEconomia.instancia.ligado),
        agora = agora ?? DateTime.now,
        online = online ?? (() => Rede.online),
        lerCifra = lerCifra ?? FirestoreService.lerArranjoDoServidor,
        lerIndice = lerIndice ?? FirestoreService.lerIndiceDoHinario,
        lerPagina = lerPagina ?? FirestoreService.lerPaginaDeLetras,
        baixarBiblia = baixarBiblia ?? _baixarBibliaPeloBundle;

  /// Pede o arquivo ao servidor sem interpretar o texto: quem o guarda é o
  /// service worker. `load` evita ler e decodificar 4 MB de JSON só para
  /// deixá-lo no aparelho.
  static Future<void> _baixarBibliaPeloBundle(String id) async {
    // Só vale se o service worker já assumiu a página: é ELE quem guarda o
    // arquivo. Antes disso o arquivo viria da rede sem ficar no aparelho, e a
    // preparação marcaria "Bíblia pronta" sem estar. Lançar aqui faz a
    // tentativa ficar para a próxima rodada (aos 60 s, ou amanhã).
    if (!Armazem.servicoDeCacheAtivo()) {
      throw StateError('o service worker ainda não assumiu a página');
    }
    await rootBundle.load('assets/biblia/$id.json');
  }

  Future<OrcamentoDeLeituras> _lerOrcamento() async {
    try {
      final t = await Armazem.ler(chaveDoOrcamento);
      return OrcamentoDeLeituras.fromJson(
          t == null ? null : Map<String, dynamic>.from(jsonDecode(t) as Map),
          agora());
    } catch (_) {
      return OrcamentoDeLeituras.fromJson(null, agora());
    }
  }

  Future<void> _gravarOrcamento(OrcamentoDeLeituras o) =>
      Armazem.gravar(chaveDoOrcamento, jsonEncode(o.toJson()));

  /// Quanto ainda pode gastar hoje.
  Future<int> restanteHoje() async =>
      (await _lerOrcamento()).restante(agora(), limite: limiteDiario);

  Future<Map<String, dynamic>> _lerProgresso() async {
    try {
      final t = await Armazem.ler(chaveDoProgresso);
      return t == null ? {} : Map<String, dynamic>.from(jsonDecode(t) as Map);
    } catch (_) {
      return {};
    }
  }

  // ── dia movimentado ───────────────────────────────────────────────────────

  static const String chaveDasAberturas = 'preparo:aberturas';

  /// A partir de quantas aberturas do app no mesmo dia a preparação fica quieta
  /// (a 3ª; eram 4 até a rodada "orçamento de leituras").
  ///
  /// **É a conta do plano grátis.** Cada abertura de mais de 30 minutos depois
  /// da anterior custa ~240 leituras (todos os documentos das escutas, de novo);
  /// a preparação custa até 150 por dia — mais da metade de OUTRA abertura fria
  /// por aparelho. Num domingo em que cada pessoa abre o app seis vezes, 30
  /// pessoas gastam ~43 mil leituras só abrindo, e somar 7.500 da preparação
  /// passaria dos 50 mil. Dia movimentado é justamente o dia de não baixar nada
  /// de fundo: a preparação espera um dia calmo.
  static const int aberturasQueSilenciam = 3;

  /// Conta uma abertura do app hoje e devolve quantas já foram.
  static Future<int> registrarAbertura({DateTime? agora}) async {
    final hoje = OrcamentoDeLeituras.diaDe(agora ?? DateTime.now());
    try {
      final t = await Armazem.ler(chaveDasAberturas);
      var n = 0;
      if (t != null) {
        final j = Map<String, dynamic>.from(jsonDecode(t) as Map);
        if (j['dia'] == hoje) n = (j['n'] as num?)?.toInt() ?? 0;
      }
      n++;
      await Armazem.gravar(chaveDasAberturas, jsonEncode({'dia': hoje, 'n': n}));
      return n;
    } catch (_) {
      return 1;
    }
  }

  Future<int> _aberturasHoje() async {
    try {
      final t = await Armazem.ler(chaveDasAberturas);
      if (t == null) return 0;
      final j = Map<String, dynamic>.from(jsonDecode(t) as Map);
      return j['dia'] == OrcamentoDeLeituras.diaDe(agora())
          ? (j['n'] as num?)?.toInt() ?? 0
          : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Os ids dos hinários na ordem em que a preparação os traz: primeiro o que
  /// a pessoa usa (a ordem que ela escolheu), depois os demais.
  ///
  /// **A ordem salva é VAZIA por padrão** — quem nunca arrastou um hinário não
  /// tem nada guardado —, e usá-la direto fazia a preparação não trazer hino
  /// nenhum, em silêncio. Foi o navegador que mostrou: o orçamento parava nas
  /// cifras. `hinariosNaOrdem` completa com os que faltam.
  static List<String> idsDosHinarios(List<String> ordemSalva) =>
      [for (final h in hinariosNaOrdem(ordemSalva)) h.id];

  /// Roda um passo da preparação. [idsDeMusicas] são as do repertório (as
  /// arquivadas não entram) e [hinarios] os ids dos hinários na ordem em que a
  /// pessoa os usa; [traducaoDaBiblia] é a tradução que ela lê.
  ///
  /// [carregarIdsDeMusicas] pede os ids DEPOIS de a preparação decidir que vai
  /// rodar (sem internet, em modo de economia e num dia movimentado ela nem
  /// começa). O repertório já não é lido a cada abertura do app — só quando
  /// alguém abre a lista —, então é aqui, e só aqui, que a preparação o traz
  /// para o aparelho. Se vier vazio, o passo das cifras simplesmente não tem o
  /// que fazer.
  Future<RelatorioDoPreparo> executar({
    List<String> idsDeMusicas = const [],
    Future<List<String>> Function()? carregarIdsDeMusicas,
    required List<String> hinarios,
    String? traducaoDaBiblia,
  }) async {
    if (!online()) return const RelatorioDoPreparo(parouPor: 'sem internet');
    // Passou de 80% das leituras do dia: o que é conforto espera amanhã.
    if (economia()) return const RelatorioDoPreparo(parouPor: 'modo de economia');
    if (await _aberturasHoje() >= aberturasQueSilenciam) {
      return const RelatorioDoPreparo(parouPor: 'dia movimentado');
    }

    if (carregarIdsDeMusicas != null) {
      try {
        idsDeMusicas = await carregarIdsDeMusicas();
      } catch (_) {
        // Sem a lista, a preparação segue com o que não depende dela.
        idsDeMusicas = const [];
      }
    }

    var orcamento = await _lerOrcamento();
    var restante = orcamento.restante(agora(), limite: limiteDiario);
    var cifras = 0;
    var hinos = 0;
    var gasto = 0;
    String? parouPor;

    Future<void> gastar(int n) async {
      gasto += n;
      restante -= n;
      orcamento = orcamento.gastando(n, agora());
      await _gravarOrcamento(orcamento);
    }

    // 1) As cifras do repertório: uma leitura por música, e o que o servidor
    // disser (inclusive "não tem cifra") vira resposta guardada — a música
    // sem cifra não é perguntada de novo amanhã.
    for (final id in idsDeMusicas) {
      if (restante <= 0) {
        parouPor = 'orçamento do dia';
        break;
      }
      if (await ArranjosLocais.jaSabe(id)) continue;
      final r = await lerCifra(id);
      if (!r.ok) {
        return RelatorioDoPreparo(
            cifras: cifras,
            hinos: hinos,
            leiturasGastas: gasto,
            parouPor: 'falha de rede');
      }
      await gastar(1);
      if (r.arranjo != null) {
        await ArranjosLocais.guardar(r.arranjo!);
        cifras++;
      } else {
        await ArranjosLocais.guardarAusencia(id);
      }
    }

    // 2) As letras dos hinos, hinário por hinário.
    final progresso = await _lerProgresso();
    for (final h in hinarios) {
      if (restante <= 0) {
        parouPor ??= 'orçamento do dia';
        break;
      }
      // O índice: do aparelho, ou uma leitura do banco.
      var indice = await HinosLocais.lerIndice(h);
      if (indice == null) {
        final r = await lerIndice(h);
        if (r.error != null || r.indice == null) {
          return RelatorioDoPreparo(
              cifras: cifras, hinos: hinos, leiturasGastas: gasto,
              parouPor: 'falha de rede');
        }
        await gastar(1);
        indice = r.indice!;
        await HinosLocais.guardarIndice(indice);
      }
      if (indice.vazio) continue; // ninguém importou este hinário

      final marca = indice.marca;
      final antes = progresso[h] is Map
          ? Map<String, dynamic>.from(progresso[h] as Map)
          : <String, dynamic>{};
      // Marca diferente = o líder importou de novo: recomeça deste hinário.
      var ate = antes['marca'] == marca ? (antes['ate'] as num?)?.toInt() ?? 0 : 0;
      var concluido = antes['marca'] == marca && antes['concluido'] == true;

      while (!concluido && restante > 0) {
        final limite = restante < hinosPorPagina ? restante : hinosPorPagina;
        final r = await lerPagina(h, depoisDe: ate, limite: limite);
        if (r.hinos == null) {
          return RelatorioDoPreparo(
              cifras: cifras, hinos: hinos, leiturasGastas: gasto,
              parouPor: 'falha de rede');
        }
        final pagina = r.hinos!;
        // Uma consulta vazia também custa uma leitura.
        await gastar(pagina.isEmpty ? 1 : pagina.length);
        await HinosLocais.guardarHinos(pagina, marca);
        hinos += pagina.length;
        if (pagina.isNotEmpty) ate = pagina.last.numero;
        // Veio menos que o pedido: acabou o hinário.
        if (pagina.length < limite) concluido = true;
        progresso[h] = {'marca': marca, 'ate': ate, 'concluido': concluido};
        await Armazem.gravar(chaveDoProgresso, jsonEncode(progresso));
      }
      if (!concluido) parouPor ??= 'orçamento do dia';
    }

    // 3) A Bíblia: UM arquivo (não passa pelo Firestore, então não gasta
    // leitura). Só a tradução que a pessoa lê, e só uma vez.
    var biblia = false;
    if (traducaoDaBiblia != null) {
      final feita = await Armazem.ler('$chaveDaBiblia$traducaoDaBiblia');
      if (feita == null) {
        try {
          await baixarBiblia(traducaoDaBiblia);
          await Armazem.gravar('$chaveDaBiblia$traducaoDaBiblia', 'ok');
          biblia = true;
        } catch (_) {
          // Sem a Bíblia hoje; amanhã tenta de novo.
        }
      }
    }

    return RelatorioDoPreparo(
      cifras: cifras,
      hinos: hinos,
      leiturasGastas: gasto,
      biblia: biblia,
      parouPor: parouPor,
    );
  }

  // ─── dados apagados pelo aparelho ─────────────────────────────────────────

  /// Confere as duas marcas (localStorage e armazém). Se o aparelho apagou um
  /// dos lugares, esquece o que é DERIVADO — progresso, cota, cópias — e
  /// recomeça a baixar aos poucos. Nunca toca na fila de envio nem nos
  /// recados: o que a pessoa fez e ainda não chegou ao banco é dela, e não se
  /// baixa de novo.
  ///
  /// Não pede nada à pessoa. Devolve o veredito, para o teste e para o log.
  static Future<VereditoDoAparelho> conferirAparelho() async {
    final marcaLocal = _lerMarcaLocal();
    final marcaArmazem = (await Armazem.ler(chaveDasMarcas)) != null;
    final veredito = conferirMarcas(
        marcaNoLocalStorage: marcaLocal, marcaNoArmazem: marcaArmazem);
    if (veredito == VereditoDoAparelho.dadosApagados) {
      await esquecerOQueEDerivado();
    }
    if (veredito != VereditoDoAparelho.tudoCerto) {
      await _deixarMarcas();
    }
    // Pede ao navegador para não apagar: com o app instalado ele costuma
    // aceitar. Se recusar, o plano acima cobre.
    unawaited(Armazem.pedirPersistencia());
    return veredito;
  }

  static bool _lerMarcaLocal() {
    try {
      return LocalStorageService.prefs.getString(chaveDasMarcas) != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _deixarMarcas() async {
    try {
      await LocalStorageService.prefs
          .setString(chaveDasMarcas, DateTime.now().toUtc().toIso8601String());
    } catch (_) {}
    await Armazem.gravar(chaveDasMarcas, DateTime.now().toUtc().toIso8601String());
  }

  /// Esquece o que a preparação guardou e a conta dela. A FILA e os RECADOS
  /// ficam.
  static Future<void> esquecerOQueEDerivado() async {
    await Armazem.apagar(chaveDoOrcamento);
    await Armazem.apagar(chaveDoProgresso);
    await Armazem.apagar(chaveDasAberturas);
    for (final k in await Armazem.chaves(chaveDaBiblia)) {
      await Armazem.apagar(k);
    }
    await ArranjosLocais.esquecerTodas();
    for (final k in await Armazem.chaves('hino:')) {
      await Armazem.apagar(k);
    }
    for (final k in await Armazem.chaves('hindice:')) {
      await Armazem.apagar(k);
    }
    await SnapshotLocal.esquecerTodas();
    await AudiosLocais.esquecerTodos();
  }
}
