import 'package:flutter/material.dart';

import '../store.dart';
import 'links.dart';
import 'palette.dart';

/// A product opened from Home's "Featured products": picture, price, description and a button to the storefront.
/// Same sheet as the web widget's ProductSheet.
Future<void> showKerabieProductSheet(BuildContext context, KerabiePalette palette, KerabieProduct product, String? storeUrl) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: palette.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (_) => _ProductSheet(palette: palette, product: product, storeUrl: storeUrl),
  );
}

class _ProductSheet extends StatelessWidget {
  const _ProductSheet({required this.palette, required this.product, required this.storeUrl});

  final KerabiePalette palette;
  final KerabieProduct product;
  final String? storeUrl;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 8), decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(4))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(product.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35, color: p.text, fontFamily: p.fontFamily)),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, size: 20, color: p.muted),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: ColoredBox(
                        color: p.surface,
                        child: product.imageUrl != null
                            ? Image.network(product.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_outlined, size: 48, color: p.subtle))
                            : Icon(Icons.inventory_2_outlined, size: 48, color: p.subtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(product.formattedPrice, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text, fontFamily: p.fontFamily)),
                  if (product.description != null) ...[
                    const SizedBox(height: 6),
                    Text(product.description!, style: TextStyle(fontSize: 13.5, height: 1.55, color: p.muted, fontFamily: p.fontFamily)),
                  ],
                ],
              ),
            ),
          ),
          if (storeUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: p.gradient ? null : p.primary, gradient: p.brandGradient, borderRadius: BorderRadius.circular(10)),
                  child: TextButton(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13), foregroundColor: p.onPrimary),
                    onPressed: () => openKerabieLink(storeUrl!),
                    child: Text('View in store', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.onPrimary, fontFamily: p.fontFamily)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
