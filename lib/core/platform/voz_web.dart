import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

/// O que a gravação devolveu.
typedef AudioGravado = ({Uint8List bytes, String tipo, int duracaoMs});

/// Como está quem toca agora.
/// `falhou` é o id do áudio que deu erro ao decodificar — o que acontece
/// quando o `canPlayType` respondeu "maybe" e era não.
typedef EstadoDoAudio = ({
  String id,
  bool tocando,
  int posicaoMs,
  String falhou,
});

// As funções moram em `web/audio.js`, que roda antes do Flutter. Ver lá o
// porquê de a gravação não estar em Dart.
@JS('levitaAudioSuportado')
external JSFunction? get _suportado;

@JS('levitaPodeTocar')
external JSFunction? get _podeTocar;

@JS('levitaGravarIniciar')
external JSFunction? get _iniciar;

@JS('levitaGravandoMs')
external JSFunction? get _gravandoMs;

@JS('levitaGravarParar')
external JSFunction? get _parar;

@JS('levitaGravarCancelar')
external JSFunction? get _cancelar;

@JS('levitaTocar')
external JSFunction? get _tocar;

@JS('levitaPausar')
external JSFunction? get _pausar;

@JS('levitaRetomar')
external JSFunction? get _retomar;

@JS('levitaEstadoAudio')
external JSFunction? get _estado;

/// Este aparelho grava voz? Falso num navegador antigo, ou sem microfone.
bool get vozSuportada {
  try {
    return _suportado?.callAsFunction(null).dartify() == true;
  } catch (_) {
    return false;
  }
}

/// Este aparelho toca ESTE formato?
///
/// É o que separa "o áudio não chegou" de "este iPhone não toca webm". A
/// bolha precisa dizer qual dos dois é.
bool podeTocar(String tipo) {
  try {
    return _podeTocar?.callAsFunction(null, tipo.toJS).dartify() == true;
  } catch (_) {
    return true;
  }
}

/// 'ok', 'sem-permissao', 'sem-suporte' ou 'erro'.
Future<String> gravarIniciar() async {
  final f = _iniciar;
  if (f == null) return 'sem-suporte';
  try {
    final r = await (f.callAsFunction(null) as JSPromise).toDart;
    return (r.dartify() as String?) ?? 'erro';
  } catch (_) {
    return 'erro';
  }
}

int gravandoMs() {
  try {
    final v = _gravandoMs?.callAsFunction(null).dartify();
    return v is num ? v.toInt() : 0;
  } catch (_) {
    return 0;
  }
}

/// Para e devolve o que foi gravado, ou null se não veio som.
Future<AudioGravado?> gravarParar() async {
  final f = _parar;
  if (f == null) return null;
  try {
    final r = await (f.callAsFunction(null) as JSPromise).toDart;
    final mapa = r.dartify();
    if (mapa is! Map) return null;
    final base64 = mapa['base64'] as String?;
    if (base64 == null || base64.isEmpty) return null;
    return (
      bytes: base64Decode(base64),
      tipo: (mapa['tipo'] as String?) ?? 'audio/mp4',
      duracaoMs: ((mapa['duracaoMs'] as num?) ?? 0).toInt(),
    );
  } catch (_) {
    return null;
  }
}

void gravarCancelar() {
  try {
    _cancelar?.callAsFunction(null);
  } catch (_) {
    // Já estava parado. Cancelar é idempotente de propósito: a tela chama
    // isto em todo caminho de saída.
  }
}

/// Toca. Falso quando este aparelho não dá conta do formato.
Future<bool> tocarAudio(String id, Uint8List bytes, String tipo) async {
  final f = _tocar;
  if (f == null) return false;
  try {
    final r = await (f.callAsFunction(
            null, id.toJS, base64Encode(bytes).toJS, tipo.toJS) as JSPromise)
        .toDart;
    return r.dartify() == true;
  } catch (_) {
    return false;
  }
}

void pausarAudio() {
  try {
    _pausar?.callAsFunction(null);
  } catch (_) {}
}

void retomarAudio() {
  try {
    _retomar?.callAsFunction(null);
  } catch (_) {}
}

EstadoDoAudio estadoDoAudio() {
  try {
    final bruto = _estado?.callAsFunction(null).dartify();
    if (bruto is! String) {
      return (id: '', tocando: false, posicaoMs: 0, falhou: '');
    }
    final mapa = jsonDecode(bruto) as Map<String, dynamic>;
    return (
      id: (mapa['id'] as String?) ?? '',
      tocando: mapa['tocando'] == true,
      posicaoMs: ((mapa['posicaoMs'] as num?) ?? 0).toInt(),
      falhou: (mapa['falhou'] as String?) ?? '',
    );
  } catch (_) {
    return (id: '', tocando: false, posicaoMs: 0, falhou: '');
  }
}
