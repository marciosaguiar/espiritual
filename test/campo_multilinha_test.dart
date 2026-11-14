import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levitasync/presentation/widgets/common/app_text_field.dart';

/// No navegador, TextInputType.text vira <input>, que descarta as quebras de
/// linha de um texto colado: a cifra do Cifra Club virava um parágrafo
/// corrido. Campo de várias linhas precisa ser multiline (<textarea>).
void main() {
  Future<TextField> campo(WidgetTester t, AppTextField f) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: f)));
    return t.widget<TextField>(find.byType(TextField));
  }

  testWidgets('campo de várias linhas aceita quebra de linha', (t) async {
    final tf = await campo(t, const AppTextField(label: 'Cifra', maxLines: 12));
    expect(tf.keyboardType, TextInputType.multiline);
  });

  testWidgets('campo de uma linha continua texto comum', (t) async {
    final tf = await campo(t, const AppTextField(label: 'Nome'));
    expect(tf.keyboardType, TextInputType.text);
  });

  testWidgets('cifra usa fonte de largura fixa', (t) async {
    final tf = await campo(
        t, const AppTextField(label: 'Cifra', maxLines: 12, monospace: true));
    expect(tf.style?.fontFamily, 'JetBrainsMono');
  });
}
