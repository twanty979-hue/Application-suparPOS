import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/pos_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isRecovery = false;

  void _addGmailSuffix() {
    if (!_emailController.text.contains('@')) {
      setState(() {
        _emailController.text = "${_emailController.text}@gmail.com";
        _emailController.selection = TextSelection.fromPosition(
          TextPosition(offset: _emailController.text.length),
        );
      });
    }
  }

Future<void> _handleLogin() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse(ApiService.login),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        }),
      );

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        // ดึง brand_id ออกมาเก็บไว้ในตัวแปรก่อน
        final brandId = result['brand_id'] ?? result['data']['brand_id'];

        // 🔥 2. บันทึก brandId ลงเครื่องด้วย SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_brand_id', brandId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("ยินดีต้อนรับกลับครับนาย!"), backgroundColor: Colors.green),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => PosScreen(brandId: brandId), // ส่งค่าที่ได้ไปหน้า POS
            ),
          );
        }
      } else {
        throw result['error'] ?? "เกิดข้อผิดพลาด";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          Positioned(
            top: -size.width * 0.2,
            left: -size.width * 0.2,
            child: _buildBlurCircle(Colors.blue.withOpacity(0.15)),
          ),
          Positioned(
            bottom: -size.width * 0.2,
            right: -size.width * 0.2,
            child: _buildBlurCircle(Colors.cyan.withOpacity(0.15)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.05),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLogo(),
                      const SizedBox(height: 20),
                      Text(
                        _isRecovery ? 'กู้คืนรหัสผ่าน' : 'ยินดีต้อนรับกลับ!',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRecovery ? 'กรอกอีเมลเพื่อรับลิงก์ตั้งรหัสใหม่' : 'Perfect POS Management',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                      const SizedBox(height: 28),
                      _buildTextField(
                        controller: _emailController,
                        label: "อีเมล",
                        hint: "ชื่อบัญชีของคุณ",
                        icon: Icons.email_outlined,
                        suffix: ValueListenableBuilder(
                          valueListenable: _emailController,
                          builder: (context, value, child) {
                            if (value.text.isNotEmpty && !value.text.contains('@')) {
                              return TextButton(
                                onPressed: _addGmailSuffix,
                                child: const Text("+ @gmail.com", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_isRecovery) ...[
                        _buildTextField(
                          controller: _passwordController,
                          label: "รหัสผ่าน",
                          hint: "••••••••",
                          icon: Icons.lock_outline,
                          isPassword: true,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setState(() => _isRecovery = true),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                            child: const Text("ลืมรหัสผ่าน?", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ] else ...[
                        const SizedBox(height: 12),
                      ],
                      _buildPrimaryButton(),
                      if (!_isRecovery) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey[200])),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text("หรือ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ),
                            Expanded(child: Divider(color: Colors.grey[200])),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildGoogleButton(),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_isRecovery ? "" : "ยังไม่มีบัญชีร้านค้า?", style: const TextStyle(fontSize: 13)),
                          TextButton(
                            onPressed: () {
                              if (_isRecovery) {
                                setState(() => _isRecovery = false);
                              } else {
                                // ไปหน้า Register
                              }
                            },
                            child: Text(
                              _isRecovery ? "กลับไปหน้า Login" : "สมัครสมาชิกฟรี",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Helpers ---

  Widget _buildBlurCircle(Color color) {
    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color, blurRadius: 80, spreadRadius: 40),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 5))
        ],
      ),
      child: const Icon(Icons.storefront, size: 36, color: Colors.blue),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        SizedBox(
          height: 50,
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),
              suffixIcon: suffix,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blue, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF1E40AF),
            Color(0xFF3B82F6),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : (_isRecovery ? () {} : _handleLogin),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: EdgeInsets.zero,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isRecovery ? 'ส่งลิงก์รีเซ็ตรหัสผ่าน' : 'เข้าสู่ระบบเลย',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                ],
              ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // TODO: ใส่ Logic Google
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.network(
                'https://cdn-icons-png.flaticon.com/512/2991/2991148.png',
                height: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                "Google",
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}