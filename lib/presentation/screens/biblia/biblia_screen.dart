import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/livros_biblia.dart';
import '../../../data/services/biblia_service.dart';
import '../../providers/biblia_provider.dart';
import '../../widgets/common/glass.dart';
import 'biblia_leitura_screen.dart';

/// A porta da Bíblia: escolher a tradução, achar o livro, abrir o capítulo.
///
/// O provider nasce aqui, e não em `main.dart` junto dos outros, porque a
/// Bíblia só deve custar alguma coisa a quem a abre.
class BibliaScreen extends StatelessWidget {
  const BibliaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BibliaProvider()..iniciar(),
      child: const _BibliaCorpo(),
    );
  }
}

class _BibliaCorpo extends StatefulWidget {
  const _BibliaCorpo();

  @override
  State<_BibliaCorpo> createState() => _BibliaCorpoState();
}

class _BibliaCorpoState extends State<_BibliaCorpo> {
  final _busca = TextEditingController();
  String _procurando = '';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  List<LivroBiblia> _filtrar(List<LivroBiblia> livros) {
    if (_procurando.isEmpty) return livros;
    final q = LivroBiblia('', _procurando, Testamento.antigo).buscavel;
    return livros.where((l) => l.buscavel.contains(q)).toList();
  }

  void _abrir(BuildContext context, LivroBiblia livro) {
    final b = context.read<BibliaProvider>();
    final total = b.traducao?.quantosCapitulos(livro.sigla) ?? 0;
    if (total == 0) return;
    if (total == 1) {
      _lerCapitulo(context, livro, 1);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EscolherCapitulo(
        livro: livro,
        total: total,
        aoEscolher: (n) => _lerCapitulo(context, livro, n),
      ),
    );
  }

  void _lerCapitulo(BuildContext context, LivroBiblia livro, int capitulo) {
    final provider = context.read<BibliaProvider>();
    Navigator.push(
      context,
      GlassPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: provider,
          child: BibliaLeituraScreen(livro: livro, capitulo: capitulo),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.watch<BibliaProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final corTexto =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Bíblia'),
        actions: [
          TextButton.icon(
            onPressed: () => _escolherTraducao(context, b),
            icon: const Icon(Icons.translate_rounded, size: 18),
            label: Text(b.descricaoAtual.sigla),
            style: TextButton.styleFrom(foregroundColor: AppColors.blue),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: b.carregando
          ? _Carregando(tamanho: b.descricaoAtual.tamanho)
          : b.erro != null
              ? _Falhou(
                  mensagem: b.erro!,
                  aoTentar: () => b.trocarTraducao(b.idAtual),
                )
              : _listaDeLivros(context, b, isDark, corTexto),
    );
  }

  Widget _listaDeLivros(
      BuildContext context, BibliaProvider b, bool isDark, Color corTexto) {
    final livros = b.traducao?.livros ?? const <LivroBiblia>[];
    final antigo = _filtrar(livros.where((l) => l.ehAntigo).toList());
    final novo = _filtrar(livros.where((l) => !l.ehAntigo).toList());
    final ultima = b.ultimaLeitura;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            controller: _busca,
            onChanged: (v) => setState(() => _procurando = v.trim()),
            style: TextStyle(fontFamily: 'Poppins', color: corTexto),
            decoration: InputDecoration(
              hintText: 'Procurar livro',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: (antigo.isEmpty && novo.isEmpty)
              ? Center(
                  child: Text(
                    'Nenhum livro com "$_procurando"',
                    style: TextStyle(fontFamily: 'Poppins', color: corTexto),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                  children: [
                    if (ultima != null && _procurando.isEmpty)
                      _ContinuarLendo(
                        ultima: ultima,
                        isDark: isDark,
                        aoTocar: () {
                          final livro = livrosDaBiblia.firstWhere(
                            (l) => l.sigla == ultima.livro,
                            orElse: () => livrosDaBiblia.first,
                          );
                          _lerCapitulo(context, livro, ultima.capitulo);
                        },
                      ),
                    if (antigo.isNotEmpty) ...[
                      _Titulo('Antigo Testamento', corTexto),
                      _Grade(livros: antigo, aoTocar: (l) => _abrir(context, l)),
                    ],
                    if (novo.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _Titulo('Novo Testamento', corTexto),
                      _Grade(livros: novo, aoTocar: (l) => _abrir(context, l)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  void _escolherTraducao(BuildContext context, BibliaProvider b) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EscolherTraducao(provider: b),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;
  final Color cor;
  const _Titulo(this.texto, this.cor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        texto,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }
}

/// A grade de livros. Três colunas no celular: nome inteiro sem cortar, e
/// alvo de toque grande o bastante para quem lê a Bíblia de pé, no culto.
class _Grade extends StatelessWidget {
  final List<LivroBiblia> livros;
  final void Function(LivroBiblia) aoTocar;

  const _Grade({required this.livros, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        childAspectRatio: 2.1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: livros.length,
      itemBuilder: (_, i) {
        final livro = livros[i];
        return GestureDetector(
          onTap: () => aoTocar(livro),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
            child: Text(
              livro.nome,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ContinuarLendo extends StatelessWidget {
  final ({String traducao, String livro, int capitulo}) ultima;
  final bool isDark;
  final VoidCallback aoTocar;

  const _ContinuarLendo({
    required this.ultima,
    required this.isDark,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        onTap: aoTocar,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: isDark ? 0.16 : 0.09),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.menu_book_rounded,
                  color: AppColors.blue, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continuar lendo',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                    Text(
                      '${nomeDoLivro(ultima.livro)} ${ultima.capitulo}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.blue),
            ],
          ),
        ),
      ),
    );
  }
}

class _EscolherCapitulo extends StatelessWidget {
  final LivroBiblia livro;
  final int total;
  final void Function(int) aoEscolher;

  const _EscolherCapitulo({
    required this.livro,
    required this.total,
    required this.aoEscolher,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171C23) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            livro.nome,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 58,
                childAspectRatio: 1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: total,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  aoEscolher(i + 1);
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.blue,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EscolherTraducao extends StatelessWidget {
  final BibliaProvider provider;
  const _EscolherTraducao({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final corTexto =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
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
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Tradução',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: corTexto,
            ),
          ),
          const SizedBox(height: 10),
          for (final t in traducoesDisponiveis)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                provider.idAtual == t.id
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: provider.idAtual == t.id ? AppColors.blue : Colors.grey,
              ),
              title: Text(
                t.nome,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: corTexto,
                ),
              ),
              subtitle: Text(
                // Antes de baixar, a pessoa vê o que vai custar e sob que
                // licença o texto está.
                BibliaService.jaCarregada(t.id)
                    ? '${t.licencaCurta} · já baixada'
                    : '${t.licencaCurta} · ${t.tamanho} para baixar',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                provider.trocarTraducao(t.id);
              },
            ),
          const SizedBox(height: 6),
          Text(
            'Só traduções que podem ser distribuídas dentro do app. Para NVI, '
            'ARA e outras, use "Abrir no YouVersion" na tela de leitura.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              height: 1.45,
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

class _Carregando extends StatelessWidget {
  final String tamanho;
  const _Carregando({required this.tamanho});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.blue),
          const SizedBox(height: 18),
          Text(
            'Baixando a tradução ($tamanho)',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Só desta vez. Depois ela fica no aparelho e abre sem internet.',
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
    );
  }
}

class _Falhou extends StatelessWidget {
  final String mensagem;
  final VoidCallback aoTentar;
  const _Falhou({required this.mensagem, required this.aoTentar});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 46, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14.5,
                height: 1.5,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: aoTentar,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: Colors.white),
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
