// Configuração que o `flutter test` aplica a TODOS os arquivos desta pasta.
//
// Desliga o carregamento da fonte da cifra (ver `FonteMono.desligada`): o aviso
// que o motor manda quando uma fonte entra pode chegar depois do fim do teste, e
// aí o teste reprova com "An animation is still running…". Foi o que reprovou 5
// testes na CI (Flutter 3.50.0) sem nunca reprovar aqui nem no Mac.

import 'dart:async';

import 'package:levitasync/core/utils/fonte_mono.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FonteMono.desligada = true;
  await testMain();
}
