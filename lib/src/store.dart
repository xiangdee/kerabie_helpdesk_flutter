import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';
import 'controller.dart';

@immutable
class KerabieProduct {
  const KerabieProduct({required this.id, required this.name, required this.price, required this.currency, this.imageUrl});

  final int id;
  final String name;
  final double price;
  final String currency;
  final String? imageUrl;

  static KerabieProduct? fromServer(Object? raw) {
    if (raw is! Map || raw['id'] is! num) return null;
    return KerabieProduct(
      id: (raw['id'] as num).toInt(),
      name: '${raw['name'] ?? ''}',
      price: (raw['price'] as num?)?.toDouble() ?? 0,
      currency: '${raw['currency'] ?? ''}',
      imageUrl: raw['imageUrl'] is String && (raw['imageUrl'] as String).isNotEmpty ? raw['imageUrl'] as String : null,
    );
  }

  /// The price in the visitor's number format, for example `$12.50`.
  String get formattedPrice {
    try {
      return NumberFormat.simpleCurrency(name: currency).format(price);
    } catch (_) {
      return '$currency $price';
    }
  }
}

/// The organisation's storefront, read only: products and where to buy them.
class KerabieStore extends ChangeNotifier {
  KerabieStore(this._controller) {
    refetch();
  }

  final KerabieController _controller;

  List<KerabieProduct> _products = const [];
  String? _name;
  String? _url;
  bool _loading = true;
  bool _disposed = false;

  List<KerabieProduct> get products => _products;
  String? get storeName => _name;

  /// Public storefronts live at the organisation's subdomain: `https://<slug>.kerabie.com`.
  String? get storeUrl => _url;
  bool get loading => _loading;

  Future<void> refetch() async {
    _loading = true;
    _notify();
    try {
      final api = await _controller.waitForApi();
      final res = await api.get('/public/store/by-widget');
      final raw = res['products'] is List ? res['products'] as List : const [];
      _products = raw.map(KerabieProduct.fromServer).whereType<KerabieProduct>().toList();
      final store = res['store'];
      _name = store is Map ? store['name'] as String? : null;
      final slug = store is Map ? store['slug'] : null;
      _url = slug is String && slug.isNotEmpty ? 'https://$slug.kerabie.com' : null;
    } on KerabieException {
      // Keep the products we have.
    } finally {
      _loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
