import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cripto_control_mx/cripto_control_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  runApp(
    CriptoControlApp(
      initialThemeModeName: prefs.getString('theme_mode_v25'),
      initialThemeStyleName: prefs.getString('theme_style_v26'),
    ),
  );
}
