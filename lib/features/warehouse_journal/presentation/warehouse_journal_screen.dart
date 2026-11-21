import 'package:flutter/material.dart';

import '../data/warehouse_journal_repository.dart';

class WarehouseJournalScreen extends StatefulWidget {
  const WarehouseJournalScreen({super.key, required this.repository});
  final WarehouseJournalRepository repository;
  @override
  State<WarehouseJournalScreen> createState() => _WarehouseJournalScreenState();
}

class _WarehouseJournalScreenState extends State<WarehouseJournalScreen> {
  List<Map<String, Object?>> rows = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.repository.latestEntries();
      if (mounted) {
        setState(() {
          rows = r;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> details(Map<String, Object?> row) async {
    final events = await widget.repository.events(row['id'] as int);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(row['summary'] as String),
        content: SizedBox(
          width: 400,
          child: ListView(
            shrinkWrap: true,
            children: events
                .map(
                  (e) => ListTile(
                    title: Text(e['message'] as String),
                    subtitle: Text(
                      '${e['event_type']} • ${DateTime.fromMillisecondsSinceEpoch(e['created_at'] as int).toLocal()}',
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Журнал операций'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : rows.isEmpty
        ? const Center(child: Text('Операций пока нет'))
        : ListView(
            children: rows
                .map(
                  (r) => ListTile(
                    title: Text(r['summary'] as String),
                    subtitle: Text('${r['entry_type']} • ${r['state']}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => details(r),
                  ),
                )
                .toList(),
          ),
  );
}
