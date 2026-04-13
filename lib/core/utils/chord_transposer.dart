/// Chord transposer utility for LevitaSync
/// Supports all common chord notations in Portuguese/Brazilian style
class ChordTransposer {
  static const List<String> sharpNotes = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  static const List<String> flatNotes = [
    'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'
  ];

  static const Map<String, String> enharmonics = {
    'C#': 'Db',
    'Db': 'C#',
    'D#': 'Eb',
    'Eb': 'D#',
    'F#': 'Gb',
    'Gb': 'F#',
    'G#': 'Ab',
    'Ab': 'G#',
    'A#': 'Bb',
    'Bb': 'A#',
  };

  static const List<String> keyNames = [
    'C', 'C#/Db', 'D', 'D#/Eb', 'E', 'F', 'F#/Gb', 'G', 'G#/Ab', 'A', 'A#/Bb', 'B'
  ];

  /// Transpose a full chord chart text by [semitones] steps
  static String transposeText(String text, int semitones) {
    if (semitones == 0) return text;
    // Match chord patterns: letter + optional # or b + optional suffix
    final chordPattern = RegExp(
      r'\b([A-G][b#]?)((?:maj|min|m|sus|aug|dim|add|[0-9]|\/[A-G][b#]?)*)\b',
    );

    return text.replaceAllMapped(chordPattern, (match) {
      final root = match.group(1)!;
      final suffix = match.group(2) ?? '';
      final transposedRoot = _transposeNote(root, semitones);
      return '$transposedRoot$suffix';
    });
  }

  /// Transpose a single note by [semitones] steps
  static String _transposeNote(String note, int semitones) {
    int index = sharpNotes.indexOf(note);
    if (index == -1) {
      index = flatNotes.indexOf(note);
      if (index == -1) return note; // unknown note, return as-is
    }

    int newIndex = (index + semitones) % 12;
    if (newIndex < 0) newIndex += 12;

    // Prefer sharps unless note was originally flat
    if (flatNotes.contains(note) && !sharpNotes.contains(note)) {
      return flatNotes[newIndex];
    }
    return sharpNotes[newIndex];
  }

  /// Get key name from semitone offset of original key
  static String getKeyName(String originalKey, int semitones) {
    int index = sharpNotes.indexOf(originalKey);
    if (index == -1) {
      index = flatNotes.indexOf(originalKey);
    }
    if (index == -1) return originalKey;

    int newIndex = (index + semitones) % 12;
    if (newIndex < 0) newIndex += 12;

    return keyNames[newIndex];
  }

  /// Get display string for transpose amount
  static String getTransposeDisplay(int semitones) {
    if (semitones == 0) return 'Original';
    if (semitones > 0) return '+$semitones';
    return '$semitones';
  }

  /// All available keys for selection
  static List<String> get allKeys => [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
    'Db', 'Eb', 'Gb', 'Ab', 'Bb',
  ];
}
