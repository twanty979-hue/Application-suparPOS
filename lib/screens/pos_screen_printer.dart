part of 'pos_screen.dart';

extension PosPrinterExtension on _PosScreenState {

  void _openReceiptSettings() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    Future<void>.delayed(Duration.zero, () {
      if (!mounted) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.popUntil((route) => route is PageRoute);
      navigator.push(
        MaterialPageRoute(
          builder: (context) => ReceiptSettingsScreen(brandId: widget.brandId),
        ),
      );
    });
  }

  Future<void> _showPrinterSettingsAction(
    Map<String, dynamic> receiptData,
  ) async {
    if (!mounted) return;
    if (_suppressPrinterFailureModalForSession || _isPrinterFailureModalOpen) {
      return;
    }

    _printerFailureModalShownCount++;
    _isPrinterFailureModalOpen = true;
    ScaffoldMessenger.of(context).clearSnackBars();

    final prefs = await SharedPreferences.getInstance();
    final dbSettings = await DatabaseHelper.instance.getPrinterSettings(
      widget.brandId,
    );
    final ipController = TextEditingController(
      text: dbSettings?['ip']?.toString().trim().isNotEmpty == true
          ? dbSettings!['ip'].toString().trim()
          : (prefs.getString('printer_ip_${widget.brandId}') ?? ''),
    );
    final savedMac = dbSettings?['mac']?.toString().trim().isNotEmpty == true
        ? dbSettings!['mac'].toString().trim()
        : prefs.getString('printer_mac_${widget.brandId}');
    var receiptCopies =
        int.tryParse(dbSettings?['copies']?.toString() ?? '') ??
        prefs.getInt('receipt_copies_${widget.brandId}') ??
        1;
    receiptCopies = receiptCopies <= 1 ? 1 : 2;

    var devices = <bt.BluetoothDevice>[];
    try {
      devices = await _printerBluetooth.getBondedDevices().timeout(
        const Duration(seconds: 4),
        onTimeout: () => <bt.BluetoothDevice>[],
      );
    } catch (e) {
      debugPrint('POS load bluetooth printers failed: $e');
    }

    bt.BluetoothDevice? selectedDevice;
    if (savedMac != null && savedMac.isNotEmpty) {
      for (final device in devices.whereType<bt.BluetoothDevice>()) {
        if ((device.address ?? '') == savedMac) {
          selectedDevice = device;
          break;
        }
      }
    }

    if (!mounted) {
      ipController.dispose();
      _isPrinterFailureModalOpen = false;
      return;
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          var modalDevices = devices;
          var modalSelectedDevice = selectedDevice;
          var modalCopies = receiptCopies;
          var isSaving = false;
          var isConnectingPrinter = false;
          var isRetryingPrint = false;
          String? statusText;

          Future<bool> saveQuickSettings(StateSetter setModalState) async {
            setModalState(() {
              isSaving = true;
              statusText = null;
            });

            final macToSave = modalSelectedDevice?.address ?? savedMac ?? '';
            await prefs.setString(
              'printer_ip_${widget.brandId}',
              ipController.text.trim(),
            );
            await prefs.setInt('receipt_copies_${widget.brandId}', modalCopies);
            if (macToSave.isNotEmpty) {
              await prefs.setString('printer_mac_${widget.brandId}', macToSave);
            }
            await DatabaseHelper.instance.savePrinterSettings(
              brandId: widget.brandId,
              ip: ipController.text.trim(),
              mac: macToSave,
              copies: modalCopies,
            );

            if (!dialogContext.mounted) return false;
            setModalState(() {
              isSaving = false;
              statusText = 'บันทึกเครื่องพิมพ์แล้ว ลองพิมพ์อีกครั้งได้เลย';
            });
            return true;
          }

          Future<void> connectBluetoothPrinter(
            bt.BluetoothDevice device,
            StateSetter setModalState,
          ) async {
            setModalState(() {
              isConnectingPrinter = true;
              statusText = 'กำลังเชื่อมต่อ Bluetooth...';
            });

            try {
              final deviceMac = device.address ?? '';
              if (deviceMac.isNotEmpty) {
                await prefs.setString(
                  'printer_mac_${widget.brandId}',
                  deviceMac,
                );
                await DatabaseHelper.instance.savePrinterSettings(
                  brandId: widget.brandId,
                  ip: ipController.text.trim(),
                  mac: deviceMac,
                  copies: modalCopies,
                );
              }

              final isConnected = await _printerBluetooth.isConnected.timeout(
                const Duration(seconds: 2),
                onTimeout: () => false,
              );
              if (isConnected == true) {
                try {
                  await _printerBluetooth.disconnect().timeout(
                    const Duration(seconds: 2),
                  );
                } catch (_) {}
              }
              await _printerBluetooth
                  .connect(device)
                  .timeout(const Duration(seconds: 8));
              await Future.delayed(const Duration(milliseconds: 700));

              if (!dialogContext.mounted) return;
              setModalState(() {
                isConnectingPrinter = false;
                statusText = 'เชื่อมต่อ Bluetooth สำเร็จ';
              });
            } catch (e) {
              if (!dialogContext.mounted) return;
              setModalState(() {
                isConnectingPrinter = false;
                statusText =
                    'เชื่อมต่อ Bluetooth ไม่สำเร็จ ตรวจสอบว่าเปิดเครื่องและจับคู่ไว้แล้ว';
              });
            }
          }

          Future<void> connectWifiPrinter(StateSetter setModalState) async {
            final printerIp = ipController.text.trim();
            if (printerIp.isEmpty) {
              setModalState(() {
                statusText = 'กรุณากรอก IP เครื่องพิมพ์ Wi-Fi / LAN';
              });
              return;
            }

            setModalState(() {
              isConnectingPrinter = true;
              statusText = 'กำลังเชื่อมต่อ Wi-Fi / LAN...';
            });

            try {
              await prefs.setString('printer_ip_${widget.brandId}', printerIp);
              await DatabaseHelper.instance.savePrinterSettings(
                brandId: widget.brandId,
                ip: printerIp,
                mac: modalSelectedDevice?.address ?? savedMac ?? '',
                copies: modalCopies,
              );

              final socket = await Socket.connect(
                printerIp,
                9100,
                timeout: const Duration(seconds: 5),
              );
              await socket.close();

              if (!dialogContext.mounted) return;
              setModalState(() {
                isConnectingPrinter = false;
                statusText = 'เชื่อมต่อ Wi-Fi / LAN สำเร็จ';
              });
            } catch (e) {
              if (!dialogContext.mounted) return;
              setModalState(() {
                isConnectingPrinter = false;
                statusText =
                    'เชื่อมต่อ Wi-Fi / LAN ไม่สำเร็จ ตรวจสอบ IP และเครือข่าย';
              });
            }
          }

          Future<void> retryPrint(StateSetter setModalState) async {
            setModalState(() {
              isRetryingPrint = true;
              statusText = null;
            });

            final saved = await saveQuickSettings(setModalState);
            if (!saved || !dialogContext.mounted) return;

            setModalState(() {
              statusText = 'กำลังพิมพ์ใบเสร็จอีกครั้ง...';
            });

            final success = await _printReceiptFromPos(
              receiptData,
              showSuccess: true,
            );
            if (!dialogContext.mounted) return;

            if (success) {
              Navigator.of(dialogContext).pop();
              return;
            }

            setModalState(() {
              isRetryingPrint = false;
              statusText =
                  'ยังพิมพ์ไม่สำเร็จ ตรวจสอบเครื่องพิมพ์แล้วลองอีกครั้ง';
            });
          }

          Future<void> refreshPrinters(StateSetter setModalState) async {
            setModalState(() => statusText = 'กำลังค้นหาเครื่องพิมพ์...');
            try {
              final latest = await _printerBluetooth.getBondedDevices().timeout(
                const Duration(seconds: 4),
                onTimeout: () => <bt.BluetoothDevice>[],
              );
              setModalState(() {
                modalDevices = latest;
                if (modalSelectedDevice != null) {
                  final selectedAddress = modalSelectedDevice?.address ?? '';
                  modalSelectedDevice = latest
                      .whereType<bt.BluetoothDevice>()
                      .cast<bt.BluetoothDevice?>()
                      .firstWhere(
                        (device) => device?.address == selectedAddress,
                        orElse: () => null,
                      );
                }
                statusText = latest.isEmpty
                    ? 'ไม่พบเครื่อง Bluetooth ที่จับคู่ไว้'
                    : 'พบเครื่องพิมพ์ ${latest.length} เครื่อง';
              });
            } catch (e) {
              setModalState(() {
                statusText = 'ค้นหาเครื่องพิมพ์ไม่สำเร็จ';
              });
            }
          }

          return StatefulBuilder(
            builder: (context, setModalState) {
              return Dialog(
                elevation: 0,
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.rose500.withOpacity(0.18),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPrinterFailureHeader(
                            onRefresh: () => refreshPrinters(setModalState),
                            onClose: () => Navigator.of(dialogContext).pop(),
                            isLoading: isSaving || isConnectingPrinter || isRetryingPrint,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            child: Column(
                              children: [
                                _buildPrinterFailureNotice(),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(
                                            Icons.print_rounded,
                                            color: AppColors.slate700,
                                            size: 15,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'เลือกเครื่องพิมพ์',
                                            style: TextStyle(
                                              color: AppColors.slate900,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      DropdownButtonFormField<
                                        bt.BluetoothDevice
                                      >(
                                        initialValue: modalSelectedDevice,
                                        isExpanded: true,
                                        items: modalDevices
                                            .whereType<bt.BluetoothDevice>()
                                            .map(
                                              (device) =>
                                                  DropdownMenuItem<
                                                    bt.BluetoothDevice
                                                  >(
                                                    value: device,
                                                    child: Text(
                                                      device.name ??
                                                          device.address ??
                                                          'Unknown printer',
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                            .toList(),
                                        onChanged:
                                            isSaving ||
                                                isConnectingPrinter ||
                                                isRetryingPrint
                                            ? null
                                            : (device) async {
                                                if (device == null) return;
                                                setModalState(() {
                                                  modalSelectedDevice = device;
                                                });
                                                await connectBluetoothPrinter(
                                                  device,
                                                  setModalState,
                                                );
                                              },
                                        decoration:
                                            _printerModalInputDecoration(
                                              'Bluetooth',
                                              Icons.bluetooth_rounded,
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: ipController,
                                        keyboardType: TextInputType.number,
                                        onSubmitted: (_) =>
                                            connectWifiPrinter(setModalState),
                                        decoration:
                                            _printerModalInputDecoration(
                                              'IP เครื่องพิมพ์ Wi-Fi / LAN',
                                              Icons.router_outlined,
                                              hintText: 'เช่น 192.168.0.131',
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'จำนวนสำเนาใบเสร็จ',
                                              style: TextStyle(
                                                color: AppColors.slate600,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          _buildCopyChoice(
                                            copies: 1,
                                            selectedCopies: modalCopies,
                                            onTap: () => setModalState(
                                              () => modalCopies = 1,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildCopyChoice(
                                            copies: 2,
                                            selectedCopies: modalCopies,
                                            onTap: () => setModalState(
                                              () => modalCopies = 2,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (statusText != null) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          statusText!,
                                          style: const TextStyle(
                                            color: AppColors.slate600,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed:
                                            isSaving ||
                                                isConnectingPrinter ||
                                                isRetryingPrint
                                            ? null
                                            : () {
                                                _suppressPrinterFailureModalForSession =
                                                    true;
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFF64748B,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFE2E8F0),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 9,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'ไม่ต้องแสดงอีก',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            isSaving ||
                                                isConnectingPrinter ||
                                                isRetryingPrint
                                            ? null
                                            : () => retryPrint(setModalState),
                                        icon:
                                            isSaving ||
                                                isConnectingPrinter ||
                                                isRetryingPrint
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.print_rounded,
                                                size: 16,
                                              ),
                                        label: Text(
                                          isConnectingPrinter
                                              ? 'กำลังเชื่อมต่อ...'
                                              : isRetryingPrint
                                              ? 'กำลังพิมพ์...'
                                              : isSaving
                                              ? 'กำลังบันทึก...'
                                              : 'พิมพ์อีกครั้ง',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.rose500,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 9,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        isSaving ||
                                            isConnectingPrinter ||
                                            isRetryingPrint
                                        ? null
                                        : () =>
                                              saveQuickSettings(setModalState),
                                    icon: const Icon(
                                      Icons.save_rounded,
                                      size: 15,
                                    ),
                                    label: const Text('บันทึกเครื่องพิมพ์'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.slate700,
                                      side: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 9,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed:
                                      isSaving ||
                                          isConnectingPrinter ||
                                          isRetryingPrint
                                      ? null
                                      : () {
                                          Navigator.of(dialogContext).pop();
                                          _openReceiptSettings();
                                        },
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 15,
                                  ),
                                  label: const Text('เปิดหน้าตั้งค่าเต็ม'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.slate600,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _isPrinterFailureModalOpen = false;
    }
  }

  Widget _buildPrinterFailureHeader({
    required VoidCallback onRefresh,
    required VoidCallback onClose,
    required bool isLoading,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFF1F2), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 76, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE4E6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.print_disabled_rounded,
                    color: AppColors.rose500,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'พิมพ์ใบเสร็จไม่สำเร็จ',
                        style: TextStyle(
                          color: Color(0xFF7F1D1D),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'เลือกเครื่องพิมพ์ในกล่องนี้ แล้วบันทึกเพื่อใช้กับ POS ทันที',
                        style: TextStyle(
                          color: Color(0xFF9F1239),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: isLoading ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  iconSize: 18,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  tooltip: 'ค้นหาเครื่องพิมพ์ใหม่',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.slate700,
                    backgroundColor: Colors.white.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  onPressed: isLoading ? null : onClose,
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 18,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  tooltip: 'ปิด',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.slate700,
                    backgroundColor: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterFailureNotice() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFEA580C),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _printerFailureModalShownCount >= 2
                  ? 'ถ้าไม่อยากให้เด้งอีกในรอบนี้ กด "ไม่ต้องแสดงอีก" ได้เลย'
                  : 'เลือก Wi-Fi หรือ Bluetooth แล้วกดพิมพ์อีกครั้งได้ทันที',
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _printerModalInputDecoration(
    String label,
    IconData icon, {
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, color: AppColors.slate400, size: 16),
      filled: true,
      isDense: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.rose500, width: 1.4),
      ),
    );
  }

  Widget _buildCopyChoice({
    required int copies,
    required int selectedCopies,
    required VoidCallback onTap,
  }) {
    final isActive = copies == selectedCopies;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AppColors.rose500 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.rose500 : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          '$copies',
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.slate700,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Future<bool> _printReceiptFromPos(
    Map<String, dynamic> receiptData, {
    bool showSuccess = false,
  }) async {
    if (_isPrintingReceipt) {
      if (mounted && showSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('กำลังพิมพ์อยู่ กรุณารอสักครู่'),
            backgroundColor: AppColors.slate800,
          ),
        );
      }
      return false;
    }

    _isPrintingReceipt = true;
    var success = false;
    try {
      success = await PrinterService.printReceipt(
        receiptData,
        widget.brandId,
      ).timeout(const Duration(seconds: 14), onTimeout: () => false);
    } catch (e) {
      debugPrint('POS print receipt failed: $e');
    } finally {
      _isPrintingReceipt = false;
    }

    if (!mounted) return success;

    if (success) {
      if (showSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('พิมพ์ใบเสร็จสำเร็จ'),
            backgroundColor: AppColors.emerald500,
          ),
        );
      }
      return true;
    }

    await _showPrinterSettingsAction(receiptData);
    return false;
  }

}
