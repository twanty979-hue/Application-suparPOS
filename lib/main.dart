import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'login.dart';
import 'screens/pos_screen.dart'; // 🔥 อย่าลืม import หน้า POS มาด้วยนะนาย

void main() async {
  // ต้องมีบรรทัดนี้เสมอถ้าจะรัน async ใน main
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");

  // 🔥 1. ดึงข้อมูลจาก SharedPreferences ออกมาดูก่อนรันแอป
  final prefs = await SharedPreferences.getInstance();
  final String? savedBrandId = prefs.getString('saved_brand_id');

  // 🔥 2. ส่งค่า brandId ที่เจอ (ซึ่งอาจจะเป็น null ถ้ายังไม่เคย Login) เข้าไปในแอป
  runApp(FoodScanApp(initialBrandId: savedBrandId));
}

class FoodScanApp extends StatelessWidget {
  // 🔥 3. ประกาศรับค่าจาก main
  final String? initialBrandId;

  const FoodScanApp({super.key, this.initialBrandId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FoodScan POS',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        fontFamily: 'Kanit', // ชอบฟอนต์นี้เหมือนกันครับ อ่านง่ายดี
      ),
      // 🔥 4. ตัดสินใจตรงนี้เลย:
      // ถ้า initialBrandId ไม่ใช่ null แสดงว่าเคย Login ไว้แล้ว -> ไปหน้า POS
      // ถ้าเป็น null (ยังไม่ Login) -> ไปหน้า Login ปกติ
      home: initialBrandId != null 
          ? PosScreen(brandId: initialBrandId!) 
          : const LoginPage(),
    );
  }
}