import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scale_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/scale_model.dart';
import '../../../data/services/firestore_service.dart';
import 'scale_detail_screen.dart';

class ScaleScreen extends StatefulWidget {
  const ScaleScreen({super.key});

  @override
  State<ScaleScreen> createState() => _ScaleScreenState();
}

class _ScaleScreenState extends State<ScaleScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  bool _isServiceDay(DateTime day) {
    final weekday = day.weekday;
    return weekday == DateTime.wednesday ||
        weekday == DateTime.friday ||
        weekday == DateTime.sunday;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final scale = context.watch<ScaleProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedScale = _selectedDay != null
        ? scale.getScaleForDay(_selectedDay!)
        : null;

    // Precompute the days that have a service for the focused month so the
    // calendar's per-cell lookup is O(1) instead of scanning all scales.
    final serviceDays =
        scale.getDaysWithServices(_focusedDay.year, _focusedDay.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escala'),
        actions: [
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _showCreateScaleDialog(context, scale, auth),
            ),
        ],
      ),
      body: Column(
        children: [
          // Calendar
          Container(
            color: isDark ? AppColors.surfaceDark : AppColors.white,
            child: TableCalendar(
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2027, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                });
              },
              onFormatChanged: (format) {
                setState(() => _calendarFormat = format);
              },
              onPageChanged: (focused) {
                setState(() => _focusedDay = focused);
              },
              eventLoader: (day) {
                final hasService =
                    serviceDays.contains(DateTime(day.year, day.month, day.day));
                return hasService ? [day] : [];
              },
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                selectedDecoration: const BoxDecoration(
                  color: AppColors.blue,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: AppColors.blue.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                markerDecoration: const BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: TextStyle(
                  fontFamily: 'Poppins',
                  color: AppColors.red.withOpacity(0.8),
                ),
                defaultTextStyle: TextStyle(
                  fontFamily: 'Poppins',
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
                selectedTextStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                todayTextStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  color: AppColors.blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
                weekendStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.red,
                ),
              ),
              headerStyle: HeaderStyle(
                titleTextStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
                formatButtonTextStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                ),
                formatButtonDecoration: BoxDecoration(
                  border: Border.all(color: AppColors.blue.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                leftChevronIcon: const Icon(Icons.chevron_left_rounded),
                rightChevronIcon: const Icon(Icons.chevron_right_rounded),
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (ctx, day, focused) {
                  final isHighlight = _isServiceDay(day);
                  if (!isHighlight) return null;
                  return Container(
                    margin: const EdgeInsets.all(4),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: AppColors.yellow,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          // Selected day content
          Expanded(
            child: _selectedDay == null
                ? _UpcomingServicesView(scale: scale)
                : _SelectedDayView(
                    day: _selectedDay!,
                    scaleModel: selectedScale,
                    auth: auth,
                    scale: scale,
                  ),
          ),
        ],
      ),
    );
  }

  void _showCreateScaleDialog(
      BuildContext context, ScaleProvider scale, AuthProvider auth) {
    if (_selectedDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selecione um dia no calendário primeiro')),
      );
      return;
    }

    if (scale.getScaleForDay(_selectedDay!) != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScaleDetailScreen(
            scale: scale.getScaleForDay(_selectedDay!)!,
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        String serviceType = 'Culto';
        return AlertDialog(
          title: Text(
            'Criar Culto - ${DateFormat('dd/MM/yyyy').format(_selectedDay!)}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 16),
          ),
          content: StatefulBuilder(builder: (ctx2, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: ['Culto', 'Ensaio', 'Especial'].map((type) {
                return RadioListTile<String>(
                  title: Text(type,
                      style: const TextStyle(fontFamily: 'Poppins')),
                  value: type,
                  groupValue: serviceType,
                  activeColor: AppColors.blue,
                  onChanged: (v) {
                    setDialogState(() => serviceType = v!);
                  },
                );
              }).toList(),
            );
          }),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final newScale = FirestoreService.createScaleModel(
                  date: _selectedDay!,
                  serviceType: serviceType,
                  createdBy: auth.user?.id,
                );
                await scale.createScale(newScale);
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScaleDetailScreen(scale: newScale),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
              child: const Text('Criar'),
            ),
          ],
        );
      },
    );
  }
}

class _UpcomingServicesView extends StatelessWidget {
  final ScaleProvider scale;
  const _UpcomingServicesView({required this.scale});

  @override
  Widget build(BuildContext context) {
    final upcoming = scale.getUpcomingScales(limit: 10);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (upcoming.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month_outlined,
                size: 56,
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Nenhum culto agendado',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: upcoming.length,
      itemBuilder: (ctx, i) => _ServiceCard(scale: upcoming[i]),
    );
  }
}

class _SelectedDayView extends StatelessWidget {
  final DateTime day;
  final ScaleModel? scaleModel;
  final AuthProvider auth;
  final ScaleProvider scale;

  const _SelectedDayView({
    required this.day,
    required this.scaleModel,
    required this.auth,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (scaleModel == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_available_rounded,
              size: 56,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhum culto em ${DateFormat('dd/MM').format(day)}',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            if (auth.isAdmin) ...[
              const SizedBox(height: 16),
              const Text(
                'Toque "+" no canto superior para criar um culto',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return _ServiceCard(scale: scaleModel!, onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScaleDetailScreen(scale: scaleModel!),
        ),
      );
    });
  }
}

class _ServiceCard extends StatelessWidget {
  final ScaleModel scale;
  final VoidCallback? onTap;

  const _ServiceCard({required this.scale, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap ??
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ScaleDetailScreen(scale: scale),
              ),
            );
          },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.warmGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd').format(scale.date),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                      Text(
                        DateFormat('MMM', 'pt_BR').format(scale.date).toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scale.serviceType,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE', 'pt_BR').format(scale.date),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.music_note_rounded,
                            size: 12, color: AppColors.blue),
                        const SizedBox(width: 3),
                        Text(
                          '${scale.songs.length}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppColors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.people_outline_rounded,
                            size: 12, color: AppColors.red),
                        const SizedBox(width: 3),
                        Text(
                          '${scale.confirmedCount}/${scale.levitas.length}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppColors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondaryLight),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
