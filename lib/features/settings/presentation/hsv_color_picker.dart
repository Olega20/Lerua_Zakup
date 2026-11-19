import 'dart:math' as math;

import 'package:flutter/material.dart';

class HsvColorPicker extends StatefulWidget {
  const HsvColorPicker({
    super.key,
    required this.initialColor,
    required this.onChanged,
  });

  final Color initialColor;
  final ValueChanged<Color> onChanged;

  @override
  State<HsvColorPicker> createState() => _HsvColorPickerState();
}

class _HsvColorPickerState extends State<HsvColorPicker> {
  late HSVColor _hsvColor;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.initialColor);
  }

  void _updateHue(Offset position, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final delta = position - center;
    final angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    final hue = (angle * 180 / math.pi + 360) % 360;
    _update(_hsvColor.withHue(hue));
  }

  void _updateSaturationValue(Offset position, Size size) {
    final saturation = (position.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - position.dy / size.height).clamp(0.0, 1.0);
    _update(_hsvColor.withSaturation(saturation).withValue(value));
  }

  void _update(HSVColor next) {
    setState(() => _hsvColor = next);
    widget.onChanged(next.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsvColor.toColor();
    final hex = color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .toUpperCase();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          height: 260,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                key: const ValueKey('hue-wheel'),
                behavior: HitTestBehavior.opaque,
                onPanDown: (details) => _updateHue(details.localPosition, size),
                onPanUpdate: (details) =>
                    _updateHue(details.localPosition, size),
                child: CustomPaint(
                  painter: _HueWheelPainter(hue: _hsvColor.hue),
                  size: size,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 260,
          height: 132,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                key: const ValueKey('saturation-value-picker'),
                behavior: HitTestBehavior.opaque,
                onPanDown: (details) =>
                    _updateSaturationValue(details.localPosition, size),
                onPanUpdate: (details) =>
                    _updateSaturationValue(details.localPosition, size),
                child: CustomPaint(
                  painter: _SaturationValuePainter(
                    hueColor: HSVColor.fromAHSV(
                      1,
                      _hsvColor.hue,
                      1,
                      1,
                    ).toColor(),
                    saturation: _hsvColor.saturation,
                    value: _hsvColor.value,
                  ),
                  size: size,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '#${hex.substring(2)}',
              key: const ValueKey('selected-color-hex'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ],
    );
  }
}

class _HueWheelPainter extends CustomPainter {
  const _HueWheelPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 16;
    final colors = List<Color>.generate(
      13,
      (index) => HSVColor.fromAHSV(1, (index % 12) * 30, 1, 1).toColor(),
    );
    final rect = Rect.fromCircle(center: center, radius: radius);
    final wheelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..shader = SweepGradient(
        colors: colors,
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawCircle(center, radius, wheelPaint);

    final angle = (hue - 90) * math.pi / 180;
    final marker = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas.drawCircle(marker, 10, Paint()..color = Colors.white);
    canvas.drawCircle(
      marker,
      8,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HueWheelPainter oldDelegate) => oldDelegate.hue != hue;
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter({
    required this.hueColor,
    required this.saturation,
    required this.value,
  });

  final Color hueColor;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(rect, Paint()..color = hueColor);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Colors.black],
        ).createShader(rect),
    );
    canvas.restore();

    final marker = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(marker, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      marker,
      7,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) =>
      oldDelegate.hueColor != hueColor ||
      oldDelegate.saturation != saturation ||
      oldDelegate.value != value;
}