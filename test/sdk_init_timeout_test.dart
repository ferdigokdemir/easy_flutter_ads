import 'dart:async';

import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the real startup path against a platform channel that never
/// answers.
///
/// This is the one part of the package where a static type check is not
/// enough: the SDK hands back a `Future<InitializationStatus>` whatever the
/// declared type says, so a timeout callback returning null compiles and then
/// throws at run time — which is exactly what shipped in 0.1.1 and left the
/// package permanently uninitialized.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/google_mobile_ads');

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) {
      // Never completes: the SDK looks like it is stuck initializing.
      if (call.method == 'MobileAds#initialize') return Completer<void>().future;
      return Future<void>.value();
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('a stalled MobileAds.initialize() does not block ad loading', () async {
    final errors = <Object>[];

    final initialized = await EasyAds.instance.initialize(
      config: EasyAdsConfig(
        adUnitIds: const EasyAdUnitIds.test(),
        sdkInitTimeout: const Duration(milliseconds: 50),
        onError: (error, _) => errors.add(error),
      ),
    );

    expect(
      initialized,
      isTrue,
      reason: 'startup must fall through to loading, not fail',
    );
    expect(EasyAds.instance.isReady, isTrue);
    // The UMP plugin is absent in tests, so a MissingPluginException is
    // expected and handled. A TypeError is what the 0.1.1 bug produced.
    expect(errors.whereType<TypeError>(), isEmpty);
  });
}
