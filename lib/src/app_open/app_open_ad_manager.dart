import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/easy_ad_event.dart';
import '../full_screen/full_screen_ad_manager.dart';

/// App Open ads — the format with the strictest placement rules.
///
/// AdMob only allows this format when the user opens the app or returns to it,
/// and the ad must render *over a loading screen*, before app content is
/// visible:
///
/// > "The preferred way to use app open ads on cold starts is to use a loading
/// > screen to load your game or app assets, and to only show the ad from the
/// > loading screen."
///
/// The two entry points here encode that: [showOnColdStart] is meant to be
/// awaited on your splash screen before you navigate to the first real screen,
/// and [startWatchingAppState] handles returns from the background.
///
/// See https://support.google.com/admob/answer/9341964
class AppOpenAdManager extends FullScreenAdManager<AppOpenAd> {
  /// Creates the manager.
  AppOpenAdManager(super.runtime);

  StreamSubscription<AppState>? _appStateSubscription;

  @override
  EasyAdFormat get format => EasyAdFormat.appOpen;

  @override
  String get adUnitId => runtime.config.adUnitIds.appOpen;

  @override
  Duration get ttl => runtime.config.appOpenAdTtl;

  /// Shows the cold start ad **while your splash screen is still on screen**.
  ///
  /// Await this after your startup work finishes and before you navigate away:
  ///
  /// ```dart
  /// final navigator = Navigator.of(context); // capture before the await
  /// await AppController.instance.init();
  /// await EasyAds.instance.appOpen.showOnColdStart();
  /// navigator.pushReplacementNamed(Routes.home);
  /// ```
  ///
  /// The wait is capped by [EasyAdsConfig.appOpenSplashMaxWait]; if the ad is
  /// not ready by then the show is cancelled for good, so it can never surface
  /// later on top of app content. The in-flight load keeps running and the ad
  /// is kept for the next opportunity.
  ///
  /// Returns true only if an ad was actually shown and dismissed.
  Future<bool> showOnColdStart({Duration? maxWait}) async {
    if (!runtime.config.appOpenColdStartEnabled) {
      _emitSkipped(EasyAdSkipReason.formatDisabled);
      return false;
    }

    // "Show your first app open ad after your users have used your app a few
    // times." Needs a persistent EasyAdsStore to mean anything.
    if (runtime.sessionCount <= runtime.config.appOpenMinSessions) {
      _emitSkipped(EasyAdSkipReason.sessionThreshold);
      return false;
    }

    return show(
      maxLoadWait: maxWait ?? runtime.config.appOpenSplashMaxWait,
    );
  }

  /// Starts showing the ad when the app returns from the background.
  ///
  /// Uses the SDK's [AppStateEventNotifier] rather than
  /// `WidgetsBindingObserver`: the latter also fires when a full screen ad
  /// takes over the Flutter view, which makes "user left the app" and "an
  /// interstitial opened" indistinguishable.
  ///
  /// Only a preloaded ad is shown. Loading on resume would put the ad on
  /// screen seconds after the user is already interacting with content — the
  /// placement AdMob prohibits.
  void startWatchingAppState() {
    if (_appStateSubscription != null) return;
    AppStateEventNotifier.startListening();
    _appStateSubscription = AppStateEventNotifier.appStateStream.listen((
      state,
    ) {
      if (state != AppState.foreground) return;
      unawaited(_onForeground());
    });
  }

  /// Stops reacting to app state changes.
  Future<void> stopWatchingAppState() async {
    await _appStateSubscription?.cancel();
    _appStateSubscription = null;
    await AppStateEventNotifier.stopListening();
  }

  Future<void> _onForeground() async {
    // Refresh the cache first: after a long background stint the ad is likely
    // past its TTL, and preload() is cheap when it is not.
    unawaited(preload());

    if (!runtime.config.appOpenResumeEnabled) {
      _emitSkipped(EasyAdSkipReason.formatDisabled);
      return;
    }
    await show(loadIfMissing: false);
  }

  @override
  Future<AppOpenAd?> performLoad(String adUnitId, AdRequest request) {
    final completer = Completer<AppOpenAd?>();
    AppOpenAd.load(
      adUnitId: adUnitId,
      request: request,
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (error) {
          emitLoadFailure(adUnitId, error);
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  @override
  void assignCallback(
    AppOpenAd ad,
    FullScreenContentCallback<AppOpenAd> callback,
  ) {
    ad.fullScreenContentCallback = callback;
  }

  @override
  Future<void> performShow(AppOpenAd ad) => ad.show();

  @override
  void dispose() {
    unawaited(stopWatchingAppState());
    super.dispose();
  }

  void _emitSkipped(EasyAdSkipReason reason) {
    runtime.emit(
      EasyAdEvent(
        format: format,
        type: EasyAdEventType.skipped,
        adUnitId: adUnitId,
        skipReason: reason,
      ),
    );
  }
}
