import 'package:flutter/material.dart';

import '../data/reference_data_repository.dart';

class InventoryCatalogScreen extends StatefulWidget {
  const InventoryCatalogScreen({super.key, required this.repository});
  final ReferenceDataRepository repository;
  @override
  State<InventoryCatalogScreen> createState() => _InventoryCatalogScreenState();
}

class _InventoryCatalogScreenState extends State<InventoryCatalogScreen> {
  List<Map<String, Object?>> products = [];
  final Set<int> selected = {};
  String search = '';
  String? status;
  bool loading = true, sequential = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    final result = await widget.repository.products(
      search: search,
      status: status,
    );
    if (mounted) {
      setState(() {
        products = result;
        loading = false;
      });
    }
  }

  String statusName(String? value) => switch (value) {
    'relevant' => 'Актуален',
    'irrelevant' => 'Не актуален',
    _ => 'Нераспределён',
  };

  Future<void> changeStatus(List<int> ids, String value) async {
    await widget.repository.setProductStatus(ids, value);
    if (!mounted) return;
    setState(() => selected.clear());
    await load();
  }

  Future<void> chooseStorage(List<int> ids) async {
    final warehouses = await widget.repository.warehouses();
    if (!mounted) return;
    if (warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала обновите список складов')),
      );
      return;
    }
    final warehouse = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Выберите склад'),
        children: warehouses
            .map(
              (w) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, w),
                child: Text(w['name'] as String),
              ),
            )
            .toList(),
      ),
    );
    if (warehouse == null || !mounted) return;
    final locations = await widget.repository.storageLocations(
      warehouse['id'] as int,
    );
    if (!mounted) return;
    if (locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('На этом складе пока нет мест хранения')),
      );
      return;
    }
    final location = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(warehouse['name'] as String),
        children: locations
            .map(
              (l) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, l),
                child: Text(l['name'] as String),
              ),
            )
            .toList(),
      ),
    );
    if (location == null) return;
    await widget.repository.assignProductsToStorageLocation(
      ids,
      warehouse['id'] as int,
      location['id'] as int,
    );
    if (!mounted) return;
    setState(() => selected.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Место назначено ${ids.length} товарам')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        sequential ? 'Последовательная актуализация' : 'Каталог товаров',
      ),
      actions: [
        IconButton(
          tooltip: sequential ? 'Обычный режим' : 'Последовательный ввод',
          icon: Icon(sequential ? Icons.list_alt : Icons.playlist_play),
          onPressed: () => setState(() {
            sequential = !sequential;
            selected.clear();
          }),
        ),
        IconButton(icon: const Icon(Icons.refresh), onPressed: load),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonFormField<String?>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Статус'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Все товары')),
              DropdownMenuItem(
                value: 'unassigned',
                child: Text('Нераспределённые'),
              ),
              DropdownMenuItem(value: 'relevant', child: Text('Актуальные')),
              DropdownMenuItem(
                value: 'irrelevant',
                child: Text('Не актуальные'),
              ),
            ],
            onChanged: (v) {
              status = v;
              load();
            },
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (context, index) {
              final p = products[index], id = p['id'] as int;
              final isSelected = selected.contains(id);
              return ListTile(
                selected: isSelected,
                leading: sequential
                    ? CircleAvatar(child: Text('${index + 1}'))
                    : selected.isNotEmpty
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                      )
                    : const Icon(Icons.inventory_2_outlined),
                title: Text(p['name'] as String),
                subtitle: Text(
                  '${statusName(p['relevance_status'] as String?)} • Остаток: ${p['stock']} ${p['uom_name']}',
                ),
                onLongPress: sequential
                    ? null
                    : () => setState(() => selected.add(id)),
                onTap: () {
                  if (selected.isNotEmpty) {
                    setState(() {
                      if (isSelected) {
                        selected.remove(id);
                      } else {
                        selected.add(id);
                      }
                    });
                  } else if (sequential) {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ProductSequenceScreen(
                          repository: widget.repository,
                          items: products,
                          index: index,
                        ),
                      ),
                    ).then((_) => load());
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ProductDetailScreen(
                          repository: widget.repository,
                          product: p,
                        ),
                      ),
                    ).then((_) => load());
                  }
                },
              );
            },
          ),
        ),
      ],
    ),
    bottomNavigationBar: selected.isEmpty
        ? null
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: Text('Выбрано: ${selected.length}')),
                  PopupMenuButton<String>(
                    tooltip: 'Действия',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) {
                      final ids = selected.toList();
                      switch (action) {
                        case 'relevant':
                          changeStatus(ids, 'relevant');
                          break;
                        case 'irrelevant':
                          changeStatus(ids, 'irrelevant');
                          break;
                        case 'unassigned':
                          changeStatus(ids, 'unassigned');
                          break;
                        case 'storage':
                          chooseStorage(ids);
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'relevant', child: Text('Актуален')),
                      PopupMenuItem(
                        value: 'irrelevant',
                        child: Text('Не актуален'),
                      ),
                      PopupMenuItem(
                        value: 'unassigned',
                        child: Text('Нераспределён'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'storage',
                        child: Text('Выбрать склад и место хранения'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Снять выделение',
                    onPressed: () => setState(() => selected.clear()),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
  );
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.repository,
    required this.product,
  });
  final ReferenceDataRepository repository;
  final Map<String, Object?> product;
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  List<Map<String, Object?>> assignments = [];
  bool loading = true;
  late String currentStatus;
  @override
  void initState() {
    super.initState();
    currentStatus =
        widget.product['relevance_status'] as String? ?? 'unassigned';
    load();
  }

  Future<void> load() async {
    final rows = await widget.repository.productStorageAssignments(
      widget.product['id'] as int,
    );
    if (mounted) {
      setState(() {
        assignments = rows;
        loading = false;
      });
    }
  }

  Future<void> addLocation() async {
    final warehouses = await widget.repository.warehouses();
    if (!mounted || warehouses.isEmpty) return;
    final warehouse = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Выберите склад'),
        children: warehouses
            .map(
              (w) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, w),
                child: Text(w['name'] as String),
              ),
            )
            .toList(),
      ),
    );
    if (warehouse == null) return;
    final locations = await widget.repository.storageLocations(
      warehouse['id'] as int,
    );
    if (!mounted || locations.isEmpty) return;
    final location = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(warehouse['name'] as String),
        children: locations
            .map(
              (l) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, l),
                child: Text(l['name'] as String),
              ),
            )
            .toList(),
      ),
    );
    if (location == null) return;
    await widget.repository.assignProductsToStorageLocation(
      [widget.product['id'] as int],
      warehouse['id'] as int,
      location['id'] as int,
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      appBar: AppBar(title: const Text('Карточка товара')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            p['name'] as String,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('Остаток: ${p['stock']} ${p['uom_name']}'),
          const SizedBox(height: 24),
          const Text('Статус', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'relevant', label: Text('Актуален')),
              ButtonSegment(value: 'irrelevant', label: Text('Не актуален')),
              ButtonSegment(value: 'unassigned', label: Text('Не распр.')),
            ],
            selected: {currentStatus},
            onSelectionChanged: (v) async {
              await widget.repository.setProductStatus([
                p['id'] as int,
              ], v.first);
              if (mounted) setState(() => currentStatus = v.first);
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Места хранения',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: addLocation,
                icon: const Icon(Icons.add_location_alt_outlined),
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          if (!loading && assignments.isEmpty)
            const Text('Места хранения не назначены'),
          ...assignments.map(
            (a) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(a['warehouse_name'] as String),
              subtitle: Text(a['location_name'] as String),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await widget.repository.removeProductStorageAssignment(
                    a['id'] as int,
                  );
                  await load();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductSequenceScreen extends StatefulWidget {
  const ProductSequenceScreen({
    super.key,
    required this.repository,
    required this.items,
    required this.index,
  });
  final ReferenceDataRepository repository;
  final List<Map<String, Object?>> items;
  final int index;
  @override
  State<ProductSequenceScreen> createState() => _ProductSequenceScreenState();
}

class _ProductSequenceScreenState extends State<ProductSequenceScreen> {
  late int index = widget.index;
  bool saving = false;
  Map<String, Object?> get product => widget.items[index];
  Future<void> assign(String status) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.repository.setProductStatus([product['id'] as int], status);
      if (mounted && index < widget.items.length - 1) {
        setState(() => index++);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Актуализация завершена')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Товар ${index + 1} из ${widget.items.length}')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          product['name'] as String,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text('Остаток: ${product['stock']} ${product['uom_name']}'),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: saving ? null : () => assign('relevant'),
          child: const Text('Актуален'),
        ),
        OutlinedButton(
          onPressed: saving ? null : () => assign('irrelevant'),
          child: const Text('Не актуален'),
        ),
        TextButton(
          onPressed: saving ? null : () => assign('unassigned'),
          child: const Text('Нераспределён'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: index == 0 || saving
                    ? null
                    : () => setState(() => index--),
                child: const Text('Назад'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: saving || index == widget.items.length - 1
                    ? null
                    : () => setState(() => index++),
                child: const Text('Пропустить'),
              ),
            ),
          ],
        ),
        if (saving) const LinearProgressIndicator(),
      ],
    ),
  );
}
