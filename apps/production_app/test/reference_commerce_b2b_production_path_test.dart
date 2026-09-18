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
///
/// The fixture (`integration-scenarios.json`) is the single source of truth:
/// the ordered journey steps and the expected insufficient-role /
/// insufficient-credit failures are read from it, never restated here.
const String _accountId = 'account-trade';
const String _buyerEmail = 'buyer@reference-commerce.example';
const String _consumerEmail = 'consumer@reference-commerce.example';
const String _password = 'reference-password';

Future<CartItem> _rfqItem(ReferenceCommerceHarness harness) async {
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

CartItem _singleItem() => CartItem(
      productId: 'product-espresso-machine',
      variantId: 'variant-espresso-machine-230v',
      quantity: 1,
      unitPriceMinor: 129900,
    );

Future<DomainFailure> _captureFailure(Future<void> Function() action) async {
  try {
    await action();
  } on DomainFailure catch (failure) {
    return failure;
  }
  fail('Expected a DomainFailure to be thrown');
}

/// Executes the fixture-declared B2B case [id] and returns its failure.
Future<DomainFailure> _driveB2bCase(String id) async {
  switch (id) {
    case 'insufficient-role':
      final harness = ReferenceCommerceHarness();
      final consumer = await harness.runtime.auth.signIn(
        email: _consumerEmail,
        password: _password,
      );
      return _captureFailure(
        () => harness.runtime.quotes.createRfq(
          accountId: _accountId,
          identityId: consumer.id,
          items: [_singleItem()],
          idempotencyKey: IdempotencyKey('b2b-rfq-forbidden'),
        ),
      );
    case 'insufficient-credit':
      final seed = defaultReferenceCommerceSeed();
      final lowCreditAccounts = InMemoryAccountRepository(
        customers: seed.customers,
        accounts: seed.accounts,
        memberships: seed.memberships,
        credits: [
          CreditSnapshot(
            accountId: _accountId,
            creditLimitMinor: 1000000,
            availableCreditMinor: 1000,
          ),
        ],
      );
      final harness = ReferenceCommerceHarness(
        seed: seed,
        accounts: lowCreditAccounts,
      );
      final identity = await harness.runtime.auth.signIn(
        email: _buyerEmail,
        password: _password,
      );
      final item = await _rfqItem(harness);
      final rfq = await harness.runtime.quotes.createRfq(
        accountId: _accountId,
        identityId: identity.id,
        items: [item],
        idempotencyKey: IdempotencyKey('b2b-rfq-key-credit'),
      );
      final quotation = await harness.erp.requestQuotation(
        rfq: rfq,
        idempotencyKey: IdempotencyKey('b2b-quotation-key-credit'),
      );
      await harness.quoteRepository.saveQuotation(
        quotation: quotation,
        idempotencyKey: IdempotencyKey('b2b-quotation-key-credit'),
      );
      return _captureFailure(
        () => harness.runtime.quotes.convertQuotationToOrder(
          quotationId: quotation.id,
          identityId: identity.id,
        ),
      );
    default:
      throw ArgumentError('No B2B case driver for $id');
  }
}

void main() {
  final scenarios = loadIntegrationScenarios();

  group('reference-commerce B2B production path', () {
    late ReferenceCommerceHarness harness;

    setUp(() {
      harness = ReferenceCommerceHarness();
    });

    test(
      'sign in -> membership -> credit -> RFQ -> quote -> order conversion',
      () async {
        // The executed journey is recorded by fixture step id so the fixture's
        // ordered step list is the single source of truth (no restatement).
        final executedSteps = <String>[];

        // 1. Sign in as a B2B buyer.
        final identity = await harness.runtime.auth.signIn(
          email: _buyerEmail,
          password: _password,
        );
        expect(identity.role, UserRole.b2bBuyer);
        executedSteps.add('sign_in');

        // 2+3. Resolve business membership and load credit. A single
        //      `loadAccountContext` call resolves both, so both fixture steps
        //      are recorded here.
        final context = await harness.runtime.quotes.loadAccountContext(
          accountId: _accountId,
          identityId: identity.id,
        );
        expect(context.account.id, _accountId);
        expect(context.membership.role, UserRole.b2bBuyer);
        expect(context.credit, isNotNull);
        expect(context.credit!.availableCreditMinor, 750000);
        executedSteps
          ..add('resolve_business_membership')
          ..add('load_credit');

        // 4. Create an RFQ through QuoteService.
        final item = await _rfqItem(harness);
        final rfq = await harness.runtime.quotes.createRfq(
          accountId: _accountId,
          identityId: identity.id,
          items: [item],
          idempotencyKey: IdempotencyKey('b2b-rfq-key-1'),
        );
        expect(rfq.status, RfqStatus.submitted);
        executedSteps.add('create_rfq');

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
        executedSteps.add('receive_deterministic_quote');

        // 6. Convert the quotation to an order through QuoteService.
        final order = await harness.runtime.quotes.convertQuotationToOrder(
          quotationId: quotation.id,
          identityId: identity.id,
        );
        expect(order.totalMinor, quotation.totalMinor);
        expect(order.items, hasLength(1));
        expect(order.items.single.quantity, item.quantity);
        expect(harness.orderRepository.distinctOrderCount, 1);
        executedSteps.add('convert_quote_to_order');

        expect(executedSteps, scenarios.b2bPath.steps);
      },
    );

    test('conversion replay returns one order identity (R11)', () async {
      final identity = await harness.runtime.auth.signIn(
        email: _buyerEmail,
        password: _password,
      );
      final item = await _rfqItem(harness);
      final rfq = await harness.runtime.quotes.createRfq(
        accountId: _accountId,
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

    test('insufficient role also denies account context', () async {
      final scenarioCase = scenarios.b2bCaseById('insufficient-role');
      final consumer = await harness.runtime.auth.signIn(
        email: _consumerEmail,
        password: _password,
      );

      final failure = await _captureFailure(
        () => harness.runtime.quotes.loadAccountContext(
          accountId: _accountId,
          identityId: consumer.id,
        ),
      );

      expect(failure.code, scenarioCase.expectedCode);
      expect(failure.retryable, scenarioCase.expectedRetryable);
    });

    group('insufficient B2B cases (fixture-driven)', () {
      for (final scenarioCase in scenarios.b2bCases) {
        test('${scenarioCase.id} -> ${scenarioCase.expectedCode!.name}',
            () async {
          final failure = await _driveB2bCase(scenarioCase.id);

          expect(failure.code, scenarioCase.expectedCode);
          expect(failure.retryable, scenarioCase.expectedRetryable);
          expect(failure.operation, scenarioCase.expectedOperation);
        });
      }
    });
  });
}
