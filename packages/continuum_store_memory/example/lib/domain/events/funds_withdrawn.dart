import 'package:continuum/continuum.dart';

import '../account.dart';

/// Event fired when funds are withdrawn from an account.
@AggregateEvent(of: Account, type: 'account.funds_withdrawn')
class FundsWithdrawn extends ContinuumEvent {
  final int amount;

  FundsWithdrawn({
    required super.eventId,
    required this.amount,
    super.occurredOn,
    super.metadata,
  });

  factory FundsWithdrawn.fromJson(Map<String, dynamic> json) {
    return FundsWithdrawn(
      eventId: EventId(json['eventId'] as String),
      amount: json['amount'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'amount': amount};
}
