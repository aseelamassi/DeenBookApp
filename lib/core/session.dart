import 'package:flutter/material.dart';
import 'api.dart';

class Session extends ChangeNotifier {
  Session(this.api) {
    api.onSignedOut = () {
      status = null;
      settings = null;
      ledgerV2 = false;
      error = null;
      pendingSync = 0;
      notifyListeners();
    };
    api.onForbidden = () {
      reload();
    };
    api.onConnectionChanged = notifyListeners;
  }
  final Api api;
  Json? status, settings;
  bool loading = true;
  bool ledgerV2 = false;
  String? error;
  String? startupError;
  int revision = 0;
  int pendingSync = 0;
  bool syncing = false;
  String? syncError;
  bool get isOffline => api.isOffline;
  bool get isTrial => status?['isTrial'] == true;
  int get trialDaysRemaining {
    if (!isTrial) return 0;
    if (!isOffline) return (status?['trialDaysRemaining'] as num?)?.toInt() ?? 0;
    final until = DateTime.tryParse('${status?['paidUntil']}');
    if (until == null) return 0;
    final hours = until.difference(DateTime.now().toUtc()).inHours;
    return hours < 0 ? 0 : (hours / 24).ceil();
  }
  Future<void>? _loadingStatus;
  String get shopId => status?['id'] as String? ?? '';
  String get shopName =>
      settings?['name'] as String? ??
      status?['name'] as String? ??
      'دفتر الأمانة';
  bool get active {
    final paidUntil = DateTime.tryParse('${status?['paidUntil']}');
    return status?['active'] == true && paidUntil != null &&
        paidUntil.isAfter(DateTime.now().toUtc());
  }

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
        await api.rememberStatus(status!);
        pendingSync = await api.pendingCount();
        ledgerV2 = (await api.storage.read('ledgerV2.$shopId')) == 'true';
        if (active) {
          settings = await api.get('/api/settings');
          try {
            final capabilities = await api.get('/api/capabilities');
            ledgerV2 = (capabilities['ledgerVersion'] as num? ?? 0) >= 2;
            if (!api.isOffline) {
              await api.storage.write('ledgerV2.$shopId', '$ledgerV2');
            }
          } on ApiFailure catch (e) {
            if (e.status == 404) {
              ledgerV2 = false;
              if (!api.isOffline) {
                await api.storage.write('ledgerV2.$shopId', 'false');
              }
            } else if (!api.isOffline) {
              rethrow;
            }
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

  Future<void> updatePending() async {
    pendingSync = await api.pendingCount();
    revision++;
    notifyListeners();
  }

  Future<int> synchronize() async {
    if (syncing || !api.signedIn) return 0;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      final synced = await api.synchronize();
      pendingSync = await api.pendingCount();
      if (!api.isOffline) {
        try {
          status = await api.get('/api/subscription');
          await api.rememberStatus(status!);
        } catch (_) {
          // A successful write remains confirmed even if the follow-up status
          // check fails. The next retry can refresh subscription state.
        }
      }
      if (synced > 0) revision++;
      return synced;
    } catch (e) {
      syncError = '$e';
      pendingSync = await api.pendingCount();
      return 0;
    } finally {
      syncing = false;
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
