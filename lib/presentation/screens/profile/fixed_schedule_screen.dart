import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/team_model.dart';
import '../../providers/agenda_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scale_provider.dart';
import '../../widgets/common/error_banner.dart';

/// The services that happen every week. Set once, and the app creates the
/// next four weeks by itself — nobody has to remember to open the calendar
/// and add Wednesday again.
class FixedScheduleScreen extends StatelessWidget {
  const FixedScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final agenda = context.watch<AgendaProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slots = agenda.slots;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda fixa'),
        actions: [
          if (slots.isNotEmpty)
            IconButton(
              tooltip: 'Novo horário',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _editarSlot(context, agenda, null),
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
                : slots.isEmpty
                    ? _PrimeiraVez(agenda: agenda)
                    : _Lista(agenda: agenda, isDark: isDark),
          ),
        ],
      ),
    );
  }

  static Future<void> _editarSlot(
      BuildContext context, AgendaProvider agenda, ScheduleSlot? slot) async {
    final resultado = await showModalBottomSheet<ScheduleSlot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditorSlot(slot: slot, equipes: agenda.teams),
    );
    if (resultado == null) return;

    final atuais = [...agenda.slots];
    final i = atuais.indexWhere((s) => s.id == resultado.id);
    if (i >= 0) {
      atuais[i] = resultado;
    } else {
      atuais.add(resultado);
    }
    atuais.sort((a, b) {
      final d = a.weekday.compareTo(b.weekday);
      return d != 0 ? d : (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute);
    });

    final erro = await agenda.saveSlots(atuais);
    if (!context.mounted) return;
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: AppColors.red),
      );
    }
  }
}

/// Nothing saved yet: offer the church's real week instead of a blank list.
class _PrimeiraVez extends StatefulWidget {
  final AgendaProvider agenda;
  const _PrimeiraVez({required this.agenda});

  @override
  State<_PrimeiraVez> createState() => _PrimeiraVezState();
}

class _PrimeiraVezState extends State<_PrimeiraVez> {
  bool _criando = false;

  Future<void> _criar() async {
    setState(() => _criando = true);
    final equipes = widget.agenda.teams;

    // Matches the two teams by name when they exist, so the five services
    // already come scheduled instead of empty.
    String acharEquipe(List<String> pistas) {
      for (final t in equipes) {
        final n = t.name.toLowerCase();
        if (pistas.any(n.contains)) return t.id;
      }
      return '';
    }

    final erro = await widget.agenda.criarAgendaPadrao(
      equipeManha: acharEquipe(['manhã', 'manha']),
      equipeNoite: acharEquipe(['noite']),
    );
    if (!mounted) return;
    setState(() => _criando = false);
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: AppColors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_repeat_rounded,
                size: 56, color: Colors.grey.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            const Text(
              'Os cultos da semana',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 17,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure uma vez e o app cria os cultos das próximas 4 '
              'semanas sozinho, já com a equipe escalada.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                height: 1.45,
                color: AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quarta · 08:00 e 19:30',
                      style:
                          TextStyle(fontFamily: 'Poppins', fontSize: 13.5)),
                  SizedBox(height: 4),
                  Text('Sexta · 19:30',
                      style:
                          TextStyle(fontFamily: 'Poppins', fontSize: 13.5)),
                  SizedBox(height: 4),
                  Text('Domingo · 08:00 e 19:00',
                      style:
                          TextStyle(fontFamily: 'Poppins', fontSize: 13.5)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _criando ? null : _criar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _criando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Usar estes 5 cultos',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Dá para mudar horário, nome e equipe depois.',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  color: AppColors.textSecondaryLight),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  final AgendaProvider agenda;
  final bool isDark;
  const _Lista({required this.agenda, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final slots = agenda.slots;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'O app cria os cultos das próximas 4 semanas quando você abre, '
            'já com a equipe escalada e todos como não confirmados.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondaryLight,
            ),
          ),
        ),
        ...slots.map((s) => _LinhaSlot(
              slot: s,
              equipe: agenda.teamById(s.teamId),
              isDark: isDark,
              onEditar: () =>
                  FixedScheduleScreen._editarSlot(context, agenda, s),
              onRemover: () async {
                final restantes =
                    slots.where((o) => o.id != s.id).toList();
                final erro = await agenda.saveSlots(restantes);
                if (!context.mounted) return;
                if (erro != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(erro), backgroundColor: AppColors.red),
                  );
                }
              },
            )),
        const SizedBox(height: 10),
        _BotaoGerarAgora(agenda: agenda),
      ],
    );
  }
}

/// Lets the leader create the services now instead of waiting for the next
/// app start — useful right after changing the schedule.
class _BotaoGerarAgora extends StatefulWidget {
  final AgendaProvider agenda;
  const _BotaoGerarAgora({required this.agenda});

  @override
  State<_BotaoGerarAgora> createState() => _BotaoGerarAgoraState();
}

class _BotaoGerarAgoraState extends State<_BotaoGerarAgora> {
  bool _gerando = false;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _gerando
          ? null
          : () async {
              setState(() => _gerando = true);
              final scale = context.read<ScaleProvider>();
              final auth = context.read<AuthProvider>();
              final antes = scale.scales.length;
              final erro = await scale.gerarProximos(
                slots: widget.agenda.slots,
                equipes: widget.agenda.teamsById,
                createdBy: auth.user?.id,
              );
              if (!mounted) return;
              setState(() => _gerando = false);
              final criados = scale.scales.length - antes;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(erro ??
                      (criados <= 0
                          ? 'As próximas 4 semanas já estavam criadas.'
                          : '$criados ${criados == 1 ? "culto criado" : "cultos criados"}.')),
                  backgroundColor:
                      erro == null ? AppColors.success : AppColors.red,
                ),
              );
            },
      icon: _gerando
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.event_available_rounded, size: 18),
      label: const Text('Criar os cultos agora',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blue,
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
    );
  }
}

class _LinhaSlot extends StatelessWidget {
  final ScheduleSlot slot;
  final TeamModel? equipe;
  final bool isDark;
  final VoidCallback onEditar;
  final VoidCallback onRemover;

  const _LinhaSlot({
    required this.slot,
    required this.equipe,
    required this.isDark,
    required this.onEditar,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: onEditar,
        leading: Container(
          width: 46,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            slot.horaFormatada,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.blue,
            ),
          ),
        ),
        title: Text(
          '${slot.diaDaSemana} · ${slot.name}',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimaryLight,
          ),
        ),
        subtitle: Text(
          equipe?.name ?? 'Sem equipe padrão',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: equipe == null
                ? AppColors.red
                : AppColors.textSecondaryLight,
          ),
        ),
        trailing: IconButton(
          tooltip: 'Remover da agenda',
          icon: const Icon(Icons.close_rounded, size: 18),
          onPressed: onRemover,
        ),
      ),
    );
  }
}

/// Edit one line of the schedule: weekday, time, name and default team.
class _EditorSlot extends StatefulWidget {
  final ScheduleSlot? slot;
  final List<TeamModel> equipes;
  const _EditorSlot({this.slot, required this.equipes});

  @override
  State<_EditorSlot> createState() => _EditorSlotState();
}

class _EditorSlotState extends State<_EditorSlot> {
  late int _weekday = widget.slot?.weekday ?? 7;
  late TimeOfDay _hora = TimeOfDay(
      hour: widget.slot?.hour ?? 19, minute: widget.slot?.minute ?? 0);
  late final TextEditingController _nome =
      TextEditingController(text: widget.slot?.name ?? 'Culto');
  late String _teamId = widget.slot?.teamId ?? '';

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const dias = {
      1: 'Seg', 2: 'Ter', 3: 'Qua', 4: 'Qui', 5: 'Sex', 6: 'Sáb', 7: 'Dom',
    };

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 10, 20, MediaQuery.of(context).viewInsets.bottom + 28),
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
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            widget.slot == null ? 'Novo horário fixo' : 'Editar horário',
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 17,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          const Text('Dia da semana',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: dias.entries.map((e) {
              final sel = _weekday == e.key;
              return GestureDetector(
                onTap: () => setState(() => _weekday = e.key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: sel
                            ? AppColors.blue
                            : Colors.grey.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
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
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_rounded,
                      color: AppColors.blue),
                  title: const Text('Horário',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                  subtitle: Text(
                    _hora.format(context),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.blue,
                    ),
                  ),
                  onTap: () async {
                    final p = await showTimePicker(
                        context: context, initialTime: _hora);
                    if (p != null) setState(() => _hora = p);
                  },
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _nome,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Equipe padrão',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...widget.equipes.map((t) {
                final sel = _teamId == t.id;
                return GestureDetector(
                  onTap: () => setState(() => _teamId = t.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.blue : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: sel
                              ? AppColors.blue
                              : Colors.grey.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      t.name,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        color: sel
                            ? Colors.white
                            : (isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight),
                      ),
                    ),
                  ),
                );
              }),
              if (widget.equipes.isEmpty)
                const Text(
                  'Crie uma equipe primeiro, em Perfil → Equipes.',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: AppColors.red),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final id = widget.slot?.id ??
                    '${const {
                      1: 'seg', 2: 'ter', 3: 'qua', 4: 'qui',
                      5: 'sex', 6: 'sab', 7: 'dom',
                    }[_weekday]}'
                        '-${_hora.hour.toString().padLeft(2, '0')}'
                        '${_hora.minute.toString().padLeft(2, '0')}';
                Navigator.pop(
                  context,
                  ScheduleSlot(
                    id: id,
                    weekday: _weekday,
                    hour: _hora.hour,
                    minute: _hora.minute,
                    name: _nome.text.trim().isEmpty
                        ? 'Culto'
                        : _nome.text.trim(),
                    teamId: _teamId,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Salvar',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
