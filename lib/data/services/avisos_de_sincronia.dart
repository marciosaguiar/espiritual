import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/platform/armazem.dart';
import '../models/aviso_de_sincronia.dart';

/// Os recados do app sobre o que a pessoa fez e não terminou como ela
/// esperava. Guardados no aparelho até ela tratar: um aviso que sumisse
/// sozinho seria uma falha silenciosa.
class AvisosDeSincronia extends ChangeNotifier {
  AvisosDeSincronia._();
  static final AvisosDeSincronia instancia = AvisosDeSincronia._();

  static const _chave = 'avisos-sync:v1';
  final List<AvisoDeSincronia> _lista = [];

  List<AvisoDeSincronia> get lista => List.unmodifiable(_lista);
  bool get temAviso => _lista.isNotEmpty;

  Future<void> carregar() async {
    _lista.clear();
    final texto = await Armazem.ler(_chave);
    if (texto != null && texto.isNotEmpty) {
      try {
        for (final j in (jsonDecode(texto) as List)) {
          _lista.add(
              AvisoDeSincronia.fromJson(Map<String, dynamic>.from(j as Map)));
        }
      } catch (_) {
        // Ilegível: começa vazio, em vez de não abrir o app.
      }
    }
    notifyListeners();
  }

  Future<void> adicionar(List<AvisoDeSincronia> novos) async {
    if (novos.isEmpty) return;
    _lista.addAll(novos);
    await _salvar();
    notifyListeners();
  }

  Future<void> remover(String id) async {
    _lista.removeWhere((a) => a.id == id);
    await _salvar();
    notifyListeners();
  }

  Future<void> limpar() async {
    _lista.clear();
    await _salvar();
    notifyListeners();
  }

  Future<void> _salvar() =>
      Armazem.gravar(_chave, jsonEncode(_lista.map((a) => a.toJson()).toList()));

  @visibleForTesting
  void esvaziarParaTeste() {
    _lista.clear();
    notifyListeners();
  }
}
