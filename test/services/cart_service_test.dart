import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/services/cart_service.dart';
import 'package:app/models/cart_item_with_details.dart';

// Mock Supabase client
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockPostgrestQueryBuilder extends Mock implements PostgrestQueryBuilder {}
class MockPostgrestFilterBuilder extends Mock implements PostgrestFilterBuilder {}
class MockPostgrestTransformBuilder extends Mock implements PostgrestTransformBuilder {}
class MockUser extends Mock implements User {}

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;
  late MockUser mockUser;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    mockUser = MockUser();
    
    // Setup auth mock
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('test-user-id');
    
    // We'll need to override the Supabase.instance.client for testing
    // This is a limitation - CartService uses Supabase.instance.client directly
    // For now, we'll test the logic we can test
  });

  group('CartService', () {
    test('singleton pattern', () {
      final instance1 = CartService.instance;
      final instance2 = CartService.instance;
      expect(instance1, same(instance2));
    });
  });

  group('CartItemWithDetails', () {
    test('unitPrice calculates correctly', () {
      final item = CartItemWithDetails(
        id: '1',
        userId: 'user1',
        productId: 'product1',
        quantity: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        productName: 'Test Product',
        price: 100.0,
        additionalPrice: 20.0,
      );
      
      expect(item.unitPrice, 120.0);
      expect(item.lineTotal, 240.0);
    });

    test('toCartItemMap returns correct structure', () {
      final item = CartItemWithDetails(
        id: '1',
        userId: 'user1',
        productId: 'product1',
        variantId: 'variant1',
        quantity: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        productName: 'Test Product',
        price: 100.0,
        size: '42',
        color: 'Black',
        additionalPrice: 10.0,
      );
      
      final map = item.toCartItemMap();
      
      expect(map['product_id'], 'product1');
      expect(map['product_name'], 'Test Product');
      expect(map['price'], 110.0);
      expect(map['size'], '42');
      expect(map['color'], 'Black');
      expect(map['quantity'], 1);
      expect(map['variant_id'], 'variant1');
    });
  });
}