## 0.1.6

- `interstitialCooldown` now defaults to 180 seconds instead of zero. App flow
  is not a frequency policy: two screens that each open an interstitial put two
  full screen ads seconds apart as soon as a user taps through them quickly.
  Enforcing the gap here rather than through an AdMob dashboard frequency cap
  also keeps the capped request from being sent at all — a dashboard cap answers
  with a no-fill, and those wasted round trips drag the ad unit's match rate
  down. Pass `Duration.zero` to restore the old behaviour.
- `minGapAfterFullScreenAd` now defaults to 120 seconds instead of 30. The gap
  has to outlast the *detour*, not the ad: a user who taps an interstitial,
  lands in the Play Store and browses for a minute comes back to an expired
  30 second gap and gets an App Open ad on top of the ad they just left —
  precisely the adjacency AdMob's placement policy prohibits. Only users who
  just tapped an ad are affected, so the lost impressions are marginal. Pass an
  explicit `Duration` to restore the old value.

## 0.1.5

- `EasyBannerAd` no longer stays empty when the user takes their time with the
  UMP consent form. A banner mounted while the form is still on screen used to
  *decline* its load — no request was sent, so the retry ladder never started
  and the slot stayed blank until the widget happened to be rebuilt from
  scratch (a tab switch, a pushed route coming back). It now watches the
  request gate and loads the moment consent resolves. The same gate reopens if
  `MobileAds.initialize()` finishes after `sdkInitTimeout`, so a banner that
  failed against a half-started SDK reloads instead of burning its retries.
- `show()` and `showForReward()` now default `maxLoadWait` to 15 seconds
  instead of no budget at all. An unbounded wait was never what a call site
  wanted: it either had a spinner up (and 15s is plenty) or had none (and an
  open-ended freeze was a bug). Pass an explicit null to restore the old
  behaviour. The constant is `FullScreenAdManager.defaultMaxLoadWait`.
  `showOnColdStart()` is unaffected — it has always passed
  `appOpenSplashMaxWait`.

## 0.1.4

- `appOpenCooldown` and `interstitialCooldown` are now persisted through the
  `EasyAdsStore`. The last impression only lived in memory, so killing and
  relaunching the app handed the user a fresh cooldown — the gate held across a
  background/resume but not across a cold start, which is exactly the case an
  App Open cooldown is there for. A stored timestamp in the future (device
  clock moved backwards) is discarded rather than freezing the format.

## 0.1.3

- New `EasyAds.instance.appOpen.suppressResume()`: call it before sending the
  user to an activity outside your UI (image picker, camera, sign-in, Play
  Store, share sheet) so the return does not open an App Open ad in the middle
  of a flow the user is still in. The SDK reports those returns as ordinary
  foreground transitions, and `minGapAfterFullScreenAd` cannot see them — it
  only knows about full screen ads the package itself showed.

## 0.1.2

- Fix a run-time crash in 0.1.1's SDK init timeout: `Future.timeout` rejects a
  callback returning null when the underlying future is non-nullable whatever
  the static type says, so startup always threw and the package stayed
  uninitialized. Covered by a test that stalls the platform channel.
- `requestConsentInfoUpdate` failures no longer escape into the host app's zone
  as unhandled async errors.

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
