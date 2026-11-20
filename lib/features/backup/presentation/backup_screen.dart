import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../../connectivity/data/api_task_dispatcher.dart';
import '../../connectivity/domain/api_task.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.service, required this.api});
  final BackupService service;
  final ApiTaskDispatcher api;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? folder;
  DateTime? last;
  int count = 0;
  int retentionDays = 30;
  bool busy = false;
  String table = 'products', format = 'json';
  DateTime? from, to;

  Future<void> pickDate(bool start) async {
    final value = await showDatePicker(
      context: context,
      initialDate: (start ? from : to) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      setState(() {
        if (start) {
          from = value;
        } else {
          to = value;
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final f = await widget.service.folderUri(),
          l = await widget.service.lastBackupAt(),
          b = await widget.service.backups(),
          retention = await widget.service.journalRetentionDays();
      if (mounted) {
        setState(() {
          folder = f;
          last = l;
          count = b.length;
          retentionDays = retention;
        });
      }
    } catch (_) {
      if (mounted) {
        message('Не удалось прочитать настройки резервного копирования');
      }
    }
  }

  void message(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> run(Future<void> Function() action, String success) async {
    setState(() => busy = true);
    try {
      await action();
      await load();
      message(success);
    } catch (_) {
      message(
        'Операция не выполнена. Проверьте доступ к папке и свободное место.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Восстановить резервную копию?'),
        content: const Text(
          'Текущая база данных будет заменена выбранной копией. Перед заменой файл проверяется на целостность.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Восстановить'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await run(() async {
      final running = await widget.api.listTasks(
        statuses: {ApiTaskStatus.running},
      );
      if (running.isNotEmpty) throw StateError('Есть выполняющийся API-запрос');
      await widget.api.suspendForDatabaseMaintenance();
      try {
        await widget.service.restoreSelectedBackup();
      } finally {
        await widget.api.resumeAfterDatabaseMaintenance();
      }
    }, 'База восстановлена. Перезапустите приложение.');
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Резервные копии и экспорт'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(
            folder == null
                ? 'Папка не выбрана'
                : 'Папка резервного копирования выбрана',
          ),
          subtitle: Text('Успешных копий: $count'),
          trailing: TextButton(
            onPressed: busy
                ? null
                : () => run(widget.service.chooseFolder, 'Папка сохранена'),
            child: const Text('Выбрать'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Последняя успешная копия'),
          subtitle: Text(last?.toLocal().toString() ?? 'Ещё не создавалась'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: busy || folder == null
              ? null
              : () => run(() async {
                  await widget.service.createBackup();
                }, 'Резервная копия создана'),
          icon: const Icon(Icons.backup),
          label: const Text('Создать резервную копию'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : restore,
          icon: const Icon(Icons.settings_backup_restore),
          label: const Text('Восстановить из файла'),
        ),
        const Divider(height: 32),
        const Divider(height: 32),
        Text(
          'Хранение Журнала операций',
          style: Theme.of(c).textTheme.titleLarge,
        ),
        DropdownButtonFormField<int>(
          initialValue: retentionDays,
          decoration: const InputDecoration(labelText: 'Срок хранения'),
          items: const [
            DropdownMenuItem(value: 7, child: Text('7 дней')),
            DropdownMenuItem(value: 30, child: Text('1 месяц')),
            DropdownMenuItem(value: 60, child: Text('2 месяца')),
            DropdownMenuItem(value: 90, child: Text('3 месяца')),
            DropdownMenuItem(value: 180, child: Text('6 месяцев')),
            DropdownMenuItem(value: 365, child: Text('1 год')),
          ],
          onChanged: busy
              ? null
              : (value) async {
                  if (value == null) return;
                  await widget.service.setJournalRetentionDays(value);
                  if (mounted) setState(() => retentionDays = value);
                },
        ),
        const Divider(height: 32),
        Text('Экспорт данных', style: Theme.of(c).textTheme.titleLarge),
        DropdownButtonFormField<String>(
          initialValue: table,
          decoration: const InputDecoration(labelText: 'Раздел'),
          items: const [
            DropdownMenuItem(value: 'products', child: Text('Товары')),
            DropdownMenuItem(value: 'warehouses', child: Text('Склады')),
            DropdownMenuItem(
              value: 'organizations',
              child: Text('Организации'),
            ),
            DropdownMenuItem(value: 'suppliers', child: Text('Поставщики')),
            DropdownMenuItem(
              value: 'payment_methods',
              child: Text('Способы оплаты'),
            ),
            DropdownMenuItem(
              value: 'warehouse_journal_entries',
              child: Text('Журнал операций'),
            ),
            DropdownMenuItem(value: 'api_tasks', child: Text('Задачи API')),
            DropdownMenuItem(
              value: 'warehouse_log',
              child: Text('Диагностический журнал'),
            ),
          ],
          onChanged: (v) => setState(() => table = v ?? 'products'),
        ),
        ListTile(
          title: const Text('Начало периода'),
          subtitle: Text(
            from?.toLocal().toString().split(' ').first ?? 'Без ограничения',
          ),
          trailing: IconButton(
            onPressed: busy ? null : () => pickDate(true),
            icon: const Icon(Icons.calendar_today),
          ),
        ),
        ListTile(
          title: const Text('Конец периода'),
          subtitle: Text(
            to?.toLocal().toString().split(' ').first ?? 'Без ограничения',
          ),
          trailing: IconButton(
            onPressed: busy ? null : () => pickDate(false),
            icon: const Icon(Icons.calendar_today),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'json', label: Text('JSON')),
            ButtonSegment(value: 'csv', label: Text('CSV')),
          ],
          selected: {format},
          onSelectionChanged: (v) => setState(() => format = v.first),
        ),
        FilledButton(
          onPressed: busy || folder == null
              ? null
              : () => run(
                  () => widget.service.exportData(
                    table: table,
                    format: format,
                    from: from,
                    to: to,
                  ),
                  'Экспорт сохранён в выбранной папке',
                ),
          child: const Text('Экспортировать'),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );
}
