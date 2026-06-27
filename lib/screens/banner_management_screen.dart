// lib/screens/banner_management_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
// ❌ ลบ SharedPreferences และ dotenv ทิ้งไปเลยครับ ไม่ใช้แล้ว!
import '../api_service.dart'; // 🌟 1. นำเข้า ApiService เพื่อใช้ระบบสลับลิงก์ Auto
import 'package:Pos_Foodscan/services/storage_service.dart'; // 🌟 2. ใช้ตู้เซฟดิจิทัล
import '../widgets/modals/add_banner_modal.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/suparpos_loading.dart';
import '../theme/app_colors.dart';
import '../widgets/products/products_top_bar.dart';
import '../widgets/bouncing_card.dart';

class BannerManagementScreen extends StatefulWidget {
  const BannerManagementScreen({super.key});

  @override
  State<BannerManagementScreen> createState() => _BannerManagementScreenState();
}

class _BannerManagementScreenState extends State<BannerManagementScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<dynamic> banners = [];
  bool isLoading = true;
  String errorMessage = '';
  String? brandId;
  String? accessToken;

  @override
  void initState() {
    super.initState();
    _loadSessionAndFetch();
  }

  String? _getBannerImageUrl(String? imageName) {
    if (imageName == null) return null;
    final cleaned = imageName.trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('http://') || cleaned.startsWith('https://'))
      return cleaned;
    return "https://img.pos-foodscan.com/$cleaned";
  }

  // 🌟 โหลดทั้ง Brand ID และ Token จากตู้เซฟดิจิทัลเท่านั้น
  Future<void> _loadSessionAndFetch() async {
    try {
      final savedBrandId = await StorageService.getBrandId();
      final savedToken = await StorageService.getToken();

      if (savedBrandId.isNotEmpty && savedToken != null) {
        setState(() {
          brandId = savedBrandId;
          accessToken = savedToken;
        });
        await fetchBannerData();
      } else {
        setState(() {
          errorMessage = 'ไม่พบเซสชันการล็อกอิน กรุณาล็อกอินใหม่อีกครั้ง';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'เกิดข้อผิดพลาดหน่วยความจำเครื่อง: $e';
        isLoading = false;
      });
    }
  }

  // 📥 GET: ดึงข้อมูลแบนเนอร์ (ใช้ ApiService.baseUrl สลับลิงก์อัตโนมัติ)
  Future<void> fetchBannerData() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    try {
      final response = await http.get(
        Uri.parse(
          "${ApiService.baseUrl}/banners",
        ), // 🚀 ดึงลิงก์ฉลาดจาก ApiService
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          setState(() {
            banners = responseData['banners'] ?? [];
            isLoading = false;
          });
        } else {
          throw responseData['error'] ?? 'เซิร์ฟเวอร์ตอบรับข้อมูลล้มเหลว';
        }
      } else if (response.statusCode == 401) {
        throw 'เซสชันหมดอายุ กรุณาล็อกอินใหม่อีกครั้ง (401)';
      } else {
        throw 'การเชื่อมต่อผิดพลาด (Status Code: ${response.statusCode})';
      }
    } catch (e) {
      setState(() {
        errorMessage = '$e';
        isLoading = false;
      });
    }
  }

  // 🔄 สลับสถานะแบนเนอร์ (ใช้ ApiService.baseUrl)
  Future<void> _toggleBannerStatus(String bannerId, bool currentStatus) async {
    try {
      final response = await http.post(
        Uri.parse(
          "${ApiService.baseUrl}/banners",
        ), // 🚀 ดึงลิงก์ฉลาดจาก ApiService
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'id': bannerId,
          'image_name': banners.firstWhere(
            (b) => b['id'] == bannerId,
          )['image_name'],
          'is_active': !currentStatus,
        }),
      );

      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 && resData['success'] == true) {
        setState(() {
          final index = banners.indexWhere((b) => b['id'] == bannerId);
          if (index != -1) banners[index]['is_active'] = !currentStatus;
        });
      }
    } catch (e) {
      print("Toggle banner status failed: $e");
    }
  }

  void _openAddBannerModal({Map<String, dynamic>? initialBannerData}) {
    if (brandId == null) return;
    showDialog(
      context: context,
      builder: (context) {
        return AddBannerModal(
          brandId: brandId!,
          initialData: initialBannerData,
          onSave: (formData) async {
            if (initialBannerData != null) {
              formData['id'] = initialBannerData['id'];
            }
            await _saveBannerToDatabase(formData);
          },
        );
      },
    );
  }

  // 📤 POST: สั่งเซฟแบนเนอร์ใหม่ (ใช้ ApiService.baseUrl)
  Future<void> _saveBannerToDatabase(Map<String, dynamic> payload) async {
    try {
      final response = await http.post(
        Uri.parse(
          "${ApiService.baseUrl}/banners",
        ), // 🚀 ดึงลิงก์ฉลาดจาก ApiService
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(payload),
      );

      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 && resData['success'] == true) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกข้อมูลเรียบร้อย! 🖼️🎉'),
              backgroundColor: Colors.green,
            ),
          );
        await fetchBannerData();
      } else {
        throw resData['error'] ?? 'เซิร์ฟเวอร์ปฏิเสธการบันทึก';
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกล้มเหลว: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bgLight ?? const Color(0xFFF8FAFC),
      drawer: const AppSidebar(activeMenu: 'banners'),
      body: Builder(
        builder: (context) {
          return SafeArea(
            child: Column(
              children: [
                ProductsTopBar(
                  activeTab: 'banner',
                  onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  onTabSelected: (tabId) {
                    // ลอจิกเด้งหน้าจัดการใน ProductsTopBar แล้ว
                  },
                ),

                // --- 🔍 บาร์หัวข้อแสดงจำนวนสไลด์แบนเนอร์ ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'แบนเนอร์สไลด์โปรโมชัน',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          Text(
                            'เปิดใช้งานอยู่ทั้งหมด ${banners.where((b) => b['is_active'] == true).length} รูป',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => _openAddBannerModal(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'เพิ่มแบนเนอร์',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- 🖼️ ตารางรายการแสดงแบนเนอร์สไลด์ ---
                Expanded(
                  child: isLoading
                      ? const SuparPosLoading(fullScreen: false)
                      : banners.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.collections_outlined,
                                size: 72,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'ยังไม่มีแบนเนอร์สไลด์โชว์ในร้าน',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          itemCount: banners.length,
                          itemBuilder: (context, index) {
                            final b = banners[index];
                            final String bId = b['id']?.toString() ?? '';
                            final String bTitle =
                                b['title']?.toString() ?? 'โปรโมชันหน้าร้าน';
                            final bool isActive = b['is_active'] ?? true;
                            final String? imageUrl = _getBannerImageUrl(
                              b['image_name'],
                            );

                            return BouncingCard(
                              onTap: () => _openAddBannerModal(initialBannerData: b),
                              glowColor: const Color(0xFF3B82F6),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isActive
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFFE2E8F0),
                                    width: isActive ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AspectRatio(
                                      aspectRatio: 21 / 9,
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(14),
                                                  ),
                                              child: imageUrl != null
                                                  ? Image.network(
                                                      imageUrl,
                                                      width: double.infinity,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : Container(
                                                      color: const Color(
                                                        0xFFF1F5F9,
                                                      ),
                                                      child: const Icon(
                                                        Icons.image,
                                                        size: 48,
                                                        color: Color(0xFFCBD5E1),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 12,
                                            right: 12,
                                            child: GestureDetector(
                                              onTap: () => _openAddBannerModal(
                                                initialBannerData: b,
                                              ),
                                              child: Container(
                                                width: 36,
                                                height: 36,
                                                decoration: const BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.edit_outlined,
                                                  color: Color(0xFF64748B),
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'แสดงผลแบนเนอร์หน้าร้าน',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 14,
                                                color: Color(0xFF1E293B),
                                              ),
                                            ),
                                          ),
                                          Switch(
                                            value: isActive,
                                            activeColor: const Color(0xFF10B981),
                                            onChanged: (val) =>
                                                _toggleBannerStatus(
                                                  bId,
                                                  isActive,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
