import 'package:shared_preferences/shared_preferences.dart';

/// Lectura (solo lectura) del derecho CriptoControlMx Pro.
///
/// AUDITOR├ìA (commit d6b6943): el repositorio no contiene Billing ni ning├║n
/// sistema previo de derechos Pro. Este contrato es el ├║nico punto que el
/// motor inteligente consulta. El futuro m├│dulo de Billing es el responsable
/// de validar compras y de escribir [activeKey]; el motor nunca valida pagos.
abstract class ProEntitlementReader {
  Future<bool> isProActive();
}

class SharedPreferencesProEntitlementReader implements ProEntitlementReader {
  SharedPreferencesProEntitlementReader(this._prefs);

  /// Clave compartida con el Worker nativo (`flutter.pro_entitlement_active_v1`).
  static const String activeKey = 'pro_entitlement_active_v1';

  final SharedPreferences _prefs;

  @override
  Future<bool> isProActive() async {
    await _prefs.reload();
    return _prefs.getBool(activeKey) ?? false;
  }
}
