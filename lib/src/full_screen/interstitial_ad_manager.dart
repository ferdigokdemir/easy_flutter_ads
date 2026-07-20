import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/easy_ad_event.dart';
import 'full_screen_ad_manager.dart';

/// Interstitial ads.
///
/// Reach for these at natural breaks — level ends, screen transitions the user
/// asked for — never mid-task. Google Play's disruptive-ads policy treats a
/// full screen ad that appears while the user is doing something else as an
/// unexpected ad, and that is an app-level enforcement, not just an AdMob one.
class InterstitialAdManager extends FullScreenAdManager<InterstitialAd> {
  /// Creates the manager.
  InterstitialAdManager(super.runtime);

  @override
  EasyAdFormat get format => EasyAdFormat.interstitial;

  @override
  String get adUnitId => runtime.config.adUnitIds.interstitial;

  @override
  Duration get ttl => runtime.config.fullScreenAdTtl;

  @override
  Future<InterstitialAd?> performLoad(String adUnitId, AdRequest request) {
    final completer = Completer<InterstitialAd?>();
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: request,
      adLoadCallback: InterstitialAdLoadCallback(
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
    InterstitialAd ad,
    FullScreenContentCallback<InterstitialAd> callback,
  ) {
    ad.fullScreenContentCallback = callback;
  }

  @override
  Future<void> performShow(InterstitialAd ad) => ad.show();
}
