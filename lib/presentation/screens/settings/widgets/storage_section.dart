import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/core/errors/storage_exception.dart';
import 'package:enpix/domain/entities/storage_config.dart';
import 'package:enpix/services/providers.dart';
import 'package:enpix/presentation/shared/widgets/enpix_section.dart';
import 'package:enpix/presentation/shared/widgets/enpix_progress.dart';

/// S3 storage configuration — endpoint, bucket, credentials, connection test.
class StorageSection extends ConsumerStatefulWidget {
  const StorageSection({super.key});
  @override
  ConsumerState<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<StorageSection> {
  final _epCtrl = TextEditingController();
  final _bkCtrl = TextEditingController();
  final _rgCtrl = TextEditingController();
  final _akCtrl = TextEditingController();
  final _skCtrl = TextEditingController();
  bool? _testResult;
  bool _testing = false;
  bool _obscureSk = true;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  @override
  void dispose() { _epCtrl.dispose(); _bkCtrl.dispose(); _rgCtrl.dispose(); _akCtrl.dispose(); _skCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final cred = ref.read(credentialServiceProvider);
    final ep = await cred.getS3Endpoint();
    final bk = await cred.getS3Bucket();
    final rg = await cred.getS3Region();
    if (mounted) setState(() {
      if (ep != null) _epCtrl.text = ep;
      if (bk != null) _bkCtrl.text = bk;
      if (rg != null) _rgCtrl.text = rg;
    });
  }

  Future<void> _test() async {
    final ep = _epCtrl.text.trim();
    final bk = _bkCtrl.text.trim();
    if (ep.isEmpty || bk.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写 Endpoint 和 Bucket')));
      return;
    }
    setState(() { _testing = true; _testResult = null; });
    try {
      ref.read(s3ServiceProvider).configure(StorageConfig(
        endpointUrl: ep, bucketName: bk, region: _rgCtrl.text.trim().isNotEmpty ? _rgCtrl.text.trim() : 'default',
        accessKey: _akCtrl.text.trim(), secretKey: _skCtrl.text.trim(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      final msg = await ref.read(s3ServiceProvider).testConnection();
      if (mounted) {
        setState(() { _testResult = true; _testing = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: context.colors.brandGreen));
      }
    } catch (e) {
      if (mounted) {
        setState(() { _testResult = false; _testing = false; });
        final msg = e is StorageException ? e.message : '连接失败: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: context.colors.brandRed));
      }
    }
  }

  Future<void> _save() async {
    final cred = ref.read(credentialServiceProvider);
    final ep = _epCtrl.text.trim();
    final bk = _bkCtrl.text.trim();
    final rg = _rgCtrl.text.trim();
    if (ep.isEmpty || bk.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Endpoint URL 和 Bucket 不能为空')));
      return;
    }
    await cred.saveS3Endpoint(ep);
    await cred.saveS3Bucket(bk);
    await cred.saveS3Region(rg.isNotEmpty ? rg : 'default');
    final ak = _akCtrl.text.trim();
    final sk = _skCtrl.text.trim();
    if (ak.isEmpty || sk.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access Key 和 Secret Key 不能为空')));
      return;
    }
    try {
      await cred.saveS3Credentials(ak, sk);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('S3 凭证已保存'), backgroundColor: context.colors.brandGreen));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('保存失败: $e'), backgroundColor: context.colors.brandRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    return EnpixSection(
      header: 'S3 存储配置',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(children: [
            TextField(controller: _epCtrl, decoration: const InputDecoration(labelText: 'Endpoint URL')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _bkCtrl, decoration: const InputDecoration(labelText: 'Bucket')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _rgCtrl, decoration: const InputDecoration(labelText: 'Region')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _akCtrl, decoration: const InputDecoration(labelText: 'Access Key')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _skCtrl, obscureText: _obscureSk,
              decoration: InputDecoration(labelText: 'Secret Key',
                suffixIcon: IconButton(
                  icon: Icon(_obscureSk ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscureSk = !_obscureSk)))),
            const SizedBox(height: AppSpacing.lg),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const EnpixCircularProgress(size: 18)
                    : Icon(_testResult == true ? Icons.check_circle_rounded : _testResult == false ? Icons.error_rounded : Icons.wifi_find_rounded,
                        size: 18, color: _testResult == true ? context.colors.brandGreen : _testResult == false ? context.colors.brandRed : null),
                label: Text(_testResult == true ? '连接成功' : _testResult == false ? '连接失败' : '测试连接'),
              ),
              const Spacer(),
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded, size: 18), label: const Text('保存')),
            ]),
          ]),
        ),
      ],
    );
  }
}
