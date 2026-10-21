import 'package:flutter/material.dart';

import '../provider.dart';
import '../store.dart';
import 'links.dart';
import 'palette.dart';
import 'screen_header.dart';
import 'skeleton.dart';

/// The organisation's storefront: a two column grid of products. Tapping one opens the store in the browser.
class KerabieStoreScreen extends StatefulWidget {
  const KerabieStoreScreen({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<KerabieStoreScreen> createState() => _KerabieStoreScreenState();
}

class _KerabieStoreScreenState extends State<KerabieStoreScreen> {
  KerabieStore? _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store ??= KerabieStore(KerabieProvider.of(context, listen: false));
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KerabiePalette.of(context, KerabieProvider.of(context));
    final store = _store!;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (_, __) => Column(
            children: [
              KerabieScreenHeader(title: store.storeName ?? 'Store', palette: palette, onClose: widget.onClose),
              Expanded(child: _body(store, palette)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(KerabieStore store, KerabiePalette palette) {
    if (store.loading) {
      return GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
        children: [
          for (var i = 0; i < 4; i++)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KerabieSkeleton(color: palette.surfaceStrong, aspectRatio: 1, borderRadius: 12),
                const SizedBox(height: 8),
                FractionallySizedBox(widthFactor: 0.7, child: KerabieSkeleton(color: palette.surfaceStrong, height: 12)),
                const SizedBox(height: 4),
                FractionallySizedBox(widthFactor: 0.4, child: KerabieSkeleton(color: palette.surfaceStrong, height: 12)),
              ],
            ),
        ],
      );
    }
    if (store.products.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(padding: const EdgeInsets.only(top: 32), child: Text('No products yet.', style: TextStyle(fontSize: 13, color: palette.subtle))),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 12, childAspectRatio: 0.78),
      itemCount: store.products.length,
      itemBuilder: (_, i) {
        final product = store.products[i];
        return InkWell(
          onTap: store.storeUrl == null ? null : () => openKerabieLink(store.storeUrl!),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: palette.primary.withValues(alpha: 0.08),
                    child: product.imageUrl != null
                        ? Image.network(product.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Text('📦', style: TextStyle(fontSize: 24))))
                        : const Center(child: Text('📦', style: TextStyle(fontSize: 24))),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.text)),
              const SizedBox(height: 2),
              Text(product.formattedPrice, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.accent)),
            ],
          ),
        );
      },
    );
  }
}
