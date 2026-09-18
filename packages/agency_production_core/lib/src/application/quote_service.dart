import '../domain/domain_failure.dart';
import '../domain/identity.dart';
import '../domain/models.dart';
import '../ports/repositories.dart';

/// A B2B account resolved for an identity: the account, its membership, and
/// (when a credit line exists) the current credit snapshot.
final class B2bAccountContext {
  const B2bAccountContext({
    required this.account,
    required this.membership,
    this.credit,
  });

  final BusinessAccount account;
  final AccountMembership membership;
  final CreditSnapshot? credit;
}

/// B2B RFQ and quotation conversion use cases.
///
/// Permissions are resolved per account from [AccountMembership] (never from a
/// single global role). Credit is checked when a quotation is converted into a
/// payable order. Mutating calls carry an [IdempotencyKey] and are never
/// blind-retried.
final class QuoteService {
  QuoteService({
    required QuoteRepository quotes,
    required AccountRepository accounts,
    required OrderRepository orders,
  })  : _quotes = quotes,
        _accounts = accounts,
        _orders = orders;

  static const _b2bRoles = {
    UserRole.b2bBuyer,
    UserRole.b2bManager,
    UserRole.admin,
  };

  final QuoteRepository _quotes;
  final AccountRepository _accounts;
  final OrderRepository _orders;

  /// Loads the account, membership, and credit snapshot for [identityId].
  Future<B2bAccountContext> loadAccountContext({
    required String accountId,
    required String identityId,
  }) async {
    try {
      final membership = await _requireMembership(
        accountId: accountId,
        identityId: identityId,
        operation: 'load_account_context',
      );
      final accounts = await _accounts.listAccountsForIdentity(identityId);
      BusinessAccount? account;
      for (final candidate in accounts) {
        if (candidate.id == accountId) {
          account = candidate;
          break;
        }
      }
      if (account == null) {
        throw DomainFailure(
          code: DomainFailureCode.forbidden,
          operation: 'load_account_context',
          retryable: false,
          message: 'Account $accountId is not accessible',
        );
      }
      final credit = await _accounts.getCreditSnapshot(accountId);
      return B2bAccountContext(
        account: account,
        membership: membership,
        credit: credit,
      );
    } on DomainFailure catch (failure) {
      throw _scope('load_account_context', failure);
    }
  }

  /// Creates an RFQ for [accountId] on behalf of [identityId].
  ///
  /// Re-submitting with the same [idempotencyKey] returns the same RFQ identity.
  Future<Rfq> createRfq({
    required String accountId,
    required String identityId,
    required List<CartItem> items,
    required IdempotencyKey idempotencyKey,
    String? message,
  }) async {
    try {
      await _requireMembership(
        accountId: accountId,
        identityId: identityId,
        operation: 'create_rfq',
      );
      if (items.isEmpty) {
        throw DomainFailure(
          code: DomainFailureCode.validation,
          operation: 'create_rfq',
          retryable: false,
          message: 'An RFQ requires at least one item',
        );
      }
      return await _quotes.createRfq(
        accountId: accountId,
        items: items,
        idempotencyKey: idempotencyKey,
        message: message,
      );
    } on DomainFailure catch (failure) {
      throw _scope('create_rfq', failure);
    }
  }

  /// Converts an accepted/sent quotation into an order for [identityId].
  ///
  /// Re-submitting with the same [idempotencyKey] returns the same order
  /// identity. Conversion is denied when the identity has no membership on the
  /// quotation's account or when available credit cannot cover the quotation.
  Future<Order> convertQuotationToOrder({
    required String quotationId,
    required String identityId,
    required IdempotencyKey idempotencyKey,
  }) async {
    try {
      final quotation = await _quotes.getQuotation(quotationId);
      if (quotation == null) {
        throw DomainFailure(
          code: DomainFailureCode.validation,
          operation: 'convert_quotation_to_order',
          retryable: false,
          message: 'Quotation $quotationId was not found',
        );
      }
      if (quotation.status != QuotationStatus.sent &&
          quotation.status != QuotationStatus.accepted) {
        throw DomainFailure(
          code: DomainFailureCode.validation,
          operation: 'convert_quotation_to_order',
          retryable: false,
          message: 'Quotation $quotationId is not convertible',
        );
      }

      final rfq = await _quotes.getRfq(quotation.rfqId);
      if (rfq == null) {
        throw DomainFailure(
          code: DomainFailureCode.validation,
          operation: 'convert_quotation_to_order',
          retryable: false,
          message: 'RFQ ${quotation.rfqId} was not found',
        );
      }

      await _requireMembership(
        accountId: rfq.accountId,
        identityId: identityId,
        operation: 'convert_quotation_to_order',
      );

      final credit = await _accounts.getCreditSnapshot(rfq.accountId);
      if (credit != null && quotation.totalMinor > credit.availableCreditMinor) {
        throw DomainFailure(
          code: DomainFailureCode.conflict,
          operation: 'convert_quotation_to_order',
          retryable: false,
          message: 'Insufficient available credit for account ${rfq.accountId}',
        );
      }

      if (rfq.items.isEmpty) {
        throw DomainFailure(
          code: DomainFailureCode.validation,
          operation: 'convert_quotation_to_order',
          retryable: false,
          message: 'RFQ ${rfq.id} has no items to convert',
        );
      }

      final cart = Cart(id: 'quotation-$quotationId', items: rfq.items);
      return await _orders.createOrder(
        cart: cart,
        idempotencyKey: idempotencyKey,
      );
    } on DomainFailure catch (failure) {
      throw _scope('convert_quotation_to_order', failure);
    }
  }

  Future<AccountMembership> _requireMembership({
    required String accountId,
    required String identityId,
    required String operation,
  }) async {
    final membership = await _accounts.getMembership(
      accountId: accountId,
      identityId: identityId,
    );
    if (membership == null || !_b2bRoles.contains(membership.role)) {
      throw DomainFailure(
        code: DomainFailureCode.forbidden,
        operation: operation,
        retryable: false,
        message: 'Insufficient permission for account $accountId',
      );
    }
    return membership;
  }

  DomainFailure _scope(String operation, DomainFailure failure) =>
      DomainFailure(
        code: failure.code,
        operation: operation,
        retryable: failure.retryable,
        message: failure.message,
        correlationId: failure.correlationId,
      );
}
