import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/hinarios.dart';
import '../../../core/utils/importar_hinario.dart';
import '../../providers/auth_provider.dart';
import '../../providers/biblioteca_provider.dart';
import '../../widgets/common/glass.dart';

/// Importar um hinário inteiro de uma vez: colar o texto, conferir, gravar.
///
/// POR QUE ELA EXISTE
///
/// Cadastrar hino é digitar o nome e colar a cifra, um por vez. Um hinário
/// tem 640. A igreja tem autorização para usar o texto, então o que faltava
/// era o caminho: o líder cola o texto, o app separa em hinos, e todo mundo
/// abre o hino pelo teclado numérico.
///
/// O QUE O APP NÃO FAZ: não traz texto de lugar nenhum. O texto é o que o
/// líder cola, de uma fonte que a igreja tem direito de usar.
///
/// AS DUAS COISAS QUE ELA GUARDA
///
/// 1. **Nada é gravado antes de conferir.** O app não sabe como o arquivo da
///    pessoa é escrito, então pode entender errado — e um hino que engole o
///    seguinte parece certo na tela. A prévia diz quantos achou, o que falta
///    e mostra a letra do primeiro, do meio e do último.
/// 2. **O texto vai para a BIBLIOTECA, não para o repertório.** O repertório
///    é lido por inteiro em todo aparelho, e 1.200 hinos ali estourariam a
///    cota de leitura. Aqui o hino só vira música quando o ministério o usa.
class ImportarHinarioScreen extends StatefulWidget {
  const ImportarHinarioScreen({super.key});

  @override
  State<ImportarHinarioScreen> createState() => _ImportarHinarioScreenState();
}

class _ImportarHinarioScreenState extends State<ImportarHinarioScreen> {
  Hinario _hinario = harpaCrista;
  String _texto = '';

  /// Quantas linhas tem o texto colado. Contada UMA vez, ao colar: contar a
  /// cada reconstrução da tela percorreria o hinário inteiro toda vez que a
  /// barra de progresso se mexesse.
  int _linhas = 0;
  ResultadoDaLeitura? _resultado;

  /// Formato escolhido à mão; nulo é "o app decide".
  FormatoDoHinario? _formato;

  bool _lendo = false;
  bool _importando = false;
  int _feitos = 0;
  int _total = 0;

  /// Problema ao colar ou ao gravar, com o motivo.
  String? _erro;

  /// Quantos hinos entraram na última importação que deu certo.
  int? _concluidos;

  bool _manualAberto = false;
  final _manualCtrl = TextEditingController();

  final _rolagem = ScrollController();
  final _chaveDaConferencia = GlobalKey();
  final _chaveDoAviso = GlobalKey();

  /// Leva a tela até [chave], depois de o quadro desenhar.
  ///
  /// Sem isto, quem cola o texto num celular não vê nada acontecer: a
  /// conferência aparece ABAIXO do que cabe na tela, e a pessoa acharia que o
  /// botão não funcionou — a falha silenciosa que este app não aceita.
  void _rolarPara(GlobalKey chave) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final alvo = chave.currentContext;
      if (alvo == null || !mounted) return;
      Scrollable.ensureVisible(
        alvo,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.02,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // Só para dizer "já tem N hinos". Falhar aqui não impede nada: é
    // informação, e a conferência de verdade é a da importação.
    context.read<BibliotecaProvider>().carregarIndice(_hinario.id);
  }

  @override
  void dispose() {
    _rolagem.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  // ── Colar e ler ───────────────────────────────────────────────────────────

  Future<void> _colar() async {
    setState(() => _erro = null);
    String texto;
    try {
      final dados = await Clipboard.getData(Clipboard.kTextPlain);
      texto = dados?.text ?? '';
    } catch (_) {
      // O navegador pode recusar ler a área de transferência. Não é erro de
      // quem copiou, então a tela diz o caminho que sempre funciona.
      if (!mounted) return;
      setState(() {
        _manualAberto = true;
        _erro = 'Este aparelho não deixou o app ler o que você copiou. '
            'Toque em "Colar à mão" aqui embaixo e cole no campo.';
      });
      return;
    }
    if (!mounted) return;
    if (texto.trim().isEmpty) {
      setState(() =>
          _erro = 'Não achei nada copiado. Copie o texto do hinário e toque em '
              '"Colar o texto copiado" de novo.');
      return;
    }
    await _ler(texto);
  }

  Future<void> _ler(String texto) async {
    setState(() {
      _texto = texto;
      _linhas = '\n'.allMatches(texto).length + 1;
      _lendo = true;
      _resultado = null;
      _concluidos = null;
      _erro = null;
    });
    // Deixa o "Lendo o texto…" aparecer antes da conta: com o hinário inteiro
    // ela leva um instante, e a tela parada parece travada.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;
    final r = ImportarHinario.analisar(texto, _hinario, formato: _formato);
    setState(() {
      _resultado = r;
      _lendo = false;
    });
    _rolarPara(_chaveDaConferencia);
  }

  void _trocarHinario(Hinario h) {
    if (_importando || h.id == _hinario.id) return;
    setState(() {
      _hinario = h;
      _concluidos = null;
    });
    context.read<BibliotecaProvider>().carregarIndice(h.id);
    // O texto colado continua valendo: só o limite de números muda.
    if (_texto.isNotEmpty) _ler(_texto);
  }

  void _trocarFormato(FormatoDoHinario? f) {
    setState(() => _formato = f);
    if (_texto.isNotEmpty) _ler(_texto);
  }

  void _recomecar() {
    setState(() {
      _texto = '';
      _linhas = 0;
      _resultado = null;
      _formato = null;
      _erro = null;
      _concluidos = null;
      _manualCtrl.clear();
    });
  }

  // ── Gravar ────────────────────────────────────────────────────────────────

  Future<void> _importar() async {
    final r = _resultado;
    final uid = context.read<AuthProvider>().user?.id;
    if (r == null || !r.achouAlgo || uid == null || _importando) return;

    final biblioteca = context.read<BibliotecaProvider>();
    final indice = biblioteca.indiceDe(_hinario.id);
    final jaTem = r.hinos.where((h) => indice.tem(h.numero)).length;

    final jaTemFrase = switch (jaTem) {
      0 => '',
      1 =>
        '\n\n1 deles já está na biblioteca. O texto novo substitui o antigo.',
      _ => '\n\n$jaTem deles já estão na biblioteca. '
          'O texto novo substitui o antigo.',
    };

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.hinos.length == 1
            ? 'Importar 1 hino?'
            : 'Importar ${r.hinos.length} hinos?'),
        content: Text(
          'Eles vão para a biblioteca da ${_hinario.nome}. '
          'O repertório do ministério não muda.$jaTemFrase',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() {
      _importando = true;
      _feitos = 0;
      _total = r.hinos.length;
      _erro = null;
    });

    final res = await biblioteca.importar(
      hinario: _hinario,
      hinos: r.hinos,
      porQuemId: uid,
      aoAvancar: (feitos, total) {
        if (mounted) setState(() => _feitos = feitos);
      },
    );
    if (!mounted) return;

    setState(() {
      _importando = false;
      if (res.error == null) {
        _concluidos = res.gravados;
        _texto = '';
        _linhas = 0;
        _resultado = null;
        _manualCtrl.clear();
      } else {
        // Diz quantos entraram: é o que a pessoa precisa para decidir. E
        // repetir é seguro — o id é o número, então regrava por cima.
        _erro = res.gravados > 0
            ? 'Entraram ${res.gravados} de ${r.hinos.length} hinos antes do '
                'erro. ${res.error} Toque em Importar para completar: o que '
                'já entrou não duplica.'
            : res.error;
      }
    });
    _rolarPara(_chaveDoAviso);
  }

  // ── Tela ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ehLider = context.watch<AuthProvider>().isAdmin;
    final indice = context.watch<BibliotecaProvider>().indiceDe(_hinario.id);
    final r = _resultado;

    return Scaffold(
      appBar: AppBar(title: const Text('Importar hinário')),
      body: SafeArea(
        child: !ehLider
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('Só os líderes importam hinários.'),
                ),
              )
            : SingleChildScrollView(
                controller: _rolagem,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Texto(
                      'Cole aqui o texto do hinário que a igreja tem '
                      'autorização para usar. O app separa os hinos sozinho, '
                      'e nada é gravado antes de você conferir.',
                      isDark: isDark,
                      muted: true,
                    ),
                    const SizedBox(height: 16),
                    _Passo(
                      numero: 1,
                      titulo: 'Qual hinário?',
                      isDark: isDark,
                      filho: _EscolhaDeHinario(
                        atual: _hinario,
                        desligado: _importando,
                        isDark: isDark,
                        onEscolher: _trocarHinario,
                        jaTem: indice.total,
                      ),
                    ),
                    _Passo(
                      numero: 2,
                      titulo: 'Cole o texto',
                      isDark: isDark,
                      filho: _PassoColar(
                        isDark: isDark,
                        desligado: _importando || _lendo,
                        temTexto: _texto.isNotEmpty,
                        linhas: _linhas,
                        manualAberto: _manualAberto,
                        manualCtrl: _manualCtrl,
                        onColar: _colar,
                        onLimpar: _recomecar,
                        onAbrirManual: () =>
                            setState(() => _manualAberto = !_manualAberto),
                        onUsarManual: () => _ler(_manualCtrl.text),
                      ),
                    ),
                    if (_lendo)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 10),
                              Text('Lendo o texto…'),
                            ],
                          ),
                        ),
                      ),
                    if (r != null)
                      KeyedSubtree(
                          key: _chaveDaConferencia,
                          child: _Passo(
                            numero: 3,
                            titulo: 'Confira',
                            isDark: isDark,
                            filho: _Conferencia(
                              resultado: r,
                              hinario: _hinario,
                              formatoForcado: _formato,
                              isDark: isDark,
                              desligado: _importando,
                              onFormato: _trocarFormato,
                            ),
                          )),
                    if (_erro != null)
                      KeyedSubtree(key: _chaveDoAviso, child: _Erro(_erro!)),
                    if (r != null && r.achouAlgo)
                      _Passo(
                        numero: 4,
                        titulo: 'Importe',
                        isDark: isDark,
                        filho: _Importar(
                          quantos: r.hinos.length,
                          importando: _importando,
                          feitos: _feitos,
                          total: _total,
                          onImportar: _importar,
                        ),
                      ),
                    if (_concluidos != null)
                      KeyedSubtree(
                        key: _chaveDoAviso,
                        child: _Pronto(
                          quantos: _concluidos!,
                          hinario: _hinario,
                          isDark: isDark,
                          onOutro: _recomecar,
                          onFechar: () => Navigator.pop(context),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ── Peças ───────────────────────────────────────────────────────────────────

class _Texto extends StatelessWidget {
  final String texto;
  final bool isDark;
  final bool muted;
  final bool forte;
  final double tamanho;

  const _Texto(
    this.texto, {
    required this.isDark,
    this.muted = false,
    this.forte = false,
    this.tamanho = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: tamanho,
        height: 1.45,
        fontWeight: forte ? FontWeight.w600 : FontWeight.w400,
        color: muted
            ? (isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight)
            : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      ),
    );
  }
}

/// Um passo numerado. Os números dizem a ordem de verdade: não se importa
/// antes de conferir, nem se confere antes de colar.
class _Passo extends StatelessWidget {
  final int numero;
  final String titulo;
  final bool isDark;
  final Widget filho;

  const _Passo({
    required this.numero,
    required this.titulo,
    required this.isDark,
    required this.filho,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$numero',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _Texto(titulo, isDark: isDark, forte: true, tamanho: 16),
              ],
            ),
            const SizedBox(height: 12),
            filho,
          ],
        ),
      ),
    );
  }
}

class _EscolhaDeHinario extends StatelessWidget {
  final Hinario atual;
  final bool desligado;
  final bool isDark;
  final int jaTem;
  final ValueChanged<Hinario> onEscolher;

  const _EscolhaDeHinario({
    required this.atual,
    required this.desligado,
    required this.isDark,
    required this.jaTem,
    required this.onEscolher,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final h in hinariosDisponiveis)
              ChoiceChip(
                label: Text(h.nome),
                selected: h.id == atual.id,
                onSelected: desligado ? null : (_) => onEscolher(h),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _Texto(
          jaTem == 0
              ? 'Ainda não há hinos da ${atual.nome} na biblioteca.'
              : jaTem == 1
                  ? 'Já há 1 hino da ${atual.nome} na biblioteca.'
                  : 'Já há $jaTem hinos da ${atual.nome} na biblioteca.',
          isDark: isDark,
          muted: true,
          tamanho: 13,
        ),
      ],
    );
  }
}

class _PassoColar extends StatelessWidget {
  final bool isDark;
  final bool desligado;
  final bool temTexto;
  final int linhas;
  final bool manualAberto;
  final TextEditingController manualCtrl;
  final VoidCallback onColar;
  final VoidCallback onLimpar;
  final VoidCallback onAbrirManual;
  final VoidCallback onUsarManual;

  const _PassoColar({
    required this.isDark,
    required this.desligado,
    required this.temTexto,
    required this.linhas,
    required this.manualAberto,
    required this.manualCtrl,
    required this.onColar,
    required this.onLimpar,
    required this.onAbrirManual,
    required this.onUsarManual,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Texto(
          'Copie o texto do hinário (pode ser o hinário inteiro, ou só uma '
          'parte) e toque no botão. Cada hino tem de começar com o número, '
          'como em "15 - Título" ou "HINO 15".',
          isDark: isDark,
          muted: true,
          tamanho: 13,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: desligado ? null : onColar,
          icon: const Icon(Icons.content_paste_rounded),
          label: Text(temTexto ? 'Colar de novo' : 'Colar o texto copiado'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
        if (temTexto) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Texto(
                  'Colei o texto: $linhas linhas.',
                  isDark: isDark,
                  muted: true,
                  tamanho: 13,
                ),
              ),
              TextButton(
                onPressed: desligado ? null : onLimpar,
                child: const Text('Limpar'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onAbrirManual,
            child: Text(manualAberto ? 'Fechar o campo' : 'Colar à mão'),
          ),
        ),
        if (manualAberto) ...[
          // O caminho que sempre funciona: segurar no campo e escolher Colar.
          // Serve a quem o aparelho não deixou o app ler a área de
          // transferência. Em partes pequenas — um campo de texto com o
          // hinário inteiro dentro fica lento.
          _Texto(
            'Segure o dedo no campo, escolha Colar e toque em "Ler este '
            'texto". Cole de 100 em 100 hinos: o campo fica rápido, e '
            'o que já entrou não se perde.',
            isDark: isDark,
            muted: true,
            tamanho: 13,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: manualCtrl,
            minLines: 5,
            maxLines: 8,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              hintText: 'Cole o texto aqui',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: desligado ? null : onUsarManual,
            child: const Text('Ler este texto'),
          ),
        ],
      ],
    );
  }
}

class _Conferencia extends StatelessWidget {
  final ResultadoDaLeitura resultado;
  final Hinario hinario;
  final FormatoDoHinario? formatoForcado;
  final bool isDark;
  final bool desligado;
  final ValueChanged<FormatoDoHinario?> onFormato;

  const _Conferencia({
    required this.resultado,
    required this.hinario,
    required this.formatoForcado,
    required this.isDark,
    required this.desligado,
    required this.onFormato,
  });

  /// As linhas de aviso, em português, só as que têm o que dizer.
  ///
  /// Aviso que aparece com tudo certo ensina a não ler os avisos. Cada linha
  /// diz o que ACONTECE com os hinos citados — "não entram", "entram como…" —,
  /// porque é isso que a pessoa precisa para decidir se aceita.
  List<String> _avisos() {
    final r = resultado;
    final saida = <String>[];
    if (r.curtos.isNotEmpty) {
      saida.add('Sem letra, por isso NÃO entram: '
          '${ResultadoDaLeitura.listaDeNumeros(r.curtos)}.');
    }
    if (r.grandes.isNotEmpty) {
      saida.add('Com texto grande demais, provavelmente juntaram o hino '
          'seguinte. NÃO entram: '
          '${ResultadoDaLeitura.listaDeNumeros(r.grandes)}.');
    }
    if (r.semTitulo.isNotEmpty) {
      saida.add('Sem título reconhecido, entram como "Hino N": '
          '${ResultadoDaLeitura.listaDeNumeros(r.semTitulo)}.');
    }
    // No máximo cinco: se o texto estiver muito estragado, uma parede de
    // avisos não se lê, e a frase de cima já diz que faltam muitos.
    for (final p in r.perdidos.take(5)) {
      final onde = p.dentroDe == null ? '' : ', dentro do hino ${p.dentroDe}';
      final linha =
          p.linha.length > 40 ? '${p.linha.substring(0, 40)}…' : p.linha;
      saida.add('O ${p.numero} não foi reconhecido como começo de hino, mas '
          'há uma linha que começa com ${p.numero}$onde: "$linha". Se for o '
          'começo do hino ${p.numero}, conserte essa linha no texto e cole de '
          'novo.${p.dentroDe == null ? '' : ' Por enquanto o texto dele fica '
              'na letra do ${p.dentroDe}, e é melhor NÃO importar assim.'}');
    }
    for (final s in r.suspeitos) {
      // Diz onde está a linha e o que fazer: o app não troca o número sozinho.
      final quem = s.titulo.isEmpty ? 'Um hino' : 'O hino "${s.titulo}"';
      saida.add('$quem está escrito como ${s.escrito}, mas fica entre '
          'o ${s.provavel - 1} e o ${s.provavel + 1}, então deve ser o '
          '${s.provavel}. NÃO entra: corrija o número no texto e cole de '
          'novo.');
    }
    if (r.repetidos.isNotEmpty) {
      saida.add('Apareceram mais de uma vez; ficou a que está na ordem certa '
          'dos números (ou, no empate, a de letra mais comprida): '
          '${ResultadoDaLeitura.listaDeNumeros(r.repetidos)}.');
    }
    if (r.foraDoLimite > 0) {
      saida.add(r.foraDoLimite == 1
          ? '1 linha parecia começo de hino, mas tem um número que a '
              '${hinario.nome} não tem. Foi ignorada.'
          : '${r.foraDoLimite} linhas pareciam começo de hino, mas têm um '
              'número que a ${hinario.nome} não tem. Foram ignoradas.');
    }
    return saida;
  }

  /// Primeiro, do meio e último: o suficiente para ver se o começo e o fim
  /// da letra estão onde deveriam, sem rolar 640 hinos.
  List<HinoLido> _amostra() {
    final h = resultado.hinos;
    if (h.length <= 3) return h;
    return [h.first, h[h.length ~/ 2], h.last];
  }

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    final avisos = _avisos();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Texto(r.frase, isDark: isDark, forte: true, tamanho: 15),
        if (r.formato != null) ...[
          const SizedBox(height: 6),
          _Texto(
            'Entendi cada hino começando assim: ${r.formato!.exemplo}',
            isDark: isDark,
            muted: true,
            tamanho: 13,
          ),
        ],
        if (avisos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: isDark ? 0.18 : 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < avisos.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  _Texto(avisos[i], isDark: isDark, tamanho: 13),
                ],
              ],
            ),
          ),
        ],
        if (r.achouAlgo) ...[
          const SizedBox(height: 14),
          _Texto('Veja se a letra está certa:',
              isDark: isDark, forte: true, tamanho: 13),
          const SizedBox(height: 6),
          for (final h in _amostra()) _AmostraDeHino(hino: h, isDark: isDark),
        ],
        const SizedBox(height: 4),
        _EscolhaDeFormato(
          atual: formatoForcado,
          achado: r.formato,
          desligado: desligado,
          isDark: isDark,
          onEscolher: onFormato,
        ),
      ],
    );
  }
}

class _AmostraDeHino extends StatelessWidget {
  final HinoLido hino;
  final bool isDark;

  const _AmostraDeHino({required this.hino, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Texto('${hino.numero} · ${hino.titulo}',
              isDark: isDark, forte: true, tamanho: 13.5),
          const SizedBox(height: 4),
          Text(
            hino.letra,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
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

/// "Não está certo?" — para quem viu que o app entendeu o texto de outro
/// jeito que o escrito. Fica recolhido: quase sempre o app acerta, e cinco
/// opções à vista fariam parecer que a pessoa precisa escolher.
class _EscolhaDeFormato extends StatelessWidget {
  final FormatoDoHinario? atual;
  final FormatoDoHinario? achado;
  final bool desligado;
  final bool isDark;
  final ValueChanged<FormatoDoHinario?> onEscolher;

  const _EscolhaDeFormato({
    required this.atual,
    required this.achado,
    required this.desligado,
    required this.isDark,
    required this.onEscolher,
  });

  @override
  Widget build(BuildContext context) {
    // O Material TRANSPARENTE no meio é o que deixa o toque aparecer: o
    // ListTile pinta o efeito no Material mais próximo, e sem este o mais
    // próximo é o da tela — com a caixa colorida do cartão na frente, que o
    // esconde. Um Flutter mais novo recusa isso; um mais velho só deixa o
    // toque sem resposta nenhuma.
    return Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Não está certo? Escolher como ler',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5)),
            childrenPadding: EdgeInsets.zero,
            children: [
              RadioGroup<FormatoDoHinario?>(
                groupValue: atual,
                onChanged: (v) {
                  if (!desligado) onEscolher(v);
                },
                child: Column(
                  children: [
                    const RadioListTile<FormatoDoHinario?>(
                      value: null,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Deixar o app decidir',
                          style:
                              TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                    ),
                    for (final f in FormatoDoHinario.values)
                      RadioListTile<FormatoDoHinario?>(
                        value: f,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(f.exemplo,
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}

class _Importar extends StatelessWidget {
  final int quantos;
  final bool importando;
  final int feitos;
  final int total;
  final VoidCallback onImportar;

  const _Importar({
    required this.quantos,
    required this.importando,
    required this.feitos,
    required this.total,
    required this.onImportar,
  });

  @override
  Widget build(BuildContext context) {
    if (importando) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: total == 0 ? null : feitos / total),
          const SizedBox(height: 8),
          Text(
            'Gravando… $feitos de $total. Não feche esta tela.',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
        ],
      );
    }
    return FilledButton.icon(
      onPressed: onImportar,
      icon: const Icon(Icons.download_done_rounded),
      label: Text(quantos == 1 ? 'Importar 1 hino' : 'Importar $quantos hinos'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }
}

class _Erro extends StatelessWidget {
  final String mensagem;
  const _Erro(this.mensagem);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 20, color: AppColors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensagem,
              style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 13.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pronto extends StatelessWidget {
  final int quantos;
  final Hinario hinario;
  final bool isDark;
  final VoidCallback onOutro;
  final VoidCallback onFechar;

  const _Pronto({
    required this.quantos,
    required this.hinario,
    required this.isDark,
    required this.onOutro,
    required this.onFechar,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success),
              const SizedBox(width: 8),
              _Texto('Pronto', isDark: isDark, forte: true, tamanho: 16),
            ],
          ),
          const SizedBox(height: 8),
          _Texto(
            '${quantos == 1 ? '1 hino entrou' : '$quantos hinos entraram'} '
            'na biblioteca da ${hinario.nome}. Agora, em Músicas → Hinários, '
            'é só digitar o número do hino.',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onOutro,
                  child: const Text('Importar mais'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onFechar,
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
