import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_runtime.dart';
import '../core/easy_ad_event.dart';

/// How an [EasyBannerAd] sizes itself.
enum EasyBannerType {
  /// Screen-width banner with a device-appropriate height, meant to be pinned
  /// to the top or bottom of the screen. The default, and what Google
  /// recommends for anchored placements.
  anchoredAdaptive,

  /// Taller, richer banner meant to live inside scrollable content. Its height
  /// is only known after the ad loads.
  inlineAdaptive,

  /// A fixed [AdSize] such as [AdSize.mediumRectangle]. Use when the layout
  /// genuinely requires an exact box.
  fixed,
}

/// Which edge a collapsible banner collapses towards.
enum EasyBannerCollapse {
  /// Not collapsible (default).
  none,

  /// Expanded area extends downwards; use for banners anchored to the top.
  top,

  /// Expanded area extends upwards; use for banners anchored to the bottom.
  bottom,
}

/// A self-managing banner: it loads on mount, reloads when the available width
/// changes (rotation, split screen), disposes itself, and renders nothing at
/// all until an ad is actually on screen.
///
/// It deliberately has no refresh timer. Banner refresh is configured on the ad
/// unit in the AdMob dashboard and handled by the SDK while the banner is
/// visible; refreshing from client code both double-counts requests and can
/// breach the 60-second minimum refresh rule.
class EasyBannerAd extends StatefulWidget {
  /// Creates a banner.
  const EasyBannerAd({
    super.key,
    this.adUnitId,
    this.type = EasyBannerType.anchoredAdaptive,
    this.fixedSize,
    this.collapse = EasyBannerCollapse.none,
    this.inlineMaxHeight,
    this.placeholder,
    this.onLoaded,
  });

  /// Overrides the ad unit from the config — useful when different screens
  /// report to different ad units.
  final String? adUnitId;

  /// How the banner sizes itself.
  final EasyBannerType type;

  /// The size to use when [type] is [EasyBannerType.fixed].
  final AdSize? fixedSize;

  /// Requests a collapsible banner. Honoured at most once per session (see
  /// [EasyAdsConfig.collapsibleBannerOncePerSession]), and only Google demand
  /// fills it — a mediated fill renders as a normal banner.
  final EasyBannerCollapse collapse;

  /// Height ceiling for [EasyBannerType.inlineAdaptive].
  final double? inlineMaxHeight;

  /// Shown while no ad is on screen. Defaults to nothing, so the layout does
  /// not reserve space for an ad that may never fill.
  final Widget? placeholder;

  /// Called once the ad renders, with its final size.
  final void Function(AdSize size)? onLoaded;

  /// Injected by `EasyAds`; not part of the public API.
  static AdRuntime? runtime;

  @override
  State<EasyBannerAd> createState() => _EasyBannerAdState();
}

class _EasyBannerAdState extends State<EasyBannerAd> {
  BannerAd? _ad;
  AdSize? _size;
  bool _loading = false;
  int _attempt = 0;
  int _requestedWidth = 0;
  Timer? _retryTimer;

  AdRuntime? get _runtime => EasyBannerAd.runtime;

  @override
  void dispose() {
    _retryTimer?.cancel();
    _disposeAd();
    super.dispose();
  }

  Future<void> _load(int width) async {
    final runtime = _runtime;
    if (runtime == null || _loading) return;
    if (!runtime.config.enabled || !runtime.config.bannerEnabled) return;

    final unitId = widget.adUnitId ?? runtime.config.adUnitIds.banner;
    if (unitId.isEmpty) return;
    if (!await runtime.ensureInitialized()) return;
    if (!runtime.canRequestAds) return;

    _loading = true;
    _disposeAd();

    try {
      final size = await _resolveSize(width);
      if (size == null || !mounted) {
        _loading = false;
        return;
      }

      runtime.emit(
        EasyAdEvent(
          format: EasyAdFormat.banner,
          type: EasyAdEventType.loadStarted,
          adUnitId: unitId,
        ),
      );

      final ad = BannerAd(
        adUnitId: unitId,
        size: size,
        request: _buildRequest(runtime),
        listener: BannerAdListener(
          onAdLoaded: (ad) async {
            final banner = ad as BannerAd;
            // Only an inline banner needs the platform size: it is requested
            // with height 0 and the real height is known only after loading.
            //
            // For anchored and fixed banners the requested size is the correct
            // reservation. The served creative is often shorter, so adopting
            // the platform size there would visibly shrink the banner right
            // after it appears — which is why Google's anchored sample renders
            // `ad.size` and only the inline sample reads the platform size.
            AdSize? resolvedSize = banner.size;
            if (widget.type == EasyBannerType.inlineAdaptive) {
              resolvedSize = await banner.getPlatformAdSize();
            }
            if (!mounted) {
              await banner.dispose();
              return;
            }
            if (resolvedSize == null) {
              // No trustworthy height: showing a wrongly sized container is
              // worse than showing nothing.
              await banner.dispose();
              _loading = false;
              runtime.emit(
                EasyAdEvent(
                  format: EasyAdFormat.banner,
                  type: EasyAdEventType.loadFailed,
                  adUnitId: unitId,
                  message: 'getPlatformAdSize() returned null',
                ),
              );
              return;
            }
            setState(() {
              _ad = banner;
              _size = resolvedSize;
              _loading = false;
              _attempt = 0;
            });
            widget.onLoaded?.call(resolvedSize);
            runtime.emit(
              EasyAdEvent(
                format: EasyAdFormat.banner,
                type: EasyAdEventType.loaded,
                adUnitId: unitId,
              ),
            );
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            _loading = false;
            runtime.emit(
              EasyAdEvent(
                format: EasyAdFormat.banner,
                type: EasyAdEventType.loadFailed,
                adUnitId: unitId,
                message: error.message,
                errorCode: error.code,
              ),
            );
            _scheduleRetry(width);
          },
          onAdImpression: (_) => runtime.emit(
            EasyAdEvent(
              format: EasyAdFormat.banner,
              type: EasyAdEventType.impression,
              adUnitId: unitId,
            ),
          ),
          onAdClicked: (_) => runtime.emit(
            EasyAdEvent(
              format: EasyAdFormat.banner,
              type: EasyAdEventType.clicked,
              adUnitId: unitId,
            ),
          ),
          onPaidEvent: (_, value, precision, currencyCode) =>
              runtime.reportPaidEvent(
                EasyAdFormat.banner,
                unitId,
                value,
                precision,
                currencyCode,
              ),
        ),
      );

      await ad.load();
    } catch (error, stackTrace) {
      _loading = false;
      runtime.logError(error, stackTrace);
    }
  }

  AdRequest _buildRequest(AdRuntime runtime) {
    if (widget.collapse == EasyBannerCollapse.none) {
      return runtime.buildRequest();
    }
    // A collapsible banner starts expanded over content. Asking for one on
    // every screen of a session is how accidental clicks happen, so the
    // session only grants one slot.
    if (runtime.config.collapsibleBannerOncePerSession) {
      if (runtime.collapsibleConsumed) return runtime.buildRequest();
      runtime.collapsibleConsumed = true;
    }
    return AdRequest(
      keywords: runtime.config.requestKeywords,
      extras: {'collapsible': widget.collapse.name},
    );
  }

  Future<AdSize?> _resolveSize(int width) async {
    switch (widget.type) {
      case EasyBannerType.anchoredAdaptive:
        return AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
      case EasyBannerType.inlineAdaptive:
        final maxHeight = widget.inlineMaxHeight;
        if (maxHeight != null) {
          return AdSize.getInlineAdaptiveBannerAdSize(
            width,
            maxHeight.truncate(),
          );
        }
        return AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(width);
      case EasyBannerType.fixed:
        return widget.fixedSize ?? AdSize.banner;
    }
  }

  void _scheduleRetry(int width) {
    final runtime = _runtime;
    if (runtime == null || !mounted) return;
    if (_attempt >= runtime.config.maxLoadRetries) return;

    final base = runtime.config.retryBaseDelay.inMilliseconds;
    final capped = runtime.config.maxRetryDelay.inMilliseconds;
    final delay = Duration(
      milliseconds: (base << _attempt.clamp(0, 16)).clamp(0, capped),
    );
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (mounted) unawaited(_load(width));
    });
  }

  void _disposeAd() {
    final ad = _ad;
    _ad = null;
    _size = null;
    if (ad == null) return;
    try {
      ad.dispose();
    } catch (error, stackTrace) {
      _runtime?.logError(error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The ad is requested for the width of the *slot*, not of the screen: a
    // banner inside a padded list would otherwise come back wider than the
    // space it has and be clipped on one side. Falls back to the screen width
    // only when the parent imposes no bound at all (a horizontal scroller).
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final width = available.truncate();

        // Rotation, split screen and layout changes make the previous ad the
        // wrong width; an adaptive banner must be re-requested for the new one.
        if (width > 0 && width != _requestedWidth) {
          _requestedWidth = width;
          _attempt = 0;
          // Loading touches state, which a build must never do synchronously.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _requestedWidth == width) unawaited(_load(width));
          });
        }

        final ad = _ad;
        final size = _size;
        if (ad == null || size == null) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        return SizedBox(
          width: size.width.toDouble(),
          height: size.height.toDouble(),
          child: AdWidget(ad: ad),
        );
      },
    );
  }
}
