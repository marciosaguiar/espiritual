import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/platform/install.dart';

/// Invites the person to put the app on their home screen.
///
/// Two reasons it earns the space. The app opens without the browser bar, so
/// it stops looking like a website; and on the iPhone an installed web app is
/// the **only** way notifications can arrive at all (iOS 16.4+). Everything in
/// the next step depends on this one.
///
/// NÃO TEM MAIS "AGORA NÃO".
///
/// Tinha, e guardava a escolha para sempre. Um toque sem pensar, no primeiro
/// dia, e o convite nunca mais aparecia — foi o que aconteceu com o dono do
/// app, que passou semanas sem o aplicativo instalado e sem entender por que
/// os avisos não chegavam. Agora o cartão fica até estar instalado, que é a
/// única coisa que o resolve de verdade.
///
/// Só não aparece quando o app já está instalado ou quando roda nativo.
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  InstallRoute _caminho = InstallRoute.naoSeAplica;

  @override
  void initState() {
    super.initState();
    _caminho = caminhoDeInstalacao;
  }

  Future<void> _instalar() async {
    final abriu = await convidarParaInstalar();
    if (!abriu && mounted) {
      // O convite expirou (o navegador só o oferece uma vez por carregamento).
      _mostrarInstrucoes();
    }
  }

  void _mostrarInstrucoes() => mostrarComoInstalar(context, _caminho);

  @override
  Widget build(BuildContext context) {
    if (_caminho == InstallRoute.naoSeAplica) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secundaria =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final convidavel = _caminho == InstallRoute.conviteDoNavegador;
    final noIphone = _caminho == InstallRoute.instrucoesIphone;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.add_to_home_screen_rounded,
              color: AppColors.blue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Instale o LevitaSync no celular',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  noIphone
                      // No iPhone não é preferência: fora da tela de início o
                      // Safari não tem Web Push nenhum.
                      ? 'No iPhone, os avisos de mensagem nova só chegam com o '
                          'app na tela de início. Pelo navegador, nunca chegam.'
                      : 'Abre como aplicativo, sem a barra do navegador, e é '
                          'assim que os avisos de mensagem nova chegam.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    height: 1.35,
                    color: secundaria,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: convidavel ? _instalar : _mostrarInstrucoes,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Text(
                        convidavel ? 'Instalar' : 'Ver como fazer',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre o passo a passo de instalação, escrito para o navegador em que a
/// pessoa está. Usado pelo cartão do Início e pela linha do Perfil.
void mostrarComoInstalar(BuildContext context, [InstallRoute? caminho]) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _FolhaDeInstrucoes(caminho: caminho ?? caminhoDeInstalacao),
  );
}

/// The three steps, written for whichever browser the person is actually in.
class _FolhaDeInstrucoes extends StatelessWidget {
  final InstallRoute caminho;
  const _FolhaDeInstrucoes({required this.caminho});

  List<(IconData, String, String)> get _passos {
    if (caminho == InstallRoute.instrucoesIphone) {
      return const [
        (
          Icons.ios_share_rounded,
          'Toque em Compartilhar',
          'É o quadradinho com a seta para cima, na barra de baixo do Safari.',
        ),
        (
          Icons.add_box_outlined,
          'Escolha "Adicionar à Tela de Início"',
          'Role a lista um pouco para baixo até achar.',
        ),
        (
          Icons.check_circle_outline_rounded,
          'Toque em Adicionar',
          'Pronto: o LevitaSync fica junto dos outros aplicativos.',
        ),
      ];
    }
    return const [
      (
        Icons.more_vert_rounded,
        'Abra o menu do navegador',
        'São os três pontinhos, no canto da tela.',
      ),
      (
        Icons.add_to_home_screen_rounded,
        'Escolha "Instalar aplicativo"',
        'Em alguns aparelhos aparece como "Adicionar à tela inicial".',
      ),
      (
        Icons.check_circle_outline_rounded,
        'Confirme',
        'Pronto: o LevitaSync fica junto dos outros aplicativos.',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171C23) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Deixar na tela de início',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caminho == InstallRoute.instrucoesIphone
                ? 'Três toques. Depois é só abrir pelo ícone — e é a partir '
                    'daí que o iPhone deixa os avisos de mensagem chegarem.'
                : 'Três toques. Depois é só abrir pelo ícone, como qualquer '
                    'outro aplicativo.',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 22),
          ..._passos.indexed.map((par) {
            final (i, (icone, titulo, detalhe)) = par;
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icone, color: AppColors.blue, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}. $titulo',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detalhe,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text(
                'Entendi',
                style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
