import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class StatusModal {
  static void show(BuildContext context, String title, String message, IconData icon, Color color) {
    showDialog(
      context: context,
      barrierColor: AppColors.slate900.withOpacity(0.6),
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(48)),
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(48)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 48),
                ),
                const SizedBox(height: 24),
                Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.slate800)),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.slate500, fontSize: 16)),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.slate800,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text("ตกลง", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
        );
      }
    );
  }
}