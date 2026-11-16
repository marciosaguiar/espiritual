import 'dart:typed_data';

/// O que a gravação devolveu.
typedef AudioGravado = ({Uint8List bytes, String tipo, int duracaoMs});

/// Como está quem toca agora.
typedef EstadoDoAudio = ({
  String id,
  bool tocando,
  int posicaoMs,
  String falhou,
});

/// Android e iOS nativos: sem gravação neste projeto. Espelha a API de
/// `voz_web.dart`, e a tela some com o botão quando isto é falso.
bool get vozSuportada => false;

bool podeTocar(String tipo) => false;

Future<String> gravarIniciar() async => 'sem-suporte';

int gravandoMs() => 0;

Future<AudioGravado?> gravarParar() async => null;

void gravarCancelar() {}

Future<bool> tocarAudio(String id, Uint8List bytes, String tipo) async => false;

void pausarAudio() {}

void retomarAudio() {}

EstadoDoAudio estadoDoAudio() =>
    (id: '', tocando: false, posicaoMs: 0, falhou: '');
