import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/platform/tela_acesa.dart';
import '../../../core/utils/chord_transposer.dart';
import '../../../core/utils/mapa_da_musica.dart';
import '../../../data/models/ao_vivo_model.dart';
import '../../../data/models/scale_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/ao_vivo_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/songs_provider.dart';

/// Uma música do culto, já pronta para ler.
class _MusicaAoVivo {
  final String nome;
  final String artista;
  final String tom;
  final MapaDaMusica mapa;
  final bool temCifra;

  /// Segundos por linha sugeridos pelo BPM do arranjo, ou nulo.
  final double? segundosPorLinha;

  const _MusicaAoVivo({
    required this.nome,
    required this.artista,
    required this.tom,
    required this.mapa,
    required this.temCifra,
    this.segundosPorLinha,
  });
}

/// Modo Culto ao vivo: todos na mesma parte da música, ao mesmo tempo.
///
/// O QUE VIAJA ENTRE OS APARELHOS
///
/// Nunca pixels: a posição é {música, âncora}, e âncora é o índice da LINHA
/// DE LETRA (ver `MapaDaMusica`). Isso é o que permite o tecladista ler a
/// cifra num celular pequeno e a cantora ler só a letra em fonte grande,
/// parados no mesmo verso.
///
/// E OS DOIS MODOS SAEM DO MESMO TEXTO
///
/// Quando existe cifra, ela é a fonte dos DOIS — quem lê só a letra vê a
/// letra extraída da cifra, não o campo `lyrics` da música. Se cada modo
/// lesse um texto diferente, as âncoras não corresponderiam e o culto
/// desalinharia sem nenhum erro aparecer na tela.
class ModoAoVivoScreen extends StatefulWidget {
  final ScaleModel culto;

  /// A função desta pessoa NESTE culto: decide se ela lê cifra ou só letra.
  final UserInstrument? funcaoNoCulto;

  const ModoAoVivoScreen({
    super.key,
    required this.culto,
    this.funcaoNoCulto,
  });

  @override
  State<ModoAoVivoScreen> createState() => _ModoAoVivoScreenState();
}

class _ModoAoVivoScreenState extends State<ModoAoVivoScreen> {
  late final AoVivoService _servico = AoVivoService.doCulto(widget.culto.id);
  StreamSubscription<EstadoAoVivo?>? _escuta;

  List<_MusicaAoVivo> _musicas = const [];
  bool _carregando = true;

  EstadoAoVivo? _estado;
  int _musica = 0;
  int _ancora = 0;

  /// Sigo o condutor? Rolar à mão solta; "Voltar a seguir" religa.
  bool _seguindo = true;

  /// Rolagem automática local, para quem toca sem condutor.
  bool _automatico = false;
  double _segundosPorLinha = 4;
  Timer? _relogioAutomatico;

  String _avisoDaTela = '';
  bool _mostrarCifra = true;

  final ScrollController _rolagem = ScrollController();
  final Map<int, GlobalKey> _chaves = {};
  Timer? _debounceDaRolagem;

  @override
  void initState() {
    super.initState();
    _mostrarCifra = widget.funcaoNoCulto == null ||
        UserModel.leituraDaFuncao(widget.funcaoNoCulto!) == ModoLeitura.toco;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _acenderTela();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _carregar();
    });
  }

  @override
  void dispose() {
    _escuta?.cancel();
    _relogioAutomatico?.cancel();
    _debounceDaRolagem?.cancel();
    _servico.dispose();
    _rolagem.dispose();
    soltarTela();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _acenderTela() async {
    final r = await manterTelaAcesa();
    if (!mounted || r == 'ok') return;
    // O plano B é honesto: este aparelho não deixa o app segurar a tela, e a
    // pessoa precisa saber ANTES de ela apagar no meio da música. No iPhone
    // isso acontece em PWA instalado antes do iOS 18.4.
    setState(() => _avisoDaTela = r == 'negado' || r == 'sem-suporte'
        ? 'Este aparelho não deixa o app manter a tela acesa. No iPhone: '
            'Ajustes → Tela e Brilho → Bloqueio Automático → Nunca.'
        : '');
  }

  // ── Carregar as músicas do culto ────────────────────────────────────────

  Future<void> _carregar() async {
    final songs = context.read<SongsProvider>();
    final prontas = <_MusicaAoVivo>[];

    for (final ref in widget.culto.songs) {
      final musica = songs.getSongById(ref.songId);
      if (musica == null) continue;
      final arranjo = await FirestoreService.getArrangement(ref.songId);
      final tomDoCulto = songs.keyOf(ref);

      // A CIFRA é a fonte dos dois modos quando existe. Ver o comentário da
      // classe: fontes diferentes = âncoras diferentes = culto desalinhado.
      final temCifra = arranjo?.hasChords ?? false;
      var fonte = temCifra ? arranjo!.chords : musica.lyrics;

      if (temCifra) {
        final n = ChordTransposer.semitonesEntre(
            arranjo!.churchKey.isEmpty ? musica.originalKey : arranjo.churchKey,
            tomDoCulto);
        if (n != 0) fonte = ChordTransposer.transposeText(fonte, n);
      }

      prontas.add(_MusicaAoVivo(
        nome: musica.name,
        artista: musica.artist,
        tom: tomDoCulto,
        mapa: MapaDaMusica.mapear(fonte),
        temCifra: temCifra,
        segundosPorLinha: (arranjo?.bpm ?? 0) > 0
            // Uma linha de letra dura mais ou menos quatro tempos.
            ? (4 * 60) / arranjo!.bpm
            : null,
      ));
    }

    if (!mounted) return;
    setState(() {
      _musicas = prontas;
      _carregando = false;
      final sugerido = prontas.isEmpty ? null : prontas.first.segundosPorLinha;
      if (sugerido != null) _segundosPorLinha = sugerido.clamp(1.5, 12);
    });
    _ouvirOCulto();
  }

  void _ouvirOCulto() {
    _escuta = AoVivoService.escutar(widget.culto.id).listen((e) {
      if (!mounted) return;
      setState(() => _estado = e);
      if (e == null || _souOCondutor) return;
      if (!_seguindo) return;
      // Seguidor: a posição do condutor manda.
      final mudou = e.musica != _musica || e.ancora != _ancora;
      if (mudou) {
        setState(() {
          _musica = e.musica.clamp(0, _musicas.isEmpty ? 0 : _musicas.length - 1);
          _ancora = e.ancora;
        });
        _rolarAte(_ancora);
      }
    }, onError: (_) {
      // Sem rede, ou leitura recusada. A tela avisa, em vez de todos acharem
      // que estão juntos.
      if (mounted) setState(() => _estado = null);
    });
  }

  // ── Quem conduz ─────────────────────────────────────────────────────────

  String get _meuId => context.read<AuthProvider>().user?.id ?? '';
  String get _meuNome => context.read<AuthProvider>().user?.name ?? '';
  bool get _souLider => context.read<AuthProvider>().isAdmin;
  bool get _souOCondutor => _estado?.souOCondutor(_meuId) ?? false;

  bool get _podeAssumir {
    final e = _estado;
    if (e == null) return true;
    return _souLider || e.podeAssumir(_meuId, DateTime.now());
  }

  _MusicaAoVivo? get _atual =>
      (_musica >= 0 && _musica < _musicas.length) ? _musicas[_musica] : null;

  void _publicar() {
    if (!_souOCondutor) return;
    final m = _atual;
    _servico.publicar(EstadoAoVivo(
      condutorId: _meuId,
      condutorNome: _meuNome,
      musica: _musica,
      ancora: _ancora,
      secao: m?.mapa.secaoDe(_ancora) ?? '',
      texto: m?.mapa.ancora(_ancora)?.texto ?? '',
      atualizadoEm: DateTime.now(),
    ));
  }

  Future<void> _assumir() async {
    setState(() {
      _seguindo = true;
      _automatico = false;
    });
    _relogioAutomatico?.cancel();
    _servico.publicar(EstadoAoVivo(
      condutorId: _meuId,
      condutorNome: _meuNome,
      musica: _musica,
      ancora: _ancora,
      secao: _atual?.mapa.secaoDe(_ancora) ?? '',
      texto: _atual?.mapa.ancora(_ancora)?.texto ?? '',
      atualizadoEm: DateTime.now(),
    ));
  }

  Future<void> _soltar() async {
    final e = _estado;
    if (e == null) return;
    final erro = await _servico.soltarComando(e);
    if (!mounted || erro == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(erro), backgroundColor: AppColors.red),
    );
  }

  /// Passar o comando para outra pessoa escalada.
  Future<void> _passarComando() async {
    final escalados = widget.culto.levitas.where((l) => l.userId != _meuId);
    if (escalados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não há mais ninguém escalado neste culto.')));
      return;
    }
    final escolhido = await showModalBottomSheet<ScaleLevita>(
      context: context,
      backgroundColor: const Color(0xFF14181F),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text('Passar o comando para',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
            ...escalados.map((l) => ListTile(
                  leading: const Icon(Icons.person_outline_rounded,
                      color: Colors.white70),
                  title: Text(l.userName,
                      style: const TextStyle(
                          fontFamily: 'Poppins', color: Colors.white)),
                  onTap: () => Navigator.pop(context, l),
                )),
          ],
        ),
      ),
    );
    if (escolhido == null || !mounted) return;
    // Quem assume de verdade é o aparelho da outra pessoa: aqui só se solta
    // o comando, e o app dela mostra "Assumir". Escrever o id dela seria
    // apontar um condutor que talvez não esteja com o app aberto.
    await _soltar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Comando liberado. ${escolhido.userName} toca em '
          '"Assumir" no aparelho dela.'),
      backgroundColor: AppColors.blue,
    ));
  }

  // ── Mover ───────────────────────────────────────────────────────────────

  void _irParaAncora(int nova, {bool rolar = true}) {
    final m = _atual;
    if (m == null || m.mapa.vazio) return;
    final limitada = nova.clamp(0, m.mapa.ancoras.length - 1);
    setState(() => _ancora = limitada);
    if (rolar) _rolarAte(limitada);
    _publicar();
  }

  void _trocarMusica(int delta) {
    final nova = (_musica + delta).clamp(0, _musicas.length - 1);
    if (nova == _musica) return;
    setState(() {
      _musica = nova;
      _ancora = 0;
    });
    _rolarAte(0);
    _publicar();
  }

  void _rolarAte(int ancora) {
    final chave = _chaves[ancora];
    final ctx = chave?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      // 0.22: a linha atual fica no alto, com o que vem a seguir à vista —
      // é onde o olho de quem toca precisa estar.
      alignment: 0.22,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// O condutor rolou à mão: a linha do topo passa a ser a posição.
  ///
  /// SÓ QUANDO A ROLAGEM PARA, e o atraso é longo de propósito (600 ms).
  ///
  /// O custo deste recurso não está nas escritas, está nas LEITURAS: cada
  /// mudança é uma leitura cobrada para CADA aparelho que está escutando.
  /// Publicar durante o arrasto faria uma rolagem de dez linhas virar dez
  /// mudanças — vezes doze aparelhos, 120 leituras num gesto. A cota grátis
  /// do Spark é 50 mil leituras por dia.
  ///
  /// E ninguém perde nada: as linhas do meio do arrasto não interessam a
  /// quem segue, só o lugar onde o condutor parou.
  void _rolagemDoCondutor() {
    _debounceDaRolagem?.cancel();
    _debounceDaRolagem = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || !_souOCondutor) return;
      final topo = _ancoraNoTopo();
      if (topo != null && topo != _ancora) {
        setState(() => _ancora = topo);
        _publicar();
      }
    });
  }

  /// Qual âncora está mais perto do alto da área de leitura.
  int? _ancoraNoTopo() {
    int? melhor;
    var menorDistancia = double.infinity;
    for (final par in _chaves.entries) {
      final ctx = par.value.currentContext;
      if (ctx == null) continue;
      final caixa = ctx.findRenderObject() as RenderBox?;
      if (caixa == null || !caixa.hasSize) continue;
      final y = caixa.localToGlobal(Offset.zero).dy;
      // Só o que está abaixo do topo conta: a linha que já passou não é a
      // posição atual.
      if (y < 80) continue;
      final d = (y - 120).abs();
      if (d < menorDistancia) {
        menorDistancia = d;
        melhor = par.key;
      }
    }
    return melhor;
  }

  void _alternarAutomatico() {
    setState(() => _automatico = !_automatico);
    _relogioAutomatico?.cancel();
    if (!_automatico) return;
    _relogioAutomatico = Timer.periodic(
      Duration(milliseconds: (_segundosPorLinha * 1000).round()),
      (_) {
        if (!mounted) return;
        final m = _atual;
        if (m == null || m.mapa.vazio) return;
        if (_ancora >= m.mapa.ancoras.length - 1) {
          setState(() => _automatico = false);
          _relogioAutomatico?.cancel();
          return;
        }
        _irParaAncora(_ancora + 1);
      },
    );
  }

  // ── Tela ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Preto de verdade e texto claro: é tela lida de longe, muitas vezes com
    // refletor em cima. O tema do app não vale aqui de propósito.
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: const Color(0xFF07090C),
        body: SafeArea(
          child: _carregando
              ? const Center(child: CircularProgressIndicator())
              : _musicas.isEmpty
                  ? _semMusicas()
                  : Column(
                      children: [
                        _barraDeCima(),
                        if (_avisoDaTela.isNotEmpty) _faixaDeAviso(),
                        if (widget.culto.observations.trim().isNotEmpty)
                          _observacoes(),
                        Expanded(child: _leitura()),
                        _barraDeBaixo(),
                      ],
                    ),
        ),
      ),
    );
  }

  /// O combinado do culto, aqui também — RECOLHIDO por padrão.
  ///
  /// É a tela que fica aberta durante o culto, com a cifra: as observações
  /// precisam estar ao alcance ("entra sem bateria"), mas não podem roubar
  /// linhas da música. Então é uma faixa de uma linha que se abre no toque.
  ///
  /// Começa recolhida porque quem abre o Modo ao vivo já leu o combinado na
  /// tela do culto; aqui é consulta, não leitura.
  bool _obsAberta = false;

  Widget _observacoes() {
    final texto = widget.culto.observations.trim();
    return GestureDetector(
      onTap: () => setState(() => _obsAberta = !_obsAberta),
      child: Container(
        width: double.infinity,
        color: const Color(0xFF12161C),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_note_outlined,
                size: 17, color: Colors.white54),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                // Uma linha quando recolhida: a música é o que importa aqui.
                maxLines: _obsAberta ? 12 : 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  height: 1.45,
                  color: Colors.white70,
                ),
              ),
            ),
            Icon(
              _obsAberta
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _semMusicas() => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_off_rounded, size: 46, color: Colors.white38),
            const SizedBox(height: 14),
            const Text(
              'Este culto ainda não tem músicas',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Monte a lista no culto e volte aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13.5, color: Colors.white60),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );

  Widget _faixaDeAviso() => Container(
        width: double.infinity,
        color: const Color(0xFF3A2A10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.lightbulb_outline_rounded,
                size: 16, color: Color(0xFFE0AD5E)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _avisoDaTela,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    height: 1.3,
                    color: Color(0xFFE0AD5E)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: Color(0xFFE0AD5E)),
              onPressed: () => setState(() => _avisoDaTela = ''),
            ),
          ],
        ),
      );

  Widget _barraDeCima() {
    final m = _atual!;
    final e = _estado;
    final conduzindo = e != null && e.vivo(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1B2029))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Sair do modo ao vivo',
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      m.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                    Text(
                      '${_musica + 1} de ${_musicas.length} · tom ${m.tom}'
                      '${m.mapa.secaoDe(_ancora).isEmpty ? '' : ' · ${m.mapa.secaoDe(_ancora)}'}',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          color: Colors.white54),
                    ),
                  ],
                ),
              ),
              // Cifra ou letra, trocável na hora. A escolha vale só aqui e
              // não mexe no perfil: é para o momento, não para sempre.
              IconButton(
                tooltip: _mostrarCifra ? 'Ver só a letra' : 'Ver a cifra',
                icon: Icon(
                    _mostrarCifra
                        ? Icons.lyrics_outlined
                        : Icons.music_note_rounded,
                    color: Colors.white70),
                onPressed: m.temCifra
                    ? () => setState(() => _mostrarCifra = !_mostrarCifra)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  conduzindo
                      ? (_souOCondutor
                          ? 'Você está conduzindo'
                          : 'Conduzindo: ${e.condutorNome}')
                      : 'Ninguém conduzindo',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: conduzindo
                        ? (_souOCondutor ? AppColors.success : Colors.white70)
                        : Colors.white38,
                  ),
                ),
              ),
              if (_servico.erro != null)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.cloud_off_rounded,
                      size: 15, color: Color(0xFFE0AD5E)),
                ),
              if (!_souOCondutor && _podeAssumir)
                TextButton(
                  onPressed: _assumir,
                  child: const Text('Assumir',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5)),
                ),
              if (_souOCondutor) ...[
                TextButton(
                  onPressed: _passarComando,
                  child: const Text('Passar',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5)),
                ),
                TextButton(
                  onPressed: _soltar,
                  child: const Text('Soltar',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          color: Colors.white54)),
                ),
              ],
            ],
          ),
          if (_servico.erro != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _servico.erro!,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0xFFE0AD5E)),
              ),
            ),
          if (!_seguindo && _estado != null && !_souOCondutor)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() => _seguindo = true);
                    final e = _estado;
                    if (e != null) {
                      setState(() {
                        _musica = e.musica.clamp(0, _musicas.length - 1);
                        _ancora = e.ancora;
                      });
                      _rolarAte(_ancora);
                    }
                  },
                  icon: const Icon(Icons.sync_rounded, size: 17),
                  label: const Text('Voltar a seguir'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      visualDensity: VisualDensity.compact),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _leitura() {
    final m = _atual!;
    final linhas = _mostrarCifra && m.temCifra
        ? m.mapa.linhasDaCifra
        : m.mapa.linhasDaLetra;
    final mono = _mostrarCifra && m.temCifra;

    // Em que linha do texto está a âncora atual, para destacar.
    final linhaAtual = m.mapa.linhaNoTexto(_ancora, cifra: mono);

    _chaves.clear();
    for (final a in m.mapa.ancoras) {
      _chaves[a.indice] = GlobalKey();
    }

    // Avisa quando os dois aparelhos estão em versões diferentes da música:
    // o índice seria o mesmo e o verso, outro.
    final e = _estado;
    final desencontro = e != null &&
        !_souOCondutor &&
        e.texto.isNotEmpty &&
        (m.mapa.ancora(e.ancora)?.texto ?? '') != e.texto;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
          if (_souOCondutor) {
            _rolagemDoCondutor();
          } else if (_seguindo) {
            // Rolou à mão: solta, e aparece "Voltar a seguir".
            setState(() => _seguindo = false);
          }
        }
        return false;
      },
      child: ListView.builder(
        controller: _rolagem,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
        itemCount: linhas.length + (desencontro ? 1 : 0),
        itemBuilder: (_, i) {
          if (desencontro && i == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Atenção: o seu aparelho tem uma versão diferente desta '
                'música, então a linha pode não bater.',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Color(0xFFE0AD5E)),
              ),
            );
          }
          final indice = desencontro ? i - 1 : i;
          final texto = linhas[indice];
          final ancoraDaLinha = m.mapa.ancoras
              .where((a) => (mono ? a.naCifra : a.naLetra) == indice)
              .firstOrNull;
          final ehAtual = indice == linhaAtual;

          final linha = Container(
            key: ancoraDaLinha == null ? null : _chaves[ancoraDaLinha.indice],
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: ehAtual
                ? BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                        left: BorderSide(color: AppColors.blue, width: 3)),
                  )
                : null,
            child: Text(
              texto.isEmpty ? ' ' : texto,
              style: TextStyle(
                fontFamily: mono ? 'JetBrainsMono' : 'Poppins',
                fontSize: mono ? 16 : 24,
                height: mono ? 1.45 : 1.5,
                fontWeight: ehAtual ? FontWeight.w700 : FontWeight.w500,
                color: ehAtual ? Colors.white : const Color(0xFFC9D1DB),
              ),
            ),
          );

          // Tocar numa linha leva o culto até ela — é o atalho do condutor
          // quando a música pula uma parte.
          return ancoraDaLinha == null || !_souOCondutor
              ? linha
              : GestureDetector(
                  onTap: () => _irParaAncora(ancoraDaLinha.indice),
                  child: linha,
                );
        },
      ),
    );
  }

  Widget _barraDeBaixo() {
    final m = _atual!;
    return Container(
      padding: EdgeInsets.fromLTRB(
          10, 8, 10, 8 + MediaQuery.of(context).padding.bottom * 0),
      decoration: const BoxDecoration(
        color: Color(0xFF0C1016),
        border: Border(top: BorderSide(color: Color(0xFF1B2029))),
      ),
      child: Column(
        children: [
          if (_automatico || !_souOCondutor)
            Row(
              children: [
                IconButton(
                  tooltip: _automatico ? 'Parar a rolagem' : 'Rolar sozinho',
                  icon: Icon(
                      _automatico
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_outline_rounded,
                      size: 30,
                      color: Colors.white70),
                  onPressed: _alternarAutomatico,
                ),
                Expanded(
                  child: Slider(
                    value: _segundosPorLinha,
                    min: 1.5,
                    max: 12,
                    divisions: 21,
                    label: '${_segundosPorLinha.toStringAsFixed(1)} s por linha',
                    onChanged: (v) {
                      setState(() => _segundosPorLinha = v);
                      if (_automatico) {
                        _alternarAutomatico();
                        _alternarAutomatico();
                      }
                    },
                  ),
                ),
                Text(
                  '${_segundosPorLinha.toStringAsFixed(1)}s',
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      color: Colors.white54),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _alternarAutomatico,
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: Text(
                  m.segundosPorLinha != null
                      ? 'Rolar sozinho (${m.segundosPorLinha!.toStringAsFixed(1)}s por linha, do BPM)'
                      : 'Rolar sozinho',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5),
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Música anterior',
                icon: const Icon(Icons.skip_previous_rounded,
                    size: 28, color: Colors.white70),
                onPressed: _musica > 0 ? () => _trocarMusica(-1) : null,
              ),
              IconButton(
                tooltip: 'Parte anterior',
                icon: const Icon(Icons.keyboard_double_arrow_up_rounded,
                    size: 26, color: Colors.white70),
                onPressed: () =>
                    _irParaAncora(m.mapa.parteAnterior(_ancora)),
              ),
              // O botão grande. Área de toque generosa de propósito: é
              // apertado com o instrumento na mão, sem olhar.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    height: 62,
                    child: FilledButton.icon(
                      onPressed: () =>
                          _irParaAncora(m.mapa.proximaParte(_ancora)),
                      icon: const Icon(Icons.keyboard_double_arrow_down_rounded,
                          size: 26),
                      label: const Text(
                        'Próxima parte',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            _souOCondutor ? AppColors.blue : const Color(0xFF263040),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Próxima música',
                icon: const Icon(Icons.skip_next_rounded,
                    size: 28, color: Colors.white70),
                onPressed: _musica < _musicas.length - 1
                    ? () => _trocarMusica(1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
