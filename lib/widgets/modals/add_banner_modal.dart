import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../api_service.dart';

class AddBannerModal extends StatefulWidget {
  final String brandId;
  final Map<String, dynamic>? initialData;
  final Function(Map<String, dynamic>) onSave;

  const AddBannerModal({
    super.key,
    required this.brandId,
    this.initialData,
    required this.onSave,
  });

  @override
  State<AddBannerModal> createState() => _AddBannerModalState();
}

class _AddBannerModalState extends State<AddBannerModal> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _sortOrderController = TextEditingController(text: '0');
  final TextEditingController _linkUrlController = TextEditingController();
  
  bool _isActive = true;
  String? _uploadedImageName; 
  Uint8List? _selectedImageBytes;
  bool _isUploading = false;
  bool _isEditMode = false; // เช็คสถานะโหมดแก้ไข

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _isEditMode = true;
      final d = widget.initialData!;
      _titleController.text = d['title']?.toString() ?? '';
      _sortOrderController.text = d['sort_order']?.toString() ?? '0';
      _linkUrlController.text = d['link_url']?.toString() ?? '';
      _isActive = d['is_active'] ?? true;
      _uploadedImageName = d['image_name']?.toString();
    }
  }

// ✂️ โมดูลจัดการตัดรูปภาพ (Crop Image) อัตราส่วน 21:9
  Future<CroppedFile?> _cropBannerImage(String sourcePath) async {
    return await ImageCropper().cropImage(
      sourcePath: sourcePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'ปรับแต่งขนาดแบนเนอร์ (21:9)',
          toolbarColor: const Color(0xFF0F172A),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFFDA4AF),
          initAspectRatio: CropAspectRatioPreset.square, // แก้ไขตรงนี้เรียบร้อยครับ
          lockAspectRatio: true, 
        ),
        IOSUiSettings(
          title: 'ปรับแต่งขนาดแบนเนอร์ (21:9)',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
      // กำหนดสัดส่วนบังคับเป็น 21:9 ชัดตาแตก
      aspectRatio: const CropAspectRatio(ratioX: 21, ratioY: 9),
    );
  }

  // ⚡️ เลือกรูป -> ครอปรูป -> แปลง WebP -> อัปโหลดขึ้นเซิร์ฟเวอร์
// ⚡️ เลือกรูป -> ครอปรูป -> แปลง WebP -> อัปโหลดขึ้นเซิร์ฟเวอร์
  Future<void> _pickAndUploadBanner() async {
    // 🛡️ บล็อคด่านแรก: ป้องกันการกดเบิ้ลรัวๆ
    if (_isUploading) return; 
    
    // 🔒 ล็อคปุ่มทันทีที่เริ่มทำงาน (แสดง Loading)
    setState(() => _isUploading = true); 

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      
      if (pickedFile == null) return; // ถ้ายกเลิกการเลือกรูป ให้ออกเลย (เดี๋ยว finally จัดการปลดล็อคให้)

      // 1. ส่งไปครอปตัดรูปภาพก่อน
      final croppedFile = await _cropBannerImage(pickedFile.path);
      if (croppedFile == null) return; // ถ้ายกเลิกการครอป ให้ออกเลย

      // 2. บีบอัดไฟล์ที่ผ่านการครอปแล้วเป็น WebP ความชัด 85%
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        croppedFile.path,
        format: CompressFormat.webp,
        quality: 85, 
      );

      if (compressedBytes == null) throw 'แปลงไฟล์แบนเนอร์เป็น WebP ไม่สำเร็จ';

      setState(() => _selectedImageBytes = compressedBytes);

      // 3. เริ่มขั้นตอนยิง API ไปอัปโหลด
      final String baseUrl = ApiService.baseUrl;
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      
      request.fields['folder'] = widget.brandId; 

      String originalName = pickedFile.name;
      String webpFileName = originalName.contains('.') 
          ? '${originalName.substring(0, originalName.lastIndexOf('.'))}.webp'
          : '$originalName.webp';

      request.files.add(http.MultipartFile.fromBytes(
        'file', 
        compressedBytes,
        filename: webpFileName,
        contentType: MediaType('image', 'webp'),
      ));
      
      var response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonResult = jsonDecode(responseData);
        _uploadedImageName = jsonResult['fileName'] ?? jsonResult['image_name'] ?? '';
      } else {
        throw 'เซิร์ฟเวอร์ตอบกลับด้วยรหัส ${response.statusCode}';
      }
    } catch (e) {
      print("Upload banner error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      // 🔓 ปลดล็อคเสมอ ไม่ว่าจะทำงานสำเร็จ, เออเร่อ, หรือกดยกเลิกกลางทาง
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // หัวเรื่องปรับตามโหมด
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditMode ? 'แก้ไขแบนเนอร์เดิม' : 'เพิ่มแบนเนอร์ใหม่', 
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))
                      ),
                      Text('บังคับขนาด 21:9 (ระบบจะเปิดกล่องครอปให้โดยอัตโนมัติ)', style: TextStyle(fontSize: 11, color: Colors.purple[300])),
                    ],
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF94A3B8))),
                ],
              ),
              const Divider(height: 24, color: Color(0xFFE2E8F0)),

              // 🖼️ 1. กล่องแสดงภาพแบนเนอร์
              GestureDetector(
                onTap: _isUploading ? null : _pickAndUploadBanner,
                child: AspectRatio(
                  aspectRatio: 21 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2), 
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFDA4AF), style: BorderStyle.solid), 
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_selectedImageBytes != null)
                          ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.memory(_selectedImageBytes!, width: double.infinity, height: double.infinity, fit: BoxFit.cover))
                        else if (_uploadedImageName != null)
                          ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network("https://img.pos-foodscan.com/$_uploadedImageName", width: double.infinity, height: double.infinity, fit: BoxFit.cover))
                        else
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_outlined, size: 36, color: Colors.pink[300]),
                              const SizedBox(height: 8),
                              Text('คลิกเพื่อเลือกและครอปรูปภาพ', style: TextStyle(color: Colors.pink[300], fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        if (_isUploading)
                          Container(
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(16)),
                            child: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                          )
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 📝 2. ฟิลด์ข้อมูลประกอบ
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ชื่อแบนเนอร์', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(hintText: 'เช่น โปรโมชันหน้าร้อน', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('↓ ลำดับ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _sortOrderController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: const Color(0xFFF8FAFC)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              const Text('ลิงก์ปลายทาง (OPTIONAL)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
              const SizedBox(height: 6),
              TextFormField(
                controller: _linkUrlController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.link_rounded, size: 18, color: Color(0xFF94A3B8)),
                  hintText: 'https://...',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
                ),
              ),
              const SizedBox(height: 16),

              // 🟢 3. ปุ่มสวิตช์เปิด-ปิดสถานะ
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('แสดงผลหน้าเว็บ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                    Switch(
                      value: _isActive,
                      activeColor: const Color(0xFF10B981), 
                      onChanged: (val) => setState(() => _isActive = val),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 🔘 4. ปุ่มก้นล่าง: ยกเลิก / บันทึก
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ยกเลิก', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF0F172A), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (_uploadedImageName == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาอัปโหลดรูปภาพก่อนบันทึกครับนาย! 🖼️'), backgroundColor: Colors.orange));
                          return;
                        }
                        
                        final data = {
                          'image_name': _uploadedImageName,
                          'title': _titleController.text.trim(),
                          'link_url': _linkUrlController.text.trim(),
                          'sort_order': int.tryParse(_sortOrderController.text) ?? 0,
                          'is_active': _isActive,
                        };
                        widget.onSave(data);
                        Navigator.pop(context);
                      },
                      child: Text(
                        _isEditMode ? 'บันทึกการแก้ไข' : 'บันทึกแบนเนอร์', 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}