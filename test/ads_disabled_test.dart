import 'dart:async';

import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A user who will never see an ad must never be asked for ad consent.
///
/// `enabled: false` used to gate ad *requests* only: `initialize()` still ran
/// the whole startup, so a subscriber got the UMP consent form in the EEA.
/// Host apps worked around it by skipping `initialize()` for subscribers,
/// which then left the SDK dead when the entitlement lapsed mid-session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/google_mobile_ads');

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <String>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call.method);
      // Never completes, so startup takes the timeout path instead of decoding
      // an initialization status the mock cannot produce.
      if (call.method == 'MobileAds#initialize') return Completer<void>().future;
      return Future<void>.value();
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  EasyAdsConfig config({required bool enabled}) => EasyAdsConfig(
    adUnitIds: const EasyAdUnitIds.test(),
    enabled: enabled,
    sdkInitTimeout: const Duration(milliseconds: 50),
  );

  test('disabled: neither consent nor the SDK is started', () async {
    final started = await EasyAds.instance.initialize(
      config: config(enabled: false),
      store: MemoryEasyAdsStore(),
    );

    expect(started, isFalse);
    expect(EasyAds.instance.isConfigured, isTrue);
    expect(EasyAds.instance.isReady, isFalse);
    expect(
      calls,
      isEmpty,
      reason: 'a subscriber must not reach the consent form',
    );
  });

  test('enabling later starts the SDK, without a cold start', () async {
    await EasyAds.instance.initialize(
      config: config(enabled: false),
      store: MemoryEasyAdsStore(),
    );

    await EasyAds.instance.setAdsEnabled(true);

    expect(EasyAds.instance.isReady, isTrue);
    expect(calls, contains('MobileAds#initialize'));
  });
}
