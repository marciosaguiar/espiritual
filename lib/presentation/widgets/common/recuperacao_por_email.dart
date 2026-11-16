import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import 'app_text_field.dart';

/// Cadastrar o e-mail que recebe o link de "esqueci minha senha".
///
/// POR QUE ISTO EXISTE, e por que a tela insiste
///
/// Aqui ninguém entra com e-mail: entra com o nome, e o Firebase, que exige
/// um endereço, recebe um inventado a partir dele (`ana@levitas.app`). Esse
/// domínio não é de ninguém, então o e-mail de recuperação do Firebase não
/// tem para onde ir.
///
/// E trocar a senha de outra pessoa exige chave de administrador do projeto —
/// que este app não tem, de propósito, porque quem a tem entra como qualquer
/// um, líder incluído. O console do Firebase também não troca senha de conta
/// que já existe: cria, apaga e manda e-mail de recuperação, nada mais.
///
/// Juntando as três coisas: **conta sem e-mail de verdade, com a senha
/// perdida, é acesso perdido.** Não há conserto depois. Só antes — e só
/// enquanto a pessoa ainda consegue entrar, porque cadastrar o e-mail pede a
/// senha atual.
Future<void> mostrarRecuperacaoPorEmail(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _RecuperacaoPorEmail(),
  );
}

class _RecuperacaoPorEmail extends StatefulWidget {
  const _RecuperacaoPorEmail();

  @override
  State<_RecuperacaoPorEmail> createState() => _RecuperacaoPorEmailState();
}

class _RecuperacaoPorEmailState extends State<_RecuperacaoPorEmail> {
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  bool _salvando = false;
  String? _erro;
  bool _pronto = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final erro = await context.read<AuthProvider>().definirEmailDeRecuperacao(
          email: _emailCtrl.text,
          senhaAtual: _senhaCtrl.text,
        );
    if (!mounted) return;
    setState(() {
      _salvando = false;
      _erro = erro;
      _pronto = erro == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5);
    final atual = context.watch<AuthProvider>().emailDeRecuperacao;

    if (_pronto) {
      return AlertDialog(
        title: const Text('Falta um clique'),
        content: Text(
          'Mandamos um e-mail para ${_emailCtrl.text.trim()}.\n\n'
          'Abra e clique no link. O e-mail passa a valer só depois disso '
          '— é essa confirmação que garante que o endereço é seu e está '
          'escrito certo.\n\n'
          'Importante: a partir daí você entra no app com esse e-mail no '
          'lugar do nome. Neste celular o app já lembra de você; é no celular '
          'novo que o e-mail vai ser pedido.',
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
      title: Text(atual == null ? 'Recuperar a senha' : 'Trocar o e-mail'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (atual != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Hoje o link de recuperação vai para:\n$atual',
                  style: estilo,
                ),
              ),
              const SizedBox(height: 14),
            ] else ...[
              const Text(
                'Sem um e-mail cadastrado, uma senha esquecida não tem como '
                'ser recuperada — nem pelo líder, nem pelo app. Cadastre '
                'agora, enquanto você ainda consegue entrar.',
                style: estilo,
              ),
              const SizedBox(height: 14),
            ],
            AppTextField(
              label: 'Seu e-mail',
              hint: 'seunome@gmail.com',
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: const Icon(Icons.mail_outline, size: 20),
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Sua senha de agora',
              hint: 'para confirmar que é você',
              controller: _senhaCtrl,
              obscureText: true,
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              onSubmitted: (_) => _salvando ? null : _salvar(),
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(_erro!, style: estilo.copyWith(color: AppColors.red)),
            ],
            const SizedBox(height: 12),
            const Text(
              'Não tem e-mail? Serve o de um filho, do cônjuge ou do líder — '
              'o que importa é alguém conseguir abrir a mensagem com você no '
              'dia em que a senha fugir.',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12, height: 1.45),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        TextButton(
          onPressed: _salvando ? null : _salvar,
          child: Text(_salvando ? 'Enviando…' : 'Enviar confirmação'),
        ),
      ],
    );
  }
}
