package com.solevision.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import androidx.annotation.ColorRes
import androidx.annotation.LayoutRes
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Draws the seller home-screen widget.
 *
 * ## Where the numbers come from
 *
 * This class **fetches nothing**. A widget's `onUpdate` runs in the launcher's
 * process with no Flutter engine, no Dart isolate and no Supabase session, so
 * the only thing it can do is render the snapshot the app already wrote — the
 * same `SharedPreferences` bag [SellerWidgetService] (Dart) fills via
 * `home_widget`, reached here through [HomeWidgetProvider]'s `widgetData`.
 *
 * That split is the whole design: **Dart fetches and decides, this class only
 * draws.** The consequence to remember when editing either side is that a
 * counter rendered here is a *picture of a number*, not a query — if it looks
 * stale, the fix is almost never in this file.
 *
 * ## Sizes
 *
 * The widget is resizable from 2×2 to full, and each tier gets its own layout
 * rather than one layout stretched — see [WidgetTier]. The tier is chosen from
 * the instance's own size on every update and on every resize, so it follows the
 * widget the user actually has.
 *
 * The four tiers, and the shape each one is for:
 *
 *     2×2      [WidgetTier.Small]   identity · today's takings · "3 to do" / "All clear"
 *     2×3+     [WidgetTier.Tall]    the same, plus orders / low stock / unread stacked
 *     4×2      [WidgetTier.Medium]  those three metrics side by side, plus the clock
 *     4×3+     [WidgetTier.Full]    all six metrics in two aligned rows
 *
 * ⚠️ The thresholds below are the launcher's *reported* numbers, which are not
 * the drawn size — see [WIDE_MIN_WIDTH_DP] for the measurement. That gap is why
 * this class carries a tier log in debug builds rather than a tidy rule.
 *
 * ## Why the keys are spelled out
 *
 * The `KEY_*` constants below are a wire format shared with
 * `lib/models/seller_widget_data.dart` (`SellerWidgetKeys`). There is no
 * generated binding between a Dart map and a Kotlin `SharedPreferences`, so they
 * are duplicated deliberately and must be changed together — a renamed key shows
 * as a blank field on every phone that already has the widget placed, not as a
 * compile error. `seller_widget_contract_test.dart` on the Dart side pins the
 * names.
 */
class SellerWidgetProvider : HomeWidgetProvider() {

    /**
     * The four sizes the SELLER half draws.
     *
     * Width decides first, because what actually breaks as a tile shrinks is the
     * number of COLUMNS; height decides second, and it decides two different
     * things: whether a second grid row fits, and whether a narrow tile has grown
     * tall enough to deserve a different SHAPE rather than a stretched square.
     *
     * ⚠️ **The customer half does not have tiers at all.** The same tile serves
     * both roles, and a customer's side of it is one card — a 3×3 square showing a
     * single product — so there is no per-size customer layout to choose between
     * and no customer column in this enum. What the launcher grants a customer is
     * still passed through, because the provider has to draw *something*: the card
     * is `wrap_content` and centred, so it is the same card at 2×2 and at 4×3 and
     * can be neither stretched nor cropped into the wrong shape. The three-product
     * layouts this replaced are gone, and with them the whole class of fault they
     * shipped: three cells 154 px wide and 740 px tall with each photograph a
     * 106×563 sliver, on a portrait tile the tier logic had called "wide".
     */
    private enum class WidgetTier(@LayoutRes val sellerLayout: Int) {
        Small(R.layout.seller_widget_small),

        Tall(R.layout.seller_widget_tall),

        Medium(R.layout.seller_widget_medium),

        Full(R.layout.seller_widget_full);

        /**
         * The layout this tier draws for [role].
         *
         * A customer's layout **takes no size**, and that is the point rather than
         * an oversight: the card is designed for a 3×3 tile and is `wrap_content`
         * and centred inside whatever the launcher grants, so there is nothing for a
         * size to decide. What this replaced was a per-tier customer layout plus an
         * aspect-ratio test, both of which existed only because three products had
         * to be arranged differently at different shapes — and the aspect test only
         * because the arrangement the tier logic chose for a *portrait* tile drew
         * three photographs as 106×563 slivers on a real phone. One card cannot do
         * that at any size, which is why [CUSTOMER_LAYOUT] is constant.
         */
        fun layoutFor(role: WidgetRole): Int =
            if (role == WidgetRole.Customer) CUSTOMER_LAYOUT else sellerLayout
    }

    /**
     * Which of the tile's two designs this phone is showing.
     *
     * Decided by ONE payload key, and only by that key: `customer_state`, whose
     * blank value means "not a customer" (draw the seller layouts, populated or
     * empty) and whose two values mean "a customer account is signed in" — with a
     * feed, or with nothing to show. Splitting that into a role flag plus a content
     * flag would make a fourth combination representable that nothing means.
     */
    private enum class WidgetRole { Seller, Customer }

    companion object {
        /**
         * Mirrors `SellerWidgetKeys` in `lib/models/seller_widget_data.dart`.
         * ⚠️ Change both sides together — see the class note.
         */
        private const val KEY_HAS_STORE = "seller_has_store"
        private const val KEY_STORE_NAME = "seller_store_name"
        private const val KEY_REVENUE_LABEL = "seller_revenue_label"
        private const val KEY_PENDING_ORDERS = "seller_pending_orders"
        private const val KEY_PENDING_CUSTOMS = "seller_pending_customs"
        private const val KEY_ACTIVE_PICKUPS = "seller_active_pickups"
        private const val KEY_PENDING_RESERVATIONS = "seller_pending_reservations"
        private const val KEY_ATTENTION_COUNT = "seller_attention_count"
        private const val KEY_LOW_STOCK = "seller_low_stock"
        private const val KEY_UNREAD = "seller_unread_notifications"
        private const val KEY_UPDATED_LABEL = "seller_updated_at_label"

        /**
         * Mirrors `CustomerWidgetKeys` in `lib/models/customer_widget_data.dart`.
         * ⚠️ Change both sides together — see the class note.
         */
        private const val KEY_CUSTOMER_STATE = "customer_state"
        private const val KEY_CUSTOMER_GROUP = "customer_group"
        private const val KEY_CUSTOMER_SIZE = "customer_size_label"
        private const val KEY_CUSTOMER_UPDATED = "customer_updated_at_label"

        /** The two values of [KEY_CUSTOMER_STATE] — never a third. */
        private const val CUSTOMER_STATE_FEED = "feed"
        private const val CUSTOMER_STATE_EMPTY = "empty"

        /**
         * The three groups, matching `CustomerWidgetGroup`'s wire values.
         *
         * The wire values are pinned against the Dart enum by
         * `seller_widget_contract_test.dart`, because a renamed one does not fail a
         * build: it prints the fallback heading over a real shelf.
         */
        private const val GROUP_NEW = "new"
        private const val GROUP_SUGGESTED = "suggested"
        private const val GROUP_SALE = "sale"

        /**
         * How many product slots the customer tile carries.
         *
         * **One**, mirroring `kCustomerWidgetProductSlots` on the Dart side (the
         * contract test pins the two together). The tile is a 3×3 card showing a
         * single product, and the shelf underneath it changes which one — so the
         * count is a constant rather than a per-size decision, and
         * count is a constant rather than a per-size decision: there is no size at
         * which the card shows fewer products, because it never shows more than one.
         */
        private const val CUSTOMER_SLOTS = 1

        /**
         * The layout a customer's tile draws, at every size.
         *
         * One layout rather than one per tier: the card is `wrap_content` and
         * centred, so a launcher that grants it 2×2 or 4×3 changes the space around
         * the card and not the card. See [WidgetTier] for the fault this replaced.
         */
        @LayoutRes
        private val CUSTOMER_LAYOUT = R.layout.customer_widget_card

        /**
         * Where a product row's tap goes — `solvision://product/{id}`.
         *
         * A contract with Dart: `DeepLinkService.productHost` names the same host,
         * and the contract test pins the two together. A widget can only hand the
         * launcher a URI, so a renamed host means a tap that opens the app on
         * nothing rather than a broken build.
         */
        private const val PRODUCT_DEEP_LINK_PREFIX = "solvision://product/"

        /**
         * Longest edge of a decoded thumbnail, in pixels.
         *
         * **A Binder budget and a quality floor, and the two numbers now have to be
         * read together.** RemoteViews crosses to the launcher in a transaction with
         * a hard size limit, so an oversized bitmap does not arrive blurry — it makes
         * the whole tile update fail. 384px at RGB_565 is ~295KB, and a customer's
         * tile carries exactly one, so the update stays well inside a 1MB
         * transaction.
         *
         * **It was 192 while the card drew its photograph at 44dp.** The card now
         * draws it at **108dp**, which is 324px at the 3× density a flagship
         * reports — so 192 would have been upscaled by roughly half on the very tile
         * this exists for, and the photograph would have looked soft for no reason.
         * 384 is that 108dp with headroom, and the decode still picks a power-of-two
         * `inSampleSize` rather than scaling after the fact (see [sampleSizeFor]).
         */
        private const val THUMBNAIL_MAX_PX = 384

        /** The payload key for one field of one product slot. */
        private fun customerKey(slot: Int, field: String) =
            "customer_product_${slot}_$field"

        /**
         * Slot → view ids, one entry per [CUSTOMER_SLOTS].
         *
         * Arrays rather than a `when` on the slot, so a second slot would be a
         * payload change and a layout change and nothing here: the loop reads the
         * same five views for every slot it is given.
         *
         * ⚠️ These have to hold EXACTLY as many ids as [CUSTOMER_LAYOUT] has views,
         * and the count is not self-checking: `R.id.customer_product_2` with no view
         * of that name is a **compile error** (which is how the three-product arrays
         * announced themselves when the card replaced them), but a slot the payload
         * writes and the layout lacks is RemoteViews' silent skip — no crash, no log,
         * just a card that never fills. `remote_views_safety_test.dart` reads both
         * sides to keep that from happening the quiet way.
         */
        private val CUSTOMER_ROW_IDS = intArrayOf(
            R.id.customer_product_1,
        )
        private val CUSTOMER_IMAGE_IDS = intArrayOf(
            R.id.customer_image_1,
        )
        private val CUSTOMER_NAME_IDS = intArrayOf(
            R.id.customer_name_1,
        )
        private val CUSTOMER_PRICE_IDS = intArrayOf(
            R.id.customer_price_1,
        )
        private val CUSTOMER_BADGE_IDS = intArrayOf(
            R.id.customer_badge_1,
        )

        /**
         * Where a tap goes: the seller shell, via the app's existing
         * `solvision://` scheme.
         *
         * A deep link rather than plain "open the app" because the app has
         * three roles behind one entry point — a customer tapping a seller tile
         * should land on their own home, and the link is what lets Dart make
         * that decision with the session it has. See `DeepLinkService`.
         */
        private const val SELLER_DEEP_LINK = "solvision://seller"

        /**
         * The launcher's reported width at which three metric columns fit.
         *
         * **180, not 240, and the difference is measured rather than reasoned.**
         * Three columns of pills need ~240dp of *drawn* width — but on the
         * launcher this widget was verified against (a P30 Pro's EMUI grid),
         * `OPTION_APPWIDGET_MIN_WIDTH` reports about a quarter LESS than the
         * tile's drawn width: a full-width tile measured at 408dp on screen
         * reported 304, which is 0.75×. So a 240 threshold here silently demanded
         * a 320dp tile, and a genuine three-column tile — one with room for the
         * three cells and therefore left as a void under a two-line tier — was
         * demoted to the smallest layout. 180 reported is that same 240 drawn,
         * with the narrowest honest case (a 2-column tile, which reports ~150)
         * still below it.
         *
         * ⚠️ A launcher's number is a heuristic and needs an owner: if a future
         * device reports the drawn width instead of this discounted value, this
         * constant is what to re-measure, and the tier log below is how (place
         * the widget, drag it, read the numbers back out of logcat).
         */
        private const val WIDE_MIN_WIDTH_DP = 180

        /**
         * Height at which a second metric row fits under the hero figure.
         *
         * ~150dp is the content's floor: card padding, header, the hero block
         * and two rows of cells. Under it, one row is the honest maximum.
         *
         * This one is NOT discounted the way the width is: that same full-width
         * tile reported a height of 132 against 304 of width, which is the right
         * order for a tile that is wide and short. Assuming both numbers carried
         * the same discount would have been the easy error here.
         */
        private const val TWO_ROW_MIN_HEIGHT_DP = 150

        /**
         * How much taller than wide a narrow tile must be to get the tall tier.
         *
         * **A ratio, complementing the absolute height above, because it is the
         * one test here that does not depend on how a launcher counts dp.** A
         * 2×2 is square-ish and a 2×3 is half again as tall as it is wide, and
         * that relationship survives whatever unit or discount the numbers
         * arrive in. Keeping it relative to the width also stops the tall tier
         * from being chosen for a WIDE tile that merely has height to spare:
         * those have three columns and want the grid, not a stack.
         *
         * 1.25 sits between a square (1.0) and a 2×3 (~1.5), with room either
         * way for a launcher whose cells are not exactly square.
         */
        private const val TALL_ASPECT_RATIO = 1.25f
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = buildViews(
                context,
                widgetData,
                appWidgetManager.getAppWidgetOptions(appWidgetId),
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    /**
     * Resize handler: a widget dragged bigger or smaller must change tier.
     *
     * Without this the layout would be whatever the last data refresh chose, so
     * shrinking a tile to 2×2 would keep drawing the six-cell grid into it until
     * the next background refresh — up to half an hour of a squashed widget, and
     * on a phone whose seller never resizes it, never corrected at all.
     *
     * `newOptions` is passed straight through rather than re-read, because it is
     * the post-resize measurement and re-reading a cached value is how a resize
     * silently keeps the old layout.
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        val views = buildViews(context, payloadStore(context), newOptions)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    /**
     * The tier a given instance should draw at.
     *
     * Read as three questions in order: is the tile WIDE enough for three
     * columns, and if so is it also tall enough for two rows of them; if it is
     * not wide, has it grown tall enough to be a different shape rather than
     * merely a bigger one.
     */
    private fun tierFor(options: Bundle): WidgetTier {
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)

        // ⚠️ 0 means the launcher reported NOTHING, not "tiniest possible".
        // Some launchers have not populated the options bundle by the first
        // update, and treating that as "small" would flash a 2×2 layout inside a
        // 4×3 tile. Falling back to Full matches `initialLayout`, which is what
        // the user is already looking at, so an unknown size changes nothing.
        //
        // Either dimension alone disqualifies the reading: the tall test below
        // compares the height against the WIDTH, so a missing width is not a
        // size the rest of this method can reason about.
        if (width <= 0 || height <= 0) return WidgetTier.Full

        return when {
            width >= WIDE_MIN_WIDTH_DP && height >= TWO_ROW_MIN_HEIGHT_DP ->
                WidgetTier.Full
            width >= WIDE_MIN_WIDTH_DP -> WidgetTier.Medium
            // Narrow. The only shape still in question is square versus tall —
            // an Int against a Float product, which Kotlin widens rather than
            // truncates.
            height >= width * TALL_ASPECT_RATIO -> WidgetTier.Tall
            else -> WidgetTier.Small
        }
    }

    private fun buildViews(
        context: Context,
        widgetData: SharedPreferences,
        options: Bundle?,
    ): RemoteViews {
        val tier = options?.let { tierFor(it) } ?: WidgetTier.Full
        val role = roleFor(widgetData)
        // The one decision the tier cannot make for a customer, answered once and
        // used by both the layout and the log line below.
        // Debug builds only. The launcher's reported size is the one input this
        // class cannot verify from a desk (see [WIDE_MIN_WIDTH_DP]), so it is
        // recorded where it can be read back — `adb logcat -s SellerWidgetSize`
        // — instead of guessed at. Never in a release build: this runs on every
        // update, and a widget that logs on every update is a battery cost for
        // no user-visible gain.
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            android.util.Log.d(
                "SellerWidgetSize",
                "role=$role raw=$options tier=$tier",
            )
        }
        val views = RemoteViews(context.packageName, tier.layoutFor(role))
        if (role == WidgetRole.Customer) {
            renderCustomer(context, views, widgetData, tier)
        } else {
            render(context, views, widgetData, tier)
        }
        return views
    }

    /**
     * Which role's tile to draw — see [WidgetRole].
     *
     * Reads ONE key and treats anything it does not recognise as "not a customer",
     * which is the safe direction: the worst that does is draw the seller tile's
     * empty state, where the other direction would put three product slots from a
     * stale payload on a seller's home screen.
     */
    private fun roleFor(widgetData: SharedPreferences): WidgetRole {
        val state = widgetData.getString(KEY_CUSTOMER_STATE, "") ?: ""
        return if (state.isEmpty()) WidgetRole.Seller else WidgetRole.Customer
    }

    private fun render(
        context: Context,
        views: RemoteViews,
        widgetData: SharedPreferences,
        tier: WidgetTier,
    ) {
        // The empty state is decided by ONE flag, never by "is the name blank" —
        // a store genuinely can be named "" and must not then look signed out.
        val hasStore = widgetData.getBoolean(KEY_HAS_STORE, false)

        if (!hasStore) {
            views.setViewVisibility(R.id.widget_content, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            applyTap(context, views)
            return
        }

        views.setViewVisibility(R.id.widget_content, View.VISIBLE)
        views.setViewVisibility(R.id.widget_empty, View.GONE)

        val storeName = widgetData.getString(KEY_STORE_NAME, "") ?: ""
        val revenue = widgetData.getString(KEY_REVENUE_LABEL, "\u2014") ?: "\u2014"
        val updated = widgetData.getString(KEY_UPDATED_LABEL, "") ?: ""

        val orders = widgetData.getInt(KEY_PENDING_ORDERS, 0)
        val customs = widgetData.getInt(KEY_PENDING_CUSTOMS, 0)
        val holds = widgetData.getInt(KEY_ACTIVE_PICKUPS, 0)
        val requests = widgetData.getInt(KEY_PENDING_RESERVATIONS, 0)
        val attention = widgetData.getInt(KEY_ATTENTION_COUNT, 0)
        val lowStock = widgetData.getInt(KEY_LOW_STOCK, 0)
        val unread = widgetData.getInt(KEY_UNREAD, 0)

        views.setTextViewText(R.id.widget_store_name, storeName)
        views.setTextViewText(R.id.widget_revenue, revenue)

        // ⚠️ Only the ids that exist in THIS tier's layout are set. RemoteViews
        // silently skips an action whose view is missing, so setting the full
        // grid's ids on the 2×2 layout would not crash — it would just make this
        // method unreadable and hide which numbers each size actually shows.
        when (tier) {
            WidgetTier.Small -> {
                val summaryLine = if (attention > 0) {
                    context.getString(R.string.seller_widget_attention_count, attention)
                } else {
                    context.getString(R.string.seller_widget_attention_none)
                }
                views.setTextViewText(R.id.widget_attention, summaryLine)
                // Muted when there is nothing to do, accent when there is: the
                // same rule the grid's counts follow, so a quiet store stays
                // quiet at every size.
                views.setTextColor(
                    R.id.widget_attention,
                    context.getColor(
                        if (attention > 0) R.color.seller_widget_accent
                        else R.color.seller_widget_muted,
                    ),
                )
                views.setContentDescription(
                    R.id.widget_root,
                    speak(context, storeName, revenue, summaryLine),
                )
            }

            WidgetTier.Tall -> {
                views.setTextViewText(
                    R.id.widget_updated,
                    context.getString(R.string.seller_widget_updated_at, updated),
                )
                setCount(context, views, R.id.widget_orders, orders, R.color.seller_widget_accent)
                setCount(context, views, R.id.widget_low_stock, lowStock, R.color.seller_widget_amber)
                setCount(context, views, R.id.widget_unread, unread, R.color.seller_widget_blue)
                // Deliberately the SAME sentence as Medium, because the two
                // tiers show the same three numbers. A screen reader should not
                // be told a different story depending on the shape of tile the
                // seller happened to drag this into.
                val spoken = context.getString(
                    R.string.seller_widget_a11y_summary_medium,
                    revenue,
                    orders,
                    lowStock,
                    unread,
                    updated,
                )
                views.setContentDescription(
                    R.id.widget_root,
                    if (storeName.isBlank()) spoken else "$storeName. $spoken",
                )
            }

            WidgetTier.Medium -> {
                views.setTextViewText(
                    R.id.widget_updated,
                    context.getString(R.string.seller_widget_updated_at, updated),
                )
                setCount(context, views, R.id.widget_orders, orders, R.color.seller_widget_accent)
                setCount(context, views, R.id.widget_low_stock, lowStock, R.color.seller_widget_amber)
                setCount(context, views, R.id.widget_unread, unread, R.color.seller_widget_blue)
                val spoken = context.getString(
                    R.string.seller_widget_a11y_summary_medium,
                    revenue,
                    orders,
                    lowStock,
                    unread,
                    updated,
                )
                views.setContentDescription(
                    R.id.widget_root,
                    if (storeName.isBlank()) spoken else "$storeName. $spoken",
                )
            }

            WidgetTier.Full -> {
                views.setTextViewText(
                    R.id.widget_updated,
                    context.getString(R.string.seller_widget_updated_at, updated),
                )
                // Each count takes its colour from its OWN value: zero is muted,
                // and only a non-empty queue is loud. Colour is never the sole
                // signal — every cell is labelled underneath, so the tile is
                // readable without perceiving hue at all.
                setCount(context, views, R.id.widget_orders, orders, R.color.seller_widget_accent)
                setCount(context, views, R.id.widget_customs, customs, R.color.seller_widget_accent)
                setCount(context, views, R.id.widget_holdings, holds, R.color.seller_widget_accent)
                setCount(context, views, R.id.widget_requests, requests, R.color.seller_widget_accent)
                // Restock is amber, not rust: running out is a warning about the
                // future, where the four queues above are work waiting now.
                setCount(context, views, R.id.widget_low_stock, lowStock, R.color.seller_widget_amber)
                // Unread is blue — inbound, not urgent, and deliberately the one
                // cool colour on a warm card so it reads as a different thing.
                setCount(context, views, R.id.widget_unread, unread, R.color.seller_widget_blue)

                val spoken = context.getString(
                    R.string.seller_widget_a11y_summary,
                    revenue,
                    orders,
                    customs,
                    holds,
                    requests,
                    lowStock,
                    unread,
                    updated,
                )
                views.setContentDescription(
                    R.id.widget_root,
                    if (storeName.isBlank()) spoken else "$storeName. $spoken",
                )
            }
        }

        applyTap(context, views)
    }

    /**
     * Draw the customer tile: one group of products, in whichever shape the size
     * allows.
     *
     * The group's NAME is not in the payload — only its wire value — because a
     * group's name is static copy, and static copy lives in `strings.xml` with the
     * rest of the widget's words rather than being rebuilt on the Dart side where
     * it could drift from the layout's own placeholder. [groupLabel] is where the
     * two meet.
     *
     * ⚠️ Nothing here decides what a customer can see. The three groups, their
     * order, the rotation and every inclusion rule are decided on the Dart side
     * (`CustomerWidgetService`), where the session, the size helpers and the sale
     * rule are. This function draws what it is handed, which is the same split the
     * seller half has, for the same reason: the launcher's process has no network,
     * no session and no Dart.
     */
    private fun renderCustomer(
        context: Context,
        views: RemoteViews,
        widgetData: SharedPreferences,
        tier: WidgetTier,
    ) {
        val state = widgetData.getString(KEY_CUSTOMER_STATE, "") ?: ""
        val hasFeed = state == CUSTOMER_STATE_FEED

        // These two views are the same ids in both customer layouts — a narrow and
        // a wide one — which is what lets one render path serve both sizes.
        views.setViewVisibility(
            R.id.widget_content,
            if (hasFeed) View.VISIBLE else View.GONE,
        )
        views.setViewVisibility(
            R.id.widget_empty,
            if (hasFeed) View.GONE else View.VISIBLE,
        )

        // `empty` is a real state and not a failure: a signed-in customer with an
        // empty catalog, or a refresh whose queries failed. The layout already says
        // so, and there are no products to draw over the top of it.
        if (!hasFeed) return

        views.setTextViewText(
            R.id.customer_group_label,
            groupLabel(context, widgetData.getString(KEY_CUSTOMER_GROUP, "") ?: ""),
        )

        // Only the size shelf carries a size, and the payload writes it blank on
        // the other two — so the view is hidden rather than left holding a stray
        // label from the last group the tile showed.
        val size = widgetData.getString(KEY_CUSTOMER_SIZE, "") ?: ""
        views.setViewVisibility(
            R.id.customer_size_label,
            if (size.isBlank()) View.GONE else View.VISIBLE,
        )
        if (size.isNotBlank()) views.setTextViewText(R.id.customer_size_label, size)

        views.setTextViewText(
            R.id.customer_updated,
            context.getString(
                R.string.customer_widget_updated,
                widgetData.getString(KEY_CUSTOMER_UPDATED, "") ?: "",
            ),
        )

        // Every size shows the one card. There is no smaller count to fall back to
        // at 2×2: the card is a photograph, a name and a price, and hiding the price
        // to fit a shape would hide the number the card exists for — the seller's
        // tiers hide *metrics*, which are peers, where this card's parts are not.
        // Hence no `maxSlots` and no `enabled` flag: the loop is here because the
        // provider is written against [CUSTOMER_SLOTS] rather than a hardcoded 1,
        // and it would fill a second card unchanged if the count ever moved.
        for (slot in 1..CUSTOMER_SLOTS) {
            renderCustomerSlot(context, widgetData, views, slot)
        }
    }

    /**
     * Draw one product slot — or hide it.
     *
     * **A slot is empty when its id is blank**: every key is written on every
     * update, so absence is a value and not a missing entry, and this is the same
     * check the eraser and the picker agree on. With one slot the empty case is the
     * "nothing to show" card — hidden rather than drawn with a placeholder, because
     * a card with a made-up name and `₱0` states something untrue about the catalog.
     *
     * Hidden, note, rather than re-shown as the empty state: [renderCustomer] has
     * already decided which of the two the tile is (the payload's `customer_state`),
     * and a product row appearing under the empty-state copy is the kind of
     * contradiction a screenshot would have to catch.
     */
    private fun renderCustomerSlot(
        context: Context,
        widgetData: SharedPreferences,
        views: RemoteViews,
        slot: Int,
    ) {
        val rowId = CUSTOMER_ROW_IDS[slot - 1]
        val id = widgetData.getString(customerKey(slot, "id"), "") ?: ""

        if (id.isEmpty()) {
            views.setViewVisibility(rowId, View.GONE)
            return
        }

        val name = widgetData.getString(customerKey(slot, "name"), "") ?: ""
        val price = widgetData.getString(customerKey(slot, "price"), "") ?: ""
        val badge = widgetData.getString(customerKey(slot, "badge"), "") ?: ""

        views.setViewVisibility(rowId, View.VISIBLE)
        views.setTextViewText(CUSTOMER_NAME_IDS[slot - 1], name)
        views.setTextViewText(CUSTOMER_PRICE_IDS[slot - 1], price)

        val badgeId = CUSTOMER_BADGE_IDS[slot - 1]
        views.setViewVisibility(badgeId, if (badge.isBlank()) View.GONE else View.VISIBLE)
        if (badge.isNotBlank()) views.setTextViewText(badgeId, badge)

        // One spoken line per row rather than a description on the whole tile: a
        // row IS a button here, and TalkBack should read the product it would open
        // ("Air Max 90, ₱2,499") instead of walking the tile or announcing a name it
        // cannot act on.
        views.setContentDescription(
            rowId,
            if (badge.isBlank()) "$name, $price" else "$name, $price, $badge",
        )

        val imageId = CUSTOMER_IMAGE_IDS[slot - 1]
        val bitmap = decodeThumbnail(
            widgetData.getString(customerKey(slot, "image"), "") ?: "",
        )
        if (bitmap == null) {
            // No photograph, or one that failed to download. The view is HIDDEN
            // rather than left holding the placeholder tint: an empty square reads
            // as a broken image, where a row that is only text reads as a product
            // without a picture — which is what it is.
            views.setViewVisibility(imageId, View.GONE)
        } else {
            views.setViewVisibility(imageId, View.VISIBLE)
            views.setImageViewBitmap(imageId, bitmap)
        }

        val openProduct = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse(PRODUCT_DEEP_LINK_PREFIX + id),
        )
        views.setOnClickPendingIntent(rowId, openProduct)

        // **The whole tile opens the card's product, not just the card.** With ONE
        // product on the tile the header and the footer have nothing else to do, and
        // a tap that lands 4dp above the card doing nothing is the kind of thing a
        // person reads as "the widget is not tappable". The seller's tiles keep the
        // root tap for their own screen; a customer's tile makes it the product —
        // the same one the card would open, so there is no ambiguity about which.
        views.setOnClickPendingIntent(R.id.widget_root, openProduct)
    }

    /**
     * The heading for a group's wire value.
     *
     * An unrecognised value gets a neutral heading rather than the first group's
     * name: the payload outlives app versions (the launcher keeps drawing what was
     * last written), so a value from a newer or older build is a real case, and
     * labelling those products "New arrivals" when the Dart side called them
     * something else would be a tile stating something untrue about a real shelf.
     */
    private fun groupLabel(context: Context, wire: String): String = when (wire) {
        GROUP_NEW -> context.getString(R.string.customer_widget_group_new)
        GROUP_SUGGESTED -> context.getString(R.string.customer_widget_group_suggested)
        GROUP_SALE -> context.getString(R.string.customer_widget_group_sale)
        else -> context.getString(R.string.customer_widget_group_other)
    }

    /**
     * Decode a cached thumbnail, downsampled to what the tile can draw.
     *
     * ⚠️ Decoded HERE, in the app's own process, and handed to the launcher as a
     * Bitmap — never as a path or a URL for the launcher to resolve. The provider
     * runs as a receiver of this app, so a local file is readable here and nowhere
     * else; a `content://` URI would need a FileProvider grant to the launcher,
     * which is a permission surface this design has no reason to open.
     *
     * The two `BitmapFactory` calls are deliberate: the first reads only the file's
     * header, so [sampleSizeFor] can size the decode before a full-size bitmap is
     * ever allocated. Decoding first and scaling after is how a widget update runs
     * out of memory on a photograph nobody was going to see at that resolution.
     *
     * Returns null for every failure — no file, an unreadable file, a decode error
     * — so a missing photograph costs the row its picture rather than the tile its
     * update.
     */
    private fun decodeThumbnail(path: String): Bitmap? {
        if (path.isBlank()) return null
        return try {
            if (!File(path).exists()) return null

            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            val options = BitmapFactory.Options().apply {
                inSampleSize = sampleSizeFor(bounds.outWidth, bounds.outHeight)
                // RGB_565 halves the bytes per pixel. These are photographs drawn at
                // 44–90dp on a tinted card, where the banding a 565 decode can
                // introduce is not visible — and the Binder cost is real (see
                // [THUMBNAIL_MAX_PX]).
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            BitmapFactory.decodeFile(path, options)
        } catch (e: Exception) {
            android.util.Log.d("SellerWidget", "thumbnail decode failed: ${e.message}")
            null
        }
    }

    /**
     * The power-of-two downsample that brings [width]×[height] inside
     * [THUMBNAIL_MAX_PX].
     *
     * Stops as soon as BOTH edges fit, so the decoded bitmap can overshoot the
     * ceiling by at most nothing — the loop tests the size it would get, not the
     * size it has. Powers of two only: `inSampleSize` is documented to round down
     * to one anyway, so computing anything else would be arithmetic the decoder
     * then discards.
     */
    private fun sampleSizeFor(width: Int, height: Int): Int {
        var sample = 1
        while (width / sample > THUMBNAIL_MAX_PX || height / sample > THUMBNAIL_MAX_PX) {
            sample *= 2
        }
        return sample
    }

    /** One sentence for the 2×2, which shows two figures and no timestamp. */
    private fun speak(
        context: Context,
        storeName: String,
        revenue: String,
        summaryLine: String,
    ): String {
        val spoken = context.getString(
            R.string.seller_widget_a11y_summary_small,
            revenue,
            summaryLine,
        )
        return if (storeName.isBlank()) spoken else "$storeName. $spoken"
    }

    /**
     * Writes a count and tints it by whether there is anything to do.
     *
     * The colour is resolved **per update, through the context the system hands
     * `onUpdate`, and never cached in a field.** Two reasons, and the first is a
     * correctness one: an `AppWidgetProvider` is instantiated by the framework
     * per broadcast, so a field holding a resolved colour would be whichever
     * theme was active when *that* instance was built. The second is dark mode —
     * `getColor` resolves against the provider's current configuration, so a
     * phone switched to dark repaints with the `-night` palette on its next
     * update with no extra work here.
     *
     * `context.getColor` rather than `ContextCompat`: minSdk is 24 and
     * `Resources.getColor(int)` has existed since API 23, so a support-library
     * call here would add a dependency for nothing.
     */
    private fun setCount(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        value: Int,
        @ColorRes activeColor: Int,
    ) {
        views.setTextViewText(viewId, value.toString())
        val colorRes = if (value > 0) activeColor else R.color.seller_widget_muted
        // `setTextColor` is on the RemoteViews allowlist; an alpha or a tint
        // would not be, and would also wash the value out of the contrast ratio
        // its colour was chosen to clear.
        views.setTextColor(viewId, context.getColor(colorRes))
    }

    /**
     * The payload store, read the same way [HomeWidgetProvider] reads it.
     *
     * Needed because `onAppWidgetOptionsChanged` is NOT wrapped by
     * `HomeWidgetProvider`, so unlike [onUpdate] it has no `widgetData`
     * parameter to use. Calling the plugin's own public accessor keeps ONE
     * definition of where the payload lives, rather than opening the
     * preferences file by name here and having two places to keep in step —
     * which is exactly how a resize would come to draw from an empty store.
     */
    private fun payloadStore(context: Context): SharedPreferences =
        HomeWidgetPlugin.getData(context)

    /**
     * One tap target for the whole tile.
     *
     * The whole card, not each cell: RemoteViews can attach a different
     * `PendingIntent` per id, but six tap targets inside one tile are six
     * mis-taps. The seller lands on the dashboard, where every one of these
     * counters already has a row with a real touch target.
     */
    private fun applyTap(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse(SELLER_DEEP_LINK),
            ),
        )
    }
}
