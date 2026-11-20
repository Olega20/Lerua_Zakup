import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/core/storage/app_database.dart';
import 'package:lerua_zakup/features/backup/data/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const channel = MethodChannel('lerua_zakup/platform');

  test('backup creates a SQLite snapshot, exports JSON and restores only a valid database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lerua-backup-test-',
    );
    final dbPath = '${directory.path}${Platform.pathSeparator}lerua_zakup.db';
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    Uint8List? backupBytes;
    Uint8List? exportBytes;
    final written = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'writeBackupFile':
              final args = Map<Object?, Object?>.from(call.arguments as Map);
              written.add(args['fileName'] as String);
              final bytes = args['bytes'];
              if (args['fileName'].toString().endsWith('.db')) {
                backupBytes = Uint8List.fromList(bytes as Uint8List);
              } else {
                exportBytes = Uint8List.fromList(bytes as Uint8List);
              }
              return 'content://test/${args['fileName']}';
            case 'listBackupFiles':
              return <Map<String, Object?>>[];
            case 'chooseBackupFile':
              return 'content://test/restore.db';
            case 'readBackupFile':
              return backupBytes;
            case 'deleteBackupFile':
              return true;
            default:
              return null;
          }
        });
    try {
      final db = await database.database;
      await db.insert('app_settings', {
        'key': 'backup_folder_uri',
        'value': 'content://test/tree',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await db.insert('products', {
        'moysklad_id': 'product-1',
        'name': 'Тестовый товар',
        'kind': 'product',
        'stock': 3,
        'uom_name': 'шт',
        'relevance_status': 'relevant',
        'is_archived': 0,
        'is_present': 1,
      });
      final service = BackupService(database: database);
      expect(await service.journalRetentionDays(), 30);
      await service.setJournalRetentionDays(60);
      expect(await service.journalRetentionDays(), 60);
      final backupName = await service.createBackup();
      expect(backupName, endsWith('.db'));
      expect(backupBytes, isNotNull);
      expect(utf8.decode(backupBytes!.take(15).toList()), 'SQLite format 3');
      expect(await service.lastBackupAt(), isNotNull);

      await service.exportData(table: 'products', format: 'json');
      expect(written.any((name) => name.endsWith('.json')), isTrue);
      expect(exportBytes, isNotNull);
      expect(jsonDecode(utf8.decode(exportBytes!)) is List, isTrue);

      await db.update('products', {'name': 'Изменённое имя'});
      await service.restoreSelectedBackup();
      final restored = await (await database.database).query('products');
      expect(restored.single['name'], 'Тестовый товар');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await database.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
}
