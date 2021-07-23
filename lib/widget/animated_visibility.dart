import 'package:flutter/widgets.dart';

/// AnimatedOpacity + Visibility
///
/// The point is to disable non-visible buttons
class AnimatedVisibility extends StatefulWidget {
  const AnimatedVisibility({
    Key? key,
    required this.child,
    required this.opacity,
    this.curve = Curves.linear,
    required this.duration,
    this.onEnd,
    this.alwaysIncludeSemantics = false,
  })  : assert(opacity >= 0.0 && opacity <= 1.0),
        super(key: key);

  @override
  createState() => _AnimatedVisibilityState();

  final Widget child;
  final double opacity;
  final Curve curve;
  final Duration duration;
  final VoidCallback? onEnd;
  final bool alwaysIncludeSemantics;
}

class _AnimatedVisibilityState extends State<AnimatedVisibility> {
  @override
  build(BuildContext context) {
    if (!_isActive && widget.opacity > 0) {
      _isActive = true;
    }
    return AnimatedOpacity(
      opacity: widget.opacity,
      curve: widget.curve,
      duration: widget.duration,
      onEnd: _onEnd,
      alwaysIncludeSemantics: widget.alwaysIncludeSemantics,
      child: Visibility(
        visible: _isActive,
        child: widget.child,
      ),
    );
  }

  void _onEnd() {
    if (widget.opacity == 0) {
      setState(() {
        _isActive = false;
      });
    }
    widget.onEnd?.call();
  }

  bool _isActive = true;
}
