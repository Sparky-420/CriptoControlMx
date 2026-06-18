import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cripto_control_mx/cripto_control_app.dart' as app;
import 'package:cripto_control_mx/ui/premium_colors.dart';

class PremiumBootGate extends StatefulWidget {
  final Future<void> Function() beforeLaunch;

  const PremiumBootGate({super.key, required this.beforeLaunch});

  @override
  State<PremiumBootGate> createState() => _PremiumBootGateState();
}

class _PremiumBootGateState extends State<PremiumBootGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    await widget.beforeLaunch();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const app.CriptoControlApp();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: PremiumColors.bootBackground,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CriptoControlMx',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: PremiumColors.primary,
            brightness: Brightness.dark,
            surface: const Color.fromARGB(255, 11, 21, 26),
          ),
          scaffoldBackgroundColor: PremiumColors.bootBackground,
        ),
        home: const _PremiumBootScreen(),
      ),
    );
  }
}

class _PremiumBootScreen extends StatelessWidget {
  const _PremiumBootScreen();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              PremiumColors.bootBackground,
              PremiumColors.bootBackgroundAlt,
              PremiumColors.bootSurface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Spacer(),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.primary.withAlpha(90)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        colors.primary.withAlpha(48),
                        colors.tertiary.withAlpha(28),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: colors.primary.withAlpha(42),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.currency_bitcoin,
                    size: 38,
                    color: PremiumColors.primary,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'CriptoControlMx',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Control matemático de cartera',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 28),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: colors.surfaceContainerHighest,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Preparando cartera local sin alterar cálculos...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withAlpha(18)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: PremiumColors.mutedText,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Fórmulas intactas',
                        style: TextStyle(
                          color: PremiumColors.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
