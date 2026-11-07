import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/rate_history.dart';
import '../../sync/snapshot.dart';
import '../finance/finance_providers.dart';
import 'backup_download.dart'
    if (dart.library.js_interop) 'backup_download_web.dart';

/// Резервна копія у файл (етап 10): усі дані в одному JSON — тому самому
/// форматі, що й синхронізація з Google Drive.

/// Робота з файлами телефона. У тестах підміняється.
abstract class BackupFiles {
  /// Системне вікно «Зберегти як». false — користувач скасував.
  Future<bool> save(String fileName, Uint8List bytes);

  /// Поділитися файлом (Telegram, пошта, Google Drive…).
  Future<void> share(String fileName, Uint8List bytes);

  /// Вибрати файл. null — скасовано.
  Future<Uint8List?> pick();
}

class DeviceBackupFiles implements BackupFiles {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    if (kIsWeb) {
      // Браузер (етап 21): звичайне скачування у «Завантаження».
      await downloadFile(fileName, bytes, 'application/json');
      return true;
    }
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
      dialogTitle: 'Зберегти копію MyManager',
    );
    return uri != null;
  }

  @override
  Future<void> share(String fileName, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Резервна копія MyManager',
      ),
    );
  }

  @override
  Future<Uint8List?> pick() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Файл копії MyManager');
    return file?.readAsBytes();
  }
}

final backupFilesProvider = Provider<BackupFiles>((ref) => DeviceBackupFiles());

/// «Надіслати копію» (в інший додаток) є лише на телефоні.
final backupCanShareProvider = Provider<bool>((ref) => !kIsWeb);

String backupFileName(DateTime now) => '${isoDay(now)}-mymanager-backup.json';

/// Скільки «живих» записів у копії — для підтвердження перед відновленням.
({int entries, int wallets, int assets, int belongings}) backupSummary(FinanceSnapshot s) => (
  entries: s.transactions.where((t) => !t.deleted).length,
  wallets: s.wallets.where((w) => !w.deleted).length,
  assets: s.assets.where((a) => !a.deleted).length,
  belongings: s.belongings.where((b) => !b.deleted).length,
);

class BackupCard extends ConsumerStatefulWidget {
  const BackupCard({super.key});

  @override
  ConsumerState<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<BackupCard> {
  bool _busy = false;

  Future<Uint8List> _export() async {
    final snap = await ref.read(databaseProvider).exportSnapshot();
    return Uint8List.fromList(utf8.encode(snap.encode()));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _snack(e is FormatException ? e.message : 'Не вдалося: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() => _run(() async {
        final ok = await ref.read(backupFilesProvider).save(backupFileName(DateTime.now()), await _export());
        if (ok) _snack('Копію збережено');
      });

  Future<void> _share() => _run(() async {
        await ref.read(backupFilesProvider).share(backupFileName(DateTime.now()), await _export());
      });

  Future<void> _restore() => _run(() async {
        final bytes = await ref.read(backupFilesProvider).pick();
        if (bytes == null) return;
        final String text;
        try {
          text = utf8.decode(bytes);
        } on FormatException {
          throw const FormatException('Це не файл MyManager');
        }
        final snap = FinanceSnapshot.decode(text);
        final s = backupSummary(snap);
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Відновити з копії?'),
            content: Text(
              'У файлі: записів — ${s.entries}, гаманців — ${s.wallets}, '
              'активів — ${s.assets}, речей — ${s.belongings}.\n\n'
              'Дані з копії додадуться до наявних. Якщо запис є і там, і тут, '
              'лишиться новіша версія. Нічого не видаляється.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Скасувати')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Відновити')),
            ],
          ),
        );
        if (ok != true) return;
        final result = await ref.read(databaseProvider).mergeSnapshot(snap);
        _snack(result.total == 0 ? 'Усе з копії вже є в додатку' : 'Відновлено: оновлено ${result.total} рядків');
      });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.save_alt_outlined),
            title: const Text('Зберегти копію у файл'),
            subtitle: Text(
              kIsWeb
                  ? 'У «Завантаження» браузера'
                  : 'Наприклад, у «Завантаження» на телефоні',
            ),
            enabled: !_busy,
            onTap: _save,
          ),
          if (ref.watch(backupCanShareProvider)) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Надіслати копію'),
              subtitle: const Text('У Telegram, на пошту чи в інший додаток'),
              enabled: !_busy,
              onTap: _share,
            ),
          ],
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Відновити з файлу'),
            subtitle: const Text('Додає дані з копії до наявних'),
            enabled: !_busy,
            onTap: _restore,
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
