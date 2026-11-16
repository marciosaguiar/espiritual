import 'dart:js_interop';

@JS('levitaNoInicio')
external set _noInicio(JSBoolean valor);

/// Avisa a página se o app está na aba Início.
///
/// A faixa de atualização lê isso para decidir se pode se aplicar sozinha.
/// Errar para o lado de "não está no Início" só faz a faixa perguntar, que é
/// o comportamento seguro.
void informarTelaInicial(bool noInicio) {
  try {
    _noInicio = noInicio.toJS;
  } catch (_) {
    // Página antiga, sem a faixa: não há o que avisar, e o app segue igual.
  }
}
