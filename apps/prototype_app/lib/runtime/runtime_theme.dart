import 'package:agency_flutter_ui/agency_flutter_ui.dart';

/// App-facing name for the resolved theme carried by a client runtime bundle.
///
/// The runtime bundle stores resolved values only; parsing is strict and never
/// inserts design defaults. See [AgencyResolvedTheme.fromJson].
typedef RuntimeTheme = AgencyResolvedTheme;
