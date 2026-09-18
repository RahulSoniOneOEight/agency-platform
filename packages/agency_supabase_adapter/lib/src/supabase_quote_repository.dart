import 'package:agency_production_core/agency_production_core.dart';

import 'supabase_error_mapper.dart';
import 'supabase_query_client.dart';
import 'supabase_row_mapping.dart';

/// Supabase-backed [QuoteRepository].
final class SupabaseQuoteRepository implements QuoteRepository {
  SupabaseQuoteRepository({
    required SupabaseQueryClient query,
    String Function()? newId,
  }) : _query = query,
       _newId = newId ?? generateSupabaseId;

  final SupabaseQueryClient _query;
  final String Function() _newId;

  @override
  Future<Rfq> createRfq({
    required String accountId,
    required List<CartItem> items,
    required IdempotencyKey idempotencyKey,
    String? message,
  }) async {
    final existing = await _loadRfqByIdempotencyKey(idempotencyKey.value);
    if (existing != null) {
      return existing;
    }

    final id = _newId();
    // Ownership is set explicitly here (not by a DB default/trigger) so the
    // reference write path is self-consistent with the shipped RLS policy
    // (`rfqs` insert requires `identity_id = auth.uid()`). `account_id` is
    // already required by the port.
    final identityId = _query.currentUserId;
    try {
      // Single nested insert: PostgREST writes the RFQ and its line items
      // atomically, so a partial RFQ with no items can never be persisted.
      await _query.insert(
        table: 'rfqs',
        rows: [
          {
            'id': id,
            'account_id': accountId,
            'identity_id': identityId,
            'status': RfqStatus.submitted.name,
            'message': message,
            'idempotency_key': idempotencyKey.value,
            if (items.isNotEmpty)
              'rfq_items': [
                for (final item in items)
                  {
                    'product_id': item.productId,
                    'variant_id': item.variantId,
                    'quantity': item.quantity,
                    'unit_price_minor': item.unitPriceMinor,
                  },
              ],
          },
        ],
      );
    } catch (error) {
      final failure = mapSupabaseFailure(error, operation: 'createRfq');
      if (failure.code == DomainFailureCode.conflict) {
        final replayed = await _loadRfqByIdempotencyKey(idempotencyKey.value);
        if (replayed != null) {
          return replayed;
        }
      }
      throw failure;
    }

    final created = await _loadRfqByIdempotencyKey(idempotencyKey.value);
    if (created != null) {
      return created;
    }
    return Rfq(id: id, accountId: accountId, items: items, message: message);
  }

  @override
  Future<Rfq?> getRfq(String rfqId) async {
    try {
      final rfqs = await _query.select(
        table: 'rfqs',
        equals: {'id': rfqId},
        limit: 1,
      );
      if (rfqs.isEmpty) {
        return null;
      }
      final items = await _query.select(
        table: 'rfq_items',
        equals: {'rfq_id': rfqId},
        orderBy: 'id',
      );
      return rfqFromRow(rfqs.first, items);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'getRfq');
    }
  }

  @override
  Future<Quotation> saveQuotation({
    required Quotation quotation,
    required IdempotencyKey idempotencyKey,
  }) async {
    final existing = await _loadQuotationByIdempotencyKey(
      idempotencyKey.value,
    );
    if (existing != null) {
      return existing;
    }
    try {
      final rows = await _query.insert(
        table: 'quotations',
        rows: [
          {
            'id': quotation.id,
            'rfq_id': quotation.rfqId,
            'total_minor': quotation.totalMinor,
            'status': quotation.status.name,
            'valid_until': quotation.validUntil?.toUtc().toIso8601String(),
            'idempotency_key': idempotencyKey.value,
          },
        ],
        onConflict: 'id',
      );
      return quotationFromRow(rows.first);
    } catch (error) {
      final failure = mapSupabaseFailure(error, operation: 'saveQuotation');
      if (failure.code == DomainFailureCode.conflict) {
        final replayed = await _loadQuotationByIdempotencyKey(
          idempotencyKey.value,
        );
        if (replayed != null) {
          return replayed;
        }
      }
      throw failure;
    }
  }

  @override
  Future<Quotation?> getQuotation(String quotationId) async {
    try {
      final rows = await _query.select(
        table: 'quotations',
        equals: {'id': quotationId},
        limit: 1,
      );
      return rows.isEmpty ? null : quotationFromRow(rows.first);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'getQuotation');
    }
  }

  Future<Rfq?> _loadRfqByIdempotencyKey(String idempotencyKey) async {
    try {
      final rfqs = await _query.select(
        table: 'rfqs',
        equals: {'idempotency_key': idempotencyKey},
        limit: 1,
      );
      if (rfqs.isEmpty) {
        return null;
      }
      final rfqId = stringValue(rfqs.first, 'id');
      final items = await _query.select(
        table: 'rfq_items',
        equals: {'rfq_id': rfqId},
        orderBy: 'id',
      );
      return rfqFromRow(rfqs.first, items);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'createRfq');
    }
  }

  Future<Quotation?> _loadQuotationByIdempotencyKey(
    String idempotencyKey,
  ) async {
    try {
      final rows = await _query.select(
        table: 'quotations',
        equals: {'idempotency_key': idempotencyKey},
        limit: 1,
      );
      return rows.isEmpty ? null : quotationFromRow(rows.first);
    } catch (error) {
      throw mapSupabaseFailure(error, operation: 'saveQuotation');
    }
  }
}
