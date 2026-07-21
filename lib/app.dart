import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/context_ext.dart';
import 'core/theme/app_spacing.dart';
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
class SeePhotoApp extends StatelessWidget {
  final bool isFirstRun;

  const SeePhotoApp({super.key, this.isFirstRun = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enpix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      initialRoute: isFirstRun ? '/setup' : '/',
      routes: {
        '/': (_) => const MainScreen(),
        '/setup': (_) => const SetupScreen(),
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
  final _settingsReload = ValueNotifier<int>(0);
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
      _settingsReload.value++;
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

  List<Widget> get _screens {
    final bool supportsPhotos = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    return <Widget>[
      supportsPhotos
          ? const LocalGalleryScreen()
          : _TabScreen(
              title: '本地',
              icon: Icons.photo_library_rounded,
              color: context.colors.brandBlue,
            ),
      CloudGalleryScreen(
        onNavigateToSettings: () => setState(() => _currentIndex = 3),
      ),
      const OverviewScreen(),
      SettingsScreen(reloadNotifier: _settingsReload),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded),
            label: '照片',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_outlined),
            selectedIcon: Icon(Icons.cloud_rounded),
            label: '云端',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: '概览',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

/// Placeholder tab screen for unsupported platforms.
class _TabScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _TabScreen({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 80, color: color.withAlpha(80)),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Enpix v0.1.0',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.colors.labelSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              '端到端加密 · S3 备份 · 跨平台',
              style: TextStyle(color: context.colors.labelSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// First-run setup wizard placeholder.
///
/// Design decisions:
/// - Centered content for focus
/// - Clear value proposition
/// - Single primary action (no decision fatigue)
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.security_rounded,
                size: 80,
                color: context.colors.brandBlue,
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                '欢迎使用 Enpix',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '端到端加密照片备份',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: context.colors.labelSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushReplacementNamed('/'),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('开始使用'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
