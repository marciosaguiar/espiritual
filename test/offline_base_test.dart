// A base do "offline primeiro": fusão de edições, a fila de envio, a faixa de
// rede, o orçamento de leituras e a conferência de dados apagados.
//
// TODO o texto é inventado.

import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/core/platform/armazem.dart';
import 'package:levitasync/core/utils/fila_de_envio.dart';
import 'package:levitasync/core/utils/frescor.dart';
import 'package:levitasync/core/utils/fusao_de_edicao.dart';
import 'package:levitasync/core/utils/memoria_do_aparelho.dart';
import 'package:levitasync/core/utils/orcamento_de_leituras.dart';
import 'package:levitasync/data/models/aviso_de_sincronia.dart';

CampoEditado _c(Object? base, Object? novo) =>
    CampoEditado(base: base, novo: novo);

void main() {
  setUp(Armazem.esvaziar);

  group('fusão de edições: quem chegou primeiro ao banco vence', () {
    test('ninguém mexeu: a edição entra', () {
      final r = fundirEdicao(
        meus: {'name': _c('Sou Grato', 'Sou muito grato')},
        servidor: {'name': 'Sou Grato'},
      );
      expect(r.aplicar, {'name': 'Sou muito grato'});
      expect(r.perdas, isEmpty);
    });

    test('outra pessoa mudou o MESMO campo antes: a minha NÃO sobrescreve, e '
        'eu sou avisado do que ficou', () {
      final r = fundirEdicao(
        meus: {'name': _c('Sou Grato', 'Sou muito grato')},
        servidor: {'name': 'Grato sou'},
      );
      expect(r.aplicar, isEmpty);
      expect(r.perdas.single.campo, 'name');
      expect(r.perdas.single.minha, 'Sou muito grato');
      expect(r.perdas.single.atual, 'Grato sou');
    });

    test('campos DIFERENTES não brigam: o meu entra, o dela também', () {
      // Eu mudei o tom, ela mudou o nome. Os dois valem.
      final r = fundirEdicao(
        meus: {'originalKey': _c('G', 'A')},
        servidor: {'name': 'Nome novo', 'originalKey': 'G'},
      );
      expect(r.aplicar, {'originalKey': 'A'});
      expect(r.perdas, isEmpty);
    });

    test('uma parte entra e outra perde, na mesma edição', () {
      final r = fundirEdicao(
        meus: {'name': _c('A', 'B'), 'originalKey': _c('G', 'A')},
        servidor: {'name': 'C', 'originalKey': 'G'},
      );
      expect(r.aplicar, {'originalKey': 'A'});
      expect(r.perdas.map((p) => p.campo), ['name']);
    });

    test('o banco já está como eu queria: nada a gravar, e não é perda', () {
      final r = fundirEdicao(
        meus: {'name': _c('A', 'B')},
        servidor: {'name': 'B'},
      );
      expect(r.nadaAGravar, isTrue);
      expect(r.perdas, isEmpty);
      expect(r.jaIguais, ['name']);
    });

    test('campo que nunca foi gravado vale nulo dos dois lados', () {
      final r = fundirEdicao(
        meus: {'observacoes': _c(null, 'entra sem bateria')},
        servidor: {},
      );
      expect(r.aplicar, {'observacoes': 'entra sem bateria'});
    });

    test('listas e mapas comparam pelo conteúdo, não pela identidade', () {
      final r = fundirEdicao(
        meus: {'links': _c({'video': 'a'}, {'video': 'b'})},
        servidor: {'links': {'video': 'a'}},
      );
      expect(r.aplicar, {'links': {'video': 'b'}});
    });

    test('duas edições offline seguidas ficam com a base da PRIMEIRA', () {
      final juntas = juntarEdicoes(
        {'name': _c('A', 'B')},
        {'name': _c('B', 'C'), 'originalKey': _c('G', 'A')},
      );
      expect(juntas['name']!.base, 'A');
      expect(juntas['name']!.novo, 'C');
      expect(juntas['originalKey']!.novo, 'A');
    });

    test('mudar e desfazer não deixa nada a enviar', () {
      final juntas =
          juntarEdicoes({'name': _c('A', 'B')}, {'name': _c('B', 'A')});
      expect(juntas, isEmpty);
    });
  });

  group('a fila de envio', () {
    late List<ItemDaFila> enviados;
    late List<AvisoDeSincronia> avisos;
    late ResultadoDoEnvio Function(ItemDaFila) decidir;
    late DateTime agora;
    late bool online;
    late FilaDeEnvio fila;

    ItemDaFila presenca(bool confirmado, {String id = 'i1'}) =>
        ItemDaFila.presenca(
            id: id,
            culto: '2026-11-22_0800',
            userId: 'u1',
            confirmado: confirmado,
            agora: agora);

    setUp(() {
      enviados = [];
      avisos = [];
      agora = DateTime(2026, 11, 20, 10);
      online = false;
      decidir = (_) => const ResultadoDoEnvio.enviado();
      fila = FilaDeEnvio(
        estaOnline: () => online,
        agora: () => agora,
        aoAvisar: avisos.addAll,
        executores: {
          for (final t in TipoDeAcao.values)
            t: (item) async {
              enviados.add(item);
              return decidir(item);
            },
        },
      );
    });

    test('sem internet: entra na fila, aparece como pendente e NÃO tenta enviar',
        () async {
      final r = await fila.enfileirar(presenca(true));
      expect(r, isNull);
      expect(fila.pendentes, 1);
      expect(enviados, isEmpty);
    });

    test('a internet volta: envia sozinho e a fila esvazia', () async {
      await fila.enfileirar(presenca(true));
      online = true;
      await fila.acordar();
      expect(enviados.single.dados['confirmado'], true);
      expect(fila.pendentes, 0);
    });

    test('confirmar, desmarcar e confirmar de novo offline manda UM envio, com '
        'o estado final', () async {
      await fila.enfileirar(presenca(true, id: 'a'));
      await fila.enfileirar(presenca(false, id: 'b'));
      await fila.enfileirar(presenca(true, id: 'c'));
      expect(fila.pendentes, 1);
      online = true;
      await fila.acordar();
      expect(enviados, hasLength(1));
      expect(enviados.single.dados['confirmado'], true);
    });

    test('com internet e envio rápido, devolve o resultado na hora (o erro '
        'aparece como sempre apareceu)', () async {
      online = true;
      decidir = (_) => const ResultadoDoEnvio.descartado(
          'Você não está escalado neste culto.');
      final r = await fila.enfileirar(presenca(true));
      expect(r!.desfecho, Desfecho.descartado);
      expect(r.erro, 'Você não está escalado neste culto.');
      expect(fila.pendentes, 0, reason: 'falha definitiva não fica rodando');
    });

    test('falha de rede mantém o item, com espera crescente', () async {
      online = true;
      decidir = (_) => const ResultadoDoEnvio.depois('sem rede');
      await fila.enfileirar(presenca(true));
      expect(fila.pendentes, 1);
      final primeira = fila.itens.single.proximaTentativa!;
      expect(primeira.isAfter(agora), isTrue);

      // Antes da hora, não tenta de novo.
      enviados.clear();
      await fila.processar();
      expect(enviados, isEmpty);

      // "A internet voltou": esquece a espera.
      await fila.acordar();
      expect(enviados, hasLength(1));
    });

    test('para no primeiro "sem rede": os outros não esperam o prazo um a um',
        () async {
      await fila.enfileirar(presenca(true));
      await fila.enfileirar(ItemDaFila.edicao(
          id: 'm1',
          tipo: TipoDeAcao.musica,
          songId: 's1',
          campos: {'name': _c('A', 'B')},
          agora: agora));
      online = true;
      decidir = (_) => const ResultadoDoEnvio.depois('sem rede');
      await fila.acordar();
      expect(enviados, hasLength(1), reason: 'o segundo nem foi tentado');
    });

    test('um recado do envio vira aviso para a pessoa', () async {
      online = true;
      decidir = (_) => ResultadoDoEnvio.enviado(avisos: [
            AvisoDeSincronia(
                id: 'x',
                tipo: TipoDeRecado.edicaoPerdida,
                criadoEm: agora,
                titulo: 't',
                texto: 'x')
          ]);
      await fila.enfileirar(presenca(true));
      expect(avisos.single.id, 'x');
    });

    test('duas edições da mesma música viram UM envio, com a base da '
        'primeira', () async {
      ItemDaFila ed(String id, Map<String, CampoEditado> c) =>
          ItemDaFila.edicao(
              id: id,
              tipo: TipoDeAcao.musica,
              songId: 's1',
              campos: c,
              agora: agora);
      await fila.enfileirar(ed('a', {'name': _c('A', 'B')}));
      await fila.enfileirar(ed('b', {'name': _c('B', 'C')}));
      expect(fila.pendentes, 1);
      final c = fila.itens.single.campos['name']!;
      expect(c.base, 'A');
      expect(c.novo, 'C');
    });

    test('edição que volta ao que era some da fila', () async {
      ItemDaFila ed(String id, Map<String, CampoEditado> c) =>
          ItemDaFila.edicao(
              id: id,
              tipo: TipoDeAcao.musica,
              songId: 's1',
              campos: c,
              agora: agora);
      await fila.enfileirar(ed('a', {'name': _c('A', 'B')}));
      await fila.enfileirar(ed('b', {'name': _c('B', 'A')}));
      expect(fila.pendentes, 0);
    });

    test('sobrevive a fechar o app: o que estava pendente volta', () async {
      await fila.enfileirar(presenca(true));
      final outra = FilaDeEnvio(
        executores: {},
        estaOnline: () => false,
        agora: () => agora,
      );
      await outra.carregar();
      expect(outra.pendentes, 1);
      expect(outra.itens.single.dados['userId'], 'u1');
    });

    test('item que não se lê não derruba a fila inteira', () async {
      await Armazem.gravar(FilaDeEnvio.chaveNoArmazem,
          '[{"id":"x","tipo":"inexistente"},{"lixo":true}]');
      await fila.carregar();
      expect(fila.pendentes, 0);
    });
  });

  group('a faixa de rede só fala quando faz diferença', () {
    final agora = DateTime(2026, 11, 20, 12);

    test('com internet e nada pendente: NADA', () {
      expect(textoDaFaixa(const SituacaoDaRede(online: true), agora), isNull);
    });

    test('offline há poucos segundos (elevador, troca de wi-fi): nada', () {
      final s = SituacaoDaRede(
          online: false,
          offlineDesde: agora.subtract(const Duration(seconds: 4)));
      expect(textoDaFaixa(s, agora), isNull);
    });

    test('offline de verdade: diz que está sem internet e que o app mostra o '
        'que já baixou', () {
      final s = SituacaoDaRede(
          online: false,
          offlineDesde: agora.subtract(const Duration(minutes: 1)));
      expect(textoDaFaixa(s, agora), contains('Sem internet'));
      expect(textoDaFaixa(s, agora), contains('o que já baixou'));
    });

    test('"atualizado há X" só quando já é velho o bastante para importar', () {
      SituacaoDaRede com(Duration idade) => SituacaoDaRede(
          online: false,
          offlineDesde: agora.subtract(const Duration(minutes: 1)),
          ultimaConferencia: agora.subtract(idade));
      expect(textoDaFaixa(com(const Duration(minutes: 5)), agora),
          isNot(contains('Atualizado')));
      expect(textoDaFaixa(com(const Duration(hours: 3)), agora),
          contains('Atualizado há 3 h.'));
      expect(textoDaFaixa(com(const Duration(days: 2)), agora),
          contains('Atualizado há 2 dias.'));
    });

    test('offline com ações esperando: diz quantas', () {
      final s = SituacaoDaRede(
          online: false,
          offlineDesde: agora.subtract(const Duration(minutes: 1)),
          pendentes: 2);
      expect(textoDaFaixa(s, agora), contains('2 alterações suas esperam'));
    });

    test('com internet, só avisa envio se demorar além do normal', () {
      SituacaoDaRede com(Duration h) => SituacaoDaRede(
          online: true, pendentes: 1, pendenteDesde: agora.subtract(h));
      expect(textoDaFaixa(com(const Duration(seconds: 1)), agora), isNull);
      expect(textoDaFaixa(com(const Duration(seconds: 8)), agora),
          'Enviando 1 alteração…');
    });
  });

  group('orçamento de leituras', () {
    final manha = DateTime(2026, 11, 20, 9);

    test('cada aparelho tem uma cota por dia, e gastar a reduz', () {
      var o = OrcamentoDeLeituras(
          dia: OrcamentoDeLeituras.diaDe(manha), gasto: 0);
      expect(o.restante(manha), OrcamentoDeLeituras.limiteDiario);
      o = o.gastando(100, manha);
      expect(o.restante(manha), OrcamentoDeLeituras.limiteDiario - 100);
    });

    test('nunca fica negativo', () {
      final o = OrcamentoDeLeituras(
          dia: OrcamentoDeLeituras.diaDe(manha), gasto: 9999);
      expect(o.restante(manha), 0);
    });

    test('o dia seguinte recomeça a conta, inclusive na virada de ano', () {
      final o = OrcamentoDeLeituras(
          dia: OrcamentoDeLeituras.diaDe(DateTime(2026, 12, 31, 23, 59)),
          gasto: 250);
      expect(o.restante(DateTime(2026, 12, 31, 23, 59)), 0);
      expect(o.restante(DateTime(2027, 1, 1, 0, 1)),
          OrcamentoDeLeituras.limiteDiario);
    });

    test('vai e volta de JSON', () {
      final o = OrcamentoDeLeituras(dia: '2026-11-20', gasto: 37);
      final de = OrcamentoDeLeituras.fromJson(o.toJson(), manha);
      expect(de.gasto, 37);
      expect(de.dia, '2026-11-20');
    });
  });

  group('dados apagados pelo aparelho', () {
    test('as duas marcas: tudo certo', () {
      expect(
          conferirMarcas(marcaNoLocalStorage: true, marcaNoArmazem: true),
          VereditoDoAparelho.tudoCerto);
    });
    test('nenhuma: primeira vez (ou tudo apagado — o caminho é o mesmo)', () {
      expect(
          conferirMarcas(marcaNoLocalStorage: false, marcaNoArmazem: false),
          VereditoDoAparelho.primeiraVez);
    });
    test('só uma: o navegador apagou um dos lugares', () {
      expect(
          conferirMarcas(marcaNoLocalStorage: true, marcaNoArmazem: false),
          VereditoDoAparelho.dadosApagados);
      expect(
          conferirMarcas(marcaNoLocalStorage: false, marcaNoArmazem: true),
          VereditoDoAparelho.dadosApagados);
    });
  });
}
