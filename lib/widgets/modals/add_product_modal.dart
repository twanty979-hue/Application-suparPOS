import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http_parser/http_parser.dart'; // ✅ เพิ่มบรรทัดนี้
import '../../api_service.dart';
import '../../services/storage_service.dart';

class AddProductModal extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final Function()? onDelete;
  final List<dynamic> categories;
  final Map<String, dynamic>? initialData;
  final String brandId; // ✅ 1. เพิ่มตัวแปรรับค่าตรงนี้

  const AddProductModal({
    super.key,
    required this.onSave,
    required this.categories,
    required this.brandId, // ✅ 2. บังคับรับค่าใน Constructor
    this.initialData,
    this.onDelete,
  });

  @override
  State<AddProductModal> createState() => _AddProductModalState();
}

class _AddProductModalState extends State<AddProductModal> {
  final _formKey = GlobalKey<FormState>();

  // Controllers สำหรับข้อมูลพื้นฐานอาหาร
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _priceSpecialController = TextEditingController();
  final TextEditingController _priceJumboController = TextEditingController();

  String? _selectedCategoryId;
  bool _isRecommended = false;
  bool _isAvailable = true;
  bool _isCreatingCategory = false;
  bool _isSaving = false;
  bool _allowPop = false;
  late List<dynamic> _categories;

  // State ตัวเลือกเสริม (Options JSONB)
  List<Map<String, dynamic>> _customOptions = [];

  // --- 📸 ตัวแปรสำหรับจัดการรูปภาพ (ใช้ Uint8List เพื่อให้รันบน Web ได้) ---
  Uint8List? _selectedImageBytes;
  bool _isUploading = false;
  String? _uploadedImageName;

  @override
  void initState() {
    super.initState();
    _categories = List<dynamic>.from(widget.categories);

    // ✅ ถ้ามี initialData ส่งเข้ามา (โหมดแก้ไข) ให้เอาข้อมูลมายัดใส่ Controller
    if (widget.initialData != null) {
      final data = widget.initialData!;

      _nameController.text = data['name']?.toString() ?? '';
      _priceController.text = data['price']?.toString() ?? '';

      if (data['price_special'] != null &&
          data['price_special'].toString() != 'null') {
        _priceSpecialController.text = data['price_special'].toString();
      }
      if (data['price_jumbo'] != null &&
          data['price_jumbo'].toString() != 'null') {
        _priceJumboController.text = data['price_jumbo'].toString();
      }

      _selectedCategoryId = data['category_id']?.toString();
      _isRecommended = data['is_recommended'] ?? false;
      _isAvailable = data['is_available'] ?? true;
      _uploadedImageName = data['image_name']?.toString(); // เก็บชื่อรูปเดิมไว้

      // ดึงตัวเลือกเสริม (Options) เดิมมาแสดง
      if (data['options'] != null && data['options'] is List) {
        _customOptions = List<Map<String, dynamic>>.from(
          (data['options'] as List).map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      }
    }
    // โหมดสร้างเมนูใหม่
    else {
      if (_categories.isNotEmpty) {
        _selectedCategoryId = _categories[0]['id']?.toString();
      }
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    final categoryName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'เพิ่มหมวดหมู่',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'ชื่อหมวดหมู่',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    );
    if (categoryName == null || !mounted) return;
    setState(() => _isCreatingCategory = true);

    try {
      final token = await StorageService.getToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/categories'),
        headers: headers,
        body: jsonEncode({
          'brand_id': widget.brandId,
          'name': categoryName,
          'sort_order': _categories.length,
        }),
      );
      final data = jsonDecode(response.body);
      if ((response.statusCode != 200 && response.statusCode != 201) ||
          data['success'] == false) {
        throw data['error'] ?? 'เพิ่มหมวดหมู่ไม่สำเร็จ';
      }

      dynamic category = data['data'] ?? data['category'];
      if (category is! Map || category['id'] == null) {
        final productsResponse = await http.get(
          Uri.parse('${ApiService.baseUrl}/products'),
          headers: headers,
        );
        final productsData = jsonDecode(productsResponse.body);
        final refreshedCategories = List<dynamic>.from(
          productsData['categories'] ?? [],
        );
        _categories = refreshedCategories;
        category = refreshedCategories.cast<dynamic>().firstWhere(
          (item) => item['name']?.toString() == categoryName,
          orElse: () => null,
        );
      } else {
        _categories.add(Map<String, dynamic>.from(category));
      }

      if (!mounted) return;
      setState(() {
        if (category is Map && category['id'] != null) {
          _selectedCategoryId = category['id'].toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เพิ่มหมวดหมู่ไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreatingCategory = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _priceSpecialController.dispose();
    _priceJumboController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    // 1. ดึงรูปมาจากคลังภาพปกติ
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      if (!mounted) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'ครอปรูปสินค้า 1:1',
            toolbarColor: const Color(0xFF0F172A),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            aspectRatioPresets: const [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: 'ครอปรูปสินค้า 1:1',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPresets: const [CropAspectRatioPreset.square],
          ),
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
            size: const CropperSize(width: 520, height: 520),
          ),
        ],
      );

      if (croppedFile == null) return;

      setState(() {
        _isUploading = true;
      });

      try {
        // 2. ⚡️ พระเอกของเรา: สั่งบีบอัดและแปลงไฟล์ตรงนี้ให้กลายเป็น .webp ทันที
        // โค้ดนี้จะแปลงไฟล์ภาพในหน่วยความจำ (Uint8List) ให้เป็นฟอร์แมต webp คุณภาพ 80% (ชัดแต่เบาหวิว)
        final compressedBytes = await FlutterImageCompress.compressWithFile(
          croppedFile.path,
          format: CompressFormat.webp,
          quality: 80, // ปรับความคมชัด 80% กำลังสวยและเบามาก
        );

        if (compressedBytes == null) throw 'แปลงไฟล์เป็น WebP ไม่สำเร็จ';

        setState(() {
          _selectedImageBytes = compressedBytes; // เก็บไปแสดงผลพรีวิวบน UI
        });

        final String baseUrl = ApiService.baseUrl;
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/upload'),
        );

        // บอกโฟลเดอร์ปลายทาง
        request.fields['folder'] = widget.brandId;

        // เปลี่ยนชื่อไฟล์ปลายทางให้ลงท้ายด้วย .webp เพื่อให้ฝั่งหลังบ้านรับไปบันทึกถูกนามสกุล
        String originalName = pickedFile.name;
        String webpFileName = originalName.contains('.')
            ? '${originalName.substring(0, originalName.lastIndexOf('.'))}.webp'
            : '$originalName.webp';

        // ... (โค้ดก่อนหน้า) ...

        // โยนไฟล์ที่เป็น WebP ยิงเข้า API พร้อมประกาศศักดาว่าเป็นรูปภาพ!
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            compressedBytes,
            filename: webpFileName,
            contentType: MediaType(
              'image',
              'webp',
            ), // 🎯 เติมบรรทัดนี้เข้าไปครับนาย!
          ),
        );

        var response = await request.send();
        // ... (โค้ดส่วนที่เหลือ) ...
        if (response.statusCode == 200) {
          final responseData = await response.stream.bytesToString();
          final jsonResult = jsonDecode(responseData);

          // ดึงค่า fileName ที่ส่งกลับมาจาก Next.js API (ซึ่งจะพ่วงชื่อโฟลเดอร์มาแล้ว เช่น "brand_id/xxxx.webp")
          final shortFileName =
              jsonResult['fileName'] ?? jsonResult['image_name'] ?? '';

          if (mounted) {
            setState(() {
              // ✅ แก้เรื่องโฟลเดอร์ซ้ำ: เอาโดเมนหลักมาต่อกับ shortFileName ตรงๆ ได้เลย ไม่ต้องใส่ brandId ซ้ำแล้วครับ
              _uploadedImageName =
                  "https://img.pos-foodscan.com/$shortFileName";
            });

            print(
              "✅ อัปโหลดรูปสำเร็จ! URL เต็มก้อนที่จะลง DB คือ: $_uploadedImageName",
            );

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('อัปโหลดรูปภาพ WebP สำเร็จ! 📸'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw 'เซิร์ฟเวอร์ปฏิเสธการอัปโหลด (Status: ${response.statusCode})';
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('อัปโหลดพัง: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }

  // 🎯 ฟังก์ชันจำลองแสดงรูปภาพในกล่อง
  Widget _buildImagePreview() {
    if (_isUploading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          SizedBox(height: 8),
          Text(
            'กำลังอัปโหลด...',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      );
    }

    if (_selectedImageBytes != null) {
      return Image.memory(
        _selectedImageBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    if (_uploadedImageName != null && _uploadedImageName!.isNotEmpty) {
      String displayUrl = _uploadedImageName!;
      if (!displayUrl.startsWith('http')) {
        if (displayUrl.contains('/')) {
          displayUrl = "https://img.pos-foodscan.com/$displayUrl";
        } else {
          displayUrl =
              "https://xvhibjejvbriotfpunvv.supabase.co/storage/v1/object/public/images/$displayUrl";
        }
      }
      return Image.network(
        displayUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: Color(0xFF94A3B8),
          ),
        ),
      );
    }

    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          size: 28,
          color: Color(0xFF94A3B8),
        ),
        SizedBox(height: 4),
        Text(
          'เลือกรูป 1:1',
          style: TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _buildProductData() {
    return {
      'name': _nameController.text.trim(),
      'category_id': _selectedCategoryId,
      'price': double.tryParse(_priceController.text) ?? 0,
      'price_special': double.tryParse(_priceSpecialController.text),
      'price_jumbo': double.tryParse(_priceJumboController.text),
      'is_recommended': _isRecommended,
      'is_available': _isAvailable,
      'options': _customOptions,
      'image_name': _uploadedImageName,
    };
  }

  Future<void> _closeModal() async {
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveAndClose() async {
    if (_isSaving) return;
    if (_nameController.text.trim().isEmpty ||
        double.tryParse(_priceController.text) == null ||
        _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อ หมวดหมู่ และราคาให้ครบ')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final saveResult = await Future.sync(
        () => widget.onSave(_buildProductData()),
      );
      if (saveResult == false) return;
      await _closeModal();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('บันทึกไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _hasUnsavedChanges() {
    if (widget.initialData != null) {
      final data = widget.initialData!;
      final oldName = data['name']?.toString() ?? '';
      final oldPrice = data['price']?.toString() ?? '';
      final oldPriceSpecial = (data['price_special'] != null && data['price_special'].toString() != 'null') ? data['price_special'].toString() : '';
      final oldPriceJumbo = (data['price_jumbo'] != null && data['price_jumbo'].toString() != 'null') ? data['price_jumbo'].toString() : '';
      final oldCategoryId = data['category_id']?.toString();
      final oldIsRecommended = data['is_recommended'] ?? false;
      final oldIsAvailable = data['is_available'] ?? true;
      final oldImageName = data['image_name']?.toString();

      if (_nameController.text != oldName) return true;
      if (_priceController.text != oldPrice) return true;
      if (_priceSpecialController.text != oldPriceSpecial) return true;
      if (_priceJumboController.text != oldPriceJumbo) return true;
      if (_selectedCategoryId != oldCategoryId && _selectedCategoryId != null) return true;
      if (_isRecommended != oldIsRecommended) return true;
      if (_isAvailable != oldIsAvailable) return true;
      if (_uploadedImageName != oldImageName) return true;
      if (_selectedImageBytes != null) return true;

      final oldOptionsLen = (data['options'] != null && data['options'] is List) ? (data['options'] as List).length : 0;
      if (_customOptions.length != oldOptionsLen) return true;
      
      return false;
    } else {
      if (_nameController.text.isNotEmpty) return true;
      if (_priceController.text.isNotEmpty) return true;
      if (_priceSpecialController.text.isNotEmpty) return true;
      if (_priceJumboController.text.isNotEmpty) return true;
      if (_isRecommended != false) return true;
      if (_isAvailable != true) return true;
      if (_selectedImageBytes != null) return true;
      if (_customOptions.isNotEmpty) return true;
      return false;
    }
  }

  Future<void> _requestClose() async {
    if (_isSaving) return;
    
    if (!_hasUnsavedChanges()) {
      await _closeModal();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.save_outlined,
                        color: Color(0xFF2563EB),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'บันทึกก่อนออกไหม?',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF94A3B8),
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Text(
                    'มีข้อมูลที่ยังไม่ได้บันทึก เลือกอัปเดตสินค้า หรือออกโดยไม่เก็บการเปลี่ยนแปลง',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.45,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, 'discard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(color: Color(0xFFFECACA)),
                            backgroundColor: const Color(0xFFFEF2F2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'ไม่บันทึก',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(dialogContext, 'save'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(
                            Icons.check_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'บันทึก',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (choice == 'save') {
      await _saveAndClose();
    } else if (choice == 'discard') {
      await _closeModal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Container(
        height: screenHeight * 0.82,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // --- HEADER BAR ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'สร้าง/แก้ไข เมนูอาหาร',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Row(
                    children: [
                      if (widget.initialData != null && widget.onDelete != null)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: () async {
                            widget.onDelete!();
                            await _closeModal();
                          },
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _requestClose,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF64748B),
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // --- SCROLLABLE FORM CONTENT ---
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildBaseDetailsTab(),
                      const SizedBox(height: 10),
                      _buildOptionsTab(),
                    ],
                  ),
                ),
              ),
            ),

            // --- FIXED BOTTOM BUTTON ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  if (widget.initialData != null) ...[
                    Expanded(
                      flex: 1,
                      child: SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          onPressed: widget.onDelete == null
                              ? null
                              : () async {
                                  widget.onDelete!();
                                  await _closeModal();
                                },
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFEF4444),
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveAndClose,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.save_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                        label: Text(
                          _isSaving ? 'กำลังบันทึก...' : 'บันทึกและอัปเดต',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          disabledBackgroundColor: const Color(0xFF93C5FD),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBaseDetailsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final imageSize = constraints.maxWidth < 340 ? 96.0 : 112.0;
            final fieldBorder = OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: imageSize,
                  child: GestureDetector(
                    onTap: _isUploading ? null : _pickAndUploadImage,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: _buildImagePreview(),
                          ),
                        ),
                        if (!_isUploading)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F172A),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'ชื่อเมนูอาหาร',
                          hintText: 'เช่น ข้าวกะเพรา',
                          labelStyle: const TextStyle(fontSize: 11),
                          hintStyle: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                          border: fieldBorder,
                          enabledBorder: fieldBorder,
                          focusedBorder: fieldBorder.copyWith(
                            borderSide: const BorderSide(
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                        validator: (val) => (val == null || val.trim().isEmpty)
                            ? 'กรุณาระบุชื่อเมนู'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_selectedCategoryId),
                              initialValue: _selectedCategoryId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'หมวดหมู่',
                                labelStyle: const TextStyle(fontSize: 11),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: fieldBorder,
                                enabledBorder: fieldBorder,
                              ),
                              items: _categories.map((c) {
                                return DropdownMenuItem<String>(
                                  value: c['id']?.toString(),
                                  child: Text(
                                    c['name']?.toString() ?? 'General',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedCategoryId = val),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: Material(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(11),
                              child: InkWell(
                                onTap: _isCreatingCategory
                                    ? null
                                    : _showAddCategoryDialog,
                                borderRadius: BorderRadius.circular(11),
                                child: Center(
                                  child: _isCreatingCategory
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 12,
                          color: Color(0xFF2563EB),
                        ),
                        SizedBox(width: 5),
                        Text(
                          'กำหนดราคาอาหาร (บาท)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const Text(
                                'ปกติ',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              TextFormField(
                                controller: _priceController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  fillColor: Colors.white,
                                  filled: true,
                                ),
                                validator: (val) =>
                                    (val == null ||
                                        double.tryParse(val) == null)
                                    ? 'ระบุราคา'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            children: [
                              const Text(
                                'พิเศษ (+)',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              TextFormField(
                                controller: _priceSpecialController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  fillColor: Colors.white,
                                  filled: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            children: [
                              const Text(
                                'จัมโบ้ (+)',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              TextFormField(
                                controller: _priceJumboController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  fillColor: Colors.white,
                                  filled: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () =>
                        setState(() => _isRecommended = !_isRecommended),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isRecommended
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'เมนูแนะนำ',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _isRecommended
                                        ? const Color(0xFFB45309)
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 38,
                            height: 24,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: Switch.adaptive(
                                value: _isRecommended,
                                activeThumbColor: const Color(0xFFF59E0B),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (val) =>
                                    setState(() => _isRecommended = val),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() => _isAvailable = !_isAvailable),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isAvailable
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isAvailable ? 'เปิดสินค้า' : 'ปิดสินค้า',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _isAvailable
                                        ? const Color(0xFF047857)
                                        : const Color(0xFFB91C1C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 38,
                            height: 24,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: Switch.adaptive(
                                value: _isAvailable,
                                activeThumbColor: const Color(0xFF10B981),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (val) =>
                                    setState(() => _isAvailable = val),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFA855F7),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'ตัวเลือกเสริม (เช่น เลือกเส้น, ความหวาน)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _customOptions.add({
                      'name': '',
                      'type': 'single',
                      'required': false,
                      'choices': <Map<String, dynamic>>[
                        {'name': '', 'price': 0},
                      ],
                    });
                  });
                },
                icon: const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 14,
                  color: Color(0xFFA855F7),
                ),
                label: const Text(
                  'เพิ่มกลุ่ม',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFA855F7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_customOptions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.layers_clear_outlined,
                  color: Color(0xFFCBD5E1),
                  size: 40,
                ),
                SizedBox(height: 8),
                Text(
                  'ไม่มีกลุ่มตัวเลือกเสริมครับนาย',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                Text(
                  'คลิก "เพิ่มกลุ่ม" ด้านบนเพื่อระบุรายละเอียดตัวเลือกย่อยอาหาร',
                  style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ..._customOptions.asMap().entries.map((entry) {
            final int optIdx = entry.key;
            final Map<String, dynamic> optData = entry.value;
            final List<dynamic> choicesList = optData['choices'] as List;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.01),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ชื่อกลุ่มตัวเลือก',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        initialValue: optData['name'],
                        onChanged: (val) => optData['name'] = val,
                        decoration: InputDecoration(
                          hintText: 'เช่น เลือกเส้น, เพิ่มหวาน',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (val) => (val == null || val.isEmpty)
                            ? 'กรุณากรอกชื่อกลุ่ม'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ประเภทการเลือก',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  value: optData['type'],
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'single',
                                      child: Text(
                                        'เลือกได้ 1 อย่าง',
                                        style: TextStyle(
                                          fontSize: 11,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'multiple',
                                      child: Text(
                                        'เลือกได้หลายอย่าง',
                                        style: TextStyle(
                                          fontSize: 11,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) =>
                                      setState(() => optData['type'] = val),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ความจำเป็น',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<bool>(
                                  value: optData['required'],
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: false,
                                      child: Text(
                                        'ไม่บังคับ',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: true,
                                      child: Text(
                                        'ต้องเลือก',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.purple,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) =>
                                      setState(() => optData['required'] = val),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),

                      const Text(
                        'รายการย่อย',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...choicesList.asMap().entries.map((cEntry) {
                        final int choiceIdx = cEntry.key;
                        final Map<String, dynamic> choiceData = cEntry.value;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: choiceData['name'],
                                  onChanged: (val) => choiceData['name'] = val,
                                  decoration: InputDecoration(
                                    hintText:
                                        'ระบุรายการ เช่น เส้นเล็ก, หวานน้อย',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    isDense: true,
                                  ),
                                  validator: (val) =>
                                      (val == null || val.isEmpty)
                                      ? 'ระบุชื่อรายการ'
                                      : null,
                                ),
                              ),
                              if (choicesList.length > 1)
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                    () => choicesList.removeAt(choiceIdx),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),

                      TextButton.icon(
                        onPressed: () => setState(
                          () => choicesList.add({'name': '', 'price': 0}),
                        ),
                        icon: const Icon(
                          Icons.add_rounded,
                          size: 16,
                          color: Color(0xFFA855F7),
                        ),
                        label: const Text(
                          'เพิ่มรายการย่อย',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFA855F7),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _customOptions.removeAt(optIdx)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.red,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
