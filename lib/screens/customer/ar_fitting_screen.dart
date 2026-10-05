import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/product_provider.dart';
import '../../providers/cart_provider.dart';
import '../../utils/cart_helpers.dart';
import '../../utils/size_key.dart';
import '../../widgets/ar_view_placeholder.dart';
import '../../widgets/cart_icon_button.dart';
import '../../widgets/seller/fly_to_order_animation.dart';
import 'ar_try_on_spike_screen.dart';
import '../../providers/try_on/try_on_mode.dart';
import '../../providers/try_on/try_on_phase.dart';
import '../../providers/try_on/try_on_session_controller.dart';
import '../../services/ar_try_on_channel.dart';
import '../../utils/try_on_coach.dart';
import '../../utils/try_on_fit.dart';
import '../../widgets/try_on/try_on_coach_card.dart';
import '../../widgets/try_on/try_on_fit_card.dart';
import '../../widgets/try_on/try_on_saved_size_card.dart';
import '../../services/try_on_placeholder_model.dart';

class ARVirtualFitScreen extends StatefulWidget {
  final Map<String, dynamic>? preselectedProduct;

  /// **The capability gate's availability half (roadmap V3.9), threaded now.**
  ///
  /// `true` means a verified model is already cached for this product, so the
  /// only thing still between this screen and a real render is AR support —
  /// which is discovered when a session tries to start, by
  /// `TryOnSessionController`.
  ///
  /// **Nothing renders it yet, and that is deliberate.** Swapping the placeholder
  /// for the platform view is V3.5, and it will be written against the renderer
  /// route V0.7 has not settled. This parameter exists ahead of it because
  /// architecture §2.3's whole point is that the *call sites stop changing*: the
  /// entry that can answer this question (product detail, from the V2.6
  /// prefetch) hands over the same answer today, so V3.5 edits one file instead
  /// of chasing five. Every other entry — the home card, the store and
  /// collection rows — leaves it `false` and keeps the simulated feed, which is
  /// D8's fallback rule rather than a gap.
  final bool modelAvailable;

  /// **The V3 switch (V3.5), read by the caller and passed in** — the same shape as
  /// `TryOnPrefetch(enabled:)` and `TryOnSessionController(enabled:)`, so a test can
  /// drive both configurations in one run and this screen never picks a default of
  /// its own.
  ///
  /// With it **false** the platform view is never built, the controller is never
  /// constructed and no channel call is made: V0's F19 ruling is that the flag gates
  /// *side effects*, not just what is painted.
  final bool tryOnEnabled;

  /// Test seam: a session controller to drive instead of building one.
  final TryOnSessionController? tryOnSessionController;

  /// Test seam: the widget that stands in for the platform view.
  ///
  /// `AndroidView` cannot be mounted under `flutter test` (there is no platform-view
  /// registry), so the real view is reached through a seam rather than built inline —
  /// the same harness boundary the V2.6 page tests had to document.
  final Widget Function()? tryOnViewBuilder;

  const ARVirtualFitScreen({
    super.key,
    this.preselectedProduct,
    this.modelAvailable = false,
    this.tryOnEnabled = AppConstants.tryOnV3Enabled,
    this.tryOnSessionController,
    this.tryOnViewBuilder,
  });

  @override
  State<ARVirtualFitScreen> createState() => _ARVirtualFitScreenState();
}

class _ARVirtualFitScreenState extends State<ARVirtualFitScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late Map<String, dynamic> _activeProduct;
  late String _activeSize;
  late String _activeColor;
  
  late ValueNotifier<bool> _isTracking;
  bool _showTutorial = true;
  bool _isAddingToCart = false;

  /// The V3 session. Present only when the switch is on **and** the entry says a
  /// model is cached — never constructed otherwise, which is what makes F19 hold.
  TryOnSessionController? _tryOn;

  /// True while the platform view occupies the camera-feed slot.
  ///
  /// It starts true when a session is possible and flips **off** the moment the
  /// controller reports a degradation, so a refused ARCore start lands on the
  /// simulated feed (D8) instead of a black rectangle the customer cannot explain.
  bool _tryOnShowingView = false;

  /// **V4.9: whether the platform view this screen asked for actually exists.**
  ///
  /// `startAr` may never be told `arViewReady: true` before the view is there
  /// (F17: the native side parks such a call and answers `timeout` after 15 s),
  /// and the framework creating the view is the only proof of it. The model
  /// handover can finish *after* that proof arrives — the ordering a phone
  /// actually produces — which is what makes this a field rather than the
  /// one-shot call it used to be.
  bool _tryOnViewCreated = false;

  /// Whether this screen built [_tryOn] and must therefore dispose it.
  bool _ownsTryOn = false;

  /// **V4.8's rotation lock.** While this screen is open the app is pinned to
  /// portrait: the AR surface, the camera projection and the coaching column are
  /// all laid out for it, and a mid-session rotation moves the renderer — the
  /// one path nobody has run on a device. Taken in [initState], restored in
  /// [dispose], so no other route inherits it.
  static const List<DeviceOrientation> _tryOnOrientations =
      <DeviceOrientation>[DeviceOrientation.portraitUp];

  /// **V4.8: the simulated feed's timers, cancellable.** The 20-open/close rule
  /// holds this screen to leaving nothing armed when it unmounts, and a
  /// `Future.delayed` cannot be cancelled out of one.
  Timer? _simulatedLockTimer;
  Timer? _relockTimer;

  // GlobalKeys for the fly-to-cart overlay animation (Add to Cart → cart icon)
  final GlobalKey _addToCartButtonKey = GlobalKey();
  final GlobalKey _cartIconKey = GlobalKey();

  /// **V4.9: the night-aid torch.** The camera feed's own brightness is capped by
  /// the sensor in a dark room (ARCore's auto-exposure is already maxed), so the
    /// only honest brightener is more light: this drives the phone's flash through
    /// the session (`ArTryOnView.setTorch`), and the chip lights up while it is on.
  bool _torchOn = false;
  
  late AnimationController _pulseController;
  late AnimationController _particleController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(_tryOnOrientations);
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    
    // Fallback if no preselected product
    if (widget.preselectedProduct != null) {
      _activeProduct = widget.preselectedProduct!;
    } else {
      _activeProduct = productProvider.products.isNotEmpty
          ? productProvider.products.first
          : {
              'id': 1,
              'name': 'Carcar Classic Oxford',
              'price': 2499.00,
              'images': ['https://images.unsplash.com/photo-1533867617858-e7b97e060509?q=80&w=600&auto=format&fit=crop'],
              'sizes': {'38': 5, '39': 8, '40': 12, '41': 6, '42': 0},
            };
    }

    // Initialize selections
    _activeColor = 'Burnished Clay';
    final sizesMap = Map<String, dynamic>.from(_activeProduct['sizes'] ?? {});
    _activeSize = sizesMap.keys.firstWhere((s) => sizesMap[s] > 0, orElse: () => '39');

    _isTracking = ValueNotifier<bool>(false);

    // ── V3.5: the real renderer, when the gate says there is something to render ──
    // The order here is F17 and it is load-bearing. The platform view is mounted by
    // `build` and `startAr` is called *from* its `onPlatformViewCreated`, so the
    // session is only ever requested once the view provably exists. The model
    // handover goes the other way — it happens now, before the view can exist,
    // because the native plugin parks it (F18), which is exactly the bug the V0
    // plugin shipped.
    if (widget.tryOnSessionController != null) {
      _tryOn = widget.tryOnSessionController;
    } else if (_tryOnWanted) {
      _ownsTryOn = true;
      _tryOn = TryOnSessionController(
        productId: _activeProduct['id'].toString(),
        // The product-level default. A per-colour override would have to resolve a
        // variant out of this map's `sizes` shape, and the app's variants are colour
        // *and* size (V2.2's D-2 deferral), so a colour-scoped model would render on
        // one size only.
        enabled: true,
        // V4.1's QA/development seam. Off in every customer build; on a build
        // that passes it, the loop still needs a live session (and so, in
        // practice, `TRY_ON_V3=true`) before it spends a frame.
        footTrackEnabled: AppConstants.tryOnFootTrackEnabled,
        // V4.9's readout switch. Passed rather than read inside the controller
        // for the same reason the two switches above are: a
        // `bool.fromEnvironment` cannot be flipped under `flutter test`.
        diagnostics: AppConstants.shoePreviewDiagnosticsEnabled,
        models: AppConstants.tryOnPlaceholderModelEnabled
            ? placeholderModelService()
            : null,
      );
    }
    // Derived, not assumed: an injected controller may have degraded *before* this
    // screen existed (a retry after a refusal), in which case the simulated feed
    // is what should paint on the very first frame.
    final controller = _tryOn;
    _tryOnShowingView = _tryOnWanted &&
        (controller == null ||
            controller.degradeReason == TryOnDegradeReason.none);
    if (_tryOn != null) {
      _tryOn!.addListener(_onTryOnChanged);
      _tryOn!.prepareModel();
    }

    // Simulated tracking lock on after 2.5 seconds, in a timer this screen can
    // cancel: V4.8's 20-open/close rule is exactly about what a `Future.delayed`
    // leaves behind when the screen closes first.
    _simulatedLockTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _isTracking.value = true;
      }
    });

    // Pulse animation for tracking dot
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    // Particle/edge overlay animation
    _particleController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // V4.8: the rotation lock lives and dies with this route.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _simulatedLockTimer?.cancel();
    _relockTimer?.cancel();
    _pulseController.dispose();
    _particleController.dispose();
    // D1: the platform view owns native teardown; disposing the controller cancels
    // its subscriptions and stops listening, and makes no `stopSession` call.
    // V4.8: the listener comes off first either way — an *injected* controller is
    // not disposed here (its owner still holds it), so it must not keep a dead
    // state listening across the 20 open/close cycles this screen has to survive.
    _tryOn?.removeListener(_onTryOnChanged);
    if (_ownsTryOn) _tryOn?.dispose();
    _isTracking.dispose();
    super.dispose();
  }

  /// **V4.8: backgrounding pauses the frame spending, and only a real resume
  /// undoes it.** The screen owns this because the screen is what sees the app's
  /// lifecycle; the controller owns what a pause means for the loop (a failure
  /// stop and a degraded session stay stopped). The native half — ARCore paused
  /// and resumed with the platform view's own surface — belongs to the view and
  /// needs no call from here.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _tryOn?.setAppForeground(foreground: state == AppLifecycleState.resumed);
  }

  /// True only when the switch is on **and** the entry says a model is cached.
  ///
  /// The availability half arrives from the caller (product detail, from the V2.6
  /// prefetch). This screen never guesses it, because answering costs a table read
  /// that the page a customer came from has already paid for.
  bool get _tryOnWanted => widget.tryOnEnabled && widget.modelAvailable;

  /// Rebuilds on the session's own events, and **falls back rather than sticking**.
  void _onTryOnChanged() {
    final controller = _tryOn;
    if (controller == null || !mounted) return;

    final degraded = controller.degradeReason != TryOnDegradeReason.none;
    // Derived rather than toggled. The first version of this flipped the flag
    // whenever `degraded` matched the current value, which turned the view *on* for
    // an entry that had no model and therefore no session to show — caught by
    // `test/widgets/ar_fitting_try_on_swap_test.dart`. The gate is still ANDed in
    // here, so a product without a model can never be shown a session.
    final desired = _tryOnWanted && !degraded;
    if (desired != _tryOnShowingView) {
      setState(() => _tryOnShowingView = desired);
    }
    if (_tryOnShowingView && controller.phase == TryOnPhase.searching) {
      // Real ARCore tracking replaces the simulated 2.5 s lock-on.
      _isTracking.value = true;
    }
    _startArIfReady();
  }

  /// **V4.9: the second chance `startAr` needs, and why the camera went black
  /// without it.**
  ///
  /// This screen's other call site is the platform view's creation, and
  /// `startAr` returns at its `modelReady` gate when the handover has not
  /// finished yet — which on a device is the *usual* ordering: the view is
  /// created a frame or two after this screen builds, while the model still has
  /// to be resolved, downloaded, verified and handed over. A dropped start used
  /// to be both silent and final: QA held exactly that screen for 48 minutes on
  /// 2026-10-05 — no session, no camera, 173,660 frames of black — because
  /// nothing ever called `startAr` a second time.
  ///
  /// So the phase reaching `modelReady` calls back in through the controller's
  /// own [`TryOnSessionController.needsArStart`] seam, and the guard against
  /// starting twice is the controller's (`startAr` is idempotent, and
  /// `needsArStart` is false the moment AR is asked to start).
  void _startArIfReady() {
    final controller = _tryOn;
    if (controller == null || !mounted) return;
    if (!_tryOnShowingView || !controller.needsArStart) return;
    // The view half of the precondition, and it is not a formality: `startAr`
    // with `arViewReady: false` degrades the session instead of starting it, so a
    // retry that guessed here would turn a race into the fallback screen. Under
    // `tryOnViewBuilder` (tests only) the injected widget *is* the view, and
    // `onPlatformViewCreated` never fires for it.
    if (!_tryOnViewCreated && widget.tryOnViewBuilder == null) return;
    unawaited(controller.startAr(arViewReady: true));
  }

  /// The real renderer, or null so [ARViewPlaceholder] keeps its simulated feed.
  Widget? _tryOnArView() {
    if (!_tryOnShowingView) return null;
    final injected = widget.tryOnViewBuilder;
    if (injected != null) return injected();
    // Android only: there is no native plugin on iOS, and an `AndroidView` there
    // throws instead of degrading.
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    return AndroidView(
      viewType: kArTryOnViewType,
      // The platform view must be able to receive taps: that is how the shoe gets
      // placed (V3.4), and a tap only reaches native if Flutter hands the gesture
      // arena over.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onPlatformViewCreated: (_) {
        _tryOnViewCreated = true;
        _startArIfReady();
      },
    );
  }

  void _switchProduct(Map<String, dynamic> product) {
    setState(() {
      _activeProduct = product;
      final sizesMap = Map<String, dynamic>.from(product['sizes'] ?? {});
      _activeSize = sizesMap.keys.firstWhere((s) => sizesMap[s] > 0, orElse: () => '39');
      
      // Simulate tracking relocking on shoe change — re-armed, so the previous
      // shoe's timer is cancelled first rather than firing under the new one.
      _isTracking.value = false;
      _relockTimer?.cancel();
      _relockTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) {
          _isTracking.value = true;
        }
      });
    });
  }

  void _checkSizeAvailability() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (context) {
        final sizesMap = Map<String, dynamic>.from(_activeProduct['sizes'] ?? {});
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock Level: ${_activeProduct['name']}',
                style: AppConstants.headlineStyle(fontSize: 18, color: AppConstants.inkInverse),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: sizesMap.entries.map((entry) {
                  final size = entry.key;
                  final qty = entry.value as int;
                  final inStock = qty > 0;
                  return Column(
                    children: [
                      Text(
                        formatSize(size),
                        style: AppConstants.monoStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.inkInverse,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: inStock ? AppConstants.success.withValues(alpha: 0.2) : AppConstants.error.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          inStock ? '$qty left' : 'OUT',
                          style: AppConstants.bodyStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: inStock ? AppConstants.success : AppConstants.error,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _addToCart() {
    // Guard against rapid taps stacking multiple overlay flights (mirrors
    // product detail screen's _isAddingToCart pattern).
    if (_isAddingToCart) return;
    setState(() => _isAddingToCart = true);

    final cart = Provider.of<CartProvider>(context, listen: false);
    final double price = (_activeProduct['price'] is int)
        ? (_activeProduct['price'] as int).toDouble()
        : (_activeProduct['price'] ?? 0.0);
    final List<dynamic> images = _activeProduct['images'] ?? [];

    // Look up variant_id for the selected size (mirrors product_detail_screen)
    final variants = _activeProduct['product_variants'] as List<dynamic>? ?? [];
    final (:variantId, :additionalPrice) = resolveVariant(
      variants: variants,
      size: _activeSize,
      color: _activeColor,
    );

    final String imageUrl = images.isNotEmpty ? images.first : '';

    cart.addToCart(
      productId: _activeProduct['id'].toString(),
      productName: _activeProduct['name'],
      imageUrl: imageUrl,
      price: price,
      size: _activeSize,
      color: _activeColor,
      variantId: variantId,
      additionalPrice: additionalPrice,
    );

    // Pack-the-box fly-to-cart overlay animation (same as the POS): the box
    // GIF draws in around the product, then the solid box flies up to the
    // cart icon and lands with a ring flash.
    FlyToOrderAnimation.show(
      context: context,
      sourceKey: _addToCartButtonKey,
      targetKey: _cartIconKey,
      imageUrl: imageUrl,
    );

    // Re-enable the button after the box-pack animation finishes (~1800 ms)
    // so rapid taps can't stack overlapping flights.
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _isAddingToCart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final otherProducts = productProvider.products;
    final coach = _tryOn;
    final sizesMap = Map<String, dynamic>.from(_activeProduct['sizes'] ?? {});

    return Scaffold(
      backgroundColor: AppConstants.surfaceDark,
      body: Stack(
        children: [
          // Immersive Camera Feed View
          SizedBox.expand(
            child: ARViewPlaceholder(arView: _tryOnArView()),
          ),

          // Animated particle scatter effect at borders
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _particleController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _ARParticlePainter(
                      progress: _particleController.value,
                    ),
                  );
                },
              ),
            ),
          ),

          // Top overlay: Glassmorphism back/title panel
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white24,
                          child: Icon(Icons.close, color: AppConstants.inkInverse, size: 18),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _activeProduct['name'] ?? 'Carcar Footwear',
                              style: AppConstants.bodyStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.inkInverse,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Active Color: $_activeColor',
                              style: AppConstants.bodyStyle(
                                fontSize: 12,
                                color: AppConstants.surfaceLight.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // V4.9: the night-aid torch — the one fix that actually adds
                      // light at night (exposure gain multiplies noise; the flash
                      // multiplies signal). Shown only while the real AR view is on
                      // screen: the simulated feed has no camera to flash.
                      if (_tryOnShowingView)
                        GestureDetector(
                          onTap: () {
                            setState(() => _torchOn = !_torchOn);
                            _tryOn?.setTorch(_torchOn);
                          },
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                _torchOn ? AppConstants.accent : Colors.white24,
                            child: Icon(
                              _torchOn ? Icons.flash_on : Icons.flash_off,
                              color: AppConstants.inkInverse,
                              size: 18,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      // Cart shortcut — fly-to-cart target for the add-to-cart animation
                      CartIconButton(
                        iconKey: _cartIconKey,
                        iconColor: AppConstants.surfaceLight,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // V4.9: the native renderer's heartbeat, when the build asked for it
          // — one dim line under the top panel, so a phone with no adb still
          // leaves the session's own numbers (`foot=`, `len=`, `scale=`,
          // `mask=`, `thermal=`) in a screenshot. Nothing is drawn until the
          // first `status` event arrives, and in a customer build the native
          // side is never even asked, so this stays empty.
          if (coach != null)
            Positioned(
              top: 130,
              left: 20,
              right: 20,
              child: ValueListenableBuilder<String?>(
                valueListenable: coach.nativeStatusLine,
                builder: (context, line, _) => line == null
                    ? const SizedBox.shrink()
                    : _TryOnStatusLine(text: line),
              ),
            ),

          // V4.5/V4.6/V4.7: the coaching column — the saved-size suggestion
          // above the live fit verdict above the coach card, over the camera.
          // Gated twice on purpose: the real view has to be the one on screen
          // (`_tryOnShowingView`), and the build has to have asked for foot
          // tracking at all (`footTrackEnabled`, the V4.1 switch — separate from
          // V3's, because "may render a shoe" and "may coach a foot" are
          // different permissions). Every widget collapses to nothing on its
          // own, so a session that is not tracking draws no empty panel, and
          // the column keeps the three from ever overlapping as they grow
          // upward from the bottom panel.
          if (coach != null &&
              _tryOnShowingView &&
              coach.footTrackEnabled)
            Positioned(
              left: 20,
              right: 20,
              bottom: 246,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // V4.7: the saved-profile comparison, first in the column and
                  // therefore the only card that moves when it appears or
                  // disappears — the verdict and the coach card keep their
                  // positions above the bottom panel.
                  ValueListenableBuilder<TryOnLiveFoot>(
                    valueListenable: coach.liveFoot,
                    builder: (context, live, _) =>
                        TryOnSavedSizeCard(live: live),
                  ),
                  // V4.6: the fit verdict, graded live from the tracker's own
                  // measurement (`coach.liveFoot`) — never from the saved scan,
                  // which is a different day's reading (V4.7 compares the two).
                  ValueListenableBuilder<TryOnLiveFoot>(
                    valueListenable: coach.liveFoot,
                    builder: (context, live, _) => TryOnFitCard(
                      product: _activeProduct,
                      selectedSize: _activeSize,
                      live: live,
                    ),
                  ),
                  ValueListenableBuilder<TryOnCoachCue?>(
                    valueListenable: coach.coachCue,
                    builder: (context, cue, _) => TryOnCoachCard(
                      cue: cue,
                      onPlaceManually: coach.dismissManualOffer,
                    ),
                  ),
                ],
              ),
            ),

          // Bottom overlay: Glassmorphism menu box (~210px tall)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status Tracking Indicator + Size Checker Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Pulse dot and status
                          ValueListenableBuilder<bool>(
                            valueListenable: _isTracking,
                            builder: (context, tracking, child) {
                              final statusText = tracking ? 'Fit looks good!' : 'Tracking your feet...';
                              return Row(
                                children: [
                                  // Pulsing Dot
                                  AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      return Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: tracking ? AppConstants.success : AppConstants.accent,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: (tracking ? AppConstants.success : AppConstants.accent)
                                                  .withValues(alpha: 0.6 * _pulseController.value),
                                              blurRadius: 6,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    statusText,
                                    style: AppConstants.bodyStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: tracking ? AppConstants.success : AppConstants.accent,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          // Size availability button
                          GestureDetector(
                            onTap: _checkSizeAvailability,
                            child: Row(
                              children: [
                                Text(
                                  'Availability',
                                  style: AppConstants.bodyStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppConstants.surfaceLight.withValues(alpha: 0.8),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_up,
                                  color: AppConstants.surfaceLight.withValues(alpha: 0.8),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Horizontal shoe variants/colors list
                      SizedBox(
                        height: 52,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: otherProducts.length,
                          itemBuilder: (context, index) {
                            final prod = otherProducts[index];
                            final isCurrent = prod['id'] == _activeProduct['id'];
                            final String img = (prod['images'] as List).isNotEmpty ? prod['images'][0] : '';
                            
                            return GestureDetector(
                              onTap: () => _switchProduct(prod),
                              child: Container(
                                width: 52,
                                height: 52,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isCurrent ? AppConstants.accent : Colors.white24,
                                    width: isCurrent ? 2 : 1,
                                  ),
                                  image: DecorationImage(
                                    image: NetworkImage(img),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Size Selector row (compact chips)
                      SizedBox(
                        height: 32,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: sizesMap.entries.map((entry) {
                            final size = entry.key;
                            final isAvailable = (entry.value as int) > 0;
                            final isSelected = _activeSize == size;

                            return GestureDetector(
                              onTap: isAvailable
                                  ? () {
                                      setState(() {
                                        _activeSize = size;
                                      });
                                    }
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppConstants.accent
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppConstants.accent
                                        : Colors.white24,
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    formatSize(size),
                                    style: AppConstants.monoStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppConstants.secondary
                                          : (isAvailable ? AppConstants.surfaceLight : Colors.white30),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Dev-only: V0 renderer spike entry point ──
                      // Opens the native SceneView spike that renders a real
                      // glTF shoe in AR. Never enabled in a shipped build:
                      // `arTryOnSpikeEnabled` is false unless the build passes
                      // --dart-define=AR_TRY_ON_SPIKE=true. See
                      // docs/RoadMap/VIRTUAL_FITTING_ROADMAP.md (V0) — delete
                      // this block with the spike.
                      if (AppConstants.arTryOnSpikeEnabled) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 38,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ArTryOnSpikeScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.science_outlined, size: 16),
                            label: const Text('SPIKE: real AR renderer'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppConstants.accent,
                              side: BorderSide(
                                color: AppConstants.accent
                                    .withValues(alpha: 0.6),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppConstants.buttonRadius,
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Add to Cart
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: FilledButton(
                          key: _addToCartButtonKey,
                          onPressed: _isAddingToCart ? null : _addToCart,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppConstants.accent,
                            foregroundColor: AppConstants.secondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppConstants.buttonRadius,
                            ),
                          ),
                          child: Text(
                            'Add to Cart (₱${_activeProduct['price']})',
                            style: AppConstants.bodyStyle(
                              fontWeight: FontWeight.bold,
                              color: AppConstants.secondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // First-time "How to use" guide overlay
          if (_showTutorial)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showTutorial = false;
                  });
                },
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Virtual Fit Guide',
                        style: AppConstants.headlineStyle(fontSize: 24, color: AppConstants.inkInverse),
                      ),
                      const SizedBox(height: 24),
                      _buildTutorialStep(
                        icon: Icons.camera_alt_outlined,
                        title: '1. Point at your feet',
                        desc: 'Hold camera ~3 feet away from your feet with good ambient lighting.',
                      ),
                      const SizedBox(height: 20),
                      _buildTutorialStep(
                        icon: Icons.checkroom_outlined,
                        title: '2. Select a shoe',
                        desc: 'Tap the circular thumbnails below to swap shoe models in real time.',
                      ),
                      const SizedBox(height: 20),
                      _buildTutorialStep(
                        icon: Icons.remove_red_eye_outlined,
                        title: '3. See how it fits',
                        desc: 'Adjust your size and look at the foot alignment on screen.',
                      ),
                      const SizedBox(height: 48),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _showTutorial = false;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppConstants.inkInverse),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: Text(
                          'Got It',
                          style: AppConstants.bodyStyle(color: AppConstants.inkInverse, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTutorialStep({required IconData icon, required String title, required String desc}) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: AppConstants.primary.withValues(alpha: 0.2),
          child: Icon(icon, color: AppConstants.accent),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppConstants.bodyStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppConstants.inkInverse),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: AppConstants.bodyStyle(fontSize: 12, color: AppConstants.surfaceLight.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// **V4.9: the renderer's own heartbeat, as one dim line over the camera.**
///
/// The try-on session's evidence channel for a phone whose developer options
/// are locked: `adb logcat` will never be read from it, so the facts a
/// screenshot can carry — where the foot tracker is, the millimetres and the
/// ×N it produced, the mask's state and the device's thermal word — have to
/// live on the screen. The preview's own readout, restyled for a camera
/// backdrop; never customer copy, and drawn only when the native side sent a
/// line, which it only does in a QA build that turned the readout on.
class _TryOnStatusLine extends StatelessWidget {
  const _TryOnStatusLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppConstants.bodyStyle(
          fontSize: 10,
          color: AppConstants.surfaceLight.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

// Custom painter for ambient scatter edge particles
class _ARParticlePainter extends CustomPainter {
  final double progress;

  _ARParticlePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppConstants.accent.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    // Draw small animated glowing circles near borders
    final double w = size.width;
    final double h = size.height;
    
    // Animate coordinates based on progress
    final double dy1 = 150 + (h * 0.4 * progress);
    final double dy2 = h * 0.7 - (h * 0.3 * progress);
    
    // Left edge
    canvas.drawCircle(Offset(30, dy1), 4, paint);
    canvas.drawCircle(Offset(45, dy2), 6, paint);
    
    // Right edge
    canvas.drawCircle(Offset(w - 30, dy2), 5, paint);
    canvas.drawCircle(Offset(w - 45, dy1), 3, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
