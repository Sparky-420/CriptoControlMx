import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cripto_control_mx/cripto_control_app.dart';
import 'package:cripto_control_mx/firebase_options.dart';

const String _analyticsConsentKey = 'analytics_consent_v1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final bool analyticsEnabled = prefs.getBool(_analyticsConsentKey) ?? false;
  var firebaseStatus = 'Inicializado';
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      analyticsEnabled,
    );
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {
    firebaseStatus = 'Error de inicialización';
  }
  runApp(
    CriptoControlApp(
      initialThemeModeName: prefs.getString('theme_mode_v25'),
      initialThemeStyleName: prefs.getString('theme_style_v26'),
      initialAnalyticsEnabled: analyticsEnabled,
      firebaseStatus: firebaseStatus,
    ),
  );
}
