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

class DeenBookApp extends StatelessWidget {
  const DeenBookApp({super.key, required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) => Scope(
    session: session,
    child: AnimatedBuilder(
      animation: session,
      builder: (context, _) => MaterialApp(
        key: ValueKey(
          session.api.signedIn
              ? '${session.shopId}:${session.active}'
              : 'signed-out',
        ),
        title: 'دفتر الأمانة',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
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
            ? const SubscriptionScreen(gate: true)
            : const AppShell(),
      ),
    ),
  );
}
