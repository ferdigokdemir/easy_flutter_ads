/// Persistence hook for the values that must survive an app restart: the
/// number of sessions so far, per-day show caps, and the last impression of
/// each cooldown-gated format.
///
/// The package deliberately does not depend on `shared_preferences` — supply a
/// thin adapter instead:
///
/// ```dart
/// class PrefsStore implements EasyAdsStore {
///   @override
///   Future<int> readInt(String key) async =>
///       (await SharedPreferences.getInstance()).getInt(key) ?? 0;
///
///   @override
///   Future<void> writeInt(String key, int value) async =>
///       (await SharedPreferences.getInstance()).setInt(key, value);
/// }
/// ```
///
/// With the default [MemoryEasyAdsStore] everything resets on every cold
/// start, which makes session thresholds, daily caps, and cooldowns
/// ineffective.
abstract class EasyAdsStore {
  /// Returns the stored value, or 0 when the key is absent.
  Future<int> readInt(String key);

  /// Persists [value] under [key].
  Future<void> writeInt(String key, int value);
}

/// In-memory [EasyAdsStore] used when the host app supplies none.
class MemoryEasyAdsStore implements EasyAdsStore {
  final Map<String, int> _values = {};

  @override
  Future<int> readInt(String key) async => _values[key] ?? 0;

  @override
  Future<void> writeInt(String key, int value) async => _values[key] = value;
}
