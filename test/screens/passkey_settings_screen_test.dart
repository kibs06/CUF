// Supabase's Passkey type is @experimental while passkeys are in beta.
// ignore_for_file: experimental_member_use

import 'package:app/screens/shared/passkey_settings_screen.dart';
import 'package:app/services/passkey_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthResponse, Passkey;

class _FakePasskeyGateway implements PasskeyGateway {
  _FakePasskeyGateway({List<Passkey>? initial})
    : passkeys = initial ?? <Passkey>[];

  final List<Passkey> passkeys;
  int nextId = 2;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<List<Passkey>> list() async => List.of(passkeys);

  @override
  Future<Passkey> register() async {
    final passkey = Passkey(
      id: '${nextId++}',
      friendlyName: 'Laptop passkey',
      createdAt: DateTime(2026, 2, 3),
    );
    passkeys.add(passkey);
    return passkey;
  }

  @override
  Future<void> delete(String passkeyId) async {
    passkeys.removeWhere((p) => p.id == passkeyId);
  }

  @override
  Future<AuthResponse> signIn() async {
    throw UnimplementedError('Sign-in is exercised by the auth screen.');
  }
}

void main() {
  final firstPasskey = Passkey(
    id: '1',
    friendlyName: 'Pixel passkey',
    createdAt: DateTime(2026, 1, 2),
  );

  testWidgets('lists, adds, and removes a passkey', (tester) async {
    final gateway = _FakePasskeyGateway(initial: [firstPasskey]);

    await tester.pumpWidget(
      MaterialApp(home: PasskeySettingsScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pixel passkey'), findsOneWidget);
    expect(find.text('Add a passkey'), findsOneWidget);

    await tester.tap(find.text('Add a passkey'));
    await tester.pumpAndSettle();

    expect(find.text('Laptop passkey'), findsOneWidget);
    expect(gateway.passkeys.length, 2);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Remove this passkey?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Pixel passkey'), findsNothing);
    expect(gateway.passkeys.length, 1);
  });

  testWidgets('shows the empty state when there are no passkeys', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PasskeySettingsScreen(gateway: _FakePasskeyGateway())),
    );
    await tester.pumpAndSettle();

    expect(find.text('No passkey yet'), findsOneWidget);
    expect(find.text('Add a passkey'), findsOneWidget);
  });
}
