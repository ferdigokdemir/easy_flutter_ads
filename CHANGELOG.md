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
