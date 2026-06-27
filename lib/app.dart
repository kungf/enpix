import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/local_gallery/local_gallery_screen.dart';
import 'presentation/screens/cloud_gallery/cloud_gallery_screen.dart';

/// Root widget of the Enpix app.
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

/// Main 3-tab screen.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  List<Widget> get _screens {
    // photo_manager only works on iOS/Android, fall back to placeholder on macOS
    final bool supportsPhotos = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);
    return <Widget>[
      supportsPhotos ? const LocalGalleryScreen() : const _TabScreen(title: '本地', icon: Icons.photo_library_rounded, color: Colors.blue),
      const CloudGalleryScreen(),
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
        destinations: const [
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library_rounded), label: '本地'),
          NavigationDestination(icon: Icon(Icons.cloud_outlined), selectedIcon: Icon(Icons.cloud_rounded), label: '云端'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
        ],
      ),
    );
  }
}

/// Simple placeholder tab screen.
class _TabScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _TabScreen({required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: false),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 80, color: color.withAlpha(80)),
            const SizedBox(height: 24),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Enpix v0.1.0',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            const Text('端到端加密 · S3 备份 · 跨平台',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// First-run setup wizard placeholder.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security_rounded, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 32),
              Text('欢迎使用 Enpix', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text('端到端加密照片备份', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('开始使用'),
                style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
