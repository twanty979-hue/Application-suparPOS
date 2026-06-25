// lib/utils/printer_service.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:blue_thermal_printer/blue_thermal_printer.dart' as bt;
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';

class PrinterService {
  static final bt.BlueThermalPrinter bluetooth = bt.BlueThermalPrinter.instance;
  static const Duration _bluetoothLookupTimeout = Duration(seconds: 4);
  static const Duration _bluetoothConnectTimeout = Duration(seconds: 8);
  static const Duration _bluetoothWriteTimeout = Duration(seconds: 8);
  static const double _receiptWidthDots = 372.0;
  static const int _printerWriteChunkSize = 2048;
  static const Duration _printerWriteChunkDelay = Duration(milliseconds: 6);
  static final NumberFormat _moneyFormat = NumberFormat('#,##0.00');

  static String _cleanMac(String value) {
    return value.trim().toUpperCase().replaceAll('-', ':');
  }

  static Future<bt.BluetoothDevice?> _findBondedDevice(String mac) async {
    final targetMac = _cleanMac(mac);
    if (targetMac.isEmpty) return null;

    final devices = await bluetooth.getBondedDevices().timeout(
      _bluetoothLookupTimeout,
      onTimeout: () => <bt.BluetoothDevice>[],
    );

    for (final device in devices.whereType<bt.BluetoothDevice>()) {
      final deviceMac = _cleanMac(device.address ?? '');
      if (deviceMac == targetMac) return device;
    }

    return null;
  }

  static Future<bool> keepBluetoothAwake(String brandId) async {
    try {
      final settings = await _loadPrinterSettings(brandId);
      final savedMac = settings.mac;
      if (savedMac == null || savedMac.isEmpty) return false;

      final selectedDevice = await _findBondedDevice(savedMac);
      if (selectedDevice == null) return false;

      await _connectBluetoothFresh(selectedDevice);

      await bluetooth
          .writeBytes(Uint8List.fromList(const [0x10, 0x04, 0x01]))
          .timeout(_bluetoothWriteTimeout);
      return true;
    } catch (e) {
      debugPrint('[Printer KeepAlive] failed: $e');
      return false;
    }
  }

  static Future<bool> printReceipt(
    Map<String, dynamic> data,
    String brandId, {
    bool isReprint = false,
  }) async {
    final settings = await _loadPrinterSettings(brandId);
    if (!settings.hasAnyPrinter) {
      debugPrint('[Printer] No printer configured');
      return false;
    }

    late final List<int> receiptBytes;
    try {
      receiptBytes = await _generateOrderReceipt(
        data,
        brandId: brandId,
        copies: settings.copies,
        isKitchenTicket: _isKitchenTicket(data),
        isReprint: isReprint,
      );
    } catch (e) {
      debugPrint('[Printer] Build receipt failed: $e');
      return false;
    }

    return _sendBytes(settings, receiptBytes, label: 'receipt');
  }

  static Future<bool> printPromptPayReceipt(
    Map<String, dynamic> data,
    String brandId, {
    required String promptPayId,
    required double amount,
  }) async {
    final qrData = _generatePromptPayQrData(promptPayId, amount);
    if (qrData.isEmpty) {
      debugPrint('[Printer] Invalid PromptPay ID');
      return false;
    }

    return printReceipt({
      ...data,
      'receipt_type': 'payment_request',
      'payment_method': 'PROMPTPAY',
      'promptpay_id': promptPayId,
      'promptpay_qr_data': qrData,
      'payable_amount': amount,
      'total_amount': amount,
    }, brandId);
  }

  static Future<bool> printTableQr({
    required String brandId,
    required String tableLabel,
    required String passcode,
    required String orderUrl,
  }) async {
    final settings = await _loadPrinterSettings(brandId);
    if (!settings.hasAnyPrinter) {
      debugPrint('[Printer] No printer configured');
      return false;
    }

    late final List<int> qrBytes;
    try {
      qrBytes = await _generateTableQrReceipt(orderUrl: orderUrl);
    } catch (e) {
      debugPrint('[Printer] Build QR failed: $e');
      return false;
    }

    return _sendBytes(settings, qrBytes, label: 'QR');
  }

  static Future<_PrinterSettings> _loadPrinterSettings(String brandId) async {
    final prefs = await SharedPreferences.getInstance();
    final dbSettings = await DatabaseHelper.instance.getPrinterSettings(
      brandId,
    );

    final savedIp = dbSettings?['ip']?.toString().trim().isNotEmpty == true
        ? dbSettings!['ip'].toString().trim()
        : prefs.getString('printer_ip_$brandId')?.trim();
    final savedMac = dbSettings?['mac']?.toString().trim().isNotEmpty == true
        ? dbSettings!['mac'].toString().trim()
        : prefs.getString('printer_mac_$brandId')?.trim();
    final savedCopies =
        int.tryParse(dbSettings?['copies']?.toString() ?? '') ??
        prefs.getInt('receipt_copies_$brandId') ??
        1;

    return _PrinterSettings(
      ip: savedIp,
      mac: savedMac,
      copies: savedCopies <= 1 ? 1 : 2,
    );
  }

  static Future<bool> _sendBytes(
    _PrinterSettings settings,
    List<int> bytes, {
    required String label,
  }) async {
    final savedIp = settings.ip;
    if (savedIp != null && savedIp.isNotEmpty) {
      try {
        final socket = await Socket.connect(
          savedIp,
          9100,
          timeout: const Duration(seconds: 5),
        );
        await _writeSocketSlow(socket, bytes);
        await socket.flush();
        await socket.close();
        return true;
      } catch (e) {
        debugPrint('[Printer] $label Wi-Fi failed, trying Bluetooth: $e');
      }
    }

    final savedMac = settings.mac;
    if (savedMac != null && savedMac.isNotEmpty) {
      return _sendBluetoothBytes(savedMac, bytes, label: label);
    }

    return false;
  }

  static Future<bool> _sendBluetoothBytes(
    String savedMac,
    List<int> bytes, {
    required String label,
  }) async {
    bt.BluetoothDevice? selectedDevice;
    try {
      selectedDevice = await _findBondedDevice(savedMac);
    } catch (e) {
      debugPrint('[Printer] Bluetooth lookup failed: $e');
      return false;
    }

    if (selectedDevice == null) {
      debugPrint('[Printer] Bluetooth device not found: $savedMac');
      return false;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _connectBluetoothFresh(selectedDevice);

        await _writeBluetoothSlow(bytes);
        await Future.delayed(const Duration(milliseconds: 300));
        return true;
      } catch (e) {
        debugPrint(
          '[Printer] $label Bluetooth attempt ${attempt + 1} failed: $e',
        );
      }
    }

    return false;
  }

  static Future<void> _connectBluetoothFresh(bt.BluetoothDevice device) async {
    await _disconnectBluetoothQuietly();
    await Future.delayed(const Duration(milliseconds: 350));
    await bluetooth.connect(device).timeout(_bluetoothConnectTimeout);
    await Future.delayed(const Duration(seconds: 1));
  }

  static Future<void> _disconnectBluetoothQuietly() async {
    try {
      await bluetooth.disconnect().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  static Future<void> _writeBluetoothSlow(List<int> bytes) async {
    for (
      var offset = 0;
      offset < bytes.length;
      offset += _printerWriteChunkSize
    ) {
      final end = math.min(offset + _printerWriteChunkSize, bytes.length);
      await bluetooth
          .writeBytes(Uint8List.fromList(bytes.sublist(offset, end)))
          .timeout(_bluetoothWriteTimeout);
      await Future.delayed(_printerWriteChunkDelay);
    }
  }

  static Future<void> _writeSocketSlow(Socket socket, List<int> bytes) async {
    for (
      var offset = 0;
      offset < bytes.length;
      offset += _printerWriteChunkSize
    ) {
      final end = math.min(offset + _printerWriteChunkSize, bytes.length);
      socket.add(bytes.sublist(offset, end));
      await socket.flush();
      await Future.delayed(_printerWriteChunkDelay);
    }
  }

  static Future<List<int>> _generateOrderReceipt(
    Map<String, dynamic> data, {
    required String brandId,
    required int copies,
    required bool isKitchenTicket,
    bool isReprint = false,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];

    for (var copy = 1; copy <= copies; copy++) {
      final image = await _buildOrderImage(
        data,
        brandId: brandId,
        isKitchenTicket: isKitchenTicket,
        copyIndex: copies > 1 ? copy : null,
        copyCount: copies,
        isReprint: isReprint,
      );
      bytes.addAll(generator.image(image));
      bytes.addAll(generator.feed(copy < copies ? 4 : 2));
    }

    bytes.addAll(generator.cut());
    return bytes;
  }

  static Future<List<int>> _generateTableQrReceipt({
    required String orderUrl,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final image = await _buildQrImage(orderUrl);
    return <int>[
      ...generator.image(image),
      ...generator.feed(2),
      ...generator.cut(),
    ];
  }

  static Future<img.Image> _buildOrderImage(
    Map<String, dynamic> data, {
    required String brandId,
    required bool isKitchenTicket,
    required int? copyIndex,
    required int copyCount,
    bool isReprint = false,
  }) async {
    final lines = <_TicketLine>[];
    final logoImage = await _loadReceiptLogo(brandId, data, isKitchenTicket);
    final brandName = _firstText(data, const [
      'brand_name',
      'brandName',
      'store_name',
      'shop_name',
    ], 'ร้านค้า');
    final tableLabel = _firstText(data, const [
      'table_label',
      'tableLabel',
      'table',
      'table_name',
    ], 'Walk-in');
    final shouldShowTableLabel =
        tableLabel.trim().isNotEmpty &&
        tableLabel.trim().toLowerCase() != 'walk-in';
    final receiptType = _firstText(data, const [
      'receipt_type',
      'receiptType',
      'type',
    ], '').toLowerCase();
    final isPaymentRequest = receiptType == 'payment_request';
    final promptPayQrData = _firstText(data, const [
      'promptpay_qr_data',
      'promptPayQrData',
      'promptpayQrData',
    ], '');
    final promptPayId = _firstText(data, const [
      'promptpay_id',
      'promptPayId',
      'promptpayId',
    ], '');
    final items = _items(data);
    final totals = _totals(data, items);

    if (copyIndex != null) {
      lines.add(
        _TicketLine.center(
          '--- Copy $copyIndex of $copyCount ---',
          fontSize: 20,
          bold: false,
        ),
      );
    }

    if (logoImage != null) {
      lines.add(_TicketLine.image(logoImage));
    }

    if (isReprint) {
      lines.add(
        const _TicketLine.center(
          '*** ใบเสร็จรับเงิน (ย้อนหลัง) ***',
          fontSize: 22,
          bold: true,
        ),
      );
    }

    lines.add(_TicketLine.center(brandName, fontSize: 34, bold: true));
    if (shouldShowTableLabel) {
      lines.add(_TicketLine.center('Table: $tableLabel', fontSize: 24));
    }
    lines.add(_TicketLine.center(_receiptDate(data), fontSize: 24));

    if (isKitchenTicket) {
      lines.add(
        const _TicketLine.center(
          '*** ใบห้องครัว ***',
          fontSize: 32,
          bold: true,
        ),
      );
    }

    lines.add(const _TicketLine.separator());
    for (final item in items) {
      _addItemLines(lines, item, isKitchenTicket: isKitchenTicket);
    }

    if (!isKitchenTicket) {
      lines
        ..add(const _TicketLine.separator())
        ..add(
          _TicketLine.leftRight(
            'ยอดรวม (Subtotal)',
            _formatMoney(totals.subtotal),
          ),
        );

      if (totals.discount.abs() > 0.001) {
        lines.add(
          _TicketLine.leftRight(
            'ส่วนลดรวม (Discount)',
            _formatMoney(-totals.discount.abs()),
          ),
        );
      }

      lines.add(
        _TicketLine.leftRight(
          isPaymentRequest ? 'ยอดที่ต้องชำระ' : 'ยอดรวมสุทธิ',
          _formatMoney(totals.total),
          fontSize: 32,
          bold: true,
        ),
      );
    }

    if (isKitchenTicket) {
      lines
        ..add(const _TicketLine.separator())
        ..add(
          const _TicketLine.center(
            '*** โปรดตรวจสอบรายการ ***',
            fontSize: 26,
            topGap: 12,
          ),
        );
    } else if (isPaymentRequest) {
      lines
        ..add(const _TicketLine.separator())
        ..add(
          const _TicketLine.center(
            'สแกนชำระเงิน PromptPay',
            fontSize: 28,
            bold: true,
          ),
        )
        ..add(_TicketLine.qr(promptPayQrData))
        ..add(_TicketLine.center('PromptPay: $promptPayId', fontSize: 22))
        ..add(const _TicketLine.center('กรุณาชำระตามยอดใน QR', fontSize: 22));
    } else {
      final received = _firstDouble(data, const [
        'received_amount',
        'receivedAmount',
        'cash_received',
      ]);
      final change = _firstDouble(data, const [
        'change_amount',
        'changeAmount',
      ]);
      final payment = _firstText(data, const [
        'payment_method',
        'paymentMethod',
      ], 'CASH');
      final cashier = _firstText(data, const [
        'cashier_name',
        'cashierName',
        'cashier',
      ], 'Ball');

      lines
        ..add(const _TicketLine.separator())
        ..add(
          _TicketLine.leftRight('รับเงิน (Received)', _formatMoney(received)),
        )
        ..add(_TicketLine.leftRight('เงินทอน (Change)', _formatMoney(change)))
        ..add(const _TicketLine.separator())
        ..add(_TicketLine.center('ชำระโดย: ${payment.toUpperCase()}'))
        ..add(_TicketLine.center('Cashier: $cashier'))
        ..add(const _TicketLine.blank(height: 12))
        ..add(const _TicketLine.center('Thank you', fontSize: 26));
    }

    return _renderLines(lines);
  }

  static Future<ui.Image?> _loadReceiptLogo(
    String brandId,
    Map<String, dynamic> data,
    bool isKitchenTicket,
  ) async {
    if (isKitchenTicket) return null;

    final prefs = await SharedPreferences.getInstance();
    final showLogo =
        data['show_receipt_logo'] == true ||
        data['showReceiptLogo'] == true ||
        (brandId.isNotEmpty &&
            (prefs.getBool('show_receipt_logo_$brandId') ?? false));
    if (!showLogo) return null;

    Uint8List? logoBytes;
    final explicitPath = _firstText(data, const [
      'receipt_logo_path',
      'receiptLogoPath',
      'logo_path',
      'logoPath',
    ], '');
    final savedPath = brandId.isEmpty
        ? ''
        : prefs.getString('store_logo_path_$brandId') ?? '';
    final logoPath = explicitPath.isNotEmpty ? explicitPath : savedPath;

    if (logoPath.isNotEmpty) {
      try {
        final file = File(logoPath);
        if (await file.exists()) {
          logoBytes = await file.readAsBytes();
        }
      } catch (_) {}
    }

    logoBytes ??= (await rootBundle.load(
      'lib/assets/app_logo.png',
    )).buffer.asUint8List();

    final decoded = img.decodeImage(logoBytes);
    if (decoded == null) return null;

    final resized = img.copyResize(
      decoded,
      width: 108,
      interpolation: img.Interpolation.average,
    );
    final pngBytes = Uint8List.fromList(img.encodePng(resized));
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<img.Image> _buildQrImage(String orderUrl) async {
    const baseWidth = _receiptWidthDots;
    const scale = 5.0;
    const width = baseWidth * scale;
    const baseHeight = 360.0;
    const height = baseHeight * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );

    _paintText(
      canvas,
      'SHOP',
      20,
      width,
      scale,
      fontSize: 20,
      bold: true,
      align: TextAlign.center,
    );
    _paintText(
      canvas,
      '--------------------------------',
      50,
      width,
      scale,
      fontSize: 20,
      bold: false,
      align: TextAlign.center,
    );

    final qrPainter = QrPainter(
      data: orderUrl,
      version: QrVersions.auto,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    const qrSize = 220.0 * scale;
    canvas
      ..save()
      ..translate((width - qrSize) / 2, 80 * scale);
    qrPainter.paint(canvas, const Size(qrSize, qrSize));
    canvas.restore();

    _paintText(
      canvas,
      '-----สแกนสั่งอาหาร-----',
      315,
      width,
      scale,
      fontSize: 20,
      bold: true,
      align: TextAlign.center,
    );

    return _pictureToThermalImage(
      recorder,
      width.toInt(),
      height.toInt(),
      baseWidth.toInt(),
      baseHeight.toInt(),
    );
  }

  static Future<img.Image> _renderLines(List<_TicketLine> lines) async {
    const baseWidth = _receiptWidthDots;
    const scale = 5.0;
    var baseHeight = 24.0;
    for (final line in lines) {
      baseHeight += line.topGap + line.height + line.bottomGap;
    }
    baseHeight += 18.0;

    const width = baseWidth * scale;
    final height = baseHeight * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );

    var y = 12.0;
    for (final line in lines) {
      y += line.topGap;
      if (line.isBlank) {
        y += line.height + line.bottomGap;
        continue;
      }

      if (line.isSeparator) {
        _paintText(
          canvas,
          '------------------------------------------------',
          y,
          width,
          scale,
          fontSize: 22,
          bold: false,
          align: TextAlign.center,
        );
      } else if (line.image != null) {
        final source = line.image!;
        final imageHeight = line.height * scale;
        final imageWidth = imageHeight * source.width / source.height;
        final dest = Rect.fromLTWH(
          (width - imageWidth) / 2,
          y * scale,
          imageWidth,
          imageHeight,
        );
        canvas.drawImageRect(
          source,
          Rect.fromLTWH(
            0,
            0,
            source.width.toDouble(),
            source.height.toDouble(),
          ),
          dest,
          Paint()..filterQuality = FilterQuality.medium,
        );
      } else if (line.qrData != null) {
        final qrSize = line.height - 20;
        final qrPainter = QrPainter(
          data: line.qrData!,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          gapless: true,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        );
        canvas.save();
        canvas.translate((width - (qrSize * scale)) / 2, y * scale);
        qrPainter.paint(canvas, Size(qrSize * scale, qrSize * scale));
        canvas.restore();
      } else if (line.center != null) {
        _paintText(
          canvas,
          line.center!,
          y,
          width,
          scale,
          fontSize: line.fontSize,
          bold: line.bold,
          align: TextAlign.center,
        );
      } else {
        final right = line.right;
        final indent = line.indent * scale;
        final maxLeftWidth = right == null
            ? width - indent - (8 * scale)
            : width - indent - (128 * scale);
        _paintText(
          canvas,
          line.left ?? '',
          y,
          maxLeftWidth,
          scale,
          fontSize: line.fontSize,
          bold: line.bold,
          x: indent,
          maxLines: 1,
          ellipsis: true,
        );
        if (right != null) {
          _paintText(
            canvas,
            right,
            y,
            width,
            scale,
            fontSize: line.fontSize,
            bold: line.bold,
            align: TextAlign.right,
          );
        }
      }
      y += line.height + line.bottomGap;
    }

    return _pictureToThermalImage(
      recorder,
      width.toInt(),
      height.toInt(),
      baseWidth.toInt(),
      baseHeight.ceil(),
    );
  }

  static void _paintText(
    Canvas canvas,
    String text,
    double y,
    double maxWidth,
    double scale, {
    double fontSize = 24,
    bool bold = false,
    TextAlign align = TextAlign.left,
    double x = 0,
    int? maxLines,
    bool ellipsis = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize * scale,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
          fontFamily: 'Sarabun',
          fontFamilyFallback: const [
            'TH Sarabun New',
            'TH SarabunPSK',
            'Noto Sans Thai',
            'Noto Sans',
            'Roboto',
            'Arial',
            'sans-serif',
            'monospace',
          ],
          height: 1.0,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: ellipsis ? '...' : null,
    );
    painter.layout(maxWidth: maxWidth);
    var paintX = x;
    if (align == TextAlign.center) {
      paintX = (maxWidth - painter.width) / 2;
    } else if (align == TextAlign.right) {
      paintX = maxWidth - painter.width;
    }
    painter.paint(
      canvas,
      Offset(paintX.roundToDouble(), (y * scale).roundToDouble()),
    );
  }

  static Future<img.Image> _pictureToThermalImage(
    ui.PictureRecorder recorder,
    int width,
    int height,
    int targetWidth,
    int targetHeight,
  ) async {
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(width, height);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    final sourceImage = img.decodeImage(byteData!.buffer.asUint8List());
    if (sourceImage == null) {
      throw StateError('Cannot decode rendered receipt image');
    }

    final resizedImage = img.copyResize(
      sourceImage,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.nearest,
    );
    return _thresholdBlackWhite(resizedImage);
  }

  static img.Image _thresholdBlackWhite(img.Image image) {
    final width = image.width;
    final height = image.height;

    // Create a 2D array of grayscales to perform error diffusion
    final grays = List.generate(
      height,
      (y) => List.generate(width, (x) {
        final colorValue = image.getPixel(x, y);
        final r = img.getRed(colorValue);
        final g = img.getGreen(colorValue);
        final b = img.getBlue(colorValue);
        final a = img.getAlpha(colorValue);

        // If mostly transparent, treat as white paper background
        if (a < 128) {
          return 255.0;
        }

        // Standard luminance formula
        return (0.299 * r) + (0.587 * g) + (0.114 * b);
      }),
    );

    // Floyd-Steinberg Dithering Algorithm
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final oldVal = grays[y][x];
        // Using 180 as threshold (balanced for text and dithering logo)
        final newVal = oldVal < 180 ? 0.0 : 255.0;
        final error = oldVal - newVal;

        grays[y][x] = newVal;

        if (x + 1 < width) {
          grays[y][x + 1] += error * 7 / 16;
        }
        if (y + 1 < height) {
          if (x - 1 >= 0) {
            grays[y + 1][x - 1] += error * 3 / 16;
          }
          grays[y + 1][x] += error * 5 / 16;
          if (x + 1 < width) {
            grays[y + 1][x + 1] += error * 1 / 16;
          }
        }
      }
    }

    // Write the dithered result back into the image pixels
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final val = grays[y][x].round().clamp(0, 255);
        image.setPixel(
          x,
          y,
          val < 128 ? img.getColor(0, 0, 0) : img.getColor(255, 255, 255),
        );
      }
    }

    return image;
  }

  static void _addItemLines(
    List<_TicketLine> lines,
    _ReceiptItem item, {
    required bool isKitchenTicket,
  }) {
    if (isKitchenTicket) {
      lines.add(_TicketLine.left('${item.quantity}x ${item.name}'));
    } else {
      lines.add(
        _TicketLine.leftRight(
          '${item.quantity}x ${item.name}',
          _formatMoney(item.total),
        ),
      );
    }

    final variant = _variantLabel(item.variant);
    if (variant.isNotEmpty) {
      lines.add(_TicketLine.left('- ($variant)', indent: 28));
    }

    for (final option in item.note.options) {
      lines.add(_TicketLine.left('- $option', indent: 28));
    }

    if (item.note.freeText.isNotEmpty) {
      final wrapped = _wrapVisual(item.note.freeText, 24);
      for (var i = 0; i < wrapped.length; i++) {
        lines.add(
          _TicketLine.left(
            i == 0 ? 'Note: ${wrapped[i]}' : '      ${wrapped[i]}',
            indent: 0,
          ),
        );
      }
    }

    if (!isKitchenTicket && item.discount.abs() > 0.001) {
      lines.add(
        _TicketLine.leftRight(
          '(ส่วนลด)',
          _formatMoney(-item.discount.abs()),
          indent: 28,
        ),
      );
    }
  }

  static List<_ReceiptItem> _items(Map<String, dynamic> data) {
    final rawItems = data['items'] ?? data['order_items'] ?? const [];
    if (rawItems is! List) return const [];

    return rawItems.whereType<Map>().map((raw) {
      final item = raw.cast<String, dynamic>();
      final qty = _firstInt(item, const ['quantity', 'qty', 'amount'], 1);
      final unitPrice = _firstDouble(item, const [
        'price',
        'unit_price',
        'unitPrice',
      ]);
      var total = _firstDouble(item, const [
        'total_price',
        'totalPrice',
        'line_total',
        'lineTotal',
        'subtotal',
      ]);
      if (total.abs() < 0.001) total = unitPrice * qty;

      return _ReceiptItem(
        name: _firstText(item, const [
          'product_name',
          'productName',
          'name',
          'title',
        ], 'รายการ'),
        quantity: qty,
        total: total,
        discount: _firstDouble(item, const [
          'discount_amount',
          'discountAmount',
          'discount',
          'item_discount',
          'itemDiscount',
        ]),
        variant: _firstText(item, const [
          'variant',
          'variant_name',
          'variantName',
          'size',
        ], ''),
        note: _parseNote(_firstText(item, const ['note', 'notes'], '')),
      );
    }).toList();
  }

  static _ReceiptTotals _totals(
    Map<String, dynamic> data,
    List<_ReceiptItem> items,
  ) {
    final itemDiscount = items.fold<double>(
      0,
      (sum, item) => sum + item.discount.abs(),
    );
    var subtotal = _firstDouble(data, const [
      'subtotal',
      'subTotal',
      'total_before_discount',
      'totalBeforeDiscount',
    ]);
    if (subtotal.abs() < 0.001) {
      subtotal = items.fold<double>(
        0,
        (sum, item) => sum + item.total + item.discount.abs(),
      );
    }

    var discount = _firstDouble(data, const [
      'total_discount',
      'totalDiscount',
      'discount_amount',
      'discountAmount',
      'discount',
    ]);
    if (discount.abs() < 0.001) discount = itemDiscount;

    var total = _firstDouble(data, const [
      'total_amount',
      'totalAmount',
      'payable_amount',
      'payableAmount',
      'total_price',
      'totalPrice',
    ]);
    if (total.abs() < 0.001) total = subtotal - discount.abs();

    return _ReceiptTotals(
      subtotal: subtotal,
      discount: discount.abs(),
      total: total,
    );
  }

  static bool _isKitchenTicket(Map<String, dynamic> data) {
    final explicitType = _firstText(data, const [
      'receipt_type',
      'receiptType',
      'type',
    ], '').toLowerCase();
    if (data['is_kitchen_ticket'] == true || data['isKitchenTicket'] == true) {
      return true;
    }
    if (explicitType == 'kitchen' || explicitType == 'order') return true;
    if (explicitType == 'sale' || explicitType == 'receipt') return false;

    final hasPayment = const [
      'payment_method',
      'paymentMethod',
      'received_amount',
      'receivedAmount',
      'change_amount',
      'changeAmount',
    ].any((key) => _text(data[key]).isNotEmpty);
    return !hasPayment;
  }

  static String _receiptDate(Map<String, dynamic> data) {
    final raw = _firstText(data, const [
      'created_at',
      'createdAt',
      'paid_at',
      'paidAt',
      'date',
    ], '');
    final date = DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
    try {
      return DateFormat('dd MMM yyyy HH:mm', 'th_TH').format(date);
    } catch (_) {
      return DateFormat('dd MMM yyyy HH:mm').format(date);
    }
  }

  static String _generatePromptPayQrData(String promptPayId, double amount) {
    final id = promptPayId.replaceAll(RegExp(r'[^0-9]'), '');
    if (id.length != 10 && id.length != 13) return '';

    const start = '000201';
    const acceptRecycle = '010211';
    const merchantInfo = '0016A000000677010111';
    final merchantInfoType = id.length == 10
        ? '2937${merchantInfo}01130066${id.substring(1)}'
        : '2937${merchantInfo}0213$id';
    const country = '5802TH';
    const currencyIso = '5303764';
    final amountText = amount > 0 ? amount.toStringAsFixed(2) : '';
    final amountData = amountText.isEmpty
        ? ''
        : '54${amountText.length.toString().padLeft(2, '0')}$amountText';
    const checksumField = '6304';
    final payload =
        '$start$acceptRecycle$merchantInfoType$country$amountData$currencyIso$checksumField';
    final checksum = _crc16(
      payload,
    ).toRadixString(16).toUpperCase().padLeft(4, '0');
    return '$payload$checksum';
  }

  static int _crc16(String data) {
    var crc = 0xFFFF;
    for (var i = 0; i < data.length; i++) {
      var x = ((crc >> 8) ^ utf8.encode(data[i])[0]) & 0xFF;
      x ^= x >> 4;
      crc = ((crc << 8) ^ (x << 12) ^ (x << 5) ^ x) & 0xFFFF;
    }
    return crc;
  }

  static _ParsedNote _parseNote(String rawNote) {
    final text = rawNote.trim();
    if (text.isEmpty) return const _ParsedNote();

    final bracket = RegExp(r'^\[(.*?)\]\s*(.*)$').firstMatch(text);
    if (bracket == null) return _ParsedNote(freeText: text);

    final options = bracket
        .group(1)!
        .split('|')
        .map((part) => part.split(':').last.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return _ParsedNote(options: options, freeText: bracket.group(2)!.trim());
  }

  static String _variantLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'special':
      case 'พิเศษ':
        return 'พิเศษ';
      case 'jumbo':
      case 'จัมโบ้':
        return 'จัมโบ้';
      case 'normal':
      case 'ธรรมดา':
      case 'null':
        return '';
      default:
        return value.trim();
    }
  }

  static String _firstText(
    Map<String, dynamic> data,
    List<String> keys,
    String fallback,
  ) {
    for (final key in keys) {
      final value = _text(data[key]);
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  static double _firstDouble(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(_text(value).replaceAll(',', ''));
      if (parsed != null) return parsed;
    }
    return 0;
  }

  static int _firstInt(
    Map<String, dynamic> data,
    List<String> keys,
    int fallback,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(_text(value));
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static String _text(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    return text;
  }

  static String _formatMoney(double value) => _moneyFormat.format(value);

  static List<String> _wrapVisual(String text, int maxLength) {
    final words = text.trim().split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (_visualLength(candidate) <= maxLength) {
        current = candidate;
      } else {
        if (current.isNotEmpty) lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines.isEmpty ? [text] : lines;
  }

  static int _visualLength(String text) {
    var length = 0;
    for (final rune in text.runes) {
      if (rune < 0x0300 || rune > 0x0E4E) length++;
    }
    return length;
  }
}

class _PrinterSettings {
  const _PrinterSettings({
    required this.ip,
    required this.mac,
    required this.copies,
  });

  final String? ip;
  final String? mac;
  final int copies;

  bool get hasAnyPrinter =>
      (ip != null && ip!.isNotEmpty) || (mac != null && mac!.isNotEmpty);
}

class _ReceiptItem {
  const _ReceiptItem({
    required this.name,
    required this.quantity,
    required this.total,
    required this.discount,
    required this.variant,
    required this.note,
  });

  final String name;
  final int quantity;
  final double total;
  final double discount;
  final String variant;
  final _ParsedNote note;
}

class _ReceiptTotals {
  const _ReceiptTotals({
    required this.subtotal,
    required this.discount,
    required this.total,
  });

  final double subtotal;
  final double discount;
  final double total;
}

class _ParsedNote {
  const _ParsedNote({this.options = const [], this.freeText = ''});

  final List<String> options;
  final String freeText;
}

class _TicketLine {
  const _TicketLine.center(
    this.center, {
    this.fontSize = 24,
    this.bold = false,
    this.topGap = 0,
  }) : left = null,
       right = null,
       qrData = null,
       image = null,
       indent = 0,
       bottomGap = 0,
       height = fontSize + 12,
       isSeparator = false,
       isBlank = false;

  const _TicketLine.left(this.left, {this.indent = 0, this.fontSize = 24})
    : center = null,
      right = null,
      qrData = null,
      image = null,
      bold = false,
      topGap = 0,
      bottomGap = 0,
      height = fontSize + 12,
      isSeparator = false,
      isBlank = false;

  const _TicketLine.leftRight(
    this.left,
    this.right, {
    this.indent = 0,
    this.fontSize = 24,
    this.bold = false,
  }) : center = null,
       qrData = null,
       image = null,
       topGap = 0,
       bottomGap = 0,
       height = fontSize + 12,
       isSeparator = false,
       isBlank = false;

  const _TicketLine.separator()
    : center = null,
      left = null,
      right = null,
      qrData = null,
      image = null,
      indent = 0,
      fontSize = 24,
      bold = false,
      topGap = 2,
      bottomGap = 2,
      height = 28,
      isSeparator = true,
      isBlank = false;

  const _TicketLine.blank({required this.height})
    : center = null,
      left = null,
      right = null,
      qrData = null,
      image = null,
      indent = 0,
      fontSize = 24,
      bold = false,
      topGap = 0,
      bottomGap = 0,
      isSeparator = false,
      isBlank = true;

  const _TicketLine.qr(this.qrData)
    : center = null,
      left = null,
      right = null,
      image = null,
      indent = 0,
      fontSize = 24,
      bold = false,
      topGap = 12,
      bottomGap = 12,
      height = 246,
      isSeparator = false,
      isBlank = false;

  const _TicketLine.image(this.image)
    : center = null,
      left = null,
      right = null,
      qrData = null,
      indent = 0,
      fontSize = 24,
      bold = false,
      topGap = 0,
      bottomGap = 8,
      height = 82,
      isSeparator = false,
      isBlank = false;

  final String? center;
  final String? left;
  final String? right;
  final String? qrData;
  final ui.Image? image;
  final double indent;
  final double fontSize;
  final bool bold;
  final double topGap;
  final double bottomGap;
  final double height;
  final bool isSeparator;
  final bool isBlank;
}
