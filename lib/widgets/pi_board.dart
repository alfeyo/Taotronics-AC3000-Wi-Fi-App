import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vector illustration of a Raspberry Pi 4 Model B (Argon's hardware), drawn
/// in a three-quarter top view. [active] lights the power/activity LEDs;
/// [dim] renders it muted when the gateway is unreachable.
class PiBoard extends StatefulWidget {
  const PiBoard({
    super.key,
    this.active = false,
    this.dim = false,
    this.size = 220,
  });

  final bool active;
  final bool dim;
  final double size;

  @override
  State<PiBoard> createState() => _PiBoardState();
}

class _PiBoardState extends State<PiBoard> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _blink.repeat();
  }

  @override
  void didUpdateWidget(PiBoard old) {
    super.didUpdateWidget(old);
    if (widget.active && !_blink.isAnimating) _blink.repeat();
    if (!widget.active && _blink.isAnimating) _blink.stop();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, _) => CustomPaint(
          size: Size(widget.size, widget.size * 0.72),
          painter: _PiPainter(
            active: widget.active,
            dim: widget.dim,
            phase: _blink.value,
          ),
        ),
      ),
    );
  }
}

class _PiPainter extends CustomPainter {
  _PiPainter({required this.active, required this.dim, required this.phase});

  final bool active;
  final bool dim;
  final double phase;

  Color _c(int v) {
    final c = Color(v);
    return dim ? Color.lerp(c, const Color(0xff2a2b30), 0.55)! : c;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Board in a slight perspective: draw on a skewed canvas.
    canvas.save();
    canvas.translate(w * 0.5, h * 0.52);
    canvas.scale(1.0, 0.82);
    canvas.rotate(-math.pi / 28);
    final bw = w * 0.86, bh = bw * 0.66;
    final board = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: bw, height: bh),
      Radius.circular(bw * 0.04),
    );

    // Shadow + PCB edge thickness.
    canvas.drawRRect(
      board.shift(Offset(0, bh * 0.07)),
      Paint()
        ..color = Colors.black.withValues(alpha: dim ? 0.25 : 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(
      board.shift(Offset(0, bh * 0.025)),
      Paint()..color = _c(0xff0d4a2a),
    );
    canvas.drawRRect(
      board,
      Paint()
        ..shader = LinearGradient(
          colors: [_c(0xff1f8a4c), _c(0xff16693a)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(board.outerRect),
    );

    final l = -bw / 2, t = -bh / 2;
    Rect r(double x, double y, double rw, double rh) =>
        Rect.fromLTWH(l + bw * x, t + bh * y, bw * rw, bh * rh);
    final metal = Paint()
      ..shader = LinearGradient(
        colors: [_c(0xffd9dce2), _c(0xff9ea3ad)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(r(0, 0, 1, 1));
    final black = Paint()..color = _c(0xff1b1c20);

    // Mounting holes.
    for (final p in [
      const Offset(0.05, 0.08),
      const Offset(0.66, 0.08),
      const Offset(0.05, 0.92),
      const Offset(0.66, 0.92),
    ]) {
      final c = Offset(l + bw * p.dx, t + bh * p.dy);
      canvas.drawCircle(c, bw * 0.024, Paint()..color = _c(0xffc8a24a));
      canvas.drawCircle(c, bw * 0.012, Paint()..color = _c(0xff0f2c1c));
    }
    // GPIO header (2 x 20 pins) along the top edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.1, 0.03, 0.52, 0.1),
        const Radius.circular(2),
      ),
      black,
    );
    final pin = Paint()..color = _c(0xffd8b45a);
    for (var i = 0; i < 20; i++) {
      for (var j = 0; j < 2; j++) {
        canvas.drawRect(
          r(0.115 + i * 0.0253, 0.045 + j * 0.04, 0.012, 0.022),
          pin,
        );
      }
    }
    // SoC with heat spreader and RAM.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.26, 0.32, 0.2, 0.3),
        const Radius.circular(3),
      ),
      metal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.28, 0.35, 0.16, 0.24),
        const Radius.circular(2),
      ),
      Paint()..color = _c(0xffb8bcc4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.5, 0.36, 0.13, 0.22),
        const Radius.circular(2),
      ),
      black,
    );
    // Wi-Fi/BT module shield.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.06, 0.2, 0.15, 0.17),
        const Radius.circular(2),
      ),
      metal,
    );
    // USB-C, 2x micro-HDMI and audio along the bottom edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.1, 0.86, 0.08, 0.12),
        const Radius.circular(2),
      ),
      metal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.24, 0.87, 0.07, 0.1),
        const Radius.circular(2),
      ),
      metal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.36, 0.87, 0.07, 0.1),
        const Radius.circular(2),
      ),
      metal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.5, 0.85, 0.07, 0.13),
        const Radius.circular(6),
      ),
      black,
    );
    // USB 2.0, USB 3.0 (blue tongues) and Gigabit Ethernet on the right edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.78, 0.04, 0.24, 0.26),
        const Radius.circular(2),
      ),
      metal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.78, 0.36, 0.24, 0.26),
        const Radius.circular(2),
      ),
      metal,
    );
    for (final y in [0.4, 0.5]) {
      canvas.drawRect(r(0.82, y, 0.17, 0.04), Paint()..color = _c(0xff2f6fd6));
    }
    for (final y in [0.08, 0.18]) {
      canvas.drawRect(r(0.82, y, 0.17, 0.04), black);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        r(0.76, 0.67, 0.26, 0.3),
        const Radius.circular(2),
      ),
      metal,
    );
    canvas.drawRect(r(0.8, 0.73, 0.19, 0.18), black);

    // Power (red) and activity (green) LEDs.
    final ledOn = active ? 1.0 : 0.0;
    final act = active
        ? (0.4 +
              0.6 *
                  (0.5 + 0.5 * math.sin(phase * math.pi * 2 * 3)).clamp(
                    0.0,
                    1.0,
                  ))
        : 0.0;
    void led(Rect rect, Color color, double level) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()..color = Color.lerp(_c(0xff3a3a3a), color, level)!,
      );
      if (level > 0 && !dim) {
        canvas.drawCircle(
          rect.center,
          bw * 0.03,
          Paint()
            ..color = color.withValues(alpha: 0.35 * level)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
    }

    led(r(0.035, 0.72, 0.028, 0.05), const Color(0xffff4d3d), ledOn);
    led(r(0.035, 0.79, 0.028, 0.05), const Color(0xff5cff7a), act);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PiPainter old) =>
      old.active != active || old.dim != dim || (active && old.phase != phase);
}
