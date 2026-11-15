/// Android e iOS: sem plugin de compartilhamento neste projeto, o app copia o
/// texto e avisa. Espelha a API de `compartilhar_web.dart`.
///
/// Devolver `false` não é falha: é a tela saber que precisa dizer "copiado"
/// em vez de "compartilhado".
Future<bool> compartilharTexto(String texto) async => false;

/// Se existe menu de compartilhamento para oferecer.
bool get podeCompartilhar => false;
