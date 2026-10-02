import 'dart:async';

import 'package:flutter/material.dart';

/// Each change to a nonzero notificationId is a new, transient UI event.
/// The initial value is a baseline: mounting or rebuilding cannot replay it.
class ScreenSuccessFeedback extends StatefulWidget {
  const ScreenSuccessFeedback({
    super.key,
    required this.notificationId,
    required this.child,
  });

  final int notificationId;
  final Widget child;

  @override
  State<ScreenSuccessFeedback> createState() => _ScreenSuccessFeedbackState();
}

class _ScreenSuccessFeedbackState extends State<ScreenSuccessFeedback>
    with SingleTickerProviderStateMixin {
  static const duration = Duration(milliseconds: 2200);
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: duration,
  );
  Timer? staticOutlineTimer;
  bool staticOutline = false;

  @override
  void didUpdateWidget(ScreenSuccessFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notificationId == 0 ||
        widget.notificationId == oldWidget.notificationId) {
      return;
    }
    staticOutlineTimer?.cancel();
    controller.stop();
    staticOutline = MediaQuery.disableAnimationsOf(context);
    if (staticOutline) {
      // Reduced motion gets a brief stationary outline, never a pulse or fade.
      staticOutlineTimer = Timer(duration, () {
        if (mounted) setState(() => staticOutline = false);
      });
    } else {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    staticOutlineTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => staticOutline || controller.isAnimating
                ? RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('screen-success-outline'),
                      painter: _SuccessOutlinePainter(
                        staticOutline
                            ? 1
                            : 1 - Curves.easeInOut.transform(controller.value),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ],
  );
}

class _SuccessOutlinePainter extends CustomPainter {
  const _SuccessOutlinePainter(this.emphasis);
  final double emphasis;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide < 16) return;
    final bounds = Offset.zero & size;
    final outline = RRect.fromRectAndRadius(
      bounds.deflate(6),
      const Radius.circular(16),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF397EA8).withValues(alpha: emphasis * 0.95),
          const Color(0xFF3E756F).withValues(alpha: emphasis * 0.95),
        ],
      ).createShader(bounds);
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRRect(
      outline,
      paint..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(outline, paint..maskFilter = null);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SuccessOutlinePainter oldDelegate) =>
      emphasis != oldDelegate.emphasis;
}
