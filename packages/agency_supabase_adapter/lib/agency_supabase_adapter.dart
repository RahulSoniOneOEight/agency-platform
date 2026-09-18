library;

// Public boundary: adapter classes, the error mapper, and provider-neutral
// value types/seams only. The concrete provider-client seam classes
// (`SupabasePostgrestQueryClient`, `SupabaseGoTrueAuthClient`) stay internal to
// `src/` so no raw Supabase exception surface is exported.
export 'src/supabase_account_repository.dart';
export 'src/supabase_auth_adapter.dart'
    hide SupabaseGoTrueAuthClient, supabaseAuthSessionFromSession;
export 'src/supabase_cart_repository.dart';
export 'src/supabase_catalog_repository.dart';
export 'src/supabase_error_mapper.dart';
export 'src/supabase_order_repository.dart';
export 'src/supabase_query_client.dart' hide SupabasePostgrestQueryClient;
export 'src/supabase_quote_repository.dart';
