/// What the user earned from a rewarded (interstitial) ad.
class EasyAdReward {
  /// Creates a reward.
  const EasyAdReward({required this.amount, required this.type});

  /// The amount configured on the ad unit in the AdMob dashboard.
  final num amount;

  /// The reward's label, e.g. `coins`.
  final String type;

  @override
  String toString() => 'EasyAdReward($amount $type)';
}
