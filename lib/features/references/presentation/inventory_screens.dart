import 'package:flutter/material.dart';

import '../data/reference_data_repository.dart';

class InventoryHomeScreen extends StatefulWidget {
  const InventoryHomeScreen({super.key, required this.repository});
  final ReferenceDataRepository repository;

  @override
  State<InventoryHomeScreen> createState() => _InventoryHomeScreenState();
}

class _InventoryHomeScreenState extends State<InventoryHomeScreen> {
  List<Map<String, Object?>> sessions = [];
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
      if (!mounted) return;
      setState(() {
        sessions = values[0];
        organizations = values[1];
        warehouses = values[2];
        loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить инвентаризации: $error')),
        );
      }
    }
  }

  Future<void> createDraft() async {
    if (organizations.isEmpty || warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала синхронизируйте организации и склады')),
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
        : sessions.isEmpty
        ? const Center(child: Text('Инвентаризаций пока нет'))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final session = sessions[index];
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
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openSession(session['id'] as int),
                ),
              );
            },
          ),
  );
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
                  .map((row) => DropdownMenuItem(
                        value: row['id'] as int,
                        child: Text(row['name'] as String, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => organizationId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: warehouseId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Склад'),
              items: widget.warehouses
                  .map((row) => DropdownMenuItem(
                        value: row['id'] as int,
                        child: Text(row['name'] as String, overflow: TextOverflow.ellipsis),
                      ))
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
            const Text('Места хранения', style: TextStyle(fontWeight: FontWeight.w600)),
            const Text('Выберите одно или несколько. По умолчанию выбраны все.'),
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
                    ..addAll(value == true
                        ? locations.map((row) => row['id'] as int)
                        : const <int>[]);
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
        onPressed: loadingLocations ||
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
  bool calculatorMode = false;
  bool syncing = false;
  double? accumulator;
  String? pendingOperator;
  bool replaceOnNextDigit = false;
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
      lines = values[0];
      session = found.isEmpty ? null : found.first;
      loading = false;
    });
    _showCurrentValue();
  }

  void _showCurrentValue() {
    final value = current?['actual_quantity'];
    quantityController.text = value == null ? '' : _formatQuantity((value as num).toDouble());
    accumulator = null;
    pendingOperator = null;
    replaceOnNextDigit = false;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && current != null) quantityFocus.requestFocus();
    });
  }

  String _formatQuantity(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  Future<void> _persistCurrent() async {
    final line = current;
    if (line == null) return;
    final text = quantityController.text.trim().replaceAll(',', '.');
    final value = text.isEmpty ? null : double.tryParse(text);
    if (text.isNotEmpty && (value == null || !value.isFinite || value < 0)) {
      throw const FormatException('Введите корректное количество');
    }
    await widget.repository.saveInventoryCount(line['id'] as int, value);
    line['actual_quantity'] = value;
  }

  void _digit(String value) {
    final text = quantityController.text;
    if (value == '.' && text.contains('.')) return;
    final next = replaceOnNextDigit ? value : text.isEmpty && value == '.' ? '0.' : '$text$value';
    replaceOnNextDigit = false;
    quantityController.text = next;
    quantityController.selection = TextSelection.collapsed(offset: next.length);
    _persistCurrentQuietly();
    setState(() {});
  }

  void _backspace() {
    final text = quantityController.text;
    if (text.isEmpty) return;
    quantityController.text = text.substring(0, text.length - 1);
    quantityController.selection = TextSelection.collapsed(offset: quantityController.text.length);
    _persistCurrentQuietly();
    setState(() {});
  }

  Future<void> _persistCurrentQuietly() {
    _saveQueue = _saveQueue.then((_) => _persistCurrent()).catchError((_) {
      // The visible value remains editable; validation is shown on navigation.
    });
    return _saveQueue;
  }

  void _clear() {
    quantityController.clear();
    _persistCurrentQuietly();
    setState(() {});
  }

  void _calculatorOperator(String op) {
    final value = double.tryParse(quantityController.text.replaceAll(',', '.'));
    if (value == null) return;
    if (accumulator != null && pendingOperator != null && !replaceOnNextDigit) {
      _calculate();
    }
    accumulator = double.tryParse(quantityController.text.replaceAll(',', '.')) ?? value;
    pendingOperator = op;
    replaceOnNextDigit = true;
  }

  void _calculate() {
    final right = double.tryParse(quantityController.text.replaceAll(',', '.'));
    final left = accumulator;
    final op = pendingOperator;
    if (right == null || left == null || op == null) return;
    final result = switch (op) {
      '+' => left + right,
      '−' => left - right,
      '×' => left * right,
      '÷' => right == 0 ? double.nan : left / right,
      _ => right,
    };
    if (!result.isFinite || result < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Результат должен быть неотрицательным числом')),
      );
      return;
    }
    quantityController.text = _formatQuantity(result);
    quantityController.selection = TextSelection.collapsed(offset: quantityController.text.length);
    accumulator = null;
    pendingOperator = null;
    replaceOnNextDigit = true;
    _persistCurrentQuietly();
    setState(() {});
  }

  Future<void> _move(int delta) async {
    try {
      await _saveQueue;
      await _persistCurrent();
      if (index + delta < 0 || index + delta >= lines.length) return;
      setState(() => index += delta);
      _showCurrentValue();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _openList() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .82,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Товары инвентаризации', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: lines.length,
                  itemBuilder: (context, i) {
                    final line = lines[i];
                    final quantity = line['actual_quantity'];
                    return ListTile(
                      selected: i == index,
                      title: Text(line['product_name_snapshot'] as String),
                      subtitle: Text(quantity == null
                          ? 'Не посчитан'
                          : 'Факт: ${_formatQuantity((quantity as num).toDouble())}'),
                      trailing: quantity == null
                          ? const Icon(Icons.radio_button_unchecked)
                          : const Icon(Icons.check_circle_outline, color: Colors.green),
                      onTap: () => Navigator.pop(sheetContext, i),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await _saveQueue;
      await _persistCurrent();
      setState(() => index = selected);
      _showCurrentValue();
    }
  }

  Future<void> _finish() async {
    await _saveQueue;
    await _persistCurrent();
    final skipped = lines.where((line) => line['actual_quantity'] == null).toList();
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
                    const Text('Отметьте товары, которые нужно добавить в инвентаризацию с количеством 0.'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 260,
                      child: ListView(
                        children: skipped.map((line) {
                          final id = line['id'] as int;
                          return CheckboxListTile(
                            dense: true,
                            value: selected.contains(id),
                            title: Text(line['product_name_snapshot'] as String),
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
          SnackBar(content: Text('Не удалось отправить. Черновик сохранён: $error')),
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
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
        title: Text('${index + 1} из ${lines.length}'),
        actions: [
          IconButton(
            tooltip: 'Список товаров',
            onPressed: _openList,
            icon: const Icon(Icons.list_alt),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
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
          if (!completed) _buildKeyboard(context),
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
                        child: Text(index == lines.length - 1
                            ? 'Завершить синхронизацию'
                            : 'Далее'),
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

  Widget _buildKeyboard(BuildContext context) {
    final keys = calculatorMode
        ? ['7', '8', '9', '÷', '4', '5', '6', '×', '1', '2', '3', '−', 'C', '0', '.', '+', '⌫', '=']
        : ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', '.', '⌫'];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  calculatorMode = !calculatorMode;
                  accumulator = null;
                  pendingOperator = null;
                }),
                icon: Icon(calculatorMode ? Icons.dialpad : Icons.calculate_outlined),
                label: Text(calculatorMode ? 'Клавиатура' : 'Калькулятор'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: keys.map((key) {
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 64) / 4,
                height: 42,
                child: FilledButton.tonal(
                  onPressed: syncing
                      ? null
                      : () {
                          if (key == 'C') {
                            _clear();
                          } else if (key == '⌫') {
                            _backspace();
                          } else if (key == '=') {
                            _calculate();
                          } else if (['+', '−', '×', '÷'].contains(key)) {
                            _calculatorOperator(key);
                          } else {
                            _digit(key);
                          }
                        },
                  child: Text(key, style: const TextStyle(fontSize: 18)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
