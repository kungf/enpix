import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/storage_exception.dart';
import '../../../services/crypto/credential_service.dart';
import '../../../services/providers.dart';
import '../../../services/ttl/ttl_config.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final ValueNotifier<int>? reloadNotifier;
  const SettingsScreen({super.key, this.reloadNotifier});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _uploadEnabled = true;
  double _uploadDelayDays = 0;
  bool _uploadUnitHours = false;
  bool _wifiOnly = true;
  bool _ttlTimeEnabled = false;
  double _ttlTimeDays = 30;
  bool _ttlSizeEnabled = false;
  double _ttlSizeGb = 100;

  final _endpointCtrl = TextEditingController();
  final _bucketCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _accessKeyCtrl = TextEditingController();
  final _secretKeyCtrl = TextEditingController();

  late final CredentialService _credService;
  bool _hasPassphrase = false;
  bool _sessionActive = false;
  bool _hasS3Creds = false;

  @override
  void initState() {
    super.initState();
    _credService = ref.read(credentialServiceProvider);
    _loadState();
    widget.reloadNotifier?.addListener(_onReload);
  }

  void _onReload() => _loadState();

  @override
  void dispose() {
    widget.reloadNotifier?.removeListener(_onReload);
    _endpointCtrl.dispose(); _bucketCtrl.dispose(); _regionCtrl.dispose();
    _accessKeyCtrl.dispose(); _secretKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final hp = await _credService.hasPassphrase();
    final hc = await _credService.hasS3Credentials();
    final ep = await _credService.getS3Endpoint();
    final bk = await _credService.getS3Bucket();
    final rg = await _credService.getS3Region();
    if (ep != null) _endpointCtrl.text = ep;
    if (bk != null) _bucketCtrl.text = bk;
    if (rg != null) _regionCtrl.text = rg;

    // Load persisted TTL config.
    final ttl = ref.read(ttlEngineProvider);
    await ttl.ensureLoaded();
    final cfg = ttl.config;

    if (mounted) setState(() {
      _hasPassphrase = hp;
      _sessionActive = _credService.isSessionActive;
      _hasS3Creds = hc;
      _ttlTimeEnabled = cfg.timeEnabled;
      _ttlTimeDays = cfg.timeDays.toDouble();
      _ttlSizeEnabled = cfg.sizeEnabled;
      _ttlSizeGb = cfg.sizeGb.toDouble();
    });
  }

  Future<void> _saveTtlConfig() async {
    final cfg = TtlConfig(
      timeEnabled: _ttlTimeEnabled,
      timeDays: _ttlTimeDays.toInt(),
      sizeEnabled: _ttlSizeEnabled,
      sizeGb: _ttlSizeGb.toInt(),
    );
    await ref.read(ttlEngineProvider).updateConfig(cfg);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: false),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        _card(Icons.security_rounded, '安全', null, [
          ListTile(leading: const Icon(Icons.key_rounded), title: const Text('加密算法'), subtitle: const Text('XChaCha20-Poly1305 + Argon2id + BLAKE2b')),
          ListTile(leading: Icon(Icons.lock_rounded, color: _sessionActive ? Colors.green : Colors.grey), title: Text(_hasPassphrase ? '加密密钥' : '设置加密密码'), subtitle: Text(_sessionActive ? '已解锁' : (_hasPassphrase ? '已锁定' : '用于加密凭证和照片')),
            trailing: _hasPassphrase ? Row(mainAxisSize: MainAxisSize.min, children: [FilledButton.tonal(onPressed: () => _unlock(context), child: const Text('解锁')), const SizedBox(width: 8), IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18), onPressed: _resetPw, tooltip: '重置')]) : FilledButton.tonal(onPressed: () => _setupPw(context), child: const Text('设置密码'))),
          ListTile(leading: Icon(Icons.vpn_key_rounded, color: _hasS3Creds ? Colors.green : Colors.grey), title: const Text('S3 凭证'), subtitle: Text(_hasS3Creds ? '已加密存储' : '保存时自动用密码加密')),
        ]),
        _card(Icons.cloud_upload_rounded, '上传配置', '仅上传拍摄时间超过阈值的照片，0 为不限', [
          SwitchListTile(title: const Text('上传阈值'), subtitle: Text(_uploadEnabled ? (_uploadDelayDays == 0 ? '不限' : '仅上传 ${_uploadDelayDays.toInt()} ${_uploadUnitHours ? "小时" : "天"}前拍摄的照片') : '已禁用'), value: _uploadEnabled, onChanged: (v) => setState(() => _uploadEnabled = v)),
          if (_uploadEnabled) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
            Row(children: [Text('拍摄于 ${_uploadDelayDays.toInt()} ${_uploadUnitHours ? "小时" : "天"}前', style: t.textTheme.bodySmall), const Spacer(),
              ChoiceChip(label: const Text('小时'), selected: _uploadUnitHours, onSelected: (_) => setState(() { _uploadUnitHours = true; if (_uploadDelayDays > 72) _uploadDelayDays = 72; })),
              const SizedBox(width: 4), ChoiceChip(label: const Text('天'), selected: !_uploadUnitHours, onSelected: (_) => setState(() => _uploadUnitHours = false))]),
            Slider(value: _uploadDelayDays, min: 0, max: _uploadUnitHours ? 72 : 365, divisions: _uploadUnitHours ? 72 : 73, onChanged: (v) => setState(() => _uploadDelayDays = v))])),
          const Divider(),
          SwitchListTile(title: const Text('仅 WiFi 上传'), value: _wifiOnly, onChanged: (v) => setState(() => _wifiOnly = v)),
        ]),
        _card(Icons.auto_delete_rounded, '本地清理 (TTL)', '已上传到 S3 的本地文件，满足条件后自动删除', [
          SwitchListTile(title: const Text('按时间清理'), subtitle: Text(_ttlTimeEnabled ? '删除 ${_ttlTimeDays.toInt()} 天前且已上传的本地文件' : '已禁用'), value: _ttlTimeEnabled, onChanged: (v) { setState(() => _ttlTimeEnabled = v); _saveTtlConfig(); }),
          if (_ttlTimeEnabled) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Text('${_ttlTimeDays.toInt()} 天前', style: t.textTheme.bodySmall), Expanded(child: Slider(value: _ttlTimeDays, min: 1, max: 365, divisions: 50, onChanged: (v) => setState(() => _ttlTimeDays = v), onChangeEnd: (_) => _saveTtlConfig())), SizedBox(width: 50, child: Text('${_ttlTimeDays.toInt()}天', style: t.textTheme.bodySmall))])),
          const Divider(),
          SwitchListTile(title: const Text('按空间清理'), subtitle: Text(_ttlSizeEnabled ? '本地空间超过 ${_ttlSizeGb.toInt()} GB 时，清理旧文件（每次 1 GiB）' : '已禁用'), value: _ttlSizeEnabled, onChanged: (v) { setState(() => _ttlSizeEnabled = v); _saveTtlConfig(); }),
          if (_ttlSizeEnabled) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [const Text('上限: '), Expanded(child: Slider(value: _ttlSizeGb, min: 5, max: 500, divisions: 99, onChanged: (v) => setState(() => _ttlSizeGb = v), onChangeEnd: (_) => _saveTtlConfig())), SizedBox(width: 50, child: Text('${_ttlSizeGb.toInt()}GB', style: t.textTheme.bodySmall))])),
        ]),
        _card(Icons.cloud_outlined, 'S3 存储配置', null, [
          _tf('Endpoint URL', _endpointCtrl), const SizedBox(height: 12),
          _tf('Bucket', _bucketCtrl), const SizedBox(height: 12),
          _tf('Region', _regionCtrl), const SizedBox(height: 12),
          _tf('Access Key', _accessKeyCtrl, obscure: true), const SizedBox(height: 12),
          _tf('Secret Key', _secretKeyCtrl, obscure: true), const SizedBox(height: 16),
          Row(children: [
            OutlinedButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('测试连接...'))), icon: const Icon(Icons.wifi_find_rounded, size: 18), label: const Text('测试连接')),
            const Spacer(), FilledButton.icon(onPressed: _saveS3Config, icon: const Icon(Icons.save_rounded, size: 18), label: const Text('保存')),
          ]),
        ]),
        _card(Icons.info_outline_rounded, '关于', null, [
          if (_hasPassphrase) FutureBuilder<String?>(future: _credService.getKekFingerprint(), builder: (_, s) => _row('KEK 指纹', s.data?.substring(0, 12) ?? '—', mono: true)),
          _row('版本', '0.1.0'), _row('加密', 'XChaCha20-Poly1305'), _row('密钥派生', 'Argon2id (64 MiB)'), _row('哈希', 'BLAKE2b-256'),
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }

  void _setupPw(BuildContext ctx) {
    final passwordCtrl = TextEditingController(), confirmCtrl = TextEditingController();
    var strength = _Strength.none;
    var obscurePw = true;
    var obscureConfirm = true;
    String? errorText;
    showDialog(context: ctx, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, dialogSetState) {
      String? validate() {
        final pw = passwordCtrl.text;
        if (pw.isEmpty) return null;
        if (pw.length < 8) return '密码至少需要 8 位';
        if (pw != confirmCtrl.text && confirmCtrl.text.isNotEmpty) return '两次输入的密码不一致';
        return null;
      }

      return AlertDialog(title: const Text('设置加密密码'), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withAlpha(60)),
          ),
          child: const Row(children: [
            Icon(Icons.shield_rounded, size: 20, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('端到端加密', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange))),
          ]),
        ),
        const SizedBox(height: 12),
        const Text('你的照片会在上传前加密，服务器无法查看内容。此密码用于加密和解密你的照片及凭证。', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        const Text('⚠️ 请牢记此密码。忘记密码将无法解密照片，且无法恢复。', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.red)),
        const SizedBox(height: 16),
        TextField(controller: passwordCtrl, obscureText: obscurePw, decoration: InputDecoration(labelText: '密码', hintText: '建议大小写字母+数字+符号', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(obscurePw ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => dialogSetState(() => obscurePw = !obscurePw))), onChanged: (_) => dialogSetState(() { strength = _calc(passwordCtrl.text); errorText = validate(); })),
        _bar(strength), const SizedBox(height: 12),
        TextField(controller: confirmCtrl, obscureText: obscureConfirm, decoration: InputDecoration(labelText: '确认密码', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => dialogSetState(() => obscureConfirm = !obscureConfirm))), onChanged: (_) => dialogSetState(() => errorText = validate())),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ]), actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
        FilledButton(onPressed: () async {
          final pw = passwordCtrl.text;
          final err = validate();
          if (err != null) { dialogSetState(() => errorText = err); return; }
          if (pw.isEmpty) { dialogSetState(() => errorText = '请输入密码'); return; }
          Navigator.pop(dialogContext);
          final kek = await _credService.setupPassphrase(pw);
          _credService.startSession(kek);
          await _loadState();
          if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('密码已设置'), backgroundColor: Colors.green));
        }, child: const Text('设置')),
      ]);
    }));
  }

  void _unlock(BuildContext ctx) {
    final passwordCtrl = TextEditingController();
    var obscure = true;
    showDialog(context: ctx, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, dialogSetState) => AlertDialog(title: const Text('解锁密钥'), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('输入密码以解锁 KEK 会话'), const SizedBox(height: 16), TextField(controller: passwordCtrl, obscureText: obscure, decoration: InputDecoration(labelText: '密码', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => dialogSetState(() => obscure = !obscure))))]), actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
      FilledButton(onPressed: () async { try { await _credService.unlockWithPassphrase(passwordCtrl.text); if (!mounted) return; Navigator.pop(dialogContext); await _loadState(); if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已解锁'), backgroundColor: Colors.green)); } on WrongPassphraseException { if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('密码错误'))); } catch (_) { if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('解锁失败，请重试'))); } }, child: const Text('解锁')),
    ])));
  }

  Future<void> _resetPw() async {
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('重置？'), content: const Text('删除所有加密数据，不可撤销。'), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('重置'))]));
    if (ok == true) { await _credService.resetAll(); await _loadState(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已重置'))); }
  }

  Future<void> _saveS3Config() async {
    final endpoint = _endpointCtrl.text.trim();
    final bucket = _bucketCtrl.text.trim();
    final region = _regionCtrl.text.trim();

    if (endpoint.isEmpty || bucket.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Endpoint URL 和 Bucket 不能为空')));
      return;
    }

    // Always save endpoint/bucket/region (not secret).
    await _credService.saveS3Endpoint(endpoint);
    await _credService.saveS3Bucket(bucket);
    await _credService.saveS3Region(region.isNotEmpty ? region : 'us-east-1');

    if (_hasPassphrase && !_credService.isSessionActive) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先解锁密钥')));
      return;
    }
    if (_hasPassphrase && _credService.isSessionActive) {
      final ak = _accessKeyCtrl.text.trim();
      final sk = _secretKeyCtrl.text.trim();
      if (ak.isEmpty || sk.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access Key 和 Secret Key 不能为空')));
        return;
      }
      try {
        await _credService.saveS3Credentials(ak, sk);
        await _loadState();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('S3 凭证已加密保存'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red));
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('建议先设置密码再保存凭证')));
    }
  }
}

// ── Top-level helpers ──

Widget _card(IconData icon, String title, String? subtitle, List<Widget> children) {
  return Builder(builder: (context) => Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20), const SizedBox(width: 8), Text(title, style: Theme.of(context).textTheme.titleMedium)]),
    if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))],
    const SizedBox(height: 12), ...children,
  ]))));
}

Widget _tf(String label, TextEditingController ctrl, {bool obscure = false}) {
  return TextField(controller: ctrl, obscureText: obscure, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()));
}

Widget _row(String label, String value, {bool mono = false}) {
  return Builder(builder: (context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
    SizedBox(width: 80, child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
    Expanded(child: Text(value, style: mono ? Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 12) : Theme.of(context).textTheme.bodyMedium)),
  ])));
}

enum _Strength { none, weak, fair, good, strong }

_Strength _calc(String pw) {
  if (pw.isEmpty) return _Strength.none;
  if (pw.length < 6) return _Strength.weak;
  final n = (pw.contains(RegExp(r'[A-Z]')) ? 1 : 0) + (pw.contains(RegExp(r'[a-z]')) ? 1 : 0) + (pw.contains(RegExp(r'[0-9]')) ? 1 : 0) + (pw.contains(RegExp(r'[^A-Za-z0-9]')) ? 1 : 0);
  if (pw.length >= 12 && n >= 4) return _Strength.strong;
  if (pw.length >= 10 && n >= 3) return _Strength.good;
  if (pw.length >= 8 && n >= 2) return _Strength.fair;
  return _Strength.weak;
}

Widget _bar(_Strength s) {
  final (l, c, w) = switch (s) { _Strength.none => ('', Colors.transparent, 0.0), _Strength.weak => ('弱', Colors.red, 0.25), _Strength.fair => ('一般', Colors.orange, 0.5), _Strength.good => ('好', Colors.lightGreen, 0.75), _Strength.strong => ('强', Colors.green, 1.0) };
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const SizedBox(height: 6), ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: w, minHeight: 4, backgroundColor: Colors.grey.shade200, color: c)), if (l.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(l, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w500)))]);
}
