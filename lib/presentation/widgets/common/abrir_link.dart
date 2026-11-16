import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre um endereço fora do app (YouTube, Cifra Club, bible.com).
///
/// Existe por causa de uma falha silenciosa: o botão do YouTube chamava
/// `canLaunchUrl` e, quando ele dizia não, simplesmente não fazia nada — um
/// toque sem resposta nenhuma, que a pessoa lê como app travado. No iPhone
/// instalado, `canLaunchUrl` responde não com alguma frequência mesmo quando
/// o link abriria.
///
/// Então aqui se TENTA abrir, e só se a tentativa falhar é que aparece o
/// aviso — com o endereço, para a pessoa poder copiar.
Future<void> abrirLink(BuildContext context, String? url) async {
  final texto = (url ?? '').trim();
  final uri = texto.isEmpty ? null : Uri.tryParse(texto);
  if (uri == null || !uri.hasScheme) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Este link está incompleto.')),
    );
    return;
  }

  var abriu = false;
  try {
    abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    abriu = false;
  }
  if (abriu || !context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Não consegui abrir: $texto'),
      action: SnackBarAction(
        label: 'Copiar',
        onPressed: () => Clipboard.setData(ClipboardData(text: texto)),
      ),
      duration: const Duration(seconds: 6),
    ),
  );
}
