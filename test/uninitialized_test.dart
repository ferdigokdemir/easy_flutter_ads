import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:flutter_test/flutter_test.dart';

/// Startup order is not something a widget can control: a screen may build
/// before the app finished booting, or the user may reach it through a route
/// that skips startup entirely. None of that may crash the host app.
void main() {
  group('before initialize()', () {
    test('reports itself as unconfigured', () {
      expect(EasyAds.instance.isConfigured, isFalse);
      expect(EasyAds.instance.isReady, isFalse);
    });

    test('manager getters return an instance instead of throwing', () {
      expect(EasyAds.instance.interstitial, isNotNull);
      expect(EasyAds.instance.rewarded, isNotNull);
      expect(EasyAds.instance.rewardedInterstitial, isNotNull);
      expect(EasyAds.instance.appOpen, isNotNull);
      expect(EasyAds.instance.consent, isNotNull);
    });

    test('shows are silent no-ops, not requests', () async {
      expect(await EasyAds.instance.interstitial.show(), isFalse);
      expect(await EasyAds.instance.rewarded.showForReward(), isNull);
      expect(await EasyAds.instance.appOpen.showOnColdStart(), isFalse);
    });

    test('preloadAll does nothing', () {
      expect(EasyAds.instance.preloadAll, returnsNormally);
    });

    test('ensureInitialized reports failure rather than starting the SDK', () async {
      expect(await EasyAds.instance.ensureInitialized(), isFalse);
    });
  });
}
