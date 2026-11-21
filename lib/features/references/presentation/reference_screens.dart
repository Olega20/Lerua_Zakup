import 'dart:convert';

import 'package:flutter/material.dart';

import '../../connectivity/data/api_task_dispatcher.dart';
import '../../connectivity/domain/api_task.dart';
import '../../warehouse_journal/data/warehouse_journal_repository.dart';
import '../../warehouse_journal/presentation/warehouse_journal_screen.dart';
import '../../warehouse_log/data/warehouse_log_repository.dart';
import '../../warehouse_log/presentation/warehouse_log_screen.dart';
import '../../backup/data/backup_service.dart';
import '../../backup/presentation/backup_screen.dart';
import '../data/reference_data_repository.dart';

class OtherActionsScreen extends StatelessWidget {
  const OtherActionsScreen({
    super.key,
    required this.repository,
    required this.api,
    required this.journal,
    required this.backupService,
    required this.warehouseLogRepository,
    this.onResumeConfirmed,
  });
  final ReferenceDataRepository repository;
  final ApiTaskDispatcher api;
  final WarehouseJournalRepository journal;
  final BackupService backupService;
  final WarehouseLogRepository warehouseLogRepository;
  final Future<void> Function()? onResumeConfirmed;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Прочие действия')),
    body: ListView(
      children: [
        _entry(
          c,
          Icons.inventory_2_outlined,
          'Актуальные товары МойСклад',
          ProductCatalogScreen(repository: repository),
        ),
        _entry(
          c,
          Icons.warehouse_outlined,
          'Склады и места хранения',
          WarehousesScreen(repository: repository),
        ),
        _entry(
          c,
          Icons.business_outlined,
          'Организации и способы оплаты',
          OrganizationsScreen(repository: repository),
        ),
        _entry(
          c,
          Icons.local_shipping_outlined,
          'Поставщики',
          SuppliersScreen(repository: repository),
        ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Резервные копии и экспорт'),
          subtitle: const Text(
            'Автоматические и ручные копии, восстановление, CSV/JSON',
          ),
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute<void>(
              builder: (_) => BackupScreen(service: backupService, api: api),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.article_outlined),
          title: const Text('Журнал склада'),
          subtitle: const Text('Диагностика API, синхронизации и ошибок'),
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute<void>(
              builder: (_) => WarehouseLogScreen(repository: warehouseLogRepository),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Журнал операций'),
          subtitle: const Text(
            'История локально сохранённых операций и событий',
          ),
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute<void>(
              builder: (_) => WarehouseJournalScreen(repository: journal),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.sync_alt),
          title: const Text('Менеджер API'),
          subtitle: const Text('Очереди и состояние задач'),
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute<void>(
              builder: (_) => ApiTasksScreen(
                api: api,
                onResumeConfirmed: onResumeConfirmed,
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _entry(BuildContext c, IconData icon, String title, Widget page) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.push(c, MaterialPageRoute<void>(builder: (_) => page)),
      );
}

class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({
    super.key,
    required this.repository,
    this.archived = false,
  });
  final ReferenceDataRepository repository;
  final bool archived;
  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  List<Map<String, Object?>> rows = [];
  Map<String, int> counts = {};
  final Set<int> selected = {};
  String search = '';
  String? filter;
  bool loading = true;
  DateTime? last;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.repository.products(
        search: search,
        status: filter,
        archived: widget.archived,
      );
      final c = await widget.repository.productCounts();
      final l = await widget.repository.lastProductSync();
      if (mounted) {
        setState(() {
          rows = r;
          counts = c;
          last = l;
          loading = false;
        });
        final restored = await widget.repository
            .consumeUnarchivedProductCount();
        if (restored > 0 && mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Товары разархивированы'),
              content: Text(
                '$restored товар(ов) вернулись из архива. Их статус сброшен в «Нераспределённые» — проверьте актуальность.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Понятно'),
                ),
              ],
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> sync() async {
    setState(() => loading = true);
    try {
      await widget.repository.syncProducts();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Полное обновление не удалось. Локальные данные сохранены.',
            ),
          ),
        );
      }
    }
    await load();
  }

  String label(String s) => switch (s) {
    'relevant' => 'Актуальные',
    'irrelevant' => 'Не актуальные',
    _ => 'Нераспределённые',
  };
  Future<void> change(List<int> ids, String status) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Изменить статус?'),
        content: Text(
          'Будет изменено товаров: ${ids.length}. Новый статус: ${label(status)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.repository.setProductStatus(ids, status);
    selected.clear();
    await load();
  }

  Widget section(String status) {
    final items = rows.where((r) => r['relevance_status'] == status).toList();
    return ExpansionTile(
      title: Text(label(status)),
      trailing: Text('${counts[status] ?? 0}'),
      initiallyExpanded: status == 'unassigned',
      children: items.map((r) {
        final id = r['id'] as int;
        return ListTile(
          leading: selected.isEmpty
              ? null
              : Checkbox(
                  value: selected.contains(id),
                  onChanged: (v) => setState(
                    () => v == true ? selected.add(id) : selected.remove(id),
                  ),
                ),
          title: Text(r['name'] as String),
          subtitle: Text('Остаток: ${r['stock']} ${r['uom_name']}'),
          onLongPress: () => setState(() => selected.add(id)),
          onTap: () {
            if (selected.isNotEmpty) {
              setState(
                () => selected.contains(id)
                    ? selected.remove(id)
                    : selected.add(id),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ProductReviewScreen(
                    repository: widget.repository,
                    items: rows,
                    index: rows.indexOf(r),
                  ),
                ),
              );
            }
          },
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.archived ? 'Архив товаров' : 'Актуальные товары'),
      actions: [
        if (!widget.archived)
          IconButton(
            tooltip: 'Архив',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => Navigator.push(
              c,
              MaterialPageRoute<void>(
                builder: (_) => ProductCatalogScreen(
                  repository: widget.repository,
                  archived: true,
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: 'Обновить',
          onPressed: loading ? null : sync,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (last != null && !widget.archived)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Последнее обновление: ${last!.toLocal()}'),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Поиск по названию',
                  ),
                  onChanged: (v) {
                    search = v;
                    load();
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: filter,
                hint: const Text('Все'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Все')),
                  DropdownMenuItem(
                    value: 'unassigned',
                    child: Text('Нераспределённые'),
                  ),
                  DropdownMenuItem(
                    value: 'relevant',
                    child: Text('Актуальные'),
                  ),
                  DropdownMenuItem(
                    value: 'irrelevant',
                    child: Text('Не актуальные'),
                  ),
                ],
                onChanged: (v) {
                  setState(() => filter = v);
                  load();
                },
              ),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        Expanded(
          child: rows.isEmpty && !loading
              ? const Center(child: Text('Товаров нет'))
              : ListView(
                  children: widget.archived
                      ? rows
                            .map(
                              (r) => ListTile(
                                title: Text(r['name'] as String),
                                subtitle: Text('Архив • ${r['uom_name']}'),
                              ),
                            )
                            .toList()
                      : [
                          section('unassigned'),
                          section('relevant'),
                          section('irrelevant'),
                        ],
                ),
        ),
      ],
    ),
    bottomNavigationBar: selected.isEmpty
        ? null
        : SafeArea(
            child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              children: [
                Text('Выбрано: ${selected.length}'),
                TextButton(
                  onPressed: () => change(selected.toList(), 'relevant'),
                  child: const Text('Актуальные'),
                ),
                TextButton(
                  onPressed: () => change(selected.toList(), 'irrelevant'),
                  child: const Text('Не актуальные'),
                ),
                TextButton(
                  onPressed: () => change(selected.toList(), 'unassigned'),
                  child: const Text('Сбросить'),
                ),
              ],
            ),
          ),
  );
}

class ProductReviewScreen extends StatefulWidget {
  const ProductReviewScreen({
    super.key,
    required this.repository,
    required this.items,
    required this.index,
  });
  final ReferenceDataRepository repository;
  final List<Map<String, Object?>> items;
  final int index;
  @override
  State<ProductReviewScreen> createState() => _ProductReviewScreenState();
}

class _ProductReviewScreenState extends State<ProductReviewScreen> {
  late int i = widget.index;
  Map<String, Object?> get r => widget.items[i];
  Future<void> assign(String s) async {
    await widget.repository.setProductStatus([r['id'] as int], s);
    if (!mounted) return;
    if (i < widget.items.length - 1) {
      setState(() => i++);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Список обработан')));
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text('Товар ${i + 1} из ${widget.items.length}')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(r['name'] as String, style: Theme.of(c).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text('Остаток: ${r['stock']} ${r['uom_name']}'),
          const Spacer(),
          FilledButton(
            onPressed: () => assign('relevant'),
            child: const Text('Актуальный'),
          ),
          OutlinedButton(
            onPressed: () => assign('irrelevant'),
            child: const Text('Не актуальный'),
          ),
          TextButton(
            onPressed: () => assign('unassigned'),
            child: const Text('Нераспределённый'),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: i == 0 ? null : () => setState(() => i--),
                  child: const Text('Назад'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (i == widget.items.length - 1) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Обработка списка завершена'),
                        ),
                      );
                    } else {
                      setState(() => i++);
                    }
                  },
                  child: const Text('Вперёд'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key, required this.repository});
  final ReferenceDataRepository repository;
  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  List<Map<String, Object?>> rows = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await widget.repository.warehouses();
    if (mounted) {
      setState(() {
        rows = r;
        loading = false;
      });
    }
  }

  Future<void> sync() async {
    setState(() => loading = true);
    try {
      await widget.repository.syncWarehouses();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обновить склады')),
        );
      }
    }
    await load();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Склады и места хранения'),
      actions: [
        IconButton(
          onPressed: loading ? null : sync,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: rows
                .map(
                  (r) => ListTile(
                    title: Text(r['name'] as String),
                    subtitle: const Text('Локальные места хранения'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      c,
                      MaterialPageRoute<void>(
                        builder: (_) => StorageLocationsScreen(
                          repository: widget.repository,
                          warehouse: r,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
  );
}

class StorageLocationsScreen extends StatefulWidget {
  const StorageLocationsScreen({
    super.key,
    required this.repository,
    required this.warehouse,
  });
  final ReferenceDataRepository repository;
  final Map<String, Object?> warehouse;
  @override
  State<StorageLocationsScreen> createState() => _StorageLocationsScreenState();
}

class _StorageLocationsScreenState extends State<StorageLocationsScreen> {
  List<Map<String, Object?>> rows = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await widget.repository.storageLocations(
      widget.warehouse['id'] as int,
    );
    if (mounted) setState(() => rows = r);
  }

  Future<void> edit([Map<String, Object?>? row]) async {
    final ctl = TextEditingController(text: row?['name'] as String? ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(row == null ? 'Новое место' : 'Переименовать'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctl.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      await widget.repository.saveStorageLocation(
        widget.warehouse['id'] as int,
        value,
        id: row?['id'] as int?,
      );
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось сохранить: проверьте уникальность названия',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.warehouse['name'] as String),
      actions: [
        IconButton(onPressed: () => edit(), icon: const Icon(Icons.add)),
      ],
    ),
    body: ListView(
      children: rows
          .map(
            (r) => ListTile(
              title: Text(r['name'] as String),
              onTap: () => edit(r),
              trailing: IconButton(
                icon: const Icon(Icons.archive_outlined),
                onPressed: () async {
                  await widget.repository.archiveStorageLocation(
                    r['id'] as int,
                  );
                  await load();
                },
              ),
            ),
          )
          .toList(),
    ),
  );
}

class OrganizationsScreen extends StatefulWidget {
  const OrganizationsScreen({super.key, required this.repository});
  final ReferenceDataRepository repository;
  @override
  State<OrganizationsScreen> createState() => _OrganizationsScreenState();
}

class _OrganizationsScreenState extends State<OrganizationsScreen> {
  List<Map<String, Object?>> orgs = [], methods = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final o = await widget.repository.organizations(),
        m = await widget.repository.paymentMethods();
    if (mounted) {
      setState(() {
        orgs = o;
        methods = m;
        loading = false;
      });
    }
  }

  Future<void> sync() async {
    setState(() => loading = true);
    try {
      await widget.repository.syncOrganizations();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обновить организации')),
        );
      }
    }
    await load();
  }

  Future<void> addMethod() async {
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Способ оплаты'),
        content: TextField(controller: ctl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctl.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await widget.repository.savePaymentMethod(name);
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось создать способ оплаты')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Организации и оплата'),
      actions: [
        IconButton(onPressed: addMethod, icon: const Icon(Icons.add_card)),
        IconButton(
          onPressed: loading ? null : sync,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: [
              const ListTile(title: Text('Способы оплаты')),
              ...methods.map(
                (m) => ListTile(
                  title: Text(m['name'] as String),
                  subtitle: Text(
                    m['organization_id'] == null
                        ? 'Не назначен организации'
                        : 'Назначен организации',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      try {
                        await widget.repository.deletePaymentMethod(
                          m['id'] as int,
                        );
                        await load();
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Способ оплаты используется'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
              const Divider(),
              const ListTile(title: Text('Организации МойСклад')),
              ...orgs.map((o) {
                final matches = methods.where(
                  (m) => m['organization_id'] == o['id'],
                );
                final assigned = matches.isEmpty ? null : matches.first;
                return ListTile(
                  title: Text(o['name'] as String),
                  subtitle: Text(
                    assigned == null
                        ? 'Способ оплаты не назначен'
                        : assigned['name'] as String,
                  ),
                  trailing: DropdownButton<int?>(
                    value: assigned?['id'] as int?,
                    hint: const Text('Оплата'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Не назначено'),
                      ),
                      ...methods.map(
                        (m) => DropdownMenuItem<int?>(
                          value: m['id'] as int,
                          child: Text(m['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (v) async {
                      await widget.repository.assignPaymentMethod(
                        o['id'] as int,
                        v,
                      );
                      await load();
                    },
                  ),
                );
              }),
            ],
          ),
  );
}

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key, required this.repository});
  final ReferenceDataRepository repository;
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final ctl = TextEditingController();
  List<Map<String, dynamic>> remote = [];
  List<Map<String, Object?>> local = [];
  bool current = true, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await widget.repository.suppliers(
      status: current ? 'current' : 'other',
    );
    if (mounted) setState(() => local = r);
  }

  Future<void> search(String q) async {
    if (q.trim().length < 2) {
      setState(() => remote = []);
      return;
    }
    setState(() => busy = true);
    try {
      final r = await widget.repository.searchSuppliers(q);
      if (mounted) setState(() => remote = r);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Поиск не выполнен')));
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> open(Map<String, dynamic> r) async {
    try {
      await widget.repository.openSupplierCard(r);
      final currentRows = await widget.repository.suppliers(status: 'current');
      final otherRows = await widget.repository.suppliers(status: 'other');
      final localRows = [...currentRows, ...otherRows];
      final found = localRows.where((x) => x['moysklad_id'] == r['id']);
      if (found.isNotEmpty && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SupplierCardScreen(
              repository: widget.repository,
              supplier: found.first,
            ),
          ),
        );
      }
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть поставщика')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Поставщики')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: ctl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Поиск от двух символов',
            ),
            onChanged: search,
          ),
        ),
        if (ctl.text.trim().length >= 2)
          Expanded(
            child: busy
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: remote
                        .map(
                          (r) => ListTile(
                            title: Text(r['name']?.toString() ?? ''),
                            subtitle: Text(r['phone']?.toString() ?? ''),
                            onTap: () => open(r),
                          ),
                        )
                        .toList(),
                  ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Актуальные')),
                ButtonSegment(value: false, label: Text('Прочие')),
              ],
              selected: {current},
              onSelectionChanged: (v) {
                setState(() => current = v.first);
                load();
              },
            ),
          ),
          Expanded(
            child: ListView(
              children: local
                  .map(
                    (r) => ListTile(
                      title: Text(r['name'] as String),
                      subtitle: Text(r['phone'] as String? ?? ''),
                      onTap: () => Navigator.push(
                        c,
                        MaterialPageRoute<void>(
                          builder: (_) => SupplierCardScreen(
                            repository: widget.repository,
                            supplier: r,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    ),
  );
}

class SupplierCardScreen extends StatefulWidget {
  const SupplierCardScreen({
    super.key,
    required this.repository,
    required this.supplier,
  });
  final ReferenceDataRepository repository;
  final Map<String, Object?> supplier;
  @override
  State<SupplierCardScreen> createState() => _SupplierCardScreenState();
}

class _SupplierCardScreenState extends State<SupplierCardScreen> {
  List<Map<String, Object?>> methods = [], details = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final m = await widget.repository.paymentMethods(),
        d = await widget.repository.supplierPaymentDetails(
          widget.supplier['id'] as int,
        );
    if (mounted) {
      setState(() {
        methods = m;
        details = d;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final d = details.isEmpty ? <String, Object?>{} : details.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Карточка поставщика')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.supplier['name'] as String,
            style: Theme.of(c).textTheme.headlineSmall,
          ),
          Text(widget.supplier['phone'] as String? ?? 'Телефон не указан'),
          DropdownButtonFormField<String>(
            initialValue: widget.supplier['relevance_status'] as String,
            decoration: const InputDecoration(labelText: 'Статус'),
            items: const [
              DropdownMenuItem(value: 'current', child: Text('Актуальный')),
              DropdownMenuItem(value: 'other', child: Text('Прочие')),
            ],
            onChanged: (v) async {
              if (v != null) {
                await widget.repository.setSupplierStatus(
                  widget.supplier['id'] as int,
                  v,
                );
                if (mounted) Navigator.pop(context);
              }
            },
          ),
          DropdownButtonFormField<int?>(
            initialValue: d['payment_method_id'] as int?,
            decoration: const InputDecoration(labelText: 'Способ оплаты'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Не назначен'),
              ),
              ...methods.map(
                (m) => DropdownMenuItem<int?>(
                  value: m['id'] as int,
                  child: Text(m['name'] as String),
                ),
              ),
            ],
            onChanged: (v) async {
              await widget.repository.setSupplierPaymentMethod(
                widget.supplier['id'] as int,
                v,
              );
              await load();
            },
          ),
          if (d['organization_name'] == null)
            const ListTile(
              leading: Icon(Icons.warning_amber),
              title: Text('Организация не определена'),
              subtitle: Text('Назначьте способ оплаты организации.'),
            )
          else
            ListTile(
              title: const Text('Организация'),
              subtitle: Text(d['organization_name'] as String),
            ),
        ],
      ),
    );
  }
}

class ApiTasksScreen extends StatefulWidget {
  const ApiTasksScreen({super.key, required this.api, this.onResumeConfirmed});
  final ApiTaskDispatcher api;
  final Future<void> Function()? onResumeConfirmed;
  @override
  State<ApiTasksScreen> createState() => _ApiTasksScreenState();
}

class _ApiTasksScreenState extends State<ApiTasksScreen> {
  List<ApiTask> tasks = [];
  bool loading = true, paused = false, confirmation = false;
  Map<String, bool> queuePauses = {};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final t = await widget.api.listTasks();
    final c = await widget.api.repository.requiresResumeConfirmation();
    final isPaused = await widget.api.isGloballyPaused();
    final queues = t.map((task) => task.logicalQueue).toSet();
    final queueState = <String, bool>{};
    for (final queue in queues) {
      queueState[queue] = await widget.api.isQueuePaused(queue);
    }
    if (mounted) {
      setState(() {
        tasks = t;
        queuePauses = queueState;
        paused = isPaused;
        confirmation = c;
        loading = false;
      });
    }
  }

  Future<void> showTaskDetails(ApiTask task) async {
    final history = await widget.api.taskHistory(task.id);
    if (!mounted) return;
    final attempts = history['attempts'] ?? [];
    final events = history['events'] ?? [];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Задача ${task.uid}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Статус: ${task.status.name} • Попытки: ${task.attemptsCount}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Запрос',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(task.request),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ответ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SelectableText(
                  const JsonEncoder.withIndent('  ')
                      .convert(task.response ?? {}),
                ),
                const SizedBox(height: 12),
                const Text(
                  'История попыток',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...attempts.map(
                  (a) => ListTile(
                    dense: true,
                    title: Text(
                      'Попытка ${a['attempt_number']} • ${a['outcome']}',
                    ),
                    subtitle: Text(
                      'HTTP ${a['http_status_code'] ?? '—'} • ${a['safe_error_code'] ?? ''} ${a['safe_error_message'] ?? ''}',
                    ),
                  ),
                ),
                const Text(
                  'События',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...events.map(
                  (e) => ListTile(
                    dense: true,
                    title: Text(e['message'] as String),
                    subtitle: Text(
                      '${e['from_state'] ?? ''} → ${e['to_state'] ?? ''}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  String _taskStatusLabel(ApiTask task) {
    if ((paused || queuePauses[task.logicalQueue] == true) &&
        (task.status == ApiTaskStatus.pending ||
            task.status == ApiTaskStatus.retryWait)) {
      return 'Остановлена';
    }
    return switch (task.status) {
      ApiTaskStatus.pending => 'В очереди',
      ApiTaskStatus.running => 'Выполняется',
      ApiTaskStatus.retryWait => 'Ожидает повтора',
      ApiTaskStatus.succeeded => 'Успешно',
      ApiTaskStatus.failed => 'Ошибка',
      ApiTaskStatus.uncertain => 'Результат не подтверждён',
      ApiTaskStatus.cancelled => 'Остановлена',
    };
  }

  Color _taskStatusColor(ApiTask task) {
    if ((paused || queuePauses[task.logicalQueue] == true) &&
        (task.status == ApiTaskStatus.pending ||
            task.status == ApiTaskStatus.retryWait)) {
      return Colors.red;
    }
    return switch (task.status) {
      ApiTaskStatus.succeeded => Colors.green,
      ApiTaskStatus.failed ||
      ApiTaskStatus.uncertain ||
      ApiTaskStatus.cancelled => Colors.red,
      ApiTaskStatus.pending ||
      ApiTaskStatus.running ||
      ApiTaskStatus.retryWait => Colors.blue,
    };
  }

  Future<void> pause(bool v) async {
    await widget.api.setGlobalPaused(v);
    await load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(v ? 'Все очереди остановлены' : 'Все очереди запущены'),
        ),
      );
  }

  Future<void> deleteAllTasks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить все задачи?'),
        content: const Text(
          'Будут удалены все задачи Менеджера API, включая историю попыток и событий. Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить все'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final deleted = await widget.api.deleteAllTasks();
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Удалено задач: $deleted')),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить задачи: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Менеджер API'),
      actions: [
        IconButton(
          tooltip: 'Удалить все задачи',
          onPressed: loading || tasks.isEmpty ? null : deleteAllTasks,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
        IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (confirmation)
                MaterialBanner(
                  content: const Text(
                    'После перезапуска требуется подтверждение продолжения очереди.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await widget.api.confirmResumeAfterRestart();
                        await widget.onResumeConfirmed?.call();
                        await load();
                      },
                      child: const Text('Подтвердить'),
                    ),
                  ],
                ),
              SwitchListTile(
                title: const Text('Пауза всех очередей'),
                value: paused,
                onChanged: pause,
              ),
              if (queuePauses.isNotEmpty)
                ExpansionTile(
                  title: const Text('Логические очереди'),
                  children: queuePauses.entries
                      .map(
                        (entry) => SwitchListTile(
                          title: Text(entry.key),
                          value: entry.value,
                          onChanged: (value) async {
                            await widget.api.setQueuePaused(entry.key, value);
                            await load();
                          },
                        ),
                      )
                      .toList(),
                ),
              ListTile(
                title: const Text('Ожидающие задачи'),
                trailing: TextButton(
                  onPressed: () async {
                    await widget.api.cancelPending();
                    await load();
                  },
                  child: const Text('Отменить все'),
                ),
              ),
              Expanded(
                child: ListView(
                  children: tasks
                      .map(
                        (t) => ListTile(
                          title: Row(
                            children: [
                              Expanded(child: Text(t.type)),
                              const SizedBox(width: 8),
                              Text(
                                _taskStatusLabel(t),
                                style: TextStyle(
                                  color: _taskStatusColor(t),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${t.uid}\nПопытки: ${t.attemptsCount} • FIFO: ${t.fifoSequence}',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Действия с задачей',
                            onSelected: (action) async {
                              if (action == 'details') {
                                await showTaskDetails(t);
                              } else if (action == 'retry') {
                                await widget.api.retryFailed(t.id);
                              } else if (action == 'success' ||
                                  action == 'failed') {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Подтвердить результат'),
                                    content: const Text(
                                      'Вы проверили состояние операции непосредственно в МойСклад?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c, false),
                                        child: const Text('Нет'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Да, проверил'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await widget.api.resolveUncertain(
                                    t.id,
                                    confirmedSucceeded: action == 'success',
                                  );
                                }
                              }
                              await load();
                            },
                            itemBuilder: (c) => [
                              const PopupMenuItem(
                                value: 'details',
                                child: Text('Детали и история'),
                              ),
                              if (t.status == ApiTaskStatus.failed)
                                const PopupMenuItem(
                                  value: 'retry',
                                  child: Text('Повторить вручную'),
                                ),
                              if (t.status == ApiTaskStatus.uncertain) ...[
                                const PopupMenuItem(
                                  value: 'success',
                                  child: Text('Подтвердить выполнение'),
                                ),
                                const PopupMenuItem(
                                  value: 'failed',
                                  child: Text('Подтвердить отсутствие'),
                                ),
                              ],
                              PopupMenuItem(
                                value: 'status',
                                enabled: false,
                                child: Text(t.status.name),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
  );
}
