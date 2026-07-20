import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/easy_ad_event.dart';
import '../core/easy_ad_reward.dart';
import 'full_screen_ad_manager.dart';

/// Rewarded interstitials: a full screen ad with a reward, shown at a natural
/// transition after an intro screen announcing it.
///
/// AdMob requires that intro screen — the user must be able to opt out before
/// the ad starts.
class RewardedInterstitialAdManager
    extends FullScreenAdManager<RewardedInterstitialAd> {
  /// Creates the manager.
  RewardedInterstitialAdManager(super.runtime);

  EasyAdReward? _reward;

  @override
  EasyAdFormat get format => EasyAdFormat.rewardedInterstitial;

  @override
  String get adUnitId => runtime.config.adUnitIds.rewardedInterstitial;

  @override
  Duration get ttl => runtime.config.fullScreenAdTtl;

  /// Shows the ad and returns the reward, or null when nothing was earned.
  Future<EasyAdReward?> showForReward({
    bool loadIfMissing = true,
    Duration? maxLoadWait,
  }) async {
    _reward = null;
    final shown = await show(
      loadIfMissing: loadIfMissing,
      maxLoadWait: maxLoadWait,
    );
    return shown ? _reward : null;
  }

  @override
  Future<RewardedInterstitialAd?> performLoad(
    String adUnitId,
    AdRequest request,
  ) {
    final completer = Completer<RewardedInterstitialAd?>();
    RewardedInterstitialAd.load(
      adUnitId: adUnitId,
      request: request,
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
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
    RewardedInterstitialAd ad,
    FullScreenContentCallback<RewardedInterstitialAd> callback,
  ) {
    ad.fullScreenContentCallback = callback;
  }

  @override
  Future<void> performShow(RewardedInterstitialAd ad) {
    return ad.show(
      onUserEarnedReward: (_, reward) {
        _reward = EasyAdReward(amount: reward.amount, type: reward.type);
        runtime.emit(
          EasyAdEvent(
            format: format,
            type: EasyAdEventType.rewardEarned,
            adUnitId: adUnitId,
            message: '${reward.amount} ${reward.type}',
          ),
        );
      },
    );
  }
}
