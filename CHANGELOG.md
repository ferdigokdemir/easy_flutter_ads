## 0.1.1

Reviewed against Google's official Android examples
(googleads-mobile-android-examples).

- The "a full screen ad is on screen" flag is now set before `show()` rather
  than in the shown callback, closing the window in which another format could
  render over an ad that was already on its way up.
- SDK startup no longer waits for the consent round trip when UMP already has
  the user's decision on file; the refresh runs alongside initialization, as in
  Google's samples. Only the first launch waits.
- `MobileAds.initialize()` is capped by the new `sdkInitTimeout` (5s default),
  matching Google's "reduce first impression latency" guidance: a stalled
  mediation adapter can no longer hold the first impression hostage.

## 0.1.0

Initial release.

- App Open ads with AdMob-policy-safe placement: splash-only cold start with a capped wait,
  resume ads from cache only, and suppression around other full screen ads.
- Interstitial, rewarded and rewarded interstitial managers sharing one loader: TTL, load timeout,
  single-flight requests and capped exponential backoff.
- `EasyBannerAd` widget: anchored adaptive, inline adaptive, fixed and collapsible banners with
  width-change reloads and self-disposal.
- UMP consent gathered before SDK initialization, plus privacy options entry point and test reset.
- Hot-swappable `EasyAdsConfig` for Remote Config, a global kill switch for subscribers, per-format
  cooldowns and daily caps.
- Lifecycle events, skip reasons and impression-level revenue (`onPaidEvent`) forwarded to the host
  app.
