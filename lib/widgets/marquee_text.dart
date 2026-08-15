import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Single-line text that scrolls (lichtkrant) when it does not fit at [style].
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.velocity = 40,
    this.gap = 48,
  });

  final String text;
  final TextStyle style;

  /// Scroll speed in logical pixels per second.
  final double velocity;

  /// Blank space between the looping copies.
  final double gap;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  static const _heightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  final _textKey = GlobalKey();
  late final AnimationController _controller;
  double _textWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.gap != widget.gap) {
      _textWidth = 0;
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final box = _textKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) {
        return;
      }
      final height = box.hasSize ? box.size.height : double.infinity;
      final width = box.getMaxIntrinsicWidth(height);
      if (!width.isFinite || width <= 0) {
        return;
      }
      if ((width - _textWidth).abs() <= 0.5) {
        return;
      }
      setState(() {
        _textWidth = width;
      });
    });
  }

  void _syncAnimation({required bool shouldScroll, required double scrollWidth}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!shouldScroll || scrollWidth <= 0) {
        if (_controller.isAnimating) {
          _controller.stop();
        }
        return;
      }
      final ms =
          (scrollWidth / widget.velocity * 1000).round().clamp(1, 1 << 30);
      final duration = Duration(milliseconds: ms);
      if (_controller.duration != duration || !_controller.isAnimating) {
        _controller
          ..duration = duration
          ..repeat();
      }
    });
  }

  Widget _label({Key? key, required TextAlign align}) {
    return Text(
      widget.text,
      key: key,
      style: widget.style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textAlign: align,
      textHeightBehavior: _heightBehavior,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleMeasure();
        final maxWidth = constraints.maxWidth;
        final fontSize = widget.style.fontSize ?? 14;
        final height = math.max(fontSize * 1.25, fontSize);
        final shouldScroll =
            maxWidth.isFinite && _textWidth > maxWidth + 0.5;
        final scrollWidth = _textWidth + widget.gap;
        _syncAnimation(shouldScroll: shouldScroll, scrollWidth: scrollWidth);

        return SizedBox(
          width: maxWidth.isFinite ? maxWidth : _textWidth,
          height: height,
          child: ClipRect(
            child: shouldScroll
                ? OverflowBox(
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    alignment: Alignment.centerLeft,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return Transform.translate(
                          offset: Offset(-_controller.value * scrollWidth, 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _label(key: _textKey, align: TextAlign.left),
                              SizedBox(width: widget.gap),
                              _label(align: TextAlign.left),
                            ],
                          ),
                        );
                      },
                    ),
                  )
                : Align(
                    alignment: Alignment.center,
                    child: OverflowBox(
                      minWidth: 0,
                      maxWidth: double.infinity,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      alignment: Alignment.center,
                      child: _label(key: _textKey, align: TextAlign.center),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
