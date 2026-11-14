import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/team_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scale_provider.dart';
import '../../widgets/common/error_banner.dart';
import '../../widgets/common/glass.dart';

/// Teams the leader sets up once: who plays in the morning, who plays at
/// night. The standing schedule puts them on the services by itself.
class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final agenda = context.watch<AgendaProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipes'),
        actions: [
          IconButton(
            tooltip: 'Nova equipe',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _editarEquipe(context, null),
          ),
        ],
      ),
      body: Column(
        children: [
          ErrorBanner.maybe(agenda.error, onRetry: agenda.retry),
          Expanded(
            child: agenda.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.blue))
                : agenda.teams.isEmpty
                    ? _Vazio(onCriar: () => _editarEquipe(context, null))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: agenda.teams.length,
                        itemBuilder: (_, i) => _CartaoEquipe(
                          equipe: agenda.teams[i],
                          isDark: isDark,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  static Future<void> _editarEquipe(
      BuildContext context, TeamModel? equipe) async {
    await Navigator.push(
      context,
      GlassPageRoute(builder: (_) => _EditorEquipe(equipe: equipe)),
    );
  }
}

class _Vazio extends StatelessWidget {
  final VoidCallback onCriar;
  const _Vazio({required this.onCriar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.groups_outlined,
                size: 56, color: Colors.grey.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            const Text(
              'Nenhuma equipe ainda',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Crie "Equipe Manhã" e "Equipe Noite" para a agenda fixa '
              'escalar sozinha os cultos da semana.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                height: 1.45,
                color: AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onCriar,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Criar equipe',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoEquipe extends StatelessWidget {
  final TeamModel equipe;
  final bool isDark;
  const _CartaoEquipe({required this.equipe, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => TeamsScreen._editarEquipe(context, equipe),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.groups_rounded,
                  color: AppColors.blue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    equipe.name,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    equipe.members.isEmpty
                        ? 'Sem ninguém ainda'
                        : '${equipe.members.length} '
                            '${equipe.members.length == 1 ? "pessoa" : "pessoas"}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondaryLight),
          ],
        ),
      ),
    );
  }
}

/// Create or edit one team: the name and who is in it.
class _EditorEquipe extends StatefulWidget {
  final TeamModel? equipe;
  const _EditorEquipe({this.equipe});

  @override
  State<_EditorEquipe> createState() => _EditorEquipeState();
}

class _EditorEquipeState extends State<_EditorEquipe> {
  late final TextEditingController _nome =
      TextEditingController(text: widget.equipe?.name ?? '');
  late Map<String, String> _membros = {
    for (final m in widget.equipe?.members ?? const <TeamMember>[])
      m.userId: m.instrument
  };
  bool _salvando = false;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  bool get _ehNova => widget.equipe == null;

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Dê um nome à equipe.'),
            backgroundColor: AppColors.red),
      );
      return;
    }

    setState(() => _salvando = true);
    final agenda = context.read<AgendaProvider>();
    final auth = context.read<AuthProvider>();

    final membros = _membros.entries
        .map((e) => TeamMember(userId: e.key, instrument: e.value))
        .toList();

    final equipe = _ehNova
        ? FirestoreService.createTeamModel(
            name: nome, members: membros, createdBy: auth.user?.id)
        : widget.equipe!.copyWith(name: nome, members: membros);

    final erro = await agenda.saveTeam(equipe);
    if (!mounted) return;

    if (erro != null) {
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: AppColors.red),
      );
      return;
    }

    // An existing team already has services scheduled with the old line-up;
    // ask before touching them.
    if (!_ehNova) {
      final aplicar = await _perguntarSeAplica(equipe);
      if (aplicar && mounted) {
        final r = await context
            .read<ScaleProvider>()
            .aplicarEquipeNosProximos(equipe);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(r.error ??
                (r.atualizados == 0
                    ? 'Nenhum culto precisou mudar.'
                    : '${r.atualizados} '
                        '${r.atualizados == 1 ? "culto atualizado" : "cultos atualizados"}.')),
            backgroundColor: r.error == null ? AppColors.success : AppColors.red,
          ),
        );
      }
    }

    if (mounted) Navigator.pop(context);
  }

  Future<bool> _perguntarSeAplica(TeamModel equipe) async {
    final resposta = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aplicar aos próximos cultos?'),
        content: const Text(
          'Os cultos futuros desta equipe passam a ter esta formação.\n\n'
          'Cultos que você já ajustou à mão ficam como estão, e quem já '
          'confirmou presença continua confirmado.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Só salvar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    return resposta ?? false;
  }

  Future<void> _apagar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar ${widget.equipe!.name}?'),
        content: const Text(
          'Os cultos já criados continuam com as pessoas que estão neles. '
          'A agenda fixa deixa de escalar esta equipe.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar',
                style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final erro =
        await context.read<AgendaProvider>().deleteTeam(widget.equipe!.id);
    if (!mounted) return;
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: AppColors.red),
      );
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_ehNova ? 'Nova equipe' : 'Editar equipe'),
        actions: [
          if (!_ehNova)
            IconButton(
              tooltip: 'Apagar equipe',
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.red),
              onPressed: _salvando ? null : _apagar,
            ),
        ],
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: AuthService.getAllUsers(),
        builder: (context, snap) {
          final pessoas = snap.data ?? const <UserModel>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
            children: [
              TextField(
                controller: _nome,
                decoration: const InputDecoration(
                  labelText: 'Nome da equipe',
                  hintText: 'Ex: Equipe Manhã',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 26),
              Text(
                'Quem toca nesta equipe',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Toque para incluir. O instrumento aqui pode ser diferente do '
                'instrumento do perfil.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 12),
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                      child: CircularProgressIndicator(color: AppColors.blue)),
                )
              else
                ...pessoas.map((p) => _LinhaPessoa(
                      pessoa: p,
                      instrumento: _membros[p.id],
                      isDark: isDark,
                      onToggle: () => setState(() {
                        if (_membros.containsKey(p.id)) {
                          _membros = {..._membros}..remove(p.id);
                        } else {
                          _membros = {
                            ..._membros,
                            p.id: p.instrument.name,
                          };
                        }
                      }),
                      onInstrumento: (novo) => setState(() {
                        _membros = {..._membros, p.id: novo};
                      }),
                    )),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _salvando ? null : _salvar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _salvando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _ehNova ? 'Criar equipe' : 'Salvar',
                      style: const TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinhaPessoa extends StatelessWidget {
  final UserModel pessoa;
  final String? instrumento;
  final bool isDark;
  final VoidCallback onToggle;
  final ValueChanged<String> onInstrumento;

  const _LinhaPessoa({
    required this.pessoa,
    required this.instrumento,
    required this.isDark,
    required this.onToggle,
    required this.onInstrumento,
  });

  @override
  Widget build(BuildContext context) {
    final dentro = instrumento != null;
    final inst = UserInstrumentExtension.fromString(
        instrumento ?? pessoa.instrument.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: dentro
            ? AppColors.blue.withValues(alpha: 0.08)
            : (isDark ? AppColors.cardDark : AppColors.cardLight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dentro
              ? AppColors.blue.withValues(alpha: 0.4)
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: onToggle,
            leading: Icon(
              dentro
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: dentro ? AppColors.blue : Colors.grey,
            ),
            title: Text(
              pessoa.name,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: dentro ? FontWeight.w600 : FontWeight.w400,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            subtitle: dentro
                ? Text('${inst.emoji} ${inst.label}',
                    style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 12))
                : null,
          ),
          if (dentro)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: UserInstrument.values.map((i) {
                  final sel = i.name == instrumento;
                  return GestureDetector(
                    onTap: () => onInstrumento(i.name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.blue : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: sel
                              ? AppColors.blue
                              : Colors.grey.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${i.emoji} ${i.label}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: sel
                              ? Colors.white
                              : (isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
