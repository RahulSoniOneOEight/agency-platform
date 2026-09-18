import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_app/runtime/deterministic_boundaries.dart';

import 'support/reference_commerce_harness.dart';

/// B2B production-path E2E for reference-commerce.
///
/// The journey drives `QuoteService` end to end (account context -> RFQ ->
/// deterministic quotation -> order conversion) using the same application
/// services and ports as production composition. Repository access is limited
/// to deterministic setup (persisting the ERP-produced quotation).
void main() {
  const accountId = 'account-trade';
  const buyerEmail = 'buyer@reference-commerce.example';

  Future<CartItem> rfqItem(ReferenceCommerceHarness harness) async {
    final catalog = await harness.runtime.commerce.loadCatalog();
    final product = catalog.firstWhere(
      (entry) => entry.product.id == 'product-espresso-machine',
    );
    final variant = product.variants.first;
    return CartItem(
      productId: product.product.id,
      variantId: variant.variant.id,
      quantity: 2,
      unitPriceMinor: variant.variant.priceMinor,
    );
  }

  Future<DomainFailure> captureFailure(Future<void> Function() action) async {
    try {
      await action();
    } on DomainFailure catch (failure) {
      return failure;
    }
    fail('Expected a DomainFailure to be thrown');
  }

  group('reference-commerce B2B production path', () {
    late ReferenceCommerceHarness harness;

    setUp(() {
      harness = ReferenceCommerceHarness();
    });

    test(
      'sign in -> membership -> credit -> RFQ -> quote -> order conversion',
      () async {
        // 1. Sign in as a B2B buyer.
        final identity = await harness.runtime.auth.signIn(
          email: buyerEmail,
          password: 'reference-password',
        );
        expect(identity.role, UserRole.b2bBuyer);

        // 2. Resolve business membership + 3. load credit.
        final context = await harness.runtime.quotes.loadAccountContext(
          accountId: accountId,
          identityId: identity.id,
        );
        expect(context.account.id, accountId);
        expect(context.membership.role, UserRole.b2bBuyer);
        expect(context.credit, isNotNull);
        expect(context.credit!.availableCreditMinor, 750000);

        // 4. Create an RFQ through QuoteService.
        final item = await rfqItem(harness);
        final rfq = await harness.runtime.quotes.createRfq(
          accountId: accountId,
          identityId: identity.id,
          items: [item],
          idempotencyKey: IdempotencyKey('b2b-rfq-key-1'),
        );
        expect(rfq.status, RfqStatus.submitted);

        // 5. Receive a deterministic quotation from the ERP port and persist
        //    it (the business side owns quotation production).
        final quotationKey = IdempotencyKey('b2b-quotation-key-1');
        final quotation = await harness.erp.requestQuotation(
          rfq: rfq,
          idempotencyKey: quotationKey,
        );
        final replayed = await harness.erp.requestQuotation(
          rfq: rfq,
          idempotencyKey: quotationKey,
        );
        expect(replayed.id, quotation.id);
        expect(quotation.status, QuotationStatus.sent);
        expect(quotation.totalMinor, item.lineTotalMinor);

        await harness.quoteRepository.saveQuotation(
          quotation: quotation,
          idempotencyKey: quotationKey,
        );

        // 6. Convert the quotation to an order through QuoteService.
        final order = await harness.runtime.quotes.convertQuotationToOrder(
          quotationId: quotation.id,
          identityId: identity.id,
        );
        expect(order.totalMinor, quotation.totalMinor);
        expect(order.items, hasLength(1));
        expect(order.items.single.quantity, item.quantity);
        expect(harness.orderRepository.distinctOrderCount, 1);
      },
    );

    test('conversion replay returns one order identity (R11)', () async {
      final identity = await harness.runtime.auth.signIn(
        email: buyerEmail,
        password: 'reference-password',
      );
      final item = await rfqItem(harness);
      final rfq = await harness.runtime.quotes.createRfq(
        accountId: accountId,
        identityId: identity.id,
        items: [item],
        idempotencyKey: IdempotencyKey('b2b-rfq-key-2'),
      );
      final quotation = await harness.erp.requestQuotation(
        rfq: rfq,
        idempotencyKey: IdempotencyKey('b2b-quotation-key-2'),
      );
      await harness.quoteRepository.saveQuotation(
        quotation: quotation,
        idempotencyKey: IdempotencyKey('b2b-quotation-key-2'),
      );

      final first = await harness.runtime.quotes.convertQuotationToOrder(
        quotationId: quotation.id,
        identityId: identity.id,
      );
      final second = await harness.runtime.quotes.convertQuotationToOrder(
        quotationId: quotation.id,
        identityId: identity.id,
      );

      expect(second.id, first.id);
      expect(harness.orderRepository.distinctOrderCount, 1);
      // The deterministic in-memory quote repository must not persist
      // `RfqStatus.converted` in a way that blocks the idempotent replay the
      // ruling requires: the RFQ remains replayable through the order key.
      final storedRfq = await harness.quoteRepository.getRfq(rfq.id);
      expect(storedRfq!.status, isNot(RfqStatus.converted));
    });

    test('insufficient role: a non-member cannot resolve or create', () async {
      final consumer = await harness.runtime.auth.signIn(
        email: 'consumer@reference-commerce.example',
        password: 'reference-password',
      );

      final contextFailure = await captureFailure(
        () => harness.runtime.quotes.loadAccountContext(
          accountId: accountId,
          identityId: consumer.id,
        ),
      );
      final rfqFailure = await captureFailure(
        () => harness.runtime.quotes.createRfq(
          accountId: accountId,
          identityId: consumer.id,
          items: [
            CartItem(
              productId: 'product-espresso-machine',
              variantId: 'variant-espresso-machine-230v',
              quantity: 1,
              unitPriceMinor: 129900,
            ),
          ],
          idempotencyKey: IdempotencyKey('b2b-rfq-forbidden'),
        ),
      );

      expect(contextFailure.code, DomainFailureCode.forbidden);
      expect(contextFailure.retryable, isFalse);
      expect(rfqFailure.code, DomainFailureCode.forbidden);
      expect(rfqFailure.retryable, isFalse);
    });

    test('insufficient credit: conversion is denied and creates no order',
        () async {
      final seed = defaultReferenceCommerceSeed();
      final lowCreditAccounts = InMemoryAccountRepository(
        customers: seed.customers,
        accounts: seed.accounts,
        memberships: seed.memberships,
        credits: [
          CreditSnapshot(
            accountId: accountId,
            creditLimitMinor: 1000000,
            availableCreditMinor: 1000,
          ),
        ],
      );
      final lowCreditHarness = ReferenceCommerceHarness(
        seed: seed,
        accounts: lowCreditAccounts,
      );

      final identity = await lowCreditHarness.runtime.auth.signIn(
        email: buyerEmail,
        password: 'reference-password',
      );
      final item = await rfqItem(lowCreditHarness);
      final rfq = await lowCreditHarness.runtime.quotes.createRfq(
        accountId: accountId,
        identityId: identity.id,
        items: [item],
        idempotencyKey: IdempotencyKey('b2b-rfq-key-credit'),
      );
      final quotation = await lowCreditHarness.erp.requestQuotation(
        rfq: rfq,
        idempotencyKey: IdempotencyKey('b2b-quotation-key-credit'),
      );
      await lowCreditHarness.quoteRepository.saveQuotation(
        quotation: quotation,
        idempotencyKey: IdempotencyKey('b2b-quotation-key-credit'),
      );

      final failure = await captureFailure(
        () => lowCreditHarness.runtime.quotes.convertQuotationToOrder(
          quotationId: quotation.id,
          identityId: identity.id,
        ),
      );

      expect(failure.code, DomainFailureCode.conflict);
      expect(failure.retryable, isFalse);
      expect(failure.operation, 'convert_quotation_to_order');
      expect(lowCreditHarness.orderRepository.distinctOrderCount, 0);
    });
  });
}
