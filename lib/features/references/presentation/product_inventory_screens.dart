import 'dart:async';

import 'package:flutter/material.dart';

import '../data/reference_data_repository.dart';

/// Compact warehouse breakdown shared by product lists and review screens.
/// The stock value belongs to the warehouse, not to the local storage location.
class ProductWarehouseOverview extends StatelessWidget {
  const ProductWarehouseOverview({
    super.key,
    required this.rows,
    required this.unit,
  });

  final List<Map<String, Object?>> rows;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text(
          'Остатки по складам не загружены',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: rows.map((row) {
          final stock = row['stock'];
          final stockText = stock == null ? '—' : '$stock $unit'.trim();
          return ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 112, maxWidth: 190),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row['warehouse_name']?.toString() ?? 'Склад',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Место: ${row['location_name'] ?? '—'}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Остаток: $stockText',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

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
  List<Map<String, Object?>> warehouseRows = [];
  final Map<int, List<Map<String, Object?>>> warehouseOverview = {};
  String? warehouseFilter;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    loadWarehouses();
    load();
  }

  Future<void> loadWarehouses() async {
    final result = await widget.repository.warehouses();
    if (mounted) setState(() => warehouseRows = result);
  }

  Future<void> load() async {
    final request = ++_loadGeneration;
    if (mounted) setState(() => loading = true);
    try {
      final result = await widget.repository.products(
        search: search,
        status: status,
        warehouseMoyskladId: warehouseFilter,
      );
      final overview = await widget.repository.productWarehouseOverview(
        result.map((row) => row['id'] as int),
      );
      final grouped = <int, List<Map<String, Object?>>>{};
      for (final row in overview) {
        (grouped[row['product_id'] as int] ??= []).add(row);
      }
      if (mounted && request == _loadGeneration) {
        setState(() {
          products = result;
          warehouseOverview
            ..clear()
            ..addAll(grouped);
          loading = false;
        });
      }
    } catch (error) {
      if (mounted && request == _loadGeneration) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить товары: $error')),
        );
      }
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

  Future<void> chooseSupplier(List<int> ids) async {
    final supplier = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => SupplierPickerDialog(repository: widget.repository),
    );
    if (supplier == null || !mounted) return;
    try {
      await widget.repository.assignSupplierToProducts(ids, supplier);
      if (!mounted) return;
      setState(() => selected.clear());
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Поставщик «${supplier['name']}» назначен ${ids.length} товарам',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось назначить поставщика: $error')),
        );
      }
    }
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
        selected.isNotEmpty
            ? 'Выбрано: ${selected.length}'
            : sequential
            ? 'Последовательная актуализация'
            : 'Каталог товаров',
      ),
      actions: [
        if (selected.isNotEmpty) ...[
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
                case 'supplier':
                  chooseSupplier(ids);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'relevant', child: Text('Актуален')),
              PopupMenuItem(value: 'irrelevant', child: Text('Не актуален')),
              PopupMenuItem(value: 'unassigned', child: Text('Нераспределён')),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'storage',
                child: Text('Выбрать склад и место хранения'),
              ),
              PopupMenuItem(
                value: 'supplier',
                child: Text('Назначить поставщика'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Снять выделение',
            onPressed: () => setState(() => selected.clear()),
            icon: const Icon(Icons.close),
          ),
        ] else ...[
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonFormField<String?>(
            initialValue: warehouseFilter,
            decoration: const InputDecoration(labelText: 'Склад'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Все склады'),
              ),
              ...warehouseRows.map(
                (w) => DropdownMenuItem<String?>(
                  value: w['moysklad_id'] as String,
                  child: Text(
                    w['name'] as String,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => warehouseFilter = value);
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(statusName(p['relevance_status'] as String?)),
                    Text('Поставщик: ${p['supplier_name'] ?? 'Не назначен'}'),
                    ProductWarehouseOverview(
                      rows: warehouseOverview[id] ?? const [],
                      unit: p['uom_name']?.toString() ?? '',
                    ),
                  ],
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
  List<Map<String, Object?>> warehouseOverview = [];
  Map<String, Object?>? supplier;
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
    final selectedSupplier = await widget.repository.productSupplier(
      widget.product['id'] as int,
    );
    final stockOverview = await widget.repository.productWarehouseOverview([
      widget.product['id'] as int,
    ]);
    if (mounted) {
      setState(() {
        assignments = rows;
        warehouseOverview = stockOverview;
        supplier = selectedSupplier;
        loading = false;
      });
    }
  }

  Future<void> chooseSupplier() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => SupplierPickerDialog(repository: widget.repository),
    );
    if (selected == null || !mounted) return;
    try {
      await widget.repository.assignSupplierToProducts([
        widget.product['id'] as int,
      ], selected);
      await load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось назначить поставщика: $error')),
        );
      }
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
          Text('Общий остаток: ${p['stock']} ${p['uom_name']}'),
          ProductWarehouseOverview(
            rows: warehouseOverview,
            unit: p['uom_name']?.toString() ?? '',
          ),
          const SizedBox(height: 24),
          const Text(
            'Поставщик',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(supplier?['name'] as String? ?? 'Не назначен'),
            subtitle: Text(supplier?['phone'] as String? ?? ''),
            trailing: const Icon(Icons.search),
            onTap: chooseSupplier,
          ),
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
  List<Map<String, Object?>> assignments = [];
  List<Map<String, Object?>> warehouseStocks = [];
  Map<String, Object?>? supplier;
  String? detailsError;
  Map<String, Object?> get product => widget.items[index];

  @override
  void initState() {
    super.initState();
    loadProductDetails();
  }

  Future<void> loadProductDetails() async {
    final id = product['id'] as int;
    try {
      final nextAssignments = await widget.repository.productStorageAssignments(
        id,
      );
      final nextStocks = await widget.repository.productWarehouseStocks(id);
      final nextSupplier = await widget.repository.productSupplier(id);
      if (mounted && (product['id'] as int) == id) {
        setState(() {
          assignments = nextAssignments;
          warehouseStocks = nextStocks;
          supplier = nextSupplier;
          detailsError = null;
        });
      }
    } catch (error) {
      if (mounted && (product['id'] as int) == id) {
        setState(() => detailsError = error.toString());
      }
    }
  }

  Future<void> moveTo(int nextIndex) async {
    if (nextIndex < 0 || nextIndex >= widget.items.length) return;
    setState(() => index = nextIndex);
    await loadProductDetails();
  }

  Future<void> assign(String status) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.repository.setProductStatus([product['id'] as int], status);
      if (mounted && index < widget.items.length - 1) {
        await moveTo(index + 1);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Актуализация завершена')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить статус: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> chooseSupplier() async {
    if (saving) return;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => SupplierPickerDialog(repository: widget.repository),
    );
    if (selected == null || !mounted) return;
    setState(() => saving = true);
    try {
      await widget.repository.assignSupplierToProducts([
        product['id'] as int,
      ], selected);
      await loadProductDetails();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось назначить поставщика: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> chooseStorage() async {
    if (saving) return;
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
    if (location == null || !mounted) return;
    setState(() => saving = true);
    try {
      await widget.repository.assignProductsToStorageLocation(
        [product['id'] as int],
        warehouse['id'] as int,
        location['id'] as int,
      );
      await loadProductDetails();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Назначено: ${warehouse['name']} • ${location['name']}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось назначить место: $error')),
        );
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
        const Text(
          'Остатки по складам',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Показывается остаток всего склада. Место хранения — локальная привязка, остаток отдельной ячейки МойСклад не предоставляет.',
          style: TextStyle(fontSize: 12),
        ),
        if (detailsError != null)
          Text('Не удалось загрузить данные товара: $detailsError'),
        if (warehouseStocks.isEmpty)
          const Text('Детализация по складам пока не загружена')
        else
          ...warehouseStocks.map((row) {
            final assignment = assignments
                .where(
                  (item) =>
                      item['warehouse_moysklad_id'] ==
                      row['warehouse_moysklad_id'],
                )
                .firstOrNull;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row['warehouse_name'] as String),
              subtitle: Text(
                assignment == null
                    ? 'Место хранения не назначено'
                    : assignment['location_name'] as String,
              ),
              trailing: Text('${row['stock']} ${product['uom_name']}'),
            );
          }),
        const SizedBox(height: 16),
        const Text('Поставщик', style: TextStyle(fontWeight: FontWeight.bold)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(supplier?['name'] as String? ?? 'Не назначен'),
          subtitle: Text(supplier?['phone'] as String? ?? ''),
          trailing: const Icon(Icons.search),
          onTap: saving ? null : chooseSupplier,
        ),
        const Text(
          'Места хранения',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (assignments.isEmpty)
          const Text('Места хранения не назначены')
        else
          ...assignments.map(
            (row) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row['warehouse_name'] as String),
              subtitle: Text(row['location_name'] as String),
              trailing: IconButton(
                tooltip: 'Убрать место хранения',
                icon: const Icon(Icons.delete_outline),
                onPressed: saving
                    ? null
                    : () async {
                        setState(() => saving = true);
                        try {
                          await widget.repository
                              .removeProductStorageAssignment(row['id'] as int);
                          await loadProductDetails();
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Не удалось убрать место: $error'),
                            ),
                          );
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: saving ? null : chooseStorage,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Назначить склад и место хранения'),
        ),
        const Divider(height: 32),
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
                    : () => moveTo(index - 1),
                child: const Text('Назад'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: saving || index == widget.items.length - 1
                    ? null
                    : () => moveTo(index + 1),
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

class SupplierPickerDialog extends StatefulWidget {
  const SupplierPickerDialog({super.key, required this.repository});
  final ReferenceDataRepository repository;

  @override
  State<SupplierPickerDialog> createState() => _SupplierPickerDialogState();
}

class _SupplierPickerDialogState extends State<SupplierPickerDialog> {
  final controller = TextEditingController();
  Timer? timer;
  List<Map<String, dynamic>> results = [];
  bool loading = false;
  int generation = 0;

  void search(String value) {
    timer?.cancel();
    final request = ++generation;
    if (value.trim().length < 2) {
      setState(() {
        results = [];
        loading = false;
      });
      return;
    }
    setState(() {
      results = [];
      loading = true;
    });
    timer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final found = await widget.repository.searchSuppliers(value);
        if (mounted && request == generation) {
          setState(() => results = found);
        }
      } catch (error) {
        if (mounted && request == generation) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '\u041f\u043e\u0438\u0441\u043a \u043f\u043e\u0441\u0442\u0430\u0432\u0449\u0438\u043a\u043e\u0432 \u043d\u0435 \u0432\u044b\u043f\u043e\u043b\u043d\u0435\u043d: $error',
              ),
            ),
          );
        }
      } finally {
        if (mounted && request == generation) {
          setState(() => loading = false);
        }
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(
      '\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u043f\u043e\u0441\u0442\u0430\u0432\u0449\u0438\u043a',
    ),
    content: SizedBox(
      width: 480,
      height: 420,
      child: Column(
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '\u041f\u043e\u0438\u0441\u043a \u043e\u0442 \u0434\u0432\u0443\u0445 \u0441\u0438\u043c\u0432\u043e\u043b\u043e\u0432',
            ),
            onChanged: search,
          ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: controller.text.trim().length < 2
                ? const Center(
                    child: Text(
                      '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043d\u0435 \u043c\u0435\u043d\u0435\u0435 \u0434\u0432\u0443\u0445 \u0441\u0438\u043c\u0432\u043e\u043b\u043e\u0432',
                    ),
                  )
                : results.isEmpty && !loading
                ? const Center(
                    child: Text(
                      '\u041f\u043e\u0441\u0442\u0430\u0432\u0449\u0438\u043a\u0438 \u043d\u0435 \u043d\u0430\u0439\u0434\u0435\u043d\u044b',
                    ),
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final supplier = results[index];
                      return ListTile(
                        title: Text(supplier['name']?.toString() ?? ''),
                        subtitle: Text(supplier['phone']?.toString() ?? ''),
                        onTap: () => Navigator.pop(context, supplier),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('\u041e\u0442\u043c\u0435\u043d\u0430'),
      ),
    ],
  );
}
