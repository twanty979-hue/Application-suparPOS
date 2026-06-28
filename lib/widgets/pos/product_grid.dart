// lib/widgets/pos/product_grid.dart

import 'dart:io';

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'category_list.dart';

class ProductGrid extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final List<Map<String, dynamic>> displayProducts;
  final TextEditingController barcodeController;
  final ValueChanged<Map<String, dynamic>> onProductClick;
  final Map<String, dynamic> Function(Map<String, dynamic>, String)
  calculatePrice;
  final String Function(double) formatCurrency;
  final bool showProductImages;
  final bool showProductNames;

  final VoidCallback onCameraPressed;
  final ValueChanged<String> onBarcodeSubmitted;

  const ProductGrid({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.displayProducts,
    required this.barcodeController,
    required this.onProductClick,
    required this.calculatePrice,
    required this.formatCurrency,
    required this.showProductImages,
    required this.showProductNames,
    required this.onCameraPressed,
    required this.onBarcodeSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = (constraints.maxWidth / 116).floor();
        if (crossAxisCount < 4) crossAxisCount = 4;
        if (crossAxisCount > 8) crossAxisCount = 8;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 16 : 8,
                isDesktop ? 16 : 8,
                isDesktop ? 16 : 8,
                isDesktop ? 12 : 8,
              ),
              color: Colors.white,
              child: Container(
                height: isDesktop ? 50 : 40,
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(isDesktop ? 16 : 10),
                  border: Border.all(color: AppColors.slate100, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    SizedBox(width: isDesktop ? 22 : 12),
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AppColors.slate400,
                      size: isDesktop ? 24 : 18,
                    ),
                    SizedBox(width: isDesktop ? 16 : 10),
                    Expanded(
                      child: TextField(
                        controller: barcodeController,
                        onSubmitted: onBarcodeSubmitted,
                        decoration: const InputDecoration(
                          hintText: "พ ->",
                          hintStyle: TextStyle(
                            color: AppColors.slate300,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.slate800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(right: isDesktop ? 8 : 4),
                      child: SizedBox(
                        width: isDesktop ? 44 : 32,
                        height: isDesktop ? 36 : 30,
                        child: ElevatedButton(
                          onPressed: onCameraPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.slate800,
                            foregroundColor: Colors.white,
                            elevation: 6,
                            shadowColor: AppColors.slate900.withOpacity(0.22),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                isDesktop ? 12 : 8,
                              ),
                            ),
                          ),
                          child: Icon(
                            Icons.camera_alt_rounded,
                            size: isDesktop ? 20 : 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            CategoryList(
              categories: categories,
              selectedCategory: selectedCategory,
              onCategorySelected: onCategorySelected,
            ),

            Expanded(
              child: Container(
                color: AppColors.bgLight,
                child: displayProducts.isEmpty
                    ? const Center(
                        child: Text(
                          "ค้าหา",
                          style: TextStyle(
                            color: AppColors.slate400,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          isDesktop ? 16 : 8,
                          isDesktop ? 16 : 8,
                          isDesktop ? 16 : 8,
                          24,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: showProductImages ? 0.72 : 0.92,
                          crossAxisSpacing: isDesktop ? 12 : 6,
                          mainAxisSpacing: isDesktop ? 12 : 8,
                        ),
                        itemCount: displayProducts.length,
                        itemBuilder: (context, index) {
                          final product = displayProducts[index];
                          final pricing = calculatePrice(product, 'normal');
                          final hasDiscount = pricing['discount'] > 0;

                          return _ProductCard(
                            product: product,
                            pricing: pricing,
                            hasDiscount: hasDiscount,
                            formatCurrency: formatCurrency,
                            showProductImages: showProductImages,
                            showProductNames: showProductNames,
                            onTap: () => onProductClick(product),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> pricing;
  final bool hasDiscount;
  final String Function(double) formatCurrency;
  final bool showProductImages;
  final bool showProductNames;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.pricing,
    required this.hasDiscount,
    required this.formatCurrency,
    required this.showProductImages,
    required this.showProductNames,
    required this.onTap,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  static const String _imageBaseUrl =
      'https://xvhibjejvbriotfpunvv.supabase.co/storage/v1/object/public/images/';

  bool _isPressed = false;

  String? _resolveProductImageUrl() {
    final raw =
        widget.product['image_url'] ??
        widget.product['image_name'] ??
        widget.product['image'];
    if (raw == null) return null;

    final value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final cleanName = value.replaceAll(RegExp(r'^/+'), '');
    return '$_imageBaseUrl$cleanName';
  }

  Widget _buildProductImage(String? imageUrl) {
    final localPath = widget.product['local_image_path']?.toString();
    final localFile = localPath == null || localPath.isEmpty
        ? null
        : File(localPath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: double.infinity,
        color: AppColors.slate100,
        child: localFile != null && localFile.existsSync()
            ? Image.file(
                localFile,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.slate300,
                  size: 22,
                ),
              )
            : imageUrl == null
            ? const Icon(
                Icons.image_outlined,
                color: AppColors.slate300,
                size: 22,
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.slate300,
                  size: 22,
                ),
              ),
      ),
    );
  }

  Future<void> _handleTap() async {
    if (_isPressed) return;

    setState(() => _isPressed = true);
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) setState(() => _isPressed = false);
    await Future.delayed(const Duration(milliseconds: 50));

    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.showProductImages
        ? _resolveProductImageUrl()
        : null;

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isPressed
                  ? AppColors.orange500
                  : (widget.hasDiscount
                        ? const Color(0xFFFED7AA)
                        : const Color(0xFFE2E8F0)),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.hasDiscount
                    ? const Color(0xFFFB923C).withOpacity(0.16)
                    : Colors.black.withOpacity(_isPressed ? 0.0 : 0.035),
                blurRadius: _isPressed ? 4 : 12,
                spreadRadius: widget.hasDiscount ? -1 : 0,
                offset: Offset(0, _isPressed ? 1 : 4),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final hasImage = widget.showProductImages;
                  final isCompact = constraints.maxWidth < 104;
                  final padding = hasImage ? 8.0 : 9.0;
                  final imageHeight = hasImage
                      ? (constraints.maxHeight * 0.42).clamp(44.0, 68.0)
                      : 0.0;
                  final nameFontSize = hasImage
                      ? (isCompact ? 11.0 : 12.0)
                      : (isCompact ? 11.5 : 12.5);
                  final priceFontSize = hasImage
                      ? (isCompact ? 13.0 : 14.0)
                      : (isCompact ? 12.8 : 13.8);
                  final originalPriceFontSize = isCompact ? 8.0 : 8.5;

                  return Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasImage) ...[
                          SizedBox(
                            height: imageHeight,
                            width: double.infinity,
                            child: _buildProductImage(imageUrl),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.showProductNames)
                                      Text(
                                        widget.product['name'] ?? '',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: nameFontSize,
                                          color: AppColors.slate700,
                                          height: 1.14,
                                        ),
                                        maxLines: hasImage ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (widget.product['barcode'] != null &&
                                        widget.product['barcode']
                                            .toString()
                                            .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          widget.product['barcode'],
                                          style: const TextStyle(
                                            fontSize: 8,
                                            fontFamily: 'monospace',
                                            color: AppColors.slate400,
                                            height: 1.05,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.hasDiscount)
                                    Text(
                                      widget.formatCurrency(
                                        widget.pricing['original'],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: originalPriceFontSize,
                                        decoration: TextDecoration.lineThrough,
                                        color: AppColors.slate400,
                                        height: 1.05,
                                      ),
                                    ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      widget.formatCurrency(
                                        widget.pricing['final'],
                                      ),
                                      style: TextStyle(
                                        fontSize: priceFontSize,
                                        fontWeight: FontWeight.w900,
                                        color: widget.hasDiscount
                                            ? AppColors.rose500
                                            : AppColors.slate800,
                                        height: 1.08,
                                        letterSpacing: 0,
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
                  );
                },
              ),
              if (widget.hasDiscount)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.rose500,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.rose500.withOpacity(0.22),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      "SALE",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
