import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  // 🎯 ดึง IP มาจากไฟล์ .env ที่นายตั้งไว้ 
  static String get baseUrl => dotenv.env['NEXT_PUBLIC_API_BASE_URL'] ?? 'http://192.168.0.103:3000/api';

  // --- รวม Endpoints ทั้งหมด ---
  static String get login => "$baseUrl/login";
  static String get register => "$baseUrl/register";
  
  // ✅ มี initPos แค่บรรทัดเดียวพอครับนาย!
  static String get initPos => "$baseUrl/pos/init"; 
  
  static String get setupProfile => "$baseUrl/setup/profile";
  static String get setupBrand => "$baseUrl/setup/brand";
  static String get setupTutorial => "$baseUrl/setup/tutorial";
}