import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('identity', () {
    test('requires a stable non-empty id', () {
      expect(
        () => AppIdentity(
          id: '  ',
          email: 'buyer@example.test',
          displayName: 'Buyer',
          role: UserRole.consumer,
        ),
        throwsArgumentError,
      );
    });

    test('resolves roles through memberships, not a global role alone', () {
      final identity = AppIdentity(
        id: 'user-1',
        email: 'buyer@example.test',
        displayName: 'Buyer',
        role: UserRole.consumer,
        memberships: [
          AccountMembership(
            accountId: 'account-1',
            identityId: 'user-1',
            role: UserRole.b2bBuyer,
          ),
          AccountMembership(
            accountId: 'account-2',
            identityId: 'user-1',
            role: UserRole.b2bManager,
          ),
        ],
      );

      expect(identity.role, UserRole.consumer);
      expect(identity.memberships, hasLength(2));
      expect(identity.memberships.first.role, UserRole.b2bBuyer);
      expect(identity.memberships.last.role, UserRole.b2bManager);
      expect(
        () => identity.memberships.add(
          AccountMembership(
            accountId: 'account-3',
            identityId: 'user-1',
            role: UserRole.admin,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('exposes exactly the reference roles', () {
      expect(
        UserRole.values.map((role) => role.name).toList(),
        <String>['consumer', 'b2bBuyer', 'b2bManager', 'admin'],
      );
    });
  });

  group('catalog models', () {
    test('require positive monetary quantities', () {
      expect(
        () => Product(
          id: 'prd-01',
          name: 'USB-C Hub',
          sku: 'SKU-ELE-1000',
          priceMinor: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => Variant(
          id: 'var-01',
          productId: 'prd-01',
          name: 'Default',
          sku: 'SKU-ELE-1000',
          priceMinor: -1,
        ),
        throwsArgumentError,
      );
    });

    test('keep variant attributes immutable', () {
      final variant = Variant(
        id: 'var-01',
        productId: 'prd-01',
        name: 'Default',
        sku: 'SKU-ELE-1000',
        priceMinor: 674,
        attributes: {'color': 'black'},
      );

      expect(variant.attributes, {'color': 'black'});
      expect(
        () => variant.attributes['size'] = 'large',
        throwsUnsupportedError,
      );
    });

    test('reject negative inventory availability', () {
      expect(
        () => InventoryAvailability(variantId: 'var-01', available: -1),
        throwsArgumentError,
      );
      expect(
        InventoryAvailability(variantId: 'var-01', available: 0).available,
        0,
      );
    });
  });

  group('B2B models', () {
    test('reject negative credit values', () {
      expect(
        () => CreditSnapshot(
          accountId: 'account-1',
          creditLimitMinor: -1,
          availableCreditMinor: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => CreditSnapshot(
          accountId: 'account-1',
          creditLimitMinor: 1000,
          availableCreditMinor: -1,
        ),
        throwsArgumentError,
      );
    });

    test('carry account-specific membership roles', () {
      final membership = AccountMembership(
        accountId: 'account-1',
        identityId: 'user-1',
        role: UserRole.b2bManager,
      );

      expect(membership.accountId, 'account-1');
      expect(membership.identityId, 'user-1');
      expect(membership.role, UserRole.b2bManager);
    });
  });

  group('cart and order models', () {
    test('require positive cart quantities and prices', () {
      expect(
        () => CartItem(
          productId: 'prd-01',
          variantId: 'var-01',
          quantity: 0,
          unitPriceMinor: 674,
        ),
        throwsArgumentError,
      );
      expect(
        () => CartItem(
          productId: 'prd-01',
          variantId: 'var-01',
          quantity: 1,
          unitPriceMinor: 0,
        ),
        throwsArgumentError,
      );
    });

    test('keep cart items immutable and total the cart', () {
      final cart = Cart(
        id: 'cart-1',
        items: [
          CartItem(
            productId: 'prd-01',
            variantId: 'var-01',
            quantity: 2,
            unitPriceMinor: 674,
          ),
        ],
      );

      expect(cart.subtotalMinor, 1348);
      expect(
        () => cart.items.add(
          CartItem(
            productId: 'prd-02',
            variantId: 'var-02',
            quantity: 1,
            unitPriceMinor: 1049,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('build an order from a cart with a stable identity', () {
      final cart = Cart(
        id: 'cart-1',
        items: [
          CartItem(
            productId: 'prd-01',
            variantId: 'var-01',
            quantity: 2,
            unitPriceMinor: 674,
          ),
        ],
      );

      final order = Order.fromCart(cart, id: 'order-1');

      expect(order.id, 'order-1');
      expect(order.items, hasLength(1));
      expect(order.items.first.quantity, 2);
      expect(order.items.first.lineTotalMinor, 1348);
      expect(order.totalMinor, 1348);
      expect(order.status, OrderStatus.pending);
      expect(() => order.items.add(order.items.first), throwsUnsupportedError);
    });

    test('require a non-empty order id', () {
      expect(
        () => Order.fromCart(
          Cart(id: 'cart-1'),
          id: '',
        ),
        throwsArgumentError,
      );
    });
  });

  group('quote models', () {
    test('require a non-empty RFQ id and immutable items', () {
      expect(
        () => Rfq(id: '', accountId: 'account-1'),
        throwsArgumentError,
      );

      final rfq = Rfq(
        id: 'rfq-1',
        accountId: 'account-1',
        items: [
          CartItem(
            productId: 'prd-01',
            variantId: 'var-01',
            quantity: 5,
            unitPriceMinor: 674,
          ),
        ],
      );

      expect(rfq.status, RfqStatus.submitted);
      expect(() => rfq.items.clear(), throwsUnsupportedError);
    });

    test('require non-negative quotation totals', () {
      expect(
        () => Quotation(
          id: 'quo-1',
          rfqId: 'rfq-1',
          totalMinor: -1,
          status: QuotationStatus.draft,
        ),
        throwsArgumentError,
      );
      expect(
        Quotation(
          id: 'quo-1',
          rfqId: 'rfq-1',
          totalMinor: 0,
          status: QuotationStatus.draft,
        ).totalMinor,
        0,
      );
    });
  });

  group('customer and account models', () {
    test('require stable non-empty identifiers', () {
      expect(
        () => CustomerProfile(
          id: '',
          identityId: 'user-1',
          displayName: 'Buyer',
          email: 'buyer@example.test',
        ),
        throwsArgumentError,
      );
      expect(
        () => BusinessAccount(id: '', name: 'Acme'),
        throwsArgumentError,
      );
    });
  });
}
