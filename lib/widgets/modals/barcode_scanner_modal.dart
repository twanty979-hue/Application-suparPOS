// lib/widgets/modals/barcode_scanner_modal.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../theme/app_colors.dart';

class BarcodeScannerModal extends StatefulWidget {
  final Function(String) onScan;

  const BarcodeScannerModal({super.key, required this.onScan});

  static void show(BuildContext context, Function(String) onScan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BarcodeScannerModal(onScan: onScan),
    );
  }

  @override
  State<BarcodeScannerModal> createState() => _BarcodeScannerModalState();
}

class _BarcodeScannerModalState extends State<BarcodeScannerModal> {
  bool _isScanned = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 16, bottom: 16),
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const Text("สแกนบาร์โค้ดสินค้า", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.slate800)),
          const SizedBox(height: 8),
          const Text("นำกล้องไปจ่อที่รหัสสินค้า", style: TextStyle(color: AppColors.slate500)),
          const SizedBox(height: 16),
          
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.slate200, width: 2),
              ),
              child: MobileScanner(
                onDetect: (capture) {
                  if (_isScanned) return; 
                  
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null) {
                      setState(() => _isScanned = true);
                      widget.onScan(barcode.rawValue!); 
                      Navigator.pop(context); 
                      break;
                    }
                  }
                },
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.rose500,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("ยกเลิก", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          )
        ],
      ),
    );
  }
}