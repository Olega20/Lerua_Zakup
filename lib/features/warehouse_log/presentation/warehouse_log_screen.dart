import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../data/warehouse_log_repository.dart';
import '../domain/warehouse_log_entry.dart';

class WarehouseLogScreen extends StatefulWidget {
  const WarehouseLogScreen({super.key, required this.repository});

  final WarehouseLogRepository repository;

  @override
  State<WarehouseLogScreen> createState() => _WarehouseLogScreenState();
}

class _WarehouseLogScreenState extends State<WarehouseLogScreen> {
  List<WarehouseLogEntry> _entries = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final entries = await widget.repository.latest();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Очистить журнал?'),
        content: const Text('Все диагностические записи будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.clear();
      if (!mounted) return;
      setState(() => _entries = const []);
    } catch (_) {
      if (!mounted) return;
      _message('Не удалось очистить журнал');
    }
  }

  Future<void> _showDetails(WarehouseLogEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(warehouseLogEventLabel(entry.type)),
        content: SingleChildScrollView(
          child: SelectableText(entry.toSafeText()),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: entry.toSafeText()));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              _message('Диагностика скопирована');
            },
            child: const Text('Копировать'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  String _formatTime(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}  '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Color _levelColor(BuildContext context, WarehouseLogLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      WarehouseLogLevel.info => scheme.primary,
      WarehouseLogLevel.warning => Colors.amber.shade800,
      WarehouseLogLevel.error => scheme.error,
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Журнал склада'),
      actions: [
        IconButton(
          tooltip: 'Обновить',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Очистить журнал',
          onPressed: _entries.isEmpty || _loading ? null : _clear,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _failed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Не удалось загрузить журнал'),
                const SizedBox(height: 8),
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          )
        : _entries.isEmpty
        ? const Center(child: Text('Журнал пока пуст'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return ListTile(
                  leading: Icon(switch (entry.level) {
                    WarehouseLogLevel.info => Icons.info_outline,
                    WarehouseLogLevel.warning => Icons.warning_amber,
                    WarehouseLogLevel.error => Icons.error_outline,
                  }, color: _levelColor(context, entry.level)),
                  title: Text(warehouseLogEventLabel(entry.type)),
                  subtitle: Text(
                    '${_formatTime(entry.timestamp)}\n${entry.description}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  onTap: () => _showDetails(entry),
                );
              },
            ),
          ),
  );
}
