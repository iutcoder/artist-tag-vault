/// Account balances and V5 allowance returned by `GET /user/subscription`.
class AccountUsage {
  const AccountUsage({
    required this.tier,
    required this.active,
    required this.subscriptionAnlas,
    required this.paidAnlas,
    required this.v5Percent,
    required this.v5Unavailable,
    required this.secondsUntilNextPercent,
  });

  factory AccountUsage.fromJson(Map<String, dynamic> json) {
    final balances = json['trainingStepsLeft'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final usage = json['usage'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return AccountUsage(
      tier: (json['tier'] as num?)?.toInt(),
      active: json['active'] as bool? ?? false,
      // The API retains legacy training-step field names for Image Anlas.
      subscriptionAnlas:
          (balances['fixedTrainingStepsLeft'] as num?)?.toInt() ?? 0,
      paidAnlas: (balances['purchasedTrainingSteps'] as num?)?.toInt() ?? 0,
      v5Percent: (usage['percent'] as num?)?.toInt(),
      v5Unavailable: usage['isNegative'] as bool? ?? false,
      secondsUntilNextPercent:
          (usage['timeUntilNextPercent'] as num?)?.toInt(),
    );
  }

  final int? tier;
  final bool active;
  final int subscriptionAnlas;
  final int paidAnlas;
  final int? v5Percent;
  final bool v5Unavailable;
  final int? secondsUntilNextPercent;

  int get totalAnlas => subscriptionAnlas + paidAnlas;

  String get tierLabel => switch (tier) {
        0 => 'Paper',
        1 => 'Tablet',
        2 => 'Scroll',
        3 => 'Opus',
        _ => active ? 'Active subscription' : 'No subscription',
      };
}
