// lib/widgets/iphone_mockup.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class IphoneMockup extends StatelessWidget {
  final String imageUrl;
  final bool isCurrent;

  static const Color _ink = Color(0xFF0B1730);

  const IphoneMockup({
    super.key,
    required this.imageUrl,
    this.isCurrent = false,
  });

  Widget _buildSideButton(double width, double height, {bool isRight = false}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF3A3C42),
        borderRadius: isRight
            ? BorderRadius.horizontal(right: Radius.circular(width))
            : BorderRadius.horizontal(left: Radius.circular(width)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        // Proportions for iPhone 17 Pro Max
        final frameRadius = width * 0.18;
        final screenRadius = width * 0.15;
        final bezelWidth = width * 0.035;

        final buttonWidth = width * 0.02;
        final actionBtnHeight = height * 0.05;
        final volBtnHeight = height * 0.09;
        final powerBtnHeight = height * 0.12;

        final dynamicIslandWidth = width * 0.30;
        final dynamicIslandHeight = width * 0.08;
        final dynamicIslandTop = width * 0.05;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Left Side Buttons
            Positioned(
              left: 0,
              top: height * 0.22,
              child: _buildSideButton(buttonWidth, actionBtnHeight),
            ),
            Positioned(
              left: 0,
              top: height * 0.30,
              child: _buildSideButton(buttonWidth, volBtnHeight),
            ),
            Positioned(
              left: 0,
              top: height * 0.41,
              child: _buildSideButton(buttonWidth, volBtnHeight),
            ),

            // Right Side Button (Power)
            Positioned(
              right: 0,
              top: height * 0.32,
              child: _buildSideButton(buttonWidth, powerBtnHeight, isRight: true),
            ),

            // Main Phone Frame
            Container(
              margin: EdgeInsets.symmetric(horizontal: buttonWidth),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1C), // Titanium dark frame
                borderRadius: BorderRadius.circular(frameRadius),
                border: Border.all(color: const Color(0xFF4A4B4F), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: EdgeInsets.all(bezelWidth),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black, // Inner bezel black
                  borderRadius: BorderRadius.circular(screenRadius),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(screenRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. ภาพหน้าจอ
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const ColoredBox(
                            color: Color(0xFFE8EEF5),
                            child: Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  color: _ink,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const ColoredBox(
                            color: Color(0xFFE8EEF5),
                            child: Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: Color(0xFF94A3B8),
                                size: 20,
                              ),
                            ),
                          );
                        },
                      ),

                      // 2. Dynamic Island
                      Positioned(
                        top: dynamicIslandTop,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: dynamicIslandWidth,
                            height: dynamicIslandHeight,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(
                                  dynamicIslandHeight / 2),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Camera lens reflection detail
                                Container(
                                  margin: EdgeInsets.only(
                                      right: dynamicIslandWidth * 0.08),
                                  width: dynamicIslandHeight * 0.6,
                                  height: dynamicIslandHeight * 0.6,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F1014),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF2A2A30),
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // 3. Overlay ตอนที่เป็น Theme ปัจจุบัน
                      if (isCurrent) ...[
                        Positioned.fill(
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 1.8, sigmaY: 1.8),
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.30),
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 7,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF2F80ED),
                                  size: 12,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}