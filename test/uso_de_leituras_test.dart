import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/platform/armazem.dart';
import 'package:levitasync/core/utils/uso_de_leituras.dart';
import 'package:levitasync/data/models/saude_model.dart';
import 'package:levitasync/data/services/contador_de_leituras.dart';
import 'package:levitasync/data/services/modo_economia.dart';

/// A conta das leituras do Firestore e a rede de proteção que depende dela.
///
/// O que estes testes guardam é principalmente o que o contador NÃO pode
/// fazer: contar menos do que gasta (o modo de economia ligaria tarde), contar
/// em dobro uma escuta que só continuou (ligaria cedo, e o app se seguraria sem
/// precisar), e deixar o dia errado — a cota vira à meia-noite do PACÍFICO, e
/// o dia do relógio do celular (Brasília) é o dia errado das 21h às 24h.
void main() {
  final t0 = DateTime.utc(2026, 11, 21, 15, 0); // sábado, 12h em Brasília

  group('custoDaNotificacao — a regra dos 30 minutos', () {
    test('escuta que continua custa só o que mudou, nas duas contas', () {
      final c = custoDaNotificacao(
        recomeco: false,
        ultimaSincronia: t0,
        agora: t0.add(const Duration(minutes: 5)),
        totalDeDocumentos: 20,
        mudancas: 2,
      );
      expect(c.comRegra, 2);
      expect(c.semRegra, 2);
    });

    test('religada DENTRO de 30 min: com a regra só o que mudou, sem ela tudo', () {
      final c = custoDaNotificacao(
        recomeco: true,
        ultimaSincronia: t0,
        agora: t0.add(const Duration(minutes: 29)),
        totalDeDocumentos: 20,
        mudancas: 1,
      );
      expect(c.comRegra, 1);
      expect(c.semRegra, 20);
    });

    test('religada DEPOIS de 30 min: custa o resultado inteiro', () {
      final c = custoDaNotificacao(
        recomeco: true,
        ultimaSincronia: t0,
        agora: t0.add(const Duration(minutes: 31)),
        totalDeDocumentos: 20,
        mudancas: 1,
      );
      expect(c.comRegra, 20);
      expect(c.semRegra, 20);
    });

    test('exatamente 30 min ainda vale a regra (é "mais de 30")', () {
      final c = custoDaNotificacao(
        recomeco: true,
        ultimaSincronia: t0,
        agora: t0.add(const Duration(minutes: 30)),
        totalDeDocumentos: 20,
        mudancas: 0,
      );
      expect(c.comRegra, 1); // consulta nenhuma custa menos de 1
      expect(c.semRegra, 20);
    });

    test('a primeira vez (sem sincronia anterior) custa tudo', () {
      final c = custoDaNotificacao(
        recomeco: true,
        ultimaSincronia: null,
        agora: t0,
        totalDeDocumentos: 42,
        mudancas: 42,
      );
      expect(c.comRegra, 42);
      expect(c.semRegra, 42);
    });

    test('resposta vazia custa 1 leitura, não zero', () {
      final c = custoDaNotificacao(
        recomeco: true,
        ultimaSincronia: null,
        agora: t0,
        totalDeDocumentos: 0,
        mudancas: 0,
      );
      expect(c.comRegra, 1);
      expect(c.semRegra, 1);
    });
  });

  group('diaDaCota — meia-noite do Pacífico, não a de Brasília', () {
    test('no inverno (UTC−8) o dia vira às 08h UTC', () {
      expect(diaDaCota(DateTime.utc(2026, 11, 21, 7, 59)), '2026-11-20');
      expect(diaDaCota(DateTime.utc(2026, 11, 21, 8, 0)), '2026-11-21');
    });

    test('no verão dos EUA (UTC−7) o dia vira às 07h UTC', () {
      expect(diaDaCota(DateTime.utc(2026, 7, 21, 6, 59)), '2026-07-20');
      expect(diaDaCota(DateTime.utc(2026, 7, 21, 7, 0)), '2026-07-21');
    });

    test('um culto de domingo à noite em Brasília ainda é o mesmo dia', () {
      // 21h30 de domingo em Brasília = 00h30 UTC de segunda = 16h30 de
      // domingo no Pacífico: o culto da noite cai na cota de DOMINGO.
      expect(diaDaCota(DateTime.utc(2026, 11, 23, 0, 30)), '2026-11-22');
    });

    test('a virada do horário de verão dos EUA (1º de novembro de 2026)', () {
      // Ainda PDT: 08:59 UTC é 01:59 PDT do dia 1.
      expect(diaDaCota(DateTime.utc(2026, 11, 1, 8, 59)), '2026-11-01');
      // Já PST: 09:00 UTC é 01:00 PST do dia 1 (a hora repetida).
      expect(diaDaCota(DateTime.utc(2026, 11, 1, 9, 0)), '2026-11-01');
      // E a meia-noite seguinte, já em PST, é às 08:00 UTC do dia 2.
      expect(diaDaCota(DateTime.utc(2026, 11, 2, 7, 59)), '2026-11-01');
      expect(diaDaCota(DateTime.utc(2026, 11, 2, 8, 0)), '2026-11-02');
    });

    test('a virada de ano usa o ano do Pacífico', () {
      expect(diaDaCota(DateTime.utc(2027, 1, 1, 7, 59)), '2026-12-31');
      expect(diaDaCota(DateTime.utc(2027, 1, 1, 8, 0)), '2027-01-01');
    });

    test('hora local e UTC do mesmo instante dão o mesmo dia', () {
      final utc = DateTime.utc(2026, 11, 21, 12, 0);
      expect(diaDaCota(utc), diaDaCota(utc.toLocal()));
    });
  });

  group('nivelDeUso — 60% avisa, 80% segura', () {
    test('as bordas', () {
      expect(nivelDeUso(0), NivelDeUso.normal);
      expect(nivelDeUso(29999), NivelDeUso.normal);
      expect(nivelDeUso(30000), NivelDeUso.alerta);
      expect(nivelDeUso(39999), NivelDeUso.alerta);
      expect(nivelDeUso(40000), NivelDeUso.economia);
      expect(nivelDeUso(80000), NivelDeUso.economia);
    });
  });

  group('UsoDoDia', () {
    test('documento que não existe é um dia zerado, não um erro', () {
      final u = UsoDoDia.fromMap(null);
      expect(u.leituras, 0);
      expect(u.nivel, NivelDeUso.normal);
    });

    test('valor estranho no console vira zero (e não derruba nem liga a economia)', () {
      final u = UsoDoDia.fromMap({
        'leituras': 'muitas',
        'leiturasSemRegra': null,
        'aberturas': [1],
        'porFonte': 'x',
      });
      expect(u.leituras, 0);
      expect(u.semRegra, 0);
      expect(u.aberturas, 0);
      expect(u.porFonte, isEmpty);
    });

    test('lê os quatro campos e soma', () {
      final a = UsoDoDia.fromMap({
        'leituras': 900,
        'leiturasSemRegra': 1500,
        'aberturas': 3,
        'porFonte': {'cultos': 400, 'musicas': 500},
      });
      final b = a.somando(const UsoDoDia(
        leituras: 100,
        semRegra: 100,
        aberturas: 1,
        porFonte: {'cultos': 50, 'chat': 50},
      ));
      expect(b.leituras, 1000);
      expect(b.semRegra, 1600);
      expect(b.aberturas, 4);
      expect(b.porFonte, {'cultos': 450, 'musicas': 500, 'chat': 50});
      // E soma não mexe no original.
      expect(a.leituras, 900);
    });

    test('percentual e frase em português de gente', () {
      expect(const UsoDoDia(leituras: 12500).percentual, 0.25);
      expect(frasesDoUso(const UsoDoDia(leituras: 12500)), contains('25%'));
      expect(frasesDoUso(const UsoDoDia(leituras: 12500)), contains('12,5 mil'));
      expect(frasesDoUso(const UsoDoDia(leituras: 32000)),
          contains('modo de economia'));
      final e = frasesDoUso(const UsoDoDia(leituras: 41000));
      expect(e, contains('Está em modo de economia'));
      // Nada de jargão: o líder não precisa saber o que é "leitura de
      // documento" para entender a frase.
      expect(e.toLowerCase(), isNot(contains('firestore')));
    });
  });

  group('ContadorDeLeituras', () {
    late DateTime agora;
    late List<({String dia, UsoDoDia delta})> gravado;
    late ContadorDeLeituras c;
    bool falhar = false;

    setUp(() {
      Armazem.esvaziar();
      agora = t0;
      gravado = [];
      falhar = false;
      c = ContadorDeLeituras.paraTeste(
        agora: () => agora,
        gravador: (dia, delta) async {
          if (falhar) throw StateError('sem rede');
          gravado.add((dia: dia, delta: delta));
        },
      );
    });

    test('a primeira resposta de uma escuta custa o resultado inteiro', () {
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: true, total: 20, mudancas: 20);
      expect(c.pendente.leituras, 20);
      expect(c.pendente.semRegra, 20);
      expect(c.pendente.porFonte, {'cultos': 20});
    });

    test('depois disso, cada notificação custa só o que mudou', () {
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: true, total: 20, mudancas: 20);
      agora = agora.add(const Duration(minutes: 2));
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: false, total: 20, mudancas: 1);
      expect(c.pendente.leituras, 21);
    });

    test('voltar depois de MAIS de 30 min em segundo plano recobra tudo, sem a regra nunca', () {
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: true, total: 20, mudancas: 20);
      c.aoIrParaSegundoPlano();
      agora = agora.add(const Duration(minutes: 45));
      c.aoVoltar();
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: false, total: 20, mudancas: 0);
      // 20 da primeira vez + 20 da religação (passou do prazo).
      expect(c.pendente.leituras, 40);
      expect(c.pendente.semRegra, 40);
    });

    test('voltar em 10 min: a regra poupa, e a conta "sem regra" mostra o pior caso', () {
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: true, total: 20, mudancas: 20);
      c.aoIrParaSegundoPlano();
      agora = agora.add(const Duration(minutes: 10));
      c.aoVoltar();
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: false, total: 20, mudancas: 0);
      expect(c.pendente.leituras, 21); // 20 + o mínimo de 1
      expect(c.pendente.semRegra, 40); // 20 + 20: a diferença entre as duas contas
    });

    test('a religação só se paga UMA vez: a notificação seguinte custa o que mudou', () {
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: true, total: 20, mudancas: 20);
      c.aoIrParaSegundoPlano();
      agora = agora.add(const Duration(minutes: 45));
      c.aoVoltar();
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: false, total: 20, mudancas: 0);
      final depois = c.pendente.leituras;
      c.notificacao(
          fonte: 'cultos', consulta: 'c', primeiraDaInstancia: false, total: 20, mudancas: 1);
      expect(c.pendente.leituras, depois + 1);
    });

    test('leitura pontual custa o que veio, no mínimo 1', () {
      c.umaVez('musicas', 42);
      c.umaVez('cifras', 0);
      expect(c.pendente.leituras, 43);
      expect(c.pendente.porFonte, {'musicas': 42, 'cifras': 1});
    });

    test('abrir o app conta uma abertura', () {
      c.abertura();
      c.abertura();
      expect(c.pendente.aberturas, 2);
      expect(c.temPendente, isTrue);
    });

    test('descarregar grava UM documento agregado, com o dia da cota, e zera o pendente', () async {
      c.umaVez('musicas', 40);
      c.umaVez('cultos', 20);
      c.abertura();
      await c.descarregar();
      expect(gravado, hasLength(1));
      expect(gravado.single.dia, diaDaCota(t0));
      expect(gravado.single.delta.leituras, 60);
      expect(gravado.single.delta.aberturas, 1);
      expect(gravado.single.delta.porFonte, {'musicas': 40, 'cultos': 20});
      expect(c.temPendente, isFalse);
    });

    test('sem nada a gravar, não escreve (cada escrita é cota)', () async {
      await c.descarregar();
      expect(gravado, isEmpty);
    });

    test('falha ao gravar NÃO perde a conta: fica para a próxima', () async {
      c.umaVez('musicas', 40);
      falhar = true;
      await c.descarregar();
      expect(gravado, isEmpty);
      expect(c.pendente.leituras, 40);
      falhar = false;
      await c.descarregar();
      expect(gravado.single.delta.leituras, 40);
      expect(c.pendente.leituras, 0);
    });

    test('o que chega DURANTE a gravação não se perde', () async {
      final c2 = ContadorDeLeituras.paraTeste(
        agora: () => agora,
        gravador: (dia, delta) async {
          // Enquanto "grava", chega mais uma leitura.
          c.umaVez('chat', 7);
          gravado.add((dia: dia, delta: delta));
        },
      );
      c = c2;
      c.umaVez('musicas', 40);
      await c.descarregar();
      expect(gravado.single.delta.leituras, 40);
      expect(c.pendente.leituras, 7);
      expect(c.pendente.porFonte, {'chat': 7});
    });

    test('duas descargas ao mesmo tempo gravam uma só vez', () async {
      c.umaVez('musicas', 40);
      await Future.wait([c.descarregar(), c.descarregar()]);
      expect(gravado, hasLength(1));
    });

    test('ir para segundo plano já grava (o app pode ser encerrado ali)', () async {
      c.umaVez('musicas', 40);
      c.aoIrParaSegundoPlano();
      await Future<void>.delayed(Duration.zero);
      expect(gravado, hasLength(1));
    });

    test('o dia gravado é o da cota, mesmo às 22h de Brasília', () async {
      // 22h de sábado em Brasília = 01h UTC de domingo: no Pacífico ainda é
      // sábado. Gravar em "domingo" separaria a cota de um culto em dois dias.
      agora = DateTime.utc(2026, 11, 22, 1, 0);
      c.umaVez('musicas', 10);
      await c.descarregar();
      expect(gravado.single.dia, '2026-11-21');
    });

    test('o pendente sobrevive a fechar o app', () async {
      c.umaVez('musicas', 40);
      await Future<void>.delayed(Duration.zero);
      final outro = ContadorDeLeituras.paraTeste(
        agora: () => agora,
        gravador: (dia, delta) async => gravado.add((dia: dia, delta: delta)),
      );
      outro.iniciar();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(outro.pendente.leituras, 40);
      expect(outro.pendente.porFonte, {'musicas': 40});
      outro.parar();
    });
  });

  group('ModoEconomia', () {
    late ContadorDeLeituras original;

    setUp(() {
      Armazem.esvaziar();
      original = ContadorDeLeituras.instancia;
      ContadorDeLeituras.instancia = ContadorDeLeituras.paraTeste(
        agora: DateTime.now,
        gravador: (_, __) async {},
      );
    });

    tearDown(() {
      ModoEconomia.instancia.definirParaTeste(null);
      ContadorDeLeituras.instancia = original;
    });

    test('sem conta nenhuma, o app não se segura', () {
      ModoEconomia.instancia.definirParaTeste(null);
      expect(ModoEconomia.instancia.ligado, isFalse);
      expect(ModoEconomia.instancia.nivel, NivelDeUso.normal);
    });

    test('79% não liga; 80% liga', () {
      ModoEconomia.instancia.definirParaTeste(const UsoDoDia(leituras: 39999));
      expect(ModoEconomia.instancia.ligado, isFalse);
      ModoEconomia.instancia.definirParaTeste(const UsoDoDia(leituras: 40000));
      expect(ModoEconomia.instancia.ligado, isTrue);
    });

    test('o que este aparelho ainda não gravou entra na conta', () {
      ModoEconomia.instancia.definirParaTeste(const UsoDoDia(leituras: 39990));
      expect(ModoEconomia.instancia.ligado, isFalse);
      ContadorDeLeituras.instancia.umaVez('musicas', 15);
      expect(ModoEconomia.instancia.ligado, isTrue);
    });

    test('o uso de ONTEM não vale hoje: a cota virou e o freio solta', () {
      // Um aparelho que ficou aberto a noite toda não pode continuar em modo
      // de economia (nem mostrando 90%) com o dia já zerado.
      ModoEconomia.instancia
          .definirParaTeste(const UsoDoDia(leituras: 45000), dia: '2020-01-01');
      expect(ModoEconomia.instancia.uso, isNull);
      expect(ModoEconomia.instancia.ligado, isFalse);
    });

    test('60% avisa o líder mas NÃO liga o freio', () {
      ModoEconomia.instancia.definirParaTeste(const UsoDoDia(leituras: 31000));
      expect(ModoEconomia.instancia.nivel, NivelDeUso.alerta);
      expect(ModoEconomia.instancia.ligado, isFalse);
    });
  });

  group('Saúde do sistema — a linha das leituras', () {
    final agoraS = DateTime(2026, 11, 21, 10, 0);
    const worker = SaudeDoWorker(configurado: true, entra: true, robo: 'entra e está líder');
    final carimbos = {
      for (final k in ['cultos', 'vespera', 'faxina'])
        k: CarimboDeSaude(em: agoraS.subtract(const Duration(hours: 2)), ok: true),
    };

    SaudeDoSistema av(UsoDoDia? uso, {bool mostrar = true}) =>
        SaudeDoSistema.avaliar(
          worker: worker,
          carimbos: carimbos,
          agora: agoraS,
          uso: uso,
          mostrarUso: mostrar,
        );

    ItemDeSaude linha(SaudeDoSistema s) =>
        s.itens.firstWhere((i) => i.titulo == 'Leituras do banco hoje');

    test('sem pedir a linha, ela não aparece (o diagnóstico dos robôs é outro)', () {
      final s = av(const UsoDoDia(leituras: 1000), mostrar: false);
      expect(s.itens.any((i) => i.titulo == 'Leituras do banco hoje'), isFalse);
    });

    test('abaixo de 60% é verde, sem instrução na tela', () {
      final l = linha(av(const UsoDoDia(leituras: 29999)));
      expect(l.estado, EstadoDeSaude.ok);
      expect(l.oQueFazer, isNull);
    });

    test('a partir de 60% é amarelo — avisa, mas não acende o alarme do Início', () {
      final s = av(const UsoDoDia(leituras: 30000));
      expect(linha(s).estado, EstadoDeSaude.alerta);
      expect(linha(s).oQueFazer, isNotNull);
      expect(s.temAlarme, isFalse);
    });

    test('em modo de economia (80%) continua amarelo, e a frase diz o que o app faz', () {
      final s = av(const UsoDoDia(leituras: 41000));
      expect(linha(s).estado, EstadoDeSaude.alerta);
      expect(linha(s).detalhe, contains('modo de economia'));
      expect(s.temAlarme, isFalse);
    });

    test('só a partir de 95% é vermelho, e acende o alarme', () {
      expect(linha(av(const UsoDoDia(leituras: 47499))).estado, EstadoDeSaude.alerta);
      final s = av(const UsoDoDia(leituras: 47500));
      expect(linha(s).estado, EstadoDeSaude.ruim);
      expect(s.temAlarme, isTrue);
      expect(s.pior!.titulo, 'Leituras do banco hoje');
    });

    test('não deu para conferir: "não sei", nunca vermelho', () {
      final s = av(null);
      expect(linha(s).estado, EstadoDeSaude.desconhecido);
      expect(s.temAlarme, isFalse);
    });

    test('um dia zerado (documento de hoje ainda não existe) é verde', () {
      expect(linha(av(const UsoDoDia())).estado, EstadoDeSaude.ok);
    });
  });
}
