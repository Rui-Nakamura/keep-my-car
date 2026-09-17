import 'package:flutter/material.dart';

/// A route-local snapshot. Acknowledgement never changes this visit's content.
class UpdateFeedback extends StatefulWidget {
  const UpdateFeedback({
    super.key,
    required this.pending,
    required this.duration,
    required this.builder,
    this.onViewed,
  });

  final bool pending;
  final Duration duration;
  final VoidCallback? onViewed;
  final Widget Function(BuildContext context, double emphasis) builder;

  @override
  State<UpdateFeedback> createState() => _UpdateFeedbackState();
}

class _UpdateFeedbackState extends State<UpdateFeedback>
    with SingleTickerProviderStateMixin {
  late final bool _pending = widget.pending;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    if (_pending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onViewed?.call();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = 1;
    if (!_started) {
      _started = true;
      if (_pending && !_reduceMotion) _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => widget.builder(
      context,
      !_pending
          ? 0
          : _reduceMotion
          ? 1
          : 1 - _controller.value,
    ),
  );
}
