import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import 'app/environment_config_loader.dart';
import 'app/production_app.dart';
import 'app/production_composition_root.dart';

/// Runtime environment selected at build time, e.g.
/// `--dart-define=ENVIRONMENT=staging`. Defaults to `dev`.
const String _environment = String.fromEnvironment(
  'ENVIRONMENT',
  defaultValue: 'dev',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = await EnvironmentConfigLoader.load(_environment);
    runApp(
      ProductionApp(
        runtime: ProductionCompositionRoot.referenceCommerce(config),
      ),
    );
  } on FormatException catch (error) {
    // No silent dev fallback: an invalid environment config stops the boot with
    // an explicit, deterministic error surface.
    runApp(_ConfigErrorApp(message: error.message));
  }
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Reference Commerce',
      theme: AgencyTheme.lightDefault(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Configuration error',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
