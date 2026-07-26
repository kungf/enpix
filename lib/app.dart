import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/local_gallery/local_gallery_screen.dart';
import 'presentation/screens/cloud_gallery/cloud_gallery_screen.dart';
import 'presentation/screens/overview/overview_screen.dart';
import 'services/providers.dart';

/// Root widget of the Enpix app.
///
/// Design decisions:
/// - iOS 18-style light theme
/// - 4-tab navigation: Local / Cloud / Overview / Settings
/// - IndexedStack preserves tab state across switches
class EnpixApp extends StatelessWidget {
  const EnpixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enpix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (_) => const MainScreen(),
      },
    );
  }
}

/// Main 3-tab screen with iOS-style navigation.
///
/// Design decisions:
/// - IndexedStack preserves tab state (no rebuild on switch)
/// - Bottom navigation in thumb zone
/// - Consistent SafeArea handling
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final _log = Logger('MainScreen');
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    // Auto-unlock KEK session from saved passphrase.
    final credService = ref.read(credentialServiceProvider);
    final unlocked = await credService.autoUnlock();
    if (unlocked) {
      _log.info('KEK session auto-unlocked');
      ref.read(sessionTickProvider.notifier).state++;
    }

    // Run TTL cleanup after unlock.
    try {
      final deleted = await ref.read(ttlEngineProvider).run();
      if (deleted > 0) {
        _log.info('TTL cleaned up $deleted photos');
      }
    } catch (e) {
      _log.warning('TTL engine error: $e');
    }
  }

  bool get _supportsPhotos =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Index of the Settings tab (shifts when the Photos tab is hidden on
  /// desktop/web).
  int get _settingsTabIndex => _supportsPhotos ? 3 : 2;

  List<Widget> get _screens {
    return <Widget>[
      if (_supportsPhotos) LocalGalleryScreen(
        onNavigateToSettings: () =>
            setState(() => _currentIndex = _settingsTabIndex),
      ),
      CloudGalleryScreen(
        onNavigateToSettings: () =>
            setState(() => _currentIndex = _settingsTabIndex),
      ),
      OverviewScreen(
        onNavigateToSettings: () =>
            setState(() => _currentIndex = _settingsTabIndex),
      ),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          if (_supportsPhotos)
            const NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library_rounded),
              label: '照片',
            ),
          const NavigationDestination(
            icon: Icon(Icons.cloud_outlined),
            selectedIcon: Icon(Icons.cloud_rounded),
            label: '云端',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: '概览',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
