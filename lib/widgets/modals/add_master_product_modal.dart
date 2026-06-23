import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../api_service.dart';

// =====================================================================
// 📦 1. คลาสหลัก: หน้าต่าง Modal เพิ่ม/แก้ไข สินค้าหลัก
// =====================================================================
class AddMasterProductModal extends StatefulWidget {
  final String brandId;
  final List<dynamic> masterCategories;
  final Map<String, dynamic>? initialData;
  final Function(Map<String, dynamic>) onSave;

  const AddMasterProductModal({
    super.key,
    required this.brandId,
    required this.masterCategories,
    required this.onSave,
    this.initialData,
  });

  @override
  State<AddMasterProductModal> createState() => _AddMasterProductModalState();
}

class _AddMasterProductModalState extends State<AddMasterProductModal> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _costPriceController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _stockController = TextEditingController(text: '0'); 
  
  String? _selectedCategoryId;
  String? _uploadedImageUrl;
  Uint8List? _selectedImageBytes;
  bool _isUploading = false;
  bool _isEditMode = false; // สำหรับเช็คโหมดแก้ไขข้อมูล

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _isEditMode = true;
      final d = widget.initialData!;
      _nameController.text = d['name']?.toString() ?? '';
      _barcodeController.text = d['barcode']?.toString() ?? '';
      _skuController.text = d['sku']?.toString() ?? '';
      _priceController.text = d['price']?.toString() ?? '0';
      _costPriceController.text = d['cost_price']?.toString() ?? '';
      _descController.text = d['description']?.toString() ?? '';
      _selectedCategoryId = d['category_id']?.toString();
      _uploadedImageUrl = d['image_url']?.toString();
      _stockController.text = d['stock']?.toString() ?? '0';
    } else if (widget.masterCategories.isNotEmpty) {
      _selectedCategoryId = widget.masterCategories[0]['id']?.toString();
    }
  }

  // ⚡️ ปรับลอจิกอัปโหลดรูปภาพใหม่ ป้องกันปัญหาเครื่องเด้งดับ 100%
  Future<void> _pickAndUploadImage() async {
    if (_isUploading) return; // 🛡️ บล็อคด่านแรก ป้องกันสัมผัสซ้อนซ้ำ
    
    setState(() => _isUploading = true); // 🔒 ล็อคสถานะทันทีตั้งแต่เริ่มกด

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      
      if (pickedFile == null) return; // กดยกเลิกเลือกรูป ออกไปที่ฟังก์ชัน finally

      final compressedBytes = await FlutterImageCompress.compressWithFile(
        pickedFile.path,
        format: CompressFormat.webp,
        quality: 80,
      );

      if (compressedBytes == null) throw 'แปลงไฟล์เป็น WebP ไม่สำเร็จ';

      setState(() => _selectedImageBytes = compressedBytes);

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
        final shortFileName = jsonResult['fileName'] ?? jsonResult['image_name'] ?? '';

        setState(() {
          _uploadedImageUrl = "https://img.pos-foodscan.com/$shortFileName";
        });
      } else {
        throw 'เซิร์ฟเวอร์ตอบกลับด้วยสถานะ ${response.statusCode}';
      }
    } catch (e) {
      print("Upload error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการอัปโหลด: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false); // 🔓 ปลดล็อคระบบทุกกรณี
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isTablet = constraints.maxWidth > 650; // ปรับหมุดเพิ่มสเปซความกว้าง

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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 🌟 ปรับหัวเรื่องตามโหมดใช้งานจริง
                      Text(
                        _isEditMode ? 'แก้ไขข้อมูลสินค้า' : 'สร้างสินค้าใหม่', 
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))
                      ),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF94A3B8))),
                    ],
                  ),
                  const Divider(height: 20, color: Color(0xFFE2E8F0)),
                  
                  isTablet 
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildImagePickerBox(),
                          const SizedBox(width: 24),
                          Expanded(child: _buildMainFormFields(isTablet)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(child: _buildImagePickerBox()),
                          const SizedBox(height: 20),
                          _buildMainFormFields(isTablet),
                        ],
                      ),
                  
                  const SizedBox(height: 24),
                  
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
                            if (_formKey.currentState!.validate()) {
                              final data = {
                                'name': _nameController.text.trim(),
                                'barcode': _barcodeController.text.trim(),
                                'sku': _skuController.text.trim(),
                                'price': double.tryParse(_priceController.text) ?? 0,
                                'cost_price': double.tryParse(_costPriceController.text),
                                'stock': int.tryParse(_stockController.text) ?? 0,
                                'description': _descController.text.trim(),
                                'category_id': _selectedCategoryId,
                                'image_url': _uploadedImageUrl,
                              };
                              widget.onSave(data);
                              Navigator.pop(context);
                            }
                          },
                          // 🌟 ข้อความปุ่มไดนามิกตรงปกความจริง
                          child: Text(
                            _isEditMode ? 'บันทึกการเปลี่ยนแปลง' : 'บันทึกข้อมูลสินค้า', 
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
      },
    );
  }

  Widget _buildImagePickerBox() {
    return GestureDetector(
      onTap: _isUploading ? null : _pickAndUploadImage,
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0), style: BorderStyle.solid),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_selectedImageBytes != null)
              ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(_selectedImageBytes!, width: 180, height: 180, fit: BoxFit.cover))
            else if (_uploadedImageUrl != null)
              ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(_uploadedImageUrl!, width: 180, height: 180, fit: BoxFit.cover))
            else
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined, size: 32, color: Color(0xFF94A3B8)),
                  SizedBox(height: 8),
                  Text('อัปโหลดรูปภาพ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
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
    );
  }

  Widget _buildMainFormFields(bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ชื่อสินค้า *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(hintText: 'เช่น น้ำดื่มตราสิงห์ 600มล.', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0)))),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณาระบุชื่อสินค้า' : null,
        ),
        const SizedBox(height: 14),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('หมวดหมู่', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
            GestureDetector(
              onTap: () async {
                final newCategory = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (ctx) => AddMasterCategoryDialog(brandId: widget.brandId),
                );
                if (newCategory != null) {
                  setState(() {
                    widget.masterCategories.add(newCategory);
                    _selectedCategoryId = newCategory['id'].toString();
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างหมวดหมู่ใหม่สำเร็จ! 🎉'), backgroundColor: Colors.green));
                  }
                }
              },
              child: const Text('+ สร้างหมวดหมู่ใหม่', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF10B981))),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCategoryId,
              isExpanded: true,
              items: widget.masterCategories.map((c) {
                return DropdownMenuItem<String>(value: c['id']?.toString(), child: Text(c['name']?.toString() ?? ''));
              }).toList(),
              onChanged: (val) => setState(() => _selectedCategoryId = val),
            ),
          ),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('รหัสบาร์โค้ด (Barcode)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  TextFormField(controller: _barcodeController, decoration: InputDecoration(hintText: 'สแกน หรือ พิมพ์บาร์โค้ด', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('รหัส SKU (ถ้ามี)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(height: 6),
                  TextFormField(controller: _skuController, decoration: InputDecoration(hintText: 'เช่น DRINK-001', contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 🌟 ปรับโครงสร้างส่วนราคา/สต็อก: ถ้าเป็นจอมือถือจะแยกแถวลงมาเพื่อไม่ให้ตัวหนังสือเบียดกันจนอ่านยาก
        isTablet 
          ? Row(
              children: [
                Expanded(child: _buildPriceField()),
                const SizedBox(width: 12),
                Expanded(child: _buildCostField()),
                const SizedBox(width: 12),
                Expanded(child: _buildStockField()),
              ],
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildPriceField()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildCostField()),
                  ],
                ),
                const SizedBox(height: 14),
                _buildStockField(),
              ],
            ),
      ],
    );
  }

  Widget _buildPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ราคาขาย *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
        const SizedBox(height: 6),
        TextFormField(controller: _priceController, keyboardType: TextInputType.number, decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
      ],
    );
  }

  Widget _buildCostField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ต้นทุน (COST)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
        const SizedBox(height: 6),
        TextFormField(controller: _costPriceController, keyboardType: TextInputType.number, decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
      ],
    );
  }

  Widget _buildStockField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isEditMode ? 'สต็อก (ห้ามแก้)' : 'สต็อกเริ่มต้น', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
        const SizedBox(height: 6),
        TextFormField(
          controller: _stockController, 
          keyboardType: TextInputType.number, 
          readOnly: _isEditMode,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), 
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: _isEditMode,
            fillColor: _isEditMode ? const Color(0xFFF1F5F9) : Colors.white,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// 📦 2. คลาสย่อย: หน้าต่าง Popup สำหรับสร้างหมวดหมู่หลัก
// =====================================================================
class AddMasterCategoryDialog extends StatefulWidget {
  final String brandId;
  const AddMasterCategoryDialog({super.key, required this.brandId});

  @override
  State<AddMasterCategoryDialog> createState() => _AddMasterCategoryDialogState();
}

class _AddMasterCategoryDialogState extends State<AddMasterCategoryDialog> {
  final _nameController = TextEditingController();
  final _sortOrderController = TextEditingController(text: '0');
  bool _isLoading = false;

  Future<void> _saveCategory() async {
    if (_nameController.text.trim().isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final String baseUrl = ApiService.baseUrl;
      final response = await http.post(
        Uri.parse('$baseUrl/master-categories'), 
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'brand_id': widget.brandId,
          'name': _nameController.text.trim(),
          'sort_order': int.tryParse(_sortOrderController.text) ?? 0,
        }),
      );

      final resData = jsonDecode(response.body);
      if (response.statusCode == 200 && resData['success'] == true) {
        Navigator.pop(context, resData['data']); 
      } else {
        throw resData['error'] ?? 'บันทึกล้มเหลว';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('สร้างหมวดหมู่ใหม่', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
                  ),
                )
              ],
            ),
            const SizedBox(height: 20),
            
            const Text('ชื่อหมวดหมู่', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.layers_outlined, color: Color(0xFF10B981)),
                hintText: 'เช่น เครื่องดื่ม, ของใช้',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF10B981))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF10B981))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5)),
              ),
            ),
            const SizedBox(height: 16),

            const Text('ลำดับการแสดงผล', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            TextFormField(
              controller: _sortOrderController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.tag, color: Color(0xFF64748B)),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                      backgroundColor: const Color(0xFF64748B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _saveCategory,
                    child: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('บันทึก', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}