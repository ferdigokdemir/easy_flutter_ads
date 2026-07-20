import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_runtime.dart';
import '../core/easy_ad_event.dart';

/// Shared machinery for every full screen format: single-flight loading, TTL
/// bookkeeping, timeout, capped exponential backoff, and a show path that can
/// never throw.
///
/// Subclasses only describe what is genuinely format-specific — which SDK load
/// call to make, and how to show the ad.
abstract class FullScreenAdManager<T extends AdWithoutView> {
  /// Creates a manager bound to [runtime].
  FullScreenAdManager(this.runtime);

  /// Shared state and policy gates.
  @protected
  final AdRuntime runtime;

  /// The format this manager handles.
  EasyAdFormat get format;

  /// The ad unit for the current platform, from the live config.
  String get adUnitId;

  /// How long a loaded ad stays usable.
  Duration get ttl;

  T? _ad;
  DateTime? _loadedAt;
  Completer<bool>? _loading;
  bool _retrying = false;

  /// True when a non-expired ad is cached and can be shown instantly.
  bool get isReady {
    final ad = _ad;
    final loadedAt = _loadedAt;
    if (ad == null || loadedAt == null) return false;
    return runtime.now.difference(loadedAt) < ttl;
  }

  /// Issues the SDK load call. Complete with the ad on success, or null on
  /// failure — never throw.
  @protected
  Future<T?> performLoad(String adUnitId, AdRequest request);

  /// Assigns [callback] to the ad. One line per subclass, because the SDK
  /// declares `fullScreenContentCallback` separately on each ad class rather
  /// than on a shared interface.
  @protected
  void assignCallback(T ad, FullScreenContentCallback<T> callback);

  /// Calls the SDK's show method. Declared per format because `show()` lives
  /// on each ad class with a different signature — rewarded formats take a
  /// reward callback.
  @protected
  Future<void> performShow(T ad);

  /// Keeps an ad cached and fresh, retrying no-fills in the background with a
  /// capped exponential backoff.
  ///
  /// Fire and forget — there is no reason to await it. Repeat calls while a
  /// retry loop is already running are ignored, so it is safe to call from
  /// every foreground transition.
  Future<void> preload() async {
    if (!runtime.config.enabled || !runtime.isFormatEnabled(format)) return;
    if (isReady || _retrying || _loading != null) return;
    if (!await runtime.ensureInitialized()) return;

    _retrying = true;
    try {
      for (var attempt = 0; attempt <= runtime.config.maxLoadRetries; attempt++) {
        if (isReady) return;
        if (await load()) return;
        if (attempt < runtime.config.maxLoadRetries) {
          await Future<void>.delayed(_backoffDelay(attempt));
        }
      }
      runtime.emit(
        EasyAdEvent(
          format: format,
          type: EasyAdEventType.loadFailed,
          adUnitId: adUnitId,
          message: 'preload retries exhausted',
        ),
      );
    } finally {
      _retrying = false;
    }
  }

  /// Loads one ad, sharing the in-flight request with concurrent callers.
  ///
  /// Returns true when a fresh ad is cached. A stale (expired) ad is disposed
  /// first: showing one fails at render time, which is both a lost impression
  /// and a confusing user experience.
  Future<bool> load() {
    if (isReady) return Future.value(true);

    final inFlight = _loading;
    if (inFlight != null) return inFlight.future;

    _disposeAd();
    final completer = Completer<bool>();
    _loading = completer;

    unawaited(
      _loadOnce().then((loaded) {
        if (identical(_loading, completer)) _loading = null;
        if (!completer.isCompleted) completer.complete(loaded);
      }),
    );

    return completer.future;
  }

  /// Shows the ad.
  ///
  /// Returns true only when the ad actually rendered and was dismissed.
  ///
  /// With [loadIfMissing] false the call returns immediately when nothing is
  /// cached — use it where a wait would be felt, and let the background
  /// preloader catch up for next time.
  ///
  /// [maxLoadWait] is a *total* budget for getting an ad on screen: SDK
  /// initialization, consent gathering and the load itself all draw from it.
  /// A budget that only covered the load would be a false promise — on a first
  /// run the consent form alone can outlast it.
  ///
  /// When the budget runs out the show is *cancelled*, not deferred: the ad
  /// never appears late, on top of content the user is already using. The load
  /// keeps running, so the ad lands in the cache for the next opportunity
  /// instead of being wasted.
  Future<bool> show({bool loadIfMissing = true, Duration? maxLoadWait}) async {
    try {
      final skipReason = await runtime.evaluateGates(format);
      if (skipReason != null) {
        _emitSkip(skipReason);
        return false;
      }

      final deadline = maxLoadWait == null ? null : runtime.now.add(maxLoadWait);

      final initializing = runtime.ensureInitialized();
      final initBudget = _remaining(deadline);
      final initialized = initBudget == null
          ? await initializing
          : await initializing.timeout(initBudget, onTimeout: () => false);
      if (!initialized) {
        _emitSkip(EasyAdSkipReason.notInitialized);
        return false;
      }

      if (adUnitId.isEmpty) {
        _emitSkip(EasyAdSkipReason.noAdUnitId);
        return false;
      }

      if (!isReady) {
        if (!loadIfMissing) {
          unawaited(preload());
          _emitSkip(EasyAdSkipReason.notReady);
          return false;
        }
        final loadBudget = _remaining(deadline);
        if (loadBudget != null && loadBudget <= Duration.zero) {
          _emitSkip(EasyAdSkipReason.notReady);
          return false;
        }
        final loading = load();
        final loaded = loadBudget == null
            ? await loading
            : await loading.timeout(loadBudget, onTimeout: () => false);
        if (!loaded) {
          _emitSkip(EasyAdSkipReason.notReady);
          return false;
        }
      }

      final ad = _ad;
      if (ad == null) {
        _emitSkip(EasyAdSkipReason.notReady);
        return false;
      }

      return await _showLoadedAd(ad);
    } catch (error, stackTrace) {
      runtime.isShowingFullScreenAd = false;
      runtime.logError(error, stackTrace);
      return false;
    }
  }

  Future<bool> _showLoadedAd(T ad) async {
    final completer = Completer<bool>();
    final unitId = adUnitId;

    assignCallback(
      ad,
      FullScreenContentCallback<T>(
        onAdShowedFullScreenContent: (_) {
          runtime.isShowingFullScreenAd = true;
          unawaited(runtime.noteShown(format));
          runtime.emit(
            EasyAdEvent(
              format: format,
              type: EasyAdEventType.showStarted,
              adUnitId: unitId,
            ),
          );
        },
        onAdImpression: (_) => runtime.emit(
          EasyAdEvent(
            format: format,
            type: EasyAdEventType.impression,
            adUnitId: unitId,
          ),
        ),
        onAdClicked: (_) => runtime.emit(
          EasyAdEvent(
            format: format,
            type: EasyAdEventType.clicked,
            adUnitId: unitId,
          ),
        ),
        onAdDismissedFullScreenContent: (_) {
          _finishShow(unitId);
          runtime.emit(
            EasyAdEvent(
              format: format,
              type: EasyAdEventType.dismissed,
              adUnitId: unitId,
            ),
          );
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToShowFullScreenContent: (_, error) {
          _finishShow(unitId);
          runtime.emit(
            EasyAdEvent(
              format: format,
              type: EasyAdEventType.showFailed,
              adUnitId: unitId,
              message: error.message,
              errorCode: error.code,
            ),
          );
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    try {
      await performShow(ad);
    } catch (error, stackTrace) {
      _finishShow(unitId);
      runtime.logError(error, stackTrace);
      if (!completer.isCompleted) completer.complete(false);
    }

    return completer.future;
  }

  /// Runs on dismiss, show-failure and show-exception alike: clears the
  /// "an ad is on screen" state, records when this ad closed so the App Open
  /// manager can keep its distance, drops the consumed ad and starts loading
  /// the next one.
  void _finishShow(String unitId) {
    runtime.isShowingFullScreenAd = false;
    if (format != EasyAdFormat.appOpen) {
      runtime.lastOtherFullScreenAdClosedAt = runtime.now;
    }
    _disposeAd();
    unawaited(preload());
  }

  Future<bool> _loadOnce() async {
    final unitId = adUnitId;
    if (unitId.isEmpty) {
      _emitSkip(EasyAdSkipReason.noAdUnitId);
      return false;
    }
    if (!await runtime.ensureInitialized()) {
      _emitSkip(EasyAdSkipReason.notInitialized);
      return false;
    }
    if (!runtime.canRequestAds) {
      _emitSkip(EasyAdSkipReason.consentNotGranted);
      return false;
    }

    runtime.emit(
      EasyAdEvent(
        format: format,
        type: EasyAdEventType.loadStarted,
        adUnitId: unitId,
      ),
    );

    try {
      final ad = await performLoad(unitId, runtime.buildRequest()).timeout(
        runtime.config.loadTimeout,
        onTimeout: () {
          runtime.emit(
            EasyAdEvent(
              format: format,
              type: EasyAdEventType.loadFailed,
              adUnitId: unitId,
              message: 'load timed out after '
                  '${runtime.config.loadTimeout.inSeconds}s',
            ),
          );
          return null;
        },
      );

      if (ad == null) return false;

      _ad = ad;
      _loadedAt = runtime.now;
      ad.onPaidEvent = (_, value, precision, currencyCode) =>
          runtime.reportPaidEvent(
            format,
            unitId,
            value,
            precision,
            currencyCode,
          );

      runtime.emit(
        EasyAdEvent(
          format: format,
          type: EasyAdEventType.loaded,
          adUnitId: unitId,
        ),
      );
      return true;
    } catch (error, stackTrace) {
      runtime.logError(error, stackTrace);
      return false;
    }
  }

  /// Reports a load failure from a subclass's SDK callback.
  @protected
  void emitLoadFailure(String unitId, LoadAdError error) {
    runtime.emit(
      EasyAdEvent(
        format: format,
        type: EasyAdEventType.loadFailed,
        adUnitId: unitId,
        message: error.message,
        errorCode: error.code,
      ),
    );
  }

  void _emitSkip(EasyAdSkipReason reason) {
    runtime.emit(
      EasyAdEvent(
        format: format,
        type: EasyAdEventType.skipped,
        adUnitId: adUnitId,
        skipReason: reason,
      ),
    );
  }

  /// Time left in a show budget, or null when there is no deadline. Returns a
  /// non-positive duration once the budget is spent.
  Duration? _remaining(DateTime? deadline) =>
      deadline?.difference(runtime.now);

  Duration _backoffDelay(int attempt) {
    final base = runtime.config.retryBaseDelay.inMilliseconds;
    final capped = runtime.config.maxRetryDelay.inMilliseconds;
    final shift = attempt.clamp(0, 16);
    return Duration(milliseconds: (base << shift).clamp(0, capped));
  }

  void _disposeAd() {
    final ad = _ad;
    _ad = null;
    _loadedAt = null;
    if (ad == null) return;
    try {
      ad.dispose();
    } catch (error, stackTrace) {
      runtime.logError(error, stackTrace);
    }
  }

  /// Drops the cached ad. Call from the host app's teardown path.
  void dispose() => _disposeAd();
}
