import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:easy_flutter_ads/src/core/ad_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// What happens when `shared_preferences` cannot be reached at all.
///
/// This file must never call `SharedPreferences.setMockInitialValues` — that
/// swaps the platform implementation for an in-memory one for the rest of the
/// file, which is exactly the failure being ruled out here. Without it the
/// plugin has no platform side, the same shape as a host that failed to
/// register it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('degrades to memory instead of throwing', () async {
    final errors = <Object>[];
    final store = PrefsEasyAdsStore(onError: (error, _) => errors.add(error));

    await store.writeInt('easy_ads.session_count', 3);
    expect(await store.readInt('easy_ads.session_count'), 3);
    expect(await store.readInt('easy_ads.absent'), 0);

    expect(errors, isNotEmpty, reason: 'the failure must be reported');
  });

  test('reports the failure once, not per read', () async {
    final errors = <Object>[];
    final store = PrefsEasyAdsStore(onError: (error, _) => errors.add(error));

    for (var i = 0; i < 5; i++) {
      await store.readInt('easy_ads.session_count');
    }

    // Retrying a missing channel would cost an exception per ad decision for
    // the rest of the run.
    expect(errors, hasLength(1));
  });

  test('the gates still run on the in-memory fallback', () async {
    var now = DateTime(2026, 7, 20, 12);
    final runtime = AdRuntime(
      config: const EasyAdsConfig(adUnitIds: EasyAdUnitIds.test()),
      store: PrefsEasyAdsStore(),
      clock: () => now,
    );
    await runtime.startSession();

    await runtime.noteShown(EasyAdFormat.appOpen);
    await runtime.noteShown(EasyAdFormat.appOpen);

    // Degraded to the old behaviour — caps that reset on restart — rather than
    // no caps at all.
    expect(
      await runtime.evaluateGates(EasyAdFormat.appOpen),
      EasyAdSkipReason.hourlyCapReached,
    );

    now = now.add(const Duration(minutes: 61));
    expect(await runtime.evaluateGates(EasyAdFormat.appOpen), isNull);
  });
}
