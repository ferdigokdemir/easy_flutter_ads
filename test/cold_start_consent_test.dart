import 'dart:async';

import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `initialize(gatherConsent: false)` — the cold start path under a splash —
/// never reaches UMP: the consent form must open on the first real screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sdk = MethodChannel('plugins.flutter.io/google_mobile_ads');
  const ump = 'plugins.flutter.io/google_mobile_ads/ump';

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final sdkCalls = <String>[];
  var umpCalls = 0;

  setUp(() {
    sdkCalls.clear();
    umpCalls = 0;
    messenger.setMockMethodCallHandler(sdk, (call) {
      sdkCalls.add(call.method);
      if (call.method == 'MobileAds#initialize') return Completer<void>().future;
      return Future<void>.value();
    });
    // The UMP channel has its own codec; counting messages is enough here.
    messenger.setMockMessageHandler(ump, (_) async {
      umpCalls++;
      return const StandardMethodCodec().encodeSuccessEnvelope(null);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(sdk, null);
    messenger.setMockMessageHandler(ump, null);
  });

  final config = EasyAdsConfig(
    adUnitIds: const EasyAdUnitIds.test(),
    sdkInitTimeout: const Duration(milliseconds: 50),
  );

  test('consent never completed: nothing starts, no form', () async {
    final store = MemoryEasyAdsStore();

    final started = await EasyAds.instance.initialize(
      config: config,
      store: store,
      gatherConsent: false,
    );

    expect(started, isFalse);
    expect(umpCalls, 0);
    expect(sdkCalls, isEmpty);
    expect(await store.readInt('easy_ads.session_count'), 0);
  });

  test('consent on file: SDK starts, the refresh waits for initialize()',
      () async {
    final store = MemoryEasyAdsStore();
    await store.writeInt('easy_ads.consent_gathered', 1);

    final started = await EasyAds.instance.initialize(
      config: config,
      store: store,
      gatherConsent: false,
    );

    expect(started, isTrue);
    expect(sdkCalls, contains('MobileAds#initialize'));
    expect(umpCalls, 0, reason: 'no consent form on the splash');

    await EasyAds.instance.initialize(config: config);

    expect(umpCalls, greaterThan(0));
  });
}
