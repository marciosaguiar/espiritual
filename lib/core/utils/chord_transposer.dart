/// Chord transposer for LevitaSync.
///
/// Chord charts are pasted in whichever shape they come from the web, so the
/// transposer has to tell chords apart from lyrics. It handles the two common
/// formats and, when in doubt, leaves the text alone:
///
///   * chords on their own line, above the lyrics (the usual Brazilian layout)
///   * chords inline between square brackets — `[G]Eu te louvarei`
///
/// A line is only transposed when *every* word in it is a chord. That is what
/// stops Portuguese words like "A", "E" and "Em" from being mistaken for
/// chords and rewritten in the middle of a lyric.
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

  /// A complete chord: root, optional quality/extensions, optional bass note.
  /// Anchored, so it must account for the whole word.
  static final RegExp _chord = RegExp(
    r'^([A-G][#b]?)'
    r'((?:maj|min|sus|aug|dim|add|m|M|°|º|ø|\+|-|[0-9#b])*)'
    r'(?:/([A-G][#b]?))?$',
  );

  /// Bar lines, repeat marks and similar notation that may share a chord line
  /// without being a chord.
  static final RegExp _notation = RegExp(
    r'^(?:\|+|:|%|~|-+|=+|x\d+|\d+x|N\.?C\.?)$',
    caseSensitive: false,
  );

  /// Punctuation wrapped around a token, e.g. `(D)` or `|Am|`.
  static final RegExp _wrapping = RegExp(r'^[(\[|{]+|[)\]|},.:]+$');

  static final RegExp _leading = RegExp(r'^[(\[|{]+');
  static final RegExp _trailing = RegExp(r'[)\]|},.:]+$');

  /// Inline chords written between square brackets.
  static final RegExp _bracketed = RegExp(r'\[([^\]\n]*)\]');

  /// Transpose a chord chart by [semitones], preserving the lyrics.
  static String transposeText(String text, int semitones) {
    if (semitones == 0 || text.isEmpty) return text;

    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (_bracketed.hasMatch(line)) {
        // Explicitly marked chords: only the bracket contents move.
        lines[i] = line.replaceAllMapped(
          _bracketed,
          (m) => '[${_transposeToken(m.group(1) ?? '', semitones)}]',
        );
      } else if (isChordLine(line)) {
        lines[i] = _transposeChordLine(line, semitones);
      }
      // Anything else is lyrics — left untouched.
    }
    return lines.join('\n');
  }

  /// Whether every word on [line] is a chord (or bar/repeat notation).
  static bool isChordLine(String line) {
    final words = line.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return false;

    var chords = 0;
    for (final word in words) {
      final token = word.replaceAll(_wrapping, '');
      if (token.isEmpty) continue; // pure punctuation
      if (_chord.hasMatch(token)) {
        chords++;
      } else if (!_notation.hasMatch(token)) {
        return false; // a real word — this is a lyric line
      }
    }
    return chords > 0;
  }

  /// Rewrites the chords on a chord line, keeping the original spacing so the
  /// chords stay above the right syllables.
  static String _transposeChordLine(String line, int semitones) {
    return line.replaceAllMapped(RegExp(r'\S+'), (m) {
      final word = m.group(0)!;
      final prefix = _leading.stringMatch(word) ?? '';
      final suffix = _trailing.stringMatch(word) ?? '';
      final start = prefix.length;
      final end = word.length - suffix.length;
      // Tokens made only of punctuation (a bare `|`, say) match both ends;
      // there is no chord left in the middle to transpose.
      if (end <= start) return word;
      final core = word.substring(start, end);
      if (!_chord.hasMatch(core)) return word;
      return '$prefix${_transposeToken(core, semitones)}$suffix';
    });
  }

  /// Transposes a single chord such as `Am7` or `G/B`. Returns it unchanged if
  /// it is not a chord.
  static String _transposeToken(String token, int semitones) {
    final match = _chord.firstMatch(token.trim());
    if (match == null) return token;

    final root = _transposeNote(match.group(1)!, semitones);
    final quality = match.group(2) ?? '';
    final bass = match.group(3);

    if (bass == null) return '$root$quality';
    return '$root$quality/${_transposeNote(bass, semitones)}';
  }

  /// Transpose a single note by [semitones] steps
  static String _transposeNote(String note, int semitones) {
    int index = sharpNotes.indexOf(note);
    final wasFlat = index == -1;
    if (index == -1) {
      index = flatNotes.indexOf(note);
      if (index == -1) return note; // unknown note, return as-is
    }

    int newIndex = (index + semitones) % 12;
    if (newIndex < 0) newIndex += 12;

    // Keep flats flat, so a chart written in Bb stays readable.
    return wasFlat ? flatNotes[newIndex] : sharpNotes[newIndex];
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
