import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lerua_zakup/features/settings/presentation/hsv_color_picker.dart';

void main() {
  testWidgets('hue wheel and saturation/value area emit selected colors', (
    tester,
  ) async {
    final selected = <Color>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HsvColorPicker(
            initialColor: const Color(0xFF2E7D32),
            onChanged: selected.add,
          ),
        ),
      ),
    );

    final wheel = find.byKey(const ValueKey('hue-wheel'));
    final wheelTop = tester.getTopLeft(wheel) + const Offset(130, 16);
    await tester.tapAt(wheelTop);
    await tester.pump();
    expect(selected, isNotEmpty);
    expect(HSVColor.fromColor(selected.last).hue, closeTo(0, 8));

    final area = find.byKey(const ValueKey('saturation-value-picker'));
    final areaTopLeft = tester.getTopLeft(area);
    await tester.tapAt(areaTopLeft + const Offset(250, 4));
    await tester.pump();
    expect(HSVColor.fromColor(selected.last).saturation, greaterThan(0.9));
    expect(HSVColor.fromColor(selected.last).value, greaterThan(0.9));
  });

  testWidgets('shows the selected color as a hex value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HsvColorPicker(
            initialColor: const Color(0xFF2E7D32),
            onChanged: _ignoreColor,
          ),
        ),
      ),
    );
    expect(find.text('#2E7D32'), findsOneWidget);
  });
}

void _ignoreColor(Color color) {}
