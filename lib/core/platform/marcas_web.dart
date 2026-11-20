import 'dart:js_interop';

@JS('levitaMarcar')
external void _marcar(JSString nome);

/// Só uma compilação de medição liga isto. Constante: na normal, o `if`
/// abaixo some junto com a chamada.
const bool medindo = bool.fromEnvironment('MEDIR');

/// Registra no `performance` da página que [nome] aconteceu AGORA.
void marcar(String nome) {
  if (!medindo) return;
  try {
    _marcar(nome.toJS);
  } catch (_) {
    // Sem a página de medição não há onde marcar, e o app segue igual.
  }
}
