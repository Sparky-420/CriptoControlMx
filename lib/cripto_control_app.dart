Warning: truncated output (original token count: 198575)
Total output lines: 23089

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:_discoveryapis_commons/_discoveryapis_commons.dart' as commons;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/price_alert_service.dart';
import 'services/price_service.dart';
import 'ui/app_theme.dart' as ccmx;

const Set<String> _safeCrashAreas = <String>{
  'cloud',
  'drive',
  'export',
  'import',
  'ocr',
  'price_refresh',
  'reset',
  'unknown',
};
const Set<String> _safeCrashCodes = <String>{
  'network_error',
  'permission_denied',
  'unavailable',
  'auth_required',
  'not_found',
  'invalid_backup',
  'auth_cancelled',
  'ocr_failed',
  'drive_error',
  'cloud_error',
  'export_error',
  'import_error',
  'price_refresh_error',
  'reset_error',
  'unknown',
};
const String _analyticsConsentKey = 'analytics_consent_v1';
const String _crashlyticsConsentKey = 'crashlytics_consent_v1';
const String _summaryViewModeKey = 'summary_view_mode';
const String _summaryChartTypeKey = 'summary_chart_type';
const Set<String> _safeAnalyticsEvents = <String>{
  'app_opened',
  'tab_view',
  'feature_used',
  'backup_created',
  'backup_restored',
  'drive_backup_created',
  'drive_backup_restored',
  'cloud_upload',
  'cloud_download',
  'ocr_result',
  'movement_form_opened',
  'movement_saved',
  'price_refresh',
  'export_created',
  'financial_reset_opened',
  'financial_reset_completed',
};

enum GoogleDriveSessionStatus {
  accountChecking,
  accountConnected,
  accountDisconnected,
  localPendingVerification,
  driveAuthorized,
  driveAuthorizationRequired,
  temporaryError,
}

const Map<String, Set<Object>> _safeAnalyticsParameterValues =
    <String, Set<Object>>{
      'source': <Object>{'local', 'drive', 'firebase', 'ocr', 'manual'},
      'status': <Object>{'started', 'completed', 'failed', 'cancelled'},
      'error_code': <Object>{
        'network_error',
        'permission_denied',
        'unavailable',
        'auth_required',
        'not_found',
        'invalid_backup',
        'auth_cancelled',
        'ocr_failed',
        'drive_error',
        'cloud_error',
        'export_error',
        'import_error',
        'price_refresh_error',
        'reset_error',
        'unknown',
      },
      'sync_mode': <Object>{'manual'},
      'platform': <Object>{'android'},
      'movement_count_bucket': <Object>{'0', '1_10', '11_50', '51_plus'},
      'active_coin_count_bucket': <Object>{'0', '1_3', '4_6', '7_plus'},
    };

class _SafeCrashError {
  const _SafeCrashError(this.area, this.code);
  final String area;
  final String code;
  @override
  String toString() => 'safe_error:$area:$code';
}

String _firebaseOperationCode(Object error) {
  if (error is FirebaseException) {
    final String code = error.code.trim().toLowerCase().replaceAll('-', '_');
    switch (code) {
      case 'permission_denied':
      case 'unavailable':
      case 'not_found':
        return code;
      case 'unauthenticated':
      case 'user_token_expired':
        return 'auth_required';
    }
  }
  final String description = error.toString().toLowerCase();
  if (description.contains('network') ||
      description.contains('socket') ||
      description.contains('timeout')) {
    return 'network_error';
  }
  return 'cloud_error';
}

String _driveOperationCode(Object error) {
  if (error is GoogleSignInException) {
    return error.code == GoogleSignInExceptionCode.canceled ||
            error.code == GoogleSignInExceptionCode.interrupted ||
            error.code == GoogleSignInExceptionCode.uiUnavailable
        ? 'auth_cancelled'
        : 'auth_required';
  }
  if (error is StateError) return 'auth_required';
  final String description = error.toString().toLowerCase();
  if (description.contains('401') ||
      description.contains('unauthorized') ||
      description.contains('invalid credential') ||
      description.contains('login required')) {
    return 'auth_required';
  }
  if (description.contains('403') ||
      description.contains('permission') ||
      description.contains('forbidden') ||
      description.contains('access denied')) {
    return 'permission_denied';
  }
  if (description.contains('network') ||
      description.contains('socket') ||
      description.contains('timeout') ||
      description.contains('503')) {
    return 'network_error';
  }
  if (description.contains('404') || description.contains('not found')) {
    return 'not_found';
  }
  return 'drive_error';
}

String _maskedIdentifier(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) return 'No disponible';
  final int visibleLength = trimmed.length < 6 ? trimmed.length : 6;
  return '${trimmed.substring(0, visibleLength)}…';
}

Future<void> recordSafeError({
  required String area,
  required String code,
  Object? error,
  StackTrace? stackTrace,
  bool fatal = false,
}) async {
  final String safeArea = _safeCrashAreas.contains(area) ? area : 'unknown';
  final String safeCode = _safeCrashCodes.contains(code) ? code : 'unknown';

  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool enabled = prefs.getBool(_crashlyticsConsentKey) ?? false;
    final FirebaseCrashlytics crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(enabled);
    if (!enabled) return;
    await crashlytics.setCustomKey('app_area', safeArea);
    await crashlytics.setCustomKey('area', safeArea);
    await crashlytics.setCustomKey('code', safeCode);
    await crashlytics.setCustomKey('fatal', fatal);
    await crashlytics.recordError(
      _SafeCrashError(safeArea, safeCode),
      stackTrace ?? StackTrace.current,
      fatal: fatal,
    );
  } catch (_) {}
}

Future<void> _logSafeAnalyticsEvent({
  required String name,
  Map<String, Object>? parameters,
}) async {
  if (!_safeAnalyticsEvents.contains(name)) return;
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool enabled = prefs.getBool(_analyticsConsentKey) ?? false;
    final FirebaseAnalytics analytics = FirebaseAnalytics.instance;
    await analytics.setAnalyticsCollectionEnabled(enabled);
    if (!enabled) return;

    final Map<String, Object> safeParameters = <String, Object>{};
    parameters?.forEach((String key, Object value) {
      final Set<Object>? allowedValues = _safeAnalyticsParameterValues[key];
      if (allowedValues != null && allowedValues.contains(value)) {
        safeParameters[key] = value;
      }
    });
    await analytics.logEvent(
      name: name,
      parameters: safeParameters.isEmpty ? null : safeParameters,
    );
  } catch (_) {}
}

class CryptoAssetMetadata {
  const CryptoAssetMetadata({
    required this.symbol,
    required this.name,
    required this.coingeckoId,
    required this.hasLocalIcon,
    required this.isActive,
  });

  final String symbol;
  final String name;
  final String coingeckoId;
  final bool hasLocalIcon;
  final bool isActive;
}

const Map<String, CryptoAssetMetadata> cryptoAssetMetadata =
    <String, CryptoAssetMetadata>{
      'BTC': CryptoAssetMetadata(
        symbol: 'BTC',
        name: 'Bitcoin',
        coingeckoId: 'bitcoin',
        hasLocalIcon: true,
        isActive: true,
      ),
      'ETH': CryptoAssetMetadata(
        symbol: 'ETH',
        name: 'Ethereum',
        coingeckoId: 'ethereum',
        hasLocalIcon: true,
        isActive: true,
      ),
      'LINK': CryptoAssetMetadata(
        symbol: 'LINK',
        name: 'Chainlink',
        coingeckoId: 'chainlink',
        hasLocalIcon: true,
        isActive: true,
      ),
      'LTC': CryptoAssetMetadata(
        symbol: 'LTC',
        name: 'Litecoin',
        coingeckoId: 'litecoin',
        hasLocalIcon: true,
        isActive: true,
      ),
      'UNI': CryptoAssetMetadata(
        symbol: 'UNI',
        name: 'Uniswap',
        coingeckoId: 'uniswap',
        hasLocalIcon: true,
        isActive: true,
      ),
      'USDT': CryptoAssetMetadata(
        symbol: 'USDT',
        name: 'Tether',
        coingeckoId: 'tether',
        hasLocalIcon: true,
        isActive: true,
      ),
      'USDC': CryptoAssetMetadata(
        symbol: 'USDC',
        name: 'USD Coin',
        coingeckoId: 'usd-coin',
        hasLocalIcon: true,
        isActive: true,
      ),
      'XRP': CryptoAssetMetadata(
        symbol: 'XRP',
        name: 'XRP',
        coingeckoId: 'ripple',
        hasLocalIcon: true,
        isActive: true,
      ),
      'SOL': CryptoAssetMetadata(
        symbol: 'SOL',
        name: 'Solana',
        coingeckoId: 'solana',
        hasLocalIcon: true,
        isActive: true,
      ),
      'ATOM': CryptoAssetMetadata(
        symbol: 'ATOM',
        name: 'Cosmos',
        coingeckoId: 'cosmos',
        hasLocalIcon: true,
        isActive: true,
      ),
      'EURC': CryptoAssetMetadata(
        symbol: 'EURC',
        name: 'EURC',
        coingeckoId: 'eurc',
        hasLocalIcon: true,
        isActive: false,
      ),
    };

class CriptoControlApp extends StatefulWidget {
  const CriptoControlApp({
    super.key,
    this.initialThemeModeName,
    this.initialThemeStyleName,
    this.initialAnalyticsEnabled = false,
    this.initialCrashlyticsEnabled = false,
    this.firebaseStatus = 'No disponible',
  });

  final String? initialThemeModeName;
  final String? initialThemeStyleName;
  final bool initialAnalyticsEnabled;
  final bool initialCrashlyticsEnabled;
  final String firebaseStatus;

  @override
  State<CriptoControlApp> createState() => _CriptoControlAppState();
}

class _ImportResult {
  const _ImportResult({
    required this.movementCount,
    required this.snapshotCount,
    this.warnings = const <String>[],
    this.errors = const <String>[],
  });
  final int movementCount, snapshotCount;
  final List<String> warnings, errors;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;
}

class _CriptoControlAppState extends State<CriptoControlApp>
    with WidgetsBindingObserver {
  static const List<String> _coins = [
    'BTC',
    'ETH',
    'LINK',
    'LTC',
    'UNI',
    'USDT',
    'USDC',
    'XRP',
    'SOL',
    'ATOM',
  ];

  static const String _movementsKey = 'movements_json';
  static const String _pricesKey = PriceService.pricesKey;
  static const String _sellFeePercentKey = 'sell_fee_percent';
  static const String _snapshotsKey = 'portfolio_snapshots_v23_json';
  static const String _darkModeKey = 'dark_mode_v24';
  static const String _themeModeKey = 'theme_mode_v25';
  static const String _accentColorKey = 'accent_color_v25';
  static const String _themeStyleKey = 'theme_style_v26';
  static const String _visiblePositionsKey = 'visible_positions_v26';
  static const String _positionSortKey = 'position_sort_v26';
  static const String _snapshotModeKey = 'snapshot_mode_v26';
  static const String _snapshotRetentionKey = 'snapshot_retention_v26';
  static const String _priceRefreshOnOpenKey = 'price_refresh_on_open_v1';
  static const String _priceRefreshAfterMovementKey =
      'price_refresh_after_movement_v1';
  static const String _priceRefreshForegroundModeKey =
      'price_refresh_foreground_mode_v1';
  static const List<String> _googleDriveScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];
  static const String _googleDriveBackupFileName =
      'criptocontrolmx_respaldo.json';
  static const String _googleDriveBackupFileIdKey =
      'google_drive_backup_file_id_v1';
  static const String _googleDriveBackupUpdatedAtKey =
      'google_drive_backup_updated_at_ms_v1';
  static const String _googleDriveBackupAccountEmailKey =
      'google_drive_backup_account_email_v1';
  static const String _googleDriveSessionEmailKey =
      'google_drive_session_email_v1';
  static const String _googleDriveSessionDisplayNameKey =
      'google_drive_session_display_name_v1';
  static const String _googleDriveSessionConnectedAtKey =
      'google_drive_session_connected_at_ms_v1';
  static const String _googleDriveSessionWasConnectedKey =
      'google_drive_session_was_connected_v1';
  static const String _googleDriveAuthorizationKnownKey =
      'google_drive_authorization_known_v1';
  static const String _googleWebClientId =
      '767407830346-bf771ge1ba2roalchb21a4j3fl8v8258.apps.googleusercontent.com';
  static const Set<String> _googleAndroidClientIds = <String>{
    '767407830346-bjlqgsn828sjq677b4t65mmrdgooc35o.apps.googleusercontent.com',
    '767407830346-fhs53hlvnonjb7befttucbq5shqs0a6v.apps.googleusercontent.com',
  };
  static const String _firebaseDeviceIdKey = 'firebase_device_id_v1';
  static const String _firebaseCloudStateUploadedAtKey =
      'firebase_cloud_state_uploaded_at_ms_v1';
  static const String _firebaseCloudStateDeviceIdKey =
      'firebase_cloud_state_device_id_v1';
  static const String _firebaseCloudStateUploadedByDeviceIdKey =
      'firebase_cloud_state_uploaded_by_device_id_v1';
  static const String _firebaseCloudStateDownloadedAtKey =
      'firebase_cloud_state_downloaded_at_ms_v1';
  static const String _firebaseCloudStateDownloadedFromDeviceIdKey =
      'firebase_cloud_state_downloaded_from_device_id_v1';

  final List<Movement> _movements = <Movement>[];
  final List<PortfolioSnapshot> _snapshots = <PortfolioSnapshot>[];
  final PriceService _priceService = PriceService();
  final PriceAlertService _priceAlertService = PriceAlertService();
  Timer? _priceRefreshTimer;

  final Map<String, double> _currentPrices = <String, double>{
    'BTC': 0.0,
    'ETH': 0.0,
    'LINK': 0.0,
    'LTC': 0.0,
    'UNI': 0.0,
    'USDT': 0.0,
    'USDC': 0.0,
    'XRP': 0.0,
    'SOL': 0.0,
    'ATOM': 0.0,
  };
  final Map<String, String> _priceModes = <String, String>{
    for (final String coin in _coins) coin: PriceService.automaticMode,
  };
  final Map<String, int> _manualPriceUpdatedAtMs = <String, int>{};

  int _currentIndex = 0;
  final PageController _mainPageController = PageController();
  double _sellFeePercent = FinancialEngine.defaultExitFeePercent;
  AppVisualMode _visualMode = AppVisualMode.system;
  AppThemeStyle _themeStyle = AppThemeStyle.proDark;
  VisiblePositions _visiblePositions = VisiblePositions.three;
  PositionSortMode _positionSortMode = PositionSortMode.largestValue;
  SummaryViewMode _summaryViewMode = SummaryViewMode.executive;
  SummaryChartType _summaryChartType = SummaryChartType.line;
  SnapshotAutomationMode _snapshotAutomationMode =
      SnapshotAutomationMode.manual;
  SnapshotRetention _snapshotRetention = SnapshotRetention.last30;
  bool _refreshPricesOnOpen = true;
  bool _refreshPricesAfterMovement = false;
  PriceRefreshForegroundMode _priceRefreshForegroundMode =
      PriceRefreshForegroundMode.manual;
  SimulationMode _requestedSimulationMode = SimulationMode.operation;
  int _simulationOpenNonce = 0;
  DateTime? _pricesUpdatedAt;
  bool _isRefreshingPrices = false;
  bool _priceAlertsEnabled = false;
  bool _notificationsAllowed = true;
  bool _automaticLocalAlertsEnabled = false;
  int _automaticLocalAlertsIntervalMinutes =
      PriceAlertService.defaultAutomaticIntervalMinutes;
  double _priceAlertThresholdPercent =
      PriceAlertService.defaultThresholdPercent;
  Map<String, double> _priceAlertReferences = <String, double>{};
  bool _recoveryAlertsEnabled = false;
  double _recoveryAlertThresholdPoints =
      PriceAlertService.defaultRecoveryThresholdPoints;
  Map<String, double> _recoveryAlertReferences = <String, double>{};
  bool _bootstrapped = false;
  Future<void>? _googleSignInInitFuture;
  Future<void>? _googleDriveSessionRestoreFuture;
  StreamSubscription<GoogleSignInAuthenticationEvent>?
  _googleAuthenticationEventsSubscription;
  GoogleSignInAccount? _googleAccount;
  String? _googleDriveSessionEmail;
  String? _googleDriveSessionDisplayName;
  DateTime? _googleDriveSessionConnectedAt;
  bool _googleDriveWasConnected = false;
  bool _googleDriveAuthorizationKnown = false;
  GoogleDriveSessionStatus _googleDriveSessionStatus =
      GoogleDriveSessionStatus.accountDisconnected;
  int _googleDriveAuthGeneration = 0;
  User? _firebaseUser;
  bool _isFirebaseAuthBusy = false;
  bool _isCloudProfilePreparing = false;
  bool _isCloudUploading = false;
  bool _isCloudDownloading = false;
  String _cloudProfileStatus = 'Sin configurar';
  String? _firebaseDeviceId;
  DateTime? _cloudStateUploadedAt;
  DateTime? _cloudStateDownloadedAt;
  bool _isGoogleConnecting = false;
  bool _isGoogleDriveCreating = false;
  bool _isGoogleDriveRestoring = false;
  bool _isGoogleDriveDisconnectingExplicitly = false;
  bool _driveAuthUserInitiated = false;
  final bool _driveGoogleStartupLock = true;
  String? _googleDriveBackupFileId;
  DateTime? _googleDriveBackupUpdatedAt;
  String? _googleDriveBackupAccountEmail;
  bool _analyticsConsent = false;
  bool _crashlyticsConsent = false;

  bool get _isGoogleDriveSessionChecking =>
      _googleDriveSessionStatus == GoogleDriveSessionStatus.accountChecking;

  bool get _isGoogleDriveAuthorized =>
      _googleAccount != null &&
      _googleDriveSessionStatus == GoogleDriveSessionStatus.driveAuthorized;

  bool get _isGoogleDriveBusy =>
      _isGoogleDriveSessionChecking ||
      _isGoogleConnecting ||
      _isGoogleDriveCreating ||
      _isGoogleDriveRestoring;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _priceAlertService.initialize();
    _visualMode = appVisualModeFromName(widget.initialThemeModeName);
    _themeStyle = appThemeStyleFromName(widget.initialThemeStyleName);
    _analyticsConsent = widget.initialAnalyticsEnabled;
    _crashlyticsConsent = widget.initialCrashlyticsEnabled;
    _loadFirebaseAuthUser();
    unawaited(_loadLocalGoogleDriveSessionState());
    unawaited(_loadCloudStateUploadMetadata());
    if (_firebaseUser != null) {
      unawaited(_ensureCloudProfile(showError: false));
    }
    unawaited(
      _logSafeAnalyticsEvent(
        name: 'app_opened',
        parameters: <String, Object>{'platform': 'android'},
      ),
    );
    _loadData();
  }

  @override
  void dispose() {
    _cancelPriceRefreshTimer();
    _googleAuthenticationEventsSubscription?.cancel();
    _mainPageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restartPriceRefreshTimer();
    } else {
      _cancelPriceRefreshTimer();
    }
  }

  void _goToMainTab(int index) {
    if (index == _currentIndex) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _currentIndex = index);
    if (!_mainPageController.hasClients) return;
    unawaited(
      _mainPageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _handleMainPageChanged(int index) {
    if (index == _currentIndex) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _currentIndex = index);
  }

  bool _canTouchGoogleFromCurrentContext(String method) {
    if (_driveAuthUserInitiated) return true;
    if (_driveGoogleStartupLock) {
      debugPrint('DRIVE_AUTH blocked:google_call_during_startup $method');
      debugPrint(StackTrace.current.toString());
      return false;
    }
    debugPrint('DRIVE_AUTH blocked:google_call_without_user_action $method');
    debugPrint(StackTrace.current.toString());
    return false;
  }

  void _ensureGoogleAuthenticationListenerRegistered() {
    if (!_canTouchGoogleFromCurrentContext('authenticationEvents.listen')) {
      throw StateError('Google Sign-In listener blocked during startup');
    }
    if (_googleAuthenticationEventsSubscription != null) return;
    _googleAuthenticationEventsSubscription =
        GoogleSignIn.instance.authenticationEvents.listen(
          _handleGoogleAuthenticationEvent,
        )..onError(_handleGoogleAuthenticationError);
    debugPrint('DRIVE_AUTH listener:registered');
  }

  Future<void> _ensureGoogleSignInInitialized() async {
    if (!_canTouchGoogleFromCurrentContext('initialize')) {
      throw StateError('Google Sign-In initialize blocked during startup');
    }
    debugPrint('DRIVE_AUTH google_init:manual_only');
    _ensureGoogleAuthenticationListenerRegistered();
    _googleSignInInitFuture ??= _initializeGoogleSignInOnce();
    try {
      await _googleSignInInitFuture;
    } catch (_) {
      _googleSignInInitFuture = null;
      rethrow;
    }
  }

  Future<void> _ensureGoogleDriveAuthInitializedFromUserAction(
    String action,
  ) async {
    if (!_driveAuthUserInitiated) {
      debugPrint('DRIVE_AUTH blocked:google_call_during_startup $action');
      debugPrint(StackTrace.current.toString());
      throw StateError('Google Drive auth requires explicit user action');
    }
    await _ensureGoogleSignInInitialized();
  }

  Future<void> _initializeGoogleSignInOnce() async {
    const bool manualServerClientId = true;
    final bool webClientIdPresent = _googleWebClientId.isNotEmpty;
    final bool androidClientIdUsedAsServer = _googleAndroidClientIds.contains(
      _googleWebClientId,
    );
    debugPrint('DRIVE_AUTH config:using_google_services_json');
    debugPrint(
      'DRIVE_AUTH config:manual_server_client_id=$manualServerClientId',
    );
    debugPrint('DRIVE_AUTH config:web_client_id_present=$webClientIdPresent');
    debugPrint(
      'DRIVE_AUTH config:android_client_id_used_as_server=$androidClientIdUsedAsServer',
    );
    debugPrint('DRIVE_AUTH initialize:start');
    await GoogleSignIn.instance.initialize(serverClientId: _googleWebClientId);
    debugPrint('DRIVE_AUTH initialize:success');
  }

  String _redactedDriveEmail(String? email) {
    final String value = email?.trim() ?? '';
    if (value.isEmpty) return 'none';
    final int atIndex = value.indexOf('@');
    if (atIndex <= 0 || atIndex == value.length - 1) return 'redacted';
    return '${value[0]}***${value.substring(atIndex)}';
  }

  Future<T?> _runDriveInteractiveCall<T>(
    String method,
    Future<T> Function() action,
  ) async {
    debugPrint(
      'DRIVE_AUTH INTERACTIVE_CALL $method userInitiated=$_driveAuthUserInitiated',
    );
    debugPrint(StackTrace.current.toString());
    if (!_driveAuthUserInitiated) {
      debugPrint('DRIVE_AUTH blocked:interactive_call_without_user_action');
      return null;
    }
    return action();
  }

  Future<void> _runUserInitiatedDriveAuth(
    String actionName,
    Future<void> Function() action,
  ) async {
    if (_driveAuthUserInitiated) return;
    _driveAuthUserInitiated = true;
    debugPrint('DRIVE_AUTH user_action:$actionName');
    try {
      await action();
    } finally {
      _driveAuthUserInitiated = false;
    }
  }

  String _googleDriveUserActionForConnect() {
    if (_googleDriveSessionStatus ==
        GoogleDriveSessionStatus.localPendingVerification) {
      return 'verify_connection';
    }
    if (_googleDriveSessionStatus == GoogleDriveSessionStatus.temporaryError) {
      return 'reconnect';
    }
    if (_googleAccount != null ||
        _googleDriveSessionStatus ==
            GoogleDriveSessionStatus.driveAuthorizationRequired) {
      return 'authorize';
    }
    return 'connect';
  }

  void _handleGoogleAuthenticationEvent(GoogleSignInAuthenticationEvent event) {
    if (!mounted) return;
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        debugPrint('DRIVE_AUTH event:authenticated email=${event.user.email}');
        final int generation = ++_googleDriveAuthGeneration;
        setState(() {
          _googleAccount = event.user;
          _googleDriveSessionEmail = event.user.email;
          _googleDriveSessionDisplayName = event.user.displayName;
          _googleDriveSessionConnectedAt = DateTime.now();
          _googleDriveWasConnected = true;
          _googleDriveSessionStatus = GoogleDriveSessionStatus.accountConnected;
        });
        debugPrint('DRIVE_AUTH ui:connected');
        unawaited(_saveGoogleDriveSessionMetadata(event.user));
        unawaited(_refreshGoogleDriveAuthorization(event.user, generation));
      case GoogleSignInAuthenticationEventSignOut():
        debugPrint('DRIVE_AUTH event:unauthenticated');
        _googleDriveAuthGeneration++;
        if (_isGoogleDriveDisconnectingExplicitly) {
          unawaited(_clearGoogleDriveSessionMetadata());
        }
        setState(() {
          _googleAccount = null;
          if (_isGoogleDriveDisconnectingExplicitly) {
            _googleDriveSessionEmail = null;
            _googleDriveSessionDisplayName = null;
            _googleDriveSessionConnectedAt = null;
            _googleDriveWasConnected = false;
            _googleDriveAuthorizationKnown = false;
            _googleDriveSessionStatus =
                GoogleDriveSessionStatus.accountDisconnected;
            debugPrint('DRIVE_AUTH ui:disconnected');
          } else {
            final bool hasKnownDriveSession =
                _googleDriveWasConnected || _googleDriveSessionEmail != null;
            _googleDriveSessionStatus = hasKnownDriveSession
                ? GoogleDriveSessionStatus.temporaryError
                : GoogleDriveSessionStatus.accountDisconnected;
            debugPrint(
              hasKnownDriveSession
                  ? 'DRIVE_AUTH ui:temporary_error'
                  : 'DRIVE_AUTH ui:disconnected',
            );
          }
        });
    }
  }

  void _handleGoogleAuthenticationError(Object error) {
    debugPrint('DRIVE_AUTH error:${error.runtimeType}');
    debugPrint('DRIVE_AUTH restore:error_preserving_local_state');
    if (!mounted) return;
    _googleDriveAuthGeneration++;
    setState(() {
      final bool hasKnownDriveSession =
          _googleDriveWasConnected || _googleDriveSessionEmail != null;
      _googleDriveSessionStatus =
          _googleAccount != null && !hasKnownDriveSession
          ? GoogleDriveSessionStatus.accountConnected
          : GoogleDriveSessionStatus.temporaryError;
    });
    debugPrint('DRIVE_AUTH ui:temporary_error');
  }

  Future<void> _refreshGoogleDriveAuthorization(
    GoogleSignInAccount account,
    int generation,
  ) async {
    if (!_canTouchGoogleFromCurrentContext('authorizationForScopes')) return;
    try {
      final GoogleSignInClientAuthorization? authorization = await account
          .authorizationClient
          .authorizationForScopes(_googleDriveScopes);
      if (!mounted ||
          generation != _googleDriveAuthGeneration ||
          _googleAccount?.email != account.email) {
        return;
      }
      setState(() {
        _googleDriveSessionStatus = authorization == null
            ? GoogleDriveSessionStatus.driveAuthorizationRequired
            : GoogleDriveSessionStatus.driveAuthorized;
        _googleDriveAuthorizationKnown = authorization != null;
      });
      debugPrint(
        authorization == null
            ? 'DRIVE_AUTH scopes:required'
            : 'DRIVE_AUTH scopes:authorized',
      );
      debugPrint(
        authorization == null
            ? 'DRIVE_AUTH ui:authorization_required'
            : 'DRIVE_AUTH ui:connected',
      );
      unawaited(_saveGoogleDriveAuthorizationKnown(authorization != null));
    } catch (error) {
      debugPrint('DRIVE_AUTH error:${error.runtimeType}');
      debugPrint('DRIVE_AUTH restore:error_preserving_local_state');
      if (!mounted ||
          generation != _googleDriveAuthGeneration ||
          _googleAccount?.email != account.email) {
        return;
      }
      setState(() {
        _googleDriveSessionStatus = GoogleDriveSessionStatus.temporaryError;
      });
      debugPrint('DRIVE_AUTH ui:temporary_error');
    }
  }

  Future<void> _saveGoogleDriveSessionMetadata(
    GoogleSignInAccount account, {
    bool authorizationKnown = false,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int connectedAtMs = DateTime.now().millisecondsSinceEpoch;
    await prefs.setString(_googleDriveSessionEmailKey, account.email);
    final String? displayName = account.displayName?.trim();
    if (displayName == null || displayName.isEmpty) {
      await prefs.remove(_googleDriveSessionDisplayNameKey);
    } else {
      await prefs.setString(_googleDriveSessionDisplayNameKey, displayName);
    }
    await prefs.setInt(_googleDriveSessionConnectedAtKey, connectedAtMs);
    await prefs.setBool(_googleDriveSessionWasConnectedKey, true);
    await prefs.setBool(_googleDriveAuthorizationKnownKey, authorizationKnown);
  }

  Future<void> _saveGoogleDriveAuthorizationKnown(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_googleDriveAuthorizationKnownKey, value);
  }

  Future<void> _clearGoogleDriveSessionMetadata() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_googleDriveSessionEmailKey);
    await prefs.remove(_googleDriveSessionDisplayNameKey);
    await prefs.remove(_googleDriveSessionConnectedAtKey);
    await prefs.remove(_googleDriveSessionWasConnectedKey);
    await prefs.remove(_googleDriveAuthorizationKnownKey);
  }

  Future<void> _loadLocalGoogleDriveSessionState() async {
    debugPrint('DRIVE_AUTH startup:local_only');
    debugPrint('DRIVE_AUTH startup:no_google_sign_in_calls');
    debugPrint('DRIVE_AUTH startup:no_interactive_login');
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? expectedEmail = prefs.getString(
        _googleDriveSessionEmailKey,
      );
      final String? expectedName = prefs.getString(
        _googleDriveSessionDisplayNameKey,
      );
      final int? connectedAtMs = prefs.getInt(
        _googleDriveSessionConnectedAtKey,
      );
      final bool lastKnownConnected =
          prefs.getBool(_googleDriveSessionWasConnectedKey) ??
          (expectedEmail != null);
      final bool authorizationKnown =
          prefs.getBool(_googleDriveAuthorizationKnownKey) ?? false;
      debugPrint('DRIVE_AUTH prefs:last_known_connected=$lastKnownConnected');
      debugPrint(
        'DRIVE_AUTH prefs:last_known_email=${_redactedDriveEmail(expectedEmail)}',
      );
      if (!mounted) return;
      setState(() {
        _googleAccount = null;
        _googleDriveSessionEmail = expectedEmail;
        _googleDriveSessionDisplayName = expectedName;
        _googleDriveSessionConnectedAt = connectedAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(connectedAtMs);
        _googleDriveWasConnected = lastKnownConnected;
        _googleDriveAuthorizationKnown = authorizationKnown;
        _googleDriveSessionStatus = lastKnownConnected
            ? GoogleDriveSessionStatus.localPendingVerification
            : GoogleDriveSessionStatus.accountDisconnected;
      });
      debugPrint(
        lastKnownConnected
            ? 'DRIVE_AUTH ui:connected_local'
            : 'DRIVE_AUTH ui:never_connected',
      );
    } catch (error) {
      debugPrint('DRIVE_AUTH prefs:error_local_only ${error.runtimeType}');
      if (!mounted) return;
      setState(() {
        _googleAccount = null;
        _googleDriveSessionStatus =
            GoogleDriveSessionStatus.accountDisconnected;
      });
      debugPrint('DRIVE_AUTH ui:never_connected');
    }
  }

  Future<void> _restoreGoogleDriveSession() {
    if (!_canTouchGoogleFromCurrentContext('restoreGoogleDriveSession')) {
      return Future<void>.value();
    }
    final Future<void>? pending = _googleDriveSessionRestoreFuture;
    if (pending != null) return pending;
    final Future<void> restore = _restoreGoogleDriveSessionOnce();
    _googleDriveSessionRestoreFuture = restore;
    return restore.whenComplete(() {
      if (identical(_googleDriveSessionRestoreFuture, restore)) {
        _googleDriveSessionRestoreFuture = null;
      }
    });
  }

  Future<void> _restoreGoogleDriveSessionOnce() async {
    final int generation = ++_googleDriveAuthGeneration;
    String? expectedEmail = _googleDriveSessionEmail;
    bool lastKnownConnected = _googleDriveWasConnected;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expectedEmail = prefs.getString(_googleDriveSessionEmailKey);
      final String? expectedName = prefs.getString(
        _googleDriveSessionDisplayNameKey,
      );
      final int? connectedAtMs = prefs.getInt(
        _googleDriveSessionConnectedAtKey,
      );
      lastKnownConnected =
          prefs.getBool(_googleDriveSessionWasConnectedKey) ??
          (expectedEmail != null);
      final bool authorizationKnown =
          prefs.getBool(_googleDriveAuthorizationKnownKey) ?? false;
      debugPrint('DRIVE_AUTH prefs:last_known_connected=$lastKnownConnected');
      debugPrint(
        'DRIVE_AUTH prefs:last_known_email=${_redactedDriveEmail(expectedEmail)}',
      );
      if (mounted && expectedEmail != null) {
        setState(() {
          _googleDriveSessionEmail = expectedEmail;
          _googleDriveSessionDisplayName = expectedName;
          _googleDriveSessionConnectedAt = connectedAtMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(connectedAtMs);
          _googleDriveWasConnected = lastKnownConnected;
          _googleDriveAuthorizationKnown = authorizationKnown;
        });
      }
    } catch (_) {}
    debugPrint('DRIVE_AUTH silent_check:no_interactive_login');
    if (mounted) {
      setState(
        () => _googleDriveSessionStatus =
            GoogleDriveSessionStatus.accountChecking,
      );
      if (lastKnownConnected) {
        debugPrint('DRIVE_AUTH manual_verify:show_restoring_state');
        debugPrint('DRIVE_AUTH ui:restoring');
      }
    }
    try {
      await _ensureGoogleDriveAuthInitializedFromUserAction(
        'verify_connection',
      );
      if (!_canTouchGoogleFromCurrentContext(
        'attemptLightweightAuthentication',
      )) {
        return;
      }
      debugPrint('DRIVE_AUTH silent_check:start');
      final Future<GoogleSignInAccount?>? lightweightAttempt = GoogleSignIn
          .instance
          .attemptLightweightAuthentication();
      final GoogleSignInAccount? account = lightweightAttempt == null
          ? null
          : await lightweightAttempt;
      if (!mounted || generation != _googleDriveAuthGeneration) return;
      if (account == null) {
        debugPrint(
          'DRIVE_AUTH silent_check:unauthenticated_preserving_local_state',
        );
        setState(() {
          _googleAccount = null;
          _googleDriveSessionStatus = lastKnownConnected
              ? GoogleDriveSessionStatus.temporaryError
              : GoogleDriveSessionStatus.accountDisconnected;
        });
        debugPrint(
          lastKnownConnected
              ? 'DRIVE_AUTH ui:temporary_error'
              : 'DRIVE_AUTH ui:disconnected',
        );
        return;
      }
      debugPrint('DRIVE_AUTH silent_check:authenticated');
      debugPrint('DRIVE_AUTH event:authenticated email=${account.email}');
      setState(() {
        _googleAccount = account;
        _googleDriveSessionEmail = account.email;
        _googleDriveSessionDisplayName = account.displayName;
        _googleDriveSessionConnectedAt = DateTime.now();
        _googleDriveWasConnected = true;
        _googleDriveSessionStatus = GoogleDriveSessionStatus.accountConnected;
      });
      debugPrint('DRIVE_AUTH ui:connected');
      unawaited(_saveGoogleDriveSessionMetadata(account));
      await _refreshGoogleDriveAuthorization(account, generation);
    } catch (error, stackTrace) {
      debugPrint('DRIVE_AUTH error:${error.runtimeType}');
      debugPrint('DRIVE_AUTH silent_check:error_preserving_local_state');
      unawaited(
        recordSafeError(
          area: 'drive',
          code: 'drive_error',
          stackTrace: stackTrace,
        ),
      );
      if (!mounted || generation != _googleDriveAuthGeneration) return;
      setState(() {
        _googleDriveSessionStatus =
            lastKnownConnected ||
                expectedEmail != null ||
                _googleAccount != null
            ? GoogleDriveSessionStatus.temporaryError
            : GoogleDriveSessionStatus.accountDisconnected;
      });
      debugPrint(
        lastKnownConnected || expectedEmail != null || _googleAccount != null
            ? 'DRIVE_AUTH ui:temporary_error'
            : 'DRIVE_AUTH ui:disconnected',
      );
    }
  }

  Future<void> _setAnalyticsConsent(
    BuildContext pageContext,
    bool enabled,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_analyticsConsentKey, enabled);
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _analyticsConsent = enabled);
    if (pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('Preferencia de privacidad actualizada.')),
      );
    }
  }

  Future<void> _setCrashlyticsConsent(
    BuildContext pageContext,
    bool enabled,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_crashlyticsConsentKey, enabled);
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        enabled,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _crashlyticsConsent = enabled);
    if (pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('Preferencia de privacidad actualizada.')),
      );
    }
  }

  void _loadFirebaseAuthUser() {
    try {
      _firebaseUser = FirebaseAuth.instance.currentUser;
      _cloudProfileStatus = _firebaseUser == null
          ? 'Sin cuenta'
          : 'Sin configurar';
    } catch (_) {
      _firebaseUser = null;
      _cloudProfileStatus = 'Revisar conexión';
    }
  }

  Future<void> _loadCloudStateUploadMetadata() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? uploadedAtMs = prefs.getInt(_firebaseCloudStateUploadedAtKey);
    final int? downloadedAtMs = prefs.getInt(
      _firebaseCloudStateDownloadedAtKey,
    );
    final String? uploadedDeviceId =
        prefs.getString(_firebaseCloudStateUploadedByDeviceIdKey) ??
        prefs.getString(_firebaseCloudStateDeviceIdKey);
    final String? downloadedDeviceId = prefs.getString(
      _firebaseCloudStateDownloadedFromDeviceIdKey,
    );
    final String? localDeviceId = prefs.getString(_firebaseDeviceIdKey);
    if (!mounted) return;
    setState(() {
      _cloudStateUploadedAt = uploadedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(uploadedAtMs);
      _cloudStateDownloadedAt = downloadedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(downloadedAtMs);
      _firebaseDeviceId =
          downloadedDeviceId ?? uploadedDeviceId ?? localDeviceId;
    });
  }

  Future<String> _localFirebaseDeviceId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString(_firebaseDeviceIdKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved;
    }

    final String suffix = math.Random().nextInt(0xFFFFFF).toRadixString(16);
    final String deviceId =
        'android-${DateTime.now().millisecondsSinceEpoch}-$suffix';
    await prefs.setString(_firebaseDeviceIdKey, deviceId);
    return deviceId;
  }

  bool _movementJsonNeedsSyncMetadata(Map<String, dynamic> json) {
    return textFromJson(json['id']).isEmpty ||
        DateTime.tryParse(json['createdAt']?.toString() ?? '') == null ||
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') == null ||
        textFromJson(json['deviceId']).isEmpty;
  }

  bool _normalizeMovementSyncMetadata(
    List<Movement> movements,
    String deviceId,
  ) {
    var changed = false;
    final Set<String> seenIds = <String>{};

    for (var i = 0; i < movements.length; i++) {
      final Movement movement = movements[i];
      var id = movement.id.trim();
      final bool duplicate = id.isEmpty || seenIds.contains(id);
      if (duplicate) {
        id = _generateMovementId();
        changed = true;
      }
      seenIds.add(id);

      final String? normalizedDeviceId =
          movement.deviceId == null || movement.deviceId!.trim().isEmpty
          ? deviceId
          : movement.deviceId;
      if (movement.id != id || movement.deviceId != normalizedDeviceId) {
        movements[i] = movement.copyWith(id: id, deviceId: normalizedDeviceId);
        changed = true;
      }
    }

    return changed;
  }

  Future<Movement> _movementWithCurrentSyncMetadata(
    Movement movement, {
    Movement? existing,
  }) async {
    final DateTime now = DateTime.now();
    final String deviceId = await _localFirebaseDeviceId();
    return movement.copyWith(
      id: existing?.id ?? movement.id,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      deletedAt: existing?.deletedAt,
      deviceId: existing?.deviceId ?? movement.deviceId ?? deviceId,
      schemaVersion: 1,
    );
  }

  DateTime? _cloudDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return DateTime.tryParse(value?.toString() ?? '');
  }

  DateTime? _latestLocalMovementUpdatedAt() {
    DateTime? latest;
    for (final Movement movement in _movements) {
      if (latest == null || movement.updatedAt.isAfter(latest)) {
        latest = movement.updatedAt;
      }
    }
    return latest;
  }

  bool _hasPossibleCloudDownloadConflict({
    required DateTime? cloudUploadedAt,
    required String? uploadedByDeviceId,
    required String localDeviceId,
  }) {
    if (_movements.isEmpty) return false;
    final DateTime? latestLocal = _latestLocalMovementUpdatedAt();
    final DateTime? latestSync =
        <DateTime?>[
          _cloudStateUploadedAt,
          _cloudStateDownloadedAt,
        ].whereType<DateTime>().fold<DateTime?>(
          null,
          (DateTime? current, DateTime value) =>
              current == null || value.isAfter(current) ? value : current,
        );
    final bool fromOtherDevice =
        uploadedByDeviceId != null &&
        uploadedByDeviceId.isNotEmpty &&
        uploadedByDeviceId != localDeviceId;
    final bool cloudOlderThanLocal =
        latestLocal != null &&
        cloudUploadedAt != null &&
        latestLocal.isAfter(cloudUploadedAt);
    final bool localAfterLastSync =
        latestLocal != null &&
        (latestSync == null || latestLocal.isAfter(latestSync));
    return fromOtherDevice || cloudOlderThanLocal || localAfterLastSync;
  }

  Future<bool> _ensureCloudProfile({
    ScaffoldMessengerState? messenger,
    bool showError = true,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _cloudProfileStatus = 'Sin cuenta');
      return false;
    }

    if (mounted) {
      setState(() {
        _isCloudProfilePreparing = true;
        _cloudProfileStatus = 'Preparando…';
      });
    }
    try {
      final String deviceId = await _localFirebaseDeviceId();
      if (!mounted) return false;
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final DocumentReference<Map<String, dynamic>> userRef = firestore
          .collection('users')
          .doc(user.uid);
      final DocumentSnapshot<Map<String, dynamic>> userSnapshot = await userRef
          .get();
      if (!mounted) return false;
      final DocumentReference<Map<String, dynamic>> deviceRef = userRef
          .collection('devices')
          .doc(deviceId);
      final DocumentSnapshot<Map<String, dynamic>> deviceSnapshot =
          await deviceRef.get();
      if (!mounted) return false;

      final Map<String, dynamic> userData = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        if (user.photoURL != null) 'photoUrl': user.photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
        'appName': 'CriptoControlMx',
        'cloudSchemaVersion': 1,
      };
      if (!userSnapshot.exists) {
        userData['createdAt'] = FieldValue.serverTimestamp();
      }

      final Map<String, dynamic> deviceData = <String, dynamic>{
        'deviceId': deviceId,
        'platform': 'android',
        'lastSeenAt': FieldValue.serverTimestamp(),
        'deviceLabel': 'Android',
        'syncEnabled': false,
        'syncStatus': 'not_configured',
      };
      if (!deviceSnapshot.exists) {
        deviceData['firstSeenAt'] = FieldValue.serverTimestamp();
      }

      await userRef.set(userData, SetOptions(merge: true));
      if (!mounted) return false;
      await deviceRef.set(deviceData, SetOptions(merge: true));

      if (!mounted) return true;
      setState(() {
        _firebaseDeviceId = deviceId;
        _cloudProfileStatus = 'Configurado';
      });
      return true;
    } catch (error, stackTrace) {
      final String code = _firebaseOperationCode(error);
      unawaited(
        recordSafeError(area: 'cloud', code: code, stackTrace: stackTrace),
      );
      if (!mounted) return false;
      setState(() => _cloudProfileStatus = 'Revisar conexión');
      if (showError && messenger != null && messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo preparar el perfil cloud. Tus datos locales no se modificaron.',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isCloudProfilePreparing = false);
    }
  }

  Future<bool> _confirmCloudStateUpload(BuildContext pageContext) async {
    if (!pageContext.mounted) return false;
    final bool? confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Subir estado a la nube'),
        content: const Text(
          'Esto guardará tu estado financiero actual en Firebase y '
          'reemplazará la copia cloud anterior. No se descargarán ni '
          'mezclarán datos en esta fase.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              final NavigatorState? navigator = Navigator.maybeOf(
                dialogContext,
              );
              if (dialogContext.mounted &&
                  navigator != null &&
                  navigator.canPop()) {
                navigator.pop(false);
              }
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final NavigatorState? navigator = Navigator.maybeOf(
                dialogContext,
              );
              if (dialogContext.mounted &&
                  navigator != null &&
                  navigator.canPop()) {
                navigator.pop(true);
              }
            },
            child: const Text('Subir y reemplazar nube'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _uploadFinancialStateToFirebase(BuildContext pageContext) async {
    if (_isCloudUploading) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    final User? user = FirebaseAuth.instance.currentUser;

    if (widget.firebaseStatus != 'Inicializado' || user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Inicia sesión para usar la nube.')),
      );
      return;
    }

    if (!await _confirmCloudStateUpload(pageContext)) return;
    if (!mounted || !pageContext.mounted) return;

    setState(() => _isCloudUploading = true);
    try {
      final bool profileReady = await _ensureCloudProfile(messenger: messenger);
      if (!mounted || !pageContext.mounted || !profileReady) return;
      final String deviceId = await _localFirebaseDeviceId();
      if (!mounted || !pageContext.mounted) return;
      final Object? decoded = jsonDecode(_buildBackupJson());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Payload financiero inválido');
      }
      final Object? movements = decoded['movements'];
      final Object? snapshots = decoded['snapshots'];
      if (movements is! List || snapshots is! List) {
        throw const FormatException('Payload financiero incompleto');
      }

      final DateTime uploadedAt = DateTime.now();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('cloudState')
          .doc('current')
          .set(<String, dynamic>{
            'schemaVersion': 1,
            'uploadedAt': FieldValue.serverTimestamp(),
            'uploadedAtLocal': uploadedAt.toIso8601String(),
            'uploadedByDeviceId': deviceId,
            'appName': 'CriptoControlMx',
            if (decoded['version'] != null) 'backupVersion': decoded['version'],
            'payload': decoded,
          }, SetOptions(merge: true));
      if (!mounted || !pageContext.mounted) return;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!mounted || !pageContext.mounted) return;
      await prefs.setInt(
        _firebaseCloudStateUploadedAtKey,
        uploadedAt.millisecondsSinceEpoch,
      );
      if (!mounted || !pageContext.mounted) return;
      await prefs.setString(_firebaseCloudStateDeviceIdKey, deviceId);
      if (!mounted || !pageContext.mounted) return;
      await prefs.setString(_firebaseCloudStateUploadedByDeviceIdKey, deviceId);

      if (!mounted || !pageContext.mounted) return;
      setState(() {
        _cloudStateUploadedAt = uploadedAt;
        _firebaseDeviceId = deviceId;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Estado subido a Firebase: ${movements.length} movimientos, '
            '${snapshots.length} instantáneas.',
          ),
        ),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'cloud_upload',
          parameters: <String, Object>{
            'source': 'firebase',
            'status': 'completed',
            'sync_mode': 'manual',
          },
        ),
      );
    } catch (error, stackTrace) {
      final String code = error is FormatException
          ? 'invalid_backup'
          : _firebaseOperationCode(error);
      unawaited(
        recordSafeError(area: 'cloud', code: code, stackTrace: stackTrace),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'cloud_upload',
          parameters: <String, Object>{
            'source': 'firebase',
            'status': 'failed',
            'sync_mode': 'manual',
            'error_code': code,
          },
        ),
      );
      if (!mounted || !pageContext.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo subir a Firebase. Tus datos locales no se modificaron.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCloudUploading = false);
    }
  }

  Future<bool> _confirmCloudStateDownload(
    BuildContext pageContext, {
    required bool hasPossibleConflict,
  }) async {
    final String message = hasPossibleConflict
        ? 'Esto reemplazará tus datos financieros actuales con el estado '
              'guardado en Firebase. No se mezclarán datos en esta fase.\n\n'
              'Se detectaron posibles cambios locales no sincronizados. Crea una '
              'copia antes de continuar.'
        : 'Esto reemplazará tus datos financieros actuales con el estado '
              'guardado en Firebase. No se mezclarán datos en esta fase.';
    if (!pageContext.mounted) return false;
    final bool? confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Descargar estado desde la nube'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              final NavigatorState? navigator = Navigator.maybeOf(
                dialogContext,
              );
              if (dialogContext.mounted &&
                  navigator != null &&
                  navigator.canPop()) {
                navigator.pop(false);
              }
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final NavigatorState? navigator = Navigator.maybeOf(
                dialogContext,
              );
              if (dialogContext.mounted &&
                  navigator != null &&
                  navigator.canPop()) {
                navigator.pop(true);
              }
            },
            child: const Text('Descargar y reemplazar'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _downloadFinancialStateFromFirebase(
    BuildContext pageContext,
  ) async {
    if (_isCloudDownloading) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Inicia sesión para usar la nube.')),
      );
      return;
    }

    setState(() => _isCloudDownloading = true);
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('cloudState')
              .doc('current')
              .get();
      if (!mounted || !pageContext.mounted) return;

      if (!snapshot.exists) {
        if (!mounted || !pageContext.mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('No hay copia en Firebase todavía.')),
        );
        return;
      }

      final Map<String, dynamic>? data = snapshot.data();
      final Object? payload = data?['payload'];
      if (payload == null) {
        throw const FormatException('Payload cloud faltante');
      }

      final String localDeviceId = await _localFirebaseDeviceId();
      if (!mounted || !pageContext.mounted) return;
      final DateTime? cloudUploadedAt =
          _cloudDateTime(data?['uploadedAt']) ??
          _cloudDateTime(data?['uploadedAtLocal']);
      final String? uploadedByDeviceId = data?['uploadedByDeviceId']
          ?.toString();
      final bool hasPossibleConflict = _hasPossibleCloudDownloadConflict(
        cloudUploadedAt: cloudUploadedAt,
        uploadedByDeviceId: uploadedByDeviceId,
        localDeviceId: localDeviceId,
      );
      if (!await _confirmCloudStateDownload(
        pageContext,
        hasPossibleConflict: hasPossibleConflict,
      )) {
        return;
      }
      if (!mounted || !pageContext.mounted) return;

      final _ImportResult result = await _applyBackupJson(jsonEncode(payload));
      if (!mounted || !pageContext.mounted) return;
      final DateTime downloadedAt = DateTime.now();

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!mounted || !pageContext.mounted) return;
      await prefs.setInt(
        _firebaseCloudStateDownloadedAtKey,
        downloadedAt.millisecondsSinceEpoch,
      );
      if (!mounted || !pageContext.mounted) return;
      if (uploadedByDeviceId != null && uploadedByDeviceId.isNotEmpty) {
        await prefs.setString(
          _firebaseCloudStateDownloadedFromDeviceIdKey,
          uploadedByDeviceId,
        );
        if (!mounted || !pageContext.mounted) return;
      }

      if (!mounted || !pageContext.mounted) return;
      setState(() {
        _cloudStateDownloadedAt = downloadedAt;
        _firebaseDeviceId = uploadedByDeviceId ?? _firebaseDeviceId;
      });
      _showImportResult(messenger, result, fileName: 'Firebase');
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'cloud_download',
          parameters: <String, Object>{
            'source': 'firebase',
            'status': 'completed',
            'sync_mode': 'manual',
          },
        ),
      );
    } on FormatException catch (_, stackTrace) {
      unawaited(
        recordSafeError(
          area: 'cloud',
          code: 'invalid_backup',
          stackTrace: stackTrace,
        ),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'cloud_download',
          parameters: <String, Object>{
            'source': 'firebase',
            'status': 'failed',
            'sync_mode': 'manual',
            'error_code': 'invalid_backup',
          },
        ),
      );
      if (!mounted || !pageContext.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('El estado guardado en la nube no es válido.'),
        ),
      );
    } catch (error, stackTrace) {
      final String code = _firebaseOperationCode(error);
      unawaited(
        recordSafeError(area: 'cloud', code: code, stackTrace: stackTrace),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'cloud_download',
          parameters: <String, Object>{
            'source': 'firebase',
            'status': 'failed',
            'sync_mode': 'manual',
            'error_code': code,
          },
        ),
      );
      if (!mounted || !pageContext.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo descargar de Firebase. Tus datos locales no se modificaron.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCloudDownloading = false);
    }
  }

  bool _isCanceledGoogleSignIn(GoogleSignInException error) =>
      error.code == GoogleSignInExceptionCode.canceled ||
      error.code == GoogleSignInExceptionCode.interrupted ||
      error.code == GoogleSignInExceptionCode.uiUnavailable;

  Future<void> _signInFirebaseWithGoogle(BuildContext pageContext) async {
    if (_isFirebaseAuthBusy) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);

    setState(() => _isFirebaseAuthBusy = true);
    try {
      await _ensureGoogleDriveAuthInitializedFromUserAction('firebase_sign_in');
      if (!mounted || !pageContext.mounted) return;
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw UnsupportedError('Google Sign-In no disponible');
      }

      debugPrint(
        'DRIVE_AUTH INTERACTIVE_CALL firebase_authenticate userInitiated=$_driveAuthUserInitiated',
      );
      debugPrint(StackTrace.current.toString());
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();
      if (!mounted || !pageContext.mounted) return;
      final String? idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google ID token no disponible');
      }

      final UserCredential credential = await FirebaseAuth.instance
          .signInWithCredential(
            GoogleAuthProvider.credential(idToken: idToken),
          );

      if (!mounted || !pageContext.mounted) return;
      setState(() => _firebaseUser = credential.user);
      final bool profileReady = await _ensureCloudProfile(messenger: messenger);
      if (!mounted || !pageContext.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            profileReady
                ? 'Sesión iniciada y perfil cloud preparado.'
                : 'Sesión iniciada; el perfil cloud requiere reintento.',
          ),
        ),
      );
    } on GoogleSignInException catch (error) {
      if (!mounted || !pageContext.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isCanceledGoogleSignIn(error)
                ? 'No se inició sesión.'
                : 'No se pudo iniciar sesión.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !pageContext.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo iniciar sesión.')),
      );
    } finally {
      if (mounted) setState(() => _isFirebaseAuthBusy = false);
    }
  }

  Future<void> _signOutFirebase(BuildContext pageContext) async {
    if (_isFirebaseAuthBusy) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);

    setState(() => _isFirebaseAuthBusy = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted || !pageContext.mounted) return;
      setState(() {
        _firebaseUser = null;
        _cloudProfileStatus = 'Sin configurar';
      });
      messenger.showSnackBar(const SnackBar(content: Text('Sesión cerrada.')));
    } catch (_) {
      if (!mounted || !pageContext.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo cerrar sesión.')),
      );
    } finally {
      if (mounted) setState(() => _isFirebaseAuthBusy = false);
    }
  }

  Future<void> _retryCloudProfile(BuildContext pageContext) async {
    if (_isCloudProfilePreparing) return;
    final ScaffoldMessengerState? messenger = pageContext.mounted
        ? ScaffoldMessenger.maybeOf(pageContext)
        : null;
    if (messenger == null) return;
    final bool prepared = await _ensureCloudProfile(messenger: messenger);
    if (!mounted) return;
    if (!prepared || !messenger.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Perfil cloud preparado.')),
    );
  }

  Future<void> _connectGoogleDrive(BuildContext pageContext) async {
    if (_isGoogleDriveBusy) return;
    if (!_driveAuthUserInitiated) {
      debugPrint('DRIVE_AUTH blocked:interactive_flow_without_user_action');
      debugPrint(StackTrace.current.toString());
      return;
    }
    final bool verifyOnly =
        _googleDriveSessionStatus ==
        GoogleDriveSessionStatus.localPendingVerification;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    var errorMessage = 'No se pudo conectar Google Drive.';

    setState(() {
      _isGoogleConnecting = true;
      _googleDriveSessionStatus = GoogleDriveSessionStatus.accountChecking;
    });
    try {
      if (verifyOnly) {
        debugPrint(
          'DRIVE_AUTH local:authorization_known=$_googleDriveAuthorizationKnown',
        );
        await _restoreGoogleDriveSession();
        if (!mounted || !pageContext.mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Verificacion de Drive finalizada.')),
        );
        return;
      }
      await _ensureGoogleDriveAuthInitializedFromUserAction('connect');
      GoogleSignInAccount? account = _googleAccount;
      if (account == null) {
        if (!GoogleSignIn.instance.supportsAuthenticate()) {
          throw UnsupportedError('Google Sign-In no disponible');
        }
        account = await _runDriveInteractiveCall<GoogleSignInAccount>(
          'authenticate',
          () =>
              GoogleSignIn.instance.authenticate(scopeHint: _googleDriveScopes),
        );
        if (account == null) {
          throw StateError('Google authentication blocked');
        }
        if (!mounted || !pageContext.mounted) return;
        final GoogleSignInAccount authenticatedAccount = account;
        debugPrint(
          'DRIVE_AUTH event:authenticated email=${authenticatedAccount.email}',
        );
        final int generation = ++_googleDriveAuthGeneration;
        setState(() {
          _googleAccount = authenticatedAccount;
          _googleDriveSessionEmail = authenticatedAccount.email;
          _googleDriveSessionDisplayName = authenticatedAccount.displayName;
          _googleDriveSessionConnectedAt = DateTime.now();
          _googleDriveWasConnected = true;
          _googleDriveSessionStatus = GoogleDriveSessionStatus.accountConnected;
        });
        debugPrint('DRIVE_AUTH ui:connected');
        unawaited(_saveGoogleDriveSessionMetadata(authenticatedAccount));
        if (generation != _googleDriveAuthGeneration) return;
      }

      final GoogleSignInAccount activeAccount = account;
      errorMessage = 'No se pudo autorizar Google Drive.';
      final GoogleSignInClientAuthorization? currentAuthorization =
          await activeAccount.authorizationClient.authorizationForScopes(
            _googleDriveScopes,
          );
      if (!mounted || !pageContext.mounted) return;
      final GoogleSignInClientAuthorization? grantedAuthorization =
          currentAuthorization ??
          await _runDriveInteractiveCall<GoogleSignInClientAuthorization>(
            'authorizeScopes',
            () => activeAccount.authorizationClient.authorizeScopes(
              _googleDriveScopes,
            ),
          );
      if (grantedAuthorization == null) {
        throw StateError('Google Drive authorization blocked');
      }
      final Map<String, String>? authHeaders = await activeAccount
          .authorizationClient
          .authorizationHeaders(_googleDriveScopes);
      if (authHeaders == null) {
        throw StateError('Google Drive authorization headers unavailable');
      }

      if (!mounted || !pageContext.mounted) return;
      _googleDriveAuthGeneration++;
      unawaited(
        _saveGoogleDriveSessionMetadata(
          activeAccount,
          authorizationKnown: true,
        ),
      );
      setState(() {
        _googleAccount = activeAccount;
        _googleDriveSessionEmail = activeAccount.email;
        _googleDriveSessionDisplayName = activeAccount.displayName;
        _googleDriveSessionConnectedAt = DateTime.now();
        _googleDriveWasConnected = true;
        _googleDriveAuthorizationKnown = true;
        _googleDriveSessionStatus = GoogleDriveSessionStatus.driveAuthorized;
      });
      debugPrint('DRIVE_AUTH scopes:authorized');
      debugPrint('DRIVE_AUTH ui:connected');
      messenger.showSnackBar(
        const SnackBar(content: Text('Google Drive conectado.')),
      );
    } on GoogleSignInException catch (error, stackTrace) {
      final bool canceled =
          error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted ||
          error.code == GoogleSignInExceptionCode.uiUnavailable;
      unawaited(
        recordSafeError(
          area: 'drive',
          code: canceled ? 'auth_cancelled' : 'drive_error',
          stackTrace: stackTrace,
        ),
      );
      if (!mounted || !pageContext.mounted) return;
      setState(() {
        _googleDriveSessionStatus = canceled
            ? _googleAccount == null
                  ? _googleDriveWasConnected
                        ? GoogleDriveSessionStatus.temporaryError
                        : GoogleDriveSessionStatus.accountDisconnected
                  : GoogleDriveSessionStatus.driveAuthorizationRequired
            : GoogleDriveSessionStatus.temporaryError;
      });
      if (_googleAccount == null && !_googleDriveWasConnected) {
        debugPrint('DRIVE_AUTH ui:disconnected');
      } else if (_googleAccount == null) {
        debugPrint('DRIVE_AUTH ui:temporary_error');
      } else {
        debugPrint('DRIVE_AUTH scopes:required');
        debugPrint('DRIVE_AUTH ui:authorization_required');
      }
      if (canceled) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se conectó Google Drive.')),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(canceled ? 'Conexión cancelada.' : errorMessage),
        ),
      );
    } catch (_, stackTrace) {
      unawaited(
        recordSafeError(
          area: 'drive',
          code: 'drive_error',
          stackTrace: stackTrace,
        ),
      );
      if (!mounted || !pageContext.mounted) return;
      setState(() {
        _googleDriveSessionStatus = GoogleDriveSessionStatus.temporaryError;
      });
      debugPrint('DRIVE_AUTH restore:error_preserving_local_state');
      debugPrint('DRIVE_AUTH ui:temporary_error');
      messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) setState(() => _isGoogleConnecting = false);
    }
  }

  commons.Media _googleDriveBackupMedia(List<int> bytes) => commons.Media(
    Stream<List<int>>.value(bytes),
    bytes.length,
    contentType: 'application/json',
  );

  Future<T> _withGoogleDriveApi<T>(
    BuildContext pageContext,
    Future<T> Function(drive.DriveApi api, GoogleSignInAccount account) action,
  ) async {
    if (!_canTouchGoogleFromCurrentContext('withGoogleDriveApi')) {
      throw StateError('Google Drive blocked outside user action');
    }
    GoogleSignInAccount? account = _googleAccount;
    if (account == null) {
      await _restoreGoogleDriveSession();
      account = _googleAccount;
    }
    if (account == null) {
      throw StateError('Google Drive no conectado');
    }
    await _ensureGoogleDriveAuthInitializedFromUserAction('drive_api');
    final GoogleSignInClientAuthorization? authorization = await account
        .authorizationClient
        .authorizationForScopes(_googleDriveScopes);
    if (authorization == null) {
      if (mounted) {
        setState(() {
          _googleDriveSessionStatus =
              GoogleDriveSessionStatus.driveAuthorizationRequired;
          _googleDriveAuthorizationKnown = false;
        });
      }
      debugPrint('DRIVE_AUTH scopes:required');
      debugPrint('DRIVE_AUTH ui:authorization_required');
      unawaited(_saveGoogleDriveAuthorizationKnown(false));
      throw StateError('Google Drive authorization required');
    }
    if (mounted) {
      setState(() {
        _googleDriveSessionStatus = GoogleDriveSessionStatus.driveAuthorized;
        _googleDriveAuthorizationKnown = true;
      });
    }
    debugPrint('DRIVE_AUTH scopes:authorized');
    unawaited(_saveGoogleDriveAuthorizationKnown(true));
    final client = authorization.authClient(scopes: _googleDriveScopes);
    try {
      return await action(drive.DriveApi(client), account);
    } finally {
      client.close();
    }
  }

  Future<drive.File?> _findGoogleDriveBackupFile(drive.DriveApi api) async {
    final drive.FileList files = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_googleDriveBackupFileName' and trashed = false",
      pageSize: 1,
      $fields: 'files(id,name,modifiedTime)',
    );
    final List<drive.File>? matches = files.files;
    return matches == null || matches.isEmpty ? null : matches.first;
  }

  Future<drive.File?> _loadGoogleDriveBackupFile(drive.DriveApi api) async {
    final String? fileId = _googleDriveBackupFileId;
    if (fileId != null && fileId.isNotEmpty) {
      try {
        return await api.files.get(fileId, $fields: 'id,name,modifiedTime')
            as drive.File;
      } catch (_) {}
    }
    return _findGoogleDriveBackupFile(api);
  }

  Future<drive.File> _uploadGoogleDriveBackup(
    drive.DriveApi api,
    List<int> bytes,
  ) async {
    final drive.File metadata = drive.File()
      ..name = _googleDriveBackupFileName
      ..mimeType = 'application/json';
    final drive.File? existing = await _findGoogleDriveBackupFile(api);
    if (existing?.id != null) {
      return api.files.update(
        metadata,
        existing!.id!,
        uploadMedia: _googleDriveBackupMedia(bytes),
        $fields: 'id,name,modifiedTime',
      );
    }
    metadata.parents = <String>['appDataFolder'];
    return api.files.create(
      metadata,
      uploadMedia: _googleDriveBackupMedia(bytes),
      $fields: 'id,name,modifiedTime',
    );
  }

  Future<void> _createGoogleDriveBackup(BuildContext pageContext) async {
    if (_isGoogleDriveBusy) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);

    setState(() => _isGoogleDriveCreating = true);
    try {
      await _withGoogleDriveApi(pageContext, (
        drive.DriveApi api,
        GoogleSignInAccount account,
      ) async {
        final List<int> bytes = utf8.encode(_buildBackupJson());
        final drive.File uploaded = await _uploadGoogleDriveBackup(api, bytes);
        if (!mounted || !pageContext.mounted) return;
        final DateTime updatedAt = uploaded.modifiedTime ?? DateTime.now();
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        if (!mounted || !pageContext.mounted) return;
        await prefs.setString(_googleDriveBackupFileIdKey, uploaded.id ?? '');
        if (!mounted || !pageContext.mounted) return;
        await prefs.setInt(
          _googleDriveBackupUpdatedAtKey,
          updatedAt.millisecondsSinceEpoch,
        );
        if (!mounted || !pageContext.mounted) return;
        await prefs.setString(_googleDriveBackupAccountEmailKey, account.email);
        if (!mounted || !pageContext.mounted) return;
        setState(() {
          _googleDriveBackupFileId = uploaded.id;
          _googleDriveBackupUpdatedAt = updatedAt;
          _googleDriveBackupAccountEmail = account.email;
        });
      });
      if (!mounted || !pageContext.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Copia creada en Google Drive.')),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'drive_backup_created',
          parameters: <String, Object>{
            'source': 'drive',
            'status': 'completed',
          },
        ),
      );
    } catch (error, stackTrace) {
      final String code = _driveOperationCode(error);
      unawaited(
        recordSafeError(area: 'drive', code: code, stackTrace: stackTrace),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'drive_backup_created',
          parameters: <String, Object>{
            'source': 'drive',
            'status': 'failed',
            'error_code': code,
          },
        ),
      );
      if (mounted && pageContext.mounted) {
        if (code == 'auth_required') {
          setState(
            () => _googleDriveSessionStatus =
                GoogleDriveSessionStatus.driveAuthorizationRequired,
          );
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              code == 'auth_required'
                  ? 'Reconecta Google Drive para crear copia.'
                  : 'No se pudo crear la copia en Google Drive. Tus datos locales no se modificaron.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleDriveCreating = false);
    }
  }

  Future<bool> _confirmGoogleDriveRestore(BuildContext pageContext) async {
    if (!pageContext.mounted) return false;
    return await showDialog<bool>(
          context: pageContext,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Restaurar desde Google Drive'),
            content: const Text(
              'Esto reemplazará tus datos financieros actuales con la copia guardada en Google Drive. Antes de restaurar, crea una copia de seguridad local.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  final NavigatorState? navigator = Navigator.maybeOf(
                    dialogContext,
                  );
                  if (dialogContext.mounted &&
                      navigator != null &&
                      navigator.canPop()) {
                    navigator.pop(false);
                  }
                },
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final NavigatorState? navigator = Navigator.maybeOf(
                    dialogContext,
                  );
                  if (dialogContext.mounted &&
                      navigator != null &&
                      navigator.canPop()) {
                    navigator.pop(true);
                  }
                },
                child: const Text('Restaurar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _saveGoogleDriveBackupMetadata(
    drive.File file,
    GoogleSignInAccount account,
  ) async {
    final DateTime updatedAt = file.modifiedTime ?? DateTime.now();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_googleDriveBackupFileIdKey, file.id ?? '');
    await prefs.setInt(
      _googleDriveBackupUpdatedAtKey,
      updatedAt.millisecondsSinceEpoch,
    );
    await prefs.setString(_googleDriveBackupAccountEmailKey, account.email);
    if (!mounted) return;
    setState(() {
      _googleDriveBackupFileId = file.id;
      _googleDriveBackupUpdatedAt = updatedAt;
      _googleDriveBackupAccountEmail = account.email;
    });
  }

  Future<void> _restoreGoogleDriveBackup(BuildContext pageContext) async {
    if (_isGoogleDriveBusy) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);

    setState(() => _isGoogleDriveRestoring = true);
    try {
      await _withGoogleDriveApi(pageContext, (
        drive.DriveApi api,
        GoogleSignInAccount account,
      ) async {
        final drive.File? file = await _loadGoogleDriveBackupFile(api);
        if (!mounted || !pageContext.mounted) return;
        if (file?.id == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No hay copia en Google Drive.')),
          );
          return;
        }
        if (!await _confirmGoogleDriveRestore(pageContext)) return;
        if (!mounted || !pageContext.mounted) return;
        final Object downloaded = await api.files.get(
          file!.id!,
          downloadOptions: commons.DownloadOptions.fullMedia,
        );
        if (!mounted || !pageContext.mounted) return;
        if (downloaded is! commons.Media) throw const FormatException();
        final List<int> bytes = <int>[];
        await for (final List<int> chunk in downloaded.stream) {
          bytes.addAll(chunk);
        }
        if (bytes.isEmpty) throw const FormatException();
        final _ImportResult result = await _applyBackupJson(utf8.decode(bytes));
        if (!mounted || !pageContext.mounted) return;
        await _saveGoogleDriveBackupMetadata(file, account);
        if (!mounted || !pageContext.mounted) return;
        _showImportResult(messenger, result, fileName: 'Google Drive');
        unawaited(
          _logSafeAnalyticsEvent(
            name: 'drive_backup_restored',
            parameters: <String, Object>{
              'source': 'drive',
              'status': 'completed',
            },
          ),
        );
      });
    } on FormatException catch (_, stackTrace) {
      unawaited(
        recordSafeError(
          area: 'drive',
          code: 'invalid_backup',
          stackTrace: stackTrace,
        ),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'drive_backup_restored',
          parameters: <String, Object>{
            'source': 'drive',
            'status': 'failed',
            'error_code': 'invalid_backup',
          },
        ),
      );
      if (mounted && pageContext.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('La copia de Google Drive no es válida.'),
          ),
        );
      }
    } catch (error, stackTrace) {
      final String code = _driveOperationCode(error);
      unawaited(
        recordSafeError(area: 'drive', code: code, stackTrace: stackTrace),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'drive_backup_restored',
          parameters: <String, Object>{
            'source': 'drive',
            'status': 'failed',
            'error_code': code,
          },
        ),
      );
      if (mounted && pageContext.mounted) {
        if (code == 'auth_required') {
          setState(
            () => _googleDriveSessionStatus =
                GoogleDriveSessionStatus.driveAuthorizationRequired,
          );
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              code == 'auth_required'
                  ? 'Reconecta Google Drive para restaurar la copia.'
                  : 'No se pudo restaurar la copia de Google Drive. Tus datos locales no se modificaron.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleDriveRestoring = false);
    }
  }

  Future<void> _disconnectGoogleDrive(BuildContext pageContext) async {
    if (_isGoogleDriveBusy) return;
    if (!_driveAuthUserInitiated) {
      debugPrint('DRIVE_AUTH blocked:interactive_flow_without_user_action');
      debugPrint(StackTrace.current.toString());
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);

    setState(() => _isGoogleConnecting = true);
    try {
      await _ensureGoogleDriveAuthInitializedFromUserAction('sign_out');
      _isGoogleDriveDisconnectingExplicitly = true;
      try {
        await _runDriveInteractiveCall<void>(
          'disconnect',
          () => GoogleSignIn.instance.disconnect(),
        );
      } catch (_) {
        await _runDriveInteractiveCall<void>(
          'signOut',
          () => GoogleSignIn.instance.signOut(),
        );
      }
    } catch (_) {
      // Local UI state is cleared even if the provider cannot be reached.
    } finally {
      if (mounted) {
        setState(() {
          _googleAccount = null;
          _googleDriveSessionEmail = null;
          _googleDriveSessionDisplayName = null;
          _googleDriveSessionConnectedAt = null;
          _googleDriveWasConnected = false;
          _googleDriveAuthorizationKnown = false;
          _googleDriveSessionStatus =
              GoogleDriveSessionStatus.accountDisconnected;
          _isGoogleConnecting = false;
        });
      }
      _isGoogleDriveDisconnectingExplicitly = false;
      unawaited(_clearGoogleDriveSessionMetadata());
      debugPrint('DRIVE_AUTH ui:disconnected');
      messenger.showSnackBar(
        const SnackBar(content: Text('Google Drive desconectado.')),
      );
    }
  }

  Future<void> _loadData() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final String? movementsRaw = prefs.getString(_movementsKey);
      if (movementsRaw != null && movementsRaw.trim().isNotEmpty) {
        try {
          final dynamic decoded = jsonDecode(movementsRaw);
          if (decoded is List) {
            var migratedMovementMetadata = false;
            final List<Movement> loadedMovements = <Movement>[];
            for (final dynamic raw in decoded) {
              final Map<String, dynamic> json = Map<String, dynamic>.from(
                raw as Map,
              );
              migratedMovementMetadata =
                  migratedMovementMetadata ||
                  _movementJsonNeedsSyncMetadata(json);
              loadedMovements.add(Movement.fromJson(json));
            }
            final String deviceId = await _localFirebaseDeviceId();
            migratedMovementMetadata =
                _normalizeMovementSyncMetadata(loadedMovements, deviceId) ||
                migratedMovementMetadata;
            _movements
              ..clear()
              ..addAll(loadedMovements);
            if (migratedMovementMetadata) {
              await prefs.setString(
                _movementsKey,
                jsonEncode(_movements.map((Movement m) => m.toJson()).toList()),
              );
            }
          }
        } catch (_) {}
      }

      final PriceCache priceCache = await _priceService.loadCachedPrices(prefs);
      _applyPriceCache(priceCache);
      _loadPriceModeState(prefs);

      final String? snapshotsRaw = prefs.getString(_snapshotsKey);
      if (snapshotsRaw != null && snapshotsRaw.trim().isNotEmpty) {
        try {
          final dynamic decoded = jsonDecode(snapshotsRaw);
          if (decoded is List) {
            _snapshots
              ..clear()
              ..addAll(
                decoded.map(
                  (dynamic e) => PortfolioSnapshot.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                ),
              );
            _snapshots.sort(
              (PortfolioSnapshot a, PortfolioSnapshot b) =>
                  b.createdAt.compareTo(a.createdAt),
            );
          }
        } catch (_) {}
      }

      _sellFeePercent =
          prefs.getDouble(_sellFeePercentKey) ??
          FinancialEngine.defaultExitFeePercent;
      final String? savedVisualMode = prefs.getString(_themeModeKey);
      if (savedVisualMode != null) {
        _visualMode = appVisualModeFromName(savedVisualMode);
      } else if (prefs.containsKey(_darkModeKey)) {
        _visualMode = (prefs.getBool(_darkModeKey) ?? false)
            ? AppVisualMode.dark
            : AppVisualMode.light;
      } else {
        _visualMode = AppVisualMode.system;
      }
      _themeStyle = appThemeStyleFromName(
        prefs.getString(_themeStyleKey) ?? prefs.getString(_accentColorKey),
      );
      _visiblePositions = visiblePositionsFromName(
        prefs.getString(_visiblePositionsKey),
      );
      _positionSortMode = positionSortModeFromName(
        prefs.getString(_positionSortKey),
      );
      _summaryViewMode = summaryViewModeFromName(
        prefs.getString(_summaryViewModeKey),
      );
      final SummaryChartType loadedSummaryChartType = summaryChartTypeFromName(
        prefs.getString(_summaryChartTypeKey),
      );
      _summaryChartType = loadedSummaryChartType == SummaryChartType.candles
          ? SummaryChartType.line
          : loadedSummaryChartType;
      _snapshotAutomationMode = snapshotAutomationModeFromName(
        prefs.getString(_snapshotModeKey),
      );
      _snapshotRetention = snapshotRetentionFromName(
        prefs.getString(_snapshotRetentionKey),
      );
      _refreshPricesOnOpen = prefs.getBool(_priceRefreshOnOpenKey) ?? true;
      _refreshPricesAfterMovement =
          prefs.getBool(_priceRefreshAfterMovementKey) ?? false;
      _priceRefreshForegroundMode = priceRefreshForegroundModeFromName(
        prefs.getString(_priceRefreshForegroundModeKey),
      );
      _googleDriveBackupFileId = prefs.getString(_googleDriveBackupFileIdKey);
      final int? driveBackupUpdatedAt = prefs.getInt(
        _googleDriveBackupUpdatedAtKey,
      );
      _googleDriveBackupUpdatedAt = driveBackupUpdatedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(driveBackupUpdatedAt);
      _googleDriveBackupAccountEmail = prefs.getString(
        _googleDriveBackupAccountEmailKey,
      );
      _googleDriveSessionEmail = prefs.getString(_googleDriveSessionEmailKey);
      _googleDriveSessionDisplayName = prefs.getString(
        _googleDriveSessionDisplayNameKey,
      );
      final int? driveSessionConnectedAt = prefs.getInt(
        _googleDriveSessionConnectedAtKey,
      );
      _googleDriveSessionConnectedAt = driveSessionConnectedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(driveSessionConnectedAt);
      _googleDriveWasConnected =
          prefs.getBool(_googleDriveSessionWasConnectedKey) ??
          (_googleDriveSessionEmail != null);
      _googleDriveAuthorizationKnown =
          prefs.getBool(_googleDriveAuthorizationKnownKey) ?? false;
      await _loadPriceAlertSettings(prefs);

      if (mounted) setState(() => _bootstrapped = true);

      await _captureAutomaticSnapshotIfNeeded(SnapshotTrigger.appOpen);

      if (_refreshPricesOnOpen) {
        await _refreshPricesIfNeeded(prefs);
      }
      if (mounted) _restartPriceRefreshTimer();
    } finally {
      if (mounted && !_bootstrapped) {
        setState(() => _bootstrapped = true);
      } else {
        _bootstrapped = true;
      }
    }
  }

  void _applyPriceCache(PriceCache cache) {
    for (final String coin in _coins) {
      _currentPrices[coin] = cache.prices[coin] ?? 0.0;
    }
    _pricesUpdatedAt = cache.updatedAt;
  }

  void _loadPriceModeState(SharedPreferences prefs) {
    _priceModes
      ..clear()
      ..addAll(_priceService.loadPriceModes(prefs));
    _manualPriceUpdatedAtMs
      ..clear()
      ..addAll(_priceService.loadManualPriceUpdatedAtMs(prefs));
  }

  String _priceModeFor(String coin) =>
      _priceModes[coin] == PriceService.manualMode
      ? PriceService.manualMode
      : PriceService.automaticMode;

  String _priceModeLabel(String coin) =>
      _priceModeFor(coin) == PriceService.manualMode ? 'Manual' : 'Automático';

  Future<void> _loadPriceAlertSettings(SharedPreferences prefs) async {
    final PriceAlertSettings settings = await _priceAlertService.loadSettings(
      prefs,
    );
    final bool notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    _priceAlertsEnabled = settings.enabled;
    _priceAlertThresholdPercent = settings.thresholdPercent;
    _priceAlertReferences = settings.referencePrices;
    _recoveryAlertsEnabled = settings.recoveryEnabled;
    _recoveryAlertThresholdPoints = settings.recoveryThresholdPoints;
    _recoveryAlertReferences = settings.recoveryReferencePnl;
    _notificationsAllowed = notificationsAllowed;
    _automaticLocalAlertsEnabled = settings.automaticAlertsEnabled;
    _automaticLocalAlertsIntervalMinutes = settings.automaticIntervalMinutes;
    await _priceAlertService.configureAutomaticAlerts(
      enabled: settings.automaticAlertsEnabled,
      intervalMinutes: settings.automaticIntervalMinutes,
    );
  }

  Future<void> _evaluatePriceAlerts(SharedPreferences prefs) async {
    final Map<String, CoinStats> stats = _computeStats();
    final List<String> activeCoins = _activeAlertCoins(stats).toList();
    final PriceAlertEvaluation evaluation = await _priceAlertService
        .evaluatePrices(
          prefs: prefs,
          currentPrices: _currentPrices,
          coins: activeCoins,
          recoveryPositions: _recoveryAlertPositions(stats),
        );
    final bool notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    if (!mounted) return;
    setState(() {
      _priceAlertsEnabled = evaluation.settings.enabled;
      _priceAlertThresholdPercent = evaluation.settings.thresholdPercent;
      _priceAlertReferences = evaluation.settings.referencePrices;
      _recoveryAlertsEnabled = evaluation.settings.recoveryEnabled;
      _recoveryAlertThresholdPoints =
          evaluation.settings.recoveryThresholdPoints;
      _recoveryAlertReferences = evaluation.settings.recoveryReferencePnl;
      _notificationsAllowed = notificationsAllowed;
      _automaticLocalAlertsEnabled = evaluation.settings.automaticAlertsEnabled;
      _automaticLocalAlertsIntervalMinutes =
          evaluation.settings.automaticIntervalMinutes;
    });
  }

  Map<String, RecoveryAlertPosition> _recoveryAlertPositions(
    Map<String, CoinStats> stats,
  ) {
    return <String, RecoveryAlertPosition>{
      for (final String coin in _coins)
        coin: RecoveryAlertPosition(
          quantity: stats[coin]?.quantity ?? 0.0,
          investmentNet: stats[coin]?.costBase ?? 0.0,
          currentPrice: stats[coin]?.currentPrice ?? 0.0,
          sellFeePercent: _sellFeePercent,
        ),
    };
  }

  Iterable<String> _activeAlertCoins(Map<String, CoinStats> stats) sync* {
    for (final String coin in _coins) {
      final CoinStats? stat = stats[coin];
      if (stat != null && stat.quantity > 0) yield coin;
    }
  }

  Future<void> _togglePriceAlerts(
    BuildContext pageContext,
    bool enabled,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    var notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    if (enabled && !notificationsAllowed) {
      notificationsAllowed = await _priceAlertService
          .requestNotificationPermission();
    }

    await _priceAlertService.setEnabled(prefs, enabled);
    await _loadPriceAlertSettings(prefs);
    if (mounted) setState(() {});

    if (enabled && !notificationsAllowed && pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Activa el permiso de notificaciones para recibir alertas.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleAutomaticLocalAlerts(
    BuildContext pageContext,
    bool enabled,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    var notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    if (enabled && !notificationsAllowed) {
      notificationsAllowed = await _priceAlertService
          .requestNotificationPermission();
    }

    await _priceAlertService.setAutomaticAlertsEnabled(prefs, enabled);
    await _priceAlertService.configureAutomaticAlerts(
      enabled: enabled,
      intervalMinutes: _automaticLocalAlertsIntervalMinutes,
    );
    if (enabled) await _priceAlertService.runAutomaticAlertCheckNow();
    await _loadPriceAlertSettings(prefs);
    if (mounted) setState(() {});

    if (enabled && !notificationsAllowed && pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Permiso denegado: las alertas internas siguen activas, pero Android no mostrará notificaciones automáticas.',
          ),
        ),
      );
    }
  }

  Future<void> _changeAutomaticLocalAlertInterval(int minutes) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _priceAlertService.setAutomaticAlertsIntervalMinutes(prefs, minutes);
    setState(() => _automaticLocalAlertsIntervalMinutes = minutes);
    await _priceAlertService.configureAutomaticAlerts(
      enabled: _automaticLocalAlertsEnabled,
      intervalMinutes: minutes,
    );
  }

  Future<void> _toggleRecoveryAlerts(
    BuildContext pageContext,
    bool enabled,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    var notificationsAllowed = await _priceAlertService
        .areNotificationsAllowed();

    if (enabled && !notificationsAllowed) {
      notificationsAllowed = await _priceAlertService
          .requestNotificationPermission();
    }

    await _priceAlertService.setRecoveryEnabled(prefs, enabled);
    await _loadPriceAlertSettings(prefs);
    if (mounted) setState(() {});

    if (enabled && !notificationsAllowed && pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Activa el permiso de notificaciones para recibir alertas.',
          ),
        ),
      );
    }
  }

  Future<void> _showRecoveryAlertThresholdDialog(
    BuildContext pageContext,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: compact(_recoveryAlertThresholdPoints),
    );

    await showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        actionsAlignment: MainAxisAlignment.end,
        title: const Text('Umbral de recuperación'),
        content: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: math.min(
                MediaQuery.of(dialogContext).viewInsets.bottom,
                24.0,
              ),
            ),
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Puntos porcentuales',
                helperText: 'Predeterminado: 2.0',
                prefixIcon: Icon(Icons.trending_up_outlined),
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final double? value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0 || value > 100) return;

              final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
              await _priceAlertService.setRecoveryThresholdPoints(prefs, value);
              await _loadPriceAlertSettings(prefs);
              if (mounted) setState(() {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPriceAlertThresholdDialog(BuildContext pageContext) async {
    final TextEditingController controller = TextEditingController(
      text: compact(_priceAlertThresholdPercent),
    );

    await showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        actionsAlignment: MainAxisAlignment.end,
        title: const Text('Umbral'),
        content: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: math.min(
                MediaQuery.of(dialogContext).viewInsets.bottom,
                24.0,
              ),
            ),
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Umbral %',
                helperText: 'Predeterminado: 2.0',
                prefixIcon: Icon(Icons.percent_outlined),
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final double? value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0 || value > 100) return;

              final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
              await _priceAlertService.setThresholdPercent(prefs, value);
              await _loadPriceAlertSettings(prefs);
              if (mounted) setState(() {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPriceAlertReferences(BuildContext pageContext) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, CoinStats> stats = _computeStats();
    final List<String> activeCoins = _activeAlertCoins(stats).toList();
    final PriceAlertSettings settings = await _priceAlertService
        .resetReferences(prefs, _currentPrices, activeCoins);

    if (!mounted) return;
    setState(() {
      _priceAlertReferences = settings.referencePrices;
      _priceAlertThresholdPercent = settings.thresholdPercent;
      _priceAlertsEnabled = settings.enabled;
    });

    if (pageContext.mounted) {
      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(const SnackBar(content: Text('Precios base reiniciados')));
    }
  }

  Future<void> _resetRecoveryAlertReferences(BuildContext pageContext) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, CoinStats> stats = _computeStats();
    final List<String> activeCoins = _activeAlertCoins(stats).toList();
    final PriceAlertSettings settings = await _priceAlertService
        .resetRecoveryReferences(
          prefs,
          _recoveryAlertPositions(stats),
          activeCoins,
        );

    if (!mounted) return;
    setState(() {
      _recoveryAlertReferences = settings.recoveryReferencePnl;
      _recoveryAlertThresholdPoints = settings.recoveryThresholdPoints;
      _recoveryAlertsEnabled = settings.recoveryEnabled;
    });

    if (pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('Base de recuperación reiniciada')),
      );
    }
  }

  Future<void> _refreshPricesIfNeeded(SharedPreferences prefs) async {
    final PriceCache priceCache = await _priceService.refreshIfStale(prefs);
    _applyPriceCache(priceCache);
    await _evaluatePriceAlerts(prefs);
    if (!mounted) return;

    setState(() {});
  }

  Future<void> _refreshPricesNow(BuildContext pageContext) async {
    if (_isRefreshingPrices) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    setState(() => _isRefreshingPrices = true);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PriceCache priceCache = await _priceService.fetchAndCachePrices(
        prefs,
      );
      if (!mounted) return;

      _applyPriceCache(priceCache);
      await _evaluatePriceAlerts(prefs);
      setState(() {});
      await _captureAutomaticSnapshotIfNeeded(SnapshotTrigger.priceUpdate);
      messenger.showSnackBar(
        const SnackBar(content: Text('Precios actualizados')),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'price_refresh',
          parameters: <String, Object>{'status': 'completed'},
        ),
      );
    } catch (_, stackTrace) {
      unawaited(
        recordSafeError(
          area: 'price_refresh',
          code: 'price_refresh_error',
          stackTrace: stackTrace,
        ),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'price_refresh',
          parameters: <String, Object>{
            'status': 'failed',
            'error_code': 'price_refresh_error',
          },
        ),
      );
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudieron actualizar los precios. Revisa tu conexión e inténtalo de nuevo.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPrices = false);
      }
    }
  }

  Future<void> _refreshPricesSilently() async {
    if (_isRefreshingPrices || !mounted) return;

    setState(() => _isRefreshingPrices = true);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PriceCache priceCache = await _priceService.fetchAndCachePrices(
        prefs,
      );
      if (!mounted) return;

      _applyPriceCache(priceCache);
      setState(() {});
    } catch (_) {
      // Foreground auto refresh is intentionally quiet.
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPrices = false);
      }
    }
  }

  bool get _isForeground {
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _restartPriceRefreshTimer() {
    _cancelPriceRefreshTimer();
    final Duration? interval = _priceRefreshForegroundMode.interval;
    if (interval == null || !_isForeground) return;

    _priceRefreshTimer = Timer.periodic(interval, (_) {
      if (!_isForeground || _isRefreshingPrices) return;
      unawaited(_refreshPricesSilently());
    });
  }

  void _cancelPriceRefreshTimer() {
    _priceRefreshTimer?.cancel();
    _priceRefreshTimer = null;
  }

  Future<void> _saveData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _movementsKey,
      jsonEncode(_movements.map((Movement m) => m.toJson()).toList()),
    );

    await prefs.setString(_pricesKey, jsonEncode(_currentPrices));
    await _priceService.savePriceModes(prefs, _priceModes);
    await _priceService.saveManualPriceUpdatedAtMs(
      prefs,
      _manualPriceUpdatedAtMs,
    );
    await prefs.setDouble(_sellFeePercentKey, _sellFeePercent);
    await prefs.setString(_themeModeKey, _visualMode.name);
    await prefs.setString(_themeStyleKey, _themeStyle.name);
    await prefs.setString(_accentColorKey, _themeStyle.name);
    await prefs.setString(_visiblePositionsKey, _visiblePositions.name);
    await prefs.setString(_positionSortKey, _positionSortMode.name);
    await prefs.setString(_snapshotModeKey, _snapshotAutomationMode.name);
    await prefs.setString(_snapshotRetentionKey, _snapshotRetention.name);
    await prefs.setBool(_priceRefreshOnOpenKey, _refreshPricesOnOpen);
    await prefs.setBool(
      _priceRefreshAfterMovementKey,
      _refreshPricesAfterMovement,
    );
    await prefs.setString(
      _priceRefreshForegroundModeKey,
      _priceRefreshForegroundMode.name,
    );
    await prefs.setBool(_darkModeKey, _visualMode == AppVisualMode.dark);
  }

  Future<void> _saveSnapshots() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _snapshotsKey,
      jsonEncode(_snapshots.map((PortfolioSnapshot s) => s.toJson()).toList()),
    );
    await _saveData();
  }

  PortfolioSnapshot _buildCurrentSnapshot() {
    final Map<String, CoinStats> stats = _computeStats();
    final PortfolioTotals totals = _totals(stats);

    return PortfolioSnapshot(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      totalCostBase: totals.costBase,
      totalCurrentValue: totals.currentValue,
      totalUnrealizedPL: totals.unrealizedPL,
      totalRealizedPL: totals.realizedPL,
      movementCount: _movements.length,
      coins: _coins
          .map((String coin) => CoinSnapshot.fromStats(stats[coin]!))
          .toList(),
    );
  }

  void _insertSnapshot(PortfolioSnapshot snapshot) {
    _snapshots.insert(0, snapshot);
    _snapshots.sort(
      (PortfolioSnapshot a, PortfolioSnapshot b) =>
          b.createdAt.compareTo(a.createdAt),
    );
    _enforceSnapshotRetention();
  }

  void _enforceSnapshotRetention() {
    final int? limit = _snapshotRetention.limit;
    if (limit != null && _snapshots.length > limit) {
      _snapshots.removeRange(limit, _snapshots.length);
    }
  }

  Future<void> _captureAutomaticSnapshotIfNeeded(
    SnapshotTrigger trigger,
  ) async {
    if (!_snapshotAutomationMode.shouldCapture(trigger, _snapshots)) return;
    if (!mounted) return;
    setState(() => _insertSnapshot(_buildCurrentSnapshot()));
    await _saveSnapshots();
  }

  Future<void> _saveMovementAndMaybeSnapshot(SnapshotTrigger trigger) async {
    await _captureAutomaticSnapshotIfNeeded(trigger);
    await _saveData();
  }

  Map<String, CoinStats> _computeStats() {
    return FinancialEngine.computeStats(
      coins: _coins,
      movements: _movements,
      currentPrices: _currentPrices,
    );
  }

  CoinAudit _auditCoin(String coin) {
    double buys = 0.0;
    double sells = 0.0;
    double transferIns = 0.0;
    double transferOuts = 0.0;
    double fees = 0.0;

    for (final Movement movement in _movements.where(
      (Movement m) => m.coin == coin,
    )) {
      final double total = movement.quantity * movement.unitPrice;
      fees += movement.fee;

      switch (movement.type) {
        case MovementType.buy:
          buys += total + movement.fee;
          break;
        case MovementType.sell:
          sells += total - movement.fee;
          break;
        case MovementType.transferIn:
          transferIns += total + movement.fee;
          break;
        case MovementType.transferOut:
          transferOuts += total + movement.fee;
          break;
      }
    }

    return CoinAudit(
      buys: buys,
      sells: sells,
      transferIns: transferIns,
      transferOuts: transferOuts,
      fees: fees,
    );
  }

  PortfolioTotals _totals(Map<String, CoinStats> stats) {
    return FinancialEngine.totals(stats);
  }

  bool _wouldCreateInvalidPosition(Movement candidate, {int? replaceIndex}) {
    return FinancialEngine.wouldCreateInvalidPosition(
      coins: _coins,
      movements: _movements,
      candidate: candidate,
      replaceIndex: replaceIndex,
    );
  }

  bool _wouldCreateDuplicateMovement(Movement candidate, {int? replaceIndex}) {
    return FinancialEngine.wouldCreateDuplicateMovement(
      movements: _movements,
      candidate: candidate,
      replaceIndex: replaceIndex,
    );
  }

  List<String> _financialDiagnostics() {
    return FinancialEngine.diagnostics(
      coins: _coins,
      movements: _movements,
      snapshots: _snapshots,
      currentPrices: _currentPrices,
    );
  }

  void _changeVisualMode(AppVisualMode value) {
    setState(() => _visualMode = value);
    _saveData();
  }

  void _changeThemeStyle(AppThemeStyle value) {
    setState(() => _themeStyle = value);
    _saveData();
  }

  void _changeVisiblePositions(VisiblePositions value) {
    setState(() => _visiblePositions = value);
    _saveData();
  }

  void _changePositionSortMode(PositionSortMode value) {
    setState(() => _positionSortMode = value);
    _saveData();
  }

  void _changeSummaryViewMode(SummaryViewMode value) {
    if (_summaryViewMode == value) return;
    setState(() => _summaryViewMode = value);
    unawaited(_saveSummaryVisualPreference(_summaryViewModeKey, value.name));
  }

  void _changeSummaryChartType(SummaryChartType value) {
    if (_summaryChartType == value) return;
    setState(() => _summaryChartType = value);
    unawaited(_saveSummaryVisualPreference(_summaryChartTypeKey, value.name));
  }

  Future<void> _saveSummaryVisualPreference(String key, String value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  void _changeSnapshotAutomationMode(SnapshotAutomationMode value) {
    setState(() => _snapshotAutomationMode = value);
    _saveData();
  }

  void _changeSnapshotRetention(SnapshotRetention value) {
    setState(() => _snapshotRetention = value);
    _enforceSnapshotRetention();
    _saveSnapshots();
    _saveData();
  }

  void _changeRefreshPricesOnOpen(bool value) {
    setState(() => _refreshPricesOnOpen = value);
    _saveData();
  }

  void _changeRefreshPricesAfterMovement(bool value) {
    setState(() => _refreshPricesAfterMovement = value);
    _saveData();
  }

  void _changePriceRefreshForegroundMode(PriceRefreshForegroundMode value) {
    setState(() => _priceRefreshForegroundMode = value);
    _saveData();
    _restartPriceRefreshTimer();
  }

  void _openSimulationMode(SimulationMode mode) {
    setState(() {
      _requestedSimulationMode = mode;
      _simulationOpenNonce++;
    });
    _goToMainTab(0);
  }

  Future<void> _showSellFeeDialog(BuildContext pageContext) async {
    final TextEditingController controller = TextEditingController(
      text: compact(_sellFeePercent),
    );

    await showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Comisión de salida'),
        content: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: math.min(
                MediaQuery.of(dialogContext).viewInsets.bottom,
                24.0,
              ),
            ),
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Porcentaje',
                helperText: 'Ejemplo: 1.5',
                prefixIcon: Icon(Icons.percent_outlined),
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final double? value = double.tryParse(controller.text.trim());
              if (value == null || value < 0 || value >= 100) return;

              setState(() => _sellFeePercent = value);
              _saveData();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showEditPriceDialog(BuildContext pageContext, String coin) {
    final TextEditingController controller = TextEditingController(
      text: compact(_currentPrices[coin] ?? 0.0),
    );
    final bool isManual = _priceModes[coin] == PriceService.manualMode;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);

    showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Precio actual de $coin'),
        content: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: math.min(
                MediaQuery.of(dialogContext).viewInsets.bottom,
                24.0,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Precio MXN',
                    prefixIcon: Icon(Icons.attach_money_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Al guardar, esta moneda usará precio manual hasta que vuelvas a automático.',
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          if (isManual)
            TextButton(
              onPressed: () async {
                final SharedPreferences prefs =
                    await SharedPreferences.getInstance();
                _priceModes[coin] = PriceService.automaticMode;
                _manualPriceUpdatedAtMs.remove(coin);
                await _priceService.savePriceModes(prefs, _priceModes);
                await _priceService.saveManualPriceUpdatedAtMs(
                  prefs,
                  _manualPriceUpdatedAtMs,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (mounted) setState(() {});
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      '$coin volverá a actualizarse con CoinGecko en el próximo refresh.',
                    ),
                  ),
                );
              },
              child: const Text('Volver a automático'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final double? value = double.tryParse(controller.text.trim());
              if (value == null || value < 0) return;

              final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
              final int updatedAtMs = DateTime.now().millisecondsSinceEpoch;
              _currentPrices[coin] = value;
              _priceModes[coin] = PriceService.manualMode;
              _manualPriceUpdatedAtMs[coin] = updatedAtMs;
              final PriceCache priceCache = await _priceService
                  .saveManualPrices(prefs, _currentPrices);
              await _priceService.savePriceModes(prefs, _priceModes);
              await _priceService.saveManualPriceUpdatedAtMs(
                prefs,
                _manualPriceUpdatedAtMs,
              );
              if (!dialogContext.mounted) return;
              await _evaluatePriceAlerts(prefs);
              if (mounted) {
                setState(() => _applyPriceCache(priceCache));
              }
              Navigator.of(dialogContext).pop();
              messenger.showSnackBar(
                SnackBar(content: Text('Precio manual guardado para $coin.')),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddMovementSheet(
    BuildContext pageContext, {
    Movement? existing,
    int? index,
    _OcrMovementCandidate? ocrCandidate,
  }) {
    final List<String> ocrWarnings = <String>[
      if (existing == null && ocrCandidate != null) ...ocrCandidate.warnings,
    ];
    final String? ocrCoin = ocrCandidate?.coin;
    if (existing == null && ocrCoin != null && !_coins.contains(ocrCoin)) {
      ocrWarnings.add('Moneda no soportada; selecciona la moneda correcta.');
    }
    final bool useOcr = existing == null && ocrCandidate != null;
    unawaited(
      _logSafeAnalyticsEvent(
        name: 'movement_form_opened',
        parameters: <String, Object>{'source': useOcr ? 'ocr' : 'manual'},
      ),
    );
    MovementType selectedType =
        existing?.type ?? ocrCandidate?.type ?? MovementType.buy;
    String selectedCoin =
        existing?.coin ??
        (ocrCoin != null && _coins.contains(ocrCoin) ? ocrCoin : _coins.first);
    DateTime selectedDate =
        existing?.date ?? ocrCandidate?.date ?? DateTime.now();
    final TextEditingController qtyController = TextEditingController(
      text: existing != null
          ? compact(existing.quantity)
          : ocrCandidate?.quantity == null
          ? ''
          : compact(ocrCandidate!.quantity!),
    );
    final TextEditingController priceController = TextEditingController(
      text: existing != null
          ? compact(existing.unitPrice)
          : ocrCandidate?.unitPrice == null
          ? ''
          : compact(ocrCandidate!.unitPrice!),
    );
    final TextEditingController feeController = TextEditingController(
      text: existing != null
          ? compact(existing.fee)
          : compact(ocrCandidate?.fee ?? 0),
    );
    final TextEditingController sourceController = TextEditingController(
      text: existing?.source ?? ocrCandidate?.source ?? '',
    );
    final TextEditingController walletController = TextEditingController(
      text: existing?.wallet ?? '',
    );
    final TextEditingController networkController = TextEditingController(
      text: existing?.network ?? '',
    );
    final TextEditingController noteController = TextEditingController(
      text: existing?.note ?? ocrCandidate?.note ?? '',
    );

    return showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SheetHeader(
                      title: useOcr
                          ? 'Revisar movimiento OCR'
                          : existing == null
                          ? 'Nuevo movimiento'
                          : 'Editar movimiento',
                      onClose: () => Navigator.of(sheetContext).pop(),
                    ),
                    const SizedBox(height: 12),
                    if (ocrWarnings.isNotEmpty) ...<Widget>[
                      Text(
                        'Revisa antes de guardar',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      ...ocrWarnings.map(
                        (String warning) => Text('• $warning'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<MovementType>(
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        prefixIcon: Icon(Icons.swap_vert_rounded),
                      ),
                      items: MovementType.values
                          .map(
                            (MovementType type) =>
                                DropdownMenuItem<MovementType>(
                                  value: type,
                                  child: Text(type.label),
                                ),
                          )
                          .toList(),
                      onChanged: (MovementType? value) {
                        if (value != null) {
                          setModalState(() => selectedType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCoin,
                      decoration: const InputDecoration(
                        labelText: 'Moneda',
                        prefixIcon: Icon(Icons.currency_bitcoin),
                      ),
                      items: _coins
                          .map(
                            (String coin) => DropdownMenuItem<String>(
                              value: coin,
                              child: Text(coin),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) {
                        if (value != null) {
                          setModalState(() => selectedCoin = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () async {
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate.isAfter(DateTime.now())
                                  ? DateTime.now()
                                  : selectedDate,
                              firstDate: DateTime(2010),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setModalState(
                                () => selectedDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                  selectedDate.hour,
                                  selectedDate.minute,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text('Fecha: ${shortDate(selectedDate)}'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final TimeOfDay? picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(selectedDate),
                            );
                            if (picked != null) {
                              setModalState(
                                () => selectedDate = DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                  picked.hour,
                                  picked.minute,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text('Hora: ${timeLabel(selectedDate)}'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qtyController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad cripto',
                        prefixIcon: Icon(Icons.token_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Precio unitario MXN',
                        prefixIcon: Icon(Icons.attach_money_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: feeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Comisión MXN',
                        prefixIcon: Icon(Icons.receipt_long_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sourceController,
                      decoration: const InputDecoration(
                        labelText: 'Plataforma',
                        prefixIcon: Icon(Icons.account_balance_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: walletController,
                      decoration: InputDecoration(
                        labelText:
                            useOcr && selectedType == MovementType.transferIn
                            ? 'Procedencia'
                            : useOcr && selectedType == MovementType.transferOut
                            ? 'Destino'
                            : 'Cartera',
                        helperText:
                            useOcr &&
                                (selectedType == MovementType.transferIn ||
                                    selectedType == MovementType.transferOut)
                            ? 'Ej.: Bitso, MetaMask, Binance, Coinbase u otra'
                            : null,
                        prefixIcon: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: networkController,
                      decoration: const InputDecoration(
                        labelText: 'Red',
                        prefixIcon: Icon(Icons.hub_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Nota',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final double? quantity = double.tryParse(
                            qtyController.text.trim(),
                          );
                          final double? unitPrice = double.tryParse(
                            priceController.text.trim(),
                          );
                          final double fee =
                              double.tryParse(feeController.text.trim()) ?? 0.0;

                          if (quantity == null || quantity <= 0) {
                            _snack(pageContext, 'Pon una cantidad válida');
                            return;
                          }

                          if (unitPrice == null || unitPrice <= 0) {
                            _snack(pageContext, 'Pon un precio mayor a cero');
                            return;
                          }

                          if (quantity * unitPrice <= 0) {
                            _snack(
                              pageContext,
                              'El total MXN debe ser mayor a cero',
                            );
                            return;
                          }

                          if (selectedDate.isAfter(
                            DateTime.now().add(const Duration(minutes: 1)),
                          )) {
                            _snack(
                              pageContext,
                              'La fecha no puede estar en el futuro',
                            );
                            return;
                          }

                          if (fee < 0) {
                            _snack(
                              pageContext,
                              'La comisión no puede ser negativa',
                            );
                            return;
                          }

                          final Movement movement =
                              await _movementWithCurrentSyncMetadata(
                                Movement(
                                  type: selectedType,
                                  coin: selectedCoin,
                                  date: selectedDate,
                                  quantity: quantity,
                                  unitPrice: unitPrice,
                                  fee: fee,
                                  source: sourceController.text.trim(),
                                  wallet: walletController.text.trim(),
                                  network: networkController.text.trim(),
                                  note: noteController.text.trim(),
                                ),
                                existing: existing,
                              );

                          if (_wouldCreateInvalidPosition(
                            movement,
                            replaceIndex: existing == null ? null : index,
                          )) {
                            _snack(
                              pageContext,
                              'Ese movimiento dejaría la posición en negativo',
                            );
                            return;
                          }

                          if (_wouldCreateDuplicateMovement(
                            movement,
                            replaceIndex: existing == null ? null : index,
                          )) {
                            final bool? continueAnyway = await showDialog<bool>(
                              context: sheetContext,
                              builder: (BuildContext dialogContext) => AlertDialog(
                                title: const Text('Posible duplicado'),
                                content: const Text(
                                  'Ya existe un movimiento idéntico. ¿Quieres guardarlo de todos modos?',
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('Revisar'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Guardar'),
                                  ),
                                ],
                              ),
                            );
                            if (continueAnyway != true) return;
                          }

                          setState(() {
                            if (existing != null &&
                                index != null &&
                                index >= 0 &&
                                index < _movements.length) {
                              _movements[index] = movement;
                            } else {
                              _movements.add(movement);
                            }
                          });

                          final Future<void> saveFuture =
                              _saveMovementAndMaybeSnapshot(
                                SnapshotTrigger.movementChange,
                              );
                          unawaited(
                            _refreshPricesAfterMovement
                                ? saveFuture.then(
                                    (_) => _refreshPricesSilently(),
                                  )
                                : saveFuture,
                          );
                          unawaited(
                            _logSafeAnalyticsEvent(
                              name: 'movement_saved',
                              parameters: <String, Object>{
                                'source': useOcr ? 'ocr' : 'manual',
                              },
                            ),
                          );
                          Navigator.of(sheetContext).pop();
                        },
                        icon: Icon(
                          existing == null ? Icons.add : Icons.save_outlined,
                        ),
                        label: Text(
                          existing == null
                              ? 'Guardar movimiento'
                              : 'Guardar cambios',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCoinDetails(BuildContext pageContext, CoinStats stats) {
    final CoinAudit audit = _auditCoin(stats.coin);

    showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (BuildContext context, ScrollController controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: <Widget>[
            SheetHeader(
              title: 'Detalles de ${stats.coin}',
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
            const SizedBox(height: 12),
            CardPanel(
              title: 'Resumen',
              subtitle: 'Lectura compacta de posición.',
              child: Column(
                children: <Widget>[
                  _SummaryDetailLine('Cantidad', crypto(stats.quantity)),
                  _SummaryDetailLine('Invertido', _coinsMoney(stats.costBase)),
                  _SummaryDetailLine(
                    'Valor de cartera',
                    _coinsMoney(stats.currentValue),
                    emphasized: true,
                  ),
                  _SummaryDetailLine(
                    'P&L no realizado',
                    _coinsMoney(stats.unrealizedPL),
                    valueColor: pnlColor(stats.unrealizedPL),
                    emphasized: true,
                  ),
                  _SummaryDetailLine(
                    'Precio recuperación',
                    _coinsMoney(stats.netBreakEvenPrice(_sellFeePercent)),
                  ),
                ],
              ),
            ),
            CardPanel(
              title: 'Auditoría',
              subtitle: 'Desglose de movimientos.',
              child: Column(
                children: <Widget>[
                  _SummaryDetailLine('Compras', _coinsMoney(audit.buys)),
                  _SummaryDetailLine('Ventas', _coinsMoney(audit.sells)),
                  _SummaryDetailLine(
                    'Entradas',
                    _coinsMoney(audit.transferIns),
                  ),
                  _SummaryDetailLine(
                    'Salidas',
                    _coinsMoney(audit.transferOuts),
                  ),
                  _SummaryDetailLine('Comisiones', _coinsMoney(audit.fees)),
                  _SummaryDetailLine('Promedio', _coinsMoney(stats.avgPrice)),
                  _SummaryDetailLine(
                    'P&L realizado',
                    _coinsMoney(stats.realizedPL),
                    valueColor: pnlColor(stats.realizedPL),
                  ),
                ],
              ),
            ),
            CardPanel(
              title: 'Fórmulas claras',
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Promedio = invertido actual / cantidad actual'),
                  SizedBox(height: 6),
                  Text(
                    'P&L no realizado = valor de cartera - invertido actual',
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Precio recuperación = promedio / (1 - comisión de salida)',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSnapshot(BuildContext pageContext) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    final PortfolioSnapshot snapshot = _buildCurrentSnapshot();

    setState(() => _insertSnapshot(snapshot));

    await _saveSnapshots();

    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Instantánea guardada')),
      );
    }
  }

  void _showSnapshots(BuildContext pageContext) {
    showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.96,
        builder: (BuildContext context, ScrollController controller) =>
            StatefulBuilder(
              builder:
                  (
                    BuildContext context,
                    void Function(void Function()) setModalState,
                  ) {
                    return ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[
                        SheetHeader(
                          title: 'Instantáneas',
                          onClose: () => Navigator.of(sheetContext).pop(),
                        ),
                        const SizedBox(height: 12),
                        if (_snapshots.isEmpty)
                          const EmptyState(
                            icon: Icons.photo_library_outlined,
                            title: 'Sin instantáneas',
                            subtitle:
                                'Guarda una instantánea de cartera desde '
                                'Más → Instantáneas.',
                          )
                        else ...<Widget>[
                          SnapshotTrendPanel(snapshots: _snapshots),
                          ..._snapshots.map(
                            (PortfolioSnapshot snapshot) => CardPanel(
                              title: longDate(snapshot.createdAt),
                              trailing: IconButton(
                                tooltip: 'Borrar instantánea',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  setState(
                                    () => _snapshots.removeWhere(
                                      (PortfolioSnapshot s) =>
                                          s.id == snapshot.id,
                                    ),
                                  );
                                  await _saveSnapshots();
                                  setModalState(() {});
                                },
                              ),
                              child: Column(
                                children: <Widget>[
                                  InfoLine(
                                    'Fecha',
                                    longDate(snapshot.createdAt),
                                  ),
                                  InfoLine(
                                    'Valor de cartera',
                                    money(snapshot.totalCurrentValue),
                                  ),
                                  InfoLine(
                                    'P&L no realizado',
                                    money(snapshot.totalUnrealizedPL),
                                    valueColor: pnlColor(
                                      snapshot.totalUnrealizedPL,
                                    ),
                                    emphasized: true,
                                  ),
                                  InfoLine(
                                    'P&L realizado',
                                    money(snapshot.totalRealizedPL),
                                    valueColor: pnlColor(
                                      snapshot.totalRealizedPL,
                                    ),
                                  ),
                                  InfoLine(
                                    'Inversión total',
                                    money(snapshot.totalCostBase),
                                  ),
                                  InfoLine(
                                    'Moneda dominante',
                                    snapshot.dominantCoinLabel,
                                  ),
                                  InfoLine(
                                    'Movimientos',
                                    snapshot.movementCount.toString(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
            ),
      ),
    );
  }

  String _buildBackupJson() {
    final Map<String, dynamic> backup = <String, dynamic>{
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': <String, dynamic>{
        'sellFeePercent': _sellFeePercent,
        'priceModes': <String, String>{
          for (final String coin in _coins) coin: _priceModeFor(coin),
        },
        'manualPricesUpdatedAtMs': <String, int>{
          for (final String coin in _coins)
            if (_manualPriceUpdatedAtMs.containsKey(coin))
              coin: _manualPriceUpdatedAtMs[coin]!,
        },
      },
      'currentPrices': _currentPrices,
      'movements': _movements.map((Movement m) => m.toJson()).toList(),
      'snapshots': _snapshots.map((PortfolioSnapshot s) => s.toJson()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  String _buildMovementsCsv() {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'fecha',
        'tipo',
        'tipo_raw',
        'cripto',
        'cantidad',
        'precio_unitario_mxn',
        'comision_mxn',
        'total_bruto_mxn',
        'plataforma',
        'cartera',
        'red',
        'nota',
      ],
      ..._movements.map((Movement m) {
        return <Object?>[
          m.date.toIso8601String(),
          m.type.label,
          m.type.name,
          m.coin,
          fixed(m.quantity, 8),
          fixed(m.unitPrice, 2),
          fixed(m.fee, 2),
          fixed(m.quantity * m.unitPrice, 2),
          m.source,
          m.wallet,
          m.network,
          m.note,
        ];
      }),
    ];

    return rows
        .map((List<Object?> row) => row.map(csvEscape).join(','))
        .join('\n');
  }

  String _buildSummaryCsv() {
    final Map<String, CoinStats> stats = _computeStats();

    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'cripto',
        'cantidad_actual',
        'cantidad_acumulada',
        'total_adquirido_historico_mxn',
        'costo_base_actual_mxn',
        'costo_promedio_mxn',
        'precio_actual_mxn',
        'price_status',
        'price_mode',
        'valor_actual_mxn',
        'pnl_no_realizado_bruto_mxn',
        'pnl_realizado_mxn',
        'break_even_bruto_mxn',
        'break_even_con_comision_salida_mxn',
        'comisiones_pagadas_mxn',
      ],
      ..._coins.map((String coin) {
        final CoinStats s = stats[coin]!;
        return <Object?>[
          s.coin,
          fixed(s.quantity, 8),
          fixed(s.quantity, 8),
          fixed(s.totalInvested, 2),
          fixed(s.costBase, 2),
          fixed(s.avgPrice, 2),
          fixed(s.currentPrice, 2),
          priceStatusCsv(s.currentPrice),
          _priceModeFor(s.coin),
          fixed(s.currentValue, 2),
          fixed(s.unrealizedPL, 2),
          fixed(s.realizedPL, 2),
          fixed(s.breakEvenReal, 2),
          fixed(s.breakEvenWithExitFee(_sellFeePercent), 2),
          fixed(s.feesPaid, 2),
        ];
      }),
    ];

    return rows
        .map((List<Object?> row) => row.map(csvEscape).join(','))
        .join('\n');
  }

  String _buildSnapshotsCsv() {
    final List<List<Object?>> rows = <List<Object?>>[
      <Object?>[
        'snapshot_id',
        'fecha',
        'costo_base_total_mxn',
        'valor_actual_total_mxn',
        'pnl_no_realizado_bruto_mxn',
        'pnl_realizado_mxn',
        'movimientos',
        'cripto',
        'cantidad',
        'costo_base_snapshot_mxn',
        'promedio_mxn',
        'valor_actual_mxn',
        'pnl_no_realizado_bruto_moneda_mxn',
        'pnl_realizado_moneda_mxn',
      ],
    ];

    for (final PortfolioSnapshot snapshot in _snapshots) {
      if (snapshot.coins.isEmpty) {
        rows.add(<Object?>[
          snapshot.id,
          snapshot.createdAt.toIso8601String(),
          fixed(snapshot.totalCostBase, 2),
          fixed(snapshot.totalCurrentValue, 2),
          fixed(snapshot.totalUnrealizedPL, 2),
          fixed(snapshot.totalRealizedPL, 2),
          snapshot.movementCount,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]);
      } else {
        for (final CoinSnapshot coin in snapshot.coins) {
          rows.add(<Object?>[
            snapshot.id,
            snapshot.createdAt.toIso8601String(),
            fixed(snapshot.totalCostBase, 2),
            fixed(snapshot.totalCurrentValue, 2),
            fixed(snapshot.totalUnrealizedPL, 2),
            fixed(snapshot.totalRealizedPL, 2),
            snapshot.movementCount,
            coin.coin,
            fixed(coin.quantity, 8),
            fixed(coin.costBase, 2),
            fixed(coin.avgPrice, 2),
            fixed(coin.currentValue, 2),
            fixed(coin.unrealizedPL, 2),
            fixed(coin.realizedPL, 2),
          ]);
        }
      }
    }

    return rows
        .map((List<Object?> row) => row.map(csvEscape).join(','))
        .join('\n');
  }

  String _buildMovementsJson() {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'movements': _movements.map((Movement m) => m.toJson()).toList(),
    });
  }

  String _buildSnapshotsJson() {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'snapshots': _snapshots
          .map((PortfolioSnapshot snapshot) => snapshot.toJson())
          .toList(),
    });
  }

  String _buildPortfolioSummaryJson() {
    final Map<String, CoinStats> stats = _computeStats();
    final PortfolioTotals totals = _totals(stats);

    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'priceSource': 'CoinGecko/manual',
      'pricesUpdatedAt': _pricesUpdatedAt?.toIso8601String(),
      'sellFeePercent': _sellFeePercent,
      'totals': <String, dynamic>{
        'costBase': totals.costBase,
        'currentValue': totals.currentValue,
        'unrealizedPL': totals.unrealizedPL,
        'realizedPL': totals.realizedPL,
        'feesPaid': totals.feesPaid,
      },
      'coins': <Map<String, dynamic>>[
        for (final String coin in _coins)
          <String, dynamic>{
            'coin': coin,
            'quantity': stats[coin]!.quantity,
            'totalInvested': stats[coin]!.totalInvested,
            'costBase': stats[coin]!.costBase,
            'avgPrice': stats[coin]!.avgPrice,
            'currentPrice': stats[coin]!.currentPrice,
            'priceStatus': priceStatusJson(stats[coin]!.currentPrice),
            'priceMode': _priceModeFor(coin),
            'manualPriceUpdatedAtMs': _manualPriceUpdatedAtMs[coin],
            'currentValue': stats[coin]!.currentValue,
            'unrealizedPL': stats[coin]!.unrealizedPL,
            'realizedPL': stats[coin]!.realizedPL,
            'feesPaid': stats[coin]!.feesPaid,
            'breakEvenReal': stats[coin]!.breakEvenReal,
            'breakEvenWithExitFee': stats[coin]!.breakEvenWithExitFee(
              _sellFeePercent,
            ),
          },
      ],
    });
  }

  Uint8List _buildXlsxBytes() {
    final Map<String, CoinStats> stats = _computeStats();
    final xl.Excel excel = xl.Excel.createExcel();

    final xl.Sheet history = excel['Historial'];
    _appendExcelRow(history, <Object?>[
      'Fecha',
      'Tipo',
      'Tipo raw',
      'Cripto',
      'Cantidad',
      'Precio unitario MXN',
      'Comisión MXN',
      'Total bruto MXN',
      'Origen',
      'Cartera',
      'Red',
      'Nota',
    ]);

    for (final Movement movement in _movements) {
      _appendExcelRow(history, <Object?>[
        movement.date.toIso8601String(),
        movement.type.label,
        movement.type.name,
        movement.coin,
        movement.quantity,
        movement.unitPrice,
        movement.fee,
        movement.quantity * movement.unitPrice,
        movement.source,
        movement.wallet,
        movement.network,
        movement.note,
      ]);
    }

    final xl.Sheet summary = excel['Resumen'];
    _appendExcelRow(summary, <Object?>[
      'Cripto',
      'Cantidad actual',
      'Costo base actual MXN',
      'Precio promedio MXN',
      'Precio actual MXN',
      'Estado precio',
      'Modo precio',
      'Valor actual MXN',
      'P&L no realizado bruto MXN',
      'P&L realizado MXN',
      'Break even neto con comisión de salida MXN',
      'Comisiones acumuladas MXN',
    ]);

    for (final String coin in _coins) {
      final CoinStats stat = stats[coin]!;
      _appendExcelRow(summary, <Object?>[
        stat.coin,
        stat.quantity,
        stat.costBase,
        stat.avgPrice,
        stat.currentPrice,
        priceStatusLabel(stat.currentPrice),
        _priceModeLabel(stat.coin),
        stat.currentValue,
        stat.unrealizedPL,
        stat.realizedPL,
        stat.netBreakEvenPrice(_sellFeePercent),
        stat.feesPaid,
      ]);
    }

    final xl.Sheet snapshots = excel['Snapshots'];
    _appendExcelRow(snapshots, <Object?>[
      'Snapshot ID',
      'Fecha',
      'Costo base total MXN',
      'Valor actual total MXN',
      'P&L no realizado bruto MXN',
      'P&L realizado MXN',
      'Movimientos',
      'Cripto',
      'Cantidad',
      'Costo base snapshot MXN',
      'Promedio MXN',
      'Valor actual MXN',
      'P&L no realizado bruto moneda MXN',
      'P&L realizado moneda MXN',
    ]);

    for (final PortfolioSnapshot snapshot in _snapshots) {
      if (snapshot.coins.isEmpty) {
        _appendExcelRow(snapshots, <Object?>[
          snapshot.id,
          snapshot.createdAt.toIso8601String(),
          snapshot.totalCostBase,
          snapshot.totalCurrentValue,
          snapshot.totalUnrealizedPL,
          snapshot.totalRealizedPL,
          snapshot.movementCount,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]);
      } else {
        for (final CoinSnapshot coin in snapshot.coins) {
          _appendExcelRow(snapshots, <Object?>[
            snapshot.id,
            snapshot.createdAt.toIso8601String(),
            snapshot.totalCostBase,
            snapshot.totalCurrentValue,
            snapshot.totalUnrealizedPL,
            snapshot.totalRealizedPL,
            snapshot.movementCount,
            coin.coin,
            coin.quantity,
            coin.costBase,
            coin.avgPrice,
            coin.currentValue,
            coin.unrealizedPL,
            coin.realizedPL,
          ]);
        }
      }
    }

    _appendExcelRow(summary, <Object?>[
      'Nota',
      'Costo promedio ponderado. P&L no realizado bruto; equilibrio neto considera comisión de salida. Precio no disponible usa 0.00 MXN como fallback técnico.',
    ]);
    excel.setDefaultSheet('Resumen');
    final List<int>? bytes = excel.encode();
    if (bytes == null) throw StateError('No se pudo crear el XLSX');
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> _buildPdfBytes() async {
    final Map<String, CoinStats> stats = _computeStats();
    final PortfolioTotals totals = _totals(stats);

    final pw.Document pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(28)),
        build: (pw.Context context) => <pw.Widget>[
          pw.Text(
            'CriptoControlMx - Reporte básico',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Generado: ${DateTime.now().toIso8601String()}'),
          pw.Text('Comisión de salida: ${pct(_sellFeePercent)}'),
          pw.Text(
            'Costo promedio ponderado. P&L no realizado bruto; equilibrio neto considera comisión de salida.',
          ),
          pw.Text(
            'Precio no disponible significa que la fuente no entregó precio válido; \$0.00 se usa solo como fallback técnico.',
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headers: <String>['Concepto', 'Monto'],
            data: <List<String>>[
              <String>['Costo base actual', money(totals.costBase)],
              <String>['Valor de cartera', money(totals.currentValue)],
              <String>['P&L no realizado', money(totals.unrealizedPL)],
              <String>['P&L realizado', money(totals.realizedPL)],
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Resumen por moneda',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headers: <String>[
              'Cripto',
              'Cantidad',
              'Invertido',
              'Valor de cartera',
              'Estado precio',
              'Modo precio',
              'P&L no realizado bruto',
              'Precio equilibrio neto',
            ],
            data: _coins.map((String coin) {
              final CoinStats s = stats[coin]!;
              return <String>[
                s.coin,
                crypto(s.quantity),
                money(s.costBase),
                money(s.currentValue),
                priceStatusLabel(s.currentPrice),
                _priceModeLabel(s.coin),
                money(s.unrealizedPL),
                money(s.netBreakEvenPrice(_sellFeePercent)),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<bool> _shareDataFile({
    required ScaffoldMessengerState messenger,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    required String successMessage,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: mimeType,
              name: fileName,
            ),
          ],
          fileNameOverrides: <String>[fileName],
          text: 'CriptoControlMx',
        ),
      );

      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      }
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'export_created',
          parameters: <String, Object>{
            'source': 'local',
            'status': 'completed',
          },
        ),
      );
      return true;
    } catch (_, stackTrace) {
      unawaited(
        recordSafeError(
          area: 'export',
          code: 'export_error',
          stackTrace: stackTrace,
        ),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'export_created',
          parameters: <String, Object>{
            'source': 'local',
            'status': 'failed',
            'error_code': 'export_error',
          },
        ),
      );
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo exportar el archivo')),
        );
      }
      return false;
    }
  }

  Future<void> _exportMovementsCsv(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_historial.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode('\ufeff${_buildMovementsCsv()}'),
      successMessage: 'Historial CSV listo',
    );
  }

  Future<void> _exportSummaryCsv(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_resumen.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode('\ufeff${_buildSummaryCsv()}'),
      successMessage: 'Resumen CSV listo',
    );
  }

  Future<void> _exportSnapshotsCsv(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_snapshots.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode('\ufeff${_buildSnapshotsCsv()}'),
      successMessage: 'Instantáneas CSV listas',
    );
  }

  Future<void> _exportMovementsJson(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_movimientos.json',
      mimeType: 'application/json',
      bytes: utf8.encode(_buildMovementsJson()),
      successMessage: 'Movimientos JSON listos',
    );
  }

  Future<void> _exportSnapshotsJson(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_snapshots.json',
      mimeType: 'application/json',
      bytes: utf8.encode(_buildSnapshotsJson()),
      successMessage: 'Instantáneas JSON listas',
    );
  }

  Future<void> _exportPortfolioSummaryJson(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_portafolio_resumen.json',
      mimeType: 'application/json',
      bytes: utf8.encode(_buildPortfolioSummaryJson()),
      successMessage: 'Resumen de portafolio JSON listo',
    );
  }

  Future<void> _exportXlsx(BuildContext pageContext) async {
    await _shareDataFile(
      messenger: ScaffoldMessenger.of(pageContext),
      fileName: 'criptocontrolmx_reporte.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      bytes: _buildXlsxBytes(),
      successMessage: 'XLSX listo',
    );
  }

  Future<void> _exportPdf(BuildContext pageContext) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    final Uint8List bytes = await _buildPdfBytes();
    if (!mounted) return;

    await _shareDataFile(
      messenger: messenger,
      fileName: 'criptocontrolmx_reporte.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
      successMessage: 'Reporte PDF listo',
    );
  }

  Future<bool> _exportBackup(BuildContext pageContext) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    final bool exported = await _shareDataFile(
      messenger: messenger,
      fileName: 'criptocontrolmx_respaldo.json',
      mimeType: 'application/json',
      bytes: utf8.encode(_buildBackupJson()),
      successMessage: 'Copia de seguridad lista para compartir',
    );
    unawaited(
      _logSafeAnalyticsEvent(
        name: 'backup_created',
        parameters: <String, Object>{
          'source': 'local',
          'status': exported ? 'completed' : 'failed',
        },
      ),
    );
    return exported;
  }

  bool _isKnownImportMovementType(dynamic value) {
    return <String>{
      'buy',
      'compra',
      'comprar',
      'sell',
      'venta',
      'vender',
      'transferin',
      'transfer_in',
      'transferenciaentrada',
      'transferencia_entrada',
      'transferencia recibida',
      'recibida',
      'entrada',
      'transferout',
      'transfer_out',
      'transferenciasalida',
      'transferencia_salida',
      'transferencia enviada',
      'enviada',
      'salida',
    }.contains(value?.toString().trim().toLowerCase() ?? '');
  }

  void _requireImportNumber(
    Map<String, dynamic> json,
    List<String> keys,
    String label,
    int number,
  ) {
    var hasField = false;
    for (final String key in keys) {
      if (!json.containsKey(key)) continue;
      hasField = true;
      final dynamic value = json[key];
      if (value == null && key != keys.last) continue;
      if (value is num || double.tryParse(value?.toString() ?? '') != null)
        return;
      throw FormatException('Movimiento #$number tiene $label no numérico');
    }
    if (hasField)
      throw FormatException('Movimiento #$number tiene $label no numérico');
  }

  Map<String, dynamic> _validatedImportMovement(dynamic raw, int index) {
    final int number = index + 1;
    if (raw is! Map)
      throw FormatException('Movimiento #$number no es un objeto válido');
    final Map<String, dynamic> json = Map<String, dynamic>.from(raw);
    if (json.containsKey('type') && !_isKnownImportMovementType(json['type'])) {
      throw FormatException('Movimiento #$number tiene tipo desconocido');
    }
    final dynamic coin = json['coin'] ?? json['crypto'];
    if (coin == null || coin.toString().trim().isEmpty)
      throw FormatException('Movimiento #$number no tiene moneda');
    _requireImportNumber(json, <String>['quantity'], 'cantidad', number);
    _requireImportNumber(
      json,
      <String>['unitPrice', 'unit_price'],
      'precio unitario',
      number,
    );
    _requireImportNumber(
      json,
      <String>['fee', 'commission'],
      'comisión',
      number,
    );
    if (json.containsKey('date') &&
        DateTime.tryParse(json['date']?.toString() ?? '') == null) {
      throw FormatException('Movimiento #$number tiene fecha inválida');
    }
    return json;
  }

  String _importErrorMessage(Object error) =>
      error is FormatException && error.message.isNotEmpty
      ? error.message
      : 'Copia de seguridad inválida o incompleta. Revisa el contenido e inténtalo de nuevo.';

  Future<_ImportResult> _applyBackupJson(String rawJson) async {
    final dynamic decoded = jsonDecode(rawJson.trim());
    if (decoded is! Map)
      throw const FormatException('La raíz de la copia no es un objeto válido');
    final Map<String, dynamic> backup = Map<String, dynamic>.from(decoded);

    final dynamic movementsRaw = backup['movements'];
    final dynamic pricesRaw = backup['currentPrices'];
    final dynamic settingsRaw = backup['settings'];
    final bool hasSnapshots = backup.containsKey('snapshots');
    final dynamic snapshotsRaw = backup['snapshots'];

    if (movementsRaw is! List)
      throw const FormatException('La copia no contiene movimientos válidos');
    if (pricesRaw is! Map)
      throw const FormatException('La copia no contiene precios válidos');
    if (hasSnapshots && snapshotsRaw is! List)
      throw const FormatException(
        'Las instantáneas de la copia no son válidas',
      );

    var importedMovementMetadataWarning = false;
    final List<Movement> imported = <Movement>[];
    for (int i = 0; i < movementsRaw.length; i++) {
      final Map<String, dynamic> json = _validatedImportMovement(
        movementsRaw[i],
        i,
      );
      importedMovementMetadataWarning =
          importedMovementMetadataWarning ||
          _movementJsonNeedsSyncMetadata(json);
      imported.add(Movement.fromJson(json));
    }
    final String importDeviceId = await _localFirebaseDeviceId();
    importedMovementMetadataWarning =
        _normalizeMovementSyncMetadata(imported, importDeviceId) ||
        importedMovementMetadataWarning;
    final Map<String, dynamic> pricesMap = Map<String, dynamic>.from(pricesRaw);
    final Map<String, String> importedPriceModes = <String, String>{
      for (final String coin in _coins) coin: PriceService.automaticMode,
    };
    final Map<String, int> importedManualUpdatedAt = <String, int>{};
    if (settingsRaw is Map) {
      final Map<String, dynamic> settings = Map<String, dynamic>.from(
        settingsRaw,
      );
      final dynamic modesRaw = settings['priceModes'];
      if (modesRaw is Map) {
        final Map<String, dynamic> modesMap = Map<String, dynamic>.from(
          modesRaw,
        );
        for (final String coin in _coins) {
          importedPriceModes[coin] =
              modesMap[coin]?.toString() == PriceService.manualMode
              ? PriceService.manualMode
              : PriceService.automaticMode;
        }
      }
      final dynamic manualRaw = settings['manualPricesUpdatedAtMs'];
      if (manualRaw is Map) {
        final Map<String, dynamic> manualMap = Map<String, dynamic>.from(
          manualRaw,
        );
        for (final String coin in _coins) {
          final dynamic value = manualMap[coin];
          if (value is int) {
            importedManualUpdatedAt[coin] = value;
          } else if (value is num) {
            importedManualUpdatedAt[coin] = value.toInt();
          }
        }
      }
    }
    final List<PortfolioSnapshot>? importedSnapshots = hasSnapshots
        ? (snapshotsRaw as List)
              .map(
                (dynamic e) => PortfolioSnapshot.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList()
        : null;
    final List<String> warnings = <String>[
      if (!hasSnapshots) 'Copia sin instantáneas',
      if (importedMovementMetadataWarning) 'IDs de movimientos normalizados',
      ...FinancialEngine.diagnostics(
        coins: _coins,
        movements: imported,
        snapshots: importedSnapshots ?? const <PortfolioSnapshot>[],
        currentPrices: <String, double>{
          for (final MapEntry<String, dynamic> entry in pricesMap.entries)
            entry.key: numberFromJson(entry.value),
        },
      ),
    ];

    setState(() {
      _movements
        ..clear()
        ..addAll(imported);

      for (final String coin in _coins) {
        _currentPrices[coin] = numberFromJson(pricesMap[coin]);
      }

      if (settingsRaw is Map && settingsRaw['sellFeePercent'] is num) {
        _sellFeePercent = (settingsRaw['sellFeePercent'] as num).toDouble();
      }
      _priceModes
        ..clear()
        ..addAll(importedPriceModes);
      _manualPriceUpdatedAtMs
        ..clear()
        ..addAll(importedManualUpdatedAt);

      if (importedSnapshots != null) {
        _snapshots
          ..clear()
          ..addAll(importedSnapshots);
        _snapshots.sort(
          (PortfolioSnapshot a, PortfolioSnapshot b) =>
              b.createdAt.compareTo(a.createdAt),
        );
        _enforceSnapshotRetention();
      }
    });

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _priceService.savePriceModes(prefs, _priceModes);
    await _priceService.saveManualPriceUpdatedAtMs(
      prefs,
      _manualPriceUpdatedAtMs,
    );
    await _saveData();
    if (importedSnapshots != null) {
      await _saveSnapshots();
    }
    return _ImportResult(
      movementCount: imported.length,
      snapshotCount: importedSnapshots?.length ?? 0,
      warnings: warnings,
    );
  }

  void _showImportResult(
    ScaffoldMessengerState messenger,
    _ImportResult result, {
    String? fileName,
  }) {
    final String source = fileName == null ? '' : ': $fileName';
    final String counts =
        '${result.movementCount} movimientos, ${result.snapshotCount} instantáneas';
    if (!result.hasWarnings) {
      messenger.showSnackBar(
        SnackBar(content: Text('Copia restaurada$source: $counts.')),
      );
      return;
    }

    final String warnings = result.warnings.take(5).join(' · ');
    messenger.showSnackBar(
      SnackBar(
        content: Text('Copia restaurada con advertencias: $counts. $warnings'),
      ),
    );
  }

  Future<void> _importBackup(BuildContext pageContext) async {
    final TextEditingController controller = TextEditingController();

    await showDialog<void>(
      context: pageContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Restaurar copia de seguridad'),
        content: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: math.min(
                MediaQuery.of(dialogContext).viewInsets.bottom,
                24.0,
              ),
            ),
            child: TextField(
              controller: controller,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                hintText: 'Pega aquí el contenido de tu copia',
                prefixIcon: Icon(Icons.data_object_outlined),
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final NavigatorState navigator = Navigator.of(dialogContext);
              final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
                pageContext,
              );
              try {
                final _ImportResult result = await _applyBackupJson(
                  controller.text,
                );

                if (!mounted) return;
                navigator.pop();
                await Future<void>.delayed(Duration.zero);
                if (!mounted) return;
                _showImportResult(messenger, result);
                unawaited(
                  _logSafeAnalyticsEvent(
                    name: 'backup_restored',
                    parameters: <String, Object>{
                      'source': 'local',
                      'status': 'completed',
                    },
                  ),
                );
              } catch (error, stackTrace) {
                unawaited(
                  recordSafeError(
                    area: 'import',
                    code: error is FormatException
                        ? 'invalid_backup'
                        : 'import_error',
                    stackTrace: stackTrace,
                  ),
                );
                unawaited(
                  _logSafeAnalyticsEvent(
                    name: 'backup_restored',
                    parameters: <String, Object>{
                      'source': 'local',
                      'status': 'failed',
                      'error_code': error is FormatException
                          ? 'invalid_backup'
                          : 'import_error',
                    },
                  ),
                );
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'No se pudo restaurar la copia. ${_importErrorMessage(error)}',
                    ),
                  ),
                );
              }
            },
            child: const Text('Restaurar copia'),
          ),
        ],
      ),
    );
  }

  Future<void> _importBackupFile(BuildContext pageContext) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);

    try {
      final FilePickerResult? pickerResult = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
        withData: true,
      );

      if (pickerResult == null || pickerResult.files.isEmpty) return;

      final PlatformFile file = pickerResult.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw const FormatException();

      final _ImportResult importResult = await _applyBackupJson(
        utf8.decode(bytes),
      );
      if (!mounted) return;

      _showImportResult(messenger, importResult, fileName: file.name);
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'backup_restored',
          parameters: <String, Object>{
            'source': 'local',
            'status': 'completed',
          },
        ),
      );
    } catch (error, stackTrace) {
      unawaited(
        recordSafeError(
          area: 'import',
          code: error is FormatException ? 'invalid_backup' : 'import_error',
          stackTrace: stackTrace,
        ),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'backup_restored',
          parameters: <String, Object>{
            'source': 'local',
            'status': 'failed',
            'error_code': error is FormatException
                ? 'invalid_backup'
                : 'import_error',
          },
        ),
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo restaurar la copia. ${_importErrorMessage(error)}',
            ),
          ),
        );
      }
    }
  }

  Future<bool> _performFinancialReset(ScaffoldMessengerState messenger) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await _priceAlertService.configureAutomaticAlerts(
        enabled: false,
        intervalMinutes: _automaticLocalAlertsIntervalMinutes,
      );
      for (final String key in <String>[
        _movementsKey,
        _pricesKey,
        PriceService.pricesUpdatedAtKey,
        PriceService.priceModesKey,
        PriceService.manualPricesUpdatedAtKey,
        _sellFeePercentKey,
        _snapshotsKey,
        _snapshotModeKey,
        _snapshotRetentionKey,
        _priceRefreshOnOpenKey,
        _priceRefreshAfterMovementKey,
        _priceRefreshForegroundModeKey,
        PriceAlertService.enabledKey,
        PriceAlertService.thresholdPercentKey,
        PriceAlertService.referencePricesKey,
        PriceAlertService.lastNotifiedAtKey,
        PriceAlertService.lastNotifiedPricesKey,
        PriceAlertService.recoveryEnabledKey,
        PriceAlertService.recoveryThresholdPointsKey,
        PriceAlertService.recoveryReferencePnlKey,
        PriceAlertService.recoveryLastNotifiedAtKey,
        PriceAlertService.automaticAlertsEnabledKey,
        PriceAlertService.automaticAlertsIntervalMinutesKey,
      ]) {
        await prefs.remove(key);
      }

      if (!mounted) return false;
      setState(() {
        _movements.clear();
        _snapshots.clear();
        _currentPrices
          ..clear()
          ..addEntries(
            _coins.map((String coin) => MapEntry<String, double>(coin, 0.0)),
          );
        _pricesUpdatedAt = null;
        _priceModes
          ..clear()
          ..addEntries(
            _coins.map(
              (String coin) =>
                  MapEntry<String, String>(coin, PriceService.automaticMode),
            ),
          );
        _manualPriceUpdatedAtMs.clear();
        _sellFeePercent = FinancialEngine.defaultExitFeePercent;
        _snapshotAutomationMode = SnapshotAutomationMode.manual;
        _snapshotRetention = SnapshotRetention.last30;
        _refreshPricesOnOpen = true;
        _refreshPricesAfterMovement = false;
        _priceRefreshForegroundMode = PriceRefreshForegroundMode.manual;
        _priceAlertsEnabled = false;
        _priceAlertThresholdPercent = PriceAlertService.defaultThresholdPercent;
        _priceAlertReferences = <String, double>{};
        _recoveryAlertsEnabled = false;
        _recoveryAlertThresholdPoints =
            PriceAlertService.defaultRecoveryThresholdPoints;
        _recoveryAlertReferences = <String, double>{};
        _automaticLocalAlertsEnabled = false;
        _automaticLocalAlertsIntervalMinutes =
            PriceAlertService.defaultAutomaticIntervalMinutes;
      });
      _restartPriceRefreshTimer();

      if (!mounted) return false;
      messenger.showSnackBar(
        const SnackBar(content: Text('Datos financieros restablecidos')),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'financial_reset_completed',
          parameters: <String, Object>{'status': 'completed'},
        ),
      );
      return true;
    } catch (_, stackTrace) {
      unawaited(
        recordSafeError(
          area: 'reset',
          code: 'reset_error',
          stackTrace: stackTrace,
        ),
      );
      unawaited(
        _logSafeAnalyticsEvent(
          name: 'financial_reset_completed',
          parameters: <String, Object>{
            'status': 'failed',
            'error_code': 'reset_error',
          },
        ),
      );
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo restablecer la app')),
        );
      }
      return false;
    }
  }

  Future<void> _resetFinancialData(BuildContext pageContext) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(pageContext);
    unawaited(
      _logSafeAnalyticsEvent(
        name: 'financial_reset_opened',
        parameters: <String, Object>{'status': 'started'},
      ),
    );
    await Navigator.of(pageContext).push(
      MaterialPageRoute<void>(
        builder: (BuildContext resetContext) => _FinancialResetScreen(
          hasCloudState:
              _firebaseUser != null ||
              _cloudStateUploadedAt != null ||
              _cloudStateDownloadedAt != null,
          onExportBackup: () => _exportBackup(resetContext),
          onReset: () => _performFinancialReset(messenger),
        ),
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String normalized = message.toLowerCase();
    final bool isError =
        normalized.contains('no se pudo') ||
        normalized.contains('pon ') ||
        normalized.contains('inválid') ||
        normalized.contains('inval') ||
        normalized.contains('error');
    final bool isWarning =
        normalized.contains('revisa') ||
        normalized.contains('debe') ||
        normalized.contains('riesgo');
    final Color tone = isError
        ? colors.error
        : isWarning
        ? const Color(0xFFF59E0B)
        : colors.primary;
    final IconData icon = isError
        ? Icons.error_outline_rounded
        : isWarning
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline_rounded;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: colors.surfaceContainerHighest,
        content: Row(
          children: <Widget>[
            Icon(icon, color: tone, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxThemeStyle themeStyle = ccmx.CcmxThemeStyle.values.byName(
      _themeStyle.name,
    );

    if (!_bootstrapped) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CriptoControlMx',
        themeMode: _visualMode.themeMode,
        themeAnimationDuration: const Duration(milliseconds: 260),
        themeAnimationCurve: Curves.easeOutCubic,
        theme: ccmx.CcmxAppTheme.build(
          style: themeStyle,
          brightness: Brightness.light,
        ),
        darkTheme: ccmx.CcmxAppTheme.build(
          style: themeStyle,
          brightness: Brightness.dark,
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final Map<String, CoinStats> stats = _computeStats();
    final PortfolioTotals totals = _totals(stats);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CriptoControlMx',
      themeMode: _visualMode.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 260),
      themeAnimationCurve: Curves.easeOutCubic,
      theme: ccmx.CcmxAppTheme.build(
        style: themeStyle,
        brightness: Brightness.light,
      ),
      darkTheme: ccmx.CcmxAppTheme.build(
        style: themeStyle,
        brightness: Brightness.dark,
      ),
      home: Builder(
        builder: (BuildContext pageContext) {
          void openMorePage(
            String title,
            Widget Function(VoidCallback refresh) childBuilder,
          ) {
            Navigator.of(pageContext).push(
              MaterialPageRoute<void>(
                builder: (_) => StatefulBuilder(
                  builder:
                      (
                        BuildContext routeContext,
                        void Function(void Function()) routeSetState,
                      ) {
                        void refresh() => routeSetState(() {});
                        return Scaffold(
                          appBar: AppBar(title: Text(title)),
                          body: childBuilder(refresh),
                        );
                      },
                ),
              ),
            );
          }

          void openAlertsTab() {
            Navigator.of(pageContext).maybePop();
            _goToMainTab(3);
          }

          Widget buildChartsTab({VoidCallback? refresh}) => ChartsTab(
            stats: stats,
            totals: totals,
            snapshots: _snapshots,
            chartType: _summaryChartType,
            onChartTypeChanged: (SummaryChartType value) {
              _changeSummaryChartType(value);
              refresh?.call();
            },
            onSaveSnapshot: () {
              _saveSnapshot(pageContext).then((_) => refresh?.call());
            },
            onViewSnapshots: () => _showSnapshots(pageContext),
          );

          Widget buildMovementsTab({bool startWithOcr = false}) => MovementsTab(
            movements: _movements,
            coins: _coins,
            startWithOcr: startWithOcr,
            onAdd: () => _showAddMovementSheet(pageContext),
            onAddFromOcr: (_OcrMovementCandidate candidate) =>
                _showAddMovementSheet(pageContext, ocrCandidate: candidate),
            onEdit: (Movement movement) => _showAddMovementSheet(
              pageContext,
              existing: movement,
              index: _movements.indexOf(movement),
            ),
            onDelete: (Movement movement) {
              setState(() => _movements.remove(movement));
              _saveMovementAndMaybeSnapshot(SnapshotTrigger.movementChange);
            },
          );

          void openMovementHistory({bool startWithOcr = false}) {
            openMorePage(
              'Historial de movimientos',
              (_) => buildMovementsTab(startWithOcr: startWithOcr),
            );
          }

          Widget buildSettingsTab({
            VoidCallback? refresh,
            SettingsView view = SettingsView.all,
          }) => SettingsTab(
            view: view,
            visualMode: _visualMode,
            themeStyle: _themeStyle,
            visiblePositions: _visiblePositions,
            positionSortMode: _positionSortMode,
            snapshotAutomationMode: _snapshotAutomationMode,
            snapshotRetention: _snapshotRetention,
            refreshPricesOnOpen: _refreshPricesOnOpen,
            refreshPricesAfterMovement: _refreshPricesAfterMovement,
            priceRefreshForegroundMode: _priceRefreshForegroundMode,
            sellFeePercent: _sellFeePercent,
            snapshotCount: _snapshots.length,
            onVisualModeChanged: (AppVisualMode value) {
              _changeVisualMode(value);
              refresh?.call();
            },
            onThemeStyleChanged: (AppThemeStyle value) {
              _changeThemeStyle(value);
              refresh?.call();
            },
            onVisiblePositionsChanged: (VisiblePositions value) {
              _changeVisiblePositions(value);
              refresh?.call();
            },
            onPositionSortModeChanged: (PositionSortMode value) {
              _changePositionSortMode(value);
              refresh?.call();
            },
            onSnapshotAutomationModeChanged: (SnapshotAutomationMode value) {
              _changeSnapshotAutomationMode(value);
              refresh?.call();
            },
            onSnapshotRetentionChanged: (SnapshotRetention value) {
              _changeSnapshotRetention(value);
              refresh?.call();
            },
            onRefreshPricesOnOpenChanged: _changeRefreshPricesOnOpen,
            onRefreshPricesAfterMovementChanged:
                _changeRefreshPricesAfterMovement,
            onPriceRefreshForegroundModeChanged:
                _changePriceRefreshForegroundMode,
            onEditSellFee: () => _showSellFeeDialog(pageContext),
            onOpenAlerts: openAlertsTab,
            automaticLocalAlertsEnabled: _automaticLocalAlertsEnabled,
            automaticLocalAlertsIntervalMinutes:
                _automaticLocalAlertsIntervalMinutes,
            notificationsAllowed: _notificationsAllowed,
            onAutomaticLocalAlertsChanged: (bool enabled) {
              _toggleAutomaticLocalAlerts(
                pageContext,
                enabled,
              ).then((_) => refresh?.call());
            },
            onAutomaticLocalAlertIntervalChanged: (int minutes) {
              _changeAutomaticLocalAlertInterval(
                minutes,
              ).then((_) => refresh?.call());
            },
            onSaveSnapshot: () {
              _saveSnapshot(pageContext).then((_) => refresh?.call());
            },
            onViewSnapshots: () => _showSnapshots(pageContext),
            onExportSnapshotsCsv: () => _exportSnapshotsCsv(pageContext),
            onExportXlsx: () => _exportXlsx(pageContext),
            onExportPdf: () => _exportPdf(pageContext),
            onExportBackup: () {
              _exportBackup(pageContext);
            },
          );

          final List<Widget> pages = <Widget>[
            SimulationTab(
              key: ValueKey<String>(
                '${_requestedSimulationMode.name}-$_simulationOpenNonce',
              ),
              coins: _coins,
              stats: stats,
              defaultFeePercent: _sellFeePercent,
              targetExitFeePercent: _sellFeePercent,
              initialMode: _requestedSimulationMode,
            ),
            SummaryTab(
              stats: stats,
              totals: totals,
              sellFeePercent: _sellFeePercent,
              hasMovements: _movements.isNotEmpty,
              visiblePositions: _visiblePositions,
              positionSortMode: _positionSortMode,
              latestSnapshot: _snapshots.isEmpty ? null : _snapshots.first,
              snapshots: _snapshots,
              viewMode: _summaryViewMode,
              chartType: _summaryChartType,
              onViewModeChanged: _changeSummaryViewMode,
              onChartTypeChanged: _changeSummaryChartType,
              onDetails: (CoinStats s) => _showCoinDetails(pageContext, s),
              onAddMovement: () => _showAddMovementSheet(pageContext),
              onImportBackup: () => _importBackup(pageContext),
              onRefreshPrices: () => _refreshPricesNow(pageContext),
              onSaveSnapshot: () => _saveSnapshot(pageContext),
              onViewSnapshots: () => _showSnapshots(pageContext),
              onViewSnapshotEvolution: () => openMorePage(
                'Gráficas',
                (VoidCallback refresh) => buildChartsTab(refresh: refresh),
              ),
            ),
            CoinsTab(
              coins: _coins,
              stats: stats,
              snapshots: _snapshots,
              sellFeePercent: _sellFeePercent,
              priceModes: _priceModes,
              manualPriceUpdatedAtMs: _manualPriceUpdatedAtMs,
              onRefreshPrices: () => _refreshPricesNow(pageContext),
              onEditPrice: (String coin) =>
                  _showEditPriceDialog(pageContext, coin),
              onDetails: (CoinStats s) => _showCoinDetails(pageContext, s),
              onViewMovements: () => openMovementHistory(),
            ),
            AlertsTab(
              coins: _coins,
              stats: stats,
              priceAlertsEnabled: _priceAlertsEnabled,
              priceAlertThresholdPercent: _priceAlertThresholdPercent,
              priceAlertReferences: _priceAlertReferences,
              recoveryAlertsEnabled: _recoveryAlertsEnabled,
              recoveryAlertThresholdPoints: _recoveryAlertThresholdPoints,
              recoveryAlertReferences: _recoveryAlertReferences,
              sellFeePercent: _sellFeePercent,
              notificationsAllowed: _notificationsAllowed,
              automaticLocalAlertsEnabled: _automaticLocalAlertsEnabled,
              automaticLocalAlertsIntervalMinutes:
                  _automaticLocalAlertsIntervalMinutes,
              pricesUpdatedAt: _pricesUpdatedAt,
              isRefreshingPrices: _isRefreshingPrices,
              onRefreshPrices: () => _refreshPricesNow(pageContext),
              onPriceAlertsChanged: (bool enabled) =>
                  _togglePriceAlerts(pageContext, enabled),
              onEditPriceAlertThreshold: () =>
                  _showPriceAlertThresholdDialog(pageContext),
              onResetPriceAlertReferences: () =>
                  _resetPriceAlertReferences(pageContext),
              onRecoveryAlertsChanged: (bool enabled) =>
                  _toggleRecoveryAlerts(pageContext, enabled),
              onEditRecoveryAlertThreshold: () =>
                  _showRecoveryAlertThresholdDialog(pageContext),
              onResetRecoveryAlertReferences: () =>
                  _resetRecoveryAlertReferences(pageContext),
              onAutomaticLocalAlertsChanged: (bool enabled) =>
                  _toggleAutomaticLocalAlerts(pageContext, enabled),
              onAutomaticLocalAlertIntervalChanged:
                  _changeAutomaticLocalAlertInterval,
            ),
            MoreTab(
              totals: totals,
              pricesUpdatedAt: _pricesUpdatedAt,
              visualMode: _visualMode,
              themeStyle: _themeStyle,
              movementCount: _movements.length,
              movementsWithIdCount: _movements
                  .where((Movement movement) => movement.id.trim().isNotEmpty)
                  .length,
              snapshotCount: _snapshots.length,
              latestSnapshot: _snapshots.isEmpty
                  ? null
                  : _snapshots.first.createdAt,
              activeCoins: stats.values
                  .where((CoinStats s) => s.quantity > 0)
                  .length,
              financialErrors: _financialDiagnostics(),
              snapshotAutomationMode: _snapshotAutomationMode,
              snapshotRetention: _snapshotRetention,
              pricesAvailableCount: _coins
                  .where((String coin) => (_currentPrices[coin] ?? 0.0) > 0.0)
                  .length,
              pricesTotalCount: _coins.length,
              missingPriceCoins: _coins
                  .where((String coin) => (_currentPrices[coin] ?? 0.0) <= 0.0)
                  .toList(),
              manualPriceCoins: _coins
                  .where(
                    (String coin) =>
                        _priceModeFor(coin) == PriceService.manualMode,
                  )
                  .toList(),
              refreshPricesOnOpen: _refreshPricesOnOpen,
              refreshPricesAfterMovement: _refreshPricesAfterMovement,
              priceRefreshForegroundMode: _priceRefreshForegroundMode,
              automaticLocalAlertsEnabled: _automaticLocalAlertsEnabled,
              automaticLocalAlertsIntervalMinutes:
                  _automaticLocalAlertsIntervalMinutes,
              notificationsAllowed: _notificationsAllowed,
              firebaseStatus: widget.firebaseStatus,
              analyticsEnabled: _analyticsConsent,
              crashlyticsEnabled: _crashlyticsConsent,
              firebaseAuthEmail: _firebaseUser?.email,
              firebaseAuthDisplayName: _firebaseUser?.displayName,
              firebaseAuthUid: _firebaseUser?.uid,
              cloudProfileStatus: _cloudProfileStatus,
              isCloudProfilePreparing: _isCloudProfilePreparing,
              hasLocalFirebaseDeviceId: _firebaseDeviceId != null,
              cloudStateUploadedAt: _cloudStateUploadedAt,
              cloudStateDownloadedAt: _cloudStateDownloadedAt,
              googleAccountEmail:
                  _googleAccount?.email ?? _googleDriveSessionEmail,
              googleAccountDisplayName:
                  _googleAccount?.displayName ?? _googleDriveSessionDisplayName,
              googleDriveLastConnectedAt: _googleDriveSessionConnectedAt,
              googleDriveWasConnected: _googleDriveWasConnected,
              googleDriveSessionStatus: _googleDriveSessionStatus,
              isGoogleDriveAuthorized: _isGoogleDriveAuthorized,
              googleDriveBackupUpdatedAt: _googleDriveBackupUpdatedAt,
              isFirebaseAuthBusy: _isFirebaseAuthBusy,
              isCloudUploading: _isCloudUploading,
              isCloudDownloading: _isCloudDownloading,
              isGoogleConnecting: _isGoogleConnecting,
              isGoogleDriveCreating: _isGoogleDriveCreating,
              isGoogleDriveRestoring: _isGoogleDriveRestoring,
              isRefreshingPrices: _isRefreshingPrices,
              chartDataCount: stats.values
                  .where((CoinStats stat) => stat.currentValue > 0)
                  .length,
              motorCoins: _coins,
              motorSellFeePercent: _sellFeePercent,
              onOpenCharts: () => openMorePage(
                'Gráficas',
                (VoidCallback refresh) => buildChartsTab(refresh: refresh),
              ),
              onOpenMovements: openMovementHistory,
              onOpenPriceSettings: () => openMorePage(
                'Actualización de precios',
                (VoidCallback refresh) => buildSettingsTab(
                  refresh: refresh,
                  view: SettingsView.prices,
                ),
              ),
              onOpenThemeSettings: () => openMorePage(
                'Tema',
                (VoidCallback refresh) => buildSettingsTab(
                  refresh: refresh,
                  view: SettingsView.theme,
                ),
              ),
              onOpenPortfolioSettings: () => openMorePage(
                'Resumen de cartera',
                (VoidCallback refresh) => buildSettingsTab(
                  refresh: refresh,
                  view: SettingsView.portfolio,
                ),
              ),
              onOpenAlerts: openAlertsTab,
              onExportMovementsCsv: () => _exportMovementsCsv(pageContext),
              onExportSummaryCsv: () => _exportSummaryCsv(pageContext),
              onExportSnapshotsCsv: () => _exportSnapshotsCsv(pageContext),
              onExportMovementsJson: () => _exportMovementsJson(pageContext),
              onExportSnapshotsJson: () => _exportSnapshotsJson(pageContext),
              onExportPortfolioSummaryJson: () =>
                  _exportPortfolioSummaryJson(pageContext),
              onExportXlsx: () => _exportXlsx(pageContext),
              onExportPdf: () => _exportPdf(pageContext),
              onExportBackup: () {
                _exportBackup(pageContext);
              },
              onImportBackup: () => _importBackup(pageContext),
              onImportBackupFile: () => _importBackupFile(pageContext),
              onSignInFirebaseWithGoogle: () => unawaited(
                _runUserInitiatedDriveAuth(
                  'firebase_sign_in',
                  () => _signInFirebaseWithGoogle(pageContext),
                ),
              ),
              onSignOutFirebase: () => _signOutFirebase(pageContext),
              onPrepareCloudProfile: () => _retryCloudProfile(pageContext),
              onUploadFinancialStateToFirebase: () =>
                  _uploadFinancialStateToFirebase(pageContext),
              onDownloadFinancialStateFromFirebase: () =>
                  _downloadFinancialStateFromFirebase(pageContext),
              onConnectGoogleDrive: () => unawaited(
                _runUserInitiatedDriveAuth(
                  _googleDriveUserActionForConnect(),
                  () => _connectGoogleDrive(pageContext),
                ),
              ),
              onReconnectGoogleDrive: () => unawaited(
                _runUserInitiatedDriveAuth('reconnect', () async {
                  if (mounted) {
                    setState(() {
                      _googleAccount = null;
                      _googleDriveSessionStatus =
                          GoogleDriveSessionStatus.temporaryError;
                    });
                  }
                  await _connectGoogleDrive(pageContext);
                }),
              ),
              onDisconnectGoogleDrive: () => unawaited(
                _runUserInitiatedDriveAuth(
                  'sign_out',
                  () => _disconnectGoogleDrive(pageContext),
                ),
              ),
              onCreateGoogleDriveBackup: () => unawaited(
                _runUserInitiatedDriveAuth(
                  'backup_now',
                  () => _createGoogleDriveBackup(pageContext),
                ),
              ),
              onRestoreGoogleDriveBackup: () => unawaited(
                _runUserInitiatedDriveAuth(
                  'restore_from_drive',
                  () => _restoreGoogleDriveBackup(pageContext),
                ),
              ),
              onSaveSnapshot: () => _saveSnapshot(pageContext),
              onViewSnapshots: () => _showSnapshots(pageContext),
              onSnapshotAutomationModeChanged: _changeSnapshotAutomationMode,
              onSnapshotRetentionChanged: _changeSnapshotRetention,
              onResetPriceAlertReferences: () =>
                  _resetPriceAlertReferences(pageContext),
              onOpenFinancialReset: () => _resetFinancialData(pageContext),
              onAnalyticsConsentChanged: (bool enabled) =>
                  _setAnalyticsConsent(pageContext, enabled),
              onCrashlyticsConsentChanged: (bool enabled) =>
                  _setCrashlyticsConsent(pageContext, enabled),
            ),
          ];

          return Scaffold(
            appBar: AppBar(
              title: const Text('CriptoControlMx'),
              actions: <Widget>[
                if (_currentIndex != 0)
                  PremiumQuickActions(
                    onCapture: () => openMovementHistory(startWithOcr: true),
                    onAdd: () => _showAddMovementSheet(pageContext),
                  ),
                if (_currentIndex != 0) const SizedBox(width: 8),
              ],
            ),
            body: PageView(
              controller: _mainPageController,
              onPageChanged: _handleMainPageChanged,
              children: pages
                  .map((Widget page) => _KeepAliveMainTab(child: page))
                  .toList(),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (int index) {
                unawaited(_logSafeAnalyticsEvent(name: 'tab_view'));
                _goToMainTab(index);
              },
              destinations: const <NavigationDestination>[
                NavigationDestination(icon: Icon(Icons.tune), label: 'Simular'),
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Resumen',
                ),
                NavigationDestination(
                  icon: Icon(Icons.currency_bitcoin),
                  label: 'Monedas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.notifications_active_outlined),
                  label: 'Alertas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  label: 'Más',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KeepAliveMainTab extends StatefulWidget {
  final Widget child;

  const _KeepAliveMainTab({required this.child});

  @override
  State<_KeepAliveMainTab> createState() => _KeepAliveMainTabState();
}

class _KeepAliveMainTabState extends State<_KeepAliveMainTab>
    with AutomaticKeepAliveClientMixin<_KeepAliveMainTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class SummaryTab extends StatelessWidget {
  final Map<String, CoinStats> stats;
  final PortfolioTotals totals;
  final double sellFeePercent;
  final bool hasMovements;
  final VisiblePositions visiblePositions;
  final PositionSortMode positionSortMode;
  final PortfolioSnapshot? latestSnapshot;
  final List<PortfolioSnapshot> snapshots;
  final SummaryViewMode viewMode;
  final SummaryChartType chartType;
  final ValueChanged<SummaryViewMode> onViewModeChanged;
  final ValueChanged<SummaryChartType> onChartTypeChanged;
  final void Function(CoinStats stats) onDetails;
  final VoidCallback onAddMovement;
  final VoidCallback onImportBackup;
  final Future<void> Function() onRefreshPrices;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;
  final VoidCallback onViewSnapshotEvolution;

  const SummaryTab({
    super.key,
    required this.stats,
    required this.totals,
    required this.sellFeePercent,
    required this.hasMovements,
    required this.visiblePositions,
    required this.positionSortMode,
    required this.latestSnapshot,
    required this.snapshots,
    required this.viewMode,
    required this.chartType,
    required this.onViewModeChanged,
    required this.onChartTypeChanged,
    required this.onDetails,
    required this.onAddMovement,
    required this.onImportBackup,
    required this.onRefreshPrices,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
    required this.onViewSnapshotEvolution,
  });

  List<Widget> _buildVisiblePositionChildren({
    required List<CoinStats> active,
    required List<CoinStats> visibleActive,
    required double sellFeePercent,
    required PositionSortMode positionSortMode,
    required void Function(CoinStats stats) onDetails,
  }) {
    if (active.isEmpty) {
      return <Widget>[
        _SummaryCompactNotice(
          icon: Icons.account_balance_wallet_outlined,
          title: hasMovements
              ? 'No tienes posiciones abiertas'
              : 'No hay cartera todavía',
          subtitle: hasMovements
              ? 'Tus movimientos existen, pero no hay saldos activos.'
              : 'Agrega tu primer movimiento para iniciar el seguimiento.',
        ),
      ];
    }

    final List<Widget> children = visibleActive
        .map<Widget>(
          (CoinStats s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SummaryCompactCoinTile(
              stats: s,
              sellFeePercent: sellFeePercent,
              onDetails: () => onDetails(s),
            ),
          ),
        )
        .toList();

    final int hiddenCount = active.length - visibleActive.length;
    if (hiddenCount > 0) {
      children.add(
        _SummaryCompactNotice(
          icon: Icons.visibility_off_outlined,
          title: '$hiddenCount posiciones ocultas',
          subtitle: 'Límite actual · ${positionSortMode.label}',
        ),
      );
    }

    return children;
  }

  @override
  Widget build(BuildContext context) {
    final List<CoinStats> active = sortedPositions(
      stats.values.where((CoinStats s) => s.quantity > 0),
      positionSortMode,
      sellFeePercent,
    );
    final int? visibleLimit = visiblePositions.limit;
    final List<CoinStats> visibleActive = visibleLimit == null
        ? active
        : active.take(visibleLimit).toList();
    final CoinStats? leader = active.isEmpty ? null : active.first;
    final CoinStats? weakest = active.isEmpty
        ? null
        : active.reduce(
            (CoinStats a, CoinStats b) =>
                a.unrealizedPL <= b.unrealizedPL ? a : b,
          );
    final int recovered = active
        .where((CoinStats s) => s.isAtOrAboveNetBreakEven(sellFeePercent))
        .length;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF070B14), Color(0xFF090D18)],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: onRefreshPrices,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 26),
          children: <Widget>[
            _SummaryViewModeSwitcher(
              value: viewMode,
              onChanged: onViewModeChanged,
            ),
            const SizedBox(height: 10),
            if (viewMode == SummaryViewMode.executive) ...<Widget>[
              _SummaryMockupHero(totals: totals),
              const SizedBox(height: 10),
              _SummaryMiniMetricGrid(totals: totals, leader: leader),
              const SizedBox(height: 12),
              _SummaryDistributionPanel(
                positions: active,
                totalValue: totals.currentValue,
              ),
              const SizedBox(height: 10),
              _SummaryCompactFocusTile(
                weakest: weakest,
                recovered: recovered,
                positionCount: active.length,
                sellFeePercent: sellFeePercent,
              ),
              const SizedBox(height: 16),
              _SummaryCompactSection(
                title: 'Posiciones visibles',
                subtitle:
                    '${visibleActive.length} · ${visiblePositions.label} · ${positionSortMode.label}',
              ),
              const SizedBox(height: 8),
              ..._buildVisiblePositionChildren(
                active: active,
                visibleActive: visibleActive,
                sellFeePercent: sellFeePercent,
                positionSortMode: positionSortMode,
                onDetails: onDetails,
              ),
              const SizedBox(height: 10),
              _SummarySnapshotPanel(
                snapshot: latestSnapshot,
                onViewEvolution: onViewSnapshotEvolution,
              ),
            ] else
              _SummaryQuickView(
                totals: totals,
                positions: visibleActive,
                latestSnapshot: latestSnapshot,
                snapshots: snapshots,
                chartType: chartType,
                onChartTypeChanged: onChartTypeChanged,
                onDetails: onDetails,
                onViewEvolution: onViewSnapshotEvolution,
              ),
            if (!hasMovements) ...<Widget>[
              const SizedBox(height: 10),
              _SummaryWelcomePanel(
                onAddMovement: onAddMovement,
                onImportBackup: onImportBackup,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const Color _summaryPurple = Color(0xFF8B5CF6);
String _summaryMoney(double value, {int decimals = 0}) {
  final List<String> parts = value.abs().toStringAsFixed(decimals).split('.');
  final String digits = parts.first;
  final StringBuffer grouped = StringBuffer();
  for (int index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  final String fraction = decimals > 0 ? '.${parts.last}' : '';
  return '${value < 0 ? '-' : ''}\$${grouped.toString()}$fraction MXN';
}

BoxDecoration _summaryTokenBox(
  BuildContext context, {
  Color? color,
  double radius = 13,
}) {
  final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
  return BoxDecoration(
    color: color ?? tokens.cardBackground,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: tokens.cardBorder, width: tokens.borderWidth),
    boxShadow: tokens.shadowOpacity == 0
        ? null
        : <BoxShadow>[
            BoxShadow(
              color: tokens.shadow.withValues(alpha: tokens.shadowOpacity),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
  );
}

List<Color> _summaryDistributionPalette(BuildContext context) {
  final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
  return <Color>[
    tokens.chartPrimary,
    tokens.chartSecondary,
    tokens.chartMarker,
    tokens.primaryAccent.withValues(alpha: 0.72),
    tokens.tertiaryAccent.withValues(alpha: 0.86),
  ];
}

class _SummaryViewModeSwitcher extends StatelessWidget {
  final SummaryViewMode value;
  final ValueChanged<SummaryViewMode> onChanged;

  const _SummaryViewModeSwitcher({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: _summaryTokenBox(
        context,
        color: tokens.surfacePrimary,
        radius: 13,
      ),
      child: Row(
        children: SummaryViewMode.values.map((SummaryViewMode mode) {
          final bool selected = mode == value;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(mode),
              borderRadius: BorderRadius.circular(9),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? tokens.selectedBackground
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: selected
                      ? <BoxShadow>[
                          BoxShadow(color: tokens.glowColor, blurRadius: 12),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      mode.icon,
                      size: 16,
                      color: selected
                          ? tokens.primaryAccent
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      mode.label,
                      style: TextStyle(
                        color: selected
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SummaryQuickView extends StatelessWidget {
  final PortfolioTotals totals;
  final List<CoinStats> positions;
  final PortfolioSnapshot? latestSnapshot;
  final List<PortfolioSnapshot> snapshots;
  final SummaryChartType chartType;
  final ValueChanged<SummaryChartType> onChartTypeChanged;
  final void Function(CoinStats stats) onDetails;
  final VoidCallback onViewEvolution;

  const _SummaryQuickView({
    required this.totals,
    required this.positions,
    required this.latestSnapshot,
    required this.snapshots,
    required this.chartType,
    required this.onChartTypeChanged,
    required this.onDetails,
    required this.onViewEvolution,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SummaryQuickMetricsGrid(totals: totals),
        const SizedBox(height: 10),
        _SummarySnapshotPanel(
          snapshot: latestSnapshot,
          onViewEvolution: onViewEvolution,
        ),
        const SizedBox(height: 10),
        _SummaryQuickEvolutionPanel(
          snapshots: snapshots,
          chartType: chartType,
          onChartTypeChanged: onChartTypeChanged,
          onViewEvolution: onViewEvolution,
        ),
        const SizedBox(height: 16),
        _SummaryCompactSection(
          title: 'Monedas en foco',
          subtitle: '${positions.length} posiciones visibles',
        ),
        const SizedBox(height: 8),
        if (positions.isEmpty)
          const _SummaryCompactNotice(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Sin posiciones abiertas',
            subtitle: 'Agrega movimientos para ver tu lectura rápida.',
          )
        else
          ...positions.map(
            (CoinStats stats) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _SummaryQuickCoinRow(
                stats: stats,
                onDetails: () => onDetails(stats),
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryQuickMetricsGrid extends StatelessWidget {
  final PortfolioTotals totals;

  const _SummaryQuickMetricsGrid({required this.totals});

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    final List<_SummaryQuickMetricData> metrics = <_SummaryQuickMetricData>[
      _SummaryQuickMetricData(
        'Valor actual',
        _summaryMoney(totals.currentValue),
        Icons.account_balance_wallet_outlined,
        tokens.primaryAccent,
      ),
      _SummaryQuickMetricData(
        'Invertido',
        _summaryMoney(totals.costBase),
        Icons.savings_outlined,
        tokens.chartSecondary,
      ),
      _SummaryQuickMetricData(
        'P&L no realizado',
        _summaryMoney(totals.unrealizedPL),
        Icons.trending_up,
        pnlColor(totals.unrealizedPL),
      ),
      _SummaryQuickMetricData(
        'P&L realizado',
        _summaryMoney(totals.realizedPL),
        Icons.payments_outlined,
        pnlColor(totals.realizedPL),
      ),
    ];

    return LayoutBuilder(
      builder: (_, BoxConstraints constraints) {
        final double width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metrics
              .map(
                (_SummaryQuickMetricData metric) => SizedBox(
                  width: width,
                  child: _SummaryQuickMetricCard(metric: metric),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SummaryQuickMetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryQuickMetricData(this.label, this.value, this.icon, this.color);
}

class _SummaryQuickMetricCard extends StatelessWidget {
  final _SummaryQuickMetricData metric;

  const _SummaryQuickMetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    return Container(
      height: 92,
      padding: const EdgeInsets.all(11),
      decoration: _summaryTokenBox(
        context,
        color: tokens.surfaceElevated,
        radius: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(metric.icon, size: 15, color: metric.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Color(0xFFB6BED0),
                    fontSize: 13,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              style: TextStyle(
                color: metric.color,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryQuickEvolutionPanel extends StatelessWidget {
  final List<PortfolioSnapshot> snapshots;
  final SummaryChartType chartType;
  final ValueChanged<SummaryChartType> onChartTypeChanged;
  final VoidCallback onViewEvolution;

  const _SummaryQuickEvolutionPanel({
    required this.snapshots,
    required this.chartType,
    required this.onChartTypeChanged,
    required this.onViewEvolution,
  });

  @override
  Widget build(BuildContext context) {
    final List<PortfolioSnapshot> ordered = snapshots.toList()
      ..sort(
        (PortfolioSnapshot a, PortfolioSnapshot b) =>
            a.createdAt.compareTo(b.createdAt),
      );
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);

    return _SummaryPanel(
      icon: Icons.show_chart,
      title: 'Evolución de cartera',
      titleFontSize: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _SummaryChartTypeButton(
                  value: chartType,
                  onChanged: onChartTypeChanged,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onViewEvolution,
                tooltip: 'Abrir gráficas',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.open_in_new, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (ordered.length < 2)
            const _SummaryCompactNotice(
              icon: Icons.show_chart_outlined,
              title: 'Histórico insuficiente',
              subtitle: 'Guarda dos instantáneas para dibujar la evolución.',
            )
          else
            SnapshotLineChart(
              snapshots: ordered,
              height: 160,
              includeZero: true,
              chartType: chartType,
              series: <SnapshotChartSeries>[
                SnapshotChartSeries(
                  label: 'Valor actual',
                  color: tokens.chartPrimary,
                  values: ordered
                      .map((PortfolioSnapshot s) => s.totalCurrentValue)
                      .toList(),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SummaryQuickCoinRow extends StatelessWidget {
  final CoinStats stats;
  final VoidCallback onDetails;

  const _SummaryQuickCoinRow({required this.stats, required this.onDetails});

  @override
  Widget build(BuildContext context) {
    final Color resultColor = pnlColor(stats.unrealizedPL);
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: _summaryTokenBox(context, radius: 11),
      child: Row(
        children: <Widget>[
          CoinLogo(coin: stats.coin, size: 30),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  stats.coin,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  crypto(stats.quantity),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFAAB3C5),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 118),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _summaryMoney(stats.currentValue),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _summaryMoney(stats.unrealizedPL),
                    style: TextStyle(
                      color: resultColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDetails,
            tooltip: 'Detalles',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right, size: 18),
          ),
        ],
      ),
    );
  }
}

class _SummaryChartTypeButton extends StatelessWidget {
  final SummaryChartType value;
  final ValueChanged<SummaryChartType> onChanged;
  final bool compact;

  const _SummaryChartTypeButton({
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    return OutlinedButton.icon(
      onPressed: () => _showSummaryChartTypeSheet(
        context,
        value: value,
        onChanged: onChanged,
        hasOhlc: false,
      ),
      icon: Icon(value.icon, size: 17),
      label: Text(
        compact ? 'Tipo de gráfico' : 'Tipo de gráfico · ${value.label}',
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.primaryAccent,
        minimumSize: Size(0, compact ? 40 : 44),
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        side: BorderSide(color: tokens.selectedBorder),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

Future<void> _showSummaryChartTypeSheet(
  BuildContext context, {
  required SummaryChartType value,
  required ValueChanged<SummaryChartType> onChanged,
  required bool hasOhlc,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(
        sheetContext,
      );
      final ColorScheme colors = Theme.of(sheetContext).colorScheme;
      return Container(
        decoration: BoxDecoration(
          color: tokens.sheetBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: tokens.cardBorder)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.primaryAccent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tipo de gráfico',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Elige cómo representar la serie temporal actual.',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 16),
              ),
              const SizedBox(height: 14),
              for (final SummaryChartType type in SummaryChartType.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SummaryChartTypeOption(
                    type: type,
                    selected: value == type,
                    enabled: type != SummaryChartType.candles || hasOhlc,
                    onTap: () {
                      onChanged(type);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SummaryChartTypeOption extends StatelessWidget {
  final SummaryChartType type;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _SummaryChartTypeOption({
    required this.type,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = enabled
        ? tokens.primaryAccent
        : colors.onSurfaceVariant.withValues(alpha: 0.62);
    return Material(
      color: selected ? tokens.selectedBackground : tokens.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? tokens.selectedBorder : tokens.cardBorder,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(type.icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      type.label,
                      style: TextStyle(
                        color: enabled ? Colors.white : const Color(0xFF7F899D),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!enabled)
                      const Text(
                        'Requiere OHLC',
                        style: TextStyle(
                          color: Color(0xFFAAB3C5),
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: tokens.primaryAccent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryMockupHero extends StatelessWidget {
  final PortfolioTotals totals;
  const _SummaryMockupHero({required this.totals});
  @override
  Widget build(BuildContext context) {
    final Color resultColor = pnlColor(totals.unrealizedPL);
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      height: 180,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[tokens.gradientStart, tokens.surfaceElevated],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.selectedBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.glowColor,
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: tokens.primaryAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 14,
                  color: tokens.primaryAccent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Valor de cartera',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _summaryMoney(totals.currentValue),
              maxLines: 1,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          Container(height: 1, color: tokens.divider),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'P&L no realizado',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _summaryMoney(totals.unrealizedPL),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: resultColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      totals.unrealizedPL >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      size: 14,
                      color: resultColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      totals.unrealizedPL >= 0 ? 'Positivo' : 'Negativo',
                      style: TextStyle(
                        color: resultColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMiniMetricGrid extends StatelessWidget {
  final PortfolioTotals totals;
  final CoinStats? leader;
  const _SummaryMiniMetricGrid({required this.totals, required this.leader});
  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      _SummaryMiniMetricCard(
        icon: Icons.savings_outlined,
        label: 'Invertido',
        value: _summaryMoney(totals.costBase).replaceFirst(' MXN', ''),
      ),
      _SummaryMiniMetricCard(
        icon: Icons.payments_outlined,
        label: 'P&L realizado',
        value: _summaryMoney(totals.realizedPL).replaceFirst(' MXN', ''),
        color: pnlColor(totals.realizedPL),
      ),
      _SummaryMiniMetricCard(
        icon: Icons.workspace_premium_outlined,
        label: 'Mayor posición',
        value: leader?.coin ?? 'Sin posición',
        color: const Color(0xFFF59E0B),
      ),
    ];
    return LayoutBuilder(
      builder: (_, BoxConstraints constraints) {
        final double availableWidth = constraints.maxWidth;
        final double cardWidth = (availableWidth - 16) / 3;
        return Row(
          children: <Widget>[
            SizedBox(width: cardWidth, child: items[0]),
            const SizedBox(width: 8),
            SizedBox(width: cardWidth, child: items[1]),
            const SizedBox(width: 8),
            SizedBox(width: cardWidth, child: items[2]),
          ],
        );
      },
    );
  }
}

class _SummaryMiniMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const…78575 tokens truncated…  subtitle!,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ChartsRangeSelector extends StatelessWidget {
  final List<SnapshotRangeOption> ranges;
  final SnapshotRangeOption selected;
  final ValueChanged<SnapshotRangeOption> onSelected;

  const _ChartsRangeSelector({
    required this.ranges,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 6;
        final double itemWidth =
            (constraints.maxWidth - gap * (ranges.length - 1)) / ranges.length;
        return Row(
          children: ranges.map((SnapshotRangeOption range) {
            final bool isSelected = range == selected;
            return Padding(
              padding: EdgeInsets.only(right: range == ranges.last ? 0 : gap),
              child: SizedBox(
                width: itemWidth,
                height: 46,
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: 'Periodo ${range.label}',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelected(range),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? tokens.selectedBackground
                              : tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? tokens.selectedBorder
                                : tokens.cardBorder,
                          ),
                        ),
                        child: Text(
                          range.label,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFFC0C9D8),
                            fontSize: 15,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ChartsMetricSelector extends StatelessWidget {
  final SnapshotMetric value;
  final ValueChanged<SnapshotMetric> onChanged;

  const _ChartsMetricSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SnapshotMetric>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.expand_more, color: tokens.primaryAccent),
          dropdownColor: tokens.menuBackground,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          items: SnapshotMetric.values
              .map(
                (SnapshotMetric metric) => DropdownMenuItem<SnapshotMetric>(
                  value: metric,
                  child: Text(metric.label),
                ),
              )
              .toList(),
          onChanged: (SnapshotMetric? metric) {
            if (metric != null) onChanged(metric);
          },
        ),
      ),
    );
  }
}

class _ChartsDataState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? detail;
  final Widget? actions;

  const _ChartsDataState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.detail,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _chartsTokenBox(
        context,
        color: tokens.surfaceElevated,
        radius: 14,
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, color: tokens.primaryAccent, size: 30),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 14),
          ),
          if (detail != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (actions != null) ...<Widget>[
            const SizedBox(height: 16),
            actions!,
          ],
        ],
      ),
    );
  }
}

class _ChartsReadoutGrid extends StatelessWidget {
  final SnapshotMetric metric;
  final double first;
  final double latest;
  final double minimum;
  final double maximum;
  final double change;
  final double? changePercent;
  final int snapshotCount;

  const _ChartsReadoutGrid({
    required this.metric,
    required this.first,
    required this.latest,
    required this.minimum,
    required this.maximum,
    required this.change,
    required this.changePercent,
    required this.snapshotCount,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 10;
        final double itemWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            _ChartsReadoutTile(
              width: itemWidth,
              label: 'Inicial',
              value: metric.format(first),
            ),
            _ChartsReadoutTile(
              width: itemWidth,
              label: 'Actual',
              value: metric.format(latest),
              valueColor: metric == SnapshotMetric.unrealizedPnl
                  ? pnlColor(latest)
                  : null,
            ),
            _ChartsReadoutTile(
              width: itemWidth,
              label: 'Máximo',
              value: metric.format(maximum),
            ),
            _ChartsReadoutTile(
              width: itemWidth,
              label: 'Mínimo',
              value: metric.format(minimum),
            ),
            _ChartsReadoutTile(
              width: constraints.maxWidth,
              label:
                  'Cambio · $snapshotCount ${snapshotCount == 1 ? 'snapshot' : 'snapshots'}',
              value:
                  '${metric.format(change)}${changePercent == null ? '' : ' · ${_chartsSignedPercent(changePercent!)}'}',
              valueColor: pnlColor(change),
              wide: true,
            ),
          ],
        );
      },
    );
  }
}

class _ChartsReadoutTile extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final Color? valueColor;
  final bool wide;

  const _ChartsReadoutTile({
    required this.width,
    required this.label,
    required this.value,
    this.valueColor,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _chartsTokenBox(
        context,
        color: tokens.surfaceElevated,
        radius: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFAAB3C5), fontSize: 13),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: wide ? 17 : 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioInteractiveChart extends StatefulWidget {
  final List<PortfolioSnapshot> snapshots;
  final List<double> values;
  final SnapshotMetric metric;
  final Color color;
  final SummaryChartType chartType;

  const _PortfolioInteractiveChart({
    required this.snapshots,
    required this.values,
    required this.metric,
    required this.color,
    required this.chartType,
  });

  @override
  State<_PortfolioInteractiveChart> createState() =>
      _PortfolioInteractiveChartState();
}

class _PortfolioInteractiveChartState
    extends State<_PortfolioInteractiveChart> {
  int? _selectedIndex;
  Timer? _dismissTimer;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PortfolioInteractiveChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex != null && _selectedIndex! >= widget.snapshots.length) {
      _selectedIndex = null;
    }
  }

  void _select(Offset localPosition, double width) {
    _dismissTimer?.cancel();
    final double usableWidth = math.max(1, width - 74);
    final double normalized = ((localPosition.dx - 54) / usableWidth).clamp(
      0.0,
      1.0,
    );
    final int index = (normalized * (widget.snapshots.length - 1)).round();
    if (index != _selectedIndex) setState(() => _selectedIndex = index);
  }

  void _dismissSelectionSoon() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _selectedIndex = null);
    });
  }

  void _dismissSelection() {
    _dismissTimer?.cancel();
    if (_selectedIndex != null) setState(() => _selectedIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double height = (width * 1.04).clamp(355.0, 380.0);
        final int? selectedIndex = _selectedIndex;
        final double tooltipWidth = math.min(210, math.max(156, width - 20));
        final double selectedX = selectedIndex == null
            ? 0
            : 54 +
                  math.max(1, width - 74) *
                      selectedIndex /
                      (widget.snapshots.length - 1);
        final double tooltipLeft = selectedIndex == null
            ? 0
            : (selectedX - tooltipWidth / 2).clamp(
                8.0,
                math.max(8.0, width - tooltipWidth - 8),
              );

        return SizedBox(
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails details) =>
                _select(details.localPosition, width),
            onTapUp: (_) => _dismissSelectionSoon(),
            onTapCancel: _dismissSelection,
            onHorizontalDragStart: (_) => _dismissTimer?.cancel(),
            onHorizontalDragUpdate: (DragUpdateDetails details) =>
                _select(details.localPosition, width),
            onHorizontalDragEnd: (_) => _dismissSelectionSoon(),
            onHorizontalDragCancel: _dismissSelection,
            child: Stack(
              children: <Widget>[
                SnapshotLineChart(
                  snapshots: widget.snapshots,
                  height: height,
                  includeZero: widget.metric != SnapshotMetric.btcDominance,
                  chartType: widget.chartType,
                  series: <SnapshotChartSeries>[
                    SnapshotChartSeries(
                      label: widget.metric.label,
                      color: widget.color,
                      values: widget.values,
                      valueFormatter: widget.metric.shortFormat,
                    ),
                  ],
                ),
                if (selectedIndex != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ChartsSelectionPainter(
                          index: selectedIndex,
                          pointCount: widget.snapshots.length,
                          chartType: widget.chartType,
                        ),
                      ),
                    ),
                  ),
                if (selectedIndex != null)
                  Positioned(
                    top: 10,
                    left: tooltipLeft,
                    width: tooltipWidth,
                    child: _ChartsPointTooltip(
                      snapshot: widget.snapshots[selectedIndex],
                      value: widget.values[selectedIndex],
                      previousValue: selectedIndex > 0
                          ? widget.values[selectedIndex - 1]
                          : null,
                      metric: widget.metric,
                      color: widget.color,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChartsSelectionPainter extends CustomPainter {
  final int index;
  final int pointCount;
  final SummaryChartType chartType;

  const _ChartsSelectionPainter({
    required this.index,
    required this.pointCount,
    required this.chartType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double x = pointCount == 1
        ? size.width / 2
        : 54 + (size.width - 74) * index / (pointCount - 1);
    final Paint paint = Paint()
      ..color = _chartsPurple.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    if (chartType == SummaryChartType.columns) {
      final double slotWidth = (size.width - 74) / pointCount;
      final Rect highlight = Rect.fromLTWH(
        x - slotWidth / 2,
        12,
        slotWidth,
        size.height - 42,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(highlight, const Radius.circular(4)),
        Paint()..color = _chartsPurple.withValues(alpha: 0.10),
      );
    }
    const double dash = 5;
    for (double y = 12; y < size.height - 30; y += dash * 2) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dash), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartsSelectionPainter oldDelegate) {
    return oldDelegate.index != index ||
        oldDelegate.pointCount != pointCount ||
        oldDelegate.chartType != chartType;
  }
}

class _ChartsPointTooltip extends StatelessWidget {
  final PortfolioSnapshot snapshot;
  final double value;
  final double? previousValue;
  final SnapshotMetric metric;
  final Color color;

  const _ChartsPointTooltip({
    required this.snapshot,
    required this.value,
    required this.previousValue,
    required this.metric,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final double? variation = previousValue == null
        ? null
        : value - previousValue!;
    final String seriesLabel = metric == SnapshotMetric.portfolioValue
        ? 'Cartera total'
        : metric.label;
    return Semantics(
      label: '${longDate(snapshot.createdAt)}, ${metric.format(value)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _chartsPurple.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              longDate(snapshot.createdAt),
              style: const TextStyle(
                color: Color(0xFFAAB3C5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              seriesLabel,
              style: const TextStyle(
                color: Color(0xFFC4B5FD),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                metric.format(value),
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (variation != null) ...<Widget>[
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Variación: ${metric.format(variation)}',
                  style: TextStyle(
                    color: pnlColor(variation),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ChartsTab extends StatelessWidget {
  final Map<String, CoinStats> stats;
  final PortfolioTotals totals;
  final List<PortfolioSnapshot> snapshots;
  final SummaryChartType chartType;
  final ValueChanged<SummaryChartType> onChartTypeChanged;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;

  const ChartsTab({
    super.key,
    required this.stats,
    required this.totals,
    required this.snapshots,
    required this.chartType,
    required this.onChartTypeChanged,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
  });

  @override
  Widget build(BuildContext context) {
    final List<CoinStats> active =
        stats.values.where((CoinStats s) => s.currentValue > 0).toList()..sort(
          (CoinStats a, CoinStats b) =>
              b.currentValue.compareTo(a.currentValue),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: <Widget>[
        const _ChartsPageHeader(),
        AnalyticsControlPanel(
          snapshots: snapshots,
          totals: totals,
          chartType: chartType,
          onChartTypeChanged: onChartTypeChanged,
          onSaveSnapshot: onSaveSnapshot,
          onViewSnapshots: onViewSnapshots,
        ),
        const SizedBox(height: 14),
        _ChartsSectionPanel(
          title: 'Lectura actual',
          subtitle:
              'Cifras vigentes de la cartera para contextualizar el histórico.',
          child: _ChartsCurrentMetrics(stats: stats, totals: totals),
        ),
        const SizedBox(height: 14),
        _ChartsSectionPanel(
          title: 'Composición actual',
          subtitle: totals.currentValue <= 0
              ? 'Sin valor cargado para graficar.'
              : 'Valor total: ${_chartsMoney(totals.currentValue)}',
          child: active.isEmpty
              ? const _ChartsDataState(
                  icon: Icons.pie_chart_outline,
                  title: 'Sin valor de cartera para graficar',
                  subtitle:
                      'Carga precios y movimientos para activar una '
                      'lectura visual premium.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ...active.map((CoinStats stat) {
                      final double share = totals.currentValue <= 0
                          ? 0.0
                          : stat.currentValue / totals.currentValue;
                      return AllocationBar(
                        label: stat.coin,
                        value: _chartsMoney(stat.currentValue),
                        share: share,
                        result: stat.unrealizedPL,
                      );
                    }),
                    const Divider(height: 26, color: Color(0x20FFFFFF)),
                    const Text(
                      'Resultado no realizado por moneda',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...active.map((CoinStats stat) {
                      final double maxAbs = active.fold<double>(
                        1,
                        (double maxValue, CoinStats item) =>
                            math.max(maxValue, item.unrealizedPL.abs()),
                      );
                      return ResultBar(
                        label: stat.coin,
                        amount: stat.unrealizedPL,
                        intensity: stat.unrealizedPL.abs() / maxAbs,
                      );
                    }),
                  ],
                ),
        ),
        if (snapshots.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              'Comparativas históricas',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SnapshotTrendPanel(snapshots: snapshots, chartType: chartType),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onViewSnapshots,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Administrar instantáneas'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChartsCurrentMetrics extends StatelessWidget {
  final Map<String, CoinStats> stats;
  final PortfolioTotals totals;

  const _ChartsCurrentMetrics({required this.stats, required this.totals});

  @override
  Widget build(BuildContext context) {
    final List<_ChartsCurrentMetric> metrics = <_ChartsCurrentMetric>[
      _ChartsCurrentMetric(
        label: 'Valor de cartera',
        value: _chartsMoney(totals.currentValue),
        icon: Icons.account_balance_wallet_outlined,
      ),
      _ChartsCurrentMetric(
        label: 'Invertido',
        value: _chartsMoney(totals.costBase),
        icon: Icons.savings_outlined,
      ),
      _ChartsCurrentMetric(
        label: 'P&L no realizado',
        value: _chartsMoney(totals.unrealizedPL),
        icon: Icons.trending_up,
        color: pnlColor(totals.unrealizedPL),
      ),
      _ChartsCurrentMetric(
        label: 'Dominancia BTC',
        value: _btcDominance(stats, totals),
        icon: Icons.currency_bitcoin,
        color: const Color(0xFFF59E0B),
      ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 10;
        final double width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map(
                (_ChartsCurrentMetric metric) =>
                    _ChartsCurrentMetricTile(metric: metric, width: width),
              )
              .toList(),
        );
      },
    );
  }
}

class _ChartsCurrentMetric {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _ChartsCurrentMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
}

class _ChartsCurrentMetricTile extends StatelessWidget {
  final _ChartsCurrentMetric metric;
  final double width;

  const _ChartsCurrentMetricTile({required this.metric, required this.width});

  @override
  Widget build(BuildContext context) {
    final Color valueColor = metric.color ?? Colors.white;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(12),
      decoration: _chartsBox(color: _chartsElevated, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            metric.icon,
            size: 18,
            color: metric.color ?? const Color(0xFFC4B5FD),
          ),
          const SizedBox(height: 7),
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFAAB3C5), fontSize: 13),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              style: TextStyle(
                color: valueColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AllocationBar extends StatelessWidget {
  final String label;
  final String value;
  final double share;
  final double result;

  const AllocationBar({
    super.key,
    required this.label,
    required this.value,
    required this.share,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text('${pct(share * 100)} · $value'),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: share.clamp(0.0, 1.0),
            minHeight: 10,
            color: pnlColor(result),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}

class ResultBar extends StatelessWidget {
  final String label;
  final double amount;
  final double intensity;

  const ResultBar({
    super.key,
    required this.label,
    required this.amount,
    required this.intensity,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: intensity.clamp(0.0, 1.0),
              minHeight: 10,
              color: pnlColor(amount),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(
              _chartsMoney(amount),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: pnlColor(amount),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialResetScreen extends StatefulWidget {
  final bool hasCloudState;
  final Future<bool> Function() onExportBackup;
  final Future<bool> Function() onReset;

  const _FinancialResetScreen({
    required this.hasCloudState,
    required this.onExportBackup,
    required this.onReset,
  });

  @override
  State<_FinancialResetScreen> createState() => _FinancialResetScreenState();
}

class _FinancialResetScreenState extends State<_FinancialResetScreen> {
  final TextEditingController _confirmationController = TextEditingController();
  bool _backupReady = false;
  bool _exportingBackup = false;
  bool _resetInProgress = false;

  bool get _confirmationReady =>
      _confirmationController.text.trim() == 'RESTABLECER';

  bool get _canReset => _backupReady && _confirmationReady && !_resetInProgress;

  @override
  void initState() {
    super.initState();
    _confirmationController.addListener(_onConfirmationChanged);
  }

  @override
  void dispose() {
    _confirmationController.removeListener(_onConfirmationChanged);
    _confirmationController.dispose();
    super.dispose();
  }

  void _onConfirmationChanged() => setState(() {});

  Future<void> _generateBackup() async {
    if (_exportingBackup || _resetInProgress) return;
    setState(() => _exportingBackup = true);
    final bool exported = await widget.onExportBackup();
    if (!mounted) return;
    setState(() {
      _backupReady = exported;
      _exportingBackup = false;
    });
  }

  Future<void> _resetFinancialData() async {
    if (!_canReset) return;
    FocusScope.of(context).unfocus();
    if (widget.hasCloudState) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Reset local con nube activa'),
          content: const Text(
            'Este reset borrará datos locales, pero no eliminará tu estado '
            'guardado en Firebase ni tu copia de Google Drive.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continuar reset local'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _resetInProgress = true);
    final bool completed = await widget.onReset();
    if (!mounted) return;
    if (completed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _resetInProgress = false);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Restablecer datos financieros')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            CardPanel(
              title: 'Acción permanente',
              subtitle:
                  'Borra datos financieros locales. Conserva tema y preferencias visuales.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const InfoLine(
                    'Se borra',
                    'Movimientos, precios y snapshots',
                  ),
                  const InfoLine('También se borra', 'Alertas y referencias'),
                  const InfoLine('Se conserva', 'Tema y preferencias visuales'),
                  if (widget.hasCloudState)
                    const InfoLine(
                      'Firebase',
                      'La copia en Firebase no se borra con este reset local.',
                    ),
                  if (widget.hasCloudState)
                    const InfoLine(
                      'Google Drive',
                      'La copia de Google Drive tampoco se borra.',
                    ),
                ],
              ),
            ),
            CardPanel(
              title: '1. Copia de seguridad',
              subtitle:
                  'Primero crea una copia de seguridad antes de permitir el restablecimiento.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _exportingBackup || _resetInProgress
                        ? null
                        : _generateBackup,
                    icon: _exportingBackup
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.backup_outlined),
                    label: Text(
                      _exportingBackup
                          ? 'Creando copia...'
                          : 'Crear copia de seguridad',
                    ),
                  ),
                  const SizedBox(height: 12),
                  InfoLine(
                    'Copia previa',
                    _backupReady ? 'Listo para continuar' : 'Requerida',
                    emphasized: true,
                    valueColor: _backupReady ? colors.primary : colors.error,
                  ),
                ],
              ),
            ),
            CardPanel(
              title: '2. Confirmación fuerte',
              subtitle:
                  'Escribe RESTABLECER exactamente para habilitar el botón final.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _confirmationController,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Escribe RESTABLECER',
                      prefixIcon: Icon(Icons.warning_amber_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: _resetInProgress
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _canReset ? _resetFinancialData : null,
                          style: _canReset
                              ? FilledButton.styleFrom(
                                  backgroundColor: colors.error,
                                  foregroundColor: colors.onError,
                                )
                              : null,
                          icon: _resetInProgress
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_forever_outlined),
                          label: Text(
                            _resetInProgress
                                ? 'Restableciendo...'
                                : 'Restablecer datos financieros',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MoreTab extends StatelessWidget {
  final PortfolioTotals totals;
  final DateTime? pricesUpdatedAt;
  final AppVisualMode visualMode;
  final AppThemeStyle themeStyle;
  final int movementCount;
  final int movementsWithIdCount;
  final int snapshotCount;
  final DateTime? latestSnapshot;
  final int activeCoins;
  final List<String> financialErrors;
  final SnapshotAutomationMode snapshotAutomationMode;
  final SnapshotRetention snapshotRetention;
  final int pricesAvailableCount;
  final int pricesTotalCount;
  final List<String> missingPriceCoins;
  final List<String> manualPriceCoins;
  final bool refreshPricesOnOpen;
  final bool refreshPricesAfterMovement;
  final PriceRefreshForegroundMode priceRefreshForegroundMode;
  final bool automaticLocalAlertsEnabled;
  final int automaticLocalAlertsIntervalMinutes;
  final bool notificationsAllowed;
  final String firebaseStatus;
  final bool analyticsEnabled;
  final bool crashlyticsEnabled;
  final String? firebaseAuthEmail;
  final String? firebaseAuthDisplayName;
  final String? firebaseAuthUid;
  final String cloudProfileStatus;
  final bool isCloudProfilePreparing;
  final bool hasLocalFirebaseDeviceId;
  final DateTime? cloudStateUploadedAt;
  final DateTime? cloudStateDownloadedAt;
  final String? googleAccountEmail;
  final String? googleAccountDisplayName;
  final DateTime? googleDriveLastConnectedAt;
  final bool googleDriveWasConnected;
  final GoogleDriveSessionStatus googleDriveSessionStatus;
  final bool isGoogleDriveAuthorized;
  final DateTime? googleDriveBackupUpdatedAt;
  final bool isFirebaseAuthBusy;
  final bool isCloudUploading;
  final bool isCloudDownloading;
  final bool isGoogleConnecting;
  final bool isGoogleDriveCreating;
  final bool isGoogleDriveRestoring;
  final bool isRefreshingPrices;
  final int chartDataCount;
  final List<String> motorCoins;
  final double motorSellFeePercent;
  final VoidCallback onOpenCharts;
  final VoidCallback onOpenMovements;
  final VoidCallback onOpenPriceSettings;
  final VoidCallback onOpenThemeSettings;
  final VoidCallback onOpenPortfolioSettings;
  final VoidCallback onOpenAlerts;
  final VoidCallback onExportMovementsCsv;
  final VoidCallback onExportSummaryCsv;
  final VoidCallback onExportSnapshotsCsv;
  final VoidCallback onExportMovementsJson;
  final VoidCallback onExportSnapshotsJson;
  final VoidCallback onExportPortfolioSummaryJson;
  final VoidCallback onExportXlsx;
  final VoidCallback onExportPdf;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;
  final VoidCallback onImportBackupFile;
  final VoidCallback onSignInFirebaseWithGoogle;
  final VoidCallback onSignOutFirebase;
  final VoidCallback onPrepareCloudProfile;
  final VoidCallback onUploadFinancialStateToFirebase;
  final VoidCallback onDownloadFinancialStateFromFirebase;
  final VoidCallback onConnectGoogleDrive;
  final VoidCallback onReconnectGoogleDrive;
  final VoidCallback onDisconnectGoogleDrive;
  final VoidCallback onCreateGoogleDriveBackup;
  final VoidCallback onRestoreGoogleDriveBackup;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;
  final ValueChanged<SnapshotAutomationMode> onSnapshotAutomationModeChanged;
  final ValueChanged<SnapshotRetention> onSnapshotRetentionChanged;
  final VoidCallback onResetPriceAlertReferences;
  final VoidCallback onOpenFinancialReset;
  final ValueChanged<bool> onAnalyticsConsentChanged;
  final ValueChanged<bool> onCrashlyticsConsentChanged;

  const MoreTab({
    super.key,
    required this.totals,
    required this.pricesUpdatedAt,
    required this.visualMode,
    required this.themeStyle,
    required this.movementCount,
    required this.movementsWithIdCount,
    required this.snapshotCount,
    required this.latestSnapshot,
    required this.activeCoins,
    required this.financialErrors,
    required this.snapshotAutomationMode,
    required this.snapshotRetention,
    required this.pricesAvailableCount,
    required this.pricesTotalCount,
    required this.missingPriceCoins,
    required this.manualPriceCoins,
    required this.refreshPricesOnOpen,
    required this.refreshPricesAfterMovement,
    required this.priceRefreshForegroundMode,
    required this.automaticLocalAlertsEnabled,
    required this.automaticLocalAlertsIntervalMinutes,
    required this.notificationsAllowed,
    required this.firebaseStatus,
    required this.analyticsEnabled,
    required this.crashlyticsEnabled,
    required this.firebaseAuthEmail,
    required this.firebaseAuthDisplayName,
    required this.firebaseAuthUid,
    required this.cloudProfileStatus,
    required this.isCloudProfilePreparing,
    required this.hasLocalFirebaseDeviceId,
    required this.cloudStateUploadedAt,
    required this.cloudStateDownloadedAt,
    required this.googleAccountEmail,
    required this.googleAccountDisplayName,
    required this.googleDriveLastConnectedAt,
    required this.googleDriveWasConnected,
    required this.googleDriveSessionStatus,
    required this.isGoogleDriveAuthorized,
    required this.googleDriveBackupUpdatedAt,
    required this.isFirebaseAuthBusy,
    required this.isCloudUploading,
    required this.isCloudDownloading,
    required this.isGoogleConnecting,
    required this.isGoogleDriveCreating,
    required this.isGoogleDriveRestoring,
    required this.isRefreshingPrices,
    required this.chartDataCount,
    required this.motorCoins,
    required this.motorSellFeePercent,
    required this.onOpenCharts,
    required this.onOpenMovements,
    required this.onOpenPriceSettings,
    required this.onOpenThemeSettings,
    required this.onOpenPortfolioSettings,
    required this.onOpenAlerts,
    required this.onExportMovementsCsv,
    required this.onExportSummaryCsv,
    required this.onExportSnapshotsCsv,
    required this.onExportMovementsJson,
    required this.onExportSnapshotsJson,
    required this.onExportPortfolioSummaryJson,
    required this.onExportXlsx,
    required this.onExportPdf,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onImportBackupFile,
    required this.onSignInFirebaseWithGoogle,
    required this.onSignOutFirebase,
    required this.onPrepareCloudProfile,
    required this.onUploadFinancialStateToFirebase,
    required this.onDownloadFinancialStateFromFirebase,
    required this.onConnectGoogleDrive,
    required this.onReconnectGoogleDrive,
    required this.onDisconnectGoogleDrive,
    required this.onCreateGoogleDriveBackup,
    required this.onRestoreGoogleDriveBackup,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
    required this.onSnapshotAutomationModeChanged,
    required this.onSnapshotRetentionChanged,
    required this.onResetPriceAlertReferences,
    required this.onOpenFinancialReset,
    required this.onAnalyticsConsentChanged,
    required this.onCrashlyticsConsentChanged,
  });

  static const String _priceSource = 'CoinGecko';
  bool get firebaseAuthConnected => firebaseAuthUid != null;
  String get analyticsStatus => analyticsEnabled ? 'Activado' : 'Desactivado';
  String get crashlyticsStatus =>
      crashlyticsEnabled ? 'Activado' : 'Desactivado';
  String get firebaseAuthAccountLabel =>
      firebaseAuthEmail ?? firebaseAuthDisplayName ?? 'Cuenta Google';
  String get cloudStateUploadLabel => cloudStateUploadedAt == null
      ? 'Sin subir'
      : longDate(cloudStateUploadedAt!);
  String get cloudStateDownloadLabel => cloudStateDownloadedAt == null
      ? 'Sin descargar'
      : longDate(cloudStateDownloadedAt!);
  String get googleDriveAccountLabel =>
      googleAccountEmail ?? googleAccountDisplayName ?? 'cuenta Google';
  String get googleDriveLastConnectionLabel =>
      googleDriveLastConnectedAt == null
      ? 'sin fecha local'
      : longDate(googleDriveLastConnectedAt!.toLocal());
  String get googleDriveAccountStatusLabel => googleDriveLastConnectedAt == null
      ? 'Cuenta: $googleDriveAccountLabel - Drive activo'
      : 'Cuenta: $googleDriveAccountLabel - Ultima conexion: $googleDriveLastConnectionLabel';
  bool get googleDriveHasKnownAccount =>
      googleDriveWasConnected || googleAccountEmail != null;
  bool get googleDriveVisuallyConnected =>
      googleDriveHasKnownAccount &&
      googleDriveSessionStatus != GoogleDriveSessionStatus.accountDisconnected;
  bool get googleDriveVerificationPending =>
      googleDriveSessionStatus ==
      GoogleDriveSessionStatus.localPendingVerification;
  bool get googleDriveVerificationFailed =>
      googleDriveSessionStatus == GoogleDriveSessionStatus.temporaryError;
  bool get googleDriveActionRequiresVerification =>
      googleDriveVerificationPending || googleDriveVerificationFailed;
  bool get googleDriveConnected =>
      googleDriveHasKnownAccount &&
      (googleDriveSessionStatus == GoogleDriveSessionStatus.accountConnected ||
          googleDriveSessionStatus ==
              GoogleDriveSessionStatus.driveAuthorized ||
          googleDriveSessionStatus ==
              GoogleDriveSessionStatus.driveAuthorizationRequired);
  bool get googleDriveLocalPending =>
      googleDriveSessionStatus ==
      GoogleDriveSessionStatus.localPendingVerification;
  bool get googleDriveSessionChecking =>
      googleDriveSessionStatus == GoogleDriveSessionStatus.accountChecking;
  bool get googleDriveAuthRequired =>
      googleDriveSessionStatus ==
      GoogleDriveSessionStatus.driveAuthorizationRequired;
  bool get googleDriveTemporaryError =>
      googleDriveSessionStatus == GoogleDriveSessionStatus.temporaryError;
  bool get googleDriveBusy =>
      googleDriveSessionChecking ||
      isGoogleConnecting ||
      isGoogleDriveCreating ||
      isGoogleDriveRestoring;
  String get googleDriveBackupLabel => googleDriveBackupUpdatedAt == null
      ? 'Sin copia en Drive'
      : longDate(googleDriveBackupUpdatedAt!.toLocal());
  String get googleDriveBackupStatus => googleDriveBackupUpdatedAt == null
      ? 'Sin copia en Drive'
      : 'Última copia en Drive: ${longDate(googleDriveBackupUpdatedAt!.toLocal())}';

  @override
  Widget build(BuildContext context) {
    return PremiumScaffoldSurface(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          _CommandCenterHeader(
            pricesUpdatedAt: pricesUpdatedAt,
            priceSource: _priceSource,
            googleDriveConnected: googleDriveVisuallyConnected,
            googleDriveBackupUpdatedAt: googleDriveBackupUpdatedAt,
            visualMode: visualMode,
            themeStyle: themeStyle,
          ),
          const SizedBox(height: 14),
          _CommandSection(
            title: 'CUENTA Y NUBE',
            children: <Widget>[
              _MoreActionTile(
                icon: Icons.account_circle_outlined,
                title: 'Cuenta en la nube',
                subtitle: firebaseAuthConnected
                    ? '$firebaseAuthAccountLabel · Perfil $cloudProfileStatus'
                    : 'Google opcional para nube manual.',
                badge: firebaseAuthConnected ? 'Conectado' : 'Sin cuenta',
                loading:
                    isFirebaseAuthBusy ||
                    isCloudProfilePreparing ||
                    isCloudUploading ||
                    isCloudDownloading,
                onTap: () => _showCloudAccountActions(context),
              ),
            ],
          ),
          _CommandSection(
            title: 'DATOS Y RESPALDOS',
            children: <Widget>[
              _MoreActionTile(
                icon: Icons.cloud_done_outlined,
                title: googleDriveVisuallyConnected
                    ? 'Google Drive conectado'
                    : 'Google Drive no conectado',
                subtitle: googleDriveSessionChecking
                    ? googleDriveHasKnownAccount
                          ? 'Restaurando Google Drive... Cuenta anterior: $googleDriveAccountLabel'
                          : 'Comprobando sesion de Google Drive...'
                    : googleDriveLocalPending
                    ? googleDriveAccountStatusLabel
                    : googleDriveAuthRequired
                    ? 'Cuenta: $googleDriveAccountLabel - Falta autorizar Drive.'
                    : googleDriveTemporaryError
                    ? googleDriveHasKnownAccount
                          ? 'Cuenta: $googleDriveAccountLabel - No se pudo verificar ahora; conexion local conservada.'
                          : 'No se pudo comprobar la sesion. Reintenta al usar Drive.'
                    : isGoogleDriveAuthorized
                    ? '$googleDriveAccountLabel - $googleDriveBackupLabel'
                    : googleDriveConnected
                    ? '$googleDriveAccountLabel - Falta autorizar Drive'
                    : 'Crea y restaura copias manuales.',
                badge: googleDriveSessionChecking
                    ? googleDriveHasKnownAccount
                          ? 'Restaurando'
                          : 'Comprobando'
                    : isGoogleDriveAuthorized
                    ? 'Conectado'
                    : googleDriveLocalPending
                    ? 'Conectado'
                    : googleDriveConnected || googleDriveAuthRequired
                    ? 'Autorizar'
                    : googleDriveTemporaryError
                    ? googleDriveHasKnownAccount
                          ? 'Conectado'
                          : 'Revisar'
                    : 'Sin conectar',
                loading: googleDriveBusy,
                onTap: () => _showGoogleDriveActions(context),
              ),
              _MoreActionTile(
                icon: Icons.backup_outlined,
                title: 'Copia local',
                subtitle: 'Backup local de movimientos, precios y snapshots.',
                onTap: onExportBackup,
              ),
              _MoreActionTile(
                icon: Icons.upload_file_outlined,
                title: 'Restaurar copia',
                subtitle: 'Importar backup con confirmación previa.',
                onTap: () => _showImportActions(context),
              ),
            ],
          ),
          _CommandSection(
            title: 'INSTANTÁNEAS',
            children: <Widget>[
              _MoreActionTile(
                icon: Icons.photo_library_outlined,
                title: 'Instantáneas',
                subtitle: snapshotCount == 1
                    ? '1 instantánea guardada · evolución y controles'
                    : '$snapshotCount instantáneas guardadas · evolución y controles',
                onTap: () => _showSnapshotActions(context),
              ),
            ],
          ),
          _CommandSection(
            title: 'EXPORTAR',
            children: <Widget>[
              _MoreActionTile(
                icon: Icons.receipt_long_outlined,
                title: 'Historial de movimientos',
                subtitle: movementCount == 1
                    ? '1 movimiento · OCR editable, auditoría y edición'
                    : '$movementCount movimientos · OCR editable, auditoría y edición',
                badge: 'Clave',
                onTap: onOpenMovements,
              ),
              _MoreActionTile(
                icon: Icons.table_chart_outlined,
                title: 'Reportes',
                subtitle: 'CSV, JSON, PDF y XLSX para respaldo o reporte.',
                badge: 'CSV/JSON',
                onTap: () => _showDataActions(context),
              ),
            ],
          ),
          _CommandSection(
            title: 'DIAGNÓSTICO',
            children: <Widget>[
              _MoreActionTile(
                icon: Icons.health_and_safety_outlined,
                title: 'Estado del sistema',
                subtitle: 'Datos locales, nube manual, alertas y precios.',
                badge: pricesUpdatedAt == null ? 'Sin precios' : 'OK',
                onTap: () => _showDiagnostics(context),
              ),
            ],
          ),
          _CommandSection(
            title: 'ACERCA DE',
            children: <Widget>[
              _MoreActionTile(
                icon: Icons.info_outline,
                title: 'Acerca de CriptoControlMx',
                subtitle: 'Información, privacidad local y aviso financiero.',
                badge: 'Local',
                onTap: () => _showAboutApp(context),
              ),
            ],
          ),
          _CommandSection(
            title: 'PERSONALIZACIÓN',
            children: <Widget>[
              _MoreActionTile(
                icon: Icons.palette_outlined,
                title: 'Tema',
                subtitle: 'Modo ${visualMode.label} · ${themeStyle.label}',
                onTap: onOpenThemeSettings,
              ),
              _MoreActionTile(
                icon: Icons.sync_outlined,
                title: 'Actualización de precios',
                subtitle: 'Apertura, movimientos e intervalo en pantalla',
                onTap: onOpenPriceSettings,
              ),
              _MoreActionTile(
                icon: Icons.view_agenda_outlined,
                title: 'Resumen de cartera',
                subtitle: 'Posiciones visibles y orden del portafolio',
                onTap: onOpenPortfolioSettings,
              ),
            ],
          ),
          _CommandSection(
            title: 'PRIVACIDAD',
            children: <Widget>[
              _PrivacyMonitoringCard(
                analyticsEnabled: analyticsEnabled,
                crashlyticsEnabled: crashlyticsEnabled,
                onAnalyticsChanged: onAnalyticsConsentChanged,
                onCrashlyticsChanged: onCrashlyticsConsentChanged,
              ),
            ],
          ),
          _CommandSection(
            title: 'ZONA DE RIESGO',
            children: <Widget>[
              _MoreActionTile(
                icon: Icons.restart_alt_outlined,
                title: 'Restablecer datos financieros',
                subtitle:
                    'Borra datos financieros con copia previa y confirmación.',
                badge: 'Peligroso',
                onTap: onOpenFinancialReset,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCloudAccountActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CommandActionSheet(
        title: 'Cuenta en la nube',
        actions: <_SheetAction>[
          _SheetAction(
            icon: firebaseAuthConnected
                ? Icons.verified_user_outlined
                : Icons.account_circle_outlined,
            title: firebaseAuthConnected
                ? 'Estado: Conectado'
                : 'Estado: Sin cuenta conectada',
            subtitle: firebaseAuthConnected
                ? 'Email: ${firebaseAuthEmail ?? 'sin email visible'}'
                : 'Inicia sesión con Google para preparar el acceso en la nube.',
            onTap: null,
          ),
          const _SheetAction(
            icon: Icons.cloud_off_outlined,
            title: 'Sincronización manual',
            subtitle:
                'Firebase no se sincroniza automáticamente. Tú decides cuándo subir o descargar estado.',
            onTap: null,
          ),
          _SheetAction(
            icon: Icons.history_outlined,
            title: 'Última subida: $cloudStateUploadLabel',
            subtitle: 'Subida manual disponible; reemplaza la copia cloud.',
            onTap: null,
          ),
          _SheetAction(
            icon: Icons.history_toggle_off_outlined,
            title: 'Última descarga: $cloudStateDownloadLabel',
            subtitle: 'Descarga manual disponible; reemplaza datos locales.',
            onTap: null,
          ),
          _SheetAction(
            icon: isCloudUploading
                ? Icons.hourglass_top_outlined
                : Icons.cloud_upload_outlined,
            title: isCloudUploading ? 'Subiendo...' : 'Subir estado a la nube',
            subtitle: firebaseAuthConnected
                ? 'Subida manual; reemplaza la copia cloud anterior.'
                : 'Inicia sesión para usar la nube.',
            onTap:
                firebaseAuthConnected &&
                    !isCloudUploading &&
                    !isCloudProfilePreparing
                ? onUploadFinancialStateToFirebase
                : null,
          ),
          _SheetAction(
            icon: isCloudDownloading
                ? Icons.hourglass_top_outlined
                : Icons.cloud_download_outlined,
            title: isCloudDownloading
                ? 'Descargando...'
                : 'Descargar estado desde la nube',
            subtitle: firebaseAuthConnected
                ? 'Reemplaza datos locales con confirmación previa. Crea una copia antes de continuar.'
                : 'Inicia sesión para usar la nube.',
            onTap: firebaseAuthConnected && !isCloudDownloading
                ? onDownloadFinancialStateFromFirebase
                : null,
          ),
          _SheetAction(
            icon: isCloudProfilePreparing
                ? Icons.hourglass_top_outlined
                : Icons.cloud_done_outlined,
            title: 'Perfil cloud: $cloudProfileStatus',
            subtitle: firebaseAuthConnected
                ? isCloudProfilePreparing
                      ? 'Preparando users/{uid} y el registro del dispositivo.'
                      : 'Toca para preparar o reintentar el perfil cloud.'
                : 'Inicia sesión para preparar el perfil.',
            onTap: firebaseAuthConnected && !isCloudProfilePreparing
                ? onPrepareCloudProfile
                : null,
          ),
          _SheetAction(
            icon: Icons.phone_android_outlined,
            title: 'DeviceId local',
            subtitle: hasLocalFirebaseDeviceId ? 'Registrado' : 'No registrado',
            onTap: null,
          ),
          if (firebaseAuthConnected && firebaseAuthDisplayName != null)
            _SheetAction(
              icon: Icons.badge_outlined,
              title: 'Nombre',
              subtitle: firebaseAuthDisplayName!,
              onTap: null,
            ),
          if (firebaseAuthConnected && firebaseAuthUid != null)
            _SheetAction(
              icon: Icons.developer_mode_outlined,
              title: 'UID diagnóstico',
              subtitle: _maskedIdentifier(firebaseAuthUid!),
              onTap: null,
            ),
          _SheetAction(
            icon: isFirebaseAuthBusy
                ? Icons.hourglass_top_outlined
                : firebaseAuthConnected
                ? Icons.logout_outlined
                : Icons.login_outlined,
            title: isFirebaseAuthBusy
                ? 'Procesando...'
                : firebaseAuthConnected
                ? 'Cerrar sesión'
                : 'Iniciar sesión con Google',
            subtitle: firebaseAuthConnected
                ? 'Cierra solo Firebase Auth; Google Drive conserva su conexión.'
                : 'No sube ni descarga datos todavía.',
            onTap: isFirebaseAuthBusy || isCloudProfilePreparing
                ? null
                : firebaseAuthConnected
                ? onSignOutFirebase
                : onSignInFirebaseWithGoogle,
          ),
        ],
      ),
    );
  }

  void _showGoogleDriveActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CommandActionSheet(
        title: googleDriveVisuallyConnected
            ? 'Google Drive conectado'
            : 'Google Drive',
        actions: <_SheetAction>[
          _SheetAction(
            icon: isGoogleDriveAuthorized
                ? Icons.link_off_outlined
                : Icons.cloud_sync_outlined,
            title: googleDriveSessionChecking
                ? googleDriveHasKnownAccount
                      ? 'Restaurando sesion'
                      : 'Comprobando sesion'
                : isGoogleConnecting
                ? 'Verificando conexion'
                : isGoogleDriveAuthorized
                ? 'Desconectar'
                : googleDriveLocalPending
                ? 'Verificar conexion'
                : googleDriveTemporaryError
                ? 'Reconectar Google Drive'
                : googleDriveConnected
                ? 'Autorizar Google Drive'
                : 'Conectar Google Drive',
            subtitle: googleDriveSessionChecking
                ? googleDriveHasKnownAccount
                      ? 'Cuenta anterior: $googleDriveAccountLabel. Ultima conexion: $googleDriveLastConnectionLabel.'
                      : 'Comprobando Google Drive sin abrir el selector de cuenta.'
                : googleDriveAuthRequired
                ? 'Cuenta detectada. Drive requiere autorizacion al continuar.'
                : googleDriveLocalPending
                ? googleDriveAccountStatusLabel
                : googleDriveTemporaryError
                ? googleDriveHasKnownAccount
                      ? 'No se pudo verificar Google Drive ahora. La sesion anterior se conserva.'
                      : 'Error temporal al comprobar Google. No se cerro la sesion.'
                : isGoogleConnecting
                ? 'Comprobando autorizacion de Google Drive.'
                : isGoogleDriveAuthorized
                ? 'Cuenta: $googleDriveAccountLabel - Estado: conectado'
                : googleDriveConnected
                ? '$googleDriveAccountLabel - Falta autorizar Drive'
                : 'Conecta Google Drive para crear y restaurar copias.',
            onTap: googleDriveBusy
                ? null
                : isGoogleDriveAuthorized
                ? onDisconnectGoogleDrive
                : onConnectGoogleDrive,
          ),
          if (googleDriveActionRequiresVerification)
            _SheetAction(
              icon: Icons.refresh_outlined,
              title: 'Reconectar Google Drive',
              subtitle:
                  'Abre Google solo por esta accion manual para renovar la cuenta.',
              onTap: googleDriveBusy ? null : onReconnectGoogleDrive,
            ),
          const _SheetAction(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacidad de Drive',
            subtitle:
                'Tu copia se guarda en el espacio privado de la app en Google Drive. CriptoControlMx no sincroniza automáticamente; solo crea o restaura una copia cuando tú lo solicitas. La copia puede incluir movimientos, precios, comisión, snapshots y configuración financiera. Puedes desconectar Google Drive cuando quieras.',
            onTap: null,
          ),
          _SheetAction(
            icon: Icons.history_outlined,
            title: googleDriveBackupStatus,
            subtitle: 'Archivo: criptocontrolmx_respaldo.json',
            onTap: null,
          ),
          _SheetAction(
            icon: isGoogleDriveCreating
                ? Icons.hourglass_top_outlined
                : Icons.cloud_upload_outlined,
            title: isGoogleDriveCreating
                ? 'Creando copia...'
                : 'Crear copia en Google Drive',
            subtitle: isGoogleDriveAuthorized
                ? 'Actualiza la copia guardada en Google Drive'
                : googleDriveLocalPending
                ? 'Verifica la conexion antes de crear una copia'
                : googleDriveConnected
                ? 'Autoriza Google Drive primero'
                : 'Conecta Google Drive primero',
            onTap:
                googleDriveBusy ||
                    (!isGoogleDriveAuthorized && !googleDriveHasKnownAccount)
                ? null
                : onCreateGoogleDriveBackup,
          ),
          _SheetAction(
            icon: isGoogleDriveRestoring
                ? Icons.hourglass_top_outlined
                : Icons.cloud_download_outlined,
            title: isGoogleDriveRestoring
                ? 'Restaurando copia...'
                : 'Restaurar desde Google Drive',
            subtitle: isGoogleDriveAuthorized
                ? 'Descarga la copia y pide confirmacion antes de restaurar'
                : googleDriveLocalPending
                ? 'Verifica la conexion antes de restaurar'
                : googleDriveConnected
                ? 'Autoriza Google Drive primero'
                : 'Conecta Google Drive primero',
            onTap:
                googleDriveBusy ||
                    (!isGoogleDriveAuthorized && !googleDriveHasKnownAccount)
                ? null
                : onRestoreGoogleDriveBackup,
          ),
          if (googleDriveVisuallyConnected && !isGoogleDriveAuthorized)
            _SheetAction(
              icon: Icons.link_off_outlined,
              title: 'Cerrar sesion de Drive',
              subtitle:
                  'Olvida la vinculacion local y vuelve al estado sin conectar.',
              onTap: googleDriveBusy ? null : onDisconnectGoogleDrive,
            ),
        ],
      ),
    );
  }

  void _showSnapshotActions(BuildContext context) {
    SnapshotAutomationMode selectedAutomation = snapshotAutomationMode;
    SnapshotRetention selectedRetention = snapshotRetention;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setModalState) {
          void runAndClose(VoidCallback action) {
            Navigator.of(sheetContext).pop();
            action();
          }

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.viewPaddingOf(context).bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Instantáneas',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    snapshotCount == 1
                        ? '1 instantánea guardada. Con 2 o más se muestra '
                              'la línea de evolución.'
                        : '$snapshotCount instantáneas guardadas. Con 2 o más '
                              'se muestra la línea de evolución.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: () => runAndClose(onSaveSnapshot),
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Guardar instantánea'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => runAndClose(onOpenCharts),
                        icon: const Icon(Icons.show_chart_outlined),
                        label: const Text('Ver evolución / Gráficas'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => runAndClose(onViewSnapshots),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Administrar instantáneas'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => runAndClose(onExportSnapshotsCsv),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Exportar CSV instantáneas'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => runAndClose(onExportSnapshotsJson),
                        icon: const Icon(Icons.data_object_outlined),
                        label: const Text('Exportar JSON instantáneas'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Automatización de instantáneas',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ...SnapshotAutomationMode.values.map(
                    (SnapshotAutomationMode option) =>
                        RadioListTile<SnapshotAutomationMode>(
                          contentPadding: EdgeInsets.zero,
                          value: option,
                          groupValue: selectedAutomation,
                          title: Text(option.label),
                          onChanged: (SnapshotAutomationMode? value) {
                            if (value == null) return;
                            setModalState(() => selectedAutomation = value);
                            onSnapshotAutomationModeChanged(value);
                          },
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Retención de instantáneas',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Define cuántas instantáneas históricas conserva la app para gráficas. No afecta movimientos ni cartera.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SnapshotRetention.values.map((
                      SnapshotRetention option,
                    ) {
                      return ChoiceChip(
                        selected: selectedRetention == option,
                        label: Text(option.label),
                        onSelected: (_) {
                          setModalState(() => selectedRetention = option);
                          onSnapshotRetentionChanged(option);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDataActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CommandActionSheet(
        title: 'Exportaciones',
        actions: <_SheetAction>[
          _SheetAction(
            icon: Icons.receipt_long_outlined,
            title: 'CSV historial',
            subtitle: 'Movimientos registrados',
            onTap: onExportMovementsCsv,
          ),
          _SheetAction(
            icon: Icons.summarize_outlined,
            title: 'CSV resumen',
            subtitle: 'Cartera actual',
            onTap: onExportSummaryCsv,
          ),
          _SheetAction(
            icon: Icons.photo_library_outlined,
            title: 'CSV instantáneas',
            subtitle: 'Evolución guardada',
            onTap: onExportSnapshotsCsv,
          ),
          _SheetAction(
            icon: Icons.data_object_outlined,
            title: 'JSON movimientos',
            subtitle: 'Historial completo de movimientos',
            onTap: onExportMovementsJson,
          ),
          _SheetAction(
            icon: Icons.data_object_outlined,
            title: 'JSON instantáneas',
            subtitle: 'Histórico de instantáneas',
            onTap: onExportSnapshotsJson,
          ),
          _SheetAction(
            icon: Icons.account_balance_wallet_outlined,
            title: 'JSON portafolio',
            subtitle: 'Resumen calculado por el motor financiero',
            onTap: onExportPortfolioSummaryJson,
          ),
          _SheetAction(
            icon: Icons.data_object_outlined,
            title: 'Copia de seguridad',
            subtitle:
                'Copia financiera; no incluye tema, alertas ni preferencias visuales',
            onTap: onExportBackup,
          ),
          _SheetAction(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF reporte',
            subtitle: 'Reporte existente',
            onTap: onExportPdf,
          ),
          _SheetAction(
            icon: Icons.table_chart_outlined,
            title: 'XLSX reporte',
            subtitle: 'Libro de cálculo existente',
            onTap: onExportXlsx,
          ),
        ],
      ),
    );
  }

  void _showImportActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CommandActionSheet(
        title: 'Restaurar copia de seguridad',
        actions: <_SheetAction>[
          _SheetAction(
            icon: Icons.content_paste_outlined,
            title: 'Pegar contenido de copia',
            subtitle: 'Modo avanzado: pegar contenido técnico de la copia',
            onTap: onImportBackup,
          ),
          _SheetAction(
            icon: Icons.upload_file_outlined,
            title: 'Cargar archivo local',
            subtitle: 'Seleccionar copia guardada',
            onTap: onImportBackupFile,
          ),
        ],
      ),
    );
  }

  void _showDiagnostics(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Estado del sistema',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Resumen local de cartera, precios, instantáneas y alertas.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Actividad local',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              InfoLine('Movimientos totales', movementCount.toString()),
              InfoLine(
                'Movimientos con ID',
                '$movementsWithIdCount/$movementCount',
              ),
              InfoLine('Instantáneas guardadas', snapshotCount.toString()),
              InfoLine(
                'Última instantánea guardada',
                latestSnapshot == null
                    ? 'Sin instantáneas'
                    : longDate(latestSnapshot!),
              ),
              const Divider(height: 20),
              Text(
                'Precios',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              InfoLine(
                'Última actualización',
                priceUpdatedLabel(pricesUpdatedAt),
              ),
              InfoLine(
                'Precios disponibles',
                '$pricesAvailableCount/$pricesTotalCount',
              ),
              InfoLine('Precios manuales', manualPriceCoins.length.toString()),
              InfoLine(
                'Precios automáticos',
                (pricesTotalCount - manualPriceCoins.length).toString(),
              ),
              InfoLine(
                'Manual',
                manualPriceCoins.isEmpty
                    ? 'Ninguna'
                    : manualPriceCoins.join(', '),
              ),
              InfoLine(
                'Sin precio',
                missingPriceCoins.isEmpty
                    ? 'Ninguna'
                    : missingPriceCoins.join(', '),
              ),
              InfoLine(
                'Estado de precios',
                pricesAvailableCount == 0
                    ? 'Sin precios'
                    : pricesAvailableCount == pricesTotalCount
                    ? 'Completo'
                    : 'Parcial',
              ),
              const InfoLine(
                'Nota',
                'Precio 0 puede indicar dato no disponible; no necesariamente valor real de mercado.',
              ),
              InfoLine(
                'Estado de actualización',
                isRefreshingPrices ? 'Actualizando' : 'En reposo',
              ),
              InfoLine(
                'Al abrir app',
                refreshPricesOnOpen ? 'Activado' : 'Desactivado',
              ),
              InfoLine(
                'Después de movimiento',
                refreshPricesAfterMovement ? 'Activado' : 'Desactivado',
              ),
              InfoLine('En pantalla', priceRefreshForegroundMode.label),
              InfoLine('Monedas con posición', activeCoins.toString()),
              InfoLine('Monedas soportadas', pricesTotalCount.toString()),
              InfoLine('Fuente de precios', _priceSource),
              const Divider(height: 20),
              Text(
                'Salud',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              InfoLine('Errores detectados', financialErrors.length.toString()),
              InfoLine('Firebase', firebaseStatus),
              InfoLine('Crash reporting', crashlyticsStatus),
              InfoLine('Analytics', analyticsStatus),
              InfoLine(
                'Firebase Auth',
                firebaseAuthConnected ? 'Conectado' : 'Sin cuenta conectada',
              ),
              if (firebaseAuthConnected)
                InfoLine(
                  'Cuenta Firebase',
                  firebaseAuthEmail ?? 'Sin email visible',
                ),
              InfoLine('Cloud profile', cloudProfileStatus),
              const InfoLine('Firebase sync', 'Manual'),
              InfoLine(
                'DeviceId local',
                hasLocalFirebaseDeviceId ? 'Registrado' : 'No registrado',
              ),
              InfoLine('Cloud state subida', cloudStateUploadLabel),
              InfoLine('Cloud state descarga', cloudStateDownloadLabel),
              InfoLine(
                'DeviceId cloud',
                hasLocalFirebaseDeviceId ? 'Registrado' : 'No registrado',
              ),
              const InfoLine('Sync automático Firebase', 'No'),
              InfoLine('Copia de seguridad local', 'Compatible'),
              InfoLine(
                'Google Drive',
                googleDriveConnected ? 'Conectado' : 'Sin cuenta conectada',
              ),
              const InfoLine('Scope Drive', 'appDataFolder'),
              const InfoLine('Sync automático Drive', 'No'),
              InfoLine('Última copia Drive', googleDriveBackupLabel),
              InfoLine(
                'Alertas automáticas locales',
                automaticLocalAlertsEnabled ? 'Activadas' : 'Desactivadas',
              ),
              const InfoLine(
                'Monitoreo de alertas',
                'Configurable desde Alertas',
              ),
              InfoLine(
                'Intervalo de alertas',
                intervalLabel(automaticLocalAlertsIntervalMinutes),
              ),
              InfoLine(
                'Permisos',
                notificationsAllowed
                    ? 'Notificaciones permitidas'
                    : 'Notificaciones no permitidas',
              ),
              InfoLine(
                'Instantáneas automáticas',
                snapshotAutomationMode.label,
              ),
              InfoLine('Retención de instantáneas', snapshotRetention.label),
              const Divider(height: 20),
              Text(
                'Checklist beta',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const InfoLine('Cuenta', 'Google/Firebase Auth opcional'),
              const InfoLine(
                'Datos financieros',
                'Locales; Drive/Firebase solo por acción manual',
              ),
              InfoLine(
                'App activity',
                analyticsEnabled ? 'Analytics autorizado' : 'No autorizado',
              ),
              InfoLine(
                'Crash logs',
                crashlyticsEnabled ? 'Reportes autorizados' : 'No autorizados',
              ),
              const InfoLine(
                'OCR',
                'Procesado localmente; no enviado a monitoreo',
              ),
              const InfoLine('Sync automático', 'No activo'),
              const InfoLine(
                'Beta readiness',
                'Data Safety por confirmar en Play Console',
              ),
              if (financialErrors.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                ...financialErrors
                    .take(6)
                    .map((String error) => InfoLine('Alerta', error)),
                if (financialErrors.length > 6)
                  InfoLine('Más alertas', '+${financialErrors.length - 6}'),
              ],
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onResetPriceAlertReferences,
                icon: const Icon(Icons.restart_alt_outlined),
                label: const Text('Reiniciar precios base'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _showMotorVerification(context),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Verificación motor financiero'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutApp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Acerca de CriptoControlMx',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'CriptoControlMx es una herramienta local para registrar movimientos, revisar cartera, consultar precios, generar instantáneas y exportar reportes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              const Divider(height: 20),
              InfoLine('Estado', 'Fase 1'),
              InfoLine('Datos', 'Guardados localmente en este dispositivo'),
              InfoLine('Firebase', firebaseStatus),
              InfoLine('Crash reporting', crashlyticsStatus),
              InfoLine('Analytics', analyticsStatus),
              InfoLine(
                'Firebase Auth',
                firebaseAuthConnected ? 'Conectado' : 'Sin cuenta conectada',
              ),
              InfoLine('Cloud profile', cloudProfileStatus),
              const InfoLine('Firebase sync', 'Manual; sin automático'),
              InfoLine('Cloud state subida', cloudStateUploadLabel),
              InfoLine('Cloud state descarga', cloudStateDownloadLabel),
              InfoLine('Fuente de precios', 'CoinGecko'),
              InfoLine('Exportaciones', 'CSV, JSON, PDF y XLSX'),
              const InfoLine(
                'Google Drive',
                'Opcional; solo por acción del usuario',
              ),
              const InfoLine(
                'Datos en copia',
                'Movimientos, precios, comisión, snapshots y configuración financiera',
              ),
              const InfoLine(
                'Cuenta Google',
                'Email visible para mostrar la cuenta conectada',
              ),
              const InfoLine(
                'Privacidad',
                'Monitoreo opcional; sin venta de datos ni sync automático',
              ),
              InfoLine(
                'Copia de seguridad',
                'Creación y restauración locales disponibles',
              ),
              InfoLine('Aviso', 'No es asesoría financiera'),
              const Divider(height: 20),
              Text(
                'Privacidad y datos',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'CriptoControlMx maneja datos financieros registrados por ti. Esos datos se quedan en tu dispositivo salvo cuando decides crear una copia en Google Drive o subir/restaurar estado desde Firebase.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Analytics y reportes de errores solo se envían si los autorizas. No se envían a monitoreo movimientos completos, montos, cantidades cripto, precios, P&L, OCR detectado, copias de seguridad, notas, wallets ni redes.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Si usas cuenta en la nube, Firebase puede procesar tu correo de cuenta y el estado financiero que subas manualmente. Si usas Google Drive Backup, tu copia se guarda en el espacio privado de la app cuando tú lo solicitas.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Data Safety preliminar: email y User ID solo con inicio de sesión; información financiera solo para funcionalidad, backup o sync manual; app activity y diagnósticos solo con autorización.',
              ),
              const SizedBox(height: 12),
              Text(
                'Las cifras dependen de los movimientos registrados, precios disponibles y comisiones configuradas.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Esta app no sustituye análisis financiero profesional ni garantiza rendimientos.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMotorVerification(BuildContext context) {
    final List<_MotorVerificationItem> items = _buildMotorVerificationItems();
    final int okCount = items.where((item) => item.passed).length;
    final int failCount = items.length - okCount;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Verificación motor financiero',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Escenarios controlados contra el motor actual. No modifica datos.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              InfoLine(
                'Escenarios ejecutados',
                '${items.length} · $okCount OK · $failCount FAIL',
                emphasized: true,
              ),
              const Divider(height: 20),
              ...items.map(
                (item) => InfoLine(
                  item.name,
                  item.passed
                      ? 'OK · ${item.actual}'
                      : 'FAIL · esp ${item.expected} · act ${item.actual}',
                  valueColor: item.passed ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_MotorVerificationItem> _buildMotorVerificationItems() {
    final List<String> coins = motorCoins;
    final DateTime stamp = DateTime.utc(2024, 1, 2, 12);

    Map<String, double> prices(String coin, double price) => <String, double>{
      for (final String c in coins) c: 0.0,
      coin: price,
    };

    CoinStats stat(
      List<Movement> movements,
      Map<String, double> currentPrices,
      String coin,
    ) {
      return FinancialEngine.computeStats(
        coins: coins,
        movements: movements,
        currentPrices: currentPrices,
      )[coin]!;
    }

    String summary(CoinStats s) {
      return 'q=${s.quantity.toStringAsFixed(8)}, cost=${s.costBase.toStringAsFixed(2)}, avg=${s.avgPrice.toStringAsFixed(2)}, '
          'price=${s.currentPrice.toStringAsFixed(2)}, value=${s.currentValue.toStringAsFixed(2)}, '
          'uPL=${s.unrealizedPL.toStringAsFixed(2)}, rPL=${s.realizedPL.toStringAsFixed(2)}, '
          'fees=${s.feesPaid.toStringAsFixed(2)}, be=${s.netBreakEvenPrice(motorSellFeePercent).toStringAsFixed(2)}';
    }

    bool close(double a, double b, [double tolerance = 0.000001]) =>
        (a - b).abs() <= tolerance;

    bool sameStats(CoinStats actual, CoinStats expected) {
      return close(actual.quantity, expected.quantity) &&
          close(actual.costBase, expected.costBase) &&
          close(actual.currentPrice, expected.currentPrice) &&
          close(actual.avgPrice, expected.avgPrice) &&
          close(actual.currentValue, expected.currentValue) &&
          close(actual.unrealizedPL, expected.unrealizedPL) &&
          close(actual.realizedPL, expected.realizedPL) &&
          close(actual.feesPaid, expected.feesPaid) &&
          close(actual.totalInvested, expected.totalInvested) &&
          close(
            actual.netBreakEvenPrice(motorSellFeePercent),
            expected.netBreakEvenPrice(motorSellFeePercent),
          );
    }

    _MotorVerificationItem coinCase({
      required String name,
      required String coin,
      required List<Map<String, Object?>> rawMoves,
      required Map<String, double> currentPrices,
      required CoinStats expected,
    }) {
      final List<Movement> movements = rawMoves
          .map(
            (Map<String, Object?> raw) =>
                Movement.fromJson(Map<String, dynamic>.from(raw)),
          )
          .toList();
      final CoinStats actual = stat(movements, currentPrices, coin);
      return _MotorVerificationItem(
        name: name,
        passed: sameStats(actual, expected),
        expected: summary(expected),
        actual: summary(actual),
      );
    }

    final List<_MotorVerificationItem> items = <_MotorVerificationItem>[
      coinCase(
        name: 'Compra simple',
        coin: 'BTC',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'buy',
            'coin': 'BTC',
            'date': stamp.toIso8601String(),
            'quantity': 1,
            'unitPrice': 100,
            'fee': 10,
            'note': 'compra simple',
          },
        ],
        currentPrices: prices('BTC', 120),
        expected: CoinStats(
          coin: 'BTC',
          quantity: 1,
          costBase: 110,
          currentPrice: 120,
          realizedPL: 0,
          feesPaid: 10,
          totalInvested: 110,
        ),
      ),
      coinCase(
        name: 'Dos compras con promedio',
        coin: 'BTC',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'buy',
            'coin': 'BTC',
            'date': stamp.toIso8601String(),
            'quantity': 1,
            'unitPrice': 100,
            'fee': 0,
            'note': 'primera',
          },
          <String, Object?>{
            'type': 'buy',
            'coin': 'BTC',
            'date': stamp.add(const Duration(minutes: 1)).toIso8601String(),
            'quantity': 1,
            'unitPrice': 300,
            'fee': 0,
            'note': 'segunda',
          },
        ],
        currentPrices: prices('BTC', 250),
        expected: CoinStats(
          coin: 'BTC',
          quantity: 2,
          costBase: 400,
          currentPrice: 250,
          realizedPL: 0,
          feesPaid: 0,
          totalInvested: 400,
        ),
      ),
      coinCase(
        name: 'Venta parcial',
        coin: 'BTC',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'buy',
            'coin': 'BTC',
            'date': stamp.toIso8601String(),
            'quantity': 2,
            'unitPrice': 100,
            'fee': 0,
            'note': 'base',
          },
          <String, Object?>{
            'type': 'sell',
            'coin': 'BTC',
            'date': stamp.add(const Duration(minutes: 1)).toIso8601String(),
            'quantity': 1,
            'unitPrice': 150,
            'fee': 0,
            'note': 'parcial',
          },
        ],
        currentPrices: prices('BTC', 150),
        expected: CoinStats(
          coin: 'BTC',
          quantity: 1,
          costBase: 100,
          currentPrice: 150,
          realizedPL: 50,
          feesPaid: 0,
          totalInvested: 200,
        ),
      ),
      coinCase(
        name: 'Venta total',
        coin: 'BTC',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'buy',
            'coin': 'BTC',
            'date': stamp.toIso8601String(),
            'quantity': 1,
            'unitPrice': 100,
            'fee': 0,
            'note': 'base',
          },
          <String, Object?>{
            'type': 'sell',
            'coin': 'BTC',
            'date': stamp.add(const Duration(minutes: 1)).toIso8601String(),
            'quantity': 1,
            'unitPrice': 150,
            'fee': 0,
            'note': 'cierre',
          },
        ],
        currentPrices: prices('BTC', 150),
        expected: CoinStats(
          coin: 'BTC',
          quantity: 0,
          costBase: 0,
          currentPrice: 150,
          realizedPL: 50,
          feesPaid: 0,
          totalInvested: 100,
        ),
      ),
      coinCase(
        name: 'Entrada sin realizedPL',
        coin: 'ETH',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'transferIn',
            'coin': 'ETH',
            'date': stamp.toIso8601String(),
            'quantity': 2,
            'unitPrice': 100,
            'fee': 0,
            'note': 'entrada',
          },
        ],
        currentPrices: prices('ETH', 120),
        expected: CoinStats(
          coin: 'ETH',
          quantity: 2,
          costBase: 200,
          currentPrice: 120,
          realizedPL: 0,
          feesPaid: 0,
          totalInvested: 200,
        ),
      ),
      coinCase(
        name: 'Salida sin realizedPL',
        coin: 'LINK',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'buy',
            'coin': 'LINK',
            'date': stamp.toIso8601String(),
            'quantity': 2,
            'unitPrice': 100,
            'fee': 0,
            'note': 'base',
          },
          <String, Object?>{
            'type': 'transferOut',
            'coin': 'LINK',
            'date': stamp.add(const Duration(minutes: 1)).toIso8601String(),
            'quantity': 1,
            'unitPrice': 120,
            'fee': 0,
            'note': 'salida',
          },
        ],
        currentPrices: prices('LINK', 100),
        expected: CoinStats(
          coin: 'LINK',
          quantity: 1,
          costBase: 100,
          currentPrice: 100,
          realizedPL: 0,
          feesPaid: 0,
          totalInvested: 200,
        ),
      ),
      coinCase(
        name: 'Comisión cero',
        coin: 'LTC',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'buy',
            'coin': 'LTC',
            'date': stamp.toIso8601String(),
            'quantity': 1,
            'unitPrice': 100,
            'fee': 0,
            'note': 'sin comisión',
          },
        ],
        currentPrices: prices('LTC', 110),
        expected: CoinStats(
          coin: 'LTC',
          quantity: 1,
          costBase: 100,
          currentPrice: 110,
          realizedPL: 0,
          feesPaid: 0,
          totalInvested: 100,
        ),
      ),
      coinCase(
        name: 'Precio faltante = 0',
        coin: 'UNI',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'buy',
            'coin': 'UNI',
            'date': stamp.toIso8601String(),
            'quantity': 1,
            'unitPrice': 100,
            'fee': 0,
            'note': 'sin precio',
          },
        ],
        currentPrices: <String, double>{},
        expected: CoinStats(
          coin: 'UNI',
          quantity: 1,
          costBase: 100,
          currentPrice: 0,
          realizedPL: 0,
          feesPaid: 0,
          totalInvested: 100,
        ),
      ),
      coinCase(
        name: 'Moneda activa con precio 0',
        coin: 'USDC',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'buy',
            'coin': 'USDC',
            'date': stamp.toIso8601String(),
            'quantity': 1,
            'unitPrice': 1,
            'fee': 0,
            'note': 'USDC sin precio',
          },
        ],
        currentPrices: prices('USDC', 0),
        expected: CoinStats(
          coin: 'USDC',
          quantity: 1,
          costBase: 1,
          currentPrice: 0,
          realizedPL: 0,
          feesPaid: 0,
          totalInvested: 1,
        ),
      ),
      coinCase(
        name: 'Venta mayor al saldo',
        coin: 'BTC',
        rawMoves: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'buy',
            'coin': 'BTC',
            'date': stamp.toIso8601String(),
            'quantity': 1,
            'unitPrice': 100,
            'fee': 0,
            'note': 'base',
          },
          <String, Object?>{
            'type': 'sell',
            'coin': 'BTC',
            'date': stamp.add(const Duration(minutes: 1)).toIso8601String(),
            'quantity': 2,
            'unitPrice': 200,
            'fee': 0,
            'note': 'exceso',
          },
        ],
        currentPrices: prices('BTC', 200),
        expected: CoinStats(
          coin: 'BTC',
          quantity: 0,
          costBase: 0,
          currentPrice: 200,
          realizedPL: 100,
          feesPaid: 0,
          totalInvested: 100,
        ),
      ),
    ];

    final List<Movement> snapshotMovements = <Movement>[
      Movement(
        type: MovementType.buy,
        coin: 'BTC',
        date: stamp,
        quantity: 1,
        unitPrice: 100,
        fee: 10,
        note: 'snapshot',
      ),
    ];
    final CoinStats snapshotStats = stat(
      snapshotMovements,
      prices('BTC', 120),
      'BTC',
    );
    final PortfolioSnapshot snapshot = PortfolioSnapshot(
      id: 'snapshot-verification',
      createdAt: stamp,
      totalCostBase: snapshotStats.costBase,
      totalCurrentValue: snapshotStats.currentValue,
      totalUnrealizedPL: snapshotStats.unrealizedPL,
      totalRealizedPL: snapshotStats.realizedPL,
      movementCount: snapshotMovements.length,
      coins: <CoinSnapshot>[CoinSnapshot.fromStats(snapshotStats)],
    );
    final PortfolioSnapshot snapshotRoundTrip = PortfolioSnapshot.fromJson(
      snapshot.toJson(),
    );
    items.add(
      _MotorVerificationItem(
        name: 'Snapshot compatible básico',
        passed:
            close(snapshotRoundTrip.totalCostBase, snapshot.totalCostBase) &&
            close(
              snapshotRoundTrip.totalCurrentValue,
              snapshot.totalCurrentValue,
            ) &&
            close(
              snapshotRoundTrip.totalUnrealizedPL,
              snapshot.totalUnrealizedPL,
            ) &&
            close(
              snapshotRoundTrip.totalRealizedPL,
              snapshot.totalRealizedPL,
            ) &&
            snapshotRoundTrip.coins.length == 1 &&
            snapshotRoundTrip.coins.first.coin == 'BTC',
        expected:
            'cost=${snapshot.totalCostBase.toStringAsFixed(2)}, value=${snapshot.totalCurrentValue.toStringAsFixed(2)}, uPL=${snapshot.totalUnrealizedPL.toStringAsFixed(2)}, rPL=${snapshot.totalRealizedPL.toStringAsFixed(2)}, coins=1',
        actual:
            'cost=${snapshotRoundTrip.totalCostBase.toStringAsFixed(2)}, value=${snapshotRoundTrip.totalCurrentValue.toStringAsFixed(2)}, uPL=${snapshotRoundTrip.totalUnrealizedPL.toStringAsFixed(2)}, rPL=${snapshotRoundTrip.totalRealizedPL.toStringAsFixed(2)}, coins=${snapshotRoundTrip.coins.length}',
      ),
    );

    final Movement backupMovement = Movement(
      type: MovementType.buy,
      coin: 'ETH',
      date: stamp,
      quantity: 1,
      unitPrice: 250,
      fee: 5,
      source: 'demo',
      wallet: 'local',
      network: 'erc20',
      note: 'backup',
    );
    final Movement backupRoundTrip = Movement.fromJson(backupMovement.toJson());
    final Map<String, dynamic> backupShape = <String, dynamic>{
      'version': 2,
      'exportedAt': stamp.toIso8601String(),
      'settings': <String, double>{'sellFeePercent': motorSellFeePercent},
      'currentPrices': prices('ETH', 260),
      'movements': <Map<String, dynamic>>[backupMovement.toJson()],
      'snapshots': <Map<String, dynamic>>[snapshot.toJson()],
    };
    final Map<String, dynamic> decodedBackup =
        jsonDecode(jsonEncode(backupShape)) as Map<String, dynamic>;
    items.add(
      _MotorVerificationItem(
        name: 'Backup financiero compatible',
        passed:
            backupRoundTrip.isFinanciallyIdenticalTo(backupMovement) &&
            decodedBackup['movements'] is List &&
            decodedBackup['currentPrices'] is Map &&
            decodedBackup['settings'] is Map &&
            decodedBackup['snapshots'] is List,
        expected:
            'movimientos=1, precios=${coins.length}, settings=1, snapshots=1',
        actual:
            'movimientos=${(decodedBackup['movements'] as List).length}, precios=${(decodedBackup['currentPrices'] as Map).length}, settings=${(decodedBackup['settings'] as Map).length}, snapshots=${(decodedBackup['snapshots'] as List).length}',
      ),
    );

    return items;
  }
}

class _MotorVerificationItem {
  final String name;
  final bool passed;
  final String expected;
  final String actual;

  const _MotorVerificationItem({
    required this.name,
    required this.passed,
    required this.expected,
    required this.actual,
  });
}

class _CommandCenterHeader extends StatelessWidget {
  final DateTime? pricesUpdatedAt;
  final String priceSource;
  final bool googleDriveConnected;
  final DateTime? googleDriveBackupUpdatedAt;
  final AppVisualMode visualMode;
  final AppThemeStyle themeStyle;

  const _CommandCenterHeader({
    required this.pricesUpdatedAt,
    required this.priceSource,
    required this.googleDriveConnected,
    required this.googleDriveBackupUpdatedAt,
    required this.visualMode,
    required this.themeStyle,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String backupValue = googleDriveConnected ? 'Drive activo' : 'Local';
    final String backupSubtitle = googleDriveBackupUpdatedAt == null
        ? 'Sin copia Drive'
        : longDate(googleDriveBackupUpdatedAt!.toLocal());

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.primaryContainer.withValues(alpha: 0.52),
            colors.surface.withValues(alpha: 0.98),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Más',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Configuración, respaldo y herramientas de CriptoControlMx.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFCBD5E1),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colors.primary.withValues(alpha: 0.18),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.26),
                  ),
                ),
                child: Icon(
                  Icons.tune_outlined,
                  color: colors.primary,
                  size: 25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const double gap = 8;
              final bool wide = constraints.maxWidth >= 520;
              final double width = wide
                  ? (constraints.maxWidth - gap * 3) / 4
                  : (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: <Widget>[
                  SizedBox(
                    width: width,
                    child: _HeaderMetric(
                      label: 'Respaldos',
                      value: backupValue,
                      subtitle: backupSubtitle,
                      icon: Icons.backup_outlined,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: const _HeaderMetric(
                      label: 'Exportaciones',
                      value: 'CSV/JSON',
                      subtitle: 'PDF y XLSX',
                      icon: Icons.file_download_outlined,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeaderMetric(
                      label: 'Precios',
                      value: priceSource,
                      subtitle: priceUpdatedLabel(pricesUpdatedAt),
                      icon: Icons.cloud_outlined,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeaderMetric(
                      label: 'Modo visual',
                      value: visualMode.label,
                      subtitle: themeStyle.label,
                      icon: Icons.palette_outlined,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;

  const _HeaderMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.58),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 17, color: color ?? colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? colors.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.onSurfaceVariant.withValues(alpha: 0.82),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoreActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool loading;
  final VoidCallback? onTap;

  const _MoreActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool destructive =
        title.toLowerCase().contains('restablecer') ||
        title.toLowerCase().contains('borrar') ||
        (badge?.toLowerCase().contains('peligro') ?? false);
    final Color accent = destructive ? colors.error : colors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        splashColor: colors.primary.withValues(alpha: 0.08),
        highlightColor: colors.primary.withValues(alpha: 0.05),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minHeight: 74),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent.withValues(alpha: 0.16)),
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, color: accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (badge != null) ...<Widget>[
                          const SizedBox(width: 8),
                          PremiumStatusBadge(
                            label: badge!,
                            tone: _premiumBadgeTone(badge!),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.22,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: colors.onSurfaceVariant.withValues(alpha: 0.72),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyMonitoringCard extends StatelessWidget {
  const _PrivacyMonitoringCard({
    required this.analyticsEnabled,
    required this.crashlyticsEnabled,
    required this.onAnalyticsChanged,
    required this.onCrashlyticsChanged,
  });

  final bool analyticsEnabled;
  final bool crashlyticsEnabled;
  final ValueChanged<bool> onAnalyticsChanged;
  final ValueChanged<bool> onCrashlyticsChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerHighest.withValues(alpha: 0.82),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.42)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.privacy_tip_outlined, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Privacidad y monitoreo',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'CriptoControlMx puede enviar reportes de errores y datos básicos de uso solo si lo autorizas.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Los datos financieros se quedan en tu dispositivo salvo cuando creas una copia en Google Drive o subes/restauras estado desde Firebase.',
            ),
            const SizedBox(height: 8),
            const Text(
              'No se envían a Analytics ni Crashlytics movimientos completos, montos, cantidades cripto, precios, P&L, OCR detectado, copias de seguridad, notas, wallets ni redes.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enviar reportes de errores'),
              subtitle: const Text(
                'Ayuda a detectar cierres inesperados. No se envían movimientos, montos, precios ni copias de seguridad.',
              ),
              value: crashlyticsEnabled,
              onChanged: onCrashlyticsChanged,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enviar datos de uso'),
              subtitle: const Text(
                'Ayuda a entender qué funciones se usan. No se envían cantidades, cartera, OCR, backup, email ni UID.',
              ),
              value: analyticsEnabled,
              onChanged: onAnalyticsChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _CommandSection({required this.title, required this.children});

  IconData get _icon {
    final String normalized = title.toLowerCase();
    if (normalized.contains('cuenta')) return Icons.cloud_outlined;
    if (normalized.contains('riesgo'))
      return Icons.report_gmailerrorred_outlined;
    if (normalized.contains('general'))
      return Icons.dashboard_customize_outlined;
    if (normalized.contains('respaldo')) return Icons.backup_outlined;
    if (normalized.contains('instant')) return Icons.photo_library_outlined;
    if (normalized.contains('export')) return Icons.file_download_outlined;
    if (normalized.contains('diagn')) return Icons.health_and_safety_outlined;
    if (normalized.contains('acerca')) return Icons.info_outline;
    if (normalized.contains('personal')) return Icons.palette_outlined;
    if (normalized.contains('privacidad')) return Icons.privacy_tip_outlined;
    return Icons.tune_outlined;
  }

  String? get _description {
    final String normalized = title.toLowerCase();
    if (normalized.contains('cuenta')) {
      return 'Estado de cuenta, nube manual y conexión de Google Drive.';
    }
    if (normalized.contains('riesgo')) {
      return 'Acciones sensibles que pueden afectar datos locales.';
    }
    if (normalized.contains('respaldo')) {
      return 'Copias manuales, restauración y estado de nube.';
    }
    if (normalized.contains('privacidad')) {
      return 'Preferencias locales, monitoreo opcional y acciones sensibles.';
    }
    if (normalized.contains('personal')) {
      return 'Apariencia, lectura de cartera y actualización de precios.';
    }
    if (normalized.contains('export')) {
      return 'Acceso a historial, reportes y formatos existentes.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool riskSection = title.toLowerCase().contains('riesgo');
    final Color sectionColor = riskSection ? colors.error : colors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(_icon, size: 17, color: sectionColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          color: colors.onSurfaceVariant.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (_description != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          _description!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.2,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool twoColumns = constraints.maxWidth >= 560;
              final double spacing = twoColumns ? 12 : 0;
              final double itemWidth = twoColumns
                  ? (constraints.maxWidth - spacing) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: spacing,
                runSpacing: 10,
                children: children
                    .map(
                      (Widget child) =>
                          SizedBox(width: itemWidth, child: child),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class PremiumQuickActions extends StatelessWidget {
  final VoidCallback onCapture;
  final VoidCallback onAdd;
  final bool expanded;

  const PremiumQuickActions({
    super.key,
    required this.onCapture,
    required this.onAdd,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget compactActions = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            button: true,
            label: 'Importar desde captura',
            child: IconButton(
              tooltip: 'Importar desde captura',
              visualDensity: VisualDensity.compact,
              onPressed: onCapture,
              icon: const Icon(Icons.document_scanner_outlined),
            ),
          ),
          const SizedBox(width: 2),
          Semantics(
            button: true,
            label: 'Agregar movimiento',
            child: IconButton.filled(
              tooltip: 'Agregar movimiento',
              visualDensity: VisualDensity.compact,
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );

    if (!expanded) return compactActions;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool iconOnly = constraints.maxWidth < 300 || textScale >= 1.35;

        if (iconOnly) {
          return Align(alignment: Alignment.centerRight, child: compactActions);
        }

        return Row(
          children: <Widget>[
            Expanded(
              child: Tooltip(
                message: 'Importar desde captura',
                child: FilledButton.tonalIcon(
                  onPressed: onCapture,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Captura'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Tooltip(
                message: 'Agregar movimiento',
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PremiumActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool loading;
  final String? emptyTitle;
  final String? emptySubtitle;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final bool showChevron;
  final VoidCallback? onTap;

  const PremiumActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.loading = false,
    this.emptyTitle,
    this.emptySubtitle,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.showChevron = true,
    this.onTap,
  });

  bool get _hasEmptyState => emptyTitle != null && emptySubtitle != null;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: colors.primary.withValues(alpha: 0.10),
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, color: colors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (badge != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PremiumStatusBadge(
                          label: badge!,
                          tone: _premiumBadgeTone(badge!),
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (showChevron) ...<Widget>[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                  size: 20,
                ),
              ],
            ],
          ),
          if (_hasEmptyState) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(icon, size: 22, color: colors.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              emptyTitle!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              emptySubtitle!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (emptyActionLabel != null &&
                      onEmptyAction != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: onEmptyAction,
                        child: Text(emptyActionLabel!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

PremiumStatusTone _premiumBadgeTone(String label) {
  final String normalized = label.toLowerCase();
  if (normalized.contains('error') ||
      normalized.contains('peligro') ||
      normalized.contains('no conectado')) {
    return PremiumStatusTone.negative;
  }
  if (normalized.contains('conectado') ||
      normalized == 'ok' ||
      normalized == 'activo') {
    return PremiumStatusTone.positive;
  }
  if (normalized.contains('pendiente')) return PremiumStatusTone.warning;
  if (normalized.contains('clave') ||
      normalized.contains('reporte') ||
      normalized.contains('nuevo')) {
    return PremiumStatusTone.accent;
  }
  return PremiumStatusTone.neutral;
}

class _SheetAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _CommandActionSheet extends StatelessWidget {
  final String title;
  final List<_SheetAction> actions;

  const _CommandActionSheet({required this.title, required this.actions});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final double bottomPadding = MediaQuery.viewPaddingOf(context).bottom + 20;
    final List<_SheetAction> visibleActions = actions
        .where((_SheetAction action) => !action.title.startsWith('Sin sincron'))
        .where(
          (_SheetAction action) =>
              action.title != 'Crear copia en Google Drive' ||
              action.onTap != null,
        )
        .where(
          (_SheetAction action) =>
              action.title != 'Restaurar desde Google Drive' ||
              action.onTap != null,
        )
        .toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Acciones disponibles para esta sección. Las operaciones sensibles conservan su confirmación existente.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: visibleActions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final _SheetAction action = visibleActions[index];
                  final bool destructive =
                      action.title.toLowerCase().contains('restaurar') ||
                      action.title.toLowerCase().contains('desconectar') ||
                      action.title.toLowerCase().contains('cerrar sesión');
                  final Color accent = destructive
                      ? colors.error
                      : colors.primary;
                  return Card(
                    margin: EdgeInsets.zero,
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.78,
                    ),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: destructive
                            ? colors.error.withValues(alpha: 0.28)
                            : colors.outlineVariant.withValues(alpha: 0.42),
                      ),
                    ),
                    child: ListTile(
                      minLeadingWidth: 36,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(action.icon, color: accent, size: 20),
                      ),
                      title: Text(action.title),
                      subtitle: Text(action.subtitle),
                      trailing: action.onTap == null
                          ? null
                          : Icon(
                              Icons.chevron_right,
                              color: colors.onSurfaceVariant,
                            ),
                      enabled: action.onTap != null,
                      onTap: action.onTap == null
                          ? null
                          : () {
                              final NavigatorState? navigator =
                                  Navigator.maybeOf(context);
                              if (context.mounted &&
                                  navigator != null &&
                                  navigator.canPop()) {
                                navigator.pop();
                              }
                              action.onTap!();
                            },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum SettingsView { all, theme, portfolio, prices }

class SettingsTab extends StatelessWidget {
  final SettingsView view;
  final AppVisualMode visualMode;
  final AppThemeStyle themeStyle;
  final VisiblePositions visiblePositions;
  final PositionSortMode positionSortMode;
  final SnapshotAutomationMode snapshotAutomationMode;
  final SnapshotRetention snapshotRetention;
  final bool refreshPricesOnOpen;
  final bool refreshPricesAfterMovement;
  final PriceRefreshForegroundMode priceRefreshForegroundMode;
  final double sellFeePercent;
  final int snapshotCount;
  final bool automaticLocalAlertsEnabled;
  final int automaticLocalAlertsIntervalMinutes;
  final bool notificationsAllowed;
  final ValueChanged<AppVisualMode> onVisualModeChanged;
  final ValueChanged<AppThemeStyle> onThemeStyleChanged;
  final ValueChanged<VisiblePositions> onVisiblePositionsChanged;
  final ValueChanged<PositionSortMode> onPositionSortModeChanged;
  final ValueChanged<SnapshotAutomationMode> onSnapshotAutomationModeChanged;
  final ValueChanged<SnapshotRetention> onSnapshotRetentionChanged;
  final ValueChanged<bool> onRefreshPricesOnOpenChanged;
  final ValueChanged<bool> onRefreshPricesAfterMovementChanged;
  final ValueChanged<PriceRefreshForegroundMode>
  onPriceRefreshForegroundModeChanged;
  final VoidCallback onEditSellFee;
  final VoidCallback onOpenAlerts;
  final ValueChanged<bool> onAutomaticLocalAlertsChanged;
  final ValueChanged<int> onAutomaticLocalAlertIntervalChanged;
  final VoidCallback onSaveSnapshot;
  final VoidCallback onViewSnapshots;
  final VoidCallback onExportSnapshotsCsv;
  final VoidCallback onExportXlsx;
  final VoidCallback onExportPdf;
  final VoidCallback onExportBackup;

  const SettingsTab({
    super.key,
    this.view = SettingsView.all,
    required this.visualMode,
    required this.themeStyle,
    required this.visiblePositions,
    required this.positionSortMode,
    required this.snapshotAutomationMode,
    required this.snapshotRetention,
    required this.refreshPricesOnOpen,
    required this.refreshPricesAfterMovement,
    required this.priceRefreshForegroundMode,
    required this.sellFeePercent,
    required this.snapshotCount,
    required this.automaticLocalAlertsEnabled,
    required this.automaticLocalAlertsIntervalMinutes,
    required this.notificationsAllowed,
    required this.onVisualModeChanged,
    required this.onThemeStyleChanged,
    required this.onVisiblePositionsChanged,
    required this.onPositionSortModeChanged,
    required this.onSnapshotAutomationModeChanged,
    required this.onSnapshotRetentionChanged,
    required this.onRefreshPricesOnOpenChanged,
    required this.onRefreshPricesAfterMovementChanged,
    required this.onPriceRefreshForegroundModeChanged,
    required this.onEditSellFee,
    required this.onOpenAlerts,
    required this.onAutomaticLocalAlertsChanged,
    required this.onAutomaticLocalAlertIntervalChanged,
    required this.onSaveSnapshot,
    required this.onViewSnapshots,
    required this.onExportSnapshotsCsv,
    required this.onExportXlsx,
    required this.onExportPdf,
    required this.onExportBackup,
  });

  @override
  Widget build(BuildContext context) {
    final bool showTheme =
        view == SettingsView.all || view == SettingsView.theme;
    final bool showPortfolio =
        view == SettingsView.all || view == SettingsView.portfolio;
    final bool showPrices =
        view == SettingsView.all || view == SettingsView.prices;
    final bool showAdvanced = view == SettingsView.all;

    return PremiumScaffoldSurface(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          if (showTheme)
            CardPanel(
              title: 'Tema',
              subtitle:
                  'Paletas premium completas, sin alterar colores '
                  'semánticos financieros.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Modo visual',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<AppVisualMode>(
                      segments: AppVisualMode.values
                          .map(
                            (AppVisualMode mode) =>
                                ButtonSegment<AppVisualMode>(
                                  value: mode,
                                  label: Text(mode.label),
                                ),
                          )
                          .toList(),
                      selected: <AppVisualMode>{visualMode},
                      onSelectionChanged: (Set<AppVisualMode> value) {
                        onVisualModeChanged(value.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Estilo visual',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...AppThemeStyle.values.map(
                    (AppThemeStyle option) => _ThemePaletteTile(
                      option: option,
                      selected: themeStyle == option,
                      onTap: () => onThemeStyleChanged(option),
                    ),
                  ),
                ],
              ),
            ),
          if (showPortfolio)
            CardPanel(
              title: 'Resumen de cartera',
              subtitle:
                  'Configura cuántas posiciones aparecen en resumen y '
                  'cómo se ordenan.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Posiciones visibles',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: VisiblePositions.values.map((
                      VisiblePositions option,
                    ) {
                      return ChoiceChip(
                        selected: visiblePositions == option,
                        label: Text(option.label),
                        onSelected: (_) => onVisiblePositionsChanged(option),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('Orden', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...PositionSortMode.values.map(
                    (PositionSortMode option) =>
                        RadioListTile<PositionSortMode>(
                          contentPadding: EdgeInsets.zero,
                          value: option,
                          groupValue: positionSortMode,
                          title: Text(option.label),
                          onChanged: (PositionSortMode? value) {
                            if (value != null) onPositionSortModeChanged(value);
                          },
                        ),
                  ),
                ],
              ),
            ),
          if (showAdvanced)
            CardPanel(
              title: 'Cálculo',
              subtitle: 'Comisión de salida actual: ${pct(sellFeePercent)}',
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: onEditSellFee,
                  child: const Text('Editar comisión'),
                ),
              ),
            ),
          if (showPrices)
            CardPanel(
              title: 'Precios',
              subtitle: 'Preferencias de actualización de precios.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SwitchListTile(
                    dense: true,
                    value: refreshPricesOnOpen,
                    onChanged: onRefreshPricesOnOpenChanged,
                    title: const Text('Actualizar al abrir app'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    dense: true,
                    value: refreshPricesAfterMovement,
                    onChanged: onRefreshPricesAfterMovementChanged,
                    title: const Text(
                      'Actualizar después de registrar movimiento',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Actualización mientras la app está abierta:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: PriceRefreshForegroundMode.values.map((
                      PriceRefreshForegroundMode option,
                    ) {
                      return ChoiceChip(
                        selected: priceRefreshForegroundMode == option,
                        label: Text(option.label),
                        onSelected: (_) =>
                            onPriceRefreshForegroundModeChanged(option),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          if (showAdvanced)
            CardPanel(
              title: 'Instantáneas',
              subtitle:
                  'Instantáneas guardadas: $snapshotCount. Configura automatización y retención.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Automatización',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  ...SnapshotAutomationMode.values.map(
                    (SnapshotAutomationMode option) =>
                        RadioListTile<SnapshotAutomationMode>(
                          contentPadding: EdgeInsets.zero,
                          value: option,
                          groupValue: snapshotAutomationMode,
                          title: Text(option.label),
                          onChanged: (SnapshotAutomationMode? value) {
                            if (value != null)
                              onSnapshotAutomationModeChanged(value);
                          },
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Retención',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SnapshotRetention.values.map((
                      SnapshotRetention option,
                    ) {
                      return ChoiceChip(
                        selected: snapshotRetention == option,
                        label: Text(option.label),
                        onSelected: (_) => onSnapshotRetentionChanged(option),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Las acciones principales de instantáneas viven en '
                    'Más → Instantáneas. '
                    'Aquí solo se configura automatización y retención.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (showAdvanced)
            CardPanel(
              title: 'Notificaciones',
              subtitle:
                  'Configura comportamiento; la gestión completa vive en Alertas.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Alertas internas: al abrir app / actualizar precios.',
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    value: automaticLocalAlertsEnabled,
                    onChanged: onAutomaticLocalAlertsChanged,
                    title: const Text('Alertas automáticas locales'),
                    subtitle: Text(
                      notificationsAllowed
                          ? 'Revisión en segundo plano de Android.'
                          : 'Permiso no autorizado en Android.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Text(
                    'Android puede agrupar o retrasar revisiones para ahorrar batería. '
                    'No son notificaciones push en la nube.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: PriceAlertService.automaticIntervalOptions.map((
                      int minutes,
                    ) {
                      return ChoiceChip(
                        selected:
                            automaticLocalAlertsIntervalMinutes == minutes,
                        label: Text(intervalLabel(minutes)),
                        onSelected: (_) =>
                            onAutomaticLocalAlertIntervalChanged(minutes),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: onOpenAlerts,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Ir a Alertas'),
                  ),
                ],
              ),
            ),
          if (showAdvanced)
            CardPanel(
              title: 'Copia de seguridad',
              subtitle:
                  'Copia manual local para exportar o restaurar datos financieros.',
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onExportBackup,
                  icon: const Icon(Icons.data_object_outlined),
                  label: const Text('Crear copia manual'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemePaletteTile extends StatelessWidget {
  final AppThemeStyle option;
  final bool selected;
  final VoidCallback onTap;

  const _ThemePaletteTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = option.palette;
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? palette.primarySoft.withValues(alpha: 0.75)
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? palette.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? palette.primary
                      : colors.surface.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? palette.primary : colors.outlineVariant,
                  ),
                ),
                child: Icon(
                  selected ? Icons.check_rounded : Icons.palette_outlined,
                  size: 19,
                  color: selected
                      ? _bestOnColor(palette.primary)
                      : colors.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      option.label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(option.description),
                  ],
                ),
              ),
              Row(
                children:
                    <Color>[
                          palette.background,
                          palette.surfaceAlt,
                          palette.primary,
                          palette.positive,
                          palette.negative,
                          palette.warning,
                        ]
                        .map(
                          (Color color) => Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: palette.border),
                            ),
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SnapshotTrendPanel extends StatelessWidget {
  final List<PortfolioSnapshot> snapshots;
  final SummaryChartType chartType;

  const SnapshotTrendPanel({
    super.key,
    required this.snapshots,
    this.chartType = SummaryChartType.line,
  });

  @override
  Widget build(BuildContext context) {
    final List<PortfolioSnapshot> ordered = snapshots.toList()
      ..sort(
        (PortfolioSnapshot a, PortfolioSnapshot b) =>
            a.createdAt.compareTo(b.createdAt),
      );
    final ColorScheme colors = Theme.of(context).colorScheme;
    final PortfolioSnapshot first = ordered.first;
    final PortfolioSnapshot latest = ordered.last;
    final double valueChange =
        latest.totalCurrentValue - first.totalCurrentValue;
    final double plChange = latest.totalUnrealizedPL - first.totalUnrealizedPL;

    return CardPanel(
      title: 'Evolución histórica',
      subtitle: ordered.length < 2
          ? 'Necesitas otra instantánea para comparar la evolución.'
          : '${ordered.length} instantáneas entre '
                '${shortDate(first.createdAt)} y ${shortDate(latest.createdAt)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Vista comparativa',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Las leyendas agrupan las series activas del histórico.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (ordered.length >= 2) ...<Widget>[
            SnapshotLineChart(
              snapshots: ordered,
              height: 220,
              includeZero: true,
              chartType: chartType,
              series: <SnapshotChartSeries>[
                SnapshotChartSeries(
                  label: 'Valor actual',
                  color: colors.primary,
                  values: ordered
                      .map((PortfolioSnapshot s) => s.totalCurrentValue)
                      .toList(),
                ),
                SnapshotChartSeries(
                  label: 'Capital invertido',
                  color: colors.tertiary,
                  values: ordered
                      .map((PortfolioSnapshot s) => s.totalCostBase)
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SnapshotLineChart(
              snapshots: ordered,
              height: 180,
              includeZero: true,
              chartType: chartType,
              series: <SnapshotChartSeries>[
                SnapshotChartSeries(
                  label: 'P&L flotante',
                  color: pnlColor(latest.totalUnrealizedPL),
                  values: ordered
                      .map((PortfolioSnapshot s) => s.totalUnrealizedPL)
                      .toList(),
                ),
                SnapshotChartSeries(
                  label: 'P&L cerrado',
                  color: colors.secondary,
                  values: ordered
                      .map((PortfolioSnapshot s) => s.totalRealizedPL)
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SnapshotLineChart(
              snapshots: ordered,
              height: 170,
              includeZero: false,
              chartType: chartType,
              series: <SnapshotChartSeries>[
                SnapshotChartSeries(
                  label: 'Dominancia BTC',
                  color: const Color(0xFFF7931A),
                  values: ordered
                      .map((PortfolioSnapshot s) => s.btcDominancePercent)
                      .toList(),
                  valueFormatter: pct,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 20),
            const SizedBox(height: 4),
          ],
          if (ordered.length >= 2) ...<Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChartLegendDot(label: 'Valor actual', color: colors.primary),
                ChartLegendDot(
                  label: 'Capital invertido',
                  color: colors.tertiary,
                ),
                ChartLegendDot(
                  label: 'P&L flotante',
                  color: pnlColor(latest.totalUnrealizedPL),
                ),
                ChartLegendDot(label: 'P&L cerrado', color: colors.secondary),
                const ChartLegendDot(
                  label: 'Dominancia BTC',
                  color: Color(0xFFF7931A),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoLine(
              'Variación de cartera',
              money(valueChange),
              valueColor: pnlColor(valueChange),
              emphasized: true,
            ),
            InfoLine(
              'Variación de P&L flotante',
              money(plChange),
              valueColor: pnlColor(plChange),
            ),
          ],
          InfoLine('Dato actual', money(latest.totalCurrentValue)),
          InfoLine('Instantáneas guardadas', ordered.length.toString()),
        ],
      ),
    );
  }
}

class SnapshotLineChart extends StatelessWidget {
  final List<PortfolioSnapshot> snapshots;
  final List<SnapshotChartSeries> series;
  final double height;
  final bool includeZero;
  final SummaryChartType chartType;

  const SnapshotLineChart({
    super.key,
    required this.snapshots,
    required this.series,
    required this.height,
    required this.includeZero,
    this.chartType = SummaryChartType.line,
  });

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    if (chartType == SummaryChartType.candles) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'Velas requiere una serie OHLC.',
            style: TextStyle(color: Color(0xFF98A2B5)),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: SnapshotLineChartPainter(
          snapshots: snapshots,
          series: series,
          includeZero: includeZero,
          chartType: chartType,
          axisColor: tokens.chartGrid,
          labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          fillColor: tokens.chartFill,
          tooltipColor: tokens.chartTooltip,
        ),
      ),
    );
  }
}

class SnapshotChartSeries {
  final String label;
  final Color color;
  final List<double> values;
  final String Function(double value)? valueFormatter;

  const SnapshotChartSeries({
    required this.label,
    required this.color,
    required this.values,
    this.valueFormatter,
  });
}

class SnapshotLineChartPainter extends CustomPainter {
  final List<PortfolioSnapshot> snapshots;
  final List<SnapshotChartSeries> series;
  final bool includeZero;
  final SummaryChartType chartType;
  final Color axisColor;
  final Color labelColor;
  final Color fillColor;
  final Color tooltipColor;

  SnapshotLineChartPainter({
    required this.snapshots,
    required this.series,
    required this.includeZero,
    required this.chartType,
    required this.axisColor,
    required this.labelColor,
    required this.fillColor,
    required this.tooltipColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshots.isEmpty || series.isEmpty) return;

    final Rect chart = Rect.fromLTWH(
      54,
      12,
      math.max(1, size.width - 74),
      math.max(1, size.height - 42),
    );

    final Iterable<double> allValues = series.expand(
      (SnapshotChartSeries s) => s.values,
    );
    double minValue = allValues.reduce(math.min);
    double maxValue = allValues.reduce(math.max);
    if (includeZero) {
      minValue = math.min(minValue, 0);
      maxValue = math.max(maxValue, 0);
    }

    if ((maxValue - minValue).abs() < 0.000001) {
      final double pad = math.max(1, maxValue.abs() * 0.1);
      minValue -= pad;
      maxValue += pad;
    }

    final Paint gridPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final double y = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);

      final double value = maxValue - ((maxValue - minValue) * i / 4);
      final String label =
          series.length == 1 && series.first.valueFormatter != null
          ? series.first.valueFormatter!(value)
          : moneyShort(value);
      _drawLabel(canvas, label, Offset(0, y - 8), labelColor);
    }

    final int pointCount = snapshots.length;
    double xFor(int index) => pointCount == 1
        ? chart.center.dx
        : chart.left + chart.width * index / (pointCount - 1);
    double yFor(double value) =>
        chart.bottom -
        ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0) *
            chart.height;

    if (includeZero && minValue < 0 && maxValue > 0) {
      canvas.drawLine(
        Offset(chart.left, yFor(0)),
        Offset(chart.right, yFor(0)),
        Paint()
          ..color = axisColor.withValues(alpha: 0.9)
          ..strokeWidth = 1.5,
      );
    }

    for (int seriesIndex = 0; seriesIndex < series.length; seriesIndex++) {
      final SnapshotChartSeries item = series[seriesIndex];
      if (item.values.length != pointCount) continue;

      final List<Offset> points = List<Offset>.generate(
        pointCount,
        (int index) => Offset(xFor(index), yFor(item.values[index])),
      );
      final Path path = Path();
      path.moveTo(points.first.dx, points.first.dy);
      for (final Offset point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }

      final Paint linePaint = Paint()
        ..color = item.color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final Paint dotPaint = Paint()..color = item.color;

      if (chartType == SummaryChartType.columns) {
        final double slotWidth = chart.width / math.max(1, pointCount);
        final double groupWidth = math.min(22.0, slotWidth * 0.66);
        final double barWidth = math.max(2.0, groupWidth / series.length);
        final double baseline = includeZero ? yFor(0) : chart.bottom;
        for (int i = 0; i < pointCount; i++) {
          final double top = math.min(points[i].dy, baseline);
          final double barHeight = math.max(
            1.0,
            (points[i].dy - baseline).abs(),
          );
          final double left =
              points[i].dx - groupWidth / 2 + seriesIndex * barWidth;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, top, math.max(1, barWidth - 1), barHeight),
              const Radius.circular(2),
            ),
            Paint()..color = item.color.withValues(alpha: 0.82),
          );
        }
      } else {
        if (chartType == SummaryChartType.area) {
          final Path areaPath = Path.from(path)
            ..lineTo(points.last.dx, chart.bottom)
            ..lineTo(points.first.dx, chart.bottom)
            ..close();
          canvas.drawPath(
            areaPath,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[fillColor, fillColor.withValues(alpha: 0.03)],
              ).createShader(chart),
          );
        }
        canvas.drawPath(path, linePaint);
        if (chartType == SummaryChartType.lineMarkers) {
          for (final Offset point in points) {
            canvas.drawCircle(point, 3.5, dotPaint);
          }
        }
      }

      final Offset lastPoint = points.last;
      if (chartType != SummaryChartType.columns) {
        canvas.drawCircle(
          lastPoint,
          7.0,
          Paint()..color = item.color.withValues(alpha: 0.16),
        );
        canvas.drawCircle(lastPoint, 4.8, dotPaint);
      }
      _drawValueTag(
        canvas,
        item.valueFormatter?.call(item.values.last) ??
            moneyShort(item.values.last),
        lastPoint.translate(10, -12 - (seriesIndex * 16.0)),
        chart,
        item.color,
      );
    }

    _drawLabel(
      canvas,
      shortDate(snapshots.first.createdAt),
      Offset(chart.left, chart.bottom + 10),
      labelColor,
    );
    _drawLabel(
      canvas,
      shortDate(snapshots.last.createdAt),
      Offset(chart.right - 82, chart.bottom + 10),
      labelColor,
    );
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 90);
    painter.paint(canvas, offset);
  }

  void _drawValueTag(
    Canvas canvas,
    String text,
    Offset anchor,
    Rect chart,
    Color color,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: math.min(120, chart.width * 0.45));
    const double padX = 6;
    const double padY = 4;
    double x = anchor.dx;
    double y = anchor.dy;
    if (x + painter.width + padX * 2 > chart.right) {
      x = anchor.dx - painter.width - padX * 2 - 20;
    }
    if (x < chart.left) x = chart.left + 4;
    if (y < chart.top) y = anchor.dy + 14;
    if (y + painter.height + padY * 2 > chart.bottom) {
      y = chart.bottom - painter.height - padY * 2 - 4;
    }
    final Rect background = Rect.fromLTWH(
      x,
      y,
      painter.width + padX * 2,
      painter.height + padY * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(background, const Radius.circular(6)),
      Paint()
        ..color = Color.alphaBlend(color.withValues(alpha: 0.08), tooltipColor),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(background, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.45),
    );
    painter.paint(canvas, Offset(x + padX, y + padY));
  }

  @override
  bool shouldRepaint(covariant SnapshotLineChartPainter oldDelegate) {
    return oldDelegate.snapshots != snapshots ||
        oldDelegate.series != series ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.tooltipColor != tooltipColor ||
        oldDelegate.chartType != chartType ||
        oldDelegate.includeZero != includeZero;
  }
}

class ChartLegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const ChartLegendDot({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _positionStatusLabel(CoinStats stats, double sellFeePercent) {
  if (stats.quantity <= 0) return 'Sin posición';
  if (stats.isAtOrAboveNetBreakEven(sellFeePercent))
    return 'Arriba del equilibrio';
  final double distance = stats.percentToNetBreakEven(sellFeePercent);
  if (stats.unrealizedPL < 0 && distance > 25) return 'Fuerte pérdida';
  if (distance > 10) return 'Debajo del equilibrio';
  return 'Vigilar';
}

enum PremiumStatusTone { positive, negative, warning, neutral, accent }

class PremiumScaffoldSurface extends StatelessWidget {
  final Widget child;

  const PremiumScaffoldSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            tokens.gradientStart,
            tokens.backgroundSecondary,
            tokens.gradientEnd,
          ],
          stops: const <double>[0, 0.46, 1],
        ),
      ),
      child: SafeArea(top: false, bottom: false, child: child),
    );
  }
}

class PremiumSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const PremiumSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Container(
            width: 3,
            height: subtitle == null ? 22 : 38,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...<Widget>[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

class PremiumCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const PremiumCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    final BorderRadius borderRadius = BorderRadius.circular(tokens.cardRadius);
    final Widget content = Padding(padding: padding, child: child);

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[tokens.surfaceElevated, tokens.cardBackground],
        ),
        border: Border.all(color: tokens.cardBorder, width: tokens.borderWidth),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow.withValues(alpha: tokens.shadowOpacity),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class PremiumStatusBadge extends StatelessWidget {
  final String label;
  final PremiumStatusTone tone;

  const PremiumStatusBadge({
    super.key,
    required this.label,
    this.tone = PremiumStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    final Color color = switch (tone) {
      PremiumStatusTone.positive => tokens.secondaryAccent,
      PremiumStatusTone.negative => colors.error,
      PremiumStatusTone.warning => tokens.tertiaryAccent,
      PremiumStatusTone.accent => tokens.primaryAccent,
      PremiumStatusTone.neutral => colors.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class PremiumEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PremiumEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ccmx.CcmxVisualTokens tokens = ccmx.CcmxVisualTokens.of(context);
    return PremiumCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: tokens.primaryAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: tokens.selectedBorder.withValues(alpha: 0.42),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: tokens.glowColor,
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: tokens.primaryAccent, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PopupActionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _PopupActionLabel({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final Color resolvedColor =
        color ?? Theme.of(context).colorScheme.onSurface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18, color: resolvedColor),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: resolvedColor, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class PremiumMetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const PremiumMetricData({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
}

class PremiumDashboardHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<PremiumMetricData> metrics;

  const PremiumDashboardHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.primaryContainer.withValues(alpha: 0.72),
            colors.surfaceContainerHighest.withValues(alpha: 0.82),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: 0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.05),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon, color: colors.primary, size: 30),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics
                .map(
                  (PremiumMetricData metric) => _HeaderMetric(
                    label: metric.label,
                    value: metric.value,
                    icon: metric.icon,
                    color: metric.color,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class PremiumSegmentShell extends StatelessWidget {
  final Widget child;

  const PremiumSegmentShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Center(child: child),
    );
  }
}

class PremiumMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;
  final String? statusLabel;
  final PremiumStatusTone statusTone;

  const PremiumMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
    this.statusLabel,
    this.statusTone = PremiumStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Row(
        children: <Widget>[
          Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
                if (statusLabel != null) ...<Widget>[
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PremiumStatusBadge(
                      label: statusLabel!,
                      tone: statusTone,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumInfoPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final Color? badgeColor;

  const PremiumInfoPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Row(
        children: <Widget>[
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(subtitle),
                if (badge != null) ...<Widget>[
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(
                      label: badge!,
                      positive: (badgeColor ?? Colors.green) == Colors.green,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const MiniMetric({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 126, maxWidth: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}

class CardPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;

  const CardPanel({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PremiumCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: content,
      ),
    );
  }
}

class SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const SheetHeader({super.key, required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
      ],
    );
  }
}

class MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final Color? valueColor;

  const MetricTile({
    super.key,
    required this.title,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }
}

class SimpleValue extends StatelessWidget {
  final String title;
  final String value;
  final Color? color;

  const SimpleValue({
    super.key,
    required this.title,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

class InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;

  const InfoLine(
    this.label,
    this.value, {
    super.key,
    this.emphasized = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          final bool stacked = constraints.maxWidth < 300 || textScale >= 1.4;
          final TextStyle valueStyle = TextStyle(
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
            color: valueColor,
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(value, style: valueStyle),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 5, child: Text(label)),
              Expanded(
                flex: 6,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: valueStyle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final bool positive;

  const StatusPill({super.key, required this.label, required this.positive});

  @override
  Widget build(BuildContext context) {
    return PremiumStatusBadge(
      label: label,
      tone: positive ? PremiumStatusTone.positive : PremiumStatusTone.negative,
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(icon: icon, title: title, description: subtitle);
  }
}

List<CoinStats> sortedPositions(
  Iterable<CoinStats> positions,
  PositionSortMode mode,
  double sellFeePercent,
) {
  final List<CoinStats> sorted = positions.toList();
  switch (mode) {
    case PositionSortMode.largestValue:
      sorted.sort(
        (CoinStats a, CoinStats b) => b.currentValue.compareTo(a.currentValue),
      );
      break;
    case PositionSortMode.largestLoss:
      sorted.sort(
        (CoinStats a, CoinStats b) => a.unrealizedPL.compareTo(b.unrealizedPL),
      );
      break;
    case PositionSortMode.closestBreakEven:
      sorted.sort((CoinStats a, CoinStats b) {
        final double da = (a.percentToNetBreakEven(sellFeePercent)).abs();
        final double db = (b.percentToNetBreakEven(sellFeePercent)).abs();
        return da.compareTo(db);
      });
      break;
    case PositionSortMode.manual:
      sorted.sort((CoinStats a, CoinStats b) => a.coin.compareTo(b.coin));
      break;
  }
  return sorted;
}

ThemeData buildPremiumTheme(AppPalette palette, Brightness brightness) {
  final ColorScheme scheme = palette.toColorScheme(brightness);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    cardTheme: CardThemeData(
      elevation: 0,
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.border.withValues(alpha: 0.55)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.textMain,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface,
      indicatorColor: palette.primarySoft,
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(color: palette.textMain, fontWeight: FontWeight.w700),
      ),
    ),
    dividerColor: palette.border,
    chipTheme: ChipThemeData(
      backgroundColor: palette.surfaceAlt,
      selectedColor: palette.primarySoft,
      side: BorderSide(color: palette.border),
      labelStyle: TextStyle(color: palette.textMain),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.border),
      ),
    ),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: palette.textMain,
      displayColor: palette.textMain,
    ),
  );
}

enum AppVisualMode { system, light, dark }

extension AppVisualModeLabel on AppVisualMode {
  String get label {
    switch (this) {
      case AppVisualMode.system:
        return 'Auto';
      case AppVisualMode.light:
        return 'Claro';
      case AppVisualMode.dark:
        return 'Oscuro';
    }
  }

  ThemeMode get themeMode {
    switch (this) {
      case AppVisualMode.system:
        return ThemeMode.system;
      case AppVisualMode.light:
        return ThemeMode.light;
      case AppVisualMode.dark:
        return ThemeMode.dark;
    }
  }
}

AppVisualMode appVisualModeFromName(String? value) {
  for (final AppVisualMode mode in AppVisualMode.values) {
    if (mode.name == value) return mode;
  }
  return AppVisualMode.system;
}

enum PriceRefreshForegroundMode {
  manual,
  every25Seconds,
  everyMinute,
  every15Minutes,
  daily,
}

extension PriceRefreshForegroundModeLabel on PriceRefreshForegroundMode {
  String get label => switch (this) {
    PriceRefreshForegroundMode.manual => 'Manual',
    PriceRefreshForegroundMode.every25Seconds => '25 s',
    PriceRefreshForegroundMode.everyMinute => '1 min',
    PriceRefreshForegroundMode.every15Minutes => '15 min',
    PriceRefreshForegroundMode.daily => 'Diario',
  };

  Duration? get interval => switch (this) {
    PriceRefreshForegroundMode.manual => null,
    PriceRefreshForegroundMode.every25Seconds => const Duration(seconds: 25),
    PriceRefreshForegroundMode.everyMinute => const Duration(minutes: 1),
    PriceRefreshForegroundMode.every15Minutes => const Duration(minutes: 15),
    PriceRefreshForegroundMode.daily => const Duration(days: 1),
  };
}

PriceRefreshForegroundMode priceRefreshForegroundModeFromName(String? value) {
  for (final PriceRefreshForegroundMode mode
      in PriceRefreshForegroundMode.values) {
    if (mode.name == value) return mode;
  }
  return PriceRefreshForegroundMode.manual;
}

class AppPalette {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color primarySoft;
  final Color border;
  final Color positive;
  final Color negative;
  final Color warning;
  final Color textMain;
  final Color textMuted;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.primarySoft,
    required this.border,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.textMain,
    required this.textMuted,
  });

  ColorScheme toColorScheme(Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: _bestOnColor(primary),
        primaryContainer: primarySoft,
        onPrimaryContainer: textMain,
        secondary: positive,
        onSecondary: _bestOnColor(positive),
        secondaryContainer: positive.withValues(alpha: 0.18),
        onSecondaryContainer: textMain,
        tertiary: warning,
        onTertiary: _bestOnColor(warning),
        tertiaryContainer: warning.withValues(alpha: 0.20),
        onTertiaryContainer: textMain,
        error: negative,
        onError: _bestOnColor(negative),
        errorContainer: negative.withValues(alpha: 0.18),
        onErrorContainer: textMain,
        surface: surface,
        onSurface: textMain,
        surfaceContainerHighest: surfaceAlt,
        onSurfaceVariant: textMuted,
        outline: border,
        outlineVariant: border.withValues(alpha: 0.55),
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: textMain,
        onInverseSurface: surface,
        inversePrimary: primarySoft,
      );
}

Color _bestOnColor(Color color) {
  return color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
}

enum AppThemeStyle {
  proDark,
  graphite,
  institutionalBlue,
  bitcoinDark,
  terminalGreen,
  highContrast,
}

extension AppThemeStyleDetails on AppThemeStyle {
  String get label {
    switch (this) {
      case AppThemeStyle.proDark:
        return 'Pro oscuro';
      case AppThemeStyle.graphite:
        return 'Grafito';
      case AppThemeStyle.institutionalBlue:
        return 'Azul institucional';
      case AppThemeStyle.bitcoinDark:
        return 'Bitcoin dark';
      case AppThemeStyle.terminalGreen:
        return 'Verde terminal';
      case AppThemeStyle.highContrast:
        return 'Alto contraste';
    }
  }

  String get description {
    switch (this) {
      case AppThemeStyle.proDark:
        return 'OLED de lujo con violeta profundo y superficies elevadas.';
      case AppThemeStyle.graphite:
        return 'Grafito ejecutivo, mínimo y editorial.';
      case AppThemeStyle.institutionalBlue:
        return 'Banca profesional con azul Bloomberg sobrio.';
      case AppThemeStyle.bitcoinDark:
        return 'Carbón premium con cobre y naranja Bitcoin.';
      case AppThemeStyle.terminalGreen:
        return 'Trading terminal, verde técnico y alto foco.';
      case AppThemeStyle.highContrast:
        return 'Accesibilidad premium con contraste limpio.';
    }
  }

  AppPalette get palette {
    switch (this) {
      case AppThemeStyle.proDark:
        return const AppPalette(
          background: Color(0xFF02030A),
          surface: Color(0xFF0A0D18),
          surfaceAlt: Color(0xFF151A2B),
          primary: Color(0xFFA78BFA),
          primarySoft: Color(0xFF241B4A),
          border: Color(0xFF2B3150),
          positive: Color(0xFF2DD4BF),
          negative: Color(0xFFFB7185),
          warning: Color(0xFFFBBF24),
          textMain: Color(0xFFFAFBFF),
          textMuted: Color(0xFF9AA6C1),
        );
      case AppThemeStyle.graphite:
        return const AppPalette(
          background: Color(0xFF0F1012),
          surface: Color(0xFF181A1D),
          surfaceAlt: Color(0xFF24272B),
          primary: Color(0xFFE5E7EB),
          primarySoft: Color(0xFF30343A),
          border: Color(0xFF3A3F46),
          positive: Color(0xFF34D399),
          negative: Color(0xFFF87171),
          warning: Color(0xFFF59E0B),
          textMain: Color(0xFFF8FAFC),
          textMuted: Color(0xFFA7ADB7),
        );
      case AppThemeStyle.institutionalBlue:
        return const AppPalette(
          background: Color(0xFF03101F),
          surface: Color(0xFF071A31),
          surfaceAlt: Color(0xFF102B4E),
          primary: Color(0xFF38BDF8),
          primarySoft: Color(0xFF0D3A68),
          border: Color(0xFF1F5A89),
          positive: Color(0xFF22C55E),
          negative: Color(0xFFEF4444),
          warning: Color(0xFFEAB308),
          textMain: Color(0xFFF8FBFF),
          textMuted: Color(0xFF9CB7D6),
        );
      case AppThemeStyle.bitcoinDark:
        return const AppPalette(
          background: Color(0xFF080604),
          surface: Color(0xFF14100B),
          surfaceAlt: Color(0xFF281A0E),
          primary: Color(0xFFF59E0B),
          primarySoft: Color(0xFF43270B),
          border: Color(0xFF6B4518),
          positive: Color(0xFF84CC16),
          negative: Color(0xFFEF4444),
          warning: Color(0xFFF97316),
          textMain: Color(0xFFFFF7ED),
          textMuted: Color(0xFFD4B483),
        );
      case AppThemeStyle.terminalGreen:
        return const AppPalette(
          background: Color(0xFF010805),
          surface: Color(0xFF06120B),
          surfaceAlt: Color(0xFF0C2616),
          primary: Color(0xFF4ADE80),
          primarySoft: Color(0xFF0B3B21),
          border: Color(0xFF14532D),
          positive: Color(0xFF22C55E),
          negative: Color(0xFFFB7185),
          warning: Color(0xFFFACC15),
          textMain: Color(0xFFF0FFF7),
          textMuted: Color(0xFF8BC7A2),
        );
      case AppThemeStyle.highContrast:
        return const AppPalette(
          background: Color(0xFF000000),
          surface: Color(0xFF080808),
          surfaceAlt: Color(0xFF171717),
          primary: Color(0xFFFFFFFF),
          primarySoft: Color(0xFF262626),
          border: Color(0xFFFFFFFF),
          positive: Color(0xFF00F57A),
          negative: Color(0xFFFF3355),
          warning: Color(0xFFFFD600),
          textMain: Color(0xFFFFFFFF),
          textMuted: Color(0xFFE6E6E6),
        );
    }
  }
}

AppThemeStyle appThemeStyleFromName(String? value) {
  switch (value) {
    case 'green':
      return AppThemeStyle.terminalGreen;
    case 'blue':
      return AppThemeStyle.institutionalBlue;
    case 'orange':
    case 'bitcoin':
      return AppThemeStyle.bitcoinDark;
    case 'grey':
      return AppThemeStyle.graphite;
  }
  for (final AppThemeStyle style in AppThemeStyle.values) {
    if (style.name == value) return style;
  }
  return AppThemeStyle.proDark;
}

enum VisiblePositions { one, two, three, five, all }

extension VisiblePositionsDetails on VisiblePositions {
  String get label {
    switch (this) {
      case VisiblePositions.one:
        return '1';
      case VisiblePositions.two:
        return '2';
      case VisiblePositions.three:
        return '3';
      case VisiblePositions.five:
        return '5';
      case VisiblePositions.all:
        return 'Todas';
    }
  }

  int? get limit {
    switch (this) {
      case VisiblePositions.one:
        return 1;
      case VisiblePositions.two:
        return 2;
      case VisiblePositions.three:
        return 3;
      case VisiblePositions.five:
        return 5;
      case VisiblePositions.all:
        return null;
    }
  }
}

VisiblePositions visiblePositionsFromName(String? value) {
  for (final VisiblePositions option in VisiblePositions.values) {
    if (option.name == value) return option;
  }
  return VisiblePositions.three;
}

enum PositionSortMode { largestValue, largestLoss, closestBreakEven, manual }

extension PositionSortModeDetails on PositionSortMode {
  String get label {
    switch (this) {
      case PositionSortMode.largestValue:
        return 'Mayor valor';
      case PositionSortMode.largestLoss:
        return 'Mayor pérdida';
      case PositionSortMode.closestBreakEven:
        return 'Más cerca del equilibrio';
      case PositionSortMode.manual:
        return 'Manual';
    }
  }
}

PositionSortMode positionSortModeFromName(String? value) {
  for (final PositionSortMode mode in PositionSortMode.values) {
    if (mode.name == value) return mode;
  }
  return PositionSortMode.largestValue;
}

enum SnapshotTrigger { appOpen, priceUpdate, movementChange, daily }

enum SnapshotAutomationMode {
  manual,
  appOpen24h,
  afterPriceUpdate,
  afterMovementChange,
  daily,
}

extension SnapshotAutomationModeDetails on SnapshotAutomationMode {
  String get label {
    switch (this) {
      case SnapshotAutomationMode.manual:
        return 'Solo manual';
      case SnapshotAutomationMode.appOpen24h:
        return 'Al abrir si pasaron 24h';
      case SnapshotAutomationMode.afterPriceUpdate:
        return 'Después de actualizar precios';
      case SnapshotAutomationMode.afterMovementChange:
        return 'Después de cambiar movimientos';
      case SnapshotAutomationMode.daily:
        return 'Diario';
    }
  }

  bool shouldCapture(
    SnapshotTrigger trigger,
    List<PortfolioSnapshot> snapshots,
  ) {
    final DateTime? latest = snapshots.isEmpty
        ? null
        : snapshots.first.createdAt;
    final bool olderThan24h =
        latest == null ||
        DateTime.now().difference(latest) >= const Duration(hours: 24);
    switch (this) {
      case SnapshotAutomationMode.manual:
        return false;
      case SnapshotAutomationMode.appOpen24h:
        return trigger == SnapshotTrigger.appOpen && olderThan24h;
      case SnapshotAutomationMode.afterPriceUpdate:
        return trigger == SnapshotTrigger.priceUpdate;
      case SnapshotAutomationMode.afterMovementChange:
        return trigger == SnapshotTrigger.movementChange;
      case SnapshotAutomationMode.daily:
        return olderThan24h &&
            (trigger == SnapshotTrigger.appOpen ||
                trigger == SnapshotTrigger.daily);
    }
  }
}

SnapshotAutomationMode snapshotAutomationModeFromName(String? value) {
  for (final SnapshotAutomationMode mode in SnapshotAutomationMode.values) {
    if (mode.name == value) return mode;
  }
  return SnapshotAutomationMode.manual;
}

enum SnapshotRetention { last30, last90, unlimited }

extension SnapshotRetentionDetails on SnapshotRetention {
  String get label {
    switch (this) {
      case SnapshotRetention.last30:
        return 'Últimas 30 instantáneas';
      case SnapshotRetention.last90:
        return 'Últimas 90 instantáneas';
      case SnapshotRetention.unlimited:
        return 'Sin límite';
    }
  }

  int? get limit {
    switch (this) {
      case SnapshotRetention.last30:
        return 30;
      case SnapshotRetention.last90:
        return 90;
      case SnapshotRetention.unlimited:
        return null;
    }
  }
}

SnapshotRetention snapshotRetentionFromName(String? value) {
  for (final SnapshotRetention retention in SnapshotRetention.values) {
    if (retention.name == value) return retention;
  }
  return SnapshotRetention.last30;
}

enum MovementType { buy, sell, transferIn, transferOut }

enum SimulationMode { operation, rotation }

enum OperationSimulationMode { buy, sell }

enum SimulationSellMethod { percent, quantity, grossAmount }

enum SimulationRotationMethod { percent, quantity, grossAmount }

extension MovementLabel on MovementType {
  String get label {
    switch (this) {
      case MovementType.buy:
        return 'Compra';
      case MovementType.sell:
        return 'Venta';
      case MovementType.transferIn:
        return 'Transferencia recibida';
      case MovementType.transferOut:
        return 'Transferencia enviada';
    }
  }

  String get shortLabel {
    switch (this) {
      case MovementType.buy:
        return 'Compra';
      case MovementType.sell:
        return 'Venta';
      case MovementType.transferIn:
        return 'Entrada';
      case MovementType.transferOut:
        return 'Salida';
    }
  }
}

MovementType movementTypeFromAny(dynamic value) {
  final String raw = value?.toString().trim().toLowerCase() ?? '';

  if (raw == 'buy' || raw == 'compra' || raw == 'comprar') {
    return MovementType.buy;
  }

  if (raw == 'sell' || raw == 'venta' || raw == 'vender') {
    return MovementType.sell;
  }

  if (raw == 'transferin' ||
      raw == 'transfer_in' ||
      raw == 'transferenciaentrada' ||
      raw == 'transferencia_entrada' ||
      raw == 'transferencia recibida' ||
      raw == 'recibida' ||
      raw == 'entrada') {
    return MovementType.transferIn;
  }

  if (raw == 'transferout' ||
      raw == 'transfer_out' ||
      raw == 'transferenciasalida' ||
      raw == 'transferencia_salida' ||
      raw == 'transferencia enviada' ||
      raw == 'enviada' ||
      raw == 'salida') {
    return MovementType.transferOut;
  }

  return MovementType.buy;
}

class FinancialEngine {
  static const double defaultExitFeePercent = 0.0;

  const FinancialEngine._();

  static Map<String, CoinStats> computeStats({
    required List<String> coins,
    required List<Movement> movements,
    required Map<String, double> currentPrices,
  }) {
    final Map<String, CoinStats> stats = <String, CoinStats>{
      for (final String coin in coins)
        coin: CoinStats(coin: coin, currentPrice: currentPrices[coin] ?? 0.0),
    };

    final List<MapEntry<int, Movement>> indexed =
        movements.asMap().entries.toList()
          ..sort((MapEntry<int, Movement> a, MapEntry<int, Movement> b) {
            final int dateCompare = a.value.date.compareTo(b.value.date);
            if (dateCompare != 0) return dateCompare;
            return a.key.compareTo(b.key);
          });

    for (final MapEntry<int, Movement> entry in indexed) {
      final Movement movement = entry.value;
      final CoinStats? stat = stats[movement.coin];
      if (stat == null) continue;

      switch (movement.type) {
        case MovementType.buy:
        case MovementType.transferIn:
          stat.quantity += movement.quantity;
          stat.costBase += movement.grossTotal + movement.fee;
          stat.totalInvested += movement.grossTotal + movement.fee;
          stat.feesPaid += movement.fee;
          break;

        case MovementType.sell:
          final double average = stat.quantity > 0
              ? stat.costBase / stat.quantity
              : 0.0;
          final double quantityToRemove = movement.quantity > stat.quantity
              ? stat.quantity
              : movement.quantity;
          final double removedCost = average * quantityToRemove;
          final double proceeds = movement.grossTotal - movement.fee;

          stat.realizedPL += proceeds - removedCost;
          stat.quantity -= quantityToRemove;
          stat.costBase -= removedCost;
          stat.feesPaid += movement.fee;
          break;

        case MovementType.transferOut:
          final double average = stat.quantity > 0
              ? stat.costBase / stat.quantity
              : 0.0;
          final double quantityToRemove = movement.quantity > stat.quantity
              ? stat.quantity
              : movement.quantity;
          final double removedCost = average * quantityToRemove;

          stat.quantity -= quantityToRemove;
          stat.costBase -= removedCost;
          stat.feesPaid += movement.fee;
          break;
      }

      if (stat.quantity.abs() < 0.0000000001) {
        stat.quantity = 0.0;
        stat.costBase = 0.0;
      }

      if (stat.costBase.abs() < 0.00000001) {
        stat.costBase = 0.0;
      }
    }

    for (final String coin in coins) {
      stats[coin]!.currentPrice = currentPrices[coin] ?? 0.0;
    }

    return stats;
  }

  static PortfolioTotals totals(Map<String, CoinStats> stats) {
    return PortfolioTotals(
      costBase: stats.values.fold<double>(
        0.0,
        (double sum, CoinStats s) => sum + s.costBase,
      ),
      currentValue: stats.values.fold<double>(
        0.0,
        (double sum, CoinStats s) => sum + s.currentValue,
      ),
      unrealizedPL: stats.values.fold<double>(
        0.0,
        (double sum, CoinStats s) => sum + s.unrealizedPL,
      ),
      realizedPL: stats.values.fold<double>(
        0.0,
        (double sum, CoinStats s) => sum + s.realizedPL,
      ),
      feesPaid: stats.values.fold<double>(
        0.0,
        (double sum, CoinStats s) => sum + s.feesPaid,
      ),
    );
  }

  static bool wouldCreateInvalidPosition({
    required List<String> coins,
    required List<Movement> movements,
    required Movement candidate,
    int? replaceIndex,
  }) {
    final List<Movement> testList = <Movement>[...movements];

    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < testList.length) {
      testList[replaceIndex] = candidate;
    } else {
      testList.add(candidate);
    }

    final Map<String, double> balances = <String, double>{
      for (final String coin in coins) coin: 0.0,
    };

    final List<MapEntry<int, Movement>> indexed =
        testList.asMap().entries.toList()
          ..sort((MapEntry<int, Movement> a, MapEntry<int, Movement> b) {
            final int dateCompare = a.value.date.compareTo(b.value.date);
            if (dateCompare != 0) return dateCompare;
            return a.key.compareTo(b.key);
          });

    for (final MapEntry<int, Movement> entry in indexed) {
      final Movement movement = entry.value;
      final double current = balances[movement.coin] ?? 0.0;

      switch (movement.type) {
        case MovementType.buy:
        case MovementType.transferIn:
          balances[movement.coin] = current + movement.quantity;
          break;
        case MovementType.sell:
        case MovementType.transferOut:
          if (movement.quantity > current + 0.0000000001) return true;
          balances[movement.coin] = current - movement.quantity;
          break;
      }
    }

    return false;
  }

  static bool wouldCreateDuplicateMovement({
    required List<Movement> movements,
    required Movement candidate,
    int? replaceIndex,
  }) {
    for (int i = 0; i < movements.length; i++) {
      if (replaceIndex != null && i == replaceIndex) continue;
      if (movements[i].isFinanciallyIdenticalTo(candidate)) return true;
    }
    return false;
  }

  static List<String> diagnostics({
    required List<String> coins,
    required List<Movement> movements,
    required List<PortfolioSnapshot> snapshots,
    required Map<String, double> currentPrices,
  }) {
    final List<String> errors = <String>[];

    for (int i = 0; i < movements.length; i++) {
      final Movement movement = movements[i];
      final int number = i + 1;
      if (!coins.contains(movement.coin)) {
        errors.add('Movimiento #$number tiene moneda no soportada');
      }
      if (movement.quantity <= 0) {
        errors.add('Movimiento #$number tiene cantidad en cero o negativa');
      }
      if (movement.unitPrice <= 0) {
        errors.add('Movimiento #$number tiene precio en cero o negativo');
      }
      if (movement.grossTotal <= 0) {
        errors.add('Movimiento #$number tiene total MXN en cero');
      }
      if (movement.fee < 0) {
        errors.add('Movimiento #$number tiene comisión negativa');
      }
      if (movement.date.isAfter(
        DateTime.now().add(const Duration(minutes: 5)),
      )) {
        errors.add('Movimiento #$number tiene fecha futura');
      }
      for (int j = i + 1; j < movements.length; j++) {
        if (movement.isFinanciallyIdenticalTo(movements[j])) {
          errors.add('Posible duplicado: movimientos #$number y #${j + 1}');
        }
      }
    }

    final Map<String, double> historicalBalances = <String, double>{
      for (final String coin in coins) coin: 0.0,
    };
    final Set<String> balanceWarnings = <String>{};
    final List<MapEntry<int, Movement>> orderedMovements =
        movements.asMap().entries.toList()
          ..sort((MapEntry<int, Movement> a, MapEntry<int, Movement> b) {
            final int dateCompare = a.value.date.compareTo(b.value.date);
            return dateCompare != 0 ? dateCompare : a.key.compareTo(b.key);
          });
    for (final MapEntry<int, Movement> entry in orderedMovements) {
      final Movement movement = entry.value;
      final double current = historicalBalances[movement.coin] ?? 0.0;
      switch (movement.type) {
        case MovementType.buy:
        case MovementType.transferIn:
          historicalBalances[movement.coin] = current + movement.quantity;
          break;
        case MovementType.sell:
        case MovementType.transferOut:
          if (movement.quantity > current + 0.0000000001) {
            final String warningKey =
                '${movement.type == MovementType.sell ? 'sell' : 'transferOut'}:${movement.coin}';
            if (balanceWarnings.add(warningKey)) {
              errors.add(
                movement.type == MovementType.sell
                    ? 'Venta excedida al saldo disponible en ${movement.coin}'
                    : 'Salida excedida al saldo disponible en ${movement.coin}',
              );
            }
          }
          historicalBalances[movement.coin] = current - movement.quantity;
          break;
      }
    }

    if (wouldCreateInvalidHistoricalBalance(movements)) {
      errors.add('Histórico inconsistente: balance negativo detectado');
    }

    for (final String coin in coins) {
      if (!currentPrices.containsKey(coin)) {
        errors.add('Precio faltante para $coin');
      } else if ((currentPrices[coin] ?? 0.0) <= 0) {
        errors.add('Precio no disponible para $coin');
      }
    }

    bool differs(double a, double b) => (a - b).abs() > 0.01;
    var hasFutureSnapshot = false,
        hasUnsupportedSnapshotCoin = false,
        hasSnapshotMovementMismatch = false,
        hasSnapshotTotalsMismatch = false;
    for (final PortfolioSnapshot snapshot in snapshots) {
      if (snapshot.createdAt.isAfter(
        DateTime.now().add(const Duration(minutes: 5)),
      )) {
        hasFutureSnapshot = true;
      }
      if (snapshot.movementCount > movements.length) {
        hasSnapshotMovementMismatch = true;
      }
      if (snapshot.coins.any((CoinSnapshot c) => !coins.contains(c.coin))) {
        hasUnsupportedSnapshotCoin = true;
      }
      if (snapshot.coins.isNotEmpty) {
        final double costBase = snapshot.coins.fold<double>(
          0.0,
          (double sum, CoinSnapshot coin) => sum + coin.costBase,
        );
        final double currentValue = snapshot.coins.fold<double>(
          0.0,
          (double sum, CoinSnapshot coin) => sum + coin.currentValue,
        );
        final double unrealizedPL = snapshot.coins.fold<double>(
          0.0,
          (double sum, CoinSnapshot coin) => sum + coin.unrealizedPL,
        );
        if (differs(costBase, snapshot.totalCostBase) ||
            differs(currentValue, snapshot.totalCurrentValue) ||
            differs(unrealizedPL, snapshot.totalUnrealizedPL)) {
          hasSnapshotTotalsMismatch = true;
        }
      }
    }
    if (hasFutureSnapshot) errors.add('Snapshot con fecha futura');
    if (hasUnsupportedSnapshotCoin)
      errors.add('Snapshot desalineado: moneda no soportada');
    if (hasSnapshotMovementMismatch)
      errors.add('Snapshot desalineado: movimientos mayores al ledger actual');
    if (hasSnapshotTotalsMismatch)
      errors.add('Snapshot desalineado: totales no coinciden con monedas');

    return errors;
  }

  static bool wouldCreateInvalidHistoricalBalance(List<Movement> movements) {
    final Set<String> coins = movements.map((Movement m) => m.coin).toSet();
    return wouldCreateInvalidPosition(
      coins: coins.toList(),
      movements: movements,
      candidate: Movement(
        type: MovementType.buy,
        coin: coins.isEmpty ? 'BTC' : coins.first,
        date: DateTime.fromMillisecondsSinceEpoch(0),
        quantity: 0.00000001,
        unitPrice: 1,
        fee: 0,
        note: '',
      ),
      replaceIndex: movements.length + 1,
    );
  }
}

class Movement {
  final String id;
  final MovementType type;
  final String coin;
  final DateTime date;
  final double quantity;
  final double unitPrice;
  final double fee;
  final String source;
  final String wallet;
  final String network;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;
  final int schemaVersion;

  Movement({
    String? id,
    required this.type,
    required this.coin,
    required this.date,
    required this.quantity,
    required this.unitPrice,
    required this.fee,
    this.source = '',
    this.wallet = '',
    this.network = '',
    required this.note,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deviceId,
    this.schemaVersion = 1,
  }) : id = id == null || id.trim().isEmpty ? _generateMovementId() : id,
       createdAt = createdAt ?? date,
       updatedAt = updatedAt ?? createdAt ?? date;

  double get grossTotal => quantity * unitPrice;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type.name,
    'coin': coin,
    'date': date.toIso8601String(),
    'quantity': quantity,
    'unitPrice': unitPrice,
    'fee': fee,
    'source': source,
    'wallet': wallet,
    'network': network,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
    if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
    'schemaVersion': schemaVersion,
  };

  Movement copyWith({
    String? id,
    MovementType? type,
    String? coin,
    DateTime? date,
    double? quantity,
    double? unitPrice,
    double? fee,
    String? source,
    String? wallet,
    String? network,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? deviceId,
    int? schemaVersion,
  }) {
    return Movement(
      id: id ?? this.id,
      type: type ?? this.type,
      coin: coin ?? this.coin,
      date: date ?? this.date,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      fee: fee ?? this.fee,
      source: source ?? this.source,
      wallet: wallet ?? this.wallet,
      network: network ?? this.network,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deviceId: deviceId ?? this.deviceId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  bool isFinanciallyIdenticalTo(Movement other) {
    return type == other.type &&
        coin == other.coin &&
        date.millisecondsSinceEpoch == other.date.millisecondsSinceEpoch &&
        (quantity - other.quantity).abs() < 0.0000000001 &&
        (unitPrice - other.unitPrice).abs() < 0.00000001 &&
        (fee - other.fee).abs() < 0.00000001 &&
        source.trim().toLowerCase() == other.source.trim().toLowerCase() &&
        note.trim().toLowerCase() == other.note.trim().toLowerCase();
  }

  factory Movement.fromJson(Map<String, dynamic> json) {
    final DateTime date =
        DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now();
    final DateTime createdAt =
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? date;
    return Movement(
      id: json['id']?.toString(),
      type: movementTypeFromAny(json['type']),
      coin: (json['coin'] ?? json['crypto'] ?? 'BTC').toString().toUpperCase(),
      date: date,
      quantity: numberFromJson(json['quantity']),
      unitPrice: numberFromJson(json['unitPrice'] ?? json['unit_price']),
      fee: numberFromJson(json['fee'] ?? json['commission']),
      source: textFromJson(json['source'] ?? json['origin'] ?? json['origen']),
      wallet: textFromJson(json['wallet'] ?? json['cartera']),
      network: textFromJson(json['network'] ?? json['red']),
      note: json['note']?.toString() ?? '',
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? createdAt,
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
      deviceId: textFromJson(json['deviceId']).isEmpty
          ? null
          : textFromJson(json['deviceId']),
      schemaVersion: json['schemaVersion'] is num
          ? (json['schemaVersion'] as num).toInt()
          : int.tryParse(json['schemaVersion']?.toString() ?? '') ?? 1,
    );
  }
}

class CoinStats {
  final String coin;
  double quantity;
  double costBase;
  double currentPrice;
  double realizedPL;
  double feesPaid;
  double totalInvested;

  CoinStats({
    required this.coin,
    this.quantity = 0.0,
    this.costBase = 0.0,
    this.currentPrice = 0.0,
    this.realizedPL = 0.0,
    this.feesPaid = 0.0,
    this.totalInvested = 0.0,
  });

  double get avgPrice => quantity > 0 ? costBase / quantity : 0.0;
  double get currentValue => quantity * currentPrice;
  double get unrealizedPL => currentValue - costBase;
  double get breakEvenReal => avgPrice;
  double breakEvenWithExitFee([
    double sellFeePercent = FinancialEngine.defaultExitFeePercent,
  ]) => netBreakEvenPrice(sellFeePercent);

  double netBreakEvenPrice(double sellFeePercent) {
    if (quantity <= 0) return 0.0;
    final double multiplier = 1 - (sellFeePercent / 100);
    if (multiplier <= 0) return 0.0;
    return avgPrice / multiplier;
  }

  double targetNetExitPrice(double sellFeePercent, double targetPercent) {
    if (quantity <= 0) return 0.0;
    final double multiplier = 1 - (sellFeePercent / 100);
    if (multiplier <= 0) return 0.0;
    return (costBase * (1 + targetPercent / 100)) / (quantity * multiplier);
  }

  double percentToNetBreakEven(double sellFeePercent) {
    if (quantity <= 0 || currentPrice <= 0) return 0.0;
    final double target = netBreakEvenPrice(sellFeePercent);
    if (target <= 0) return 0.0;
    return ((target / currentPrice) - 1) * 100;
  }

  bool isAtOrAboveNetBreakEven(double sellFeePercent) {
    if (quantity <= 0) return true;
    return currentPrice >= netBreakEvenPrice(sellFeePercent);
  }
}

class CoinAudit {
  final double buys;
  final double sells;
  final double transferIns;
  final double transferOuts;
  final double fees;

  CoinAudit({
    required this.buys,
    required this.sells,
    required this.transferIns,
    required this.transferOuts,
    required this.fees,
  });
}

class PortfolioTotals {
  final double costBase;
  final double currentValue;
  final double unrealizedPL;
  final double realizedPL;
  final double feesPaid;

  PortfolioTotals({
    required this.costBase,
    required this.currentValue,
    required this.unrealizedPL,
    required this.realizedPL,
    this.feesPaid = 0.0,
  });
}

class CoinSnapshot {
  final String coin;
  final double quantity;
  final double costBase;
  final double avgPrice;
  final double currentValue;
  final double unrealizedPL;
  final double realizedPL;

  CoinSnapshot({
    required this.coin,
    required this.quantity,
    required this.costBase,
    required this.avgPrice,
    required this.currentValue,
    required this.unrealizedPL,
    required this.realizedPL,
  });

  factory CoinSnapshot.fromStats(CoinStats stats) => CoinSnapshot(
    coin: stats.coin,
    quantity: stats.quantity,
    costBase: stats.costBase,
    avgPrice: stats.avgPrice,
    currentValue: stats.currentValue,
    unrealizedPL: stats.unrealizedPL,
    realizedPL: stats.realizedPL,
  );

  factory CoinSnapshot.fromJson(Map<String, dynamic> json) => CoinSnapshot(
    coin: json['coin'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    costBase: (json['costBase'] as num).toDouble(),
    avgPrice: (json['avgPrice'] as num).toDouble(),
    currentValue: (json['currentValue'] as num).toDouble(),
    unrealizedPL: (json['unrealizedPL'] as num).toDouble(),
    realizedPL: (json['realizedPL'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'coin': coin,
    'quantity': quantity,
    'costBase': costBase,
    'avgPrice': avgPrice,
    'currentValue': currentValue,
    'unrealizedPL': unrealizedPL,
    'realizedPL': realizedPL,
  };
}

class PortfolioSnapshot {
  final String id;
  final DateTime createdAt;
  final double totalCostBase;
  final double totalCurrentValue;
  final double totalUnrealizedPL;
  final double totalRealizedPL;
  final int movementCount;
  final List<CoinSnapshot> coins;

  PortfolioSnapshot({
    required this.id,
    required this.createdAt,
    required this.totalCostBase,
    required this.totalCurrentValue,
    required this.totalUnrealizedPL,
    required this.totalRealizedPL,
    required this.movementCount,
    required this.coins,
  });

  String get dominantCoinLabel {
    final List<CoinSnapshot> active =
        coins.where((CoinSnapshot coin) => coin.currentValue > 0).toList()
          ..sort(
            (CoinSnapshot a, CoinSnapshot b) =>
                b.currentValue.compareTo(a.currentValue),
          );
    if (active.isEmpty) return 'Sin posición dominante';
    final CoinSnapshot leader = active.first;
    final double share = totalCurrentValue <= 0
        ? 0.0
        : (leader.currentValue / totalCurrentValue) * 100;
    return '${leader.coin} · ${pct(share)}';
  }

  double get btcDominancePercent {
    if (totalCurrentValue <= 0) return 0.0;
    final double btcValue = coins
        .where((CoinSnapshot coin) => coin.coin.toUpperCase() == 'BTC')
        .fold<double>(
          0.0,
          (double total, CoinSnapshot coin) => total + coin.currentValue,
        );
    return (btcValue / totalCurrentValue) * 100;
  }

  factory PortfolioSnapshot.fromJson(Map<String, dynamic> json) {
    return PortfolioSnapshot(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      totalCostBase: (json['totalCostBase'] as num).toDouble(),
      totalCurrentValue: (json['totalCurrentValue'] as num).toDouble(),
      totalUnrealizedPL: (json['totalUnrealizedPL'] as num).toDouble(),
      totalRealizedPL: (json['totalRealizedPL'] as num).toDouble(),
      movementCount: json['movementCount'] as int,
      coins: (json['coins'] as List<dynamic>)
          .map(
            (dynamic e) =>
                CoinSnapshot.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'totalCostBase': totalCostBase,
    'totalCurrentValue': totalCurrentValue,
    'totalUnrealizedPL': totalUnrealizedPL,
    'totalRealizedPL': totalRealizedPL,
    'movementCount': movementCount,
    'coins': coins.map((CoinSnapshot c) => c.toJson()).toList(),
  };
}

double numberFromJson(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

String textFromJson(dynamic value) => value?.toString().trim() ?? '';

String _generateMovementId() {
  final int timestamp = DateTime.now().millisecondsSinceEpoch;
  final String suffix = math.Random().nextInt(0xFFFFFFF).toRadixString(16);
  return 'mov_${timestamp}_$suffix';
}

DateTime dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

const Duration days1 = Duration(days: 1);

String money(double value) => '\$${value.toStringAsFixed(2)} MXN';

String priceDisplay(double value) =>
    value > 0 ? money(value) : 'Precio no disponible';

String priceStatusCsv(double value) =>
    value > 0 ? 'disponible' : 'no_disponible';

String priceStatusJson(double value) => value > 0 ? 'available' : 'unavailable';

String priceStatusLabel(double value) =>
    value > 0 ? 'Disponible' : 'No disponible';

String moneyShort(double value) => '\$${value.toStringAsFixed(0)}';

String crypto(double value) => value.toStringAsFixed(8);

String pct(double value) => '${value.toStringAsFixed(2)}%';

String intervalLabel(int minutes) {
  switch (minutes) {
    case 15:
      return '15 min';
    case 30:
      return '30 min';
    case 60:
      return '1 h';
    case 360:
      return '6 h';
    case 1440:
      return 'Diario';
  }
  return '$minutes min';
}

String fixed(double value, int decimals) => value.toStringAsFixed(decimals);

String compact(double value) {
  final String text = value.toStringAsFixed(8);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String shortDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String longDate(DateTime date) {
  return '${shortDate(date)} ${timeLabel(date)}';
}

String timeLabel(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String priceUpdatedLabel(DateTime? updatedAt) {
  if (updatedAt == null) return 'Sin actualización registrada';

  final Duration age = DateTime.now().difference(updatedAt);
  if (age.inMinutes < 1) return 'Actualizado hace menos de 1 min';
  if (age.inHours < 1) {
    return 'Actualizado hace ${age.inMinutes} min';
  }
  if (age.inDays < 1) {
    return 'Actualizado hace ${age.inHours} h';
  }

  return 'Actualizado ${longDate(updatedAt)}';
}

String isoDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String csvEscape(Object? value) {
  final String text = value?.toString() ?? '';
  final bool needsEscape =
      text.contains(',') || text.contains('"') || text.contains('\n');
  final String escaped = text.replaceAll('"', '""');
  return needsEscape ? '"$escaped"' : escaped;
}

void _appendExcelRow(xl.Sheet sheet, List<Object?> values) {
  sheet.appendRow(values.map(toExcelValue).toList());
}

xl.CellValue? toExcelValue(Object? value) {
  if (value is int) return xl.IntCellValue(value);
  if (value is double) return xl.DoubleCellValue(value);
  return xl.TextCellValue(value?.toString() ?? '');
}

Color pnlColor(double value) {
  if (value > 0) return const Color(0xFF16A34A);
  if (value < 0) return const Color(0xFFDC2626);
  return Colors.grey.shade700;
}
