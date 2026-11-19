import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/hinarios.dart';
import '../../../data/models/song_model.dart';
import '../../../data/services/local_storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scale_provider.dart';
import '../../providers/songs_provider.dart';
import '../../widgets/common/glass.dart';
import '../../widgets/songs/colar_cifra.dart';
import 'add_song_screen.dart';
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
  String _digitado = '';
  String _recado = '';
  final _buscaCtrl = TextEditingController();
  String _busca = '';
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    _ordemDosHinarios = hinariosNaOrdem(LocalStorageService.ordemDosHinarios);
    _ordem = ordemPorId(LocalStorageService.ordemDosHinos);
    // QUEM ABRE É O PRIMEIRO DA LISTA, e não o último usado.
    //
    // Duas fontes para a mesma decisão seria a pessoa arrastar o Cantor para
    // cima e o app continuar abrindo na Harpa, sem nada que explicasse.
    // Então a ordem manda — e, para quem nunca arrastou nada, o último
    // hinário usado ainda vale, porque aí a lista gravada está vazia e este
    // `??` é o que preserva o costume de hoje.
    _hinario = LocalStorageService.ordemDosHinarios.isEmpty
        ? (hinarioPorId(LocalStorageService.ultimoHinario) ??
            _ordemDosHinarios.first)
        : _ordemDosHinarios.first;
  }

  Future<void> _reordenar(int de, int para) async {
    // O ReorderableListView entrega o destino contando a linha que saiu, e
    // sem este ajuste arrastar para baixo erra uma posição.
    if (para > de) para -= 1;
    final lista = List<Hinario>.from(_ordemDosHinarios);
    final h = lista.removeAt(de);
    lista.insert(para, h);
    await _gravarOrdem(lista);
  }

  Future<void> _mover(Hinario h, int passos) async {
    final ids =
        movido(_ordemDosHinarios.map((x) => x.id).toList(), h.id, passos);
    await _gravarOrdem(hinariosNaOrdem(ids));
  }

  Future<void> _gravarOrdem(List<Hinario> lista) async {
    setState(() {
      _ordemDosHinarios = lista;
      // Reordenar não troca de hinário: quem arrasta está organizando a
      // lista, não escolhendo o que ler agora. O primeiro só passa a mandar
      // na PRÓXIMA abertura — e é isso que "abre aqui" promete.
    });
    await LocalStorageService.salvarOrdemDosHinarios(
        lista.map((h) => h.id).toList());
  }

  Future<void> _escolherOrdem(OrdemDosHinos o) async {
    setState(() => _ordem = o);
    await LocalStorageService.salvarOrdemDosHinos(o.id);
  }

  /// A lista de ordens, com uma marca na que está valendo.
  ///
  /// É uma folha simples, sem explicação nenhuma: quatro linhas que a pessoa
  /// lê de uma vez. O que precisava de explicação — "mais tocados de quando?"
  /// — fica na própria tela, embaixo da busca, onde a lista está à vista.
  void _abrirOrdenar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Ordenar os hinos',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...OrdemDosHinos.values.map((o) {
              final marcada = o == _ordem;
              return ListTile(
                leading: Icon(
                  marcada
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: marcada
                      ? AppColors.blue
                      : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight),
                ),
                title: Text(
                  o.rotulo,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14.5,
                    fontWeight: marcada ? FontWeight.w600 : FontWeight.w400,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _escolherOrdem(o);
                },
              );
            }),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _buscaCtrl.dispose();
    super.dispose();
  }

  // ─── O teclado ──────────────────────────────────────────────────────────

  void _digitar(String d) {
    HapticFeedback.selectionClick();
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

  void _abrir() {
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
    setState(() {
      _recado = fora != null
          ? 'O hino $n está fora do repertório.'
          : 'O hino $n ainda não está no repertório.';
    });
  }

  void _irPara(SongModel hino) {
    _relogio?.cancel();
    LocalStorageService.salvarHinoAberto(hino.hinario, hino.numero ?? 0);
    setState(() {
      _digitado = '';
      _recado = '';
    });
    if (widget.paraEscolher) {
      Navigator.pop(context, hino);
      return;
    }
    Navigator.push(
      context,
      GlassPageRoute(builder: (_) => SongDetailScreen(song: hino)),
    );
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final songs = context.watch<SongsProvider>();
    final auth = context.watch<AuthProvider>();
    final numeroDigitado = int.tryParse(_digitado);

    // A contagem sai dos cultos que o app já tem em memória — sem coleção
    // nova e sem leitura nova. A janela são 60 dias, e é por isso que a tela
    // diz "nos últimos 2 meses" em vez de prometer o histórico inteiro.
    final vezes = _ordem == OrdemDosHinos.maisTocados
        ? ScaleProvider.vezesTocadas(
            context.watch<ScaleProvider>().scales, DateTime.now())
        : const <String, int>{};
    // Escolher "mais tocados" num ministério que ainda não tem culto nenhum
    // registrado devolveria uma lista em ordem de número sem explicação
    // nenhuma. Então a tela avisa, numa frase, e diz em que ordem ficou.
    final semDados = _ordem == OrdemDosHinos.maisTocados && vezes.isEmpty;
    final ordemValendo = semDados ? OrdemDosHinos.numero : _ordem;

    final achados = SongsProvider.hinosOrdenados(
      songs.hinosDe(_hinario.id, busca: _busca),
      ordemValendo,
      vezesTocadas: vezes,
      favoritas: auth.user?.favoriteSongs.toSet() ?? const {},
    );

    final corpo = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        _SeletorDeHinario(
          ordem: _ordemDosHinarios,
          escolhido: _hinario,
          isDark: isDark,
          onEscolher: _trocarHinario,
          onReordenar: _reordenar,
          onMover: _mover,
        ),
        const SizedBox(height: 18),
        _Mostrador(
          sigla: _hinario.sigla,
          digitado: _digitado,
          isDark: isDark,
        ),
        if (_recado.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Recado(
            texto: _recado,
            isDark: isDark,
            // O botão só aparece para quem o banco deixa cadastrar. Para um
            // levita ele falharia com erro de permissão, que não explica
            // nada — então a frase diz o que fazer em vez de oferecer um
            // caminho fechado.
            acao: (auth.isAdmin &&
                    numeroDigitado != null &&
                    _hinario.existe(numeroDigitado) &&
                    songs.hinoCadastrado(_hinario.id, numeroDigitado) == null)
                ? 'Cadastrar agora'
                : null,
            onAcao: numeroDigitado == null
                ? null
                : () => _cadastrar(numeroDigitado),
            rodape: auth.isAdmin
                ? null
                : 'Peça a um líder para cadastrar este hino.',
            // O atalho para achar a cifra do hino, com o nome do hinário
            // já no texto da busca: "Harpa Cristã 15" é o que acha o hino
            // certo no Cifra Club.
            acaoExtra: (auth.isAdmin &&
                    numeroDigitado != null &&
                    _hinario.existe(numeroDigitado))
                ? 'Buscar no Cifra Club'
                : null,
            onAcaoExtra: numeroDigitado == null
                ? null
                : () => abrirBuscaCifraClub(
                    context, '${_hinario.nome} $numeroDigitado'),
          ),
        ],
        const SizedBox(height: 18),
        _Teclado(
          isDark: isDark,
          onDigito: _digitar,
          onApagar: _apagar,
          onLimpar: _limpar,
          podeApagar: _digitado.isNotEmpty,
        ),
        const SizedBox(height: 26),
        _UltimosAbertos(isDark: isDark, onAbrir: _irPara),
        const SizedBox(height: 26),
        Text(
          'Ou procure pelo nome ou por um trecho',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _buscaCtrl,
                onChanged: (v) => setState(() => _busca = v),
                decoration: InputDecoration(
                  hintText: 'Ex: grato, 15, firme nas promessas',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // DISCRETO, e ao lado da busca de propósito: é aqui que a
            // pessoa está olhando a lista. A busca continua valendo em
            // qualquer ordem — filtrar e ordenar são coisas separadas.
            IconButton(
              icon: const Icon(Icons.swap_vert_rounded),
              tooltip: 'Ordenar',
              onPressed: _abrirOrdenar,
            ),
          ],
        ),
        if (semDados) ...[
          const SizedBox(height: 6),
          Text(
            'Nenhum culto com repertório nos últimos 2 meses, então ainda '
            'não dá para dizer o que é mais tocado. A lista está pelo '
            'número.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              height: 1.4,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        ] else if (_ordem != OrdemDosHinos.numero) ...[
          const SizedBox(height: 6),
          Text(
            _ordem == OrdemDosHinos.maisTocados
                ? 'Mais tocados nos últimos 2 meses, primeiro.'
                : '${_ordem.rotulo}.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (achados.isEmpty)
          _Vazio(
            busca: _busca,
            hinario: _hinario,
            total: songs.hinosDe(_hinario.id).length,
            isDark: isDark,
          )
        else
          ...achados.map((h) => _LinhaDeHino(
                hino: h,
                hinario: _hinario,
                isDark: isDark,
                onAbrir: () => _irPara(h),
              )),
      ],
    );

    if (widget.embutida) return corpo;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.paraEscolher
            ? 'Escolher hino pelo número'
            : 'Hino pelo número'),
      ),
      body: corpo,
    );
  }
}

// ─── Peças da tela ────────────────────────────────────────────────────────

/// Os hinários, na ordem da pessoa — e é ela quem arrasta.
///
/// POR QUE ISTO VIROU UMA LISTA DE PÉ
///
/// Eram duas pastilhas lado a lado, e lado a lado não há "arrastar para
/// cima". O preço são uns 50 px a mais antes do teclado, numa tela de 375 px;
/// o que se ganha é a igreja que canta do Cantor Cristão poder deixá-lo em
/// primeiro **e o app abrir nele**, em vez de tocar na pastilha certa toda
/// vez que abre a tela, sempre com a igreja esperando.
///
/// A alça fica visível, e o mesmo movimento está no menu de cada linha:
/// arrastar exige firmeza na mão, e metade deste ministério tem mais de
/// sessenta anos.
class _SeletorDeHinario extends StatelessWidget {
  final List<Hinario> ordem;
  final Hinario escolhido;
  final bool isDark;
  final ValueChanged<Hinario> onEscolher;
  final void Function(int de, int para) onReordenar;
  final void Function(Hinario h, int passos) onMover;

  const _SeletorDeHinario({
    required this.ordem,
    required this.escolhido,
    required this.isDark,
    required this.onEscolher,
    required this.onReordenar,
    required this.onMover,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Lista rolável aninhada diz o próprio recuo, senão herda o do
      // MediaQuery — que aqui é a barra inteira da aba Músicas, e abriria um
      // buraco de 110 px no meio da tela. Já aconteceu, na Bíblia.
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: ordem.length,
      onReorder: onReordenar,
      itemBuilder: (context, i) {
        final h = ordem[i];
        final ativo = h.id == escolhido.id;
        return Padding(
          key: ValueKey(h.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: ativo
                ? AppColors.blue
                : (isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onEscolher(h),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 20,
                          color: ativo
                              ? Colors.white70
                              : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        h.nome,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ativo
                              ? Colors.white
                              : (isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight),
                        ),
                      ),
                    ),
                    if (i == 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          'abre aqui',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: ativo
                                ? Colors.white70
                                : (isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight),
                          ),
                        ),
                      ),
                    PopupMenuButton<int>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 19,
                        color: ativo
                            ? Colors.white70
                            : (isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight),
                      ),
                      tooltip: 'Mover ${h.nome}',
                      onSelected: (passos) => onMover(h, passos),
                      itemBuilder: (_) => [
                        // A opção que não tem para onde ir some, em vez de
                        // aparecer e não fazer nada — toque que não responde
                        // é o jeito de a pessoa achar que o app travou.
                        if (i > 0)
                          const PopupMenuItem(
                            value: -1,
                            child: Row(children: [
                              Icon(Icons.arrow_upward_rounded, size: 18),
                              SizedBox(width: 10),
                              Text('Mover para cima'),
                            ]),
                          ),
                        if (i < ordem.length - 1)
                          const PopupMenuItem(
                            value: 1,
                            child: Row(children: [
                              Icon(Icons.arrow_downward_rounded, size: 18),
                              SizedBox(width: 10),
                              Text('Mover para baixo'),
                            ]),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Mostrador extends StatelessWidget {
  final String sigla;
  final String digitado;
  final bool isDark;

  const _Mostrador({
    required this.sigla,
    required this.digitado,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final vazio = digitado.isEmpty;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        vazio ? 'Digite o número' : '$sigla $digitado',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: vazio ? 17 : 42,
          fontWeight: vazio ? FontWeight.w500 : FontWeight.w700,
          height: 1.1,
          color: vazio
              ? (isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight)
              : (isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight),
        ),
      ),
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

class _Teclado extends StatelessWidget {
  final bool isDark;
  final ValueChanged<String> onDigito;
  final VoidCallback onApagar;
  final VoidCallback onLimpar;
  final bool podeApagar;

  const _Teclado({
    required this.isDark,
    required this.onDigito,
    required this.onApagar,
    required this.onLimpar,
    required this.podeApagar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final linha in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            children: linha
                .map((d) => _Tecla(
                      rotulo: d,
                      isDark: isDark,
                      onTap: () => onDigito(d),
                    ))
                .toList(),
          ),
        Row(
          children: [
            _Tecla(
              rotulo: 'C',
              isDark: isDark,
              suave: true,
              onTap: podeApagar ? onLimpar : null,
            ),
            _Tecla(rotulo: '0', isDark: isDark, onTap: () => onDigito('0')),
            _Tecla(
              rotulo: '⌫',
              isDark: isDark,
              suave: true,
              onTap: podeApagar ? onApagar : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _Tecla extends StatelessWidget {
  final String rotulo;
  final bool isDark;
  final bool suave;
  final VoidCallback? onTap;

  const _Tecla({
    required this.rotulo,
    required this.isDark,
    this.onTap,
    this.suave = false,
  });

  @override
  Widget build(BuildContext context) {
    final desligada = onTap == null;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: suave
              ? (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04))
              : (isDark ? Colors.white12 : Colors.white),
          borderRadius: BorderRadius.circular(14),
          elevation: suave ? 0 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            // Alto de propósito: é tela usada de pé, com a igreja esperando,
            // e tecla pequena erra.
            child: SizedBox(
              height: 62,
              child: Center(
                child: Text(
                  rotulo,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: desligada
                        ? (isDark ? Colors.white24 : Colors.black26)
                        : (isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight),
                  ),
                ),
              ),
            ),
          ),
        ),
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: abertos.map((h) {
            final hin = hinarioPorId(h.hinario);
            return ActionChip(
              label: Text('${hin?.sigla ?? ''} ${h.numero}'),
              onPressed: () => onAbrir(h),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _LinhaDeHino extends StatelessWidget {
  final SongModel hino;
  final Hinario hinario;
  final bool isDark;
  final VoidCallback onAbrir;

  const _LinhaDeHino({
    required this.hino,
    required this.hinario,
    required this.isDark,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(
        width: 46,
        child: Text(
          '${hino.numero}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.blue,
          ),
        ),
      ),
      title: Text(
        hino.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text('Tom ${hino.originalKey}'),
      onTap: onAbrir,
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
  final int total;
  final bool isDark;

  const _Vazio({
    required this.busca,
    required this.hinario,
    required this.total,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final String texto;
    if (total == 0) {
      texto = 'Nenhum hino da ${hinario.nome} está no repertório ainda. '
          'Eles entram pelo cadastro de música, com a cifra do hinário da '
          'igreja.';
    } else if (busca.trim().isNotEmpty) {
      texto = 'Nenhum hino da ${hinario.nome} com "$busca".';
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
