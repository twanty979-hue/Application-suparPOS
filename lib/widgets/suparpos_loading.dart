import 'dart:math' as math;

import 'package:flutter/material.dart';

class SuparPosLoading extends StatefulWidget {
  const SuparPosLoading({
    super.key,
    this.message = 'กำลังเตรียม SuparPOS',
    this.fullScreen = true,
  });

  final String message;
  final bool fullScreen;

  @override
  State<SuparPosLoading> createState() => _SuparPosLoadingState();
}

class _SuparPosLoadingState extends State<SuparPosLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final sceneWidth = math.min(constraints.maxWidth, 370.0);
        return SizedBox(
          width: sceneWidth,
          height: sceneWidth * 0.82,
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) => _CharactersScene(progress: _motion.value),
          ),
        );
      },
    );

    if (!widget.fullScreen) {
      return Center(
        child: Container(
          width: 132,
          height: 118,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF4FFF0), Color(0xFFE3F8DF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFC7EDC2)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F9D58).withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: content,
        ),
      );
    }

    return ColoredBox(
      color: const Color(0xFF70C56B),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB9EDAA), Color(0xFF70C56B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const Positioned(top: 70, left: -60, child: _GlowOrb(size: 180)),
            const Positioned(
              right: -75,
              bottom: 70,
              child: _GlowOrb(size: 230),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharactersScene extends StatelessWidget {
  const _CharactersScene({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final phase = progress * math.pi * 2;
    final posY = math.sin(phase) * 4.5;
    final posX = math.sin(phase * 0.65) * 1.8;
    final posRotation = math.sin(phase * 0.65) * 0.014;
    final phoneY = math.sin((phase * 0.83) + 1.1) * 2.5;
    final phoneX = math.cos((phase * 0.7) + 0.5) * 1.4;
    final phoneRotation = math.sin((phase * 0.72) + 1.3) * 0.009;
    final blink =
        (progress > 0.32 && progress < 0.38) ||
        (progress > 0.79 && progress < 0.84);
    final rayPulse = 0.82 + (math.sin(phase * 2) * 0.18);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: width * 0.10,
              right: width * 0.10,
              bottom: 5,
              height: 25,
              child: Transform.scale(
                scaleX: 0.95 + (math.cos(phase) * 0.03),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF14532D).withValues(alpha: 0.17),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x2414532D),
                        blurRadius: 19,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: width * 0.015,
              bottom: 2,
              width: width * 0.72,
              child: Transform.translate(
                offset: Offset(posX, posY),
                child: Transform.rotate(
                  angle: posRotation,
                  child: _PosCharacter(blink: blink),
                ),
              ),
            ),
            Positioned(
              right: width * 0.015,
              bottom: 9,
              width: width * 0.31,
              child: Transform.translate(
                offset: Offset(phoneX, phoneY),
                child: Transform.rotate(
                  angle: phoneRotation,
                  child: Image.asset(
                    'lib/assets/loading/phone-layer.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            Positioned(
              right: width * 0.17,
              top: width * 0.035,
              child: Opacity(
                opacity: rayPulse.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: rayPulse,
                  child: const _ActionRays(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PosCharacter extends StatelessWidget {
  const _PosCharacter({required this.blink});

  final bool blink;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 867 / 1063,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          return Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'lib/assets/loading/pos-layer.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              if (blink) ...[
                _BlinkEye(
                  left: width * 0.418,
                  top: height * 0.278,
                  width: width,
                ),
                _BlinkEye(
                  left: width * 0.638,
                  top: height * 0.278,
                  width: width,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BlinkEye extends StatelessWidget {
  const _BlinkEye({required this.left, required this.top, required this.width});

  final double left;
  final double top;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: width * 0.064,
      height: width * 0.105,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF257556),
          borderRadius: BorderRadius.circular(width),
        ),
        child: Center(
          child: Container(
            width: width * 0.042,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRays extends StatelessWidget {
  const _ActionRays();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 52,
      child: Stack(
        children: [
          Positioned(
            left: 2,
            top: 0,
            child: Transform.rotate(angle: 0.45, child: const _Ray(height: 24)),
          ),
          Positioned(
            right: 0,
            top: 17,
            child: Transform.rotate(angle: 1.05, child: const _Ray(height: 25)),
          ),
          Positioned(
            right: 4,
            bottom: 0,
            child: Transform.rotate(angle: 1.72, child: const _Ray(height: 21)),
          ),
        ],
      ),
    );
  }
}

class _Ray extends StatelessWidget {
  const _Ray({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFFFDF6D),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

class _LoadingDots extends StatelessWidget {
  const _LoadingDots({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (animation.value + (index * 0.18)) % 1.0;
            final opacity = 0.35 + (math.sin(phase * math.pi) * 0.65);
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
      ),
    );
  }
}
