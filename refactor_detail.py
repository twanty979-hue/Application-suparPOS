
import re

with open('lib/screens/theme_detail_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Colors and Paddings in build()
c = c.replace('backgroundColor: const Color(0xFFF5F8FB),', 'backgroundColor: const Color(0xFFFAF8F4),')
c = c.replace('backgroundColor: Colors.white,', 'backgroundColor: const Color(0xFFFAF8F4),')
c = c.replace('padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),', 'padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),')
c = c.replace('color: const Color(0xFFF8FAFC),', 'color: const Color(0xFFEDE9E3),') # back button bg
c = c.replace('size: 18,', 'size: 16,') # back button icon
c = c.replace('fontSize: 12,', 'fontSize: 10,') # back button text

# previewHeight change
old_ph = 'final previewHeight = (screenWidth * (isCompact ? 1.34 : 1.04))\n        .clamp(360.0, 500.0)\n        .toDouble();'
new_ph = 'final previewHeight = (screenWidth * (isCompact ? 1.15 : 0.9))\n        .clamp(300.0, 420.0)\n        .toDouble();'
c = c.replace(old_ph, new_ph)

# Build method layout spacings
c = c.replace('SizedBox(height: isCompact ? 26 : 34)', 'SizedBox(height: isCompact ? 16 : 24)')
c = c.replace('const SizedBox(height: 34)', 'const SizedBox(height: 16)')
c = c.replace('const SizedBox(height: 30)', 'const SizedBox(height: 16)')

# 2. _buildCoinBalancePill
old_coin = '''  Widget _buildCoinBalancePill() {
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset('lib/assets/cion.png', width: 20),
          const SizedBox(width: 4),
          _isLoadingCoins
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange,
                  ),
                )
              : Text(
                  '',
                  style: TextStyle(
                    color: Colors.amber.shade800,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
        ],
      ),
    );
  }'''

new_coin = '''  Widget _buildCoinBalancePill() {
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9E3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCD6CB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset('lib/assets/cion.png', width: 14),
          const SizedBox(width: 4),
          _isLoadingCoins
              ? const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF292524),
                  ),
                )
              : Text(
                  '',
                  style: const TextStyle(
                    color: Color(0xFF292524),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
        ],
      ),
    );
  }'''
c = c.replace(old_coin, new_coin)

with open('lib/screens/theme_detail_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)

print('Done part 1')

