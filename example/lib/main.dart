import 'dart:async';

import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ExampleApp());
}

/// Persists the session counter and daily caps across cold starts. Without a
/// store like this, `appOpenMinSessions` and the daily caps do nothing.
class PrefsAdsStore implements EasyAdsStore {
  @override
  Future<int> readInt(String key) async =>
      (await SharedPreferences.getInstance()).getInt(key) ?? 0;

  @override
  Future<void> writeInt(String key, int value) async =>
      (await SharedPreferences.getInstance()).setInt(key, value);
}

/// Root widget.
class ExampleApp extends StatelessWidget {
  /// Creates the app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'easy_flutter_ads example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const SplashPage(),
    );
  }
}

/// The loading screen. This is where the cold start App Open ad belongs: it
/// renders over a screen the user is already waiting on, before any app
/// content is visible.
class SplashPage extends StatefulWidget {
  /// Creates the splash page.
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    // Capture the navigator before the first await: the widget may be gone by
    // the time the ad is dismissed.
    final navigator = Navigator.of(context);

    await EasyAds.instance.initialize(
      store: PrefsAdsStore(),
      config: EasyAdsConfig(
        adUnitIds: const EasyAdUnitIds.test(),
        verboseLogging: true,
        appOpenMinSessions: 0, // show from the first run in this demo
        onEvent: (event) => debugPrint('event: $event'),
        onPaidEvent: (revenue) => debugPrint('revenue: $revenue'),
        onError: (error, stack) => debugPrint('error: $error'),
      ),
    );

    EasyAds.instance.preloadAll();

    // Your own startup work (config fetch, auth, migrations) goes here.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Shows only if an ad is ready within appOpenSplashMaxWait; otherwise the
    // launch continues without one.
    await EasyAds.instance.appOpen.showOnColdStart();

    unawaited(
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// Demonstrates the remaining formats.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _lastResult = '—';
  bool _privacyOptionsRequired = false;

  @override
  void initState() {
    super.initState();
    // Resume ads start here, once the app is actually running.
    EasyAds.instance.appOpen.startWatchingAppState();
    _checkPrivacyOptions();
  }

  Future<void> _checkPrivacyOptions() async {
    final required = await EasyAds.instance.consent.isPrivacyOptionsRequired();
    if (mounted) setState(() => _privacyOptionsRequired = required);
  }

  Future<void> _showInterstitial() async {
    final shown = await EasyAds.instance.interstitial.show();
    setState(() => _lastResult = 'interstitial shown: $shown');
  }

  Future<void> _showRewarded() async {
    final reward = await EasyAds.instance.rewarded.showForReward();
    setState(
      () => _lastResult = reward == null
          ? 'no reward — do not grant anything'
          : 'earned ${reward.amount} ${reward.type}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('easy_flutter_ads')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_lastResult, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _showInterstitial,
            child: const Text('Show interstitial'),
          ),
          FilledButton(
            onPressed: _showRewarded,
            child: const Text('Show rewarded'),
          ),
          FilledButton(
            onPressed: () => EasyAds.instance.setAdsEnabled(false),
            child: const Text('Simulate a subscriber (disable ads)'),
          ),
          if (_privacyOptionsRequired)
            TextButton(
              onPressed: () =>
                  unawaited(EasyAds.instance.consent.showPrivacyOptionsForm()),
              child: const Text('Privacy settings'),
            ),
          const SizedBox(height: 24),
          const Text('Inline adaptive banner inside content:'),
          const EasyBannerAd(type: EasyBannerType.inlineAdaptive),
        ],
      ),
      // Anchored adaptive banner, the standard bottom placement.
      bottomNavigationBar: const SafeArea(child: EasyBannerAd()),
    );
  }
}
