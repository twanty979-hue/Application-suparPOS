import 'package:flutter/material.dart';

class BouncingCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color? glowColor;

  const BouncingCard({
    super.key,
    required this.child,
    required this.onTap,
    this.glowColor,
  });

  @override
  State<BouncingCard> createState() => _BouncingCardState();
}

class _BouncingCardState extends State<BouncingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _isHovering = true);
        _controller.forward();
      },
      onTapUp: (_) {
        setState(() => _isHovering = false);
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isHovering = false);
        _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: _isHovering
                  ? [
                      BoxShadow(
                        color: (widget.glowColor ?? Theme.of(context).primaryColor).withValues(alpha: 0.2),
                        blurRadius: 15,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
