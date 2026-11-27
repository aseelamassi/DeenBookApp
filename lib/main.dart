import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/session.dart';
import 'core/storage.dart';
import 'features/auth.dart';
import 'features/shell.dart';
import 'features/profile.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final session = Session(Api(DeviceStorage()));
    runApp(DeenBookApp(session: session));
    session.initialize();
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text('$e', textDirection: TextDirection.rtl)),
        ),
      ),
    );
  }
}

class DeenBookApp extends StatefulWidget {
  const DeenBookApp({super.key, required this.session});
  final Session session;
  @override
  State<DeenBookApp> createState() => _DeenBookAppState();
}

class _DeenBookAppState extends State<DeenBookApp> with WidgetsBindingObserver {
  Session get session => widget.session;
  Timer? _graceTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _graceTimer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }
  Future<void> _check() async {
    if (!mounted || !session.api.signedIn) return;
    await session.checkOfflineGrace();
    if (!mounted) return;
    if (session.api.offlineExpired && !session.syncing) unawaited(session.synchronize());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }
  @override
  void dispose() {
    _graceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scope(
    session: session,
    child: AnimatedBuilder(
      animation: session,
      builder: (context, _) => MaterialApp(
        key: ValueKey(
          session.api.signedIn
              ? '${session.shopId}:${session.api.verifiedUserId}:${session.active}:${session.api.offlineExpired}'
              : 'signed-out',
        ),
        title: 'دفتر دين',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        builder: (context, child) => ColoredBox(
          color: const Color(0xFF101127),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width >= 700 ? 820 : 480,
              ),
              child: Column(
                children: [
                  if (session.api.signedIn && !session.api.offlineExpired && session.api.grace.reminderDay != null)
                    Material(
                      color: const Color(0xFFFFE4B5),
                      child: SafeArea(bottom: false, child: Row(children: [
                        const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.sync_problem)),
                        Expanded(child: Text('مرّ ${session.api.grace.reminderDay} أيام دون تحقق من الخادم. زامن الآن قبل انتهاء مهلة ${session.api.offlineGraceDays} أيام.', style: const TextStyle(fontSize: 12))),
                        TextButton(onPressed: session.syncing ? null : () { unawaited(session.synchronize()); }, child: const Text('مزامنة الآن')),
                      ])),
                    ),
                  Expanded(child: child!),
                ],
              ),
            ),
          ),
        ),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: session.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : session.startupError != null
            ? Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Empty(
                      'تعذّر تجهيز التطبيق',
                      session.startupError!,
                      action: BusyButton(
                        label: 'إعادة المحاولة',
                        onPressed: session.initialize,
                      ),
                    ),
                  ),
                ),
              )
            : !session.api.signedIn
            ? const LoginScreen()
            : session.api.offlineExpired
            ? Scaffold(
                body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Empty(
                  'انتهت مدة العمل دون إنترنت',
                  'مدة السماح المحددة ${session.api.offlineGraceDays} أيام كحد أقصى، أو حتى انتهاء الاشتراك. بياناتك وعملياتك المحلية محفوظة. اتصل بالخادم للتحقق والمزامنة.',
                  action: Column(children: [
                    if (session.syncError != null) Text(session.syncError!),
                    BusyButton(label: 'مزامنة الآن', busy: session.syncing, onPressed: () async {
                      await session.synchronize();
                      if (!session.api.offlineExpired) await session.reload();
                    }),
                    TextButton(onPressed: session.syncing ? null : () async { await session.api.clear(); }, child: const Text('إعادة تسجيل الدخول (لا تحذف الحركات المحلية)')),
                  ]),
                ))),
              )
            : session.error != null
            ? Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Empty(
                      'تعذّر تحميل الحساب',
                      session.error!,
                      action: Column(
                        children: [
                          BusyButton(
                            label: 'إعادة المحاولة',
                            onPressed: session.reload,
                          ),
                          TextButton(
                            onPressed: session.api.clear,
                            child: const Text('العودة للدخول'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : !session.active
            ? (session.isOwner
                ? const SubscriptionScreen(gate: true)
                : const WorkerSubscriptionLockedScreen())
            : session.workerSetup ? const WorkersScreen() : const AppShell(),
      ),
    ),
  );
}
