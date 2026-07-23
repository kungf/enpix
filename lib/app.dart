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
import 'presentation/screens/settings/dialogs/setup_password_dialog.dart';
import 'domain/entities/storage_config.dart';
import 'services/providers.dart';

/// Root widget of the Enpix app.
///
/// Design decisions:
/// - iOS 18-style light theme
/// - 4-tab navigation: Local / Cloud / Overview / Settings
/// - IndexedStack preserves tab state across switches
class EnpixApp extends StatelessWidget {
  final bool isFirstRun;

  const EnpixApp({super.key, this.isFirstRun = false});

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
      if (_supportsPhotos) const LocalGalleryScreen(),
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

/// First-run setup wizard: welcome -> S3 configuration -> encryption
/// password -> done. Each step is self-contained; the user can test the S3
/// connection before proceeding and must set a passphrase to finish.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  int _step = 0;
  final _endpoint = TextEditingController();
  final _bucket = TextEditingController();
  final _region = TextEditingController(text: 'us-east-1');
  final _ak = TextEditingController();
  final _sk = TextEditingController();
  bool _s3Saved = false;
  bool _passwordSet = false;
  bool _testing = false;
  String? _statusMsg;
  bool _statusError = false;

  @override
  void dispose() {
    _endpoint.dispose();
    _bucket.dispose();
    _region.dispose();
    _ak.dispose();
    _sk.dispose();
    super.dispose();
  }

  Future<void> _testAndSaveS3() async {
    if (_endpoint.text.trim().isEmpty ||
        _bucket.text.trim().isEmpty ||
        _ak.text.trim().isEmpty ||
        _sk.text.trim().isEmpty) {
      setState(() {
        _statusMsg = '请填写 Endpoint、Bucket、Access Key 和 Secret Key';
        _statusError = true;
      });
      return;
    }
    setState(() {
      _testing = true;
      _statusMsg = null;
      _statusError = false;
    });
    try {
      final cred = ref.read(credentialServiceProvider);
      final s3 = ref.read(s3ServiceProvider);
      await cred.saveS3Endpoint(_endpoint.text.trim());
      await cred.saveS3Bucket(_bucket.text.trim());
      await cred.saveS3Region(_region.text.trim());
      await cred.saveS3Credentials(_ak.text.trim(), _sk.text.trim());
      s3.configure(
        StorageConfig(
          endpointUrl: _endpoint.text.trim(),
          bucketName: _bucket.text.trim(),
          region: _region.text.trim().isEmpty ? 'default' : _region.text.trim(),
          accessKey: _ak.text.trim(),
          secretKey: _sk.text.trim(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        kekFingerprint: await cred.getPathPrefix(),
      );
      final msg = await s3.testConnection();
      setState(() {
        _testing = false;
        _statusMsg = msg;
        _statusError = false;
        _s3Saved = true;
      });
    } catch (e) {
      setState(() {
        _testing = false;
        _statusMsg = '连接失败: $e';
        _statusError = true;
      });
    }
  }

  Future<void> _setPassword() async {
    final pw = await showSetupPasswordDialog(context);
    if (pw == null || pw.isEmpty) return;
    try {
      final cred = ref.read(credentialServiceProvider);
      // setupPassphrase now activates the full session (KEK + Master Key)
      // and persists the passphrase for auto-unlock itself.
      await cred.setupPassphrase(pw);
      ref.read(sessionTickProvider.notifier).state++;
      setState(() => _passwordSet = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMsg = '设置密码失败: $e';
          _statusError = true;
        });
      }
    }
  }

  void _finish() => Navigator.of(context).pushReplacementNamed('/');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.backgroundPrimary,
      appBar: AppBar(
        title: Text(
          _step == 0
              ? '欢迎使用 Enpix'
              : _step == 1
                  ? '配置 S3 存储'
                  : '设置加密密码',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildWelcome();
      case 1:
        return _buildS3();
      default:
        return _buildPassword();
    }
  }

  Widget _buildWelcome() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.security_rounded, size: 80, color: context.colors.brandBlue),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          '欢迎使用 Enpix',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '端到端加密照片备份。开始前需要配置 S3 存储并设置加密密码。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.colors.labelSecondary,
              ),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        FilledButton(
          onPressed: () => setState(() => _step = 1),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('开始设置'),
        ),
      ],
    );
  }

  Widget _buildS3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '填写 S3 / MinIO 连接信息',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.colors.labelPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _field(_endpoint, 'Endpoint URL', 'https://s3.example.com'),
        _field(_bucket, 'Bucket', 'my-bucket'),
        _field(_region, 'Region', 'us-east-1'),
        _field(_ak, 'Access Key', 'AKIA...'),
        _field(_sk, 'Secret Key', '********', obscure: true),
        if (_statusMsg != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _statusMsg!,
            style: TextStyle(
              fontSize: 13,
              color: _statusError
                  ? context.colors.brandRed
                  : context.colors.brandGreen,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton(
          onPressed: _testing ? null : _testAndSaveS3,
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: _testing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('测试连接并保存'),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(
          onPressed: _s3Saved ? () => setState(() => _step = 2) : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('下一步'),
        ),
      ],
    );
  }

  Widget _buildPassword() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_rounded, size: 72, color: context.colors.brandPurple),
        const SizedBox(height: AppSpacing.xl),
        Text(
          _passwordSet ? '加密密码已设置' : '设置加密密码',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.colors.labelPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '加密密码用于保护云端照片。忘记时可用恢复密钥找回。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: context.colors.labelSecondary),
        ),
        const SizedBox(height: AppSpacing.xxxl),
        if (!_passwordSet)
          FilledButton(
            onPressed: _setPassword,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('设置加密密码'),
          )
        else
          FilledButton(
            onPressed: _finish,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('完成，进入应用'),
          ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
