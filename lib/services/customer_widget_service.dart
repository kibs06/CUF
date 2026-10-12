import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_widget_data.dart';
import '../utils/customer_widget_feed.dart';
import '../utils/product_images.dart';
import '../utils/sale_price.dart';
import '../utils/size_match.dart';
import 'supabase_service.dart';

/// Builds the **customer** half of the home-screen widget: the ONE product a
/// customer's tile shows, and the local thumbnail for it.
///
/// The tile is a 3×3 card, so what changes between refreshes is *which* product is
/// on it — drawn at random from the shelf that is currently showing, which is the
/// behaviour asked for ("one card every refresh, in random"). The three shelves
/// themselves still rotate on the scheduled run; see [pickGroup].
///
/// ## Why this is a service and not part of the widget's writer
///
/// It GATHERS and returns; it never writes to the widget's store.
/// `SellerWidgetService` remains the only writer for both roles, so the rules that
/// matter about the store — one definition of where the payload lives, one place
/// that knows an `int` must not be written through the `String` branch, one
/// `clear()` that erases both families of keys — stay in one file instead of
/// being copied into a second one that could fall out of step.
///
/// ## The three things it has to get right
///
///  * **Nothing here is a new rule.** "On sale" is [isOnSale], "in my size" is
///    [productsInMySize], and the price shown is [effectivePrice] — the same
///    functions the catalog, the ON SALE poster and Home's "Based on your size"
///    grid use. A tile that disagreed with the app about what is on sale or what
///    fits would be the shop contradicting itself on the customer's own home
///    screen.
///  * **The customer's size comes from their profile**, through the same
///    [shoppingEuSizeFrom] / [shoppingCategoryFrom] helpers the app's size grid
///    uses. The in-memory AR measurement those helpers also accept is NOT
///    available here (a background isolate has no provider tree and this
///    deliberately does not fetch one), so the profile snapshot decides — which
///    is the same value both the scan and the manual picker persist.
///  * **The photographs are downloaded and cached by slot**, because the native
///    side cannot fetch anything. A widget is drawn by the launcher in a process
///    with no session and no network code of ours; all it can do is decode a file
///    that is already on disk. See [_cacheThumbnail] for why the cache is keyed by
///    slot and skipped when the URL has not moved.
class CustomerWidgetService {
  CustomerWidgetService._();

  static final CustomerWidgetService instance = CustomerWidgetService._();

  /// Ceiling on a downloaded thumbnail.
  ///
  /// **8 MB, and this is a download-and-disk guard rather than a rendering one.**
  /// The bitmap that reaches the launcher is not this file: the provider decodes it
  /// header-first and samples it down to 192 px a side as RGB_565
  /// (`THUMBNAIL_MAX_PX`), so what crosses the Binder is ~74 KB whatever the source
  /// weighed.
  ///
  /// **The first version of this constant said the opposite — that an oversized
  /// image "is not slow, it is a failed update" — and set 2 MB, and the first phone
  /// it ran on had a product photograph of 2,562,362 bytes.** The result was one of
  /// the tile's three rows drawing with no picture while the other two had theirs:
  /// a defect visible on a real home screen, caused by a limit that was never
  /// protecting anything. A 12 MP camera JPEG is routinely 3–5 MB, so any ceiling
  /// below that drops ordinary catalogue images.
  ///
  /// The guard still exists, because this runs in the background and writes into
  /// the app's own files: a pathological response must not become an unbounded
  /// download. 8 MB covers a phone photograph with room to spare, and the cache
  /// holds at most one file per slot ([_pruneSlot]).
  static const int maxThumbnailBytes = 8 * 1024 * 1024;

  /// Build the customer payload, or null when there is nothing to show.
  ///
  /// Null is a real answer, not a failure: a catalog with no live sale, no
  /// product in the customer's size and nothing new has no group to rotate to,
  /// and the caller's response to that is to clear the tile rather than print a
  /// heading over an empty shelf.
  ///
  /// [advance] moves the rotation on to the next group — true for the scheduled
  /// background refresh, false for an app-driven sync (see [pickGroup]).
  Future<CustomerWidgetData?> gather({required bool advance}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    final now = DateTime.now();

    final List<Map<String, dynamic>> products;
    final Map<String, dynamic>? profile;
    try {
      // The profile is read with its own narrow select rather than through
      // `AuthService.getProfile`: that one retries against the signup trigger and
      // CREATES a missing row, which is the right behaviour on the auth path and
      // the wrong one inside a periodic background job.
      profile = await Supabase.instance.client
          .from('profiles')
          .select('foot_size_ph, foot_size_category')
          .eq('id', userId)
          .maybeSingle();
      products = await SupabaseService.instance.fetchProducts();
    } catch (e) {
      debugPrint('[CustomerWidget] fetch failed: $e');
      return null;
    }

    if (products.isEmpty) {
      debugPrint('[CustomerWidget] catalog is empty → nothing to show');
      return null;
    }

    final euSize = shoppingEuSizeFrom(profile);
    final category = shoppingCategoryFrom(profile);

    // Which groups have anything in them right now. Asked with `limit: 1`
    // because the question is only "is this shelf non-empty"; the real pick
    // happens after the rotation has chosen one.
    final available = <CustomerWidgetGroup>{};
    for (final group in CustomerWidgetGroup.values) {
      final probe = feedForGroup(
        group,
        products,
        euSize: euSize,
        category: category,
        limit: 1,
        now: now,
      );
      if (probe.isNotEmpty) available.add(group);
    }

    final lastShown = await _lastShownIndex();
    final group = pickGroup(
      available: available,
      lastShownIndex: lastShown,
      advance: advance,
    );
    if (group == null) {
      debugPrint('[CustomerWidget] no group has products → nothing to show');
      return null;
    }

    // One card, and WHICH card changes on every refresh: the pick is random
    // within the shelf, preferring not to repeat the product the tile already
    // shows. `Random()` is created per call rather than held, because this whole
    // service runs in a background isolate that may not exist a second time — and
    // a seeded generator shared across refreshes would produce the same product
    // every time, which is the one thing this must not do.
    final picks = feedForGroup(
      group,
      products,
      euSize: euSize,
      category: category,
      now: now,
      random: Random(),
      avoidId: await _lastShownProductId(),
    );

    final shown = <CustomerWidgetProduct>[];
    for (var slot = 1; slot <= picks.length; slot++) {
      final product = picks[slot - 1];
      final id = product['id']?.toString() ?? '';
      // A product with no id cannot be opened by a tap and cannot be keyed in the
      // cache, so it is skipped rather than drawn as a dead row.
      if (id.isEmpty) continue;

      final urls = productImageUrls(product);
      final path = urls.isEmpty
          ? ''
          : await _cacheThumbnail(slot: slot, url: urls.first);

      shown.add(
        CustomerWidgetProduct(
          id: id,
          name: (product['name'] ?? '').toString(),
          // The price the customer actually pays, so a sale tile and the product
          // page can never disagree about the number.
          price: effectivePrice(product, now: now),
          badge: formatDiscountBadge(salePercent(product, now: now)),
          imagePath: path,
        ),
      );
    }

    if (shown.isEmpty) {
      debugPrint('[CustomerWidget] picked products carried no id → nothing to show');
      return null;
    }

    debugPrint('[CustomerWidget] showing ${group.wire} '
        '(${shown.length} product${shown.length == 1 ? '' : 's'}, '
        'size=${euSize?.toStringAsFixed(0) ?? 'none'})');

    return CustomerWidgetData(
      group: group,
      products: shown,
      sizeLabel: group == CustomerWidgetGroup.inMySize && euSize != null
          ? euSizeLabel(euSize)
          : '',
      rotationIndex: group.index,
      updatedAt: now,
    );
  }

  /// Where the tile keeps its thumbnails.
  ///
  /// The application-support directory rather than a cache directory: this is
  /// data the widget needs in order to draw at all, and a cache directory is one
  /// an OS-triggered purge may empty while the tile is still on the launcher —
  /// which would leave three blank rows until the next refresh, up to half an
  /// hour later.
  Future<Directory> _thumbnailDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/widget-thumbnails');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Download [url] to this device once, and hand back the local path.
  ///
  /// **The cache key is the URL itself, carried in the file's NAME** —
  /// `slot2-1f3a9c04.img`. Three things follow, and each replaces a worse
  /// design:
  ///
  ///  * **A refresh that picks the same photograph downloads nothing.** The job
  ///    runs every 30 minutes and the top of "New arrivals" rarely moves, so
  ///    without this the same three images would cross the customer's data plan
  ///    forty-eight times a day.
  ///  * **A changed photograph is picked up immediately.** Keying the file on the
  ///    product id instead would have been smaller and wrong: a seller who
  ///    replaces a photo keeps the same id, so the tile would show the old picture
  ///    until that product happened to drop out of the group.
  ///  * **The files cannot grow without bound.** Names start with the slot, so
  ///    each write prunes the other files that slot ever produced — at most three
  ///    live thumbnails, however long the tile runs.
  ///
  /// Every failure returns `''` — no thumbnail — rather than throwing: a product
  /// without its photograph is a tile with a text row, and that is strictly
  /// better than a tile that failed to update at all.
  Future<String> _cacheThumbnail({required int slot, required String url}) async {
    try {
      final dir = await _thumbnailDirectory();
      final file = File('${dir.path}/slot$slot-${stableUrlHash(url)}.img');

      if (file.existsSync()) return file.path;

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        debugPrint('[CustomerWidget] thumbnail $slot: HTTP ${response.statusCode}');
        return '';
      }
      if (response.bodyBytes.length > maxThumbnailBytes) {
        debugPrint('[CustomerWidget] thumbnail $slot: '
            '${response.bodyBytes.length} bytes is over the tile\'s ceiling');
        return '';
      }

      await file.writeAsBytes(response.bodyBytes, flush: true);
      await _pruneSlot(dir, slot, keep: file);
      return file.path;
    } catch (e) {
      debugPrint('[CustomerWidget] thumbnail $slot failed: $e');
      return '';
    }
  }

  /// Delete the other thumbnails this slot has produced, after a fresh write.
  Future<void> _pruneSlot(Directory dir, int slot, {required File keep}) async {
    try {
      for (final entry in dir.listSync()) {
        final name = entry.uri.pathSegments.last;
        if (entry.path == keep.path) continue;
        if (!name.startsWith('slot$slot-')) continue;
        entry.deleteSync();
      }
    } catch (e) {
      debugPrint('[CustomerWidget] thumbnail prune failed: $e');
    }
  }

  /// The rotation position the last payload left behind, or -1 when there is none.
  Future<int> _lastShownIndex() async {
    try {
      return await HomeWidget.getWidgetData<int>(CustomerWidgetKeys.rotation) ?? -1;
    } catch (e) {
      // A store that cannot be read is treated as "no position yet", which makes
      // the next refresh start at the first group rather than skip one.
      debugPrint('[CustomerWidget] rotation read failed: $e');
      return -1;
    }
  }

  /// The product the tile is showing right now, or null when it never has.
  ///
  /// Read back so the next pick can avoid repeating it: a random draw returns the
  /// same product about one time in *n*, and to the person holding the phone a card
  /// that did not change is indistinguishable from a refresh that failed. Nothing
  /// extra is stored for this — the id in slot 1 IS the record of what is on the
  /// tile, which is why this half of the payload needs no bookkeeping of its own.
  Future<String?> _lastShownProductId() async {
    try {
      final id = await HomeWidget.getWidgetData<String>(
        CustomerWidgetKeys.productId(1),
      );
      return (id == null || id.isEmpty) ? null : id;
    } catch (e) {
      // A store that cannot be read means "no previous product", which costs at
      // most one repeat and nothing else.
      debugPrint('[CustomerWidget] last product read failed: $e');
      return null;
    }
  }

}

/// A stable hash of a URL, for a cache filename — 32-bit FNV-1a, in hex.
///
/// **`String.hashCode` is deliberately NOT used.** Dart does not guarantee that
/// value is stable between runs (and the VM has salted it before now), and a hash
/// that changes per launch would silently reduce the thumbnail cache to "download
/// it again every refresh" — the exact cost the cache exists to avoid. Written
/// out rather than pulled from a package: it is eight lines, it has to be
/// reproducible on every device and Dart version, and a dependency that changed
/// its own algorithm would break the cache without breaking any test.
String stableUrlHash(String url) {
  var hash = 0x811c9dc5;
  for (final unit in url.codeUnits) {
    hash ^= unit;
    // `& 0xffffffff` keeps this 32-bit: Dart ints are 64-bit on the VM and
    // unbounded on the web, so the multiply would otherwise grow without limit.
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
