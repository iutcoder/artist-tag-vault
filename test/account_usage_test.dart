import 'package:artist_tag_vault/src/models/account_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Anlas balances and V5 allowance', () {
    final usage = AccountUsage.fromJson({
      'tier': 3,
      'active': true,
      'trainingStepsLeft': {
        'fixedTrainingStepsLeft': 8000,
        'purchasedTrainingSteps': 250,
      },
      'usage': {
        'percent': 73,
        'isNegative': false,
        'timeUntilNextPercent': 420,
      },
    });

    expect(usage.totalAnlas, 8250);
    expect(usage.tierLabel, 'Opus');
    expect(usage.v5Percent, 73);
    expect(usage.secondsUntilNextPercent, 420);
  });
}
