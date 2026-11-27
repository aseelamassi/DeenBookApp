import 'dart:async';
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
      pendingWorkerSync = 0;
      workerSetup = false;
      notifyListeners();
    };
    api.onForbidden = () {
      reload();
    };
    api.onConnectionChanged = () {
      notifyListeners();
      // A successful request can be the first sign that connectivity has
      // returned. Start sending queued movements immediately in that case.
      if (!api.isOffline && pendingSync > 0 && !syncing) {
        unawaited(synchronize());
      }
    };
  }
  final Api api;
  Json? status, settings;
  bool loading = true;
  bool workerSetup = false;
  bool ledgerV2 = false;
  String? error;
  String? startupError;
  int revision = 0;
  int pendingSync = 0;
  int pendingWorkerSync = 0;
  int get pendingFinancialSync => pendingSync >= pendingWorkerSync
      ? pendingSync - pendingWorkerSync : 0;
  Future<void> _refreshPending() async {
    final catalog = await api.pendingCatalog();
    pendingWorkerSync = (await api.pendingWorkerDeletes()).length + (await api.pendingWorkerRenames()).length + catalog.where((r)=>r['collection']!='/api/transactions').length;
    pendingSync = (await api.currentOutbox()).length + pendingWorkerSync + catalog.where((r)=>r['collection']=='/api/transactions').length;
  }
  bool syncing = false;
  String? syncError;
  bool get isOffline => api.isOffline;
  bool get isTrial => status?['isTrial'] == true;
  bool get isOwner => status?['isOwner'] != false;
  // Identity returned by the authenticated subscription endpoint.
  // Do not substitute the shop name for a worker's identity.
  String get currentUserName {
    final name = '${status?['userName'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    if (isOwner) {
      final owner = '${settings?['ownerName'] ?? ''}'.trim();
      return owner.isNotEmpty ? owner : 'صاحب المحل';
    }
    final workerPhone = '${status?['userPhone'] ?? ''}'.trim();
    return workerPhone.isNotEmpty ? workerPhone : 'عامل المحل';
  }
  String get currentUserPhone => '${status?['userPhone'] ?? ''}'.trim();
  int get trialDaysRemaining {
    if (!isTrial) return 0;
    if (!isOffline) {
      return (status?['trialDaysRemaining'] as num?)?.toInt() ?? 0;
    }
    final until = DateTime.tryParse('${status?['paidUntil']}');
    if (until == null) return 0;
    final hours = until.difference(DateTime.now().toUtc()).inHours;
    return hours < 0 ? 0 : (hours / 24).ceil();
  }

  Future<void>? _loadingStatus;
  String get shopId => status?['id'] as String? ?? '';
  String get shopName =>
      settings?['name'] as String? ?? status?['name'] as String? ?? 'دفتر دين';
  bool get active {
    final paidUntil = DateTime.tryParse('${status?['paidUntil']}');
    return status?['active'] == true &&
        paidUntil != null &&
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

  Future<void> loginForWorkerSetup(String phone, String password) async {
    workerSetup = true;
    try { await login(phone, password); }
    catch (_) { workerSetup = false; rethrow; }
  }
  void finishWorkerSetup() { workerSetup = false; notifyListeners(); }

  Future<void> reload() =>
      _loadingStatus ??= _load().whenComplete(() => _loadingStatus = null);
  Future<void> _load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (api.signedIn) {
        status = await api.get('/api/subscription');
        await _refreshPending();
        ledgerV2 = (await api.storage.read('ledgerV2.$shopId')) == 'true';
        if (active && !api.offlineExpired) {
          settings = await api.get('/api/settings');
          if (!api.isOffline) unawaited(api.warmOfflineCatalog());
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

  int? _lastGraceStage;
  bool? _lastGraceExpired;
  Future<void> checkOfflineGrace() async {
    try { await api.observeOfflineClock(); } catch (_) { /* No financial data is changed. */ }
    final day = api.grace.reminderDay;
    final expired = api.offlineExpired;
    if (day != _lastGraceStage || expired != _lastGraceExpired) {
      _lastGraceStage = day;
      _lastGraceExpired = expired;
      notifyListeners();
    }
  }

  Future<void> updatePending() async {
    await _refreshPending();
    revision++;
    notifyListeners();
    if (pendingSync > 0 && !api.isOffline && !syncing) {
      unawaited(synchronize());
    }
  }

  Future<int> synchronize() async {
    if (syncing || !api.signedIn) return 0;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      final synced = await api.synchronize();
      await _refreshPending();
      if (api.lastVerifiedStatus != null) status = api.lastVerifiedStatus;
      if (!api.isOffline && active) {
        settings = await api.get('/api/settings');
      }
      // Refresh local projections even if the server rejected an operation;
      // its blocked/review state is now different.
      revision++;
      return synced;
    } catch (e) {
      if (api.lastVerifiedStatus != null) status = api.lastVerifiedStatus;
      syncError = '$e';
      await _refreshPending();
      revision++;
      return 0;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  void changed() {
    unawaited(updatePending());
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
