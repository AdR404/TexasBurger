import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/discount_code.dart';
import 'discount_code_repository.dart';
import 'user_role_service.dart';

class DiscountCodeService extends ChangeNotifier {
  static final DiscountCodeService _instance =
      DiscountCodeService._internal();

  factory DiscountCodeService() => _instance;

  DiscountCodeService._internal()
    : _repository = DiscountCodeRepository(),
      _testLocal = false;

  @visibleForTesting
  DiscountCodeService.forTesting()
    : _repository = null,
      _testLocal = true;

  final DiscountCodeRepository? _repository;
  final bool _testLocal;

  static const _storageKey = 'texas_discount_codes';

  List<DiscountCode> _codes = [];
  bool _initialized = false;
  bool _loadFailed = false;

  bool get loadFailed => _loadFailed;
  List<DiscountCode> get codes => List.unmodifiable(_codes);

  Future<void> init() async {
    if (_initialized) return;

    try {
      if (_testLocal) {
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString(_storageKey);

        if (stored != null && stored.isNotEmpty) {
          final loaded = (jsonDecode(stored) as List<dynamic>)
              .map(
                (item) => DiscountCode.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList();

          if (loaded.any((code) => !code.isValid)) {
            throw const FormatException('Cupón inválido');
          }

          _codes = loaded;
        }
      } else {
        _codes = await _repository!.fetchAll();
      }

      _initialized = true;
      _loadFailed = false;
    } catch (_) {
      _loadFailed = true;
    }

    notifyListeners();
  }

    Future<void> refresh() async {
      if (_testLocal) {
        await init();
        return;
      }

      try {
        _codes = await _repository!.fetchAll();
        _initialized = true;
        _loadFailed = false;
      } catch (_) {
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

    if (!code.isValid) {
      throw ArgumentError('Código o importe inválido.');
    }

    final saved = DiscountCode(
      code: code.code.trim().toUpperCase(),
      description: code.description.trim(),
      kind: code.kind,
      value: code.value,
      isActive: code.isActive,
    );

    await _mutate(
      (codes) {
        final index = codes.indexWhere(
          (item) => item.code.trim().toUpperCase() == saved.code,
        );

        if (index < 0) {
          codes.add(saved);
        } else {
          codes[index] = saved;
        }
      },
      remoteWrite: () => _repository!.save(saved),
    );
  }

  Future<void> setActive(String code, bool isActive) async {
    UserRoleService().requireAdmin();
    final normalized = code.trim().toUpperCase();

    await _mutate(
      (codes) {
        final index = codes.indexWhere(
          (item) => item.code.trim().toUpperCase() == normalized,
        );

        if (index >= 0) {
          codes[index] = codes[index].copyWith(isActive: isActive);
        }
      },
      remoteWrite: () => _repository!.setActive(normalized, isActive),
    );
  }

  Future<void> remove(String code) async {
    UserRoleService().requireAdmin();
    final normalized = code.trim().toUpperCase();

    await _mutate(
      (codes) => codes.removeWhere(
        (item) => item.code.trim().toUpperCase() == normalized,
      ),
      remoteWrite: () => _repository!.remove(normalized),
    );
  }

  Future<void> _writes = Future<void>.value();

  Future<void> _mutate(
    void Function(List<DiscountCode>) change, {
    required Future<void> Function() remoteWrite,
  }) {
    final operation = _writes.then(
      (_) => _persistChange(change, remoteWrite),
    );

    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _persistChange(
    void Function(List<DiscountCode>) change,
    Future<void> Function() remoteWrite,
  ) async {
    if (!_initialized || _loadFailed) {
      throw StateError(
        'No se pudieron cargar los cupones. Revisa la conexión con la base de datos.',
      );
    }

    UserRoleService().requireAdmin();

    final next = List<DiscountCode>.of(_codes);
    change(next);

    if (_testLocal) {
      final prefs = await SharedPreferences.getInstance();

      final saved = await prefs.setString(
        _storageKey,
        jsonEncode(next.map((coupon) => coupon.toJson()).toList()),
      );

      if (!saved) {
        throw StateError('No se pudo guardar el cupón de prueba.');
      }
    } else {
      await remoteWrite();
    }

    _codes = next;
    notifyListeners();
  }
}
