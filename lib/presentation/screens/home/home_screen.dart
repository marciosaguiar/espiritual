import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scale_provider.dart';
import '../../providers/songs_provider.dart';
import '../../widgets/common/install_banner.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/scale_model.dart';
import '../biblia/biblia_screen.dart';
import '../scale/scale_detail_screen.dart';
import '../scale/modo_ao_vivo_screen.dart';
import '../../../data/services/avisos_de_sincronia.dart';
import '../../widgets/home/avisos_de_sincronia.dart';
import '../../widgets/home/aviso_de_saude.dart';
import '../../widgets/home/pendencias.dart';
import '../../../data/services/local_storage_service.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/common/glass.dart';
import '../../widgets/common/responsivo.dart';
import '../../widgets/common/recuperacao_por_email.dart';
import '../../widgets/common/minhas_proximas_musicas.dart';
import '../../../data/models/user_model.dart';

class HomeScreen extends StatefulWidget {
  /// Leva para a aba Perfil. A foto no canto parecia um botão e não era:
  /// quem toca ali espera o próprio perfil, não um enfeite.
  final VoidCallback? onAbrirPerfil;

  /// Para onde as pendências levam. Vêm de fora porque quem troca de aba é o
  /// `main_screen`: o Início não conhece a barra de baixo.
  final VoidCallback? onAbrirChat;
  final VoidCallback? onAbrirMembros;
  final VoidCallback? onAbrirEscala;

  const HomeScreen({
    super.key,
    this.onAbrirPerfil,
    this.onAbrirChat,
    this.onAbrirMembros,
    this.onAbrirEscala,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Não há nada esperando por esta pessoa?
  ///
  /// A pergunta usa as MESMAS contas que desenham os cartões (as funções de
  /// `pendencias.dart`). Se fossem duas contas, um dia a tela diria "tudo em
  /// ordem" com um cartão de pendência do lado.
  bool _nadaPendente(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final eu = auth.user;
    if (eu == null) return false;

    final chat = context.watch<ChatProvider>();
    final escala = context.watch<ScaleProvider>();
    final proximo = escala.nextScale;

    final temCulto = proximo != null && proximo.isUserInScale(eu.id);
    final temMensagem = chat.naoLidasNoInicio(eu.id) > 0;
    final temLider = auth.isAdmin &&
        (quantosPendentes(auth.pessoas) > 0 ||
            cultosSemEscala(escala.scales, DateTime.now()).isNotEmpty);

    // Um recado de edição que não valeu é pendência: dizer "nada pendente"
    // acima dele seria mentir.
    final temRecado = AvisosDeSincronia.instancia.temAviso;

    return !temCulto && !temMensagem && !temLider && !temRecado;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final scale = context.watch<ScaleProvider>();
    final songs = context.watch<SongsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nextScale = scale.nextScale;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: Stack(
              fit: StackFit.expand,
              children: [
                // Real frosted blur of the content scrolling behind the header.
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: Container(
                      color: isDark
                          ? const Color(0x8C141019)
                          : Colors.white.withOpacity(0.55),
                    ),
                  ),
                ),
                FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                  title: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Sem emoji, de propósito. O 👋 fazia o navegador baixar a fonte de
                        // emoji do Google (~380 KB, de um servidor de fora, com
                        // conexão nova) NA ABERTURA DE TODO DIA, só para
                        // desenhar uma mão — numa linha lenta são uns 2 s.
                        'Olá, ${auth.user?.name.split(' ').first ?? 'Levita'}!',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE, d \'de\' MMMM', 'pt_BR')
                            .format(DateTime.now()),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // A Bíblia VOLTOU para a tela principal (pedido do dono). Tinha ido
              // para a aba Músicas na rodada "menos é mais", e quem lê antes do
              // culto não a achava. Fica na BARRA DE CIMA, ao lado do avatar, e
              // não no meio da tela: o Início de quem está escalado já enche o
              // celular (cartão do culto + as músicas), e um atalho no fim ficaria
              // abaixo da dobra. Na barra fixa ele está à vista a qualquer
              // momento, sem custar nenhuma altura.
              const _AtalhoBiblia(),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Semantics(
                  button: true,
                  label: 'Abrir meu perfil',
                  child: InkWell(
                    onTap: widget.onAbrirPerfil,
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.blue.withOpacity(0.15),
                      child: Text(
                        (auth.user?.name.isNotEmpty == true)
                            ? auth.user!.name[0].toUpperCase()
                            : 'L',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: AppColors.blue,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: LayoutBuilder(
                builder: (context, c) {
                  // O aviso de robô parado vem ANTES de tudo: é o único
                  // cartão desta tela que ninguém mais vai ver se não for
                  // agora, e cada dia de silêncio é um culto sem escala ou um
                  // lembrete que não chegou.
                  final saude = AvisoDeSaude(
                    onAbrir: widget.onAbrirPerfil ?? () {},
                  );

                  // UM CARTÃO SÓ DE CULTO.
                  //
                  // Eram dois, com a mesma data e o mesmo culto: "Meu próximo
                  // compromisso" no topo e "Próximo culto" no fim da tela,
                  // com o Início inteiro entre eles. Quem estava escalado lia
                  // a mesma informação duas vezes e tinha de descobrir que
                  // eram o mesmo culto; quem não estava via um cartão
                  // vermelho sumir e o outro aparecer, sem entender a
                  // diferença.
                  //
                  // Agora é um: se eu estou escalado, ele fala comigo e traz
                  // o botão de confirmar; se não, mostra o próximo culto do
                  // ministério. Nos dois casos, o toque abre o culto.
                  //
                  // O repertório do meu próximo culto, cada música abrindo no
                  // toque, no tom e na função daquele culto, fica junto do
                  // cartão: é a mesma pergunta — "o que eu toco no domingo?" —
                  // e são duas partes da resposta.
                  final doCulto = <Widget>[
                    _CartaoDoCulto(scale: nextScale, songs: songs),
                    const MinhasProximasMusicas(),
                  ];

                  // As pendências, e SÓ quando existem: pedidos de entrada e
                  // culto sem escala, para o líder; mensagens novas, para
                  // todos.
                  //
                  // OS DOIS CONVITES FICAM NO FIM, e isso foi medido. Eles
                  // abriam a tela, e a 375 px os dois juntos empurravam o
                  // cartão do culto para fora do primeiro olhar. Nenhum dos
                  // dois é "agora" — instalar e cadastrar e-mail são coisas de
                  // uma vez na vida —, e os dois somem sozinhos quando estão
                  // feitos.
                  //
                  // O que SAIU desta tela, e para onde foi: "Hino pelo
                  // número" → aba Músicas; versículo do dia → topo da Bíblia;
                  // sugestões do dia → Repertório. (O atalho da Bíblia saiu e
                  // VOLTOU: ver `_AtalhoBiblia`.)
                  final aviso = <Widget>[
                    // Recado de uma edição que não valeu: vem antes de tudo
                    // porque é sobre algo que a pessoa JÁ fez e acha que está
                    // salvo.
                    const CartaoDeAvisosDeSincronia(),
                    Pendencias(
                      onAbrirChat: widget.onAbrirChat,
                      onAbrirMembros: widget.onAbrirMembros,
                      onAbrirEscala: widget.onAbrirEscala,
                    ),
                    const InstallBanner(),
                    const _CartaoRecuperarSenha(),
                    // Os recados não vêm de um Provider: sem escutá-los aqui,
                    // a linha "nada pendente" ficaria na tela depois de um
                    // recado chegar.
                    ListenableBuilder(
                      listenable: AvisosDeSincronia.instancia,
                      builder: (ctx, _) =>
                          NadaPendente(mostrar: _nadaPendente(ctx)),
                    ),
                  ];

                  // Em tela larga as duas metades da pergunta ficam lado a
                  // lado: o que eu toco, à esquerda; o que está esperando por
                  // mim, à direita. Em celular, uma coluna só, como sempre.
                  final lado = c.maxWidth >= 860;
                  if (!lado) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        saude,
                        ...doCulto,
                        ...aviso,
                        const SizedBox(height: 100),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      saude,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: doCulto,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: aviso,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Atalho para a Bíblia, na barra de cima da tela principal.
///
/// Uma pílula com TEXTO e ícone, e não um ícone sozinho: o que está atrás de um
/// ícone não existe para quem só usa WhatsApp. A tela e o texto só são
/// carregados no toque — a Bíblia não entra no pacote inicial nem atrasa a
/// abertura de quem nunca a lê. Abre por cima, como os outros toques do Início
/// (que não é mestre-detalhe), e a mesma Bíblia continua dentro da aba Músicas:
/// nada foi removido, só ganhou um segundo caminho.
class _AtalhoBiblia extends StatelessWidget {
  const _AtalhoBiblia();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Center(
        child: Semantics(
          button: true,
          label: 'Bíblia. Ler no aparelho, sem internet.',
          excludeSemantics: true,
          child: ComMao(
            onTap: () => Navigator.push(
              context,
              GlassPageRoute(builder: (_) => const BibliaScreen()),
            ),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: isDark ? 0.28 : 0.13),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_rounded,
                      size: 19,
                      color: isDark ? Colors.white : AppColors.blue),
                  const SizedBox(width: 7),
                  Text(
                    'Bíblia',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Cadastre um e-mail para recuperar a senha", no Início.
///
/// Some sozinho quando a conta já tem e-mail, e NÃO tem "agora não" — o
/// botão de dispensar foi o que fez o dono do app passar semanas sem o
/// aplicativo instalado, sem entender por que os avisos não chegavam. Aqui o
/// preço de dispensar seria maior: perder o acesso à própria conta.
class _CartaoRecuperarSenha extends StatelessWidget {
  const _CartaoRecuperarSenha();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.emailDeRecuperacao != null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => mostrarRecuperacaoPorEmail(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.yellow.withValues(alpha: isDark ? 0.14 : 0.10),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.yellow.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 22, color: AppColors.yellowDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cadastre um e-mail',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Sem ele, uma senha esquecida não tem volta.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        height: 1.35,
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
      ),
    );
  }
}

/// O cartão do culto no Início: um só.
///
/// Eram dois, com a mesma data e o mesmo culto — "Meu próximo compromisso" no
/// topo e "Próximo culto" no fim, com a tela inteira entre eles. Quem estava
/// escalado lia a mesma informação duas vezes; quem não estava via um cartão
/// vermelho sumir e outro aparecer, sem entender a diferença.
class _CartaoDoCulto extends StatelessWidget {
  final ScaleModel? scale;
  final SongsProvider songs;

  const _CartaoDoCulto({this.scale, required this.songs});

  @override
  Widget build(BuildContext context) {
    final eu = context.watch<AuthProvider>().user;
    final culto = scale;
    final euEstouEscalado =
        culto != null && eu != null && culto.isUserInScale(eu.id);

    // É HOJE? Então o botão do Modo ao vivo entra, abaixo do cartão.
    //
    // Domingo, com a igreja de pé, chegar ao Modo ao vivo era: abrir a aba
    // Escala, achar o culto, abrir, rolar até o botão. Quatro toques, no
    // único momento em que ninguém tem tempo.
    final ehHoje = culto != null &&
        DateTime(culto.date.year, culto.date.month, culto.date.day) ==
            DateTime(DateTime.now().year, DateTime.now().month,
                DateTime.now().day);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          GestureDetector(
        onTap: culto == null
            ? null
            : () => Navigator.push(
                  context,
                  GlassPageRoute(
                    builder: (_) => ScaleDetailScreen(scale: culto),
                  ),
                ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              if (euEstouEscalado) _MyNextCallCard(scale: culto),
              _NextServiceCard(
                scale: culto,
                songs: songs,
                comFaixaEmCima: euEstouEscalado,
              ),
            ],
          ),
        ),
          ),
          if (ehHoje && euEstouEscalado) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  GlassPageRoute(
                    builder: (_) => ModoAoVivoScreen(
                      culto: culto,
                      funcaoNoCulto: _minhaFuncao(context, culto),
                    ),
                  ),
                ),
                icon: const Icon(Icons.queue_music_rounded, size: 21),
                label: const Text('Modo Culto ao vivo'),
                style: FilledButton.styleFrom(
                  // Alto: é botão que se toca de pé, com o instrumento na
                  // mão.
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A minha função NESTE culto, para a música abrir em cifra ou em letra.
  ///
  /// A mesma conta da tela do culto: quem canta num domingo e toca baixo no
  /// outro precisa de coisas diferentes, e é a escala que sabe qual é hoje.
  UserInstrument? _minhaFuncao(BuildContext context, ScaleModel culto) {
    final eu = context.read<AuthProvider>().user?.id;
    if (eu == null) return null;
    for (final l in culto.levitas) {
      if (l.userId == eu) {
        return UserInstrumentExtension.fromString(l.instrument);
      }
    }
    return null;
  }
}

class _NextServiceCard extends StatelessWidget {
  final ScaleModel? scale;
  final SongsProvider songs;

  /// Há uma faixa pessoal em cima? Então este corpo não desenha canto nem
  /// borda próprios: os dois são um cartão só.
  final bool comFaixaEmCima;

  const _NextServiceCard({
    this.scale,
    required this.songs,
    this.comFaixaEmCima = false,
  });

  @override
  Widget build(BuildContext context) {
    // Nome por id: o culto guarda cópia, e o gerador da agenda fixa grava
    // vazio — os chips apareciam em branco.
    final nomes = context.watch<AuthProvider>().nomes;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius:
            comFaixaEmCima ? BorderRadius.zero : BorderRadius.circular(20),
        border: comFaixaEmCima
            ? null
            : Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.church_rounded, color: AppColors.yellow, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                // Com a faixa em cima já dizendo "Você toca domingo", repetir
                // "Próximo culto" aqui seria dizer duas vezes a mesma coisa
                // dentro do mesmo cartão.
                comFaixaEmCima ? 'Neste culto' : AppStrings.nextService,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (scale == null)
            Text(
              AppStrings.noNextService,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            )
          else ...[
            // Date
            _InfoRow(
              icon: Icons.calendar_today_rounded,
              text: DateFormat("EEEE, d 'de' MMMM', às' HH:mm", 'pt_BR')
                  .format(scale!.date),
              color: AppColors.blue,
            ),
            const SizedBox(height: 8),
            // Service type
            _InfoRow(
              icon: Icons.church_rounded,
              text: scale!.serviceType,
              color: AppColors.red,
            ),
            if (scale!.songs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Músicas (${scale!.songs.length})',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 6),
              ...scale!.songs.take(3).map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note_rounded,
                            size: 14, color: AppColors.blue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _songLabel(context, s),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )),
              if (scale!.songs.length > 3)
                Text(
                  '+ ${scale!.songs.length - 3} músicas',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: AppColors.blue,
                  ),
                ),
            ],
            if (scale!.levitas.isNotEmpty) ...[
              const SizedBox(height: 12),
              // "3 de 7 confirmaram" no lugar de "Levitas (7)".
              //
              // A pergunta do líder no sábado à noite não é quantas pessoas
              // estão escaladas — é quantas já disseram que vêm. Ele
              // respondia isso abrindo o culto e contando os nomes verdes.
              Row(
                children: [
                  Icon(
                    scale!.todosConfirmaram
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    size: 14,
                    color: scale!.todosConfirmaram
                        ? AppColors.success
                        : AppColors.textSecondaryLight,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    scale!.textoDaConfirmacao,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scale!.todosConfirmaram
                          ? AppColors.success
                          : (isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: scale!.levitas.map((l) {
                  // MEDIDO NO MODO ESCURO: estas pastilhas eram brancas
                  // (`grey.shade100` fixo), e no tema escuro apareciam como
                  // retalhos claros no meio do cartão — parecia defeito.
                  // Agora quem não confirmou segue o tema.
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: l.confirmed
                          ? AppColors.success.withValues(alpha: 0.1)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.07)
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: l.confirmed
                            ? AppColors.success.withValues(alpha: 0.3)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (l.confirmed)
                          const Icon(Icons.check_circle_rounded,
                              size: 12, color: AppColors.success),
                        if (l.confirmed) const SizedBox(width: 4),
                        Text(
                          l.nomeCom(nomes),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: l.confirmed
                                ? AppColors.success
                                : (isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              // QUEM FALTA, pelo nome.
              //
              // Os chips já dizem quem confirmou, mas ler ausência numa lista
              // é trabalho: o olho conta os que têm tique. A frase diz
              // diretamente de quem o líder precisa cobrar — que é a única
              // coisa que ele pode FAZER a respeito.
              if (scale!.naoConfirmados.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  scale!.faltamConfirmar(nomes),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoRow({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
        ),
      ],
    );
  }
}

/// Label for a song referenced by a service: "Nome • Artista", with the artist
/// dropped when unknown. Read from the repertoire, never from a stored copy.
String _songLabel(BuildContext context, ScaleSong ref) {
  final songs = context.read<SongsProvider>();
  final artist = songs.artistOf(ref);
  final name = songs.nameOf(ref);
  return artist.isEmpty ? name : '$name • $artist';
}

/// "Você toca domingo às 9h" — the first thing on the screen when this person
/// is scheduled, with the confirm button right there.
///
/// The information existed: [ScaleModel.isUserInScale] and
/// [ScaleModel.hasUserConfirmed] were written and never called from this
/// screen, so somebody only found out they were scheduled by opening the
/// Escala tab and guessing the day. Nothing is shown when they are not
/// scheduled: an empty promise would be worse than silence.
class _MyNextCallCard extends StatefulWidget {
  final ScaleModel? scale;
  const _MyNextCallCard({this.scale});

  @override
  State<_MyNextCallCard> createState() => _MyNextCallCardState();
}

class _MyNextCallCardState extends State<_MyNextCallCard> {
  bool _saving = false;

  Future<void> _confirm(String userId, bool confirmed) async {
    setState(() => _saving = true);
    final error = await context
        .read<ScaleProvider>()
        .confirmPresence(widget.scale!.id, userId, confirmed);

    if (!mounted) return;
    setState(() => _saving = false);
    // Sem internet a escolha vale na tela e espera para ir ao líder: a
    // mensagem diz isso, e não "confirmada" como se já tivesse chegado.
    final pendente = context
        .read<ScaleProvider>()
        .presencaPendente(widget.scale!.id, userId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ??
            (pendente
                ? 'Salvo. O líder será avisado quando a internet voltar.'
                : (confirmed ? 'Presença confirmada!' : 'Presença cancelada'))),
        backgroundColor: error == null ? AppColors.success : AppColors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final user = context.watch<AuthProvider>().user;
    if (scale == null || user == null || !scale.isUserInScale(user.id)) {
      return const SizedBox.shrink();
    }

    // Reads from the live list so the card follows a confirmation given on the
    // service screen.
    final live = context.select<ScaleProvider, ScaleModel?>((p) {
      for (final s in p.scales) {
        if (s.id == scale.id) return s;
      }
      return null;
    }) ?? scale;

    final confirmed = live.hasUserConfirmed(user.id);
    final aguardando = context
        .select<ScaleProvider, bool>((p) => p.presencaPendente(live.id, user.id));
    // "domingo, 19h" — sem os minutos quando são zero, que é o caso de quase
    // todo culto, e sem o "às", que a frase não precisa.
    final hora = live.date.minute == 0
        ? '${DateFormat('HH', 'pt_BR').format(live.date)}h'
        : DateFormat('HH:mm', 'pt_BR').format(live.date);
    final quando = '${DateFormat('EEEE', 'pt_BR').format(live.date)}, $hora';
    final faltam = _faltam(live.date);

    // A FUNÇÃO ENTRA NA FRASE: "Você toca domingo, 19h, no baixo".
    //
    // Sem ela a pessoa lia "você toca domingo" e abria o culto só para
    // descobrir em quê — e quem canta não "toca", então a frase inteira muda.
    final minha = UserInstrumentExtension.fromString(
      live.levitas
          .firstWhere((l) => l.userId == user.id,
              orElse: () => const ScaleLevita(
                  userId: '', userName: '', instrument: 'other'))
          .instrument,
    );
    final frase = minha == UserInstrument.vocalist
        ? 'Você canta $quando'
        : (minha.naFrase.isEmpty
            ? 'Você toca $quando'
            : 'Você toca $quando, ${minha.naFrase}');

    // Sem canto arredondado e sem margem: esta faixa é o TOPO do cartão
    // único do culto, e quem arredonda é o `ClipRRect` de fora.
    return Padding(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: confirmed
                ? [const Color(0xFF13694F), const Color(0xFF1B8A68)]
                : [const Color(0xFF8E0000), const Color(0xFFB3261E)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  confirmed
                      ? Icons.check_circle_rounded
                      : Icons.campaign_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    frase,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${live.serviceType}$faltam',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                color: Colors.white70,
              ),
            ),
            if (aguardando)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Esperando a internet para avisar o líder',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            if (_saving)
              const SizedBox(
                height: 36,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              )
            else if (confirmed)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Presença confirmada. Obrigado!',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _confirm(user.id, false),
                    child: const Text(
                      'Não vou poder',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.white70,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white70,
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirm(user.id, true),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'Confirmar presença',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF8E0000),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// " · é hoje", " · amanhã", " · em 3 dias".
  String _faltam(DateTime quando) {
    final hoje = DateTime.now();
    final dias = DateTime(quando.year, quando.month, quando.day)
        .difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;
    if (dias < 0) return '';
    if (dias == 0) return ' · é hoje';
    if (dias == 1) return ' · amanhã';
    return ' · em $dias dias';
  }
}
