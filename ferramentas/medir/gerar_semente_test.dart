// Gera os dados de um ministério do tamanho do de verdade, para medir a
// abertura do app contra o emulador do Firebase.
//
//   SEMENTE_EM=/tmp/semente.json flutter test ferramentas/medir/gerar_semente_test.dart
//
// COMO FUNCIONA
//
// Os documentos saem dos PRÓPRIOS modelos do app (`toFirestore`), e não de um
// JSON escrito à mão: se o modelo mudar, a semente muda junto, e o emulador
// nunca guarda um formato que o app não leria. `Timestamp` vira
// `{"$ts": "<ISO em UTC>"}`; quem grava (`semear.mjs`) o devolve ao formato do
// Firestore.
//
// O TAMANHO é o do ministério, medido numa rodada anterior: 16 pessoas, 42
// músicas, ~109 cultos dentro da janela de leitura (60 dias para trás, 90 para
// a frente), 50 mensagens e 3 equipes.
//
// Todo texto é inventado. Fica fora de `test/` para não rodar a cada commit.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/data/models/message_model.dart';
import 'package:levitasync/data/models/scale_model.dart';
import 'package:levitasync/data/models/song_model.dart';
import 'package:levitasync/data/models/team_model.dart';
import 'package:levitasync/data/models/user_model.dart';

import '../../test/utilitarios/dados_inventados.dart';

/// Troca `Timestamp` por `{"$ts": ...}` em qualquer profundidade.
Object? _jsonavel(Object? v) {
  if (v is Timestamp) return {r'$ts': v.toDate().toUtc().toIso8601String()};
  if (v is Map) return {for (final e in v.entries) '${e.key}': _jsonavel(e.value)};
  if (v is Iterable) return [for (final e in v) _jsonavel(e)];
  return v;
}

void main() {
  final saida = Platform.environment['SEMENTE_EM'];
  if (saida == null) {
    test('semente', () {}, skip: 'defina SEMENTE_EM=<arquivo.json>');
    return;
  }

  test('gera a semente', () {
    final agora = DateTime.now();
    final docs = <Map<String, Object?>>[];
    void doc(String caminho, Map<String, dynamic> dados) =>
        docs.add({'path': caminho, 'data': _jsonavel(dados)});

    // ── 16 pessoas (a primeira é quem entra no app) ─────────────────────────
    const nomes = [
      'Marcio Teste', 'Bruno Lima', 'Carla Dias', 'Davi Rocha', 'Elisa Prado',
      'Fábio Nunes', 'Gabriela Alves', 'Hugo Matos', 'Isabela Reis',
      'João Pires', 'Karen Souza', 'Lucas Melo', 'Marta Ramos', 'Nathan Cruz',
      'Olívia Teles', 'Paulo Vaz',
    ];
    const funcoes = [
      UserInstrument.vocalist, UserInstrument.guitar, UserInstrument.keyboard,
      UserInstrument.bass, UserInstrument.vocalist, UserInstrument.drums,
    ];
    final pessoas = <UserModel>[
      for (var i = 0; i < nomes.length; i++)
        UserModel(
          id: 'u${i + 1}',
          name: nomes[i],
          email: UserModel.emailForName(nomes[i]),
          role: i == 0 ? UserRole.admin : UserRole.levita,
          instrument: funcoes[i % funcoes.length],
          createdAt: DateTime(2026, 1, 1),
          recuperacaoPorEmail: true,
        ),
    ];
    for (final p in pessoas) {
      doc('users/${p.id}', p.toFirestore());
    }

    // ── 42 músicas ──────────────────────────────────────────────────────────
    final base = repertorioInventado();
    final musicas = <SongModel>[
      ...base,
      for (var i = base.length; i < 42; i++)
        SongModel(
          id: 'm$i',
          name: 'Música ${tituloInventado(i)}',
          artist: i.isEven ? 'Coral Aurora' : 'Banda Jardim',
          lyrics: letraInventada(i),
          originalKey: const ['C', 'D', 'E', 'G', 'A'][i % 5],
          createdAt: DateTime(2026, 1, 1),
          addedBy: 'u1',
        ),
    ];
    for (final m in musicas) {
      doc('songs/${m.id}', m.toFirestore());
    }

    // ── cultos: a rotina da igreja, dentro da janela de leitura ─────────────
    // Quarta 8h e 19h30, sexta 19h30, domingo 8h e 19h.
    const rotina = <int, List<(int, int)>>{
      DateTime.wednesday: [(8, 0), (19, 30)],
      DateTime.friday: [(19, 30)],
      DateTime.sunday: [(8, 0), (19, 0)],
    };
    var n = 0;
    for (var d = -60; d <= 90; d++) {
      final dia = DateTime(agora.year, agora.month, agora.day)
          .add(Duration(days: d));
      for (final (h, m) in rotina[dia.weekday] ?? const <(int, int)>[]) {
        final quando = DateTime(dia.year, dia.month, dia.day, h, m);
        final gente = [
          for (var k = 0; k < 6; k++)
            ScaleLevita(
              userId: 'u${(n + k) % 16 + 1}',
              userName: nomes[(n + k) % 16],
              instrument: funcoes[k % funcoes.length].name,
              confirmed: k.isEven,
            ),
        ];
        final culto = ScaleModel(
          id: ScaleModel.idPara(quando),
          date: quando,
          serviceType: h == 8 ? 'Culto da manhã' : 'Culto da noite',
          levitas: gente,
          songs: [
            for (var k = 0; k < 4; k++) ScaleSong(songId: musicas[(n * 3 + k) % 42].id),
          ],
          observations: n % 5 == 0 ? 'Entra sem bateria na segunda música.' : '',
          createdBy: 'u1',
          createdAt: DateTime(2026, 1, 1),
        );
        doc('scales/${culto.id}', culto.toFirestore());
        n++;
      }
    }

    // ── 50 mensagens ────────────────────────────────────────────────────────
    for (var i = 0; i < 50; i++) {
      final autor = i % 16;
      final msg = MessageModel(
        id: 'c$i',
        userId: 'u${autor + 1}',
        userName: nomes[autor],
        text: 'Mensagem ${50 - i}: combinado do ensaio e do culto.',
        timestamp: agora.subtract(Duration(minutes: 30 * (i + 1))),
        expiraEm: agora.add(const Duration(days: 25)),
      );
      doc('messages/${msg.id}', msg.toFirestore());
    }

    // ── 3 equipes ───────────────────────────────────────────────────────────
    for (var t = 0; t < 3; t++) {
      final equipe = TeamModel(
        id: 'eq$t',
        name: const ['Equipe Manhã', 'Equipe Noite', 'Equipe Quarta'][t],
        members: [
          for (var k = 0; k < 6; k++)
            TeamMember(
                userId: 'u${(t * 5 + k) % 16 + 1}',
                instrument: funcoes[k % funcoes.length].name),
        ],
        createdBy: 'u1',
        updatedAt: DateTime(2026, 1, 1),
      );
      doc('teams/${equipe.id}', equipe.toFirestore());
    }

    File(saida).writeAsStringSync(jsonEncode({
      'entrar': {
        'id': 'u1',
        'nome': nomes[0],
        'email': UserModel.emailForName(nomes[0]),
        'senha': 'senha-de-teste-123',
      },
      'docs': docs,
    }));
    // ignore: avoid_print
    print('semente: ${docs.length} documentos em $saida');
  });
}
