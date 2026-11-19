import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/texto.dart';
import '../../../data/models/song_model.dart';
import '../../screens/songs/hino_por_numero_screen.dart';
import '../common/glass.dart';
import '../../../data/services/firestore_service.dart';
import '../../providers/scale_provider.dart';
import '../../providers/songs_provider.dart';
import '../common/app_text_field.dart';

/// Escolher as músicas do culto.
///
/// Antes a lista era só nome e "artista • tom", na ordem em que o banco
/// devolvia — então montar um culto era lembrar de cabeça o que já tinha sido
/// tocado nas últimas semanas e quais músicas a equipe já sabe. As três
/// informações que faltavam são justamente as que decidem a escolha: o tom,
/// se a cifra está pronta, e quando foi a última vez.
enum OrdemDaEscolha {
  /// Menos tocadas primeiro. É o padrão porque é a pergunta que o líder faz:
  /// "o que a gente não canta há um tempo?". Repetir o mesmo repertório é o
  /// jeito mais comum de um ministério cansar a igreja sem perceber.
  menosTocadas,

  /// Por nome, para quando o líder já sabe o que quer e só precisa achar.
  alfabetica,
}

/// A ordem da lista, como função pura.
///
/// Música sem registro de ter sido tocada vem PRIMEIRO na ordem "menos
/// tocadas" — é o caso da música nova, e da que não é tocada há mais tempo
/// que a janela de leitura. As duas são exatamente o que o líder procura.
List<SongModel> ordenar(
  List<SongModel> musicas,
  OrdemDaEscolha ordem,
  Map<String, DateTime> ultimaVez,
) {
  final lista = List<SongModel>.from(musicas);
  if (ordem == OrdemDaEscolha.alfabetica) {
    lista.sort((a, b) => semAcento(a.name).compareTo(semAcento(b.name)));
    return lista;
  }
  lista.sort((a, b) {
    final da = ultimaVez[a.id];
    final db = ultimaVez[b.id];
    if (da == null && db == null) {
      // Empate entre duas sem registro: por nome, para a lista não dançar a
      // cada abertura.
      return semAcento(a.name).compareTo(semAcento(b.name));
    }
    if (da == null) return -1;
    if (db == null) return 1;
    return da.compareTo(db);
  });
  return lista;
}

/// O que a linha diz sobre a última vez.
///
/// "Nunca tocada" seria MENTIRA: o app só lê os cultos dos últimos 60 dias,
/// então a ausência de registro significa apenas que não foi tocada nesse
/// período. Uma música do ano passado apareceria como nunca tocada, e o líder
/// montaria o culto com base nisso.
String textoDaUltimaVez(DateTime? quando) {
  if (quando == null) {
    final meses = FirestoreService.janelaPassado.inDays ~/ 30;
    return 'não tocada nos últimos $meses meses';
  }
  return 'tocada em ${DateFormat('dd/MM', 'pt_BR').format(quando)}';
}

/// Abre o diálogo e devolve as músicas escolhidas, ou nulo se cancelou.
Future<List<SongModel>?> escolherMusicas(
  BuildContext context, {
  required List<String> jaNoCulto,
}) async {
  final songs = context.read<SongsProvider>();
  final repertorio = songs.repertorio;
  if (repertorio.isEmpty) return null;

  // A pergunta das cifras sai daqui, e não da abertura do app: é uma leitura
  // por música, e só o líder que está montando um culto precisa da resposta.
  songs.conferirCifras();

  final ultimaVez = ScaleProvider.ultimaVezTocada(
    context.read<ScaleProvider>().scales,
    DateTime.now(),
  );

  return showDialog<List<SongModel>>(
    context: context,
    builder: (_) => _Escolher(jaNoCulto: jaNoCulto, ultimaVez: ultimaVez),
  );
}

class _Escolher extends StatefulWidget {
  final List<String> jaNoCulto;
  final Map<String, DateTime> ultimaVez;

  const _Escolher({required this.jaNoCulto, required this.ultimaVez});

  @override
  State<_Escolher> createState() => _EscolherState();
}

class _EscolherState extends State<_Escolher> {
  final _buscaCtrl = TextEditingController();
  late final Set<String> _escolhidas;
  OrdemDaEscolha _ordem = OrdemDaEscolha.menosTocadas;

  @override
  void initState() {
    super.initState();
    _escolhidas = {...widget.jaNoCulto};
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  /// Abre o teclado numérico de hinos e marca o que vier.
  ///
  /// O MESMO teclado das outras duas telas — não uma busca por número
  /// colada aqui. Três telas parecidas é o jeito de uma delas ficar para
  /// trás quando a regra muda; e esta já herda de graça o "não existe o hino
  /// 700", o "ainda não está no repertório" e os últimos abertos.
  Future<void> _escolherHino() async {
    final hino = await Navigator.push<SongModel>(
      context,
      // GlassPageRoute, nunca MaterialPageRoute: os dois temas deixam o
      // fundo transparente, e o Material deixaria a tela que entra
      // translúcida durante a animação. O teste de varredura pega isto.
      GlassPageRoute(
        builder: (_) => const HinoPorNumeroScreen(paraEscolher: true),
        fullscreenDialog: true,
      ),
    );
    if (hino == null || !mounted) return;
    setState(() => _escolhidas.add(hino.id));
    // A busca é limpa de propósito: com um filtro ativo, o hino que acabou
    // de ser marcado poderia não aparecer na lista, e a pessoa ficaria sem
    // saber se o toque funcionou.
    _buscaCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${hino.name} entrou na lista do culto.'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<SongsProvider>();
    final busca = _buscaCtrl.text;
    final lista = ordenar(
      songs.repertorio
          .where((m) => combina(busca, [m.name, m.artist]))
          .toList(),
      _ordem,
      widget.ultimaVez,
    );

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(
            child: Text('Músicas do culto',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 16)),
          ),
          // Hino pelo número, aqui também. Montando o culto, o líder sabe o
          // número do hino antes de lembrar o nome dele — e procurar
          // "HC 15" por nome na lista é o que esta entrega veio tirar.
          IconButton(
            tooltip: 'Hino pelo número',
            icon: const Icon(Icons.dialpad_rounded, size: 21),
            onPressed: _escolherHino,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 440,
        child: Column(
          children: [
            AppTextField(
              label: 'Buscar',
              hint: 'nome ou artista',
              controller: _buscaCtrl,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<OrdemDaEscolha>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity(horizontal: -2,
                          vertical: -2),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: OrdemDaEscolha.menosTocadas,
                        label: Text('Menos tocadas',
                            style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: OrdemDaEscolha.alfabetica,
                        label: Text('A–Z',
                            style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 11)),
                      ),
                    ],
                    selected: {_ordem},
                    onSelectionChanged: (v) =>
                        setState(() => _ordem = v.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: lista.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhuma música com esse nome.',
                        style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (_, i) {
                        final m = lista[i];
                        return CheckboxListTile(
                          dense: true,
                          value: _escolhidas.contains(m.id),
                          activeColor: AppColors.blue,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _escolhidas.add(m.id);
                            } else {
                              _escolhidas.remove(m.id);
                            }
                          }),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins', fontSize: 13),
                                ),
                              ),
                              // O ícone só aparece quando a resposta já
                              // chegou E é sim. Ausência de ícone enquanto
                              // carrega não pode parecer "sem cifra".
                              if (songs.cifrasConferidas && songs.temCifra(m.id))
                                const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Icon(Icons.description_outlined,
                                      size: 16, color: AppColors.success),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            [
                              if (m.artist.trim().isNotEmpty) m.artist,
                              'Tom ${m.originalKey}',
                              textoDaUltimaVez(widget.ultimaVez[m.id]),
                            ].join(' · '),
                            maxLines: 2,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 11),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
          onPressed: () {
            // A ordem do culto é a que o líder já tinha, com as novas no fim:
            // reordenar o repertório do culto por causa de uma inclusão
            // mudaria a ordem em que a equipe vai tocar.
            final escolhidas = <SongModel>[];
            for (final id in widget.jaNoCulto) {
              if (!_escolhidas.contains(id)) continue;
              final m = context.read<SongsProvider>().getSongById(id);
              if (m != null) escolhidas.add(m);
            }
            for (final m in context.read<SongsProvider>().repertorio) {
              if (_escolhidas.contains(m.id) &&
                  !widget.jaNoCulto.contains(m.id)) {
                escolhidas.add(m);
              }
            }
            Navigator.pop(context, escolhidas);
          },
          child: Text('Salvar (${_escolhidas.length})'),
        ),
      ],
    );
  }
}
