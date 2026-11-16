import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/song_model.dart';
import '../models/arrangement_model.dart';
import '../models/team_model.dart';
import '../models/scale_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import 'auth_service.dart';
import '../../core/utils/crypto_utils.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Collections ──────────────────────────────────────────────────────────
  static const String _songs = 'songs';
  static const String _scales = 'scales';
  static const String _messages = 'messages';

  // ─── SONGS ────────────────────────────────────────────────────────────────

  /// Ordena no app, não no banco.
  ///
  /// `orderBy('name')` no Firestore descarta em silêncio todo documento que
  /// não tenha o campo `name` — a música simplesmente não existiria para o
  /// app, sem erro nenhum. Ordenar aqui custa nada nesta escala e faz uma
  /// música torta aparecer (ainda que sem nome) em vez de sumir.
  static Stream<List<SongModel>> watchSongs() {
    return _db.collection(_songs).snapshots().map((snap) {
      final songs = snap.docs
          .map((doc) => SongModel.fromFirestore(doc.data()))
          .toList();
      songs.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return songs;
    });
  }

  static Future<List<SongModel>> getSongs() async {
    final snap = await _db.collection(_songs).orderBy('name').get();
    return snap.docs.map((doc) => SongModel.fromFirestore(doc.data())).toList();
  }

  static Future<SongModel?> getSongById(String id) async {
    try {
      final doc = await _db.collection(_songs).doc(id).get();
      if (!doc.exists) return null;
      return SongModel.fromFirestore(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  static Future<({bool success, String? error})> addSong(SongModel song) async {
    try {
      await _db.collection(_songs).doc(song.id).set(song.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'salvar a música'));
    } catch (e) {
      return (success: false, error: 'Não foi possível salvar a música: $e');
    }
  }

  static Future<({bool success, String? error})> updateSong(
      SongModel song) async {
    try {
      await _db.collection(_songs).doc(song.id).update(song.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'alterar a música'));
    } catch (e) {
      return (success: false, error: 'Não foi possível alterar a música: $e');
    }
  }

  /// Tira a música do repertório sem apagar nada.
  ///
  /// O documento fica: é o que mantém o nome dela nos cultos em que foi
  /// tocada, em vez de "Música removida", e é o que permite desfazer. Apagar
  /// de verdade não existe mais no app — as regras recusam `delete` em
  /// `songs` para todo mundo, líder incluído. Isso só pelo console.
  static Future<({bool success, String? error})> arquivarSong(
    String songId,
    String porQuemId,
  ) async {
    try {
      await _db.collection(_songs).doc(songId).update({
        'archived': true,
        'archivedAt': FieldValue.serverTimestamp(),
        'archivedBy': porQuemId,
      });
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: 'Não foi possível tirar do repertório: ${e.message}'
      );
    }
  }

  /// Devolve a música ao repertório, limpando o carimbo.
  static Future<({bool success, String? error})> desarquivarSong(
      String songId) async {
    try {
      await _db.collection(_songs).doc(songId).update({
        'archived': false,
        'archivedAt': null,
        'archivedBy': null,
      });
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: 'Não foi possível devolver ao repertório: ${e.message}'
      );
    }
  }

  static SongModel createSongModel({
    required String name,
    required String artist,
    required String lyrics,
    required String originalKey,
    List<SongLink> links = const [],
    String? addedBy,
  }) {
    return SongModel(
      id: CryptoUtils.generateId(),
      name: name,
      artist: artist,
      lyrics: lyrics,
      originalKey: originalKey,
      links: links,
      addedBy: addedBy,
      createdAt: DateTime.now(),
    );
  }

  // ─── ARRANGEMENTS ─────────────────────────────────────────────────────────
  // How this church plays a song. A subcollection of the song, so the chart is
  // fetched only when somebody opens that song.

  static CollectionReference<Map<String, dynamic>> _arrangementsOf(
          String songId) =>
      _db.collection(_songs).doc(songId).collection('arrangements');

  static Future<List<ArrangementModel>> getArrangements(String songId) async {
    try {
      final snap = await _arrangementsOf(songId).get();
      return snap.docs
          .map((d) => ArrangementModel.fromFirestore(d.data()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The arrangement to show: the one asked for, else the first available.
  static Future<ArrangementModel?> getArrangement(
    String songId, {
    String arrangementId = '',
  }) async {
    try {
      if (arrangementId.isNotEmpty) {
        final doc = await _arrangementsOf(songId).doc(arrangementId).get();
        if (doc.exists) return ArrangementModel.fromFirestore(doc.data()!);
      }
      final snap = await _arrangementsOf(songId).limit(1).get();
      if (snap.docs.isEmpty) return null;
      return ArrangementModel.fromFirestore(snap.docs.first.data());
    } catch (_) {
      return null;
    }
  }

  static Future<({bool success, String? error, ArrangementModel? arrangement})>
      saveArrangement(ArrangementModel arrangement) async {
    try {
      await _arrangementsOf(arrangement.songId)
          .doc(arrangement.id)
          .set(arrangement.toFirestore());
      return (success: true, error: null, arrangement: arrangement);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: _describe(e, 'salvar o arranjo'),
        arrangement: null
      );
    }
  }

  static ArrangementModel createArrangementModel({
    required String songId,
    required String churchKey,
    String name = 'Padrão',
    String chords = '',
    int bpm = 0,
    String notes = '',
    String? approvedBy,
  }) {
    return ArrangementModel(
      id: CryptoUtils.generateId(),
      songId: songId,
      name: name,
      churchKey: churchKey,
      chords: chords,
      bpm: bpm,
      notes: notes,
      approvedBy: approvedBy,
      updatedAt: DateTime.now(),
    );
  }

  // ─── PERSONAL PREFERENCES ─────────────────────────────────────────────────
  // users/{userId}/songPrefs/{songId} — private to each musician.

  static CollectionReference<Map<String, dynamic>> _prefsOf(String userId) =>
      _db.collection('users').doc(userId).collection('songPrefs');

  static Future<SongPrefModel?> getSongPref(String userId, String songId) async {
    try {
      final doc = await _prefsOf(userId).doc(songId).get();
      if (!doc.exists) return null;
      return SongPrefModel.fromFirestore(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, SongPrefModel>> getAllSongPrefs(
      String userId) async {
    try {
      final snap = await _prefsOf(userId).get();
      return {
        for (final d in snap.docs)
          d.id: SongPrefModel.fromFirestore(d.data()),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<({bool success, String? error})> saveSongPref(
    String userId,
    SongPrefModel pref,
  ) async {
    try {
      if (pref.isEmpty) {
        await _prefsOf(userId).doc(pref.songId).delete();
      } else {
        await _prefsOf(userId).doc(pref.songId).set(pref.toFirestore());
      }
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'salvar sua preferência'));
    }
  }

  /// Turns a Firebase failure into a sentence a person can act on.
  static String _describe(FirebaseException e, String acao) {
    switch (e.code) {
      case 'permission-denied':
        return 'Você não tem permissão para $acao.';
      case 'unavailable':
        return 'Sem conexão. Não foi possível $acao.';
      case 'not-found':
        return 'O item não existe mais.';
      default:
        return 'Não foi possível $acao: ${e.message ?? e.code}';
    }
  }

  // ─── SCALES ───────────────────────────────────────────────────────────────

  /// How far back and forward the app keeps services in memory.
  ///
  /// The standing schedule produces about five services a week — roughly 260
  /// a year — and the app used to read the whole collection on every start.
  /// The window bounds that to about a hundred documents, for ever.
  static const Duration janelaPassado = Duration(days: 60);
  static const Duration janelaFuturo = Duration(days: 90);

  static DateTime get _inicioDaJanela {
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month, agora.day)
        .subtract(janelaPassado);
  }

  static DateTime get _fimDaJanela => DateTime.now().add(janelaFuturo);

  static Stream<List<ScaleModel>> watchScales() {
    return _db
        .collection(_scales)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_inicioDaJanela))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_fimDaJanela))
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ScaleModel.fromFirestore(doc.data()))
            .toList());
  }

  static Future<List<ScaleModel>> getScales() async {
    final snap = await _db
        .collection(_scales)
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_inicioDaJanela))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_fimDaJanela))
        .orderBy('date')
        .get();
    return snap.docs
        .map((doc) => ScaleModel.fromFirestore(doc.data()))
        .toList();
  }

  static Future<ScaleModel?> getScaleForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final snap = await _db
        .collection(_scales)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ScaleModel.fromFirestore(snap.docs.first.data());
  }

  static Future<List<ScaleModel>> getUpcomingScales({int limit = 5}) async {
    final now = DateTime.now();
    final snap = await _db
        .collection(_scales)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('date')
        .limit(limit)
        .get();
    return snap.docs
        .map((doc) => ScaleModel.fromFirestore(doc.data()))
        .toList();
  }

  static Future<({bool success, String? error})> createScale(
      ScaleModel scale) async {
    try {
      await _db.collection(_scales).doc(scale.id).set(scale.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'criar o culto'));
    } catch (e) {
      return (success: false, error: 'Não foi possível criar o culto: $e');
    }
  }

  static Future<({bool success, String? error})> deleteScale(
      String scaleId) async {
    try {
      await _db.collection(_scales).doc(scaleId).delete();
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'apagar o culto'));
    } catch (e) {
      return (success: false, error: 'Não foi possível apagar o culto: $e');
    }
  }

  /// Confirms or cancels one person's presence, inside a transaction.
  ///
  /// This used to read the whole `levitas` list, change one entry and write
  /// the list back. Between the read and the write anybody else's confirmation
  /// was lost — on a Sunday morning, with several people confirming at once,
  /// which is exactly when the screen is used. The transaction re-reads inside
  /// the write and Firestore retries it if the document changed meanwhile, so
  /// only this person's entry moves.
  static Future<({bool success, String? error})> confirmPresence(
    String scaleId,
    String userId,
    bool confirmed,
  ) async {
    final ref = _db.collection(_scales).doc(scaleId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'levitasync',
            code: 'not-found',
            message: 'culto não encontrado',
          );
        }

        final scale = ScaleModel.fromFirestore(snap.data()!);
        if (!scale.isUserInScale(userId)) {
          throw FirebaseException(
            plugin: 'levitasync',
            code: 'not-scheduled',
            message: 'você não está nesta escala',
          );
        }

        final levitas = scale.levitas
            .map((l) => l.userId == userId
                ? l.copyWith(confirmed: confirmed)
                : l)
            .map((l) => l.toMap())
            .toList();

        // Only this field is written, so nothing else in the service is
        // touched, and the security rules allow it for a levita.
        tx.update(ref, {'levitas': levitas});
      });
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      if (e.code == 'not-scheduled') {
        return (success: false, error: 'Você não está escalado neste culto.');
      }
      return (success: false, error: _describe(e, 'confirmar sua presença'));
    }
  }

  /// Replaces the song list of a service, inside a transaction.
  ///
  /// Writes only `songs`, so a leader rearranging the repertoire no longer
  /// overwrites confirmations somebody is giving at the same moment.
  static Future<({bool success, String? error})> setScaleSongs(
    String scaleId,
    List<ScaleSong> songs,
  ) async {
    return _updateScaleField(
      scaleId,
      'o repertório do culto',
      (scale) => {
        'songs': songs.map((s) => s.toMap()).toList(),
        ..._marcaEdicaoManual(scale),
      },
    );
  }

  /// Marks a generated service as touched by hand, so reapplying a team later
  /// leaves it alone. One-off services need no mark: nothing bulk-updates them.
  static Map<String, dynamic> _marcaEdicaoManual(ScaleModel scale) {
    if (!scale.daAgendaFixa || scale.manuallyEdited) return const {};
    return const {'manuallyEdited': true};
  }

  /// Adds one song to the end of a service's list, inside a transaction.
  ///
  /// Used by the chat's "add to the service". Reading the list inside the
  /// transaction is what makes two leaders adding at the same time end up with
  /// both songs instead of one.
  static Future<({bool success, String? error})> addSongToScale(
    String scaleId,
    ScaleSong song,
  ) async {
    return _updateScaleField(scaleId, 'adicionar a música ao culto', (scale) {
      if (scale.songs.any((s) => s.songId == song.songId)) {
        // Already there: nothing to write.
        return null;
      }
      final songs = [...scale.songs, song];
      return {
        'songs': songs.map((s) => s.toMap()).toList(),
        ..._marcaEdicaoManual(scale),
      };
    });
  }

  /// Replaces who is scheduled, inside a transaction.
  ///
  /// Confirmations already given are kept: somebody who stays on the list
  /// keeps their answer instead of being reset to "not confirmed".
  static Future<({bool success, String? error})> setScaleLevitas(
    String scaleId,
    List<ScaleLevita> levitas,
  ) async {
    return _updateScaleField(scaleId, 'a escala de levitas', (scale) {
      final previous = {for (final l in scale.levitas) l.userId: l.confirmed};
      final merged = levitas
          .map((l) => l.copyWith(confirmed: previous[l.userId] ?? l.confirmed))
          .map((l) => l.toMap())
          .toList();
      // Mexer na escalação é o gesto de "já vi e resolvi": é aqui que o
      // aviso de quem foi removido some.
      return {
        'levitas': merged,
        if (scale.faltando.isNotEmpty) 'faltando': <String>[],
        ..._marcaEdicaoManual(scale),
      };
    });
  }

  /// Changes the service's own fields (date, type, notes), inside a
  /// transaction, without touching the song or levita lists.
  static Future<({bool success, String? error})> updateScaleDetails(
    String scaleId, {
    DateTime? date,
    String? serviceType,
    String? observations,
  }) async {
    return _updateScaleField(scaleId, 'os dados do culto', (scale) {
      final data = <String, dynamic>{};
      if (date != null) data['date'] = Timestamp.fromDate(date);
      if (serviceType != null) data['serviceType'] = serviceType;
      if (observations != null) data['observations'] = observations;
      if (data.isEmpty) return null;
      return {...data, ..._marcaEdicaoManual(scale)};
    });
  }

  /// Shared shape of every change above: read the service inside the
  /// transaction, work out the fields to write from what is actually stored,
  /// and write only those.
  ///
  /// [build] returning null means "nothing to do".
  static Future<({bool success, String? error})> _updateScaleField(
    String scaleId,
    String acao,
    Map<String, dynamic>? Function(ScaleModel current) build,
  ) async {
    final ref = _db.collection(_scales).doc(scaleId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'levitasync',
            code: 'not-found',
            message: 'culto não encontrado',
          );
        }
        final data = build(ScaleModel.fromFirestore(snap.data()!));
        if (data == null || data.isEmpty) return;
        tx.update(ref, data);
      });
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, acao));
    }
  }

  static ScaleModel createScaleModel({
    required DateTime date,
    String serviceType = 'Culto',
    String? createdBy,
  }) {
    return ScaleModel(
      id: CryptoUtils.generateId(),
      date: date,
      serviceType: serviceType,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
  }

  // ─── MEMBERSHIP: REMOVING AND RESTORING ───────────────────────────────────

  /// Takes someone out of the ministry.
  ///
  /// "Remove" here means revoking access, never deleting. Two reasons, and
  /// only the first is a choice: the Firebase account itself can only be
  /// deleted with the Admin SDK on a server, which needs the paid plan this
  /// project deliberately stays off; and the history — who played where, who
  /// said what in the chat — belongs to the ministry, not to the membership.
  ///
  /// Everything happens inside ONE transaction, so the person is never left
  /// half out: still on a team but with no access, or the other way round.
  /// The transaction re-reads each team and service as it runs, and writes
  /// back only the field it owns (`members`, `levitas`), so a confirmation
  /// someone taps during these few hundred milliseconds is not thrown away.
  ///
  /// Past services keep the person: they played there, and rewriting that
  /// would be rewriting history. Only services from now on are cleaned.
  static Future<({bool success, String? error})> removerDoMinisterio({
    required UserModel alvo,
    required String porQuemId,
    required List<TeamModel> equipes,
    required List<ScaleModel> escalas,
  }) async {
    // A contagem de líderes mora no AuthService, junto com a mesma checagem
    // que já existe para rebaixar alguém. Repeti-la aqui seria ter duas
    // verdades sobre quando o ministério fica sem líder.
    if (alvo.isAdmin && await AuthService.adminCount() <= 1) {
      return (
        success: false,
        error: 'O ministério precisa de pelo menos um líder. '
            'Promova outra pessoa antes.'
      );
    }

    final agora = DateTime.now();
    final idsEquipes = equipes
        .where((e) => e.members.any((m) => m.userId == alvo.id))
        .map((e) => e.id)
        .toList();
    final idsEscalas = escalas
        .where((s) =>
            s.date.isAfter(agora) && s.levitas.any((l) => l.userId == alvo.id))
        .map((s) => s.id)
        .toList();

    try {
      await _db.runTransaction((tx) async {
        final refUser = _db.collection('users').doc(alvo.id);
        final refsEquipes =
            idsEquipes.map((id) => _db.collection(_teams).doc(id)).toList();
        final refsEscalas =
            idsEscalas.map((id) => _db.collection(_scales).doc(id)).toList();

        // O Firestore exige TODAS as leituras antes de qualquer escrita.
        final equipesLidas = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final ref in refsEquipes) {
          equipesLidas.add(await tx.get(ref));
        }
        final escalasLidas = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final ref in refsEscalas) {
          escalasLidas.add(await tx.get(ref));
        }

        tx.update(refUser, {
          'role': UserRole.removido.name,
          'removedAt': FieldValue.serverTimestamp(),
          'removedBy': porQuemId,
        });

        for (var i = 0; i < equipesLidas.length; i++) {
          final restantes =
              semAPessoa(equipesLidas[i].data()?['members'], alvo.id);
          if (restantes != null) {
            tx.update(refsEquipes[i], {'members': restantes});
          }
        }
        for (var i = 0; i < escalasLidas.length; i++) {
          final dados = escalasLidas[i].data();
          final restantes = semAPessoa(dados?['levitas'], alvo.id);
          if (restantes == null) continue;
          // Sumir com o nome e não dizer nada deixaria o culto com um
          // instrumento a menos, e o líder só descobriria no domingo.
          final faltando = ((dados?['faltando'] as List?) ?? [])
              .map((e) => '$e')
              .toList();
          if (!faltando.contains(alvo.name)) faltando.add(alvo.name);
          tx.update(refsEscalas[i], {
            'levitas': restantes,
            'faltando': faltando,
          });
        }
      });
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: 'Não foi possível remover do ministério: ${e.message}'
      );
    }
  }

  /// A lista sem a pessoa, ou `null` quando ela não estava lá — e aí não há
  /// escrita nenhuma a fazer.
  ///
  /// Pública e pura de propósito: é a única decisão da remoção que dá para
  /// errar em silêncio (tirar a pessoa errada, ou gravar uma lista igual à
  /// que já estava lá), e dentro da transação ela não teria como ser testada.
  static List<dynamic>? semAPessoa(Object? lista, String userId) {
    if (lista is! List) return null;
    final restantes = lista
        .where((item) => !(item is Map && item['userId'] == userId))
        .toList();
    return restantes.length == lista.length ? null : restantes;
  }

  /// Devolve o acesso de alguém removido: volta como levita, sem equipe.
  ///
  /// Sem equipe de propósito — o líder escala de novo. Readmitir a pessoa
  /// exatamente onde ela estava exigiria guardar de quais equipes ela saiu, e
  /// isso envelhece: a equipe pode nem existir mais quando ela voltar.
  static Future<({bool success, String? error})> devolverAcesso(
      String userId) async {
    try {
      await _db.collection('users').doc(userId).update({
        'role': UserRole.levita.name,
        'removedAt': null,
        'removedBy': null,
      });
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: 'Não foi possível devolver o acesso: ${e.message}'
      );
    }
  }

  // ─── TEAMS AND THE STANDING SCHEDULE ──────────────────────────────────────

  static const String _teams = 'teams';
  static const String _config = 'config';
  static const String _agendaDoc = 'agendaFixa';

  static Stream<List<TeamModel>> watchTeams() {
    return _db.collection(_teams).orderBy('name').snapshots().map(
          (snap) => snap.docs
              .map((d) => TeamModel.fromFirestore(d.data()))
              .toList(),
        );
  }

  static Future<({bool success, String? error})> saveTeam(
      TeamModel team) async {
    try {
      await _db.collection(_teams).doc(team.id).set(team.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'salvar a equipe'));
    }
  }

  static Future<({bool success, String? error})> deleteTeam(
      String teamId) async {
    try {
      await _db.collection(_teams).doc(teamId).delete();
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'apagar a equipe'));
    }
  }

  static TeamModel createTeamModel({
    required String name,
    List<TeamMember> members = const [],
    String? createdBy,
  }) {
    return TeamModel(
      id: CryptoUtils.generateId(),
      name: name,
      members: members,
      createdBy: createdBy,
      updatedAt: DateTime.now(),
    );
  }

  static Stream<FixedSchedule?> watchSchedule() {
    return _db.collection(_config).doc(_agendaDoc).snapshots().map(
          (d) => d.exists ? FixedSchedule.fromFirestore(d.data()!) : null,
        );
  }

  static Future<({bool success, String? error})> saveSchedule(
      FixedSchedule agenda) async {
    try {
      await _db
          .collection(_config)
          .doc(_agendaDoc)
          .set(agenda.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'salvar a agenda fixa'));
    }
  }

  // ─── GENERATING THE NEXT WEEKS ────────────────────────────────────────────

  /// Which services of the next [semanas] weeks do not exist yet.
  ///
  /// Pure on purpose: no Firestore, no clock of its own. All the thinking
  /// that can go wrong — which dates, in which order, what counts as already
  /// there — lives here and is covered by tests; what is left in
  /// [ensureUpcomingServices] is the writing.
  ///
  /// A service already in [existentes] is never proposed again, cancelled
  /// ones included: they exist, and recreating them is exactly what
  /// cancelling must not undo.
  static List<ScaleModel> servicosFaltando({
    required List<ScheduleSlot> slots,
    required Map<String, TeamModel> equipes,
    required List<ScaleModel> existentes,
    required DateTime agora,
    int semanas = 4,
    String? createdBy,
  }) {
    if (slots.isEmpty) return const [];

    final jaExistem = {for (final s in existentes) s.id};
    final limite = agora.add(Duration(days: 7 * semanas));
    final aCriar = <ScaleModel>[];

    for (final slot in slots) {
      var quando = slot.proximaData(agora);
      while (!quando.isAfter(limite)) {
        final id = ScaleModel.idPara(quando);
        // `isAfter(agora)` descarta o culto de hoje que já passou.
        if (quando.isAfter(agora) && !jaExistem.contains(id)) {
          aCriar.add(_servicoDoSlot(slot, quando, id, equipes, createdBy));
          jaExistem.add(id);
        }
        quando = quando.add(const Duration(days: 7));
      }
    }

    aCriar.sort((a, b) => a.date.compareTo(b.date));
    return aCriar;
  }

  /// Creates the services of the next [semanas] weeks that do not exist yet.
  ///
  /// [existentes] are the services the app already holds in memory, so the
  /// check for what is missing costs no extra reads. Each creation runs in a
  /// transaction that first looks for the document: because the id comes from
  /// the date and time, two leaders opening the app at the same moment try to
  /// write the same document, and the second one finds it and does nothing.
  ///
  /// A cancelled service still exists, so it is not recreated — which is why
  /// cancelling is a field and never a deletion.
  static Future<({int criados, String? error})> ensureUpcomingServices({
    required List<ScheduleSlot> slots,
    required Map<String, TeamModel> equipes,
    required List<ScaleModel> existentes,
    int semanas = 4,
    String? createdBy,
  }) async {
    final aCriar = servicosFaltando(
      slots: slots,
      equipes: equipes,
      existentes: existentes,
      agora: DateTime.now(),
      semanas: semanas,
      createdBy: createdBy,
    );

    if (aCriar.isEmpty) return (criados: 0, error: null);

    var criados = 0;
    for (final servico in aCriar) {
      final ref = _db.collection(_scales).doc(servico.id);
      try {
        final novo = await _db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (snap.exists) return false;
          tx.set(ref, servico.toFirestore());
          return true;
        });
        if (novo) criados++;
      } on FirebaseException catch (e) {
        // One failure must not stop the rest: the next start tries again.
        return (criados: criados, error: _describe(e, 'criar os cultos'));
      }
    }
    return (criados: criados, error: null);
  }

  static ScaleModel _servicoDoSlot(
    ScheduleSlot slot,
    DateTime quando,
    String id,
    Map<String, TeamModel> equipes,
    String? createdBy,
  ) {
    final equipe = equipes[slot.teamId];
    return ScaleModel(
      id: id,
      date: quando,
      serviceType: slot.name,
      // Everyone starts unconfirmed: being scheduled is not the same as
      // having said yes.
      levitas: equipe == null
          ? const []
          : equipe.members
              .map((m) => ScaleLevita(
                    userId: m.userId,
                    userName: '',
                    instrument: m.instrument,
                  ))
              .toList(),
      createdBy: createdBy,
      createdAt: DateTime.now(),
      fromSlot: slot.id,
      teamId: slot.teamId,
    );
  }

  /// Puts a team's current line-up back on its future services.
  ///
  /// Skips anything a leader touched by hand and anything already cancelled,
  /// and keeps the answer of whoever was already scheduled and stays — being
  /// re-applied must not wipe a "yes" that was already given.
  static Future<({int atualizados, String? error})> applyTeamToFutureServices({
    required TeamModel equipe,
    required List<ScaleModel> existentes,
  }) async {
    final agora = DateTime.now();
    final alvos = existentes.where((s) =>
        s.teamId == equipe.id &&
        !s.manuallyEdited &&
        !s.canceled &&
        s.date.isAfter(agora));

    var atualizados = 0;
    for (final servico in alvos) {
      final anteriores = {
        for (final l in servico.levitas) l.userId: l.confirmed
      };
      final levitas = equipe.members
          .map((m) => ScaleLevita(
                userId: m.userId,
                userName: '',
                instrument: m.instrument,
                confirmed: anteriores[m.userId] ?? false,
              ).toMap())
          .toList();

      final r = await _updateScaleField(
        servico.id,
        'atualizar a equipe dos próximos cultos',
        (_) => {'levitas': levitas},
      );
      if (!r.success) return (atualizados: atualizados, error: r.error);
      atualizados++;
    }
    return (atualizados: atualizados, error: null);
  }

  /// Cancels or reinstates one service, without touching the schedule.
  static Future<({bool success, String? error})> setScaleCanceled(
    String scaleId,
    bool canceled,
  ) {
    return _updateScaleField(
      scaleId,
      canceled ? 'cancelar o culto' : 'reativar o culto',
      (_) => {'canceled': canceled},
    );
  }

  // ─── CHAT ─────────────────────────────────────────────────────────────────

  static Stream<List<MessageModel>> watchMessages({int limit = 50}) {
    return _db
        .collection(_messages)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MessageModel.fromFirestore(doc.data()))
            .toList()
            .reversed
            .toList());
  }

  static Future<({bool success, String? error})> sendMessage(
      MessageModel message) async {
    try {
      await _db
          .collection(_messages)
          .doc(message.id)
          .set(message.toFirestore());
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (success: false, error: _describe(e, 'enviar a mensagem'));
    } catch (e) {
      return (success: false, error: 'Não foi possível enviar: $e');
    }
  }

  /// Reage (ou tira a reação) numa mensagem. Devolve null quando dá certo.
  ///
  /// Grava SÓ a própria chave do mapa, com caminho de ponto: a regra do banco
  /// confere que o diff do mapa afeta apenas o meu uid, então gravar o mapa
  /// inteiro seria recusado — e seria certo recusar, porque apagaria a reação
  /// de quem reagiu no mesmo segundo.
  static Future<String?> reagir({
    required String mensagemId,
    required String meuId,
    required String? emoji,
  }) async {
    try {
      await _db.collection(_messages).doc(mensagemId).update({
        'reacoes.$meuId': emoji ?? FieldValue.delete(),
      });
      return null;
    } on FirebaseException catch (e) {
      return _describe(e, 'reagir');
    }
  }

  static MessageModel createMessage({
    required String userId,
    required String userName,
    required String text,
    String? linkedSongId,
    String? linkedSongName,
    MessageModel? respondendoA,
    List<String> mencoes = const [],
  }) {
    final agora = DateTime.now();
    return MessageModel(
      id: CryptoUtils.generateId(),
      userId: userId,
      userName: userName,
      text: text,
      type: linkedSongId != null ? MessageType.song : MessageType.text,
      linkedSongId: linkedSongId,
      linkedSongName: linkedSongName,
      timestamp: agora,
      // O prazo vai gravado na mensagem, e não calculado na hora de ler,
      // porque quem apaga é uma faxina que roda fora do app.
      expiraEm: agora.add(MessageModel.validade),
      respondeA: respondendoA?.id,
      respondeANome: respondendoA?.userName,
      // O pedaço citado é COPIADO: a original some em 30 dias, e resolver
      // por id custaria uma leitura por bolha na tela.
      respondeATexto: respondendoA == null ? null : _pedacoCitado(respondendoA),
      mencoes: mencoes,
    );
  }

  /// O pedaço da mensagem citada que cabe na bolha.
  static String _pedacoCitado(MessageModel m) {
    if (m.temAudio) return '🎤 Mensagem de voz';
    final texto = m.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (texto.isEmpty) return 'Mensagem';
    return texto.length > 160 ? '${texto.substring(0, 159)}…' : texto;
  }

  /// Marca ou desmarca uma conta como robô. Devolve null quando dá certo.
  ///
  /// Grava SÓ o campo `bot`, nada mais: a regra do banco deixa o líder mexer
  /// nesse campo e em nenhum outro do cadastro alheio, e gravar o documento
  /// inteiro apagaria o que a pessoa editou no perfil ao mesmo tempo.
  static Future<String?> marcarComoBot(UserModel alvo, bool bot) async {
    try {
      await _db.collection('users').doc(alvo.id).update({'bot': bot});
      return null;
    } on FirebaseException catch (e) {
      return _describe(e, 'marcar a conta');
    }
  }

  // ─── Mensagens de voz ─────────────────────────────────────────────────────

  static const String _audios = 'audios';

  /// Teto de bytes por áudio, conferido aqui e na regra do banco.
  ///
  /// O documento do Firestore vai até 1 MiB. Pedir 32 kbps não garante 32:
  /// medido num Chromium, dois minutos sairiam com 531 KiB — 36 kbps, por
  /// causa do contêiner. 800 KiB aceita um aparelho que grave bem mais gordo
  /// que isso e ainda fica longe do limite do banco. O teto apertado era o
  /// jeito de recusar a mensagem DEPOIS de a pessoa falar dois minutos.
  static const int audioMaximoBytes = 800 * 1024;

  /// Grava o áudio e a mensagem que o anuncia, juntos.
  ///
  /// Os dois num lote só: uma mensagem apontando para um áudio que não
  /// existe seria um play eternamente carregando, e um áudio sem mensagem
  /// seria lixo que ninguém vê e a faxina só apaga em 30 dias.
  static Future<({bool success, String? error, String? mensagemId})>
      enviarAudio({
    required String userId,
    required String userName,
    required Uint8List bytes,
    required String tipo,
    required int duracaoMs,
  }) async {
    if (bytes.length > audioMaximoBytes) {
      return (
        success: false,
        error: 'Áudio grande demais (${(bytes.length / 1024).round()} KB). '
            'Grave um mais curto.',
        mensagemId: null,
      );
    }

    final agora = DateTime.now();
    final expira = agora.add(MessageModel.validade);
    final audioId = CryptoUtils.generateId();
    final mensagemId = CryptoUtils.generateId();

    try {
      final lote = _db.batch();
      lote.set(_db.collection(_audios).doc(audioId), {
        'id': audioId,
        'mensagemId': mensagemId,
        'userId': userId,
        'bytes': Blob(bytes),
        'tipo': tipo,
        'duracaoMs': duracaoMs,
        'criadoEm': Timestamp.fromDate(agora),
        // O áudio vence junto com a mensagem, e some junto quando ela é
        // fixada. Guardado aqui porque a faxina apaga as duas coleções sem
        // precisar cruzar uma com a outra.
        'expiraEm': Timestamp.fromDate(expira),
      });
      lote.set(_db.collection(_messages).doc(mensagemId), MessageModel(
        id: mensagemId,
        userId: userId,
        userName: userName,
        text: '',
        type: MessageType.audio,
        timestamp: agora,
        expiraEm: expira,
        audioId: audioId,
        audioDuracaoMs: duracaoMs,
        audioTipo: tipo,
      ).toFirestore());
      await lote.commit();
      return (success: true, error: null, mensagemId: mensagemId);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: _describe(e, 'enviar o áudio'),
        mensagemId: null,
      );
    }
  }

  /// Os bytes de um áudio. Chamado SÓ quando alguém toca no play.
  static Future<({Uint8List? bytes, String? tipo, String? error})> baixarAudio(
      String audioId) async {
    try {
      final doc = await _db.collection(_audios).doc(audioId).get();
      if (!doc.exists) {
        return (
          bytes: null,
          tipo: null,
          error: 'Este áudio não está mais disponível.'
        );
      }
      final dados = doc.data()!;
      final blob = dados['bytes'];
      if (blob is! Blob) {
        return (bytes: null, tipo: null, error: 'Áudio gravado errado.');
      }
      return (
        bytes: blob.bytes,
        tipo: dados['tipo'] as String? ?? 'audio/mp4',
        error: null
      );
    } on FirebaseException catch (e) {
      return (bytes: null, tipo: null, error: _describe(e, 'baixar o áudio'));
    }
  }

  /// Fixa ou desafixa uma mensagem. Só o líder — ver firestore.rules.
  ///
  /// Fixar apaga o prazo; desafixar devolve o prazo contado do horário
  /// original, e não de agora: uma mensagem de dois meses atrás que sai do
  /// topo não ganha mais 30 dias de vida.
  static Future<({bool success, String? error})> fixarMensagem(
    MessageModel mensagem,
    bool fixar,
    String porQuemId,
  ) async {
    final prazo = fixar
        ? null
        : Timestamp.fromDate(mensagem.timestamp.add(MessageModel.validade));
    try {
      // O áudio acompanha a mensagem: fixar sem mexer nele deixaria a faxina
      // apagar o áudio de uma mensagem que ficou no topo — a bolha sobrevive
      // e o play fica mudo para sempre.
      final lote = _db.batch();
      lote.update(_db.collection(_messages).doc(mensagem.id), {
        'fixada': fixar,
        'fixadaPor': fixar ? porQuemId : null,
        'expiraEm': prazo,
      });
      if (mensagem.audioId != null) {
        lote.update(_db.collection(_audios).doc(mensagem.audioId!),
            {'expiraEm': prazo});
      }
      await lote.commit();
      return (success: true, error: null);
    } on FirebaseException catch (e) {
      return (
        success: false,
        error: _describe(e, fixar ? 'fixar a mensagem' : 'desafixar')
      );
    }
  }

  // ─── TYPING (presence) ──────────────────────────────────────────────────────

  static const String _typing = 'typing';

  /// Broadcasts whether [userId] is currently typing in the group chat.
  static Future<void> setTyping({
    required String userId,
    required String userName,
    required bool typing,
  }) async {
    try {
      await _db.collection(_typing).doc(userId).set({
        'userId': userId,
        'userName': userName,
        'typing': typing,
        'updatedAt': Timestamp.now(),
      });
    } catch (_) {
      // Presence is best-effort; ignore failures.
    }
  }

  static Stream<List<({String userId, String userName, DateTime updatedAt})>>
      watchTyping() {
    return _db
        .collection(_typing)
        .where('typing', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              return (
                userId: data['userId'] as String? ?? doc.id,
                userName: data['userName'] as String? ?? '',
                updatedAt:
                    (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              );
            }).toList());
  }
}
