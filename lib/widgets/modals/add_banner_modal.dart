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

  bool _hasUnsavedChanges() {
    if (widget.initialData != null) {
      final data = widget.initialData!;
      final oldIsActive = data['is_active'] ?? true;
      final oldImageName = data['image_name']?.toString();

      if (_isActive != oldIsActive) return true;
      if (_uploadedImageName != oldImageName) return true;
      if (_selectedImageBytes != null) return true;
      return false;
    } else {
      if (_selectedImageBytes != null) return true;
      if (_isActive != true) return true;
      return false;
    }
  }

  Future<void> _requestClose() async {
    if (_isUploading) return;
    
    if (!_hasUnsavedChanges()) {
      Navigator.pop(context);
      return;
    }
    
    final choice = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
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
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber.shade600,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ละทิ้งการแก้ไข?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ข้อมูลที่คุณกรอกไว้จะไม่ถูกบันทึก\nคุณแน่ใจหรือไม่ที่จะละทิ้งการแก้ไขนี้?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext, 'cancel'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'แก้ไขต่อ',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, 'discard'),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: Colors.red.shade500,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'ละทิ้ง',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
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

    if (choice == 'discard' && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _requestClose();
      },
      child: Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // หัวเรื่องปรับตามโหมด
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditMode ? 'แก้ไขแบนเนอร์เดิม' : 'เพิ่มแบนเนอร์ใหม่', 
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))
                          ),
                          const SizedBox(height: 4),
                          const Text('บังคับขนาด 21:9 (ระบบจะเปิดกล่องครอปให้โดยอัตโนมัติ)', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                        ],
                      ),
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
                const SizedBox(height: 24),

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

              // 📝 2. ลบฟิลด์ข้อมูลประกอบออกตามความต้องการ

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
                      onPressed: _requestClose,
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
                          'title': 'โปรโมชันหน้าร้าน', // Default value
                          'link_url': '',
                          'sort_order': 0,
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
      ),
      ),
    );
  }
}