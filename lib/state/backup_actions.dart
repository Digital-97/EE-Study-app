import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'progress_store.dart';

/// User-facing flows for saving, sharing and restoring a progress backup.
class BackupActions {
  BackupActions(this.context, this.store);

  final BuildContext context;
  final ProgressStore store;

  String get _fileName {
    final d = store.now;
    String two(int n) => n.toString().padLeft(2, '0');
    return 'ee-study-backup-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }

  Uint8List get _bytes => Uint8List.fromList(utf8.encode(store.exportBackup()));

  /// Lets the user pick where to save the backup file.
  Future<void> saveToFile() async {
    try {
      final uri = await FilePicker.saveFile(
        fileName: _fileName,
        bytes: _bytes,
        mimeType: 'application/json',
        dialogTitle: 'Save EE Study backup',
      );
      if (uri != null) _toast('Backup saved.');
    } catch (e) {
      _toast('Could not save the backup: $e');
    }
  }

  /// Opens the share sheet, e.g. to send the backup to Drive, mail or chat.
  Future<void> share() async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(_bytes, mimeType: 'application/json', name: _fileName)],
        fileNameOverrides: [_fileName],
        subject: 'EE Study backup',
      ));
    } catch (e) {
      _toast('Could not share the backup: $e');
    }
  }

  /// Picks a backup file and, after confirmation, replaces all progress.
  Future<void> restore() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(dialogTitle: 'Choose an EE Study backup');
    } catch (e) {
      _toast('Could not open the file picker: $e');
      return;
    }
    if (file == null || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text('Your current progress will be replaced by the progress in "${file!.name}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await store.importBackup(await file.xFile.readAsString());
      _toast('Progress restored.');
    } on BackupException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Could not read the file: $e');
    }
  }

  void _toast(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
