import 'package:app/models/customer_widget_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CustomerWidgetProduct item({String id = 'p1', double price = 2499, String badge = ''}) =>
      CustomerWidgetProduct(id: id, name: 'Air Max $id', price: price, badge: badge);

  CustomerWidgetData feed({
    List<CustomerWidgetProduct>? products,
    CustomerWidgetGroup group = CustomerWidgetGroup.newArrivals,
    String sizeLabel = '',
  }) =>
      CustomerWidgetData(
        group: group,
        products: products ?? [item()],
        sizeLabel: sizeLabel,
        rotationIndex: group.index,
        updatedAt: DateTime(2026, 10, 12, 15, 7),
      );

  group('the eraser can clear what the writer writes', () {
    // ⚠️ The seller payload's own rule, and it has to hold here too: a key the
    // writer fills and the eraser does not know about is stale data that survives
    // a sign-out. It fails OPEN, which is the direction that matters.
    test('the writer\'s key set is exactly the eraser\'s list', () {
      expect(feed().toWidgetValues().keys.toSet(),
          CustomerWidgetKeys.all.toSet());
    });

    test('and it holds with no product at all, too', () {
      // The empty slot is written as a blank rather than skipped, so the two sets
      // stay equal at every product count — which is what makes the native side's
      // "a blank id means no card" rule safe to rely on.
      final values = feed(products: const []).toWidgetValues();
      expect(values.keys.toSet(), CustomerWidgetKeys.all.toSet());
      expect(values[CustomerWidgetKeys.productId(1)], '');
      expect(values[CustomerWidgetKeys.productName(1)], '');
      expect(values[CustomerWidgetKeys.productImage(1)], '');
    });

    test('every product slot has its own five keys', () {
      for (var slot = 1; slot <= kCustomerWidgetProductSlots; slot++) {
        final keys = [
          CustomerWidgetKeys.productId(slot),
          CustomerWidgetKeys.productName(slot),
          CustomerWidgetKeys.productPrice(slot),
          CustomerWidgetKeys.productBadge(slot),
          CustomerWidgetKeys.productImage(slot),
        ];
        expect(keys.toSet().length, 5, reason: 'slot $slot reuses a key');
        for (final key in keys) {
          expect(CustomerWidgetKeys.all, contains(key));
        }
      }
    });
  });

  group('what the native side is told', () {
    test('a feed says so in the state key, not by a non-empty name', () {
      final values = feed().toWidgetValues();
      expect(values[CustomerWidgetKeys.state], CustomerWidgetKeys.stateFeed);
      expect(values[CustomerWidgetKeys.group], 'new');
    });

    test('the empty state is its own value, and it says nothing else', () {
      // The whole reason this exists: a signed-in customer with nothing to show
      // must NOT fall through to the seller layouts' "sign in" copy. One key, and
      // the tile stays in the customer layouts.
      final values = CustomerWidgetData.emptyStateValues();
      expect(values[CustomerWidgetKeys.state], CustomerWidgetKeys.stateEmpty);
      expect(values.length, 1);
    });

    test('the group travels as its wire value, and round-trips', () {
      for (final group in CustomerWidgetGroup.values) {
        final values = feed(group: group).toWidgetValues();
        expect(values[CustomerWidgetKeys.group], group.wire);
        expect(CustomerWidgetGroup.fromWire(group.wire), group);
      }
    });

    test('the wire values are distinct', () {
      final wires = CustomerWidgetGroup.values.map((g) => g.wire).toSet();
      expect(wires.length, CustomerWidgetGroup.values.length);
    });

    test('an unknown wire value is null rather than a default', () {
      // A payload from another build must never be guessed at: the provider has its
      // own neutral fallback heading, and picking a group here would put real
      // products under a heading that describes something else.
      expect(CustomerWidgetGroup.fromWire('clearance'), isNull);
      expect(CustomerWidgetGroup.fromWire(''), isNull);
      expect(CustomerWidgetGroup.fromWire(null), isNull);
    });

    test('the price is pre-formatted, because RemoteViews cannot format', () {
      expect(item(price: 2499).priceLabel, '₱2,499');
      expect(item(price: 950).priceLabel, '₱950');
      expect(item(price: 0).priceLabel, '₱0');
      expect(item(price: 1234567).priceLabel, '₱1,234,567');
      // A refund-shaped price keeps its sign rather than losing it to the floor.
      expect(item(price: -250).priceLabel, '-₱250');
    });

    test('the clock is absolute, like the seller tile\'s', () {
      expect(feed().updatedAtLabel, '3:07 PM');
      expect(
        CustomerWidgetData(
          group: CustomerWidgetGroup.onSale,
          products: [item()],
          sizeLabel: '',
          rotationIndex: 2,
          updatedAt: DateTime(2026, 10, 12, 0, 5),
        ).updatedAtLabel,
        '12:05 AM',
      );
    });

    test('exactly ONE product is written, whatever the caller hands over', () {
      // The payload caps itself at [kCustomerWidgetProductSlots] rather than
      // trusting its caller, and the cap is worth pinning: a second product
      // arriving here would be written into no key at all — dropped silently
      // rather than drawn wrongly, which is the harder of the two to notice.
      expect(kCustomerWidgetProductSlots, 1, reason: 'the tile is one card');

      final values = feed(products: [item(id: 'a'), item(id: 'b')]).toWidgetValues();
      expect(values[CustomerWidgetKeys.productId(1)], 'a');
      expect(values.containsKey(CustomerWidgetKeys.productId(2)), isFalse);
    });
  });

  group('the discount badge', () {
    test('is blank when there is no live discount', () {
      expect(formatDiscountBadge(null), '');
      expect(formatDiscountBadge(0), '');
      expect(formatDiscountBadge(-5), '');
    });

    test('and prints the whole percent when there is', () {
      expect(formatDiscountBadge(20), '-20%');
      expect(formatDiscountBadge(1), '-1%');
    });
  });

  group('formatPesoPrice', () {
    test('groups thousands and drops the cents', () {
      // Floored rather than rounded: every price in the app is a whole peso, and
      // rounding UP could print a price higher than the one charged.
      expect(formatPesoPrice(2499.99), '₱2,499');
      expect(formatPesoPrice(1000), '₱1,000');
      expect(formatPesoPrice(999), '₱999');
      expect(formatPesoPrice(1000000), '₱1,000,000');
    });
  });
}
