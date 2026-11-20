import '../../core/utils/fusao_de_edicao.dart';

/// Um recado do app sobre algo que a pessoa fez e que NÃO terminou como ela
/// esperava: uma edição que perdeu para outra, uma confirmação que não pôde
/// ser enviada.
///
/// Fica guardado no aparelho até a pessoa tratar. Um aviso que sumisse sozinho
/// seria uma falha silenciosa com mais passos.
enum TipoDeRecado { edicaoPerdida, acaoNaoEnviada }

class AvisoDeSincronia {
  final String id;
  final TipoDeRecado tipo;
  final DateTime criadoEm;
  final String titulo;
  final String texto;

  /// Para "Aplicar a minha mesmo assim": a música e o alvo da edição.
  final String? songId;
  final String? alvo;

  /// Só para [TipoDeRecado.edicaoPerdida]: os campos em que a edição perdeu.
  final List<PerdaDeCampo> perdas;

  const AvisoDeSincronia({
    required this.id,
    required this.tipo,
    required this.criadoEm,
    required this.titulo,
    required this.texto,
    this.songId,
    this.alvo,
    this.perdas = const [],
  });

  bool get podeReaplicar =>
      tipo == TipoDeRecado.edicaoPerdida && songId != null && perdas.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo.name,
        'criadoEm': criadoEm.toUtc().toIso8601String(),
        'titulo': titulo,
        'texto': texto,
        'songId': songId,
        'alvo': alvo,
        'perdas': perdas.map((p) => p.toJson()).toList(),
      };

  factory AvisoDeSincronia.fromJson(Map<String, dynamic> j) => AvisoDeSincronia(
        id: j['id'] as String,
        tipo: TipoDeRecado.values.firstWhere((t) => t.name == j['tipo'],
            orElse: () => TipoDeRecado.acaoNaoEnviada),
        criadoEm: DateTime.parse(j['criadoEm'] as String).toLocal(),
        titulo: (j['titulo'] as String?) ?? '',
        texto: (j['texto'] as String?) ?? '',
        songId: j['songId'] as String?,
        alvo: j['alvo'] as String?,
        perdas: ((j['perdas'] as List?) ?? const [])
            .map((p) => PerdaDeCampo.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList(),
      );
}

/// O nome do campo, como a pessoa o conhece.
String rotuloDoCampo(String campo) => switch (campo) {
      'name' => 'Nome',
      'artist' => 'Artista',
      'originalKey' => 'Tom',
      'observacoes' => 'Anotações da música',
      'lyrics' => 'Letra',
      'links' => 'Links',
      'chords' => 'Cifra',
      'bpm' => 'BPM',
      'churchKey' => 'Tom da igreja',
      'notes' => 'Observações do arranjo',
      'structure' => 'Estrutura',
      _ => campo,
    };

/// O valor de um campo em poucas palavras, para caber numa frase.
String resumoDoValor(Object? v) {
  if (v == null) return '(vazio)';
  if (v is String) {
    final t = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return '(vazio)';
    return t.length > 60 ? '${t.substring(0, 57)}…' : t;
  }
  if (v is List) return v.isEmpty ? '(vazio)' : '(${v.length} item${v.length == 1 ? '' : 's'})';
  return '$v';
}
