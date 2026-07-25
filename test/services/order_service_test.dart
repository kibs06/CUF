import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/services/order_service.dart';
import 'package:app/services/supabase_service.dart';

// Mock classes
class MockSupabaseService extends Mock implements SupabaseService {}
class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late OrderService orderService;
  late MockSupabaseService mockDb;
  late MockSupabaseClient mockClient;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockDb = MockSupabaseService();
    mockClient = MockSupabaseClient();
    
    // Pass both mocked dependencies to avoid Supabase.instance access
    orderService = OrderService(db: mockDb, client: mockClient);
  });

  group('OrderService', () {
    test('placeOrder calls _db.createOrder and returns order ID', () async {
      // Arrange
      final testDto = {
        'customer_id': 'customer1',
        'store_id': 'store1',
        'total_amount': 100.0,
      };

      when(() => mockDb.createOrder(testDto))
          .thenAnswer((_) async => {'id': 'order-123'});

      // Act
      final result = await orderService.placeOrder(testDto);

      // Assert
      expect(result, 'order-123');
      verify(() => mockDb.createOrder(testDto)).called(1);
    });

    test('placeOrder propagates exceptions from _db.createOrder', () async {
      // Arrange
      final testDto = <String, dynamic>{'customer_id': 'c1'};

      when(() => mockDb.createOrder(testDto))
          .thenThrow(Exception('Database error'));

      // Act & Assert
      expect(
        () => orderService.placeOrder(testDto),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Database error'),
        )),
      );
    });

    test('placeOrder returns correct order ID format', () async {
      // Arrange
      final testDto = {'items': []};

      when(() => mockDb.createOrder(testDto))
          .thenAnswer((_) async => {'id': 'uuid-order-456'});

      // Act
      final result = await orderService.placeOrder(testDto);

      // Assert
      expect(result, 'uuid-order-456');
    });

    test('updateOrderStatus delegates to _db.updateOrderStatus', () async {
      // Arrange
      when(() => mockDb.updateOrderStatus('order-123', 'preparing'))
          .thenAnswer((_) async => <String, dynamic>{});

      // Act
      await orderService.updateOrderStatus('order-123', 'preparing');

      // Assert
      verify(() => mockDb.updateOrderStatus('order-123', 'preparing')).called(1);
    });

    test('updateOrderStatus propagates PostgrestException', () async {
      // Arrange
      when(() => mockDb.updateOrderStatus('order-123', 'cancelled'))
          .thenThrow(PostgrestException(message: 'Check constraint failed', code: '23514'));

      // Act & Assert
      expect(
        () => orderService.updateOrderStatus('order-123', 'cancelled'),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
