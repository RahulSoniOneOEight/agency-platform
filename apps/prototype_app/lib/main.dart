import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import 'prototype_app.dart';
import 'runtime/prototype_runtime.dart';
import 'runtime/runtime_exception.dart';
import 'runtime/runtime_loader.dart';
import 'screens/runtime_error_screen.dart';

/// Local/demo convenience default. This is a declared default, not a fallback
/// for invalid explicit client IDs.
const String kDefaultClientId = 'prototype-demo';

void main() {
  runApp(const PrototypeBootstrap());
}

class PrototypeBootstrap extends StatefulWidget {
  const PrototypeBootstrap({super.key});

  @override
  State<PrototypeBootstrap> createState() => _PrototypeBootstrapState();
}

class _PrototypeBootstrapState extends State<PrototypeBootstrap> {
  late final String _requestedDirection;
  late final Future<PrototypeRuntime> _runtime;

  @override
  void initState() {
    super.initState();
    final parameters = Uri.base.queryParameters;
    _requestedDirection = parameters['direction'] ?? '';
    final clientId = parameters['client'] ?? kDefaultClientId;
    _runtime = RuntimeLoader.loadClient(clientId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PrototypeRuntime>(
      future: _runtime,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _shell(const Scaffold(body: Center(child: CircularProgressIndicator())));
        }
        final error = snapshot.error;
        if (error != null) {
          return _shell(
            RuntimeErrorScreen(
              error: error is RuntimeException
                  ? error
                  : RuntimeException(
                      code: RuntimeException.invalidBundle,
                      message: error.toString(),
                    ),
            ),
          );
        }
        return PrototypeApp(
          runtime: snapshot.requireData,
          requestedDirection: _requestedDirection.isEmpty ? null : _requestedDirection,
        );
      },
    );
  }

  Widget _shell(Widget home) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Agency Prototype',
        theme: AgencyTheme.light(),
        home: home,
      );
}
