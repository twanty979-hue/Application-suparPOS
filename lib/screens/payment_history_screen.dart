// lib/screens/payment_history_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../api_service.dart';
import 'package:Pos_Foodscan/services/storage_service.dart';
import '../widgets/suparpos_loading.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  List<dynamic> _payments = [];
  List<dynamic> _coins = [];

  String _activeSubTab = 'billing'; // 'billing' หรือ 'coins'

  @override
  void initState() {
    super.initState();
    _fetchHistoryData();
  }

  Future<void> _fetchHistoryData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty)
        throw "เซสชันหมดอายุ กรุณาล็อกอินใหม่";

      final response = await http.get(
        Uri.parse(ApiService.paymentHistory),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          setState(() {
            _payments = result['payments'] ?? [];
            _coins = result['coins'] ?? [];
          });
        } else {
          throw result['error'] ?? "โหลดข้อมูลประวัติล้มเหลว";
        }
      } else {
        throw "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatCurrency(num amount) {
    return NumberFormat.currency(
      locale: 'th_TH',
      symbol: '฿',
      decimalDigits: 2,
    ).format(amount / 100);
  }

  String _formatCoins(num amount) {
    return NumberFormat('#,###').format(amount);
  }

  String _formatDate(String isoString) {
    final date = DateTime.parse(isoString).toLocal();
    return "${DateFormat('d MMM yyyy', 'th').format(date)} ${DateFormat('HH:mm').format(date)} น.";
  }

  Widget _buildHeader(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        8,
        compact ? 12 : 16,
        8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFEDE9E3),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Scaffold.of(context).openDrawer();
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFDCD6CB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFF292524),
                size: 20,
              ),
            ),
          ),
          SizedBox(width: compact ? 12 : 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ประวัติชำระเงิน',
                  style: TextStyle(
                    color: Color(0xFF292524),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'ดูประวัติและสรุปยอดการชำระเงิน',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDE9E3),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF9F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCD6CB)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSubTabButton(
                      title: 'บิลชำระเงิน',
                      isActive: _activeSubTab == 'billing',
                      icon: Icons.receipt_long_rounded,
                      onTap: () => setState(() => _activeSubTab = 'billing'),
                    ),
                  ),
                  Expanded(
                    child: _buildSubTabButton(
                      title: 'ประวัติ Coins',
                      isActive: _activeSubTab == 'coins',
                      icon: Icons.monetization_on_rounded,
                      onTap: () => setState(() => _activeSubTab = 'coins'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
          ? const SuparPosLoading(fullScreen: false)
          : _errorMessage != null
          ? Center(
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchHistoryData,
              child: _activeSubTab == 'billing'
                  ? _buildPaymentList()
                  : _buildCoinList(),
            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabButton({
    required String title,
    required bool isActive,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFDCD6CB) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive
                  ? const Color(0xFF292524)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF292524)
                    : const Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 💳 รายการบิลชำระเงิน
  Widget _buildPaymentList() {
    if (_payments.isEmpty)
      return _buildEmptyState(
        'ยังไม่มีประวัติการชำระเงิน',
        Icons.payment_rounded,
      );

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _payments.length,
      itemBuilder: (context, index) {
        final bill = _payments[index];
        final isSuccess = bill['status'] == 'successful';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF9F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSuccess
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSuccess
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  color: isSuccess
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'แพ็กเกจ ${(bill['plan_detail'] ?? 'Premium Plan').toString().toUpperCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(bill['created_at']),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatCurrency(bill['amount'] ?? 0),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 🎁 รายการประวัติ Coins
  Widget _buildCoinList() {
    if (_coins.isEmpty)
      return _buildEmptyState(
        'ยังไม่มีประวัติการใช้หรือเติม Coins',
        Icons.monetization_on_outlined,
      );

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _coins.length,
      itemBuilder: (context, index) {
        final coinLog = _coins[index];
        final int amount = coinLog['amount'] ?? 0;
        final bool isEarned = amount >= 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF9F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isEarned
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFFFF7ED),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isEarned
                      ? Icons.add_card_rounded
                      : Icons.shopping_bag_outlined,
                  color: isEarned
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFFF97316),
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coinLog['action']?.toString().toUpperCase() ??
                          'COIN TRANSACTION',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (coinLog['details'] != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        coinLog['details'].toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(coinLog['created_at']),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${isEarned ? '+' : ''}${_formatCoins(amount)}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: isEarned
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFEA580C),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            text,
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
