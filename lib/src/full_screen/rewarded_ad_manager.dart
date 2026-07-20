import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/easy_ad_event.dart';
import '../core/easy_ad_reward.dart';
import 'full_screen_ad_manager.dart';

/// Rewarded ads — the user opts in and gets something back.
///
/// Because the user asked for this ad, it is exempt from the cooldown and
/// adjacency gates: suppressing it would break a promise the app has already
/// made on screen ("watch an ad to unlock").
class RewardedAdManager extends FullScreenAdManager<RewardedAd> {
  /// Creates the manager.
  RewardedAdManager(super.runtime);

  EasyAdReward? _reward;

  @override
  EasyAdFormat get format => EasyAdFormat.rewarded;

  @override
  String get adUnitId => runtime.config.adUnitIds.rewarded;

  @override
  Duration get ttl => runtime.config.fullScreenAdTtl;

  /// Shows the ad and returns the reward the user earned.
  ///
  /// Returns null when the ad could not be shown *or* when the user dismissed
  /// it before earning the reward — in both cases you must not grant anything.
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
  Future<RewardedAd?> performLoad(String adUnitId, AdRequest request) {
    final completer = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: adUnitId,
      request: request,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
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
    RewardedAd ad,
    FullScreenContentCallback<RewardedAd> callback,
  ) {
    ad.fullScreenContentCallback = callback;
  }

  @override
  Future<void> performShow(RewardedAd ad) {
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
