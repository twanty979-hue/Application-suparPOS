import 'package:flutter/material.dart';

class SuparPosNavigationLoader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return child;
  }
}
