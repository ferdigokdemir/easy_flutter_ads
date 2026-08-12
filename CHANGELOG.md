## 0.1.10

- **Frequency controls are now persisted by default.** `EasyAds.initialize`
  falls back to `PrefsEasyAdsStore` (backed by `shared_preferences`) instead of
  the in-memory store, so the session counter, daily caps, hourly windows and
  cooldowns survive a cold start with no wiring in the host app.
  This closes a silent failure: an app that never passed a `store` got no
  working caps at all — no error, no log — and App Open, the format with the
  strictest rules, was hit hardest, because it shows precisely at cold start,
  the moment an in-memory counter has just been wiped.
- Adds a dependency on `shared_preferences` (>=2.3.0 <3.0.0). It reads and
  writes through the same `SharedPreferences.getInstance()` API the README used
  to document as a hand-written adapter, so an app deleting its own adapter
  keeps the counters it had rather than handing every user a fresh allowance.
  Keys stay namespaced under `easy_ads.`.
- Passing your own `EasyAdsStore` still overrides it; pass `MemoryEasyAdsStore()`
  to deliberately opt out of persistence. If the platform channel is
  unavailable the store degrades to memory and reports through
  `EasyAdsConfig.onError` — the old behaviour — rather than failing startup.
- New `appOpenHourlyCap`, defaulting to 2 — the same rolling window 0.1.9 gave
  interstitials, now for App Open ads. `appOpenDailyCap` bounds the day but says
  nothing about how fast the allowance is spent, and this format's trigger is a
  burst by nature: a user alternating between your app and a messenger produces
  a foreground transition every time, so all three of the day's App Open ads can
  be gone before they have used the app once with intent.
- `appOpenCooldown` stays at zero. A fixed gap would space the burst out too,
  but it charges the user who returns twice all day as much as the one who
  returns twice a minute; the rolling hour only bites the second.
- The window is persisted through `EasyAdsStore` like the interstitial one, so
  a relaunch cannot clear it — which matters more here, because cold start is
  exactly when the format shows. Pass `clearAppOpenHourlyCap: true` through
  `copyWith` to opt back out.
- No new machinery: `AdRuntime.hourlyCapFor` was already format-agnostic, so the
  show gate, the ring buffer and the TTL-aware preload decision all applied to
  App Open the moment the config field existed. In practice preloading is
  unaffected — a spent hour reopens within 60 minutes and an App Open ad stays
  fresh for 3h30m, so the ad is in hand the moment the cap lifts.

## 0.1.9

- New `interstitialHourlyCap`, defaulting to 2. It is the middle term between
  `interstitialCooldown` and `interstitialDailyCap`, and none of the three can
  stand in for the others: a cooldown alone lets a heavy session run twenty ads
  an hour, and a daily cap alone lets the whole allowance burn in the first ten
  minutes. Raising the cooldown to imitate the cap would space ads far apart
  even for a user who has seen none today.
- The window slides — "in the last 60 minutes", not "since the top of the
  hour" — so the boundary cannot be used to double up. Only the last `cap`
  impressions are stored, in a ring buffer whose cursor points at the oldest, so
  the check costs two reads no matter how heavily the app is used. Persisted
  through `EasyAdsStore`, so a relaunch cannot clear a running window.
- `preload()` decides on TTL here rather than skipping outright: it loads when
  the ad would still be fresh at the moment the cap lifts, and skips when it
  would expire in the cache first.
- New `EasyAdSkipReason.hourlyCapReached`.

## 0.1.8

- `preload()` no longer sends a request once the format's daily cap is spent.
  The cap used to be a show-time gate only, so a capped format kept loading all
  day — every background transition fired a preload, and each no-fill dragged
  three retries behind it. Nothing loaded after the cap can be shown before the
  date rolls over, so the request was pure waste.
- A running **cooldown** still loads through, deliberately: the point of
  preloading is to have the ad in hand when the window reopens, and skipping
  the load would empty the cache at exactly the moment the next impression is
  due.
- New `AdRuntime.isDailyCapReached(format)` backs both the show gate and the
  preload gate, so the rule lives in one place.

## 0.1.7

- `appOpenDailyCap` now defaults to 3 and `interstitialDailyCap` to 6, instead
  of no cap at all. A cooldown bounds the interval between two ads but never the
  day: a user who switches back and forth all afternoon clears any gap you set
  and still meets an App Open ad on every return. Both caps need a persistent
  `EasyAdsStore` — with the in-memory default the App Open counter resets on
  every cold start, which is exactly when the format shows. Pass
  `clearAppOpenDailyCap: true` / `clearInterstitialDailyCap: true` through
  `copyWith` to opt back out.
- `appOpenMinSessions` now defaults to 1 instead of 3. Skipping the very first
  launch is what the guidance is about — the session that decides whether the
  app is kept — and three sessions withheld more inventory than that buys.

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
