import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http_parser/http_parser.dart'; // ✅ เพิ่มบรรทัดนี้
import '../../api_service.dart';
class AddProductModal extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final List<dynamic> categories; 
  final Map<String, dynamic>? initialData;
  final String brandId; // ✅ 1. เพิ่มตัวแปรรับค่าตรงนี้

  const AddProductModal({
    super.key,
    required this.onSave,
    required this.categories,
    required this.brandId, // ✅ 2. บังคับรับค่าใน Constructor
    this.initialData,
  });

  @override
  State<AddProductModal> createState() => _AddProductModalState();
}

class _AddProductModalState extends State<AddProductModal> {
  final _formKey = GlobalKey<FormState>();
  int _currentTab = 0;

  // Controllers สำหรับข้อมูลพื้นฐานอาหาร
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _priceSpecialController = TextEditingController();
  final TextEditingController _priceJumboController = TextEditingController();
  
  String? _selectedCategoryId;
  bool _isRecommended = false;

  // State ตัวเลือกเสริม (Options JSONB)
  List<Map<String, dynamic>> _customOptions = [];

  // --- 📸 ตัวแปรสำหรับจัดการรูปภาพ (ใช้ Uint8List เพื่อให้รันบน Web ได้) ---
  Uint8List? _selectedImageBytes;
  bool _isUploading = false;
  String? _uploadedImageName;

  @override
  void initState() {
    super.initState();
    
    // ✅ ถ้ามี initialData ส่งเข้ามา (โหมดแก้ไข) ให้เอาข้อมูลมายัดใส่ Controller
    if (widget.initialData != null) {
      final data = widget.initialData!;
      
      _nameController.text = data['name']?.toString() ?? '';
      _priceController.text = data['price']?.toString() ?? '';
      
      if (data['price_special'] != null && data['price_special'].toString() != 'null') {
        _priceSpecialController.text = data['price_special'].toString();
      }
      if (data['price_jumbo'] != null && data['price_jumbo'].toString() != 'null') {
        _priceJumboController.text = data['price_jumbo'].toString();
      }
      
      _selectedCategoryId = data['category_id']?.toString();
      _isRecommended = data['is_recommended'] ?? false;
      _uploadedImageName = data['image_name']?.toString(); // เก็บชื่อรูปเดิมไว้
      
      // ดึงตัวเลือกเสริม (Options) เดิมมาแสดง
      if (data['options'] != null && data['options'] is List) {
        _customOptions = List<Map<String, dynamic>>.from(
          (data['options'] as List).map((item) => Map<String, dynamic>.from(item))
        );
      }
    } 
    // โหมดสร้างเมนูใหม่
    else {
      if (widget.categories.isNotEmpty) {
        _selectedCategoryId = widget.categories[0]['id']?.toString();
      }
    }
  }
Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    // 1. ดึงรูปมาจากคลังภาพปกติ
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      setState(() {
        _isUploading = true;
      });

      try {
        // 2. ⚡️ พระเอกของเรา: สั่งบีบอัดและแปลงไฟล์ตรงนี้ให้กลายเป็น .webp ทันที
        // โค้ดนี้จะแปลงไฟล์ภาพในหน่วยความจำ (Uint8List) ให้เป็นฟอร์แมต webp คุณภาพ 80% (ชัดแต่เบาหวิว)
        final compressedBytes = await FlutterImageCompress.compressWithFile(
          pickedFile.path,
          format: CompressFormat.webp,
          quality: 80, // ปรับความคมชัด 80% กำลังสวยและเบามาก
        );

        if (compressedBytes == null) throw 'แปลงไฟล์เป็น WebP ไม่สำเร็จ';

        setState(() {
          _selectedImageBytes = compressedBytes; // เก็บไปแสดงผลพรีวิวบน UI
        });

        final String baseUrl = ApiService.baseUrl;
        var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
        
        // บอกโฟลเดอร์ปลายทาง
        request.fields['folder'] = widget.brandId; 

        // เปลี่ยนชื่อไฟล์ปลายทางให้ลงท้ายด้วย .webp เพื่อให้ฝั่งหลังบ้านรับไปบันทึกถูกนามสกุล
        String originalName = pickedFile.name;
        String webpFileName = originalName.contains('.') 
            ? '${originalName.substring(0, originalName.lastIndexOf('.'))}.webp'
            : '$originalName.webp';

       // ... (โค้ดก่อนหน้า) ...
        
        // โยนไฟล์ที่เป็น WebP ยิงเข้า API พร้อมประกาศศักดาว่าเป็นรูปภาพ!
        request.files.add(http.MultipartFile.fromBytes(
          'file', 
          compressedBytes,
          filename: webpFileName,
          contentType: MediaType('image', 'webp'), // 🎯 เติมบรรทัดนี้เข้าไปครับนาย!
        ));
        
        var response = await request.send();
        // ... (โค้ดส่วนที่เหลือ) ...
        if (response.statusCode == 200) {
          final responseData = await response.stream.bytesToString();
          final jsonResult = jsonDecode(responseData);
          
          // ดึงค่า fileName ที่ส่งกลับมาจาก Next.js API (ซึ่งจะพ่วงชื่อโฟลเดอร์มาแล้ว เช่น "brand_id/xxxx.webp")
          final shortFileName = jsonResult['fileName'] ?? jsonResult['image_name'] ?? '';

          if (mounted) {
            setState(() {
              // ✅ แก้เรื่องโฟลเดอร์ซ้ำ: เอาโดเมนหลักมาต่อกับ shortFileName ตรงๆ ได้เลย ไม่ต้องใส่ brandId ซ้ำแล้วครับ
              _uploadedImageName = "https://img.pos-foodscan.com/$shortFileName";
            });

            print("✅ อัปโหลดรูปสำเร็จ! URL เต็มก้อนที่จะลง DB คือ: $_uploadedImageName");

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('อัปโหลดรูปภาพ WebP สำเร็จ! 📸'), backgroundColor: Colors.green),
            );
          }
        } else {
          throw 'เซิร์ฟเวอร์ปฏิเสธการอัปโหลด (Status: ${response.statusCode})';
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('อัปโหลดพัง: $e'), backgroundColor: Colors.red),
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
          CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.blue)),
          SizedBox(height: 16),
          Text('กำลังอัปโหลดรูปภาพ...', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      );
    }
    
    if (_selectedImageBytes != null) {
      return Image.memory(_selectedImageBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }

    if (_uploadedImageName != null && _uploadedImageName!.isNotEmpty) {
      String displayUrl = _uploadedImageName!;
      if (!displayUrl.startsWith('http')) {
        if (displayUrl.contains('/')) {
          displayUrl = "https://img.pos-foodscan.com/$displayUrl";
        } else {
          displayUrl = "https://xvhibjejvbriotfpunvv.supabase.co/storage/v1/object/public/images/$displayUrl";
        }
      }
      return Image.network(
        displayUrl, 
        fit: BoxFit.cover, 
        width: double.infinity, 
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image_outlined, size: 48, color: Color(0xFF94A3B8))),
      );
    }

    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_outlined, size: 48, color: Color(0xFF94A3B8)),
        SizedBox(height: 8),
        Text('คลิกเพื่ออัพโหลดรูป', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 14))
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // --- HEADER BAR ---
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'สร้าง/แก้ไข เมนูอาหาร',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                ),
                Container(
                  decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20),
                    onPressed: () => Navigator.pop(context),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ],
            ),
          ),

          // --- SEGMENTED TABS ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 46,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), border: Border.all(color: Colors.transparent), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _currentTab = 0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _currentTab == 0 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _currentTab == 0 ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : [],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'รายละเอียด',
                          style: TextStyle(fontWeight: FontWeight.w900, color: _currentTab == 0 ? const Color(0xFF0F172A) : const Color(0xFF64748B), fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _currentTab = 1),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _currentTab == 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _currentTab == 1 ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : [],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'ตัวเลือกเสริม',
                          style: TextStyle(fontWeight: FontWeight.w900, color: _currentTab == 1 ? const Color(0xFF0F172A) : const Color(0xFF64748B), fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- SCROLLABLE FORM CONTENT ---
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
              child: Form(
                key: _formKey,
                child: _currentTab == 0 ? _buildBaseDetailsTab() : _buildOptionsTab(),
              ),
            ),
          ),

          // --- FIXED BOTTOM BUTTON ---
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: _currentTab == 0
                  ? ElevatedButton(
                      onPressed: () => setState(() => _currentTab = 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('ถัดไป: ตัวเลือกเสริม', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                        ],
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          final data = {
                            'name': _nameController.text.trim(),
                            'category_id': _selectedCategoryId,
                            'price': double.tryParse(_priceController.text) ?? 0,
                            'price_special': double.tryParse(_priceSpecialController.text),
                            'price_jumbo': double.tryParse(_priceJumboController.text),
                            'is_recommended': _isRecommended,
                            'options': _customOptions,
                            'image_name': _uploadedImageName, 
                          };
                          widget.onSave(data);
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.save_outlined, color: Colors.white),
                      label: const Text('บันทึกข้อมูลเมนู', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaseDetailsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: GestureDetector(
            onTap: _isUploading ? null : _pickAndUploadImage,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _buildImagePreview(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        const Text('ชื่อเมนูอาหาร', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'เช่น ข้าวกะเพราหมูสับ',
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB))),
          ),
          validator: (val) => (val == null || val.trim().isEmpty) ? 'กรุณาระบุชื่อเมนูอาหาร' : null,
        ),
        const SizedBox(height: 18),

        const Text('หมวดหมู่', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedCategoryId,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          ),
          items: widget.categories.map((c) {
            return DropdownMenuItem<String>(
              value: c['id']?.toString(),
              child: Text(c['name']?.toString() ?? 'General', style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
          onChanged: (val) => setState(() => _selectedCategoryId = val),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.payments_outlined, size: 16, color: Color(0xFF2563EB)),
                  SizedBox(width: 6),
                  Text('กำหนดราคาอาหาร (บาท)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('ปกติ', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '0',
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          validator: (val) => (val == null || double.tryParse(val) == null) ? 'ระบุราคา' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('พิเศษ (+)', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _priceSpecialController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '0',
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('จัมโบ้ (+)', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _priceJumboController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '0',
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
        const SizedBox(height: 20),

        GestureDetector(
          onTap: () => setState(() => _isRecommended = !_isRecommended),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _isRecommended ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Icon(Icons.star_rounded, color: _isRecommended ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ตั้งเป็นเมนูแนะนำ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _isRecommended ? const Color(0xFFB45309) : const Color(0xFF334155))),
                      const Text('แสดงผลติดดาว ⭐ และดันขึ้นลำดับแรกของหน้าร้าน', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _isRecommended,
                  activeColor: const Color(0xFFF59E0B),
                  onChanged: (val) => setState(() => _isRecommended = val),
                )
              ],
            ),
          ),
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
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
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
                      'choices': <Map<String, dynamic>>[{'name': '', 'price': 0}]
                    });
                  });
                },
                icon: const Icon(Icons.add_circle_outline_rounded, size: 14, color: Color(0xFFA855F7)),
                label: const Text('เพิ่มกลุ่ม', style: TextStyle(fontSize: 12, color: Color(0xFFA855F7), fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
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
                Icon(Icons.layers_clear_outlined, color: Color(0xFFCBD5E1), size: 40),
                SizedBox(height: 8),
                Text('ไม่มีกลุ่มตัวเลือกเสริมครับนาย', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                Text('คลิก "เพิ่มกลุ่ม" ด้านบนเพื่อระบุรายละเอียดตัวเลือกย่อยอาหาร', style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)), textAlign: TextAlign.center),
              ],
            ),
          )
        else
          ..._customOptions.asMap().entries.map((entry) {
            final int optIdx = entry.key;
            final Map<String, dynamic> optData = entry.value;
            final List<dynamic> choicesList = optData['choices'] as List;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4)],
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ชื่อกลุ่มตัวเลือก', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                      const SizedBox(height: 6),
                      TextFormField(
                        initialValue: optData['name'],
                        onChanged: (val) => optData['name'] = val,
                        decoration: InputDecoration(
                          hintText: 'เช่น เลือกเส้น, เพิ่มหวาน',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) => (val == null || val.isEmpty) ? 'กรุณากรอกชื่อกลุ่ม' : null,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('ประเภทการเลือก', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  value: optData['type'],
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), 
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'single', child: Text('เลือกได้ 1 อย่าง', style: TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis))),
                                    DropdownMenuItem(value: 'multiple', child: Text('เลือกได้หลายอย่าง', style: TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis))),
                                  ],
                                  onChanged: (val) => setState(() => optData['type'] = val),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('ความจำเป็น', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<bool>(
                                  value: optData['required'],
                                  isExpanded: true, 
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), 
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: false, child: Text('ไม่บังคับ', style: TextStyle(fontSize: 12))),
                                    DropdownMenuItem(value: true, child: Text('ต้องเลือก', style: TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.bold))),
                                  ],
                                  onChanged: (val) => setState(() => optData['required'] = val),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),

                      const Text('รายการย่อย', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
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
                                    hintText: 'ระบุรายการ เช่น เส้นเล็ก, หวานน้อย',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    isDense: true,
                                  ),
                                  validator: (val) => (val == null || val.isEmpty) ? 'ระบุชื่อรายการ' : null,
                                ),
                              ),
                              if (choicesList.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 20),
                                  onPressed: () => setState(() => choicesList.removeAt(choiceIdx)),
                                ),
                            ],
                          ),
                        );
                      }),
                      
                      TextButton.icon(
                        onPressed: () => setState(() => choicesList.add({'name': '', 'price': 0})),
                        icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFFA855F7)),
                        label: const Text('เพิ่มรายการย่อย', style: TextStyle(fontSize: 12, color: Color(0xFFA855F7), fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => _customOptions.removeAt(optIdx)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.red, size: 16),
                      ),
                    ),
                  )
                ],
              ),
            );
          }),
      ],
    );
  }
}