import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/songs_provider.dart';
import '../providers/scale_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../widgets/common/glass.dart';
import 'home/home_screen.dart';
import 'songs/songs_screen.dart';
import 'scale/scale_screen.dart';
import 'chat/chat_screen.dart';
import 'profile/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  AuthProvider? _auth;

  late final List<Widget> _screens = [
    HomeScreen(onNavigateTab: _goToTab),
    const SongsScreen(),
    const ScaleScreen(),
    const ChatScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Defer to after the first frame so provider notifyListeners() (favorites
    // sync, preview seed data) don't fire during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initData();
    });
  }

  void _goToTab(int index) {
    if (index < 0 || index >= _screens.length) return;
    setState(() => _currentIndex = index);
  }

  void _initData() {
    _auth = context.read<AuthProvider>();
    final songs = context.read<SongsProvider>();
    final scale = context.read<ScaleProvider>();
    final chat = context.read<ChatProvider>();

    // Set favorites in songs provider from user data
    if (_auth!.user != null) {
      songs.setFavorites(_auth!.user!.favoriteSongs);
    }
    // Keep favorites in sync reactively (outside of build) so toggling a
    // favorite anywhere updates the Songs filter without a rebuild loop.
    _auth!.addListener(_syncFavorites);

    // Start real-time listeners
    songs.listenToSongs();
    scale.listenToScales();
    chat.listenToMessages();
    chat.listenToTyping();
  }

  void _syncFavorites() {
    if (!mounted) return;
    context
        .read<SongsProvider>()
        .setFavorites(_auth?.user?.favoriteSongs ?? const []);
  }

  @override
  void dispose() {
    _auth?.removeListener(_syncFavorites);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _GlassNavBar(
        currentIndex: _currentIndex,
        onTap: _goToTab,
        isDark: isDark,
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isDark;

  const _GlassNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
  });

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, AppStrings.home),
    (Icons.music_note_outlined, Icons.music_note_rounded, AppStrings.songs),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded,
        AppStrings.scale),
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
        AppStrings.chat),
    (Icons.person_outline_rounded, Icons.person_rounded, AppStrings.profile),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: GlassContainer(
          blur: 28,
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              for (int i = 0; i < _items.length; i++)
                Expanded(
                  child: _GlassNavItem(
                    outlined: _items[i].$1,
                    filled: _items[i].$2,
                    label: _items[i].$3,
                    selected: i == currentIndex,
                    isDark: isDark,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassNavItem extends StatelessWidget {
  final IconData outlined;
  final IconData filled;
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _GlassNavItem({
    required this.outlined,
    required this.filled,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.blue
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? filled : outlined, size: 23, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
