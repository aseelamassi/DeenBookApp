import 'package:flutter/material.dart';
import 'api.dart';

class Session extends ChangeNotifier {
  Session(this.api) {
    api.onSignedOut = () {
      status = null;
      settings = null;
      ledgerV2 = false;
      error = null;
      notifyListeners();
    };
    api.onForbidden = () {
      reload();
    };
  }
  final Api api;
  Json? status, settings;
  bool loading = true;
  bool ledgerV2 = false;
  String? error;
  String? startupError;
  int revision = 0;
  Future<void>? _loadingStatus;
  String get shopId => status?['id'] as String? ?? '';
  String get shopName =>
      settings?['name'] as String? ??
      status?['name'] as String? ??
      'دفتر الأمانة';
  bool get active => status?['active'] == true;
  Future<void> initialize() async {
    loading = true;
    startupError = null;
    notifyListeners();
    try {
      await api.restore();
      await reload();
    } catch (_) {
      startupError = 'تعذّر فتح التخزين الآمن على الجهاز. أعد المحاولة.';
      loading = false;
      notifyListeners();
    }
  }

  Future<void> login(String phone, String password) async {
    await api.login(phone, password);
    await reload();
  }

  Future<void> reload() =>
      _loadingStatus ??= _load().whenComplete(() => _loadingStatus = null);
  Future<void> _load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (api.signedIn) {
        status = await api.get('/api/subscription');
        ledgerV2 = false;
        if (active) {
          settings = await api.get('/api/settings');
          try {
            final capabilities = await api.get('/api/capabilities');
            ledgerV2 = (capabilities['ledgerVersion'] as num? ?? 0) >= 2;
          } on ApiFailure catch (e) {
            if (e.status != 404) rethrow;
          }
        }
      }
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void changed() {
    revision++;
    notifyListeners();
  }
}

class Scope extends InheritedWidget {
  const Scope({super.key, required this.session, required super.child});
  final Session session;
  static Session of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Scope>()!.session;
  @override
  bool updateShouldNotify(Scope oldWidget) => session != oldWidget.session;
}
