import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/scale_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/local_storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/scale_provider.dart';

/// As pendências do Início: o que exige uma ação de QUEM está olhando.
///
/// POR QUE ELAS SÃO CONDICIONAIS
///
/// O Início responde uma pergunta — "o que eu preciso fazer agora?". Cartão
/// que aparece quando não há nada a fazer ensina a passar o olho por cima de
/// todos os outros, inclusive dos que importam. Então cada um destes só
/// existe na tela quando há mesmo algo pendente.

/// Quantas mensagens do chat eu ainda não vi.
///
/// A conta é PURA e recebe o instante da última visita, para o teste poder
/// ficar na virada do dia. Mensagem minha nunca conta: ninguém tem mensagem
/// não lida de si mesmo.
int naoLidas(List<MessageModel> mensagens, String meuId, DateTime? vistoEm) {
  if (vistoEm == null) {
    // Nunca abriu o chat neste aparelho. Contar tudo faria o app estrear com
    // "47 mensagens novas", que não é notícia, é parede.
    return 0;
  }
  var n = 0;
  for (final m in mensagens) {
    if (m.userId == meuId) continue;
    if (m.timestamp.isAfter(vistoEm)) n++;
  }
  return n;
}

/// Os cultos futuros sem ninguém escalado — pendência de líder.
///
/// Culto cancelado fica de fora: ninguém precisa escalar quem não vai tocar.
List<ScaleModel> cultosSemEscala(List<ScaleModel> cultos, DateTime agora) {
  final achados = cultos
      .where((c) =>
          !c.canceled && c.levitas.isEmpty && c.date.isAfter(agora))
      .toList();
  achados.sort((a, b) => a.date.compareTo(b.date));
  return achados;
}

/// Quem está esperando aprovação — pendência de líder.
int quantosPendentes(List<UserModel> pessoas) =>
    pessoas.where((p) => p.role == UserRole.pendente && !p.bot).length;

/// A fila de pendências do Início, na ordem de quem cobra.
class Pendencias extends StatelessWidget {
  /// Abre a aba do chat.
  final VoidCallback? onAbrirChat;

  /// Abre a tela Membros (só faz sentido para líder).
  final VoidCallback? onAbrirMembros;

  /// Abre a aba da escala.
  final VoidCallback? onAbrirEscala;

  const Pendencias({
    super.key,
    this.onAbrirChat,
    this.onAbrirMembros,
    this.onAbrirEscala,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();
    final escala = context.watch<ScaleProvider>();
    final eu = auth.user;
    if (eu == null) return const SizedBox.shrink();

    final linhas = <Widget>[];

    // ── Líder: quem está esperando para entrar ──
    if (auth.isAdmin) {
      final esperando = quantosPendentes(auth.pessoas);
      if (esperando > 0) {
        linhas.add(_Pendencia(
          icone: Icons.person_add_alt_1_rounded,
          cor: AppColors.warning,
          titulo: esperando == 1
              ? '1 pessoa quer entrar no ministério'
              : '$esperando pessoas querem entrar no ministério',
          detalhe: 'Elas não veem nada do app até você aprovar.',
          onTap: onAbrirMembros,
        ));
      }

      final semEscala = cultosSemEscala(escala.scales, DateTime.now());
      if (semEscala.isNotEmpty) {
        linhas.add(_Pendencia(
          icone: Icons.event_busy_rounded,
          cor: AppColors.warning,
          titulo: semEscala.length == 1
              ? 'Um culto sem ninguém escalado'
              : '${semEscala.length} cultos sem ninguém escalado',
          detalhe: 'O próximo é ${_quando(semEscala.first.date)}.',
          onTap: onAbrirEscala,
        ));
      }
    }

    // ── Todos: mensagens novas no chat ──
    final naoVistas = naoLidas(
      chat.messages,
      eu.id,
      LocalStorageService.chatVistoEm,
    );
    if (naoVistas > 0) {
      final ultima = chat.messages.isEmpty ? null : chat.messages.last;
      linhas.add(_Pendencia(
        icone: Icons.forum_rounded,
        cor: AppColors.blue,
        titulo: naoVistas == 1
            ? '1 mensagem nova no chat'
            : '$naoVistas mensagens novas no chat',
        // A prévia é CURTA de propósito: o Início não é o chat, e um
        // parágrafo aqui faria a pessoa ler a conversa de pé na porta.
        detalhe: ultima == null ? '' : _previa(ultima),
        onTap: onAbrirChat,
      ));
    }

    if (linhas.isEmpty) return const SizedBox.shrink();
    return Column(children: linhas);
  }

  static String _previa(MessageModel m) {
    final quem = m.userName.trim().isEmpty ? 'Alguém' : m.userName.trim();
    if (m.temAudio) return '$quem mandou um áudio';
    final texto = m.text.replaceAll('\n', ' ').trim();
    if (texto.isEmpty) return quem;
    return texto.length <= 60 ? '$quem: $texto' : '$quem: ${texto.substring(0, 60)}…';
  }

  static String _quando(DateTime d) {
    const dias = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado',
      'domingo'];
    final hoje = DateTime.now();
    final diff = DateTime(d.year, d.month, d.day)
        .difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;
    final hora = '${d.hour}h${d.minute == 0 ? '' : d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'hoje às $hora';
    if (diff == 1) return 'amanhã às $hora';
    if (diff < 7) return '${dias[d.weekday - 1]} às $hora';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} às $hora';
  }
}

class _Pendencia extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String titulo;
  final String detalhe;
  final VoidCallback? onTap;

  const _Pendencia({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.detalhe,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cor.withValues(alpha: isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icone, size: 21, color: cor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      if (detalhe.isNotEmpty)
                        Text(
                          detalhe,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.5,
                            height: 1.35,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Nada pendente": a frase que aparece quando não há nada a fazer.
///
/// Uma frase, e não um cartão vazio nem um espaço em branco. Tela vazia num
/// app que a pessoa abriu de propósito parece defeito; "está tudo em ordem" é
/// uma resposta.
class NadaPendente extends StatelessWidget {
  final bool mostrar;

  const NadaPendente({super.key, required this.mostrar});

  @override
  Widget build(BuildContext context) {
    if (!mostrar) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 34,
              color: AppColors.success.withValues(alpha: 0.7)),
          const SizedBox(height: 10),
          Text(
            'Tudo em ordem por aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nada esperando por você. As músicas e a escala estão nas abas '
            'de baixo.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              height: 1.45,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
