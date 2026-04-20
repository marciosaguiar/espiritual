import 'package:flutter/material.dart';
import '../../core/utils/chord_transposer.dart';

/// Renders a cifra (chord chart) with chords displayed above the lyrics,
/// highlighted in a distinct color so instrumentalists know where to play.
///
/// Chord lines are detected automatically: a line is considered a chord line
/// when it contains only chord tokens (e.g. "G  Em  C  D") and whitespace.
class ChordedLyricsWidget extends StatelessWidget {
  final String text;
  final int semitones;
  final double fontSize;
  final Color chordColor;
  final Color lyricColor;

  const ChordedLyricsWidget({
    super.key,
    required this.text,
    this.semitones = 0,
    this.fontSize = 15.0,
    required this.chordColor,
    required this.lyricColor,
  });

  /// Pattern that matches a single chord token: root + optional accidental +
  /// optional suffix (m, maj, sus4, add9, /B, etc.).
  static final _chordToken = RegExp(
    r'^[A-G][b#]?(maj|min|m|sus|aug|dim|add|[0-9]+|\/[A-G][b#]?)*$',
  );

  /// Returns true when every non-empty word on the line is a chord name.
  static bool isChordLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    final words = trimmed.split(RegExp(r'\s+'));
    return words.every((w) => _chordToken.hasMatch(w));
  }

  @override
  Widget build(BuildContext context) {
    final displayText = semitones != 0
        ? ChordTransposer.transposeText(text, semitones)
        : text;

    final lines = displayText.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.isEmpty) {
          // Blank line – small spacer between sections
          return const SizedBox(height: 8);
        }

        final isChord = isChordLine(line);

        return Text(
          line,
          style: TextStyle(
            // Monospace keeps chord positions aligned over the lyrics below
            fontFamily: 'Courier',
            fontSize: isChord ? fontSize - 1.5 : fontSize,
            fontWeight: isChord ? FontWeight.w700 : FontWeight.w400,
            color: isChord ? chordColor : lyricColor,
            // Tighter leading for chord lines so they sit close to the lyric
            height: isChord ? 1.1 : 1.7,
            letterSpacing: isChord ? 0.5 : 0.0,
          ),
        );
      }).toList(),
    );
  }
}
