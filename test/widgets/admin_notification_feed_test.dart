import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:app/providers/admin_notification_provider.dart';
import 'package:app/screens/admin/admin_notification_center_screen.dart';
import 'package:app/screens/admin/seller_business_docs_review_screen.dart';
import 'package:app/services/admin_notification_service.dart';
import 'package:app/widgets/admin/admin_notification_bell.dart';

/// The admin feed's UI contract, exercised through the real widgets and the
/// real `AdminNotificationProvider`.
///
/// The transport is the one seam faked: `AdminNotificationService` is
/// substituted so the provider's own logic — optimistic read, rollback,
/// unread arithmetic — is what runs. Every assertion here fails if the
/// behaviour it describes is removed:
///
///   • deleting the badge → 'the bell shows the unread count' fails
///   • always painting the dot → the read-notice assertions fail
///   • a non-optimistic markAsRead → 'updates without a reload' fails on the
///     call counters and the row's dot
///   • dropping the rollback → 'a failed read is rolled back' fails
///   • navigating nowhere → the queue assertion fails
///   • removing onRefresh → the refresh count stays 1
///
/// The database side (the trigger writing rows) is covered separately by
/// `supabase/tests/admin_notifications.test.sql`; nothing here re-tests it.
class _FakeAdminNotificationService extends AdminNotificationService {
  _FakeAdminNotificationService(this.rows);

  List<AdminNotification> rows;
  bool failMarkRead = false;
  bool failMarkAll = false;

  int fetchCalls = 0;
  int unreadCalls = 0;
  int markReadCalls = 0;
  int markAllCalls = 0;

  @override
  Future<List<AdminNotification>> fetch({int limit = 50}) async {
    fetchCalls++;
    return List<AdminNotification>.of(rows);
  }

  @override
  Future<int> unreadCount() async {
    unreadCalls++;
    return rows.where((n) => !n.isRead).length;
  }

  @override
  Future<void> markAsRead(String id) async {
    markReadCalls++;
    if (failMarkRead) throw Exception('read failed');
    rows = [
      for (final n in rows)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ];
  }

  @override
  Future<void> markAllAsRead() async {
    markAllCalls++;
    if (failMarkAll) throw Exception('read-all failed');
    rows = [for (final n in rows) n.copyWith(isRead: true)];
  }
}

AdminNotification notice(String id, {required bool read}) =>
    AdminNotification(
      id: id,
      type: 'business_docs_resubmitted',
      title: 'Resubmitted $id',
      body: 'Seller $id sent new documents after a rejection.',
      referenceId: 'seller-$id',
      isRead: read,
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );

Widget feedHarness(AdminNotificationProvider provider) =>
    ChangeNotifierProvider<AdminNotificationProvider>.value(
      value: provider,
      child: const MaterialApp(home: AdminNotificationCenterScreen()),
    );

Widget bellHarness(AdminNotificationProvider provider) =>
    ChangeNotifierProvider<AdminNotificationProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: Scaffold(
          appBar: _BellOnlyAppBar(),
        ),
      ),
    );

/// An AppBar holding just the bell, so the badge is exercised on its own.
class _BellOnlyAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _BellOnlyAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(actions: const [AdminNotificationBell()]);
  }
}

Future<void> openFeed(WidgetTester tester, AdminNotificationProvider p) async {
  await tester.pumpWidget(feedHarness(p));
  await tester.pump(); // post-frame load starts
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bell shows the unread count, and drops the badge as rows '
      'are read — without re-querying', (tester) async {
    final fake = _FakeAdminNotificationService([
      notice('a', read: false),
      notice('b', read: false),
    ]);
    final provider = AdminNotificationProvider(service: fake);
    // The feed is what the bell opens, so load it the way that screen does:
    // rows and count together. Reading a specific notice needs the rows.
    await provider.load();

    await tester.pumpWidget(bellHarness(provider));
    await tester.pump();

    expect(find.byKey(const Key('admin-notification-badge')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byTooltip('Notifications, 2 unread'), findsOneWidget);
    expect(fake.fetchCalls, 1);
    expect(fake.unreadCalls, 0);

    // A single read: the badge follows the provider, it does not re-query.
    await provider.markAsRead('a');
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
    expect(find.byTooltip('Notifications, 1 unread'), findsOneWidget);
    expect(fake.markReadCalls, 1);
    expect(fake.unreadCalls, 0,
        reason: 'the badge must react to the provider, not to a fresh query');
    expect(fake.fetchCalls, 1,
        reason: 'reading one row must not reload the feed');

    await provider.markAllAsRead();
    await tester.pump();

    expect(find.byKey(const Key('admin-notification-badge')), findsNothing);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(fake.markAllCalls, 1);
    expect(fake.unreadCalls, 0);
    expect(fake.fetchCalls, 1);
  });

  testWidgets('the bell has no badge when nothing is unread', (tester) async {
    final fake = _FakeAdminNotificationService([notice('a', read: true)]);
    final provider = AdminNotificationProvider(service: fake);
    await provider.loadUnread();

    await tester.pumpWidget(bellHarness(provider));
    await tester.pump();

    expect(find.byKey(const Key('admin-notification-badge')), findsNothing);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('the feed lists unread and read notices distinguishably',
      (tester) async {
    final fake = _FakeAdminNotificationService([
      notice('new', read: false),
      notice('old', read: true),
    ]);
    final provider = AdminNotificationProvider(service: fake);

    await openFeed(tester, provider);

    expect(find.text('Resubmitted new'), findsOneWidget);
    expect(find.text('Resubmitted old'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-notice-unread-dot-new')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('admin-notice-unread-dot-old')),
        findsNothing);

    final unread = tester.widget<Text>(find.text('Resubmitted new'));
    final read = tester.widget<Text>(find.text('Resubmitted old'));
    expect(unread.style?.fontWeight, FontWeight.bold);
    expect(read.style?.fontWeight, isNot(FontWeight.bold));
  });

  testWidgets('tapping a notice marks it read and opens the Business Docs '
      'queue', (tester) async {
    final fake = _FakeAdminNotificationService([
      notice('a', read: false),
      notice('b', read: true),
    ]);
    final provider = AdminNotificationProvider(service: fake);

    await openFeed(tester, provider);
    expect(fake.fetchCalls, 1);

    await tester.tap(find.byKey(const ValueKey('admin-notice-a')));
    await tester.pumpAndSettle();

    expect(provider.notifications.firstWhere((n) => n.id == 'a').isRead, isTrue,
        reason: 'the tapped notice must be read in the feed\'s own state');
    expect(fake.markReadCalls, 1);
    expect(fake.fetchCalls, 1,
        reason: 'marking read updates the row; it must not reload the feed');
    expect(find.byType(SellerBusinessDocsReviewScreen), findsOneWidget,
        reason: 'a resubmission notice must open the queue it is about');

    // Back on the feed, the row must already look seen without another fetch.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('admin-notice-unread-dot-a')),
        findsNothing);
    final row = tester.widget<Text>(find.text('Resubmitted a'));
    expect(row.style?.fontWeight, isNot(FontWeight.bold));
    expect(fake.fetchCalls, 2,
        reason: 'closing the queue deliberately refreshes the feed once');
  });

  testWidgets('Mark all read clears every row and the badge in one move',
      (tester) async {
    final fake = _FakeAdminNotificationService([
      notice('a', read: false),
      notice('b', read: false),
      notice('c', read: true),
    ]);
    final provider = AdminNotificationProvider(service: fake);

    await openFeed(tester, provider);
    expect(provider.unreadCount, 2);

    await tester.tap(find.byKey(const Key('admin-notifications-mark-all')));
    await tester.pumpAndSettle();

    for (final id in ['a', 'b', 'c']) {
      expect(find.byKey(ValueKey('admin-notice-unread-dot-$id')), findsNothing,
          reason: '$id must no longer read as unseen');
    }
    expect(provider.unreadCount, 0);
    expect(fake.markAllCalls, 1);
    expect(fake.fetchCalls, 1,
        reason: 'mark-all updates the rows in place, no reload');
    // The action disappears once there is nothing left to mark.
    expect(find.byKey(const Key('admin-notifications-mark-all')), findsNothing);
  });

  testWidgets('pull-to-refresh reloads the feed', (tester) async {
    final fake = _FakeAdminNotificationService([notice('a', read: false)]);
    final provider = AdminNotificationProvider(service: fake);

    await openFeed(tester, provider);
    expect(fake.fetchCalls, 1);
    expect(find.text('Resubmitted c'), findsNothing);

    fake.rows = [...fake.rows, notice('c', read: false)];

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(fake.fetchCalls, 2, reason: 'the pull must run the same load again');
    expect(find.text('Resubmitted c'), findsOneWidget);
  });

  testWidgets('a failed read is rolled back instead of shown as seen',
      (tester) async {
    final fake = _FakeAdminNotificationService([notice('a', read: false)])
      ..failMarkRead = true;
    final provider = AdminNotificationProvider(service: fake);

    await openFeed(tester, provider);
    expect(find.byKey(const ValueKey('admin-notice-unread-dot-a')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('admin-notice-a')));
    await tester.pumpAndSettle();

    // The tap still opens the queue (that is not the failing call), so come
    // back to the feed to look at the row itself.
    expect(find.byType(SellerBusinessDocsReviewScreen), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(provider.notifications.single.isRead, isFalse,
        reason: 'the optimistic read must be undone when the UPDATE fails');
    expect(provider.unreadCount, 1);
    expect(find.byKey(const ValueKey('admin-notice-unread-dot-a')),
        findsOneWidget,
        reason: 'a failed read must not leave the notice looking seen');
    expect(fake.markReadCalls, 1);
  });

  testWidgets('a failed Mark all read leaves every row unread', (tester) async {
    final fake = _FakeAdminNotificationService([
      notice('a', read: false),
      notice('b', read: false),
    ])
      ..failMarkAll = true;
    final provider = AdminNotificationProvider(service: fake);

    await openFeed(tester, provider);
    expect(provider.unreadCount, 2);

    await tester.tap(find.byKey(const Key('admin-notifications-mark-all')));
    await tester.pumpAndSettle();

    expect(provider.unreadCount, 2);
    for (final id in ['a', 'b']) {
      expect(find.byKey(ValueKey('admin-notice-unread-dot-$id')),
          findsOneWidget,
          reason: '$id must still read as unseen');
    }
    expect(fake.markAllCalls, 1);
  });
}
