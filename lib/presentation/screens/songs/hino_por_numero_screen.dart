import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/hinarios.dart';
import '../../../data/models/hino_da_biblioteca.dart';
import '../../../data/models/song_model.dart';
import '../../../data/services/local_storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/biblioteca_provider.dart';
import '../../providers/scale_provider.dart';
import '../../providers/songs_provider.dart';
import '../../../core/utils/lista_de_hinos.dart';
import '../../widgets/common/glass.dart';
import '../../widgets/common/responsivo.dart';
import '../../widgets/hinarios/lista_de_hinos_view.dart';
import '../../widgets/hinarios/pastilhas_de_hinario.dart';
import '../../widgets/hinarios/teclado_de_hino.dart';
import '../../widgets/songs/colar_cifra.dart';
import 'add_song_screen.dart';
import 'hino_da_biblioteca_screen.dart';
import 'song_detail_screen.dart';

/// Abrir o hino pelo número, em segundos.
///
/// POR QUE ESTA TELA EXISTE
///
/// Na igreja, o dirigente anuncia "hino 15 da Harpa" sem avisar antes. Quem
/// vai tocar tinha de sair do culto, ir em Músicas, lembrar o nome do hino e
/// procurar — com a igreja já de pé, esperando. Aqui são dois toques: o
/// hinário, que já vem escolhido, e o número.
///
/// O TEXTO DOS HINOS NÃO MORA NO APP
///
/// Nenhum hino vem embarcado, e isso é decisão de licença, não falta de
/// trabalho: a Harpa Cristã é obra editada e revisada pela CPAD, e 246 dos
/// 640 hinos têm tradução protegida até 2053. Então o que esta tela acha é o
/// que o próprio ministério cadastrou, do hinário que a igreja comprou — e é
/// por isso que "ainda não está no repertório" é um estado normal dela, com
/// um caminho para resolver, e não um erro.
class HinoPorNumeroScreen extends StatefulWidget {
  /// Quando verdadeiro, a tela DEVOLVE o hino escolhido em vez de abri-lo.
  ///
  /// É o que permite o mesmo teclado servir a três lugares — abrir para ler,
  /// escolher no Modo Culto ao vivo, escolher ao montar o repertório do
  /// culto — sem três telas parecidas, que é o jeito de uma delas ficar para
  /// trás quando a regra muda.
  final bool paraEscolher;

  /// Dentro da aba Músicas, o teclado não traz Scaffold nem barra própria: a
  /// aba já tem as suas, e duas barras empilhadas com dois títulos é o tipo
  /// de tela que parece defeito.
  final bool embutida;

  const HinoPorNumeroScreen({
    super.key,
    this.paraEscolher = false,
    this.embutida = false,
  });

  @override
  State<HinoPorNumeroScreen> createState() => _HinoPorNumeroScreenState();
}

enum _Visao { numero, lista }

class _HinoPorNumeroScreenState extends State<HinoPorNumeroScreen> {
  /// Quanto o app espera por mais um dígito antes de abrir sozinho.
  ///
  /// Sem espera nenhuma, digitar "150" abriria o hino 1 no primeiro toque.
  /// Com espera longa, a pessoa acha que o app travou. 600 ms é o intervalo
  /// em que ninguém digita o segundo dígito de um número que queria.
  static const _espera = Duration(milliseconds: 600);

  late Hinario _hinario;
  late List<Hinario> _ordemDosHinarios;
  late OrdemDosHinos _ordem;
  String? _usuario;
  bool _organizando = false;

  /// Qual das duas formas de achar o hino está na tela. Nulo = a que combina
  /// com como a pessoa usa o aparelho (dedo: o teclado; mouse: a lista, onde
  /// se digita o número no teclado de verdade).
  _Visao? _visao;

  String _digitado = '';
  String _recado = '';

  /// O recado é um ERRO (sem internet, sem permissão), e não o "ainda não
  /// está no repertório". Muda o que a tela oferece: "Cadastrar agora" e "Peça
  /// a um líder" respondem a outra pergunta, e ao lado de "Sem internet"
  /// mandariam a pessoa fazer o que não resolve.
  bool _recadoDeErro = false;

  /// Perguntando à biblioteca. A primeira consulta do dia lê o índice, e sem
  /// um sinal a pessoa tocaria no número e veria a tela parada.
  bool _procurando = false;

  final _buscaCtrl = TextEditingController();
  final _buscaFoco = FocusNode();

  /// Quem recebe o teclado de verdade quando nenhum campo está com o foco —
  /// sem ele, depois de clicar numa linha da lista, digitar o número do hino
  /// não chegaria a lugar nenhum.
  final _focoDaTela = FocusNode(debugLabel: 'hinarios');

  String _busca = '';
  Timer? _relogio;

  /// O hino que está aberto no painel da direita (telas largas).
  int? _selecionado;
  String? _erroDasLetras;

  // Lista de itens guardada entre desenhos: montar 640 itens a cada tecla
  // digitada pesaria num celular velho. Só se refaz quando muda de onde ela
  // vem (o repertório, o índice, as letras ou o hinário).
  List<ItemDeHino> _itens = const [];
  Object? _songsUsadas;
  Object? _indiceUsado;
  Object? _letrasUsadas;
  String? _hinarioUsado;

  @override
  void initState() {
    super.initState();
    // "O hino 15 está no repertório?" precisa do repertório inteiro, que o app
    // já não lê a cada abertura.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SongsProvider>().atualizarSeVelho();
    });
    _usuario = context.read<AuthProvider>().user?.id;
    final salvaDosHinarios = LocalStorageService.ordemDosHinariosDe(_usuario);
    _ordemDosHinarios = hinariosNaOrdem(salvaDosHinarios);
    _ordem = ordemPorId(LocalStorageService.ordemDosHinosDe(_usuario));
    // QUEM ABRE É O PRIMEIRO DA FILA, e não o último usado.
    //
    // Duas fontes para a mesma decisão seria a pessoa pôr o Cantor na
    // frente e o app continuar abrindo na Harpa, sem nada que explicasse.
    // Então a ordem manda — e, para quem nunca mexeu nela, o último hinário
    // usado ainda vale, porque aí a lista gravada está vazia e este `??` é o
    // que preserva o costume de hoje.
    _hinario = salvaDosHinarios.isEmpty
        ? (hinarioPorId(LocalStorageService.ultimoHinario) ??
            _ordemDosHinarios.first)
        : _ordemDosHinarios.first;
    // Lê o índice de títulos da biblioteca (UMA leitura por hinário). Erro
    // aqui não precisa de aviso: a consulta pelo número, que é o que a
    // pessoa faz de fato, mostra o motivo se a biblioteca não responder.
    context.read<BibliotecaProvider>().carregarIndice(_hinario.id);
  }

  Future<void> _mover(Hinario h, int passos) async {
    final ids =
        movido(_ordemDosHinarios.map((x) => x.id).toList(), h.id, passos);
    final lista = hinariosNaOrdem(ids);
    // Mudar a ordem não troca de hinário: quem está organizando não está
    // escolhendo o que ler agora. O primeiro só passa a mandar na PRÓXIMA
    // abertura — e é isso que "abre primeiro" promete.
    setState(() => _ordemDosHinarios = lista);
    await LocalStorageService.salvarOrdemDosHinariosDe(
        _usuario, lista.map((x) => x.id).toList());
  }

  Future<void> _escolherOrdem(OrdemDosHinos o) async {
    setState(() => _ordem = o);
    await LocalStorageService.salvarOrdemDosHinosDe(_usuario, o.id);
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _buscaCtrl.dispose();
    _buscaFoco.dispose();
    _focoDaTela.dispose();
    super.dispose();
  }

  // ─── O teclado ──────────────────────────────────────────────────────────

  void _digitar(String d) {
    HapticFeedback.selectionClick();
    // Quem toca nas teclas e TAMBÉM tem teclado (um iPad com teclado) passa a
    // poder digitar o resto no teclado de verdade.
    if (!_focoDaTela.hasFocus && !_buscaFoco.hasFocus) {
      _focoDaTela.requestFocus();
    }
    // Quatro dígitos é mais que qualquer hinário; passar disso é toque
    // repetido sem querer, e deixar crescer só atrasaria o "não existe".
    if (_digitado.length >= 4) return;
    setState(() {
      _digitado += d;
      _recado = '';
    });
    _programarAbertura();
  }

  void _apagar() {
    if (_digitado.isEmpty) return;
    HapticFeedback.selectionClick();
    _relogio?.cancel();
    setState(() {
      _digitado = _digitado.substring(0, _digitado.length - 1);
      _recado = '';
    });
    if (_digitado.isNotEmpty) _programarAbertura();
  }

  void _limpar() {
    _relogio?.cancel();
    setState(() {
      _digitado = '';
      _recado = '';
    });
  }

  /// Decide se abre agora ou espera mais um dígito.
  ///
  /// Quando nenhum número maior é possível — "65" na Harpa, porque 650 passa
  /// de 640 —, não há o que esperar e a abertura é imediata. É o que faz o
  /// caso mais comum (hino de dois ou três dígitos) parecer instantâneo.
  void _programarAbertura() {
    _relogio?.cancel();
    if (!_hinario.podeCrescer(_digitado)) {
      _abrir();
      return;
    }
    _relogio = Timer(_espera, _abrir);
  }

  Future<void> _abrir() async {
    final n = int.tryParse(_digitado);
    if (n == null) return;

    if (!_hinario.existe(n)) {
      setState(() => _recado = 'Não existe o hino $n na ${_hinario.nome}.');
      return;
    }

    final songs = context.read<SongsProvider>();
    final hino = songs.hinoPorNumero(_hinario.id, n);
    if (hino != null) {
      _irPara(hino);
      return;
    }

    // Cadastrado mas fora do repertório é diferente de não cadastrado, e
    // confundir os dois faria o líder cadastrar de novo um hino que já
    // existe — perdendo a cifra que alguém já colou nele.
    final fora = songs.hinoCadastrado(_hinario.id, n);
    if (fora != null) {
      setState(() {
        _recado = 'O hino $n está fora do repertório.';
        _recadoDeErro = false;
      });
      return;
    }

    // Nem no repertório, nem fora dele: a biblioteca (o texto que o líder
    // importou) tem?
    await _abrirDaBiblioteca(n, doTeclado: true);
  }

  /// Procura o hino [n] na biblioteca e abre.
  ///
  /// [doTeclado] é verdadeiro quando a busca nasceu de um número digitado: aí
  /// a resposta pode chegar DEPOIS de a pessoa digitar outro número ou trocar
  /// de hinário, e abrir o hino velho por cima do que ela pediu agora seria
  /// pior que não abrir nada.
  Future<void> _abrirDaBiblioteca(int n, {required bool doTeclado}) async {
    if (_procurando) return;
    final hinario = _hinario;
    setState(() {
      _procurando = true;
      _recado = '';
      _recadoDeErro = false;
    });

    final r = await context.read<BibliotecaProvider>().buscarHino(hinario, n);
    if (!mounted) return;
    setState(() => _procurando = false);

    if (doTeclado &&
        (int.tryParse(_digitado) != n || _hinario.id != hinario.id)) {
      return;
    }

    if (r.error != null) {
      setState(() {
        _recado = r.error!;
        _recadoDeErro = true;
      });
      return;
    }
    final hino = r.hino;
    if (hino == null) {
      setState(() => _recado = 'O hino $n ainda não está no repertório.');
      return;
    }
    await _irParaDaBiblioteca(hinario, hino);
  }

  /// Abre o hino da biblioteca.
  ///
  /// Para LER, abre a tela de leitura e não escreve nada. Para ESCOLHER (pôr
  /// num culto), o hino tem de virar música do repertório antes, porque o
  /// culto guarda o id da música — e quem escolhe é sempre líder, que é
  /// quem as regras deixam criar música.
  Future<void> _irParaDaBiblioteca(
      Hinario hinario, HinoDaBiblioteca hino) async {
    _relogio?.cancel();
    LocalStorageService.salvarHinoAberto(hinario.id, hino.numero);

    if (widget.paraEscolher) {
      final songs = context.read<SongsProvider>();
      final ja = songs.hinoPorNumero(hinario.id, hino.numero);
      if (ja != null) {
        _irPara(ja);
        return;
      }
      final auth = context.read<AuthProvider>();
      final biblioteca = context.read<BibliotecaProvider>();
      setState(() => _procurando = true);
      final r = await biblioteca.porNoRepertorio(hinario, hino,
          porQuemId: auth.user?.id);
      if (!mounted) return;
      setState(() => _procurando = false);
      if (r.musica == null) {
        setState(() {
          _recado = r.error ?? 'Não foi possível pôr o hino no repertório.';
          _recadoDeErro = true;
        });
        return;
      }
      setState(() {
        _digitado = '';
        _recado = '';
      });
      Navigator.pop(context, r.musica);
      return;
    }

    setState(() {
      _digitado = '';
      _recado = '';
      _selecionado = hino.numero;
    });
    await abrirTela(
      context,
      (_) => HinoDaBibliotecaScreen(hinario: hinario, hino: hino),
    );
  }

  void _irPara(SongModel hino) {
    _relogio?.cancel();
    LocalStorageService.salvarHinoAberto(hino.hinario, hino.numero ?? 0);
    setState(() {
      _digitado = '';
      _recado = '';
      _selecionado = hino.numero;
    });
    if (widget.paraEscolher) {
      Navigator.pop(context, hino);
      return;
    }
    abrirTela(context, (_) => SongDetailScreen(song: hino));
  }

  /// Abre o hino de uma linha da lista, venha ele do repertório ou da
  /// biblioteca.
  void _abrirItem(ItemDeHino item) {
    final m = item.musica;
    if (m != null) {
      _irPara(m);
    } else {
      _abrirDaBiblioteca(item.numero, doTeclado: false);
    }
  }

  /// Enter no campo de busca: o número digitado abre, e um resultado só
  /// abre também. É o "digitar 15 e Enter" de quem tem teclado de verdade.
  void _enviarBusca(String texto, List<ItemDeHino> itens) {
    final limpo = texto.trim();
    if (RegExp(r'^\d+$').hasMatch(limpo)) {
      _digitado = limpo;
      _abrir();
    } else if (itens.length == 1) {
      _abrirItem(itens.first);
    }
  }

  /// Abre a tela de cadastro já com o hinário e o número preenchidos.
  void _cadastrar(int numero) {
    _relogio?.cancel();
    setState(() {
      _digitado = '';
      _recado = '';
    });
    Navigator.push(
      context,
      GlassPageRoute(
        builder: (_) => AddSongScreen(hinario: _hinario, numero: numero),
      ),
    );
  }

  void _trocarHinario(Hinario h) {
    _relogio?.cancel();
    LocalStorageService.salvarHinario(h.id);
    setState(() {
      _hinario = h;
      _digitado = '';
      _recado = '';
      _recadoDeErro = false;
      _selecionado = null;
      _erroDasLetras = null;
    });
    context.read<BibliotecaProvider>().carregarIndice(h.id);
  }

  Future<void> _baixarLetras() async {
    final erro =
        await context.read<BibliotecaProvider>().baixarLetras(_hinario);
    if (!mounted) return;
    setState(() => _erroDasLetras = erro);
  }

  // ─── Teclado de verdade ─────────────────────────────────────────────────

  /// As teclas de quem tem teclado: digitar o número e Enter, "/" para
  /// buscar, Esc para sair da busca ou fechar o hino aberto.
  KeyEventResult _teclas(FocusNode _, KeyEvent e, _Visao visao) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final c = e.character ?? '';
    final soDigito = RegExp(r'^\d$').hasMatch(c);
    final comAtalho = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed;
    if (comAtalho) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.escape) {
      if (_buscaFoco.hasFocus) {
        if (_busca.isNotEmpty) {
          _buscaCtrl.clear();
          setState(() => _busca = '');
        } else {
          _focoDaTela.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (visao == _Visao.numero && _digitado.isNotEmpty) {
        _limpar();
        return KeyEventResult.handled;
      }
      // Escolhendo o hino de um culto, Esc só cancela a escolha — não fecha
      // o culto que está aberto ao lado.
      if (widget.paraEscolher) {
        Navigator.maybePop(context);
        return KeyEventResult.handled;
      }
      final painel = PainelDeDetalhe.maybeOf(context);
      if (painel != null && painel.aberto) {
        painel.fechar();
        setState(() => _selecionado = null);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Se o campo de busca tem o foco, quem digita é ele.
    if (_buscaFoco.hasFocus) return KeyEventResult.ignored;

    if (visao == _Visao.numero) {
      if (soDigito) {
        _digitar(c);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.backspace) {
        _apagar();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter) {
        _relogio?.cancel();
        _abrir();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (k == LogicalKeyboardKey.slash) {
      _buscaFoco.requestFocus();
      return KeyEventResult.handled;
    }
    if (soDigito) {
      // Digitar o número de qualquer lugar da tela já cai na busca.
      _buscaCtrl.value = TextEditingValue(
        text: c,
        selection: TextSelection.collapsed(offset: c.length),
      );
      setState(() => _busca = c);
      _buscaFoco.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── A tela ─────────────────────────────────────────────────────────────

  List<ItemDeHino> _itensDe(
    SongsProvider songs,
    IndiceDoHinario indice,
    Map<int, String> letras,
  ) {
    final igual = identical(_songsUsadas, songs.allSongs) &&
        identical(_indiceUsado, indice) &&
        identical(_letrasUsadas, letras) &&
        _hinarioUsado == _hinario.id;
    if (!igual) {
      _itens = itensDoHinario(
        hinario: _hinario.id,
        repertorio: songs.repertorio,
        indice: indice,
        letras: letras,
      );
      _songsUsadas = songs.allSongs;
      _indiceUsado = indice;
      _letrasUsadas = letras;
      _hinarioUsado = _hinario.id;
    }
    return _itens;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final songs = context.watch<SongsProvider>();
    final auth = context.watch<AuthProvider>();
    final biblioteca = context.watch<BibliotecaProvider>();
    final numeroDigitado = int.tryParse(_digitado);
    final indice = biblioteca.indiceDe(_hinario.id);
    final letras = biblioteca.letrasDe(_hinario.id);

    // A contagem sai dos cultos que o app já tem em memória — sem coleção
    // nova e sem leitura nova. A janela são 60 dias, e é por isso que a tela
    // diz "nos últimos 2 meses" em vez de prometer o histórico inteiro.
    // O histórico de 60 dias não fica sempre lido: abre só quando a pessoa
    // escolhe "mais tocados" (e a tela se refaz quando ele chega).
    if (_ordem == OrdemDosHinos.maisTocados) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<ScaleProvider>().garantirHistorico();
      });
    }
    final vezes = _ordem == OrdemDosHinos.maisTocados
        ? ScaleProvider.vezesTocadas(
            context.watch<ScaleProvider>().scales, DateTime.now())
        : const <String, int>{};
    // Escolher "mais tocados" num ministério que ainda não tem culto nenhum
    // registrado devolveria uma lista em ordem de número sem explicação
    // nenhuma. Então a tela avisa, numa frase, e diz em que ordem ficou.
    final semDados = _ordem == OrdemDosHinos.maisTocados && vezes.isEmpty;
    final ordemValendo = semDados ? OrdemDosHinos.numero : _ordem;

    final todos = _itensDe(songs, indice, letras);
    final itens = ordenarItens(
      filtrarItens(todos, _busca),
      ordemValendo,
      vezesTocadas: vezes,
      favoritas: auth.user?.favoriteSongs.toSet() ?? const {},
    );

    final buscaPorTexto = _busca.trim().length >= 3 &&
        !RegExp(r'^\d+$').hasMatch(_busca.trim());
    final estadoDasLetras = !buscaPorTexto || indice.total == 0
        ? EstadoDasLetras.nenhum
        : biblioteca.baixandoLetras(_hinario.id)
            ? EstadoDasLetras.baixando
            : biblioteca.letrasProntas(_hinario.id)
                ? EstadoDasLetras.prontas
                : EstadoDasLetras.oferecer;

    final String? avisoDaOrdem;
    if (semDados) {
      avisoDaOrdem = 'Nenhum culto com repertório nos últimos 2 meses, então '
          'ainda não dá para dizer o que é mais tocado. A lista está pelo '
          'número.';
    } else if (_ordem == OrdemDosHinos.maisTocados) {
      avisoDaOrdem = 'Mais tocados nos últimos 2 meses, primeiro.';
    } else {
      avisoDaOrdem = null;
    }

    final recado = _recado.isEmpty
        ? null
        : _Recado(
            texto: _recado,
            isDark: isDark,
            // O botão só aparece para quem o banco deixa cadastrar. Para um
            // levita ele falharia com erro de permissão, que não explica
            // nada — então a frase diz o que fazer em vez de oferecer um
            // caminho fechado.
            acao: (!_recadoDeErro &&
                    auth.isAdmin &&
                    numeroDigitado != null &&
                    _hinario.existe(numeroDigitado) &&
                    songs.hinoCadastrado(_hinario.id, numeroDigitado) == null)
                ? 'Cadastrar agora'
                : null,
            onAcao: numeroDigitado == null
                ? null
                : () => _cadastrar(numeroDigitado),
            rodape: (_recadoDeErro || auth.isAdmin)
                ? null
                : 'Peça a um líder para cadastrar este hino.',
            // O atalho para achar a cifra do hino, com o nome do hinário
            // já no texto da busca: "Harpa Cristã 15" é o que acha o hino
            // certo no Cifra Club.
            acaoExtra: (!_recadoDeErro &&
                    auth.isAdmin &&
                    numeroDigitado != null &&
                    _hinario.existe(numeroDigitado))
                ? 'Buscar no Cifra Club'
                : null,
            onAcaoExtra: numeroDigitado == null
                ? null
                : () => abrirBuscaCifraClub(
                    context, '${_hinario.nome} $numeroDigitado'),
          );

    final corpo = ConformeAEntrada(
      builder: (context, toque) {
        // Dedo: o teclado primeiro, a lista a um toque. Mouse: direto na
        // lista, onde digitar o número e Enter funciona.
        final visao = toque ? (_visao ?? _Visao.numero) : _Visao.lista;

        final cabeca = <Widget>[
          PastilhasDeHinario(
            ordem: _ordemDosHinarios,
            escolhido: _hinario,
            organizando: _organizando,
            isDark: isDark,
            onEscolher: _trocarHinario,
            onMover: _mover,
            onAlternarOrganizar: () =>
                setState(() => _organizando = !_organizando),
          ),
          if (toque) ...[
            const SizedBox(height: 4),
            _AbasDaVisao(
              visao: visao,
              isDark: isDark,
              onEscolher: (v) => setState(() => _visao = v),
            ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 8),
          if (_procurando) ...[
            _Procurando(numero: numeroDigitado, isDark: isDark),
            const SizedBox(height: 8),
          ],
        ];

        final Widget conteudo;
        if (visao == _Visao.numero) {
          conteudo = LayoutBuilder(
            builder: (context, c) {
              // As teclas crescem com o espaço que sobra, até um limite: em
              // celular alto ficam grandes (tela usada de pé), e em celular
              // baixo voltam a 52 px e a tela rola em vez de espremer.
              final reservado = 64 + 8 + 8 + 10 + 46 + 24 +
                  (recado != null ? 84 : 0);
              final tecla = ((c.maxHeight - reservado) / 4 - 8)
                  .clamp(52.0, 74.0)
                  .toDouble();
              return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MostradorDoHino(
                      sigla: _hinario.sigla,
                      digitado: _digitado,
                      isDark: isDark,
                    ),
                    if (recado != null) ...[
                      const SizedBox(height: 8),
                      recado,
                    ],
                    const SizedBox(height: 8),
                    TecladoDeHino(
                      isDark: isDark,
                      alturaDaTecla: tecla,
                      onDigito: _digitar,
                      onApagar: _apagar,
                      onLimpar: _limpar,
                      podeApagar: _digitado.isNotEmpty,
                    ),
                    const SizedBox(height: 10),
                    _UltimosAbertos(isDark: isDark, onAbrir: _irPara),
                  ],
                ),
              );
            },
          );
        } else {
          conteudo = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (recado != null) ...[
                recado,
                const SizedBox(height: 8),
              ],
              if (_erroDasLetras != null) ...[
                _Recado(texto: _erroDasLetras!, isDark: isDark),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: ListaDeHinosView(
                  controle: _buscaCtrl,
                  foco: _buscaFoco,
                  // Com mouse, o cursor já cai na busca: é o que permite
                  // digitar o número e Enter sem tocar em nada.
                  autofoco: !toque && !widget.paraEscolher,
                  onTapFora: () => _focoDaTela.requestFocus(),
                  busca: _busca,
                  onBusca: (v) => setState(() => _busca = v),
                  onEnviar: (t) => _enviarBusca(t, itens),
                  ordem: ordemValendo,
                  onOrdem: _escolherOrdem,
                  avisoDaOrdem: avisoDaOrdem,
                  itens: itens,
                  totalDoHinario: todos.length,
                  hinario: _hinario,
                  favoritas: auth.user?.favoriteSongs.toSet() ?? const {},
                  selecionado: _selecionado,
                  isDark: isDark,
                  onAbrir: _abrirItem,
                  letras: estadoDasLetras,
                  onBaixarLetras: _baixarLetras,
                  vazio: _Vazio(
                    busca: _busca,
                    hinario: _hinario,
                    total: songs.hinosDe(_hinario.id).length,
                    naBiblioteca: indice.total,
                    isDark: isDark,
                  ),
                ),
              ),
            ],
          );
        }

        return Focus(
          focusNode: _focoDaTela,
          autofocus: false,
          onKeyEvent: (n, e) => _teclas(n, e, visao),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...cabeca,
                Expanded(child: conteudo),
              ],
            ),
          ),
        );
      },
    );

    if (widget.embutida) return corpo;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.paraEscolher
            ? 'Escolher hino pelo número'
            : 'Hino pelo número'),
      ),
      body: ColunaCentral(largura: 720, child: corpo),
    );
  }
}

// ─── Peças da tela ────────────────────────────────────────────────────────

/// As duas formas de achar o hino: digitando o número, ou vendo todos.
///
/// Abas com texto, e não um ícone: quem chega aqui na hora do culto procura
/// "o número" e, se não lembra, "a lista".
class _AbasDaVisao extends StatelessWidget {
  final _Visao visao;
  final bool isDark;
  final ValueChanged<_Visao> onEscolher;

  const _AbasDaVisao({
    required this.visao,
    required this.isDark,
    required this.onEscolher,
  });

  @override
  Widget build(BuildContext context) {
    Widget aba(_Visao v, IconData icone, String rotulo) {
      final ativa = v == visao;
      final cor = ativa
          ? AppColors.blue
          : (isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight);
      return Expanded(
        child: Semantics(
          button: true,
          selected: ativa,
          child: InkWell(
            onTap: () => onEscolher(v),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: ativa ? AppColors.blue : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icone, size: 19, color: cor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      rotulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.5,
                        fontWeight: ativa ? FontWeight.w600 : FontWeight.w500,
                        color: cor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        aba(_Visao.numero, Icons.dialpad_rounded, 'Digitar o número'),
        aba(_Visao.lista, Icons.format_list_numbered_rounded,
            'Ver todos os hinos'),
      ],
    );
  }
}

class _Recado extends StatelessWidget {
  final String texto;
  final bool isDark;
  final String? acao;
  final VoidCallback? onAcao;
  final String? rodape;
  final String? acaoExtra;
  final VoidCallback? onAcaoExtra;

  const _Recado({
    required this.texto,
    required this.isDark,
    this.acao,
    this.onAcao,
    this.rodape,
    this.acaoExtra,
    this.onAcaoExtra,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: isDark ? 0.14 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texto,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          if (acao != null || acaoExtra != null) ...[
            const SizedBox(height: 2),
            Wrap(
              spacing: 14,
              children: [
                if (acao != null)
                  TextButton.icon(
                    onPressed: onAcao,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(acao!),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  ),
                if (acaoExtra != null)
                  TextButton.icon(
                    onPressed: onAcaoExtra,
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    label: Text(acaoExtra!),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  ),
              ],
            ),
          ],
          if (rodape != null) ...[
            const SizedBox(height: 4),
            Text(
              rodape!,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UltimosAbertos extends StatelessWidget {
  final bool isDark;
  final ValueChanged<SongModel> onAbrir;

  const _UltimosAbertos({required this.isDark, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<SongsProvider>();
    // Só os que ainda estão no repertório: chip que abre "hino removido" é
    // pior que chip nenhum.
    final abertos = <SongModel>[];
    for (final r in LocalStorageService.hinosAbertos) {
      final h = songs.hinoPorNumero(r.hinario, r.numero);
      if (h != null) abertos.add(h);
    }
    if (abertos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Últimos abertos',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 6),
        // Uma fila só, que rola para o lado: um Wrap quebraria em várias
        // linhas e comeria a tela que o teclado precisa.
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: [
              for (final h in abertos)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label:
                        Text('${hinarioPorId(h.hinario)?.sigla ?? ''} ${h.numero}'),
                    onPressed: () => onAbrir(h),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Procurando o hino 15…" — a primeira consulta do dia lê o índice, e sem um
/// sinal a pessoa tocaria no número e veria a tela parada, achando que o
/// teclado não funcionou.
class _Procurando extends StatelessWidget {
  final int? numero;
  final bool isDark;

  const _Procurando({required this.numero, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          numero == null ? 'Procurando o hino…' : 'Procurando o hino $numero…',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13.5,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }
}

/// Lista vazia que diz QUAL dos casos é.
///
/// A regra do projeto: vazio explica por que está vazio. "Nenhum hino" sem
/// motivo é lido como defeito do app, e aqui há dois motivos bem diferentes —
/// a busca não achou, ou a igreja ainda não cadastrou hino nenhum daquele
/// hinário.
class _Vazio extends StatelessWidget {
  final String busca;
  final Hinario hinario;

  /// Hinos do hinário que estão NO REPERTÓRIO.
  final int total;

  /// Hinos do hinário que o líder importou para a biblioteca.
  final int naBiblioteca;
  final bool isDark;

  const _Vazio({
    required this.busca,
    required this.hinario,
    required this.total,
    required this.naBiblioteca,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final String texto;
    if (total == 0 && naBiblioteca == 0) {
      texto = 'Nenhum hino da ${hinario.nome} está no repertório ainda. '
          'Eles entram pelo cadastro de música, com a cifra do hinário da '
          'igreja.';
    } else if (busca.trim().isNotEmpty) {
      texto = 'Nenhum hino da ${hinario.nome} com "$busca".';
    } else if (total == 0) {
      // A biblioteca tem os hinos, o repertório ainda não: não é "vazio",
      // e dizer "nenhum hino" aqui seria mandar cadastrar o que já existe.
      texto = 'Nenhum hino da ${hinario.nome} no repertório ainda. Eles '
          'entram quando um líder os põe no culto. Antes disso, dá para '
          'abrir qualquer um pelo número ou pelo nome.';
    } else {
      texto = 'Nenhum hino para mostrar.';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13.5,
          height: 1.5,
          color: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondaryLight,
        ),
      ),
    );
  }
}
