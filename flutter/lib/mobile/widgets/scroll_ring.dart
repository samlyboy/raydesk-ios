import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/model.dart';

const Color _accent = Color(0xFFFFA726);

/// iOS touch wheel: tap the floating button, then drag along the ring.
/// Clockwise sends mouse-wheel-down, counter-clockwise sends mouse-wheel-up.
class ScrollRing extends StatefulWidget {
  final FFI ffi;
  /// 每次自增触发打开；按钮在底部工具栏，控件本身不绘制按钮。
  final ValueNotifier<int> openSignal;

  const ScrollRing({
    super.key,
    required this.ffi,
    required this.openSignal,
  });

  @override
  State<ScrollRing> createState() => _ScrollRingState();
}

class _ScrollRingState extends State<ScrollRing> {
  static const int _dotCount = 60;
  static const double _stepAngle = 2 * pi / _dotCount;

  bool _open = false;
  double? _lastAngle;
  double _pointerAngle = -pi / 2;

  @override
  void initState() {
    super.initState();
    widget.openSignal.addListener(_onOpenSignal);
  }

  void _onOpenSignal() {
    if (!_open) _show();
  }

  void _show() {
    setState(() {
      _open = true;
      _lastAngle = null;
      _pointerAngle = -pi / 2;
    });
    widget.ffi.cursorModel.blockEvents = true;
  }

  void _hide() {
    if (!_open) return;
    setState(() {
      _open = false;
      _lastAngle = null;
    });
    widget.ffi.cursorModel.blockEvents = false;
  }

  @override
  void dispose() {
    widget.openSignal.removeListener(_onOpenSignal);
    if (_open) widget.ffi.cursorModel.blockEvents = false;
    super.dispose();
  }

  double _rawAngle(Offset point, Offset center) =>
      atan2(point.dy - center.dy, point.dx - center.dx);

  void _onDown(PointerDownEvent e, Offset center, double radius) {
    final distance = (e.position - center).distance;
    if ((distance - radius).abs() > 47) {
      _hide();
      return;
    }
    final snapped =
        (_rawAngle(e.position, center) / _stepAngle).round() * _stepAngle;
    _lastAngle = snapped;
    setState(() => _pointerAngle = snapped);
  }

  void _onMove(PointerMoveEvent e, Offset center) {
    final last = _lastAngle;
    if (last == null) return;
    final snapped =
        (_rawAngle(e.position, center) / _stepAngle).round() * _stepAngle;
    if (snapped == last) return;

    var delta = snapped - last;
    if (delta.abs() > pi) {
      delta += delta > 0 ? -2 * pi : 2 * pi;
    }
    _lastAngle = snapped;
    setState(() => _pointerAngle = snapped);

    // Screen coordinates: atan2 grows clockwise.
    // Matches official floating_mouse.dart: clockwise -> wheel down (-1).
    widget.ffi.inputModel.scroll(delta > 0 ? -1 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, max(180.0, size.height - 280));
    // 圆环缩到原来的 2/3：原 min(96, max(64, w*0.2))
    final radius = min(64.0, max(42.0, size.width * (0.2 * 2 / 3)));

    if (!_open) return const SizedBox.shrink();

    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _onDown(e, center, radius),
        onPointerMove: (e) => _onMove(e, center),
        onPointerUp: (_) => _hide(),
        onPointerCancel: (_) => _hide(),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0x33000000)),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _ScrollRingPainter(
                  center: center,
                  radius: radius,
                  angle: _pointerAngle,
                ),
              ),
            ),
            Positioned(
              right: 18,
              top: 18,
              child: GestureDetector(
                onTap: _hide,
                child: const Icon(Icons.close, color: Colors.white70, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollRingPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double angle;

  const _ScrollRingPainter({
    required this.center,
    required this.radius,
    required this.angle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..color = Colors.grey.shade600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawCircle(center, radius, ring);

    final dot = Paint()..color = _accent;
    canvas.drawCircle(
      center + Offset(radius * cos(angle), radius * sin(angle)),
      9,
      dot,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrollRingPainter old) =>
      old.center != center || old.radius != radius || old.angle != angle;
}
