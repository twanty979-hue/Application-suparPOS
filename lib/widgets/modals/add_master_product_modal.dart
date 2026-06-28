import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../api_service.dart';

// =====================================================================
// 📦 1. คลาสหลัก: หน้าต่าง Modal เพิ่ม/แก้ไข สินค้าหลัก
// =====================================================================
class AddMasterProductModal extends StatefulWidget {
  final String brandId;
  final List<dynamic> masterCategories;
  final Map<String, dynamic>? initialData;
  final Function(Map<String, dynamic>) onSave;
  final Function()? onDelete;

  const AddMasterProductModal({
    super.key,
    required this.brandId,
    required this.masterCategories,
    required this.onSave,
    this.initialData,
    this.onDelete,
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
  final TextEditingController _stockController = TextEditingController(
    text: '0',
  );

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

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _priceController.dispose();
    _costPriceController.dispose();
    _descController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  // ⚡️ ปรับลอจิกอัปโหลดรูปภาพใหม่ ป้องกันปัญหาเครื่องเด้งดับ 100%
  Future<void> _pickAndUploadImage() async {
    if (_isUploading) return; // 🛡️ บล็อคด่านแรก ป้องกันสัมผัสซ้อนซ้ำ

    setState(() => _isUploading = true); // 🔒 ล็อคสถานะทันทีตั้งแต่เริ่มกด

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null)
        return; // กดยกเลิกเลือกรูป ออกไปที่ฟังก์ชัน finally

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

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          compressedBytes,
          filename: webpFileName,
          contentType: MediaType('image', 'webp'),
        ),
      );

      var response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonResult = jsonDecode(responseData);
        final shortFileName =
            jsonResult['fileName'] ?? jsonResult['image_name'] ?? '';

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
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการอัปโหลด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false); // 🔓 ปลดล็อคระบบทุกกรณี
      }
    }
  }

  bool _hasUnsavedChanges() {
    if (widget.initialData != null) {
      final d = widget.initialData!;
      final oldName = d['name']?.toString() ?? '';
      final oldBarcode = d['barcode']?.toString() ?? '';
      final oldSku = d['sku']?.toString() ?? '';
      final oldPrice = d['price']?.toString() ?? '0';
      final oldCostPrice = d['cost_price']?.toString() ?? '';
      final oldDesc = d['description']?.toString() ?? '';
      final oldCategoryId = d['category_id']?.toString();
      final oldImageUrl = d['image_url']?.toString();
      final oldStock = d['stock']?.toString() ?? '0';

      if (_nameController.text != oldName) return true;
      if (_barcodeController.text != oldBarcode) return true;
      if (_skuController.text != oldSku) return true;
      if (_priceController.text != oldPrice) return true;
      if (_costPriceController.text != oldCostPrice) return true;
      if (_descController.text != oldDesc) return true;
      if (_stockController.text != oldStock) return true;
      if (_selectedCategoryId != oldCategoryId && _selectedCategoryId != null) return true;
      if (_uploadedImageUrl != oldImageUrl) return true;
      if (_selectedImageBytes != null) return true;

      return false;
    } else {
      if (_nameController.text.isNotEmpty) return true;
      if (_barcodeController.text.isNotEmpty) return true;
      if (_skuController.text.isNotEmpty) return true;
      if (_priceController.text.isNotEmpty && _priceController.text != '0') return true;
      if (_costPriceController.text.isNotEmpty) return true;
      if (_descController.text.isNotEmpty) return true;
      if (_stockController.text != '0' && _stockController.text.isNotEmpty) return true;
      if (_selectedImageBytes != null) return true;
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
    final screenHeight = MediaQuery.of(context).size.height;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditMode ? 'แก้ไขข้อมูลสินค้า' : 'สร้างสินค้าใหม่',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                if (_isEditMode && widget.onDelete != null)
                  IconButton(
                    onPressed: () {
                      widget.onDelete!();
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                      size: 20,
                    ),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _requestClose,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAF9F6),
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
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Form(key: _formKey, child: _buildCompactForm()),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFEDE9E3))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFEDE9E3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'ยกเลิก',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: _saveProduct,
                      icon: const Icon(
                        Icons.save_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      label: Text(
                        _isEditMode ? 'บันทึกและอัปเดต' : 'บันทึกสินค้า',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
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

  void _saveProduct() {
    if (!_formKey.currentState!.validate()) return;
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

  Future<void> _addMasterCategory() async {
    final newCategory = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AddMasterCategoryDialog(brandId: widget.brandId),
    );
    if (newCategory == null || !mounted) return;
    setState(() {
      widget.masterCategories.add(newCategory);
      _selectedCategoryId = newCategory['id'].toString();
    });
  }

  InputDecoration _compactDecoration(String label, {String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFEDE9E3)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(fontSize: 10),
      hintStyle: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFF16A34A)),
      ),
    );
  }

  Widget _compactField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      style: const TextStyle(fontSize: 11),
      decoration: _compactDecoration(label, hint: hint).copyWith(
        filled: readOnly,
        fillColor: readOnly ? const Color(0xFFFAF9F6) : Colors.white,
      ),
      validator: validator,
    );
  }

  Widget _buildCompactForm() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageSize = constraints.maxWidth < 340 ? 96.0 : 112.0;
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildImagePickerBox(imageSize),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      _compactField(
                        label: 'ชื่อสินค้า *',
                        controller: _nameController,
                        hint: 'เช่น น้ำดื่ม 600 มล.',
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'กรุณาระบุชื่อ'
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
                              decoration: _compactDecoration('หมวดหมู่'),
                              items: widget.masterCategories.map((category) {
                                return DropdownMenuItem<String>(
                                  value: category['id']?.toString(),
                                  child: Text(
                                    category['name']?.toString() ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) =>
                                  setState(() => _selectedCategoryId = value),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: Material(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: _addMasterCategory,
                                borderRadius: BorderRadius.circular(10),
                                child: const Icon(
                                  Icons.add_rounded,
                                  color: Colors.white,
                                  size: 22,
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
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _compactField(
                    label: 'บาร์โค้ด',
                    controller: _barcodeController,
                    hint: 'สแกนหรือพิมพ์',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactField(
                    label: 'SKU',
                    controller: _skuController,
                    hint: 'เช่น DRINK-001',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _compactField(
                    label: 'ราคาขาย *',
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value == null || double.tryParse(value) == null
                        ? 'ระบุราคา'
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactField(
                    label: 'ต้นทุน',
                    controller: _costPriceController,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactField(
                    label: _isEditMode ? 'สต็อก (ห้ามแก้)' : 'สต็อกเริ่มต้น',
                    controller: _stockController,
                    keyboardType: TextInputType.number,
                    readOnly: _isEditMode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _compactField(
              label: 'รายละเอียดสินค้า',
              controller: _descController,
              hint: 'รายละเอียดเพิ่มเติม (ถ้ามี)',
            ),
          ],
        );
      },
    );
  }

  Widget _buildImagePickerBox(double size) {
    return GestureDetector(
      onTap: _isUploading ? null : _pickAndUploadImage,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFAF9F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFEDE9E3),
            style: BorderStyle.solid,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_selectedImageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  _selectedImageBytes!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              )
            else if (_uploadedImageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  _uploadedImageUrl!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              )
            else
              const Column(
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
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            if (_isUploading)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainFormFields(bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ชื่อสินค้า *',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'เช่น น้ำดื่มตราสิงห์ 600มล.',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFEDE9E3)),
            ),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'กรุณาระบุชื่อสินค้า' : null,
        ),
        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'หมวดหมู่',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF475569),
              ),
            ),
            GestureDetector(
              onTap: () async {
                final newCategory = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (ctx) =>
                      AddMasterCategoryDialog(brandId: widget.brandId),
                );
                if (newCategory != null) {
                  setState(() {
                    widget.masterCategories.add(newCategory);
                    _selectedCategoryId = newCategory['id'].toString();
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('สร้างหมวดหมู่ใหม่สำเร็จ! 🎉'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: const Text(
                '+ สร้างหมวดหมู่ใหม่',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEDE9E3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCategoryId,
              isExpanded: true,
              items: widget.masterCategories.map((c) {
                return DropdownMenuItem<String>(
                  value: c['id']?.toString(),
                  child: Text(c['name']?.toString() ?? ''),
                );
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
                  const Text(
                    'รหัสบาร์โค้ด (Barcode)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _barcodeController,
                    decoration: InputDecoration(
                      hintText: 'สแกน หรือ พิมพ์บาร์โค้ด',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'รหัส SKU (ถ้ามี)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _skuController,
                    decoration: InputDecoration(
                      hintText: 'เช่น DRINK-001',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
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
        const Text(
          'ราคาขาย *',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _priceController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildCostField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ต้นทุน (COST)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _costPriceController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildStockField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isEditMode ? 'สต็อก (ห้ามแก้)' : 'สต็อกเริ่มต้น',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _stockController,
          keyboardType: TextInputType.number,
          readOnly: _isEditMode,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: _isEditMode,
            fillColor: _isEditMode ? const Color(0xFFFAF9F6) : Colors.white,
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
  State<AddMasterCategoryDialog> createState() =>
      _AddMasterCategoryDialogState();
}

class _AddMasterCategoryDialogState extends State<AddMasterCategoryDialog> {
  final _nameController = TextEditingController();
  final _sortOrderController = TextEditingController(text: '0');
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
                const Text(
                  'สร้างหมวดหมู่ใหม่',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAF9F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const Text(
              'ชื่อหมวดหมู่',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.layers_outlined,
                  color: Color(0xFF10B981),
                ),
                hintText: 'เช่น เครื่องดื่ม, ของใช้',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF10B981)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF10B981)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF10B981),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'ลำดับการแสดงผล',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _sortOrderController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.tag, color: Color(0xFF64748B)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFEDE9E3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFEDE9E3)),
                ),
                filled: true,
                fillColor: const Color(0xFFFAF9F6),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: Color(0xFFEDE9E3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'ยกเลิก',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: const Color(0xFF64748B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : _saveCategory,
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'บันทึก',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
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
    );
  }
}

