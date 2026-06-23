part of 'package_tab.dart';

// UI ของหน้าต่างอัปเกรดและการ์ดราคา แยกไว้เพื่อแก้ดีไซน์ได้ง่าย
extension _PackageUpgradeSheet on _PackageTabState {
  void _showUpgradeSheet() {
    if (_dbPlans.isEmpty) _fetchDbPlans();
    final currentRank = _getPlanRank(_dynamicCurrentPlan);
    final filteredPlans = _dbPlans
        .where((p) => _getPlanRank(p['plan_key'] ?? '') >= currentRank)
        .toList();

    _activePlanIndex = 0;
    if (_plansController.hasClients) _plansController.jumpToPage(0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF111827).withOpacity(0.6),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: _isLoadingPlans && filteredPlans.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _PackageTabState._violet,
                      ),
                    )
                  : Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 20,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFF1F5F9)),
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(32),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFEEF2FF),
                                          Color(0xFFFAF5FF),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(
                                          0xFFE0E7FF,
                                        ).withOpacity(0.5),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.workspace_premium_outlined,
                                      color: _PackageTabState._violet,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'อัปเกรดแพ็กเกจ',
                                    style: TextStyle(
                                      color: _PackageTabState._ink,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: AppColors.slate400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFF1F5F9)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildSheetSegment(
                                  left: 'รายเดือน',
                                  right: 'รายปี',
                                  activeIndex: _billingCycle,
                                  rightBadge: '-20%',
                                  onChanged: (value) {
                                    _billingCycle = value;
                                    setModalState(() {});
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 44,
                                  child: OutlinedButton.icon(
                                    onPressed: _isSubmitting
                                        ? null
                                        : () async {
                                            setModalState(
                                              () => _isSubmitting = true,
                                            );
                                            await _restoreRevenueCatPurchases();
                                            if (mounted) setModalState(() {});
                                          },
                                    icon: const Icon(
                                      Icons.restore_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('RESTORE'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _PackageTabState._violet,
                                      side: const BorderSide(
                                        color: Color(0xFFE0E7FF),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: PageView.builder(
                            controller: _plansController,
                            itemCount: filteredPlans.length,
                            onPageChanged: (index) {
                              _activePlanIndex = index;
                              setModalState(() {});
                            },
                            itemBuilder: (context, index) {
                              return AnimatedScale(
                                duration: const Duration(milliseconds: 180),
                                scale: _activePlanIndex == index ? 1 : 0.9,
                                child: _buildPlanCardInsideSheet(
                                  filteredPlans[index],
                                  setModalState,
                                ),
                              );
                            },
                          ),
                        ),
                        if (filteredPlans.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                filteredPlans.length,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: _activePlanIndex == index ? 24 : 8,
                                  height: 8,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _activePlanIndex == index
                                        ? _PackageTabState._violet
                                        : const Color(0xFFCBD5E1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetSegment({
    required String left,
    required String right,
    required int activeIndex,
    required ValueChanged<int> onChanged,
    IconData? leftIcon,
    IconData? rightIcon,
    String? rightBadge,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildSheetSegmentButton(
            label: left,
            icon: leftIcon,
            isActive: activeIndex == 0,
            onTap: () => onChanged(0),
          ),
          const SizedBox(width: 4),
          _buildSheetSegmentButton(
            label: right,
            icon: rightIcon,
            badge: rightBadge,
            isActive: activeIndex == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetSegmentButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    IconData? icon,
    String? badge,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? _PackageTabState._violet : Colors.transparent,
              width: 1.4,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: isActive
                        ? _PackageTabState._violet
                        : AppColors.slate400,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: isActive
                        ? _PackageTabState._violet
                        : AppColors.slate500,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF34D399), Color(0xFF10B981)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCardInsideSheet(dynamic dbPlan, StateSetter setModalState) {
    final String planId = dbPlan['plan_key'] ?? 'free';
    final String planName = dbPlan['name'] ?? planId.toUpperCase();
    final isFree = planId == 'free';
    final isCurrent = _dynamicCurrentPlan.toLowerCase() == planId;
    final isPopular = planId == 'pro';

    int displayPriceMonthly = ((dbPlan['price_monthly'] ?? 0) / 100).round();
    int displayPriceYearly = ((dbPlan['price_yearly'] ?? 0) / 100).round();
    int currentPlanCoins = _billingCycle == 1
        ? (dbPlan['coins_yearly'] ?? 0)
        : (dbPlan['coins_monthly'] ?? 0);

    bool isPromoPrice = false;
    bool isMonthlyFreeFirstTime = false;
    bool isYearlyFreeFirstTime = false;

    if (_isFirstTimeBuyer && !isFree) {
      if (_billingCycle == 0) {
        if (dbPlan['first_time_price_monthly'] != null) {
          int promoMonthly = (dbPlan['first_time_price_monthly'] as num)
              .round();
          displayPriceMonthly = (promoMonthly / 100).round();
          isPromoPrice = true;
          if (displayPriceMonthly == 0) {
            isMonthlyFreeFirstTime = true;
          }
        }
      } else {
        if (dbPlan['first_time_price_yearly'] != null) {
          int promoYearly = (dbPlan['first_time_price_yearly'] as num).round();
          displayPriceYearly = (promoYearly / 100).round();
          isPromoPrice = true;
          if (displayPriceYearly == 0) {
            isYearlyFreeFirstTime = true;
          }
        }
      }
    }

    final monthlyAverage = (displayPriceYearly / 12).floor();
    final fullPricePerYear =
        ((dbPlan['price_monthly'] ?? 0) / 100).round() * 12;

    String btnText = isCurrent
        ? (isFree ? 'กำลังใช้งาน' : 'ต่ออายุแพ็กเกจนี้')
        : 'เลือกแพ็กเกจนี้';
    bool btnDisabled = isCurrent && isFree;

    return Center(
      child: Container(
        width: 340,
        height: 480,
        margin: const EdgeInsets.symmetric(vertical: 24),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isPopular
                ? _PackageTabState._violet
                : const Color(0xFFEAF0F7),
            width: isPopular ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF64748B).withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (isPopular)
              Positioned(
                top: -36,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFFD946EF)],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: _PackageTabState._violet.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFCD34D),
                          size: 14,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'ขายดีที่สุด',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Column(
              children: [
                Text(
                  planName,
                  style: const TextStyle(
                    color: AppColors.slate400,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                if (_billingCycle == 1 && !isFree) ...[
                  if (isYearlyFreeFirstTime)
                    const Text(
                      'ฟรีปีแรก!',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _formatCurrency(monthlyAverage),
                          style: const TextStyle(
                            color: _PackageTabState._ink,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'บ./เดือน',
                          style: TextStyle(
                            color: AppColors.slate400,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFD1FAE5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPromoPrice ? Icons.local_offer_rounded : Icons.savings_rounded,
                          color: const Color(0xFF059669),
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isPromoPrice
                              ? 'ยอดชำระปีแรก: ${_formatCurrency(displayPriceYearly)} บ.'
                              : 'ประหยัด ${_formatCurrency(fullPricePerYear - displayPriceYearly)} บ./ปี',
                          style: const TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  if (isMonthlyFreeFirstTime && !isFree)
                    const Text(
                      'ฟรีเดือนแรก!',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          isFree ? 'ฟรี' : _formatCurrency(displayPriceMonthly),
                          style: const TextStyle(
                            color: _PackageTabState._ink,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (!isFree) ...[
                          const SizedBox(width: 4),
                          const Text(
                            'บ./เดือน',
                            style: TextStyle(
                              color: AppColors.slate400,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
                if (isPromoPrice && !isFree)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.amber.shade900,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'เฉพาะสมัครครั้งแรกเท่านั้น',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (currentPlanCoins > 0 && !isFree)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFEF3C7), Color(0xFFFFFBEB)],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.card_giftcard_rounded,
                          color: Color(0xFFD97706),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'รับโบนัสฟรี ',
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${_formatCurrency(currentPlanCoins)} ',
                          style: const TextStyle(
                            color: Color(0xFFD97706),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFFFCD34D),
                            decorationThickness: 2,
                          ),
                        ),
                        const Icon(
                          Icons.monetization_on_rounded,
                          color: Color(0xFFF59E0B),
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const Divider(color: _PackageTabState._line),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: _getPlanFeatures(planId)
                        .map(
                          (feat) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEFF6FF),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check_rounded,
                                    color: _PackageTabState._violet,
                                    size: 11,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    feat,
                                    style: const TextStyle(
                                      color: AppColors.slate600,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: btnDisabled || _isSubmitting
                        ? null
                        : () async {
                            setModalState(() => _isSubmitting = true);
                            await _purchasePlanWithRevenueCat(planId);
                            if (mounted) setModalState(() {});
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getPlanBtnColor(planId),
                      foregroundColor: _getPlanBtnTextColor(planId),
                      disabledBackgroundColor: const Color(0xFFF1F5F9),
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSubmitting && !btnDisabled
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            btnText,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
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