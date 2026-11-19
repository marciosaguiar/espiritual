import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scale_provider.dart';
import '../../providers/songs_provider.dart';
import '../../../core/utils/texto.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/scale_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/avisos_service.dart';
import '../../widgets/common/abrir_link.dart';
import '../../widgets/common/glass.dart';
import '../songs/song_detail_screen.dart';
import 'modo_ao_vivo_screen.dart';
import '../../widgets/songs/escolher_musicas.dart';

class ScaleDetailScreen extends StatefulWidget {
  final ScaleModel scale;
  const ScaleDetailScreen({super.key, required this.scale});

  @override
  State<ScaleDetailScreen> createState() => _ScaleDetailScreenState();
}

class _ScaleDetailScreenState extends State<ScaleDetailScreen> {
  late ScaleModel _scale;
  final _observationsCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scale = widget.scale;
    _observationsCtrl.text = _scale.observations;
  }

  @override
  void dispose() {
    _observationsCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmPresence(AuthProvider auth) async {
    final user = auth.user;
    if (user == null) return;

    final isConfirmed = _scale.hasUserConfirmed(user.id);
    final provider = context.read<ScaleProvider>();

    final error =
        await provider.confirmPresence(_scale.id, user.id, !isConfirmed);
    if (!mounted) return;

    if (error == null) {
      final updated = provider.scales
          .firstWhere((s) => s.id == _scale.id, orElse: () => _scale);
      setState(() => _scale = updated);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ??
            (!isConfirmed ? 'Presença confirmada!' : 'Presença cancelada')),
        backgroundColor: error == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// Leader fixes the service's date and time.
  Future<void> _editDateTime() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _scale.date,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      helpText: 'Data do culto',
    );
    if (data == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scale.date),
      helpText: 'A que horas começa?',
    );
    if (hora == null || !mounted) return;

    final novo =
        DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
    final error = await context
        .read<ScaleProvider>()
        .updateDetails(_scale.id, date: novo);

    if (!mounted) return;
    if (error == null) setState(() => _scale = _scale.copyWith(date: novo));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Culto remarcado.'),
        backgroundColor: error == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  /// Cancels (or reinstates) without deleting.
  ///
  /// A service from the standing schedule has an id built from its date and
  /// time: deleting it would only make the next app start create it again.
  Future<void> _cancelarOuReativar(bool cancelar) async {
    if (cancelar) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancelar este culto?'),
          content: const Text(
            'Ele deixa de aparecer como próximo culto e ninguém é cobrado '
            'para confirmar presença. A agenda fixa continua igual: só este '
            'dia é cancelado.\n\nDÁ PARA DESFAZER: o culto não é apagado, e '
            '"Reativar culto" no mesmo menu traz tudo de volta, inclusive '
            'quem já tinha confirmado.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Voltar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancelar culto',
                  style: TextStyle(color: AppColors.red)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final erro =
        await context.read<ScaleProvider>().setCanceled(_scale.id, cancelar);
    if (!mounted) return;
    if (erro == null)
      setState(() => _scale = _scale.copyWith(canceled: cancelar));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(erro ?? (cancelar ? 'Culto cancelado.' : 'Culto reativado.')),
        backgroundColor: erro == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  Future<void> _saveObservations() async {
    setState(() => _isSaving = true);
    final texto = _observationsCtrl.text;
    final error = await context
        .read<ScaleProvider>()
        .updateDetails(_scale.id, observations: texto);

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (error == null) _scale = _scale.copyWith(observations: texto);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Observações salvas.'),
        backgroundColor: error == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  Future<void> _showAddSongDialog() async {
    final songs = context.read<SongsProvider>();
    if (songs.repertorio.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma música no repertório ainda.')),
      );
      return;
    }

    final selected = await escolherMusicas(
      context,
      jaNoCulto: _scale.songs.map((s) => s.songId).toList(),
    );
    if (selected == null || !mounted) return;

    // Só a referência é guardada: nome, artista e tom são resolvidos pela
    // música na hora de desenhar, então corrigir uma música corrige também
    // todos os cultos que a usam.
    final scaleSongs = selected.map((s) => ScaleSong(songId: s.id)).toList();
    final error =
        await context.read<ScaleProvider>().setSongs(_scale.id, scaleSongs);

    if (!mounted) return;
    if (error == null) {
      setState(() => _scale = _scale.copyWith(songs: scaleSongs));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.red),
      );
    }
  }

  /// A função de cada pessoa NESTE culto, escolhida no diálogo de escalar.
  Map<String, String> _funcaoEscolhida = const {};

  /// Em que função EU vou neste culto, se estou escalado.
  ///
  /// Nulo quando não estou na escala: aí a música abre como sempre, pelo que
  /// escolhi no perfil.
  UserInstrument? _minhaFuncaoNesteCulto(BuildContext context) {
    final eu = context.read<AuthProvider>().user?.id;
    if (eu == null) return null;
    for (final l in _scale.levitas) {
      if (l.userId == eu) {
        return UserInstrumentExtension.fromString(l.instrument);
      }
    }
    return null;
  }

  Future<void> _showAddLevitaDialog() async {
    final List<UserModel> allUsers = await AuthService.watchEscalaveis().first;

    if (!mounted) return;

    final List<String>? selectedIds = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final currentIds = _scale.levitas.map((l) => l.userId).toSet();
        // Em qual função cada pessoa vai NESTE culto.
        //
        // Quem toca duas coisas — canta e faz violão, baixo e teclado — ia
        // sempre na função principal do cadastro, e o líder não tinha como
        // dizer "hoje ela canta". A escolha é por culto, não por pessoa.
        final funcaoNoCulto = <String, String>{
          for (final l in _scale.levitas) l.userId: l.instrument,
        };
        var busca = '';
        return StatefulBuilder(builder: (ctx2, setDialog) {
          // A busca ignora acento, como a do repertório. Num ministério de
          // trinta pessoas, escalar virava rolar a lista inteira procurando
          // um nome — e a lista cabe em 400 px de altura, uns sete nomes.
          final mostrados =
              allUsers.where((u) => combina(busca, [u.name])).toList();
          return AlertDialog(
            title: const Text('Quem toca neste culto',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  if (allUsers.length > 8) ...[
                    TextField(
                      onChanged: (v) => setDialog(() => busca = v),
                      decoration: InputDecoration(
                        hintText: 'Procurar pessoa',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (mostrados.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Ninguém com esse nome.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: mostrados.length,
                        itemBuilder: (_, i) {
                          final u = mostrados[i];
                          final checked = currentIds.contains(u.id);
                          final escolhida =
                              funcaoNoCulto[u.id] ?? u.instrument.name;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CheckboxListTile(
                                secondary: CircleAvatar(
                                  radius: 16,
                                  backgroundColor:
                                      AppColors.blue.withValues(alpha: 0.15),
                                  child: Text(
                                    // NUNCA indexa texto vazio: `''[0]` LANÇA, e um
                                    // cadastro com o nome em branco derrubaria o
                                    // diálogo inteiro no meio da lista. É a mesma
                                    // armadilha que já custou a tela do culto.
                                    u.name.trim().isEmpty
                                        ? '?'
                                        : u.name.trim()[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.blue,
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                title: Text(
                                    u.name.trim().isEmpty ? 'Alguém' : u.name,
                                    style: const TextStyle(
                                        fontFamily: 'Poppins', fontSize: 13)),
                                subtitle: Text(
                                    u.instruments
                                        .map((f) => '${f.emoji} ${f.label}')
                                        .join(' · '),
                                    style: const TextStyle(
                                        fontFamily: 'Poppins', fontSize: 11)),
                                value: checked,
                                activeColor: AppColors.blue,
                                onChanged: (v) {
                                  setDialog(() {
                                    if (v == true) {
                                      currentIds.add(u.id);
                                      funcaoNoCulto[u.id] ??= u.instrument.name;
                                    } else {
                                      currentIds.remove(u.id);
                                    }
                                  });
                                },
                              ),
                              // Só para quem faz mais de uma coisa, e só quando está
                              // escalada: perguntar antes de escalar seria perguntar
                              // à toa.
                              if (checked && u.temVariasFuncoes)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 72, bottom: 10),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: u.instruments.map((f) {
                                      final ativa = escolhida == f.name;
                                      return GestureDetector(
                                        onTap: () => setDialog(
                                            () => funcaoNoCulto[u.id] = f.name),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: ativa
                                                ? AppColors.blue
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                                color: ativa
                                                    ? AppColors.blue
                                                    : Colors.grey.shade400),
                                          ),
                                          child: Text(
                                            '${f.emoji} ${f.label}',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 11,
                                              fontWeight: ativa
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: ativa
                                                  ? Colors.white
                                                  : AppColors
                                                      .textSecondaryLight,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  _funcaoEscolhida = Map.of(funcaoNoCulto);
                  Navigator.pop(ctx, currentIds.toList());
                },
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
                child: const Text('Confirmar'),
              ),
            ],
          );
        });
      },
    );

    if (selectedIds != null && mounted) {
      final existingLevitas = Map<String, ScaleLevita>.fromEntries(
        _scale.levitas.map((l) => MapEntry(l.userId, l)),
      );

      final levitas = selectedIds.map((uid) {
        final user = allUsers.firstWhere(
          (u) => u.id == uid,
          orElse: () => UserModel(
            id: uid,
            name: uid,
            createdAt: DateTime.now(),
          ),
        );
        final funcao = _funcaoEscolhida[uid] ?? user.instrument.name;
        final jaEstava = existingLevitas[uid];
        // Quem já estava escalado NÃO perde a confirmação de presença por
        // causa de uma troca de função — é o mesmo cuidado que o provider
        // tem ao salvar a equipe.
        if (jaEstava != null) {
          return jaEstava.instrument == funcao
              ? jaEstava
              : ScaleLevita(
                  userId: jaEstava.userId,
                  userName: jaEstava.userName,
                  instrument: funcao,
                  confirmed: jaEstava.confirmed,
                );
        }
        return ScaleLevita(
          userId: user.id,
          userName: user.name,
          instrument: funcao,
        );
      }).toList();

      // Comparado ANTES de salvar, porque depois a lista nova já é a lista.
      final recemEscalados = quemEntrouNaEscala(_scale.levitas, levitas);

      final provider = context.read<ScaleProvider>();
      final error = await provider.setLevitas(_scale.id, levitas);

      if (error == null && recemEscalados.isNotEmpty) {
        // Depois de salvo, e sem esperar: a escala já está no banco, e o
        // aviso é para quem está com o app fechado.
        AvisosService.avisarEscalados(_scale.id, recemEscalados);
      }

      if (!mounted) return;
      if (error == null) {
        // As confirmações já dadas são preservadas pelo provider.
        setState(() => _scale = provider.scales
            .firstWhere((s) => s.id == _scale.id, orElse: () => _scale));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUserInScale =
        auth.user != null && _scale.isUserInScale(auth.user!.id);
    final isConfirmed =
        auth.user != null && _scale.hasUserConfirmed(auth.user!.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_scale.serviceType} - ${DateFormat('dd/MM HH:mm', 'pt_BR').format(_scale.date)}',
        ),
        actions: [
          if (auth.isAdmin)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'cancel') {
                  await _cancelarOuReativar(!_scale.canceled);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'cancel',
                  child: Row(
                    children: [
                      Icon(
                        _scale.canceled
                            ? Icons.event_available_rounded
                            : Icons.event_busy_rounded,
                        size: 18,
                        color:
                            _scale.canceled ? AppColors.success : AppColors.red,
                      ),
                      const SizedBox(width: 8),
                      // O menu DIZ que dá para voltar. Antes, as duas opções
                      // vermelhas pareciam irreversíveis, e cancelar um culto
                      // por engano assustava quem não sabia que havia volta.
                      Text(
                        _scale.canceled
                            ? 'Reativar culto'
                            : 'Cancelar culto (dá para reativar)',
                        style: TextStyle(
                          color: _scale.canceled
                              ? AppColors.success
                              : AppColors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                // EXCLUIR CULTO NÃO EXISTE MAIS, nem para o culto avulso.
                //
                // Vale a mesma regra das músicas: cancelar é um campo, nunca
                // exclusão. Um culto apagado levava junto quem já tinha
                // confirmado presença, o repertório montado e o registro de
                // quem tocou ali — e no culto da agenda fixa nem funcionava,
                // porque o gerador o recriava na abertura seguinte. O menu
                // tinha duas opções vermelhas quase idênticas, e a que não
                // tinha volta era a de baixo.
                //
                // Apagar de verdade, se um dia for mesmo preciso, só pelo
                // console do Firebase.
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Um culto cancelado continua existindo (o gerador não o recria),
            // então precisa dizer isso na cara, e não sumir em silêncio.
            if (_scale.canceled)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppColors.red.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.event_busy_rounded,
                        size: 18, color: AppColors.red),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Culto cancelado. Ele não aparece como próximo culto '
                        'e ninguém precisa confirmar presença.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Service info header. The leader taps it to fix the date or the
            // time — without this, a wrong time could never be corrected.
            GestureDetector(
              onTap: auth.isAdmin ? _editDateTime : null,
              child: _SectionHeader(
                title: DateFormat("EEEE, d 'de' MMMM', às' HH:mm", 'pt_BR')
                    .format(_scale.date),
                subtitle: auth.isAdmin
                    ? '${_scale.serviceType} · toque para alterar'
                    : _scale.serviceType,
                icon: Icons.church_rounded,
                color: AppColors.red,
              ),
            ),
            const SizedBox(height: 20),

            // Confirm presence button (if user is in scale)
            if (isUserInScale)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isConfirmed
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isConfirmed
                        ? AppColors.success.withOpacity(0.3)
                        : AppColors.blue.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isConfirmed
                          ? Icons.check_circle_rounded
                          : Icons.help_outline_rounded,
                      color: isConfirmed ? AppColors.success : AppColors.blue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isConfirmed
                            ? 'Você confirmou presença!'
                            : 'Você está escalado. Confirmar presença?',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color:
                              isConfirmed ? AppColors.success : AppColors.blue,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _confirmPresence(auth),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              isConfirmed ? AppColors.success : AppColors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isConfirmed ? 'Cancelar' : 'Confirmar',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // AS OBSERVAÇÕES FICAM NO TOPO, e para todo mundo.
            //
            // Elas estavam no fim da tela, embaixo da lista de escalados,
            // onde quem abria o culto no domingo não chegava. É o combinado
            // do culto — "entra sem bateria", "a Ana leva o cabo" —, e um
            // combinado que ninguém lê é um combinado que não existe.
            if (_scale.observations.trim().isNotEmpty)
              _ObservacoesDoCulto(texto: _scale.observations, isDark: isDark),

            const SizedBox(height: 20),

            // O botão do Modo Culto ao vivo. Fica acima das músicas, porque é
            // o que se procura com o instrumento na mão, em cima do horário.
            if (_scale.songs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      GlassPageRoute(
                        builder: (_) => ModoAoVivoScreen(
                          culto: _scale,
                          funcaoNoCulto: _minhaFuncaoNesteCulto(context),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.queue_music_rounded, size: 22),
                    label: const Text(
                      'Modo Culto ao vivo',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                    style:
                        FilledButton.styleFrom(backgroundColor: AppColors.blue),
                  ),
                ),
              ),

            // Songs section
            Row(
              children: [
                Text(
                  'Músicas (${_scale.songs.length})',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const Spacer(),
                if (auth.isAdmin)
                  GestureDetector(
                    onTap: _showAddSongDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add_rounded,
                              size: 16, color: AppColors.blue),
                          SizedBox(width: 4),
                          Text(
                            'Adicionar',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: AppColors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_scale.songs.isEmpty)
              _EmptyState(
                icon: Icons.music_off_rounded,
                text: 'Nenhuma música adicionada',
              )
            else
              ...List.generate(_scale.songs.length, (i) {
                final s = _scale.songs[i];
                return _SongRow(
                  song: s,
                  index: i + 1,
                  // A função desta pessoa NESTE culto decide se a música
                  // abre em letra ou em cifra. Era a escolha fixa do perfil,
                  // que não sabe que hoje ela canta e domingo toca baixo.
                  funcaoNoCulto: _minhaFuncaoNesteCulto(context),
                );
              }),

            const SizedBox(height: 20),

            // Alguém escalado aqui saiu do ministério. O aviso é só para o
            // líder, porque é ele quem resolve — e some quando ele mexe na
            // escalação.
            if (_scale.faltando.isNotEmpty && auth.isAdmin) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.45)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.person_off_outlined,
                        size: 19, color: Colors.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _scale.faltando.length == 1
                            ? 'Faltando alguém: ${_scale.faltando.first} foi '
                                'removido do ministério.'
                            : 'Faltando alguém: '
                                '${_scale.faltando.join(', ')} foram removidos '
                                'do ministério.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          height: 1.45,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Levitas section
            Row(
              children: [
                Text(
                  // A contagem de confirmados, não a de escalados: é a
                  // pergunta que o líder faz aqui.
                  'Levitas · ${_scale.textoDaConfirmacao}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                const Spacer(),
                if (auth.isAdmin)
                  GestureDetector(
                    onTap: _showAddLevitaDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.person_add_alt_rounded,
                              size: 16, color: AppColors.red),
                          SizedBox(width: 4),
                          // "Definir" não diz o que vai acontecer; "Escalar"
                          // é a palavra que esta equipe usa ("fui escalado").
                          Text(
                            'Escalar',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: AppColors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_scale.levitas.isEmpty)
              _EmptyState(
                icon: Icons.people_outline_rounded,
                text: 'Nenhum levita definido',
              )
            else
              ...List.generate(_scale.levitas.length, (i) {
                final l = _scale.levitas[i];
                return _LevitaRow(
                  levita: l,
                  nomes: context.watch<AuthProvider>().nomes,
                );
              }),

            const SizedBox(height: 20),

            // O EDITOR é só do líder: para os outros o campo aparecia como
            // uma caixa de texto que não aceitava texto, o que parece defeito.
            // Quem não é líder lê as observações no topo da tela.
            if (auth.isAdmin) ...[
              // "Observações do culto", e não "Observações": a música tem as
              // dela ("Anotações da música"), e as duas apareciam com o mesmo
              // nome em telas diferentes.
              Text(
                'Observações do culto',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _observationsCtrl,
                maxLines: 4,
                readOnly: !auth.isAdmin,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
                decoration: InputDecoration(
                  hintText: 'Adicione observações sobre o culto...',
                  hintStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    color: AppColors.textSecondaryLight,
                  ),
                  filled: true,
                  fillColor:
                      isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color:
                          isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveObservations,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Salvar observações do culto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// O combinado do culto, para quem só precisa LER.
///
/// Fica no topo da tela e sem campo de texto: o editor é do líder, e um campo
/// que não aceita o que a pessoa digita parece defeito.
class _ObservacoesDoCulto extends StatelessWidget {
  final String texto;
  final bool isDark;

  const _ObservacoesDoCulto({required this.texto, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.event_note_outlined, size: 16, color: AppColors.blue),
              SizedBox(width: 8),
              Text(
                'Observações do culto',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            texto.trim(),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              height: 1.5,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimaryLight,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SongRow extends StatelessWidget {
  final ScaleSong song;
  final int index;
  final UserInstrument? funcaoNoCulto;

  const _SongRow({
    required this.song,
    required this.index,
    this.funcaoNoCulto,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The service stores only the id; what to show comes from the repertoire.
    final songs = context.watch<SongsProvider>();
    final missing = !songs.exists(song);
    final completa = songs.getSongById(song.songId);
    final video = completa?.videoUrl;
    return GestureDetector(
      // O culto e o repertório não se falavam: para ver a cifra da música do
      // domingo, a pessoa saía do culto, ia em Músicas e procurava pelo nome.
      onTap: completa == null
          ? null
          : () => Navigator.push(
                context,
                GlassPageRoute(
                  builder: (_) => SongDetailScreen(
                    song: completa,
                    funcaoNoCulto: funcaoNoCulto,
                  ),
                ),
              ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : AppColors.cardLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    songs.nameOf(song),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontStyle: missing ? FontStyle.italic : FontStyle.normal,
                      color: missing
                          ? AppColors.textSecondaryLight
                          : (isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight),
                    ),
                  ),
                  Text(
                    songs.artistOf(song),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
            // O vídeo, aqui no culto, é para ensaiar antes — abrir a música
            // inteira só para achar o link era um caminho a mais no celular,
            // em cima do horário.
            if (video != null)
              IconButton(
                tooltip: 'Abrir no YouTube',
                icon: const Icon(Icons.play_circle_outline_rounded,
                    size: 22, color: AppColors.red),
                onPressed: () => abrirLink(context, video),
                visualDensity: VisualDensity.compact,
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                songs.keyOf(song),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevitaRow extends StatelessWidget {
  /// Nome de cada pessoa por id, para resolver o de quem está escalado. O
  /// culto guarda cópia, e o gerador da agenda fixa grava vazio.
  final Map<String, String> nomes;

  final ScaleLevita levita;
  const _LevitaRow({required this.levita, required this.nomes});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: levita.confirmed
              ? AppColors.success.withOpacity(0.3)
              : isDark
                  ? Colors.grey.shade800
                  : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: levita.confirmed
                ? AppColors.success.withOpacity(0.15)
                : AppColors.blue.withOpacity(0.15),
            child: Text(
              levita.inicialCom(nomes),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: levita.confirmed ? AppColors.success : AppColors.blue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  levita.nomeCom(nomes),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                Text(
                  // O campo guarda o nome técnico do enum ("other", "keyboard").
                  // Mostrar isso cru fazia a tela exibir "other" para quem
                  // escolheu "Outro".
                  () {
                    final i =
                        UserInstrumentExtension.fromString(levita.instrument);
                    return '${i.emoji} ${i.label}';
                  }(),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: levita.confirmed
                  ? AppColors.success.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  levita.confirmed
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  size: 12,
                  color: levita.confirmed ? AppColors.success : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  levita.confirmed ? 'Confirmado' : 'Pendente',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: levita.confirmed ? AppColors.success : Colors.orange,
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      width: double.infinity,
      child: Column(
        children: [
          Icon(icon,
              size: 36,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
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
