import 'package:flutter/material.dart';

import '../../../core/widgets/quantity_keyboard.dart';

import '../data/reference_data_repository.dart';

class InventoryHomeScreen extends StatefulWidget {
  const InventoryHomeScreen({super.key, required this.repository});
  final ReferenceDataRepository repository;

  @override
  State<InventoryHomeScreen> createState() => _InventoryHomeScreenState();
}

class _InventoryHomeScreenState extends State<InventoryHomeScreen> {
  List<Map<String, Object?>> sessions = [];
  List<Map<String, dynamic>> remoteInventories = [];
  String? remoteLoadError;
  List<Map<String, Object?>> organizations = [];
  List<Map<String, Object?>> warehouses = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final values = await Future.wait([
        widget.repository.inventorySessions(),
        widget.repository.organizations(),
        widget.repository.warehouses(),
      ]);
      List<Map<String, dynamic>> remote = [];
      String? remoteError;
      try {
        remote = await widget.repository.moySkladInventories();
      } catch (error) {
        remoteError = error.toString();
      }
      if (!mounted) return;
      setState(() {
        sessions = values[0]
            .where((session) => session['status'] != 'completed')
            .toList();
        organizations = values[1];
        warehouses = values[2];
        remoteInventories = remote;
        remoteLoadError = remoteError;
        loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось загрузить инвентаризации: $error'),
          ),
        );
      }
    }
  }

  Future<void> createDraft() async {
    if (organizations.isEmpty || warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала синхронизируйте организации и склады'),
        ),
      );
      return;
    }
    final setup = await showDialog<_InventorySetupResult>(
      context: context,
      builder: (_) => InventorySetupDialog(
        repository: widget.repository,
        organizations: organizations,
        warehouses: warehouses,
      ),
    );
    if (setup == null || !mounted) return;
    try {
      final id = await widget.repository.createInventoryDraft(
        organizationId: setup.organizationId,
        warehouseId: setup.warehouseId,
        storageLocationIds: setup.locationIds,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => InventorySessionScreen(
            repository: widget.repository,
            sessionId: id,
          ),
        ),
      );
      await load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось создать инвентаризацию: $error')),
        );
      }
    }
  }

  Future<void> deleteDraft(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить черновик?'),
        content: const Text(
          'Локальная инвентаризация и все введённые количества будут удалены. Документ в МойСклад не создавался.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteInventoryDraft(id);
      await load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить черновик: $error')),
      );
    }
  }

  Future<void> openMoySkladInventory(Map<String, dynamic> inventory) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MoySkladInventoryScreen(
          repository: widget.repository,
          inventory: inventory,
        ),
      ),
    );
    await load();
  }

  Future<void> openSession(int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => InventorySessionScreen(
          repository: widget.repository,
          sessionId: id,
        ),
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Инвентаризация'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: createDraft,
      icon: const Icon(Icons.add),
      label: const Text('Новая'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              if (remoteLoadError != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: const Text(
                      'Не удалось загрузить документы МойСклад',
                    ),
                    subtitle: Text(remoteLoadError!),
                    trailing: IconButton(
                      tooltip: 'Повторить',
                      onPressed: load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                ),
              if (sessions.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text(
                    'Локальные черновики',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...sessions.map((session) {
                  final status = session['status'] as String;
                  final completed = status == 'completed';
                  final failed = status == 'sync_failed';
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        completed
                            ? Icons.check_circle_outline
                            : failed
                            ? Icons.error_outline
                            : Icons.inventory_2_outlined,
                        color: completed
                            ? Colors.green
                            : failed
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      title: Text(session['warehouse_name_snapshot'] as String),
                      subtitle: Text(
                        '${session['organization_name_snapshot']} • ${_inventoryStatus(status)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (status == 'draft')
                            IconButton(
                              tooltip: 'Удалить черновик',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  deleteDraft(session['id'] as int),
                            ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => openSession(session['id'] as int),
                    ),
                  );
                }),
              ],
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Text(
                  'Инвентаризации МойСклад',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (remoteInventories.isEmpty && remoteLoadError == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('В МойСклад инвентаризаций не найдено'),
                ),
              ...remoteInventories.map((inventory) {
                final name = inventory['name']?.toString() ?? 'Инвентаризация';
                final store = _inventoryRelatedName(inventory['store']);
                final organization = _inventoryRelatedName(
                  inventory['organization'],
                );
                final moment =
                    inventory['moment']?.toString() ??
                    inventory['created']?.toString() ??
                    '';
                final state = _inventoryRelatedName(inventory['state']);
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_done_outlined),
                    title: Text(name),
                    subtitle: Text(
                      [
                        if (store.isNotEmpty) store,
                        if (organization.isNotEmpty) organization,
                        if (moment.isNotEmpty) moment.replaceFirst('T', ' '),
                        if (state.isNotEmpty) state,
                      ].join(' • '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openMoySkladInventory(inventory),
                  ),
                );
              }),
            ],
          ),
  );
}

String _inventoryRelatedName(Object? value) {
  if (value is Map) {
    return value['name']?.toString() ?? '';
  }
  return '';
}

String _inventoryStatus(String status) => switch (status) {
  'completed' => 'Отправлена в МойСклад',
  'sync_failed' => 'Ошибка отправки — можно повторить',
  'syncing' => 'Отправка',
  _ => 'Черновик',
};

class _InventorySetupResult {
  const _InventorySetupResult({
    required this.organizationId,
    required this.warehouseId,
    required this.locationIds,
  });
  final int organizationId;
  final int warehouseId;
  final List<int> locationIds;
}

class InventorySetupDialog extends StatefulWidget {
  const InventorySetupDialog({
    super.key,
    required this.repository,
    required this.organizations,
    required this.warehouses,
  });

  final ReferenceDataRepository repository;
  final List<Map<String, Object?>> organizations;
  final List<Map<String, Object?>> warehouses;

  @override
  State<InventorySetupDialog> createState() => _InventorySetupDialogState();
}

class _InventorySetupDialogState extends State<InventorySetupDialog> {
  int? organizationId;
  int? warehouseId;
  List<Map<String, Object?>> locations = [];
  final Set<int> selectedLocations = {};
  bool loadingLocations = false;

  @override
  void initState() {
    super.initState();
    organizationId = widget.organizations.first['id'] as int;
    warehouseId = widget.warehouses.first['id'] as int;
    loadLocations();
  }

  Future<void> loadLocations() async {
    final id = warehouseId;
    if (id == null) return;
    setState(() => loadingLocations = true);
    try {
      final rows = await widget.repository.storageLocations(id);
      if (!mounted || warehouseId != id) return;
      setState(() {
        locations = rows;
        selectedLocations
          ..clear()
          ..addAll(rows.map((row) => row['id'] as int));
        loadingLocations = false;
      });
    } catch (_) {
      if (mounted) setState(() => loadingLocations = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новая инвентаризация'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: organizationId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Организация'),
              items: widget.organizations
                  .map(
                    (row) => DropdownMenuItem(
                      value: row['id'] as int,
                      child: Text(
                        row['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => organizationId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: warehouseId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Склад'),
              items: widget.warehouses
                  .map(
                    (row) => DropdownMenuItem(
                      value: row['id'] as int,
                      child: Text(
                        row['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  warehouseId = value;
                  locations = [];
                  selectedLocations.clear();
                });
                loadLocations();
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Места хранения',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text(
              'Выберите одно или несколько. По умолчанию выбраны все.',
            ),
            if (loadingLocations)
              const LinearProgressIndicator()
            else if (locations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Для этого склада не настроены места хранения'),
              )
            else ...[
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: selectedLocations.length == locations.length,
                title: const Text('Все места хранения'),
                onChanged: (value) => setState(() {
                  selectedLocations
                    ..clear()
                    ..addAll(
                      value == true
                          ? locations.map((row) => row['id'] as int)
                          : const <int>[],
                    );
                }),
              ),
              ...locations.map((row) {
                final id = row['id'] as int;
                return CheckboxListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 12),
                  value: selectedLocations.contains(id),
                  title: Text(row['name'] as String),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      selectedLocations.add(id);
                    } else {
                      selectedLocations.remove(id);
                    }
                  }),
                );
              }),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed:
            loadingLocations ||
                organizationId == null ||
                warehouseId == null ||
                selectedLocations.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                _InventorySetupResult(
                  organizationId: organizationId!,
                  warehouseId: warehouseId!,
                  locationIds: selectedLocations.toList(),
                ),
              ),
        child: const Text('Создать'),
      ),
    ],
  );
}

class InventorySessionScreen extends StatefulWidget {
  const InventorySessionScreen({
    super.key,
    required this.repository,
    required this.sessionId,
  });

  final ReferenceDataRepository repository;
  final int sessionId;

  @override
  State<InventorySessionScreen> createState() => _InventorySessionScreenState();
}

class _InventorySessionScreenState extends State<InventorySessionScreen> {
  final TextEditingController quantityController = TextEditingController();
  final FocusNode quantityFocus = FocusNode();
  List<Map<String, Object?>> lines = [];
  Map<String, Object?>? session;
  int index = 0;
  bool loading = true;
  bool listMode = false;
  bool syncing = false;
  Future<void> _saveQueue = Future<void>.value();

  Map<String, Object?>? get current => lines.isEmpty ? null : lines[index];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final values = await Future.wait([
      widget.repository.inventoryLines(widget.sessionId),
      widget.repository.inventorySessions(),
    ]);
    if (!mounted) return;
    final allSessions = values[1];
    final found = allSessions.cast<Map<String, Object?>>().where(
      (row) => row['id'] == widget.sessionId,
    );
    setState(() {
      lines = values[0]
          .map((line) => Map<String, Object?>.from(line))
          .toList();
      session = found.isEmpty ? null : found.first;
      loading = false;
    });
    _showCurrentValue();
  }

  void _showCurrentValue() {
    final value = current?['actual_quantity'];
    quantityController.text = value == null
        ? ''
        : _formatQuantity((value as num).toDouble());
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && current != null) quantityFocus.requestFocus();
    });
  }

  String _formatQuantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  Future<void> _persistCurrent() async {
    final line = current;
    if (line == null) return;
    final text = quantityController.text.trim().replaceAll(',', '.');
    final value = text.isEmpty ? null : double.tryParse(text);
    if (text.isNotEmpty && (value == null || !value.isFinite || value < 0)) {
      throw const FormatException('Введите корректное количество');
    }
    await widget.repository.saveInventoryCount(line['id'] as int, value);
    final lineIndex = lines.indexWhere((item) => item['id'] == line['id']);
    if (mounted && lineIndex >= 0) {
      setState(() {
        lines[lineIndex] = {...lines[lineIndex], 'actual_quantity': value};
      });
    }
  }

  Future<void> _persistCurrentQuietly() {
    _saveQueue = _saveQueue.then((_) => _persistCurrent()).catchError((_) {
      // The visible value remains editable; validation is shown on navigation.
    });
    return _saveQueue;
  }

  Future<void> _move(int delta) async {
    try {
      await _saveQueue;
      await _persistCurrent();
      if (index + delta < 0 || index + delta >= lines.length) return;
      setState(() => index += delta);
      _showCurrentValue();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleListMode() async {
    await _saveQueue;
    await _persistCurrent();
    if (!mounted) return;
    setState(() => listMode = !listMode);
    if (!listMode) _showCurrentValue();
  }

  Future<void> _selectListItem(int selected) async {
    await _saveQueue;
    await _persistCurrent();
    if (!mounted) return;
    setState(() => index = selected);
    _showCurrentValue();
  }

  Future<void> _finish() async {
    await _saveQueue;
    await _persistCurrent();
    if (!mounted) return;
    final skipped = lines
        .where((line) => line['actual_quantity'] == null)
        .toList();
    if (skipped.isNotEmpty) {
      final zeroLineIds = await showDialog<Set<int>>(
        context: context,
        builder: (dialogContext) {
          final selected = skipped.map((line) => line['id'] as int).toSet();
          return StatefulBuilder(
            builder: (context, updateDialog) => AlertDialog(
              title: Text('Пропущено товаров: ${skipped.length}'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Отметьте товары, которые нужно добавить в инвентаризацию с количеством 0.',
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 260,
                      child: ListView(
                        children: skipped.map((line) {
                          final id = line['id'] as int;
                          return CheckboxListTile(
                            dense: true,
                            value: selected.contains(id),
                            title: Text(
                              line['product_name_snapshot'] as String,
                            ),
                            onChanged: (value) => updateDialog(() {
                              if (value == true) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, <int>{}),
                  child: const Text('Нет, не учитывать'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, selected),
                  child: const Text('Да, обнулить отмеченные'),
                ),
              ],
            ),
          );
        },
      );
      if (zeroLineIds == null) return;
      await widget.repository.resolveSkippedInventoryLines(
        widget.sessionId,
        zeroLineIds: zeroLineIds,
      );
      await load();
    }
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отправить инвентаризацию?'),
        content: Text(
          'Будет создан документ в МойСклад для склада «${session?['warehouse_name_snapshot']}». '
          'В документ попадут ${lines.where((line) => line['include_in_inventory'] == 1 && (line['actual_quantity'] != null || skipped.isNotEmpty)).length} позиций.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Продолжить позже'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => syncing = true);
    try {
      await widget.repository.syncInventorySession(widget.sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Инвентаризация создана в МойСклад')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось отправить. Черновик сохранён: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  @override
  void dispose() {
    quantityController.dispose();
    quantityFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session == null || lines.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Инвентаризация')),
        body: const Center(child: Text('В инвентаризации нет товаров')),
      );
    }
    final completed = session!['status'] == 'completed';
    final line = current!;
    final expected = line['expected_stock'];
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${index + 1} из ${lines.length}'),
            Text(
              '${session?['warehouse_name_snapshot']} • ${session?['organization_name_snapshot']}',
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: listMode ? 'Поштучный режим' : 'Список товаров',
            onPressed: _toggleListMode,
            icon: Icon(listMode ? Icons.view_agenda_outlined : Icons.list_alt),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: listMode
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    itemCount: lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, itemIndex) {
                      final item = lines[itemIndex];
                      final actual = item['actual_quantity'];
                      final book = item['expected_stock'];
                      return ListTile(
                        selected: itemIndex == index,
                        leading: CircleAvatar(child: Text('${itemIndex + 1}')),
                        title: Text(item['product_name_snapshot'] as String),
                        subtitle: Text(
                          'Учёт: ${book == null ? '—' : _formatQuantity((book as num).toDouble())} • Факт: ${actual == null ? 'не внесён' : _formatQuantity((actual as num).toDouble())} ${item['uom_name_snapshot']}',
                        ),
                        trailing: itemIndex == index
                            ? const Icon(Icons.edit)
                            : actual == null
                            ? const Icon(Icons.radio_button_unchecked)
                            : const Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                              ),
                        onTap: completed
                            ? null
                            : () => _selectListItem(itemIndex),
                      );
                    },
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    children: [
                      Text(
                        line['product_name_snapshot'] as String,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Остаток по учёту: ${expected == null ? '—' : '${_formatQuantity((expected as num).toDouble())} ${line['uom_name_snapshot']}'}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: quantityController,
                        focusNode: quantityFocus,
                        readOnly: true,
                        showCursor: true,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                        decoration: const InputDecoration(
                          labelText: 'Фактическое количество',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        line['uom_name_snapshot'] as String,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (completed)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text('Документ уже отправлен в МойСклад'),
                        ),
                    ],
                  ),
          ),
          if (!completed)
            QuantityKeyboard(
              controller: quantityController,
              enabled: !syncing,
              onChanged: () {
                _persistCurrentQuietly();
              },
            ),
          if (!completed)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  children: [
                    if (index > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: syncing ? null : () => _move(-1),
                          child: const Text('Назад'),
                        ),
                      ),
                    if (index > 0) const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: syncing
                            ? null
                            : index == lines.length - 1
                            ? _finish
                            : () => _move(1),
                        child: Text(
                          index == lines.length - 1
                              ? 'Завершить синхронизацию'
                              : 'Далее',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (syncing) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class MoySkladInventoryScreen extends StatefulWidget {
  const MoySkladInventoryScreen({
    super.key,
    required this.repository,
    required this.inventory,
  });

  final ReferenceDataRepository repository;
  final Map<String, dynamic> inventory;

  @override
  State<MoySkladInventoryScreen> createState() =>
      _MoySkladInventoryScreenState();
}

class _MoySkladInventoryScreenState extends State<MoySkladInventoryScreen> {
  List<Map<String, dynamic>> positions = [];
  bool loading = true;
  bool saving = false;
  String? error;

  String get inventoryId => widget.inventory['id']?.toString() ?? '';
  String get inventoryName =>
      widget.inventory['name']?.toString() ?? 'Инвентаризация';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (inventoryId.isEmpty) {
        throw StateError('МойСклад не вернул идентификатор документа.');
      }
      final rows = await widget.repository.moySkladInventoryPositions(
        inventoryId,
      );
      if (!mounted) return;
      setState(() {
        positions = rows;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  Future<void> editPosition(Map<String, dynamic> position) async {
    final positionId = position['id']?.toString();
    if (positionId == null || positionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У позиции нет идентификатора МойСклад')),
      );
      return;
    }
    final assortment = position['assortment'];
    final productName = assortment is Map
        ? assortment['name']?.toString() ?? 'Товар'
        : 'Товар';
    final controller = TextEditingController(
      text: (position['quantity'] as num?)?.toString() ?? '0',
    );
    final quantity = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(productName),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                readOnly: true,
                showCursor: true,
                decoration: const InputDecoration(
                  labelText: 'Учётное количество',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              QuantityKeyboard(
                controller: controller,
                onChanged: () {},
                height: 250,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
              if (value == null || !value.isFinite || value < 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Введите корректное неотрицательное число'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (quantity == null || !mounted) return;
    setState(() => saving = true);
    try {
      await widget.repository.updateMoySkladInventoryPosition(
        inventoryId: inventoryId,
        positionId: positionId,
        productName: productName,
        quantity: quantity,
        documentName: inventoryName,
      );
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Изменение сохранено в МойСклад')),
      );
    } catch (exception) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить позицию: $exception')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _inventoryRelatedName(widget.inventory['store']);
    final organization = _inventoryRelatedName(
      widget.inventory['organization'],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(inventoryName),
        actions: [
          IconButton(
            tooltip: 'Обновить из МойСклад',
            onPressed: loading || saving ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (saving) const LinearProgressIndicator(),
                ListTile(
                  title: Text(store.isEmpty ? 'Склад не указан' : store),
                  subtitle: Text(
                    organization.isEmpty
                        ? 'Документ загружен непосредственно из МойСклад'
                        : organization,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: positions.isEmpty
                      ? const Center(child: Text('В документе нет позиций'))
                      : ListView.separated(
                          itemCount: positions.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final position = positions[index];
                            final assortment = position['assortment'];
                            final productName = assortment is Map
                                ? assortment['name']?.toString() ?? 'Товар'
                                : 'Товар';
                            final quantity =
                                (position['quantity'] as num?)?.toString() ??
                                '—';
                            final calculated =
                                (position['calculatedQuantity'] as num?)
                                    ?.toString();
                            return ListTile(
                              title: Text(productName),
                              subtitle: Text(
                                'Учётное количество: $quantity'
                                '${calculated == null ? '' : ' • Расчётный остаток: $calculated'}',
                              ),
                              trailing: const Icon(Icons.edit_outlined),
                              onTap: saving
                                  ? null
                                  : () => editPosition(position),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
