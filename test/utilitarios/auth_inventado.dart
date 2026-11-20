// O líder das fotos e do demo: o AuthProvider de verdade, sem banco.
//
// Mora num arquivo à parte, sem `flutter_test`, porque o demo que roda num
// navegador de verdade (`ferramentas/captura/main_demo.dart`) também o usa — e
// `flutter_test` não compila para a web.

import 'package:levitasync/data/models/user_model.dart';
import 'package:levitasync/presentation/providers/auth_provider.dart';

import 'dados_inventados.dart';

/// O líder da foto. Estende o AuthProvider de verdade, trocando só o que
/// falaria com o banco.
class AuthInventado extends AuthProvider {
  @override
  UserModel? get user => lider;

  @override
  bool get isAdmin => true;

  @override
  AuthStatus get status => AuthStatus.authenticated;

  @override
  List<UserModel> get pessoas => ministerio;

  @override
  Map<String, String> get nomes => {for (final p in ministerio) p.id: p.name};

  @override
  String? get emailDeRecuperacao => 'ana@exemplo.com';

  @override
  void ouvirPessoas() {}

  @override
  Future<void> conferirRecuperacao() async {}
}
