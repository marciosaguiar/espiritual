// Os dados com que o roteiro de captura enche o app.
//
// TUDO AQUI É INVENTADO. Nenhuma letra, título de hino ou nome de pessoa é de
// verdade: o texto dos hinários não pode morar no repositório (ver "Hinário
// com letra" no CLAUDE.md), e as fotos das telas ficam em páginas de entrega.
// Os títulos dos hinos saem de duas listas de palavras, para a lista de 640
// parecer uma lista de hinos sem ser a de ninguém.

import 'package:levitasync/data/models/hino_da_biblioteca.dart';
import 'package:levitasync/data/models/message_model.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/song_model.dart';
import 'package:levitasync/data/models/user_model.dart';

const _sujeitos = [
  'Manhã',
  'Fonte',
  'Caminho',
  'Rocha',
  'Luz',
  'Promessa',
  'Colheita',
  'Vigia',
  'Aurora',
  'Descanso',
  'Jardim',
  'Cântico',
  'Porto',
  'Ponte',
  'Estrela',
];

const _complementos = [
  'de graça',
  'que sustenta',
  'da esperança',
  'no deserto',
  'de paz',
  'dos humildes',
  'sem fim',
  'da aliança',
  'do pastor',
  'que não falha',
  'da fidelidade',
  'sobre as águas',
];

/// Título inventado e estável para o hino [n] — o mesmo número dá sempre o
/// mesmo título, para duas fotos da mesma tela saírem iguais.
String tituloInventado(int n) {
  final s = _sujeitos[(n * 7) % _sujeitos.length];
  final c = _complementos[(n * 5 + n ~/ 13) % _complementos.length];
  return '$s $c';
}

/// O índice de uma biblioteca com [total] hinos.
IndiceDoHinario indiceInventado(String hinario, int total) => IndiceDoHinario(
      hinario: hinario,
      titulos: {for (var n = 1; n <= total; n++) n: tituloInventado(n)},
    );

/// A letra de um hino, inventada. Três estrofes e um refrão.
String letraInventada(int n) {
  final t = tituloInventado(n);
  return '1 O $t nos acompanha,\n'
      'em cada manhã de luz;\n'
      'a fidelidade não muda\n'
      'e o amor nos conduz.\n\n'
      'REFRÃO\n'
      'Firmes na promessa, firmes,\n'
      'cantamos de coração;\n'
      'o Senhor é a nossa rocha\n'
      'e a nossa canção.\n\n'
      '2 Se vier a noite escura,\n'
      'não vamos desanimar;\n'
      'quem guarda o seu povo vela\n'
      'e não deixa de amparar.';
}

final _agora = DateTime.now();
final _desde = DateTime(2026, 1, 1);

UserModel pessoa(
  String id,
  String nome, {
  UserRole role = UserRole.levita,
  UserInstrument instrumento = UserInstrument.other,
  List<UserInstrument>? funcoes,
}) =>
    UserModel(
      id: id,
      name: nome,
      role: role,
      instrument: instrumento,
      instruments: funcoes,
      createdAt: _desde,
      recuperacaoPorEmail: true,
    );

final lider = pessoa('u1', 'Ana Souza',
    role: UserRole.admin, instrumento: UserInstrument.vocalist);

final ministerio = <UserModel>[
  lider,
  pessoa('u2', 'Bruno Lima', instrumento: UserInstrument.guitar),
  pessoa('u3', 'Carla Dias', instrumento: UserInstrument.keyboard),
  pessoa('u4', 'Davi Rocha', instrumento: UserInstrument.bass),
  pessoa('u5', 'Elisa Prado', instrumento: UserInstrument.vocalist),
  pessoa('u6', 'Fábio Nunes', instrumento: UserInstrument.drums),
];

/// O repertório: músicas comuns e alguns hinos já postos nele.
List<SongModel> repertorioInventado() {
  const nomes = [
    ['Grande é a tua fidelidade', 'Coral Aurora', 'G'],
    ['Porto seguro', 'Ministério Vigia', 'D'],
    ['Rocha firme', 'Ministério Vigia', 'A'],
    ['Cântico da manhã', 'Banda Jardim', 'C'],
    ['Descanso nas águas', 'Banda Jardim', 'E'],
    ['Aliança eterna', 'Coral Aurora', 'F'],
    ['Quem guarda o seu povo', 'Davi Lima', 'Bb'],
    ['Luz no caminho', 'Elisa Prado', 'D'],
    ['Colheita de paz', 'Coral Aurora', 'G'],
    ['Estrela da esperança', 'Banda Jardim', 'A'],
    ['Ponte sobre o rio', 'Ministério Vigia', 'C'],
    ['Fonte que não seca', 'Elisa Prado', 'E'],
  ];
  final saida = <SongModel>[
    for (var i = 0; i < nomes.length; i++)
      SongModel(
        id: 'm$i',
        name: nomes[i][0],
        artist: nomes[i][1],
        lyrics: letraInventada(100 + i),
        originalKey: nomes[i][2],
        createdAt: _desde,
        addedBy: 'u1',
      ),
  ];
  for (final n in const [15, 65, 150, 301]) {
    saida.add(SongModel(
      id: 'h$n',
      name: 'HC $n · ${tituloInventado(n)}',
      artist: 'Harpa Cristã',
      lyrics: letraInventada(n),
      originalKey: 'G',
      createdAt: _desde,
      addedBy: 'u1',
      hinario: 'harpa',
      numero: n,
    ));
  }
  return saida;
}

/// Cultos da semana que vem, com gente escalada e músicas.
List<ScaleModel> cultosInventados() {
  DateTime dia(int daqui, int hora, int minuto) {
    final d = _agora.add(Duration(days: daqui));
    return DateTime(d.year, d.month, d.day, hora, minuto);
  }

  ScaleModel culto(DateTime quando, String tipo, List<ScaleLevita> gente,
      List<String> musicas, {String obs = ''}) {
    return ScaleModel(
      id: ScaleModel.idPara(quando),
      date: quando,
      serviceType: tipo,
      levitas: gente,
      songs: [for (final m in musicas) ScaleSong(songId: m)],
      observations: obs,
      createdBy: 'u1',
      createdAt: _desde,
    );
  }

  const ana = ScaleLevita(
      userId: 'u1', userName: 'Ana Souza', instrument: 'vocalist', confirmed: true);
  const bruno = ScaleLevita(
      userId: 'u2', userName: 'Bruno Lima', instrument: 'guitar', confirmed: true);
  const carla = ScaleLevita(
      userId: 'u3', userName: 'Carla Dias', instrument: 'keyboard');
  const davi =
      ScaleLevita(userId: 'u4', userName: 'Davi Rocha', instrument: 'bass');
  const elisa = ScaleLevita(
      userId: 'u5', userName: 'Elisa Prado', instrument: 'vocalist', confirmed: true);

  return [
    culto(dia(1, 19, 30), 'Culto de quarta', [ana, bruno, carla, davi],
        ['m0', 'm2', 'h15'],
        obs: 'Entra sem bateria na segunda música.'),
    culto(dia(3, 8, 0), 'Culto da manhã', [ana, bruno, elisa], ['m1', 'm3']),
    culto(dia(3, 19, 0), 'Culto da noite', [ana, carla, davi, elisa],
        ['m4', 'm5', 'h65']),
    culto(dia(8, 19, 30), 'Culto de quarta', const [], const []),
    culto(dia(10, 8, 0), 'Culto da manhã', [bruno, carla], ['m6']),
  ];
}

List<MessageModel> conversaInventada() {
  MessageModel m(int minutosAtras, String id, String nome, String texto,
          {bool fixada = false}) =>
      MessageModel(
        id: 'c$minutosAtras',
        userId: id,
        userName: nome,
        text: texto,
        timestamp: _agora.subtract(Duration(minutes: minutosAtras)),
        fixada: fixada,
        expiraEm: fixada ? null : _agora.add(const Duration(days: 30)),
      );
  return [
    m(2900, 'u1', 'Ana Souza',
        'Ensaio sábado às 16h, na sala de cima. Quem puder, chega 15 min antes.',
        fixada: true),
    m(180, 'u2', 'Bruno Lima', 'Bom dia, pessoal! Alguém leva o cabo extra?'),
    m(165, 'u4', 'Davi Rocha', 'Eu levo. Já deixo no carro.'),
    m(140, 'u3', 'Carla Dias',
        'Preciso trocar o teclado de lugar no domingo, posso chegar mais cedo?'),
    m(122, 'u1', 'Ana Souza', 'Pode sim, a igreja abre às 7h.'),
    m(60, 'u5', 'Elisa Prado',
        'A segunda música ficou alta demais para mim. Dá para baixar um tom?'),
    m(41, 'u1', 'Ana Souza', 'Dá. Troco no culto de quarta e aviso aqui.'),
    m(12, 'u6', 'Fábio Nunes', 'Combinado 👍'),
  ];
}
