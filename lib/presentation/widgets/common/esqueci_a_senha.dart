import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/services/auth_service.dart';
import 'app_text_field.dart';

/// "Esqueci minha senha", na tela de login.
///
/// Pede o E-MAIL, não o nome, e isso é a diferença entre funcionar e enganar.
/// O endereço com que o Firebase identifica cada conta nasce do nome
/// (`ana@levitas.app`) e esse domínio não é de ninguém: pedir o nome aqui
/// mandaria o link para o vazio, a tela diria "enviamos" e a pessoa ficaria
/// esperando um e-mail que nunca sai.
///
/// Quem nunca cadastrou um e-mail não tem como recuperar a senha — por isso
/// esta tela diz isso na cara, em vez de deixar a pessoa tentando.
Future<void> mostrarEsqueciASenha(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _EsqueciASenha(),
  );
}

class _EsqueciASenha extends StatefulWidget {
  const _EsqueciASenha();

  @override
  State<_EsqueciASenha> createState() => _EsqueciASenhaState();
}

class _EsqueciASenhaState extends State<_EsqueciASenha> {
  final _ctrl = TextEditingController();
  bool _enviando = false;
  String? _erro;
  bool _enviado = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final r = await AuthService.enviarLinkDeSenha(_ctrl.text);
    if (!mounted) return;
    setState(() {
      _enviando = false;
      _erro = r.error;
      _enviado = r.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5);

    if (_enviado) {
      return AlertDialog(
        title: const Text('Olhe o seu e-mail'),
        content: Text(
          // O Firebase não conta se a conta existe — é proteção contra alguém
          // descobrir quem tem conta no app. Então a tela também não pode
          // prometer que chegou: diz o que fazer se não chegar.
          'Se existir uma conta com ${_ctrl.text.trim()}, o link para criar '
          'uma senha nova chega em alguns minutos.\n\n'
          'Não chegou? Veja a caixa de spam. Se não houver nada lá, '
          'provavelmente o e-mail cadastrado é outro — fale com o líder do '
          'ministério.',
          style: estilo,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Esqueci minha senha'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Digite o e-mail que você cadastrou no app, em '
            'Perfil → Recuperar a senha.',
            style: estilo,
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'E-mail',
            hint: 'seunome@gmail.com',
            controller: _ctrl,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.mail_outline, size: 20),
            onSubmitted: (_) => _enviando ? null : _enviar(),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(
              _erro!,
              style: estilo.copyWith(color: AppColors.red),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Nunca cadastrou e-mail? Então a senha não pode ser recuperada '
              'por aqui: fale com o líder do ministério. Ninguém — nem o '
              'líder, nem o app — consegue trocar a senha de outra pessoa.',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        TextButton(
          onPressed: _enviando ? null : _enviar,
          child: Text(_enviando ? 'Enviando…' : 'Enviar link'),
        ),
      ],
    );
  }
}
