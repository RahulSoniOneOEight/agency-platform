import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import 'prototype_app.dart';
import 'review/memory_review_repository.dart';
import 'review/review_controller.dart';
import 'review/review_route.dart';
import 'review/review_shell.dart';
import 'runtime/prototype_runtime.dart';
import 'runtime/runtime_exception.dart';
import 'runtime/runtime_loader.dart';
import 'screens/runtime_error_screen.dart';

/// Local/demo convenience default. This is a declared default, not a fallback
/// for invalid explicit client IDs, and it is never applied to Review Mode.
const String kDefaultClientId = 'prototype-demo';

void main() {
  runApp(const PrototypeBootstrap());
}

class PrototypeBootstrap extends StatefulWidget {
  const PrototypeBootstrap({super.key, this.uri, this.loadRuntime});

  /// Overrides `Uri.base` in tests. Review Mode is detected from this URI.
  final Uri? uri;

  /// Overrides `RuntimeLoader.loadClient` in tests. Both modes share one load.
  final Future<PrototypeRuntime> Function(String clientId)? loadRuntime;

  @override
  State<PrototypeBootstrap> createState() => _PrototypeBootstrapState();
}

class _PrototypeBootstrapState extends State<PrototypeBootstrap> {
  late final ReviewRouteRequest _route;
  late final Future<PrototypeRuntime>? _runtime;
  RuntimeException? _routeError;
  String? _requestedDirection;
  ReviewController? _reviewController;

  @override
  void initState() {
    super.initState();
    final uri = widget.uri ?? Uri.base;
    _route = parseReviewRoute(uri);

    final reviewClientId = _route.clientId;
    if (_route.isReviewMode &&
        (reviewClientId == null || reviewClientId.trim().isEmpty)) {
      _routeError = const RuntimeException(
        code: RuntimeException.clientNotFound,
        message:
            'Review Mode requires an explicit client id (use /review?client=<id>).',
      );
      _runtime = null;
      return;
    }

    // `?direction=` only ever influences normal prototype mode; Review Mode
    // starts with no selected direction.
    _requestedDirection =
        _route.isReviewMode ? null : uri.queryParameters['direction'];
    final clientId =
        _route.isReviewMode ? reviewClientId! : (_route.clientId ?? kDefaultClientId);
    final loader = widget.loadRuntime ?? RuntimeLoader.loadClient;
    _runtime = loader(clientId);
  }

  @override
  void dispose() {
    _reviewController?.dispose();
    super.dispose();
  }

  /// Composition root: Review Mode storage is chosen here, never in the UI.
  ReviewController _controllerFor(PrototypeRuntime runtime) {
    return _reviewController ??= ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeError = _routeError;
    if (routeError != null) {
      return _shell(RuntimeErrorScreen(error: routeError));
    }

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
        final runtime = snapshot.requireData;
        if (_route.isReviewMode) {
          return _shell(
            ReviewShell(runtime: runtime, controller: _controllerFor(runtime)),
          );
        }
        final requested = _requestedDirection;
        return PrototypeApp(
          runtime: runtime,
          requestedDirection: (requested == null || requested.isEmpty) ? null : requested,
        );
      },
    );
  }

  Widget _shell(Widget home) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Agency Prototype',
        theme: AgencyTheme.lightDefault(),
        home: home,
      );
}
