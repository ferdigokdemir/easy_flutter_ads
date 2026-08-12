import 'package:easy_flutter_ads/easy_flutter_ads.dart';
import 'package:easy_flutter_ads/src/core/ad_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The happy path of the default store. The failure path needs a test file
/// with no mock preferences in it at all — see `prefs_store_fallback_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    now = DateTime(2026, 7, 20, 12);
    SharedPreferences.setMockInitialValues({});
  });

  group('the default store', () {
    test('round-trips a value', () async {
      final store = PrefsEasyAdsStore();

      expect(await store.readInt('easy_ads.absent'), 0);

      await store.writeInt('easy_ads.session_count', 4);
      expect(await store.readInt('easy_ads.session_count'), 4);
    });

    test('a second instance reads what the first wrote', () async {
      await PrefsEasyAdsStore().writeInt('easy_ads.session_count', 7);

      // Stands in for the next cold start: new process, same preferences.
      expect(await PrefsEasyAdsStore().readInt('easy_ads.session_count'), 7);
    });

    test('carries an hourly window across a restart', () async {
      const config = EasyAdsConfig(adUnitIds: EasyAdUnitIds.test());

      final first = AdRuntime(
        config: config,
        store: PrefsEasyAdsStore(),
        clock: clock,
      );
      await first.startSession();
      await first.noteShown(EasyAdFormat.appOpen);
      await first.noteShown(EasyAdFormat.appOpen);

      // The user kills the app and relaunches it ten minutes later. This is the
      // case the in-memory default could never cover: App Open shows at cold
      // start, exactly when memory has just been wiped.
      now = now.add(const Duration(minutes: 10));
      final second = AdRuntime(
        config: config,
        store: PrefsEasyAdsStore(),
        clock: clock,
      );
      await second.startSession();

      expect(
        await second.evaluateGates(EasyAdFormat.appOpen),
        EasyAdSkipReason.windowCapReached,
      );

      now = now.add(const Duration(minutes: 51));
      expect(await second.evaluateGates(EasyAdFormat.appOpen), isNull);
    });

    test('the session counter survives a restart', () async {
      const config = EasyAdsConfig(adUnitIds: EasyAdUnitIds.test());

      final first = AdRuntime(config: config, store: PrefsEasyAdsStore());
      await first.startSession();
      expect(first.sessionCount, 1);

      final second = AdRuntime(config: config, store: PrefsEasyAdsStore());
      await second.startSession();
      // Without this, appOpenMinSessions would hold the format back forever.
      expect(second.sessionCount, 2);
    });
  });
}
