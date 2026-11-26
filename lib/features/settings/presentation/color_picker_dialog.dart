import 'package:material_ui/material_ui.dart';

import 'hsv_color_picker.dart';

class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.onPreviewChanged,
  });

  final Color initialColor;
  final ValueChanged<Color> onPreviewChanged;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Основной цвет'),
      content: SingleChildScrollView(
        child: HsvColorPicker(
          initialColor: _selectedColor,
          onChanged: (color) {
            setState(() => _selectedColor = color);
            widget.onPreviewChanged(color);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('apply-primary-color'),
          onPressed: () => Navigator.pop(context, _selectedColor),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}
