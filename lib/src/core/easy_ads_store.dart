/// Persistence hook for the values that must survive an app restart: the
/// number of sessions so far, daily caps, the rolling hourly windows, and the
/// last impression of each cooldown-gated format.
///
/// You do not have to implement this — `EasyAds.initialize` defaults to
/// [PrefsEasyAdsStore], which is backed by `shared_preferences`. Implement it
/// only to keep the counters somewhere else (a database, an encrypted store, a
/// backend the caps are shared with):
///
/// ```dart
/// class MyStore implements EasyAdsStore {
///   @override
///   Future<int> readInt(String key) async => ...;
///
///   @override
///   Future<void> writeInt(String key, int value) async => ...;
/// }
/// ```
///
/// Keys are namespaced under `easy_ads.` and hold plain ints.
abstract class EasyAdsStore {
  /// Returns the stored value, or 0 when the key is absent.
  Future<int> readInt(String key);

  /// Persists [value] under [key].
  Future<void> writeInt(String key, int value);
}

/// In-memory [EasyAdsStore]. Everything it holds dies with the process, so
/// session thresholds, daily caps and hourly windows reset on every cold start.
///
/// Pass it explicitly to opt out of persistence; the internal default before a
/// store is installed, and what the unit tests run against.
class MemoryEasyAdsStore implements EasyAdsStore {
  final Map<String, int> _values = {};

  @override
  Future<int> readInt(String key) async => _values[key] ?? 0;

  @override
  Future<void> writeInt(String key, int value) async => _values[key] = value;
}
