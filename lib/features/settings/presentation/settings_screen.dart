import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../core/feedback/snackbar_service.dart';
import '../data/settings_repository.dart';
import 'color_picker_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.appVersion,
    required this.onThemeChanged,
    this.onSeedColorChanged,
    this.onTokenSaved,
    this.onTokenDeleted,
  });

  final SettingsRepository repository;
  final String appVersion;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<Color>? onSeedColorChanged;
  final VoidCallback? onTokenSaved;
  final VoidCallback? onTokenDeleted;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _tokenController = TextEditingController();
  final SnackbarService _snackbar = SnackbarService();
  ThemeMode _themeMode = ThemeMode.light;
  Color _seedColor = AppTheme.defaultSeedColor;
  bool _hasToken = false;
  bool _loading = true;
  bool _saving = false;
  bool _tokenDirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final theme = await widget.repository.loadTheme();
    final token = await widget.repository.loadToken();
    final seedColor = await widget.repository.loadSeedColor();
    if (!mounted) return;
    setState(() {
      _themeMode = theme;
      _seedColor = seedColor;
      _hasToken = token != null && token.isNotEmpty;
      if (_hasToken) _tokenController.text = '••••••••';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  void _message(String message) {
    _snackbar.show(context, message);
  }

  Widget _themeButton(ThemeMode mode, String label) {
    final selected = _themeMode == mode;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: selected
            ? FilledButton(
                onPressed: () => _changeTheme(mode),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: () => _changeTheme(mode),
                child: Text(label),
              ),
      ),
    );
  }

  Future<void> _pickSeedColor() async {
    final initialColor = _seedColor;
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => ColorPickerDialog(
        initialColor: initialColor,
        onPreviewChanged: (color) {
          if (!mounted) return;
          setState(() => _seedColor = color);
          widget.onSeedColorChanged?.call(color);
        },
      ),
    );
    if (!mounted) return;
    if (selectedColor == null) {
      setState(() => _seedColor = initialColor);
      widget.onSeedColorChanged?.call(initialColor);
      return;
    }
    try {
      await widget.repository.saveSeedColor(selectedColor);
      if (!mounted) return;
      setState(() => _seedColor = selectedColor);
      widget.onSeedColorChanged?.call(selectedColor);
    } catch (_) {
      setState(() => _seedColor = initialColor);
      widget.onSeedColorChanged?.call(initialColor);
      _message('Не удалось сохранить основной цвет');
    }
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    try {
      await widget.repository.saveTheme(mode);
      if (!mounted) return;
      setState(() => _themeMode = mode);
      widget.onThemeChanged(mode);
    } catch (_) {
      _message('Не удалось сохранить тему оформления');
    }
  }

  Future<void> _saveToken() async {
    if (_saving || _hasToken) return;
    setState(() => _saving = true);
    final result = await widget.repository.saveToken(_tokenController.text);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case SaveTokenResult.saved:
        setState(() {
          _hasToken = true;
          _tokenDirty = false;
          _tokenController.text = '••••••••';
        });
        widget.onTokenSaved?.call();
      case SaveTokenResult.emptyInput:
        _message('Введите API-токен');
      case SaveTokenResult.tokenAlreadyExists:
        setState(() {
          _hasToken = true;
          _tokenController.text = '••••••••';
          _tokenDirty = false;
        });
      case SaveTokenResult.storageError:
        _message('Не удалось сохранить API-токен');
    }
  }

  Future<bool> _confirm(
    String title,
    String message, {
    required String confirmLabel,
    String cancelLabel = 'Отмена',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteToken() async {
    if (!_hasToken) return;
    final confirmed = await _confirm(
      'Удалить API-токен?',
      'Сохранённый токен будет удалён с устройства.',
      confirmLabel: 'Удалить',
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.repository.deleteToken();
      if (!mounted) return;
      setState(() {
        _hasToken = false;
        _tokenDirty = false;
        _tokenController.clear();
      });
      widget.onTokenDeleted?.call();
    } catch (_) {
      _message('Не удалось удалить API-токен');
    }
  }

  Future<void> _resetSettings() async {
    final confirmed = await _confirm(
      'Сбросить настройки?',
      'Тема оформления, основной цвет и другие пользовательские настройки будут сброшены.',
      confirmLabel: 'Сбросить',
    );
    if (!confirmed || !mounted) return;

    var deleteToken = false;
    if (_hasToken) {
      deleteToken = await _confirm(
        'Удалить сохранённый API-токен?',
        'Подтвердите удаление токена отдельно от сброса настроек.',
        confirmLabel: 'Удалить',
        cancelLabel: 'Оставить токен',
      );
      if (!mounted) return;
    }

    try {
      await widget.repository.resetSettings(confirmTokenDeletion: deleteToken);
      if (!mounted) return;
      setState(() {
        _themeMode = ThemeMode.light;
        _seedColor = AppTheme.defaultSeedColor;
        if (deleteToken) {
          _hasToken = false;
          _tokenController.clear();
        } else if (_hasToken) {
          _tokenController.text = '••••••••';
        }
        _tokenDirty = false;
      });
      widget.onThemeChanged(ThemeMode.light);
      widget.onSeedColorChanged?.call(AppTheme.defaultSeedColor);
      if (deleteToken) widget.onTokenDeleted?.call();
      _message('Настройки сброшены');
    } catch (_) {
      _message('Не удалось сбросить настройки');
    }
  }

  Future<bool> _handleBack() async {
    if (!_tokenDirty) return true;
    return _confirm(
      'Несохранённые изменения',
      'Введённый API-токен не сохранён. Покинуть настройки?',
      confirmLabel: 'Покинуть',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_tokenDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_tokenDirty) return;
        final leave = await _handleBack();
        if (!mounted) return;
        if (leave) {
          Navigator.of(this.context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Настройки'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    'Тема оформления',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _themeButton(ThemeMode.light, 'Светлая'),
                      _themeButton(ThemeMode.dark, 'Тёмная'),
                      _themeButton(ThemeMode.system, 'Системная'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    key: const ValueKey('primary-color-setting'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Основной цвет'),
                    subtitle: Text(
                      '#${_seedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                    ),
                    trailing: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _seedColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                    onTap: _pickSeedColor,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'API-токен',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('api-token-field'),
                    controller: _tokenController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    readOnly: _hasToken,
                    onChanged: (_) => setState(() => _tokenDirty = true),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Введите API-токен',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_hasToken)
                    OutlinedButton(
                      onPressed: _deleteToken,
                      child: const Text('Удалить токен'),
                    )
                  else
                    FilledButton(
                      onPressed: _saving ? null : _saveToken,
                      child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
                    ),
                  const SizedBox(height: 28),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Журнал склада'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _message('Функция находится в разработке'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _resetSettings,
                    child: const Text('Сбросить настройки'),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      'Версия ${widget.appVersion}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
