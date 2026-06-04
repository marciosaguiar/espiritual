import 'package:flutter/foundation.dart' show kIsWeb;

import '../data/models/user_model.dart';
import '../data/models/song_model.dart';
import '../data/models/scale_model.dart';
import '../data/models/message_model.dart';

/// Preview/demo mode. Enabled automatically on the **web** target so the app
/// can be previewed in a browser without a real Firebase project: Firebase is
/// skipped, the user is auto–logged in and the screens are filled with the
/// sample data below.
///
/// On Android/iOS this is always `false`, so the real app behaves normally.
const bool kPreviewMode = kIsWeb;

class PreviewData {
  static final DateTime _now = DateTime.now();

  static final UserModel demoUser = UserModel(
    id: 'demo-user',
    name: 'Márcio (demo)',
    passwordHash: '',
    role: UserRole.admin,
    instrument: UserInstrument.keyboard,
    favoriteSongs: const ['s1', 's3'],
    savedTones: const {'s2': 2},
    createdAt: _now,
  );

  static final List<SongModel> songs = [
    SongModel(
      id: 's1',
      name: 'Bondade de Deus',
      artist: 'Isaías Saad',
      originalKey: 'G',
      lyrics:
          'Eu te amo, Deus\nO Teu amor não falha\nVocê me cerca, ó Deus\nE em tudo posso ver a Tua mão',
      chords:
          'G              D\nEu te amo, Deus\nEm   C\nO Teu amor não falha\nG              D\nVocê me cerca, ó Deus',
      createdAt: _now,
      addedBy: 'demo-user',
      youtubeUrl: 'https://youtube.com',
    ),
    SongModel(
      id: 's2',
      name: 'Oceanos',
      artist: 'Hillsong (Ana Nóbrega)',
      originalKey: 'D',
      lyrics:
          'Tua voz me chama sobre as águas\nOnde os meus pés podem falhar\nE ali Te encontro no mistério\nEm meio ao mar, confiarei',
      chords:
          'D            A\nTua voz me chama\nBm           G\nSobre as águas',
      createdAt: _now,
      addedBy: 'demo-user',
    ),
    SongModel(
      id: 's3',
      name: 'Teu Santo Nome',
      artist: 'Gabriela Rocha',
      originalKey: 'E',
      lyrics:
          'A glória da Tua presença\nÉ tudo que eu sempre busquei\nNada se compara a Ti\nSenhor, somente Tu és Rei',
      chords: 'E             B\nA glória da Tua presença',
      createdAt: _now,
    ),
    SongModel(
      id: 's4',
      name: 'Lugar Secreto',
      artist: 'Gabriela Rocha',
      originalKey: 'A',
      lyrics:
          'Eu corro pro Teu santuário\nO lugar secreto, o esconderijo\nEu corro pra debaixo das Tuas asas',
      chords: 'A            E\nEu corro pro Teu santuário',
      createdAt: _now,
    ),
    SongModel(
      id: 's5',
      name: 'Teu Amor Não Falha',
      artist: 'Nívea Soares',
      originalKey: 'C',
      lyrics:
          'Teu amor não falha\nTeu amor não falha\nTeu amor não falha por mim',
      chords: 'C        G\nTeu amor não falha',
      createdAt: _now,
    ),
    SongModel(
      id: 's6',
      name: 'Tua Graça Me Basta',
      artist: 'Toque no Altar',
      originalKey: 'D',
      lyrics:
          'A Tua graça me basta\nA Tua graça me basta, Senhor\nNos momentos de angústia\nNas horas de aflição',
      chords: 'D             A\nA Tua graça me basta',
      createdAt: _now,
    ),
  ];

  static List<ScaleModel> get scales {
    final today = DateTime(_now.year, _now.month, _now.day);
    // Next Sunday from today.
    final nextSunday =
        today.add(Duration(days: (DateTime.sunday - today.weekday + 7) % 7));
    final culto = nextSunday.day == today.day
        ? nextSunday.add(const Duration(days: 7))
        : nextSunday;
    final ensaio = culto.subtract(const Duration(days: 2));

    return [
      ScaleModel(
        id: 'sc1',
        date: culto,
        serviceType: 'Culto',
        createdBy: 'demo-user',
        createdAt: _now,
        observations: 'Chegar 30 min antes para passagem de som.',
        songs: const [
          ScaleSong(
              songId: 's1',
              songName: 'Bondade de Deus',
              artist: 'Isaías Saad',
              key: 'G'),
          ScaleSong(
              songId: 's2',
              songName: 'Oceanos',
              artist: 'Hillsong',
              key: 'D'),
          ScaleSong(
              songId: 's3',
              songName: 'Teu Santo Nome',
              artist: 'Gabriela Rocha',
              key: 'E'),
        ],
        levitas: const [
          ScaleLevita(
              userId: 'demo-user',
              userName: 'Márcio',
              instrument: 'keyboard',
              confirmed: true),
          ScaleLevita(
              userId: 'u2',
              userName: 'Ana',
              instrument: 'vocalist',
              confirmed: true),
          ScaleLevita(
              userId: 'u3',
              userName: 'João',
              instrument: 'guitar',
              confirmed: false),
        ],
      ),
      ScaleModel(
        id: 'sc2',
        date: ensaio,
        serviceType: 'Ensaio',
        createdBy: 'demo-user',
        createdAt: _now,
        songs: const [
          ScaleSong(
              songId: 's4',
              songName: 'Lugar Secreto',
              artist: 'Gabriela Rocha',
              key: 'A'),
        ],
        levitas: const [
          ScaleLevita(
              userId: 'u2',
              userName: 'Ana',
              instrument: 'vocalist',
              confirmed: false),
        ],
      ),
    ];
  }

  static List<MessageModel> get messages => [
        MessageModel(
          id: 'm1',
          userId: 'u2',
          userName: 'Ana',
          text: 'Paz, pessoal! Prontos para o ensaio? 🙌',
          timestamp: _now.subtract(const Duration(hours: 3)),
        ),
        MessageModel(
          id: 'm2',
          userId: 'u3',
          userName: 'João',
          text: 'Bora! Já separei as cifras.',
          timestamp: _now.subtract(const Duration(hours: 2, minutes: 50)),
        ),
        MessageModel(
          id: 'm3',
          userId: 'u2',
          userName: 'Ana',
          text: 'Coloquei essa no repertório:',
          type: MessageType.song,
          linkedSongId: 's2',
          linkedSongName: 'Oceanos',
          timestamp: _now.subtract(const Duration(hours: 2, minutes: 40)),
        ),
        MessageModel(
          id: 'm4',
          userId: 'demo-user',
          userName: 'Márcio',
          text: 'Perfeito! Confirmei minha presença no culto. 🎹',
          timestamp: _now.subtract(const Duration(minutes: 30)),
        ),
      ];
}
