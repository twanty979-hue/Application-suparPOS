import 'package:flutter/material.dart';

class AddDiscountModal extends StatefulWidget {
  final Function(Map<String, dynamic>) onSave;
  final List<dynamic> products; 
  final List<dynamic> productMaster; 

  const AddDiscountModal({
    super.key,
    required this.onSave, 
    required this.products,
    required this.productMaster,
  });

  @override
  State<AddDiscountModal> createState() => _AddDiscountModalState();
}

class _AddDiscountModalState extends State<AddDiscountModal> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  String _type = 'percentage';
  bool _applyNormal = true;
  bool _applySpecial = true;
  bool _applyJumbo = true;

  DateTime? _startDate;
  DateTime? _endDate;

  String _applyTo = 'all'; 
  List<String> _selectedProductIds = [];
  String _searchQuery = '';
  int _productTypeTab = 0; 

  Future<void> _pickDateTime(bool isStart) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF0F172A)),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: Color(0xFF0F172A)),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        setState(() {
          final selectedDateTime = DateTime(
            pickedDate.year, pickedDate.month, pickedDate.day,
            pickedTime.hour, pickedTime.minute,
          );
          if (isStart) {
            _startDate = selectedDateTime;
          } else {
            _endDate = selectedDateTime;
          }
        });
      }
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'วว/ดด/ปปปป --:--';
    final String day = dt.day.toString().padLeft(2, '0');
    final String month = dt.month.toString().padLeft(2, '0');
    final String year = dt.year.toString();
    final String hour = dt.hour.toString().padLeft(2, '0');
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  bool _hasUnsavedChanges() {
    if (_nameController.text.isNotEmpty) return true;
    if (_valueController.text.isNotEmpty) return true;
    if (_type != 'percentage') return true;
    if (_applyNormal != true) return true;
    if (_applySpecial != true) return true;
    if (_applyJumbo != true) return true;
    if (_startDate != null) return true;
    if (_endDate != null) return true;
    if (_applyTo != 'all') return true;
    if (_selectedProductIds.isNotEmpty) return true;
    return false;
  }

  Future<void> _requestClose() async {
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
              color: const Color(0xFFFAF9F6),
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
                  'ละทิ้งการสร้าง?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ข้อมูลที่คุณกรอกไว้จะไม่ถูกบันทึก\nคุณแน่ใจหรือไม่ที่จะละทิ้งการสร้างนี้?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
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
                          'ทำต่อ',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
                          foregroundColor: const Color(0xFFFAF9F6),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'ละทิ้ง',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
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
          color: Color(0xFFFAF9F6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('สร้างโปรโมชัน', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                  GestureDetector(
                    onTap: _requestClose,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Color(0xFFEDE9E3), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 16),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildDetailsSection(),
                      ),
                      
                      const SizedBox(height: 24),
                      const Divider(height: 1, color: Color(0xFFEDE9E3)),
                      const SizedBox(height: 16),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('สินค้าที่ร่วมรายการ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                      ),
                      const SizedBox(height: 12),
                      
                      _buildProductsSection(),
                    ],
                  ),
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF9F6),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      final data = {
                        'name': _nameController.text.trim(),
                        'type': _type,
                        'value': double.tryParse(_valueController.text) ?? 0,
                        'apply_to': _applyTo,
                        'apply_normal': _applyNormal,
                        'apply_special': _applySpecial,
                        'apply_jumbo': _applyJumbo,
                        'start_date': _startDate?.toIso8601String(), 
                        'end_date': _endDate?.toIso8601String(),     
                        'product_ids': _applyTo == 'all' ? [] : _selectedProductIds, 
                      };
                      widget.onSave(data);
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.save_outlined, color: Color(0xFFFAF9F6), size: 14),
                  label: const Text('บันทึกโปรโมชัน', style: TextStyle(color: Color(0xFFFAF9F6), fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ชื่อโปรโมชัน', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      hintText: 'เช่น ลดล้างสต็อก',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEDE9E3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEDE9E3))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                    ),
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'กรุณาระบุ' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ประเภท', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _type,
                    style: const TextStyle(fontSize: 11, color: Colors.black),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEDE9E3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEDE9E3))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'percentage', child: Text('%', style: TextStyle(fontSize: 11))),
                      DropdownMenuItem(value: 'fixed', child: Text('฿', style: TextStyle(fontSize: 11))),
                    ],
                    onChanged: (val) => setState(() => _type = val!),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('มูลค่า', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _valueController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEDE9E3))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEDE9E3))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                    ),
                    validator: (val) => (val == null || double.tryParse(val) == null) ? 'ตัวเลข' : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF9F6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEDE9E3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ระยะเวลา (ไม่บังคับ)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                  if (_startDate != null || _endDate != null)
                    GestureDetector(
                      onTap: () => setState(() { _startDate = null; _endDate = null; }),
                      child: const Text('ล้างค่า', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                    )
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('เริ่มต้น', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _pickDateTime(true), 
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(color: const Color(0xFFFAF9F6), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFEDE9E3))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDateTime(_startDate), 
                                  style: TextStyle(fontSize: 10, color: _startDate == null ? const Color(0xFF94A3B8) : const Color(0xFF1E293B), fontWeight: _startDate == null ? FontWeight.normal : FontWeight.bold)
                                ),
                                const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF94A3B8)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('สิ้นสุด', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _pickDateTime(false), 
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(color: const Color(0xFFFAF9F6), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFEDE9E3))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDateTime(_endDate), 
                                  style: TextStyle(fontSize: 10, color: _endDate == null ? const Color(0xFF94A3B8) : const Color(0xFF1E293B), fontWeight: _endDate == null ? FontWeight.normal : FontWeight.bold)
                                ),
                                const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF94A3B8)),
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
          ),
        ),
        const SizedBox(height: 16),

        const Text('เงื่อนไขราคา', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildCustomCheckbox('ราคาปกติ', _applyNormal, (val) => setState(() => _applyNormal = val))),
            const SizedBox(width: 4),
            Expanded(child: _buildCustomCheckbox('ราคาพิเศษ', _applySpecial, (val) => setState(() => _applySpecial = val))),
            const SizedBox(width: 4),
            Expanded(child: _buildCustomCheckbox('ราคาจัมโบ้', _applyJumbo, (val) => setState(() => _applyJumbo = val))),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomCheckbox(String title, bool isChecked, Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!isChecked),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF9F6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isChecked ? const Color(0xFF0F172A) : const Color(0xFFEDE9E3), width: 1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: isChecked ? const Color(0xFF0F172A) : const Color(0xFFFAF9F6),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: isChecked ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
              ),
              child: isChecked ? const Icon(Icons.check, size: 10, color: Color(0xFFFAF9F6)) : null,
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isChecked ? const Color(0xFF1E293B) : const Color(0xFF475569)))),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsSection() {
    final currentListToDisplay = _productTypeTab == 0 ? widget.products : widget.productMaster;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Container(
                height: 32,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFEDE9E3))),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _applyTo = 'all'),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _applyTo == 'all' ? const Color(0xFFFAF9F6) : Colors.transparent,
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                          ),
                          alignment: Alignment.center,
                          child: Text('ทั้งร้าน', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: _applyTo == 'all' ? const Color(0xFF0F172A) : const Color(0xFF64748B))),
                        ),
                      ),
                    ),
                    Container(width: 1, color: const Color(0xFFEDE9E3)),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _applyTo = 'specific'),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _applyTo == 'specific' ? const Color(0xFFFAF9F6) : const Color(0xFFFAF9F6),
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                            border: _applyTo == 'specific' ? Border.all(color: const Color(0xFF0F172A), width: 1.5) : null,
                          ),
                          alignment: Alignment.center,
                          child: Text('เลือกเฉพาะบางเมนู', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: _applyTo == 'specific' ? const Color(0xFF0F172A) : const Color(0xFF64748B))),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (_applyTo == 'specific') ...[
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _productTypeTab = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: _productTypeTab == 0 ? const Color(0xFF0F172A) : Colors.transparent, width: 2)),
                          ),
                          alignment: Alignment.center,
                          child: Text('อาหารหน้าร้าน', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _productTypeTab == 0 ? const Color(0xFF0F172A) : const Color(0xFF94A3B8))),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _productTypeTab = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: _productTypeTab == 1 ? const Color(0xFF0F172A) : Colors.transparent, width: 2)),
                          ),
                          alignment: Alignment.center,
                          child: Text('สินค้าบาร์โค้ด', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _productTypeTab == 1 ? const Color(0xFF0F172A) : const Color(0xFF94A3B8))),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 1, color: Color(0xFFEDE9E3)),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: const Color(0xFFFAF9F6), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFEDE9E3))),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Color(0xFF94A3B8), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          style: const TextStyle(fontSize: 11),
                          onChanged: (val) => setState(() => _searchQuery = val),
                          decoration: const InputDecoration(
                            hintText: 'ค้นหาชื่อสินค้า หรือ SKU...',
                            hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),

        if (_applyTo == 'specific')
          currentListToDisplay.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('ไม่พบรายการสินค้าในหมวดหมู่นี้', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 4),
                  itemCount: currentListToDisplay.length,
                  itemBuilder: (context, index) {
                    final p = currentListToDisplay[index];
                    final String pId = p['id']?.toString() ?? '';
                    final String pName = p['name']?.toString() ?? 'ไม่มีชื่อ';
                    final String sku = p['sku']?.toString() ?? ''; 
                    final isSelected = _selectedProductIds.contains(pId);
                    
                    if (_searchQuery.isNotEmpty) {
                      final q = _searchQuery.toLowerCase();
                      if (!pName.toLowerCase().contains(q) && !sku.toLowerCase().contains(q)) {
                        return const SizedBox.shrink();
                      }
                    }

                    final String price = p['price']?.toString() ?? '0';
                    final String? priceSpecial = p['price_special']?.toString();
                    final String? priceJumbo = p['price_jumbo']?.toString();

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedProductIds.remove(pId);
                          } else {
                            _selectedProductIds.add(pId);
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF9F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFEDE9E3), width: 1.0),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
                              ),
                              child: isSelected ? const Icon(Icons.check, size: 10, color: Color(0xFFFAF9F6)) : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1E293B))),
                                  if (sku.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text('SKU: $sku', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                                  ],
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFFEDE9E3), borderRadius: BorderRadius.circular(4)),
                                        child: Text('฿$price', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
                                      ),
                                      if (priceSpecial != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(4)),
                                          child: Text('S: ฿$priceSpecial', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF4F46E5))),
                                        ),
                                      if (priceJumbo != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(4)),
                                          child: Text('J: ฿$priceJumbo', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF7C3AED))),
                                        ),
                                    ],
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                )
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Center(
              child: Text('โปรโมชันนี้จะถูกนำไปใช้งานกับสินค้าทุกรายการในร้านโดยอัตโนมัติ', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.5)),
            ),
          )
      ],
    );
  }
}