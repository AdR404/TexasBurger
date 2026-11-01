import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/discount_code.dart';
import 'user_role_service.dart';

class DiscountCodeService extends ChangeNotifier {
  static final DiscountCodeService _instance = DiscountCodeService._internal();
  factory DiscountCodeService() => _instance;
  DiscountCodeService._internal();
  @visibleForTesting
  DiscountCodeService.forTesting();

  static const _storageKey = 'texas_discount_codes';
  List<DiscountCode> _codes = [];
  bool _initialized = false;
  bool _loadFailed = false;
  bool get loadFailed => _loadFailed;
  List<DiscountCode> get codes => List.unmodifiable(_codes);

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored != null && stored.isNotEmpty) {
        final loaded = (jsonDecode(stored) as List<dynamic>)
            .map((item) => DiscountCode.fromJson(item as Map<String, dynamic>))
            .toList();
        if (loaded.any((code) => !code.isValid)) {
          throw const FormatException('Cupón inválido');
        }
        _codes = loaded;
      }
      _initialized = true;
      _loadFailed = false;
    } catch (_) {
      // Do not block startup or overwrite stored data when coupons cannot load.
      _loadFailed = true;
    }
    notifyListeners();
  }

  DiscountCode? findActive(String code) {
    final normalized = code.trim().toUpperCase();
    for (final coupon in _codes) {
      if (coupon.isActive &&
          coupon.isValid &&
          coupon.code.trim().toUpperCase() == normalized) {
        return coupon;
      }
    }
    return null;
  }

  Future<void> save(DiscountCode code) async {
    UserRoleService().requireAdmin();
    if (!code.isValid) throw ArgumentError('Código o importe inválido.');
    final saved = DiscountCode(
      code: code.code.trim().toUpperCase(),
      description: code.description.trim(),
      kind: code.kind,
      value: code.value,
      isActive: code.isActive,
    );
    await _mutate((codes) {
      final index = codes.indexWhere(
        (item) => item.code.trim().toUpperCase() == saved.code,
      );
      if (index < 0) {
        codes.add(saved);
      } else {
        codes[index] = saved;
      }
    });
  }

  Future<void> setActive(String code, bool isActive) async {
    UserRoleService().requireAdmin();
    await _mutate((codes) {
      final index = codes.indexWhere(
        (item) => item.code.trim().toUpperCase() == code.trim().toUpperCase(),
      );
      if (index >= 0) codes[index] = codes[index].copyWith(isActive: isActive);
    });
  }

  Future<void> remove(String code) async {
    UserRoleService().requireAdmin();
    await _mutate(
      (codes) => codes.removeWhere(
        (item) => item.code.trim().toUpperCase() == code.trim().toUpperCase(),
      ),
    );
  }

  Future<void> _writes = Future<void>.value();

  Future<void> _mutate(void Function(List<DiscountCode>) change) {
    final operation = _writes.then((_) => _persistChange(change));
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _persistChange(void Function(List<DiscountCode>) change) async {
    if (!_initialized || _loadFailed) {
      throw StateError(
        'No se pudieron cargar los códigos. Se conservaron los datos guardados.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    UserRoleService().requireAdmin();
    final next = List<DiscountCode>.of(_codes);
    change(next);
    if (!await prefs.setString(
      _storageKey,
      jsonEncode(next.map((c) => c.toJson()).toList()),
    )) {
      throw StateError('No se pudo guardar el código.');
    }
    _codes = next;
    notifyListeners();
  }
}
