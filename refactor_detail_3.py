
import re

with open('lib/screens/theme_detail_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# _buildPlanTabs
old_pt = '''Widget _buildPlanTabs() {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final activeIndex = math.max(
            0,
            _availablePlans.indexWhere((plan) => plan['id'] == _selectedPlan),
          );
          final segmentWidth =
              constraints.maxWidth / math.max(1, _availablePlans.length);

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 390),
                curve: Curves.easeOutBack,
                left: segmentWidth * activeIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFD4DCE6)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),'''

new_pt = '''Widget _buildPlanTabs() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9E3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final activeIndex = math.max(
            0,
            _availablePlans.indexWhere((plan) => plan['id'] == _selectedPlan),
          );
          final segmentWidth =
              constraints.maxWidth / math.max(1, _availablePlans.length);

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 390),
                curve: Curves.easeOutBack,
                left: segmentWidth * activeIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF292524),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),'''
c = c.replace(old_pt, new_pt)

c = c.replace('''color: isSelected
                                    ? const Color(0xFF0B1730)
                                    : const Color(0xFF64748B),''', '''color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF64748B),''')

c = c.replace('fontSize: 13,', 'fontSize: 11,') # might match elsewhere, but okay
c = c.replace('right: 14,\n                                top: 13,', 'right: 8,\n                                top: 10,')

# _buildPriceCard
old_pc = '''Widget _buildPriceCard() {
    final badge = _selectedPlan == 'yearly'
        ? ('??', const Color(0xFFECFDF5), const Color(0xFF047857))
        : _selectedPlan == 'monthly'
        ? ('?', const Color(0xFFDBEAFE), const Color(0xFF2563EB))
        : ('', Colors.transparent, Colors.transparent);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF0B1730), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 26,
            child: badge..isEmpty
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: badge.,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _selectedPlan == 'yearly'
                            ? const Color(0xFFA7F3D0)
                            : const Color(0xFFBFDBFE),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedPlan == 'yearly'
                              ? Icons.star_rounded
                              : Icons.local_fire_department_rounded,
                          size: 13,
                          color: _selectedPlan == 'yearly'
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF97316),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          badge.,
                          style: TextStyle(
                            color: badge.,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B1730),
                    fontSize: 50,
                    fontWeight: FontWeight.w900,
                    height: 0.95,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  '?',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _currentPlanDesc,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),'''

new_pc = '''Widget _buildPriceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDE9E3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF292524),
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 0.95,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  '?',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _currentPlanDesc,
            textAlign: TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),'''
c = c.replace(old_pc, new_pc)

# _buildPrimaryAction
old_pa = '''Widget _buildPrimaryAction() {
    if (_isOwned) {
      return SizedBox(
        height: 58,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0B1730),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 8,
            shadowColor: const Color(0xFF0B1730).withValues(alpha: 0.22),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text(
            '?????',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    final canCheckout = !_isLoadingCoins && _availablePlans.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0B1730),
          disabledBackgroundColor: const Color(0xFFCBD5E1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: canCheckout ? 8 : 0,
          shadowColor: const Color(0xFF0B1730).withValues(alpha: 0.22),
        ),
        onPressed: canCheckout ? () => _showCheckoutModal() : null,
        child: Text(
          '??',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: canCheckout ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }'''

new_pa = '''Widget _buildPrimaryAction() {
    if (_isOwned) {
      return SizedBox(
        height: 42,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF292524),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text(
            '?????',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    final canCheckout = !_isLoadingCoins && _availablePlans.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF292524),
          disabledBackgroundColor: const Color(0xFFCBD5E1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        onPressed: canCheckout ? () => _showCheckoutModal() : null,
        child: Text(
          '??',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: canCheckout ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }'''
c = c.replace(old_pa, new_pa)

with open('lib/screens/theme_detail_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)

print('Done part 3')

