import 'dart:async';

import 'package:flutter/material.dart';

import 'suparpos_loading.dart';

/// Builds the destination immediately, then keeps the branded animation above
/// it briefly. Network/data loading continues behind the animation.
class SuparPosNavigationLoader extends StatefulWidget {
  const SuparPosNavigationLoader({
    super.key,
    required this.child,
    this.visibleDuration = const Duration(milliseconds: 760),
    this.fullScreen = true,
  });

  final Widget child;
  final Duration visibleDuration;
  final bool fullScreen;

  @override
  State<SuparPosNavigationLoader> createState() =>
      _SuparPosNavigationLoaderState();
}

class _SuparPosNavigationLoaderState extends State<SuparPosNavigationLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  Timer? _hideTimer;
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _hideTimer = Timer(widget.visibleDuration, _hideOverlay);
  }

  Future<void> _hideOverlay() async {
    if (!mounted) return;
    await _fadeController.forward();
    if (mounted) setState(() => _showOverlay = false);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showOverlay)
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: ReverseAnimation(
                  CurvedAnimation(
                    parent: _fadeController,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: SuparPosLoading(fullScreen: widget.fullScreen),
              ),
            ),
          ),
      ],
    );
  }
}
