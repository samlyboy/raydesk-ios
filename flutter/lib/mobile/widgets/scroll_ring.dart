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
  static const double _arrowSize = 44.0;
  static const double _arrowGap = 8.0;
  static const double _arrowSpacing = 12.0;

  bool _open = false;
  bool _ignorePointerUp = false;
  String? _pressedArrowKey;
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

  /// 上/下键的点击区域：圆环右侧，两个 _arrowSize 圆按钮，间隔 _arrowSpacing。
  /// 按钮中心 x = center.x + radius + 12(半环宽) + _arrowGap + _arrowSize/2
  List<Rect> _arrowRects(Offset center, double radius) {
    final left = center.dx + radius + 12 + _arrowGap;
    final top = center.dy - _arrowSize - _arrowSpacing / 2;
    return [
      Rect.fromLTWH(left, top, _arrowSize, _arrowSize),
      Rect.fromLTWH(left, top + _arrowSize + _arrowSpacing, _arrowSize, _arrowSize),
    ];
  }

  bool _onArrow(Offset p, Offset center, double radius) =>
      _arrowRects(center, radius).any((r) => r.contains(p));

  void _sendArrowKey(String name) {
    widget.ffi.inputModel.inputKey(name);
  }

  Widget _arrowButton(IconData icon, String keyName, Offset center, double radius) {
    final rect = _arrowRects(center, radius)[keyName == 'VK_UP' ? 0 : 1];
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: _arrowSize,
      height: _arrowSize,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade600,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  void _onDown(PointerDownEvent e, Offset center, double radius) {
    final arrows = _arrowRects(center, radius);
    if (arrows[0].contains(e.position)) {
      _ignorePointerUp = true;
      _pressedArrowKey = 'VK_UP';
      return;
    }
    if (arrows[1].contains(e.position)) {
      _ignorePointerUp = true;
      _pressedArrowKey = 'VK_DOWN';
      return;
    }
    _ignorePointerUp = false;
    _pressedArrowKey = null;
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
    final center = Offset(size.width / 2, max(180.0, size.height - 230));
    // 圆环缩到原来的 2/3：原 min(96, max(64, w*0.2))
    final radius = min(64.0, max(42.0, size.width * (0.2 * 2 / 3)));

    if (!_open) return const SizedBox.shrink();

    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _onDown(e, center, radius),
        onPointerMove: (e) => _onMove(e, center),
        onPointerUp: (e) {
          if (_ignorePointerUp) {
            final key = _pressedArrowKey;
            _ignorePointerUp = false;
            _pressedArrowKey = null;
            // 只在按下的同一个按钮内抬起才发送，防止误触。
            if (key != null && _onArrow(e.position, center, radius)) {
              final expected = e.position.dy < center.dy ? 'VK_UP' : 'VK_DOWN';
              if (key == expected) _sendArrowKey(key);
            }
            return;
          }
          _hide();
        },
        onPointerCancel: (_) {
          _ignorePointerUp = false;
          _pressedArrowKey = null;
          _hide();
        },
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
            _arrowButton(Icons.keyboard_arrow_up, 'VK_UP', center, radius),
            _arrowButton(Icons.keyboard_arrow_down, 'VK_DOWN', center, radius),
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
      ..strokeWidth = 24;
    canvas.drawCircle(center, radius, ring);

    final dot = Paint()..color = _accent;
    canvas.drawCircle(
      center + Offset(radius * cos(angle), radius * sin(angle)),
      18,
      dot,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrollRingPainter old) =>
      old.center != center || old.radius != radius || old.angle != angle;
}
