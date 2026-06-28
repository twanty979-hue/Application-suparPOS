
import re

with open('lib/screens/theme_detail_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# _buildDeviceToggle
old_dt = '''Widget _buildDeviceToggle() {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDDE5EF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),'''
new_dt = '''Widget _buildDeviceToggle() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9E3),
        borderRadius: BorderRadius.circular(10),
      ),'''
c = c.replace(old_dt, new_dt)

c = c.replace('color: const Color(0xFF0B1730),', 'color: const Color(0xFF292524),', 1) # device toggle active background

# _buildDeviceToggleItem
c = c.replace('fontSize: 13,', 'fontSize: 11,')
c = c.replace('size: 17,', 'size: 14,')

# _buildThemeHeader
old_th = '''Widget _buildThemeHeader(
    String category,
    String mode,
    String name,
    bool isCompact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildCategoryPill(category),
            if (mode.isNotEmpty)
              Text(
                ' ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isCompact ? 27 : 30,'''
new_th = '''Widget _buildThemeHeader(
    String category,
    String mode,
    String name,
    bool isCompact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isCompact ? 20 : 22,'''
c = c.replace(old_th, new_th)

# Swap Features and Continue
old_layout = '''                        _buildFeatureListCard(),
                        const SizedBox(height: 16),
                        _buildPrimaryAction(),'''
new_layout = '''                        _buildPrimaryAction(),
                        const SizedBox(height: 16),
                        _buildFeatureListCard(),'''
c = c.replace(old_layout, new_layout)

with open('lib/screens/theme_detail_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)

print('Done part 2')

