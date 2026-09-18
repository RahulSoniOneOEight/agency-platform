import 'package:agency_supabase_adapter/agency_supabase_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Proves the composition root can build production adapters from a real
/// provider client through the public barrel, without importing `src/`.
void main() {
  group('production adapter factories', () {
    late SupabaseClient client;

    setUpAll(() {
      // Lazy construction only: no request is issued by the constructor.
      client = SupabaseClient(
        'https://example.supabase.co',
        'public-anon-key',
      );
    });

    test('createSupabaseQueryClient returns the public query seam', () {
      final SupabaseQueryClient seam = createSupabaseQueryClient(client);

      expect(seam, isA<SupabaseQueryClient>());
    });

    test('createSupabaseAuthClient returns the public auth seam', () {
      final SupabaseAuthClient seam = createSupabaseAuthClient(client.auth);

      expect(seam, isA<SupabaseAuthClient>());
    });
  });
}
