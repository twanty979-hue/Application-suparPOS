import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/printer_service.dart';

class PrinterKeepAliveService with WidgetsBindingObserver {
  PrinterKeepAliveService._();

  static final PrinterKeepAliveService instance = PrinterKeepAliveService._();

  Timer? _timer;
  String? _brandId;
  bool _isPinging = false;

  void start(String? brandId) {
    if (brandId == null || brandId.isEmpty) return;

    _brandId = brandId;
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => _ping());
    _ping();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _ping();
    }
  }

  Future<void> _ping() async {
    final brandId = _brandId;
    if (brandId == null || _isPinging) return;

    _isPinging = true;
    try {
      await PrinterService.keepBluetoothAwake(brandId);
    } finally {
      _isPinging = false;
    }
  }
}
