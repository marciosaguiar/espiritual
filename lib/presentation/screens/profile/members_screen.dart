import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/scale_provider.dart';

/// Ministry roster. Leaders use this to promote or step someone down —
/// the sign-up form no longer lets people pick their own role.
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Membros do ministério')),
      body: StreamBuilder<List<UserModel>>(
        stream: AuthService.getAllUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.wifi_off_rounded,
              title: 'Não foi possível carregar os membros',
              detail: 'Verifique sua conexão e tente novamente.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.blue),
            );
          }

          final members = snapshot.data!;
          if (members.isEmpty) {
            return _Message(
              icon: Icons.people_outline_rounded,
              title: 'Nenhum membro cadastrado',
              detail: 'Peça para o pessoal criar a conta no app.',
            );
          }

          // Três grupos, porque são três decisões diferentes: quem espera uma
          // resposta, quem já está dentro, e quem saiu — este último visível
          // de propósito, para um "não" por engano ter conserto.
          // Robô fora de tudo: a faxina do chat e o servidor dos avisos
          // entram como líderes comuns, e apareciam aqui como se fossem
          // gente — inclusive na contagem "3 líderes · 5 membros".
          //
          // Os nomes ficam: o robô pode ter removido alguém, e a linha
          // "saiu em 14/11, por Faxina" precisa saber traduzir o id.
          final nomes = {for (final m in members) m.id: m.name};
          final gente = members.where((m) => !m.bot).toList();

          final pendentes = gente.where((m) => m.isPendente).toList();
          final equipe = gente.where((m) => m.aprovado).toList();
          final removidos = gente.where((m) => m.isRemovido).toList();
          final robos = members.where((m) => m.bot && m.aprovado).toList();
          final leaders = equipe.where((m) => m.isAdmin).length;

          Widget linha(UserModel m) => _MemberRow(
                member: m,
                isMe: m.id == auth.user?.id,
                canManage: auth.isAdmin,
                isDark: isDark,
              );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            children: [
              if (pendentes.isNotEmpty && auth.isAdmin) ...[
                _Secao(
                  titulo: pendentes.length == 1
                      ? '1 pessoa aguardando você'
                      : '${pendentes.length} pessoas aguardando você',
                  detalhe: 'Enquanto você não aprovar, elas não veem o '
                      'repertório, a escala nem o chat.',
                  destaque: true,
                  isDark: isDark,
                ),
                ...pendentes.map((m) => _PendenteRow(member: m, isDark: isDark)),
                const SizedBox(height: 22),
              ],
              _Secao(
                titulo: 'Equipe',
                detalhe: '$leaders ${leaders == 1 ? 'líder' : 'líderes'} · '
                    '${equipe.length} ${equipe.length == 1 ? 'membro' : 'membros'}',
                isDark: isDark,
              ),
              // QUEM AINDA NÃO PODE RECUPERAR A SENHA.
              //
              // Isto fica aqui, e não escondido num menu, porque é a única
              // coisa deste app que não tem conserto depois: conta sem e-mail
              // cadastrado, com a senha perdida, é acesso perdido — trocar a
              // senha de outra pessoa exige chave de administrador, que este
              // projeto não tem, e o console do Firebase também não faz isso.
              //
              // Só vale enquanto a pessoa ainda entra, porque cadastrar o
              // e-mail pede a senha atual. Por isso o líder precisa ver a
              // lista ANTES de alguém esquecer.
              if (auth.isAdmin)
                _SemRecuperacao(
                  quantos: equipe.where((m) => !m.recuperacaoPorEmail).length,
                  isDark: isDark,
                ),
              if (equipe.isEmpty)
                _Message(
                  icon: Icons.people_outline_rounded,
                  title: 'Ninguém aprovado ainda',
                  detail: 'Aprove alguém acima para montar a equipe.',
                )
              else
                ...equipe.map(linha),
              if (robos.isNotEmpty && auth.isAdmin) ...[
                const SizedBox(height: 22),
                _SecaoRecolhida(
                  titulo: 'Contas de robô (${robos.length})',
                  isDark: isDark,
                  filhos: robos.map(linha).toList(),
                ),
              ],
              if (removidos.isNotEmpty && auth.isAdmin) ...[
                const SizedBox(height: 22),
                _SecaoRecolhida(
                  titulo: 'Removidos (${removidos.length})',
                  isDark: isDark,
                  filhos: removidos
                      .map((m) => _RemovidoRow(
                            member: m,
                            porQuem: nomes[m.removedBy],
                            isDark: isDark,
                          ))
                      .toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// "3 pessoas não conseguem recuperar a senha" — para o líder, na Equipe.
class _SemRecuperacao extends StatelessWidget {
  final int quantos;
  final bool isDark;

  const _SemRecuperacao({required this.quantos, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (quantos == 0) {
      // Zero não vira tarja verde: um aviso que fica na tela quando não há
      // nada a fazer ensina a não olhar para ele.
      return const SizedBox.shrink();
    }

    final um = quantos == 1;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, size: 18, color: AppColors.red),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  um
                      ? '1 pessoa não consegue recuperar a senha'
                      : '$quantos pessoas não conseguem recuperar a senha',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  um
                      ? 'Ela ainda não cadastrou e-mail. Se esquecer a senha, '
                          'não há como devolver o acesso — nem por você. Peça '
                          'que faça agora, em Perfil → Recuperar a senha.'
                      : 'Elas ainda não cadastraram e-mail. Quem esquecer a '
                          'senha perde o acesso, e nem você consegue devolver. '
                          'Peça que façam agora, em Perfil → Recuperar a senha.',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatefulWidget {
  final UserModel member;
  final bool isMe;
  final bool canManage;
  final bool isDark;

  const _MemberRow({
    required this.member,
    required this.isMe,
    required this.canManage,
    required this.isDark,
  });

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  bool _saving = false;

  Future<void> _changeRole(UserRole role) async {
    final label = role == UserRole.admin ? 'Líder' : 'Levita';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tornar $label?'),
        content: Text(
          role == UserRole.admin
              ? '${widget.member.name} poderá criar cultos, montar escalas e '
                  'cadastrar músicas.'
              : '${widget.member.name} deixará de gerenciar cultos, escalas e '
                  'músicas.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final result = await AuthService.setUserRole(widget.member, role);
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? '${widget.member.name} agora é $label.'
              : result.error ?? 'Não foi possível alterar a função.',
        ),
        backgroundColor: result.success ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// Tira a pessoa do ministério: perde o acesso, sai das equipes e dos
  /// cultos que ainda não aconteceram, e some das telas — sem apagar nada.
  Future<void> _remover() async {
    final m = widget.member;

    // O limite do último líder é conferido antes de perguntar: avisar depois
    // de a pessoa confirmar seria fazê-la decidir duas vezes.
    if (m.isAdmin && await AuthService.adminCount() <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O ministério precisa de pelo menos um líder. '
              'Promova outra pessoa antes.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remover ${m.name} do ministério?'),
        content: Text(
          '${m.name} perde o acesso ao chat, às escalas e às músicas. '
          'Dá para devolver depois em Membros > Removidos.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final eu = context.read<AuthProvider>().user?.id ?? '';
    final equipes = context.read<AgendaProvider>().teams;
    // Só os cultos que o app tem na memória, que é a janela de 60/90 dias.
    // O gerador só cria 4 semanas à frente, então não há culto futuro fora
    // dela — e, se um dia houver, ele aparece ao líder como "faltando
    // alguém" em vez de sumir calado.
    final escalas = context.read<ScaleProvider>().scales;

    setState(() => _saving = true);
    final r = await FirestoreService.removerDoMinisterio(
      alvo: m,
      porQuemId: eu,
      equipes: equipes,
      escalas: escalas,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.success
            // "Saiu" é o que a própria pessoa faz, em Perfil. Aqui quem
            // decidiu foi o líder, e a frase tem de dizer isso.
            ? '${m.name} foi removido do ministério.'
            : r.error ?? 'Não foi possível remover.'),
        backgroundColor: r.success ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// Marca (ou desmarca) a conta como robô.
  ///
  /// Robô sai de tudo: lista, contagem, equipes, escalas e avisos — e deixa
  /// de contar na proteção do último líder. Por isso marcar exige confirmar
  /// com o nome, como remover: marcar uma pessoa por engano a tiraria das
  /// escalas sem ela entender o motivo.
  Future<void> _marcarRobo(bool virarRobo) async {
    final m = widget.member;

    // Um robô que fosse o último líder "de verdade" deixaria o ministério sem
    // ninguém que aprove. A conta é a mesma do remover, e vem antes de
    // perguntar.
    if (virarRobo && m.isAdmin && await AuthService.adminCount() <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este é o único líder de verdade. Promova outra '
              'pessoa antes de marcar esta conta como robô.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(virarRobo
            ? 'Marcar ${m.name} como robô?'
            : '${m.name} é uma pessoa?'),
        content: Text(
          virarRobo
              ? 'Contas de robô (a faxina do chat, o servidor dos avisos) '
                  'somem da lista de membros e das contagens, não entram em '
                  'equipe nem em escala, não recebem avisos e não contam como '
                  'líder.\n\nNão use isto numa pessoa.'
              : '${m.name} volta a aparecer na lista de membros, nas equipes '
                  'e nas escalas.',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: virarRobo ? AppColors.blue : AppColors.success),
            child: Text(virarRobo ? 'É um robô' : 'É uma pessoa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    final erro = await FirestoreService.marcarComoBot(m, virarRobo);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(erro ??
            (virarRobo
                ? '${m.name} agora é uma conta de robô.'
                : '${m.name} voltou a ser uma pessoa.')),
        backgroundColor: erro == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// Explains why the app cannot set someone else's password any more.
  ///
  /// Sign-in moved to Firebase Authentication, which only lets an account
  /// change its own password. Doing it for another person needs the Admin SDK
  /// running on a server, which an app cannot do.
  void _explainPasswordReset() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Senha de ${widget.member.name}'),
        content: const Text(
          AuthService.leaderResetUnavailable,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final isDark = widget.isDark;
    final accent = m.isAdmin ? AppColors.red : AppColors.blue;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.white.withOpacity(0.65),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: accent.withOpacity(0.15),
            child: Text(
              m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                    ),
                    if (widget.isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          '(você)',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11.5,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  // TODAS as funções, aqui: é nesta tela que o líder decide
                  // quem pode ser escalado em quê. Nas outras telas aparece
                  // só a principal, onde só cabe uma.
                  '${m.isAdmin ? '👑 Líder' : '🎵 Levita'} · '
                  '${m.instruments.map((f) => '${f.emoji} ${f.label}').join(' · ')}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          if (widget.canManage) ...[
            const SizedBox(width: 4),
            if (_saving)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              PopupMenuButton<String>(
                tooltip: 'Opções',
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (value) {
                  if (value == 'role') {
                    _changeRole(m.isAdmin ? UserRole.levita : UserRole.admin);
                  } else if (value == 'password') {
                    _explainPasswordReset();
                  } else if (value == 'remover') {
                    _remover();
                  } else if (value == 'robo') {
                    _marcarRobo(!m.bot);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'role',
                    child: Row(
                      children: [
                        Icon(
                          m.isAdmin
                              ? Icons.person_outline_rounded
                              : Icons.workspace_premium_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(m.isAdmin ? 'Tornar levita' : 'Tornar líder'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'password',
                    child: Row(
                      children: [
                        Icon(Icons.help_outline_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Senha esquecida?'),
                      ],
                    ),
                  ),
                  // Marcar robô não aparece na própria linha: ninguém se
                  // esconde do ministério por engano.
                  if (!widget.isMe)
                    PopupMenuItem(
                      value: 'robo',
                      child: Row(
                        children: [
                          Icon(
                            m.bot
                                ? Icons.person_outline_rounded
                                : Icons.smart_toy_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(m.bot ? 'É uma pessoa' : 'É uma conta de robô'),
                        ],
                      ),
                    ),
                  // Nunca na própria linha: sair do ministério é decisão de
                  // quem sai, e fica em Perfil → Sair do ministério.
                  if (!widget.isMe)
                    const PopupMenuItem(
                      value: 'remover',
                      child: Row(
                        children: [
                          Icon(Icons.person_remove_outlined,
                              size: 18, color: AppColors.red),
                          SizedBox(width: 10),
                          Text('Remover do ministério',
                              style: TextStyle(color: AppColors.red)),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// Seção que começa fechada. Os removidos são história: precisam existir
/// para um engano ter conserto, mas não podem disputar espaço com quem está
/// esperando uma resposta.
class _SecaoRecolhida extends StatefulWidget {
  final String titulo;
  final List<Widget> filhos;
  final bool isDark;

  const _SecaoRecolhida({
    required this.titulo,
    required this.filhos,
    required this.isDark,
  });

  @override
  State<_SecaoRecolhida> createState() => _SecaoRecolhidaState();
}

class _SecaoRecolhidaState extends State<_SecaoRecolhida> {
  bool _aberta = false;

  @override
  Widget build(BuildContext context) {
    final cor = widget.isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _aberta = !_aberta),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _aberta
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.chevron_right_rounded,
                  size: 22,
                  color: cor,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.titulo,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (_aberta) ...widget.filhos,
      ],
    );
  }
}

/// Quem saiu ou foi tirado do ministério, com a data e quem fez.
class _RemovidoRow extends StatefulWidget {
  final UserModel member;
  final String? porQuem;
  final bool isDark;

  const _RemovidoRow({
    required this.member,
    required this.porQuem,
    required this.isDark,
  });

  @override
  State<_RemovidoRow> createState() => _RemovidoRowState();
}

class _RemovidoRowState extends State<_RemovidoRow> {
  bool _salvando = false;

  String get _quando {
    final d = widget.member.removedAt;
    if (d == null) return 'saiu agora';
    String dois(int v) => v.toString().padLeft(2, '0');
    return 'saiu em ${dois(d.day)}/${dois(d.month)}/${d.year}';
  }

  Future<void> _devolver() async {
    setState(() => _salvando = true);
    final r = await FirestoreService.devolverAcesso(widget.member.id);
    if (!mounted) return;
    setState(() => _salvando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.success
            ? '${widget.member.name} voltou como levita. Escale de novo '
                'quando quiser.'
            : r.error ?? 'Não foi possível devolver o acesso.'),
        backgroundColor: r.success ? AppColors.success : AppColors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final isDark = widget.isDark;
    final fraca = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.porQuem == null
                      ? _quando
                      : '$_quando · por ${widget.porQuem}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: fraca,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_salvando)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            OutlinedButton(
              onPressed: _devolver,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.blue,
                side: BorderSide(color: AppColors.blue.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Devolver acesso'),
            ),
        ],
      ),
    );
  }
}

/// Cabeçalho de um dos três grupos da lista.
class _Secao extends StatelessWidget {
  final String titulo;
  final String detalhe;
  final bool destaque;
  final bool isDark;

  const _Secao({
    required this.titulo,
    required this.detalhe,
    required this.isDark,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final cor = destaque
        ? AppColors.blue
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detalhe,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.5,
              height: 1.4,
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

/// Quem está esperando uma resposta do líder: aprovar ou recusar.
///
/// Recusar não apaga ninguém — o app não tem como apagar uma conta, e as
/// regras proíbem. A pessoa vai para o mesmo estado de quem foi removido
/// depois de aprovado (é a mesma coisa: sem acesso, com volta possível) e
/// aparece em "Removidos", onde o líder consegue devolver o acesso.
class _PendenteRow extends StatefulWidget {
  final UserModel member;
  final bool isDark;

  const _PendenteRow({required this.member, required this.isDark});

  @override
  State<_PendenteRow> createState() => _PendenteRowState();
}

class _PendenteRowState extends State<_PendenteRow> {
  bool _salvando = false;

  Future<void> _decidir(UserRole papel) async {
    final m = widget.member;

    if (papel == UserRole.removido) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Recusar ${m.name}?'),
          content: const Text(
            'A pessoa continua sem ver o repertório, a escala e o chat. '
            'Você pode liberar a entrada depois, se for engano.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('Recusar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _salvando = true);
    final r = await AuthService.setUserRole(m, papel);
    if (!mounted) return;
    setState(() => _salvando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.success
              ? (papel == UserRole.levita
                  ? '${m.name} entrou no ministério.'
                  : '${m.name} não foi aprovado.')
              : r.error ?? 'Não foi possível salvar.',
        ),
        backgroundColor: r.success ? AppColors.success : AppColors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final isDark = widget.isDark;
    const esperando = true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: esperando
            ? AppColors.blue.withValues(alpha: isDark ? 0.14 : 0.07)
            : (isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: esperando
              ? AppColors.blue.withValues(alpha: 0.35)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.65)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.blue.withValues(alpha: 0.15),
                child: Text(
                  m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                    Text(
                      '${m.instrument.emoji} ${m.instrument.label}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_salvando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            )
          else
            Row(
              children: [
                if (esperando) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _decidir(UserRole.removido),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: BorderSide(
                            color: AppColors.red.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      child: const Text('Recusar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _decidir(UserRole.levita),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: const Text('Aprovar'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 46,
                color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 14),
            Text(
              title,
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
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
