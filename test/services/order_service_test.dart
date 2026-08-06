import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app/services/order_service.dart';
import 'package:app/services/supabase_service.dart';

// Mock classes
class MockSupabaseService extends Mock implements SupabaseService {}
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// A real [PostgrestFilterBuilder] whose `eq` chain records calls and
/// resolves immediately — avoids mocking `Future.then`, which mocktail
/// cannot match on a Future-implementing mock.
class RecordingFilterBuilder extends PostgrestFilterBuilder<dynamic> {
  RecordingFilterBuilder()
      : super(
          PostgrestBuilder<dynamic, dynamic, dynamic>(
            url: Uri.parse('https://test.local'),
            headers: const <String, String>{},
          ),
        );

  final List<(String, Object)> eqCalls = [];

  @override
  PostgrestFilterBuilder<dynamic> eq(String column, Object value) {
    eqCalls.add((column, value));
    return this;
  }

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue,
      {Function? onError}) async {
    return onValue(<dynamic>[]);
  }
}

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
    test('deleteOrder always targets the cancelled status (guardrail)',
        () async {
      // Arrange — stub the query chain with a recording fake builder
      final query = MockSupabaseQueryBuilder();
      final filter = RecordingFilterBuilder();
      when(() => mockClient.from('orders')).thenAnswer((_) => query);
      when(() => query.delete()).thenAnswer((_) => filter);

      // Act
      await orderService.deleteOrder('order-123');

      // Assert — the status='cancelled' guard is baked into every call,
      // so a non-cancelled order can never be deleted through this path.
      verify(() => mockClient.from('orders')).called(1);
      verify(() => query.delete()).called(1);
      expect(filter.eqCalls, [
        ('id', 'order-123'),
        ('status', 'cancelled'),
      ]);
    });
  });
}
