import 'package:flutter/material.dart';

/// Shared quantity keypad used by purchasing and inventory workflows.
/// The calculator edits the same field as the numeric keypad; only a
/// successfully evaluated expression becomes a numeric quantity.
class QuantityKeyboard extends StatefulWidget {
  const QuantityKeyboard({
    super.key,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
    this.height = 276,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool enabled;
  final double height;

  @override
  State<QuantityKeyboard> createState() => _QuantityKeyboardState();
}

class _QuantityKeyboardState extends State<QuantityKeyboard> {
  bool _calculatorMode = false;

  void _write(String value) {
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged();
  }

  void _press(String key) {
    if (!widget.enabled) return;
    final text = widget.controller.text;
    if (key == '=') {
      try {
        final result = _ExpressionParser(text).parse();
        if (!result.isFinite) throw const FormatException();
        final rounded = double.parse(result.toStringAsFixed(8));
        final output = rounded == rounded.roundToDouble()
            ? rounded.toInt().toString()
            : rounded.toString().replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
        _write(output);
      } on FormatException {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Проверь математическое выражение.')),
        );
      } on UnsupportedError {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нельзя делить на ноль.')),
        );
      }
      return;
    }

    String updated;
    if (key == 'C') {
      updated = '';
    } else if (key == '⌫') {
      updated = text.isEmpty ? '' : text.substring(0, text.length - 1);
    } else if (key == ',' || key == '.') {
      final normalized = text.replaceAll(',', '.');
      final lastNumber = normalized.split(RegExp(r'[+\-×÷() ]')).last;
      if (lastNumber.contains('.')) return;
      updated = '${text.isEmpty ? '0' : text}${key == ',' ? ',' : '.'}';
    } else {
      updated = '$text$key';
    }
    _write(updated);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final keys = _calculatorMode
        ? const ['C', '(', ')', '÷', '7', '8', '9', '×', '4', '5', '6', '−', '1', '2', '3', '+', '⌫', '0', ',', '=']
        : const ['7', '8', '9', '4', '5', '6', '1', '2', '3', ',', '0', '⌫'];

    return SizedBox(
      height: widget.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  Icon(
                    _calculatorMode ? Icons.calculate_rounded : Icons.dialpad_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _calculatorMode ? 'Калькулятор' : 'Цифровая клавиатура',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: _calculatorMode
                        ? 'Обычная клавиатура'
                        : 'Открыть калькулятор',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.enabled
                        ? () => setState(() => _calculatorMode = !_calculatorMode)
                        : null,
                    icon: Icon(
                      _calculatorMode
                          ? Icons.keyboard_alt_outlined
                          : Icons.calculate_outlined,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = _calculatorMode ? 4 : 3;
                  final rows = (keys.length / columns).ceil();
                  const spacing = 6.0;
                  final cellWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) / columns;
                  final cellHeight =
                      (constraints.maxHeight - spacing * (rows - 1)) / rows;
                  final aspectRatio = cellWidth / cellHeight;
                  return GridView.count(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    crossAxisCount: columns,
                    childAspectRatio: aspectRatio,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    children: [
                      for (final key in keys)
                        FilledButton.tonal(
                          onPressed: widget.enabled ? () => _press(key) : null,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            key,
                            style: TextStyle(
                              fontSize: key.length > 1 ? 18 : 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpressionParser {
  _ExpressionParser(String source)
      : _source = source.replaceAll(',', '.').replaceAll('×', '*').replaceAll('÷', '/').replaceAll('−', '-').replaceAll(' ', '');

  final String _source;
  int _index = 0;

  double parse() {
    if (_source.isEmpty) throw const FormatException();
    final result = _expression();
    if (_index != _source.length) throw const FormatException();
    return result;
  }

  double _expression() {
    var value = _term();
    while (_index < _source.length) {
      final operator = _source[_index];
      if (operator != '+' && operator != '-') break;
      _index++;
      final right = _term();
      value = operator == '+' ? value + right : value - right;
    }
    return value;
  }

  double _term() {
    var value = _factor();
    while (_index < _source.length) {
      final operator = _source[_index];
      if (operator != '*' && operator != '/') break;
      _index++;
      final right = _factor();
      if (operator == '/' && right == 0) throw UnsupportedError('division by zero');
      value = operator == '*' ? value * right : value / right;
    }
    return value;
  }

  double _factor() {
    if (_index >= _source.length) throw const FormatException();
    final current = _source[_index];
    if (current == '+' || current == '-') {
      _index++;
      final value = _factor();
      return current == '-' ? -value : value;
    }
    if (current == '(') {
      _index++;
      final value = _expression();
      if (_index >= _source.length || _source[_index] != ')') {
        throw const FormatException();
      }
      _index++;
      return value;
    }

    final start = _index;
    var decimalSeen = false;
    while (_index < _source.length) {
      final char = _source[_index];
      if (char == '.') {
        if (decimalSeen) throw const FormatException();
        decimalSeen = true;
        _index++;
      } else if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        _index++;
      } else {
        break;
      }
    }
    if (start == _index) throw const FormatException();
    final value = double.tryParse(_source.substring(start, _index));
    if (value == null) throw const FormatException();
    return value;
  }
}
