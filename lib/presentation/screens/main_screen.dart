import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/songs_provider.dart';
import '../providers/scale_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/auth_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
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

  final List<Widget> _screens = const [
    HomeScreen(),
    SongsScreen(),
    ScaleScreen(),
    ChatScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    final auth = context.read<AuthProvider>();
    final songs = context.read<SongsProvider>();
    final scale = context.read<ScaleProvider>();
    final chat = context.read<ChatProvider>();

    // Set favorites in songs provider from user data
    if (auth.user != null) {
      songs.setFavorites(auth.user!.favoriteSongs);
    }

    // Start real-time listeners
    songs.listenToSongs();
    scale.listenToScales();
    chat.listenToMessages();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: AppStrings.home,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.music_note_outlined),
              activeIcon: Icon(Icons.music_note_rounded),
              label: AppStrings.songs,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              activeIcon: Icon(Icons.calendar_month_rounded),
              label: AppStrings.scale,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: AppStrings.chat,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: AppStrings.profile,
            ),
          ],
        ),
      ),
    );
  }
}
