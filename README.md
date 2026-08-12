# easy_flutter_ads

A production-grade wrapper around [`google_mobile_ads`](https://pub.dev/packages/google_mobile_ads).

The SDK gives you `load()` and `show()`. Everything between them — caching, expiry, retries, consent
ordering, and the placement rules AdMob enforces — is left to you, and that is where apps get their
ad serving limited. `easy_flutter_ads` is that layer, written once.

```dart
await EasyAds.instance.initialize(
  config: EasyAdsConfig(adUnitIds: const EasyAdUnitIds.test()),
  store: PrefsAdsStore(),
);

EasyAds.instance.preloadAll();
EasyAds.instance.appOpen.startWatchingAppState();

await EasyAds.instance.interstitial.show();
final reward = await EasyAds.instance.rewarded.showForReward();
```

## What it handles for you

| | |
|---|---|
| **Expiry** | Interstitial/rewarded ads expire ~1h after the request, App Open ads after 4h. Cached ads carry a TTL with a safety margin, and an expired ad is disposed instead of shown — showing one fails at render time. |
| **Single-flight loading** | One in-flight request per format. Concurrent callers share it. In mediation, every duplicate `load()` fans out to every network. |
| **Backoff** | No-fill retries use a capped exponential backoff (2s → 4s → … → 32s), never a tight loop. |
| **Timeout** | The SDK has no load timeout; this package does. A request on a dead network cannot pin the retry loop forever. |
| **Consent ordering** | UMP consent is gathered *before* `MobileAds.initialize()` and before the first request. Ads requested without a consent string cost you EEA/UK/CH fill. |
| **Initialization ordering** | Every load waits behind a memoized `initialize()`, so mediation adapters participate in the first request. |
| **Placement policy** | The App Open rules AdMob actually enforces — see below. |
| **Revenue** | `onPaidEvent` is wired automatically for every format. Retrofitting impression-level revenue later is painful. |
| **Kill switches** | One `enabled` flag for subscribers, one per format, all hot-swappable from Remote Config. |
| **Frequency** | Per-format cooldowns and daily caps, enforced client side so capped requests are never sent (AdMob's dashboard cap returns a no-fill instead). |
| **Never crashes** | Every path swallows its exceptions and reports them via `onError`. A broken ad stack degrades to "no ads". |

## App Open ads: the part most implementations get wrong

AdMob's [placement policy](https://support.google.com/admob/answer/9341964) for this format is
specific, and two rules are routinely broken:

**1. The ad must render over a loading screen, not over app content.**

> "The preferred way to use app open ads on cold starts is to use a loading screen to load your game
> or app assets, and to only show the ad from the loading screen."

So `showOnColdStart()` belongs on your splash screen, before you navigate:

```dart
final navigator = Navigator.of(context); // capture before awaiting
await AppController.instance.init();
await EasyAds.instance.appOpen.showOnColdStart();
navigator.pushReplacementNamed(Routes.home);
```

The wait is capped by `appOpenSplashMaxWait` (5s default). If the ad is not ready in time the show is
**cancelled**, not deferred — it can never appear later, on top of content the user is already using.
The load keeps running in the background, so the ad is kept for the next opportunity.

Note what this rules out: `Future.timeout()` around a plain `show()` does *not* work. Futures in Dart
cannot be cancelled, so the ad still appears when it eventually loads — over your home screen.

**2. No ad immediately before or after another ad.**

When a user taps an interstitial or rewarded ad, the app is backgrounded (Play Store or browser
opens). On return, the SDK reports a foreground transition — and a naive resume handler shows an App
Open ad on top of the ad the user just came back from. `minGapAfterFullScreenAd` (120s default)
suppresses exactly that, and `startWatchingAppState()` only ever shows an already-cached ad, so an ad
can never surface seconds into a session.

**3. No ad on a return your own app caused.**

An image picker, the camera, a sign-in flow, the Play Store, a share sheet — every one of them
backgrounds your app and comes back as a plain foreground transition. `minGapAfterFullScreenAd` does
not help here: it only knows about ads *this package* showed. Announce those trips:

```dart
EasyAds.instance.appOpen.suppressResume();
final file = await ImagePicker().pickImage(source: source);
```

The whole window (5 min default) is suppressed rather than just the next foreground event, because a
permission dialog in front of the picker fires a background/foreground pair of its own. It expires by
itself, so an abandoned flow does not disable the resume ad for the rest of the session.

There is **no numeric frequency rule** for App Open ads in AdMob's policies — the "4 hours" in
Google's docs is the ad object's expiry, and the other "4 hours" on the policy page describes which
apps the format suits ("apps with frequent opens see the best performance"). Frequency is therefore a
UX/revenue decision: `appOpenCooldown` defaults to zero (no gate) — set it yourself if you want one.
Interstitials are different: `interstitialCooldown` defaults to 180 seconds, because two screens that
each open one put two full screen ads seconds apart the moment a user taps through them quickly. Both
last impressions are persisted, so killing and relaunching the app does not hand the user a fresh
cooldown.

## Configuration

Every field of `EasyAdsConfig` is documented inline and hot-swappable:

```dart
// Firebase Remote Config → package
await EasyAds.instance.updateConfig(
  EasyAds.instance.config.copyWith(
    appOpenCooldown: Duration(seconds: remote.getInt('app_open_cooldown')),
    interstitialEnabled: remote.getBool('interstitial_enabled'),
  ),
);

// The user just subscribed
await EasyAds.instance.setAdsEnabled(false);
```

Session thresholds (`appOpenMinSessions`, "show the first App Open ad after a few visits"), daily
caps, and cooldowns need persistence — and the defaults already include caps (3 App Open ads and 6
interstitials a day), so this is not optional bookkeeping: without a store the App Open counter
resets on every cold start, which is exactly when the format shows. Supply an `EasyAdsStore`:

```dart
class PrefsAdsStore implements EasyAdsStore {
  @override
  Future<int> readInt(String key) async =>
      (await SharedPreferences.getInstance()).getInt(key) ?? 0;

  @override
  Future<void> writeInt(String key, int value) async =>
      (await SharedPreferences.getInstance()).setInt(key, value);
}
```

## Banners

```dart
const EasyBannerAd()                                        // anchored adaptive
const EasyBannerAd(type: EasyBannerType.inlineAdaptive)     // inside scrollables
const EasyBannerAd(type: EasyBannerType.fixed,
                   fixedSize: AdSize.mediumRectangle)
const EasyBannerAd(collapse: EasyBannerCollapse.bottom)     // collapsible
```

`EasyBannerAd` loads on mount, re-requests when the available width changes (rotation, split screen),
retries failures with backoff, disposes itself, and renders nothing until an ad is actually on
screen — so no empty box is reserved for a banner that may never fill.

It has **no refresh timer** on purpose. Refresh rate belongs on the ad unit in the AdMob dashboard;
refreshing from client code double-counts requests and can breach the 60-second minimum.

Collapsible banners are granted one slot per session (`collapsibleBannerOncePerSession`) since they
start expanded over content. Only Google demand fills them; a mediated fill renders as a normal
banner.

## Events and revenue

```dart
EasyAdsConfig(
  onEvent: (event) => analytics.logEvent(name: 'ad_${event.type.name}', parameters: {
    'format': event.format.name,
    if (event.skipReason != null) 'skip_reason': event.skipReason!.name,
  }),
  onPaidEvent: (revenue) => analytics.logEvent(name: 'ad_impression', parameters: {
    'value': revenue.value,
    'currency': revenue.currencyCode,
  }),
  onError: (error, stack) =>
      FirebaseCrashlytics.instance.recordError(error, stack),
)
```

`skipped` events are the interesting ones: they tell you how often a show was blocked and by which
gate — numbers AdMob's dashboard cannot show you, because those requests never left the device.

## Testing

`EasyAdUnitIds.test()` returns Google's official test IDs. `testDeviceIds` is ignored in release
builds unless you explicitly opt in, so a device left on the list cannot silently stop earning.

To exercise the EEA consent form, set `forceConsentDebugGeographyEea: true` with your device in
`testDeviceIds`, and use `EasyAds.instance.consent.reset()` between runs (debug builds only — it
asserts).

## Setup

Add the AdMob app ID to `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY"/>
```

and to `ios/Runner/Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>
```

## Not included

- **Native ads.** They need platform-side layout factories, which would make this a plugin with
  native code rather than a pure Dart package.
- **The SDK's own preloading API.** `InterstitialAdPreloader` and friends are merged into the plugin's
  main branch but are not in a released version yet. The manual cache here does the same job; when the
  API ships, it becomes an implementation detail behind the same façade.

## License

MIT
