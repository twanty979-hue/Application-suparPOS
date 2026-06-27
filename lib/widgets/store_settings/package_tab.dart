// lib/widgets/store_settings/package_tab.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../modals/variant_modal.dart';
import '../modals/quota_history_modal.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../theme/app_colors.dart';
import '../../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
import 'package:Pos_Foodscan/services/revenuecat_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

part 'package_upgrade_sheet.dart';

class PackageTab extends StatefulWidget {
  final String currentPlan;
  final DateTime? planExpiryDate;
  final VoidCallback? onUpgradeSuccess;

  const PackageTab({
    super.key,
    required this.currentPlan,
    this.planExpiryDate,
    this.onUpgradeSuccess,
  });

  @override
  State<PackageTab> createState() => _PackageTabState();
}

class _PackageTabState extends State<PackageTab> {
  static const _ink = Color(0xFF0B1224);
  static const _line = Color(0xFFE2E8F0);
  static const _violet = Color(0xFF4F46E5);
  static const _blue = Color(0xFF3B82F6);
  static const _activeTextColor = Color(0xFF2563EB);

  int _billingCycle = 0;
  int _activePlanIndex = 0;
  late PageController _plansController;

  bool _isSubmitting = false;
  List<dynamic> _dbPlans = [];
  bool _isFirstTimeBuyer = false;
  bool _isLoadingPlans = false;

  String _dynamicCurrentPlan = 'free';
  DateTime? _dynamicExpiryDate;
  int? _dynamicDaysLeft;
  
  int _orderCount = 0;
  int _orderLimit = -1;
  List<dynamic> _orderHistory = [];

  Timer? _paymentTimer;

  @override
  void initState() {
    super.initState();
    _dynamicCurrentPlan = widget.currentPlan;
    _dynamicExpiryDate = widget.planExpiryDate;

    _plansController = PageController(viewportFraction: 0.72);
    _fetchDbPlans();
  }

  @override
  void dispose() {
    _paymentTimer?.cancel();
    _plansController.dispose();
    super.dispose();
  }

  Future<void> _fetchDbPlans() async {
    if (!mounted) return;
    setState(() => _isLoadingPlans = true);
    try {
      final accessToken = await StorageService.getToken();

      final response = await http.get(
        Uri.parse(ApiService.availablePlans),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          setState(() {
            _dbPlans = result['plans'] ?? [];
            _isFirstTimeBuyer = result['isFirstTimeBuyer'] ?? false;

            if (result['currentPlan'] != null) {
              _dynamicCurrentPlan = result['currentPlan'];
            }
            if (result['expiryDate'] != null) {
              _dynamicExpiryDate = DateTime.parse(
                result['expiryDate'],
              ).toLocal();
            }
            if (result['daysLeft'] != null) {
              _dynamicDaysLeft = result['daysLeft'];
            }
          });
        }
      }

      // ดึงข้อมูลจำนวนบิลปัจจุบันเพื่อเอาไปโชว์ในแพ็กเกจฟรี
      final quotaRes = await http.get(
        Uri.parse('${ApiService.baseUrl}/pos/quota'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      );
      if (quotaRes.statusCode == 200) {
        final quotaResult = jsonDecode(quotaRes.body);
        if (quotaResult['success'] == true) {
          setState(() {
            _orderCount = quotaResult['usage'] ?? 0;
            _orderLimit = quotaResult['limit'] ?? -1;
            _orderHistory = quotaResult['history'] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint("🚨 Fetch Plans Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingPlans = false);
    }
  }

  void _startPaymentPolling(String chargeId, String planId) {
    _paymentTimer?.cancel();
    _paymentTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final accessToken = await StorageService.getToken();
        final brandId = await StorageService.getBrandId();
        final periodStr = _billingCycle == 0 ? 'monthly' : 'yearly';

        final response = await http.post(
          Uri.parse('${ApiService.baseUrl}/payments/status'),
          headers: {
            'Content-Type': 'application/json',
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'brandId': brandId,
            'chargeId': chargeId,
            'plan': planId,
            'period': periodStr,
          }),
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          if (result['status'] == 'successful') {
            timer.cancel();
            if (mounted) {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('ชำระเงินสำเร็จ อัปเกรดแพ็กเกจแล้ว!'),
                  backgroundColor: Colors.green,
                ),
              );
              _fetchDbPlans();
              widget.onUpgradeSuccess?.call();
            }
          } else if (result['status'] == 'failed') {
            timer.cancel();
            if (mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('รายการล้มเหลว กรุณาลองใหม่'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint("Polling Error: $e");
      }
    });
  }

  void _showQrCodeDialog(String qrImageUrl, String chargeId, String planId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'สแกน QR Code',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'รองรับทุกแอปธนาคาร',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SvgPicture.network(
                      qrImageUrl,
                      fit: BoxFit.cover,
                      placeholderBuilder: (BuildContext context) =>
                          const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      _paymentTimer?.cancel();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'ยกเลิก',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _processUpgradePlan(String planId) async {
    try {
      final String? accessToken = await StorageService.getToken();
      final String brandId = await StorageService.getBrandId();

      if (brandId.isEmpty) throw Exception('ไม่พบข้อมูลร้านค้า');
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('เซสชันหมดอายุ กรุณาล็อกอินใหม่อีกครั้ง');
      }

      final periodStr = _billingCycle == 0 ? 'monthly' : 'yearly';

      final response = await http.post(
        Uri.parse(ApiService.paymentPromptpay),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'brandId': brandId,
          'newPlan': planId,
          'period': periodStr,
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        if (result['success'] == true && result['type'] == 'promptpay') {
          final String qrImageUrl = result['qrImage'] ?? '';
          final String chargeId = result['chargeId'] ?? '';
          if (mounted) {
            setState(() => _isSubmitting = false);
            _showQrCodeDialog(qrImageUrl, chargeId, planId);
            _startPaymentPolling(chargeId, planId);
          }
        } else if (result['success'] == true && result['type'] == 'free') {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('รับสิทธิ์ฟรี/อัปเกรดสำเร็จ!'),
                backgroundColor: Colors.green,
              ),
            );
            _fetchDbPlans();
            widget.onUpgradeSuccess?.call();
          }
        } else {
          throw Exception(result['error'] ?? 'สร้างรายการชำระเงินไม่สำเร็จ');
        }
      } else if (response.statusCode == 401) {
        throw Exception(
          'สิทธิ์การเข้าถึงไม่ถูกต้อง (401) กรุณาลองเปิดหน้าตั้งค่าใหม่อีกครั้ง',
        );
      } else {
        throw Exception('Server Error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('ระบบมีปัญหา'),
              content: Text(e.toString().replaceAll('Exception: ', '')),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('ตกลง'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  Future<void> _purchasePlanWithRevenueCat(String planId) async {
    try {
      final String brandId = await StorageService.getBrandId();
      if (brandId.isEmpty) {
        throw Exception('ไม่พบข้อมูลร้านค้า กรุณาเข้าสู่ระบบใหม่');
      }

      final periodStr = _billingCycle == 0 ? 'monthly' : 'yearly';
      final customerInfo = await RevenueCatService.purchasePlan(
        planId: planId,
        period: periodStr,
      );

      final activePlan = RevenueCatService.activePlanFrom(customerInfo);
      if (mounted) {
        if (activePlan != null) {
          setState(() {
            _dynamicCurrentPlan = activePlan;
            _isSubmitting = false;
          });
        } else {
          setState(() => _isSubmitting = false);
        }

        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ชำระเงินผ่าน Google Play สำเร็จ กำลังอัปเดตแพ็กเกจ'),
            backgroundColor: Colors.green,
          ),
        );
        await _fetchDbPlans();
        widget.onUpgradeSuccess?.call();
      }
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        return;
      }

      _showPaymentError(_revenueCatErrorMessage(errorCode, e.message));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showPaymentError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _restoreRevenueCatPurchases() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      final customerInfo = await RevenueCatService.restorePurchases();
      final activePlan = RevenueCatService.activePlanFrom(customerInfo);

      if (!mounted) return;
      setState(() {
        if (activePlan != null) _dynamicCurrentPlan = activePlan;
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activePlan == null
                ? 'ไม่พบรายการซื้อที่กู้คืนได้'
                : 'กู้คืนรายการซื้อสำเร็จ กำลังอัปเดตแพ็กเกจ',
          ),
          backgroundColor: activePlan == null ? Colors.orange : Colors.green,
        ),
      );
      await _fetchDbPlans();
      if (activePlan != null) widget.onUpgradeSuccess?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showPaymentError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _showPaymentError(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ระบบชำระเงินมีปัญหา'),
          content: Text(message),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ตกลง'),
            ),
          ],
        );
      },
    );
  }

  String _revenueCatErrorMessage(PurchasesErrorCode code, String? detail) {
    switch (code) {
      case PurchasesErrorCode.productNotAvailableForPurchaseError:
      case PurchasesErrorCode.configurationError:
        return 'ยังตั้งค่าสินค้าใน RevenueCat/Google Play ไม่ครบ กรุณาตรวจ product id, offering และ entitlement';
      case PurchasesErrorCode.networkError:
      case PurchasesErrorCode.offlineConnectionError:
        return 'เชื่อมต่อระบบชำระเงินไม่ได้ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่';
      case PurchasesErrorCode.paymentPendingError:
        return 'รายการชำระเงินอยู่ระหว่างดำเนินการ เมื่อ Google Play ยืนยันแล้วระบบจะอัปเดตให้อัตโนมัติ';
      default:
        return detail ?? 'ไม่สามารถทำรายการชำระเงินได้ กรุณาลองใหม่';
    }
  }

  int _getPlanRank(String planId) {
    switch (planId.toLowerCase()) {
      case 'ultimate':
        return 3;
      case 'pro':
        return 2;
      case 'basic':
        return 1;
      case 'free':
      default:
        return 0;
    }
  }

  List<String> _getPlanFeatures(String planId) {
    switch (planId.toLowerCase()) {
      case 'free':
        return [
          'คิดเงินหน้าร้านไม่จำกัด',
          
          '100 ออเดอร์/เดือน',
          'Dashboard ย้อนหลัง 30 วัน',
        ];
      case 'basic':
        return [
          
          
          'คิดเงินได้ไม่จำกัด',
          'ออเดอร์ไม่จำกัด',
          'Dashboard ไม่จำกัดย้อนหลัง',
          
          
        ];
      case 'pro':
        return [
          
          
          'คิดเงินได้ไม่จำกัด',
          'ออเดอร์ไม่จำกัด',
          'Dashboard ขั้นสูง',
          'Export รายงาน (Excel)',
          'ระบบพนักงานสูงสุด 3 คน',

          
        ];
      case 'ultimate':
        return [
          'สิทธิ์ใช้งานได้ทุกธีม',
         
       
          'Dashboard ขั้นสูง',
          'Export รายงาน (Excel)',
          'ระบบพนักงานสูงสุด 10 คน',
        ];
      default:
        return ['ฟีเจอร์พื้นฐานของระบบ'];
    }
  }

  Color _getPlanBtnColor(String planId) {
    if (planId == 'free') return const Color(0xFFF1F5F9);
    if (planId == 'basic') {
      return const Color(0xFF0F172A); // 🌟 ปุ่มสีกรมเท่ๆ ตามภาพ
    }
    if (planId == 'pro') return const Color(0xFF4F46E5);
    return const Color(0xFF9333EA);
  }

  Color _getPlanBtnTextColor(String planId) {
    return planId == 'free' ? const Color(0xFF475569) : Colors.white;
  }

  String _formatCurrency(num amount) => NumberFormat('#,###').format(amount);

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('package-tab'),
      children: [_buildCurrentPlanCard()],
    );
  }

  // 🌟 3. ปรับโครงสร้างสลับเปลี่ยนการ์ดคัดตามระดับสิทธิ์จริง
  Widget _buildCurrentPlanCard() {
    final plan = _dynamicCurrentPlan.toLowerCase();

    if (plan == 'ultimate') {
      return _buildUltimatePlanCard();
    } else if (plan == 'pro') {
      return _buildProPlanCard();
    } else if (plan == 'basic') {
      return _buildBasicPlanCard();
    }

    return _buildFreePlanCard();
  }

  // =========================================================================
  // 🌟 4. [ULTIMATE CARD] - ดีไซน์ดาร์กโหมดหรูหราขอบทองหรูหรา (ตามรูปที่ 1)
  // =========================================================================
  Widget _buildUltimatePlanCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withOpacity(0.15),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2212),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFFD4AF37),
                    width: 1.5,
                  ),
                ),
                child: const Text(
                  'EXCLUSIVE',
                  style: TextStyle(
                    color: Color(0xFFD4AF37),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Icon(
                Icons.workspace_premium_outlined,
                color: Color(0xFFD4AF37),
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Ultimate',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
          _buildExpiryBar(
            textColor: Colors.white,
            boxBgColor: Colors.white.withOpacity(0.06),
            btnBgColor: const Color(0xFFEF4444),
          ),
          const SizedBox(height: 28),
          _buildPremiumMetric(
            Icons.dynamic_feed_rounded,
            'THEMES',
            '55 ธีม + พรีเมียม',
            const Color(0xFFD4AF37),
          ),
          const SizedBox(height: 18),
          _buildPremiumMetric(
            Icons.check_rounded,
            'ORDERS',
            'ไม่จำกัด',
            const Color(0xFFD4AF37),
          ),
          const SizedBox(height: 48),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE5C173), Color(0xFFC0974A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton(
              onPressed: _showUpgradeSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'ต่ออายุแพ็กเกจ',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.workspace_premium,
                    color: Color(0xFF111827),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 🌟 5. [PRO CARD] - ดีไซน์การ์ดขาวนีออนไล่เฉด RGB สดใส (ตามรูปที่ 2)
  // =========================================================================
  Widget _buildProPlanCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFC7D2FE),
          width: 2,
        ), // ขอบเส้นสว่างพรีเมียม
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFDDD6FE)),
                ),
                child: const Text(
                  'CURRENT PLAN',
                  style: TextStyle(
                    color: _violet,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Icon(
                Icons.star_purple500_rounded,
                color: _violet,
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Pro',
            style: TextStyle(
              color: _ink,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
          _buildExpiryBar(
            textColor: _ink,
            boxBgColor: const Color(0xFFF8FAFC),
            btnBgColor: const Color(0xFFEF4444),
          ),
          const SizedBox(height: 28),
          _buildPlanMetric(Icons.diamond_outlined, 'THEMES', '7 ธีม'),
          const SizedBox(height: 18),
          _buildPlanMetric(Icons.check_rounded, 'ORDERS', 'ไม่จำกัด'),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _showUpgradeSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: _violet,
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: _violet.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'ต่ออายุแพ็กเกจ',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.autorenew_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 🌟 6. [BASIC CARD] - ดีไซน์โมเดิร์นมินิมอลขาว-เทามาดสปอร์ต (ตามรูปที่ 3)
  // =========================================================================
  Widget _buildBasicPlanCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: const Text(
                  'CURRENT PLAN',
                  style: TextStyle(
                    color: _activeTextColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Icon(Icons.storefront_outlined, color: _blue, size: 26),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Basic',
            style: TextStyle(
              color: _ink,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
          _buildExpiryBar(
            textColor: _ink,
            boxBgColor: const Color(0xFFF8FAFC),
            btnBgColor: const Color(0xFF64748B),
          ),
          const SizedBox(height: 28),
          _buildPlanMetric(Icons.diamond_outlined, 'THEMES', '4 ธีม'),
          const SizedBox(height: 18),
          _buildPlanMetric(Icons.check_rounded, 'ORDERS', 'ไม่จำกัด'),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _showUpgradeSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'อัปเกรดแพ็กเกจ 👑',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 🌟 7. [FREE CARD] - แพลนฟรีสแตนดาร์ดเริ่มต้นใช้งาน
  // =========================================================================
  Widget _buildFreePlanCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 30, 32, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEAF0F7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Text(
                  'CURRENT PLAN',
                  style: TextStyle(
                    color: _activeTextColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (_orderHistory.isNotEmpty) {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => QuotaHistoryModal(history: _orderHistory),
                    );
                  }
                },
                child: const Icon(Icons.storefront_outlined, color: _blue, size: 26),
              ),
            ],
          ),
          const SizedBox(height: 34),
          Text(
            _dynamicCurrentPlan.toUpperCase(),
            style: const TextStyle(
              color: _ink,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'ใช้งานได้ตลอดชีพ',
            style: TextStyle(
              color: AppColors.slate600,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 30),
          _buildPlanMetric(Icons.storefront_rounded, 'POS', 'ขายหน้าร้านไม่จำกัด'),
          const SizedBox(height: 18),
          _buildPlanMetric(Icons.qr_code_scanner_rounded, 'QR BILL', '$_orderCount/$_orderLimit บิล'),
          const SizedBox(height: 56),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _showUpgradeSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                elevation: 12,
                shadowColor: _ink.withOpacity(0.22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'อัปเกรดแพ็กเกจ',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 🛠️ UTILS UI REUSABLE WIDGETS
  // =========================================================================

  // กล่องแถบโชว์วันหมดอายุ + เม็ดกระดุมสีแดงเด้งเตือนจำนวนวัน (เหมือนในรูปเป๊ะๆ)
  Widget _buildExpiryBar({
    required Color textColor,
    required Color boxBgColor,
    required Color btnBgColor,
  }) {
    int daysLeft = _dynamicDaysLeft ?? 0;
    if (daysLeft < 0) daysLeft = 0;

    String expiryText = '-';
    if (_dynamicExpiryDate != null) {
      final thaiMonths = [
        'ม.ค.',
        'ก.พ.',
        'มี.ค.',
        'เม.ย.',
        'พ.ค.',
        'มิ.ย.',
        'ก.ค.',
        'ส.ค.',
        'ก.ย.',
        'ต.ค.',
        'พ.ย.',
        'ธ.ค.',
      ];
      String monthStr = thaiMonths[_dynamicExpiryDate!.month - 1];
      String yearStr = (_dynamicExpiryDate!.year + 543).toString().substring(2);
      expiryText = '${_dynamicExpiryDate!.day} $monthStr $yearStr';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: boxBgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'หมดอายุวันที่',
                style: TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                expiryText,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: btnBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'อีก $daysLeft วัน',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumMetric(
    IconData icon,
    String label,
    String value,
    Color goldColor,
  ) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: goldColor.withOpacity(0.4), width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: goldColor, size: 20),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFA1A1AA),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlanMetric(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _blue, size: 20),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9AA8BA),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
