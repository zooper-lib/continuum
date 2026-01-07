import 'package:continuum/continuum.dart';

import '../account.dart';

/// Event fired when funds are deposited into an account.
@Event(ofAggregate: Account, type: 'account.funds_deposited')
class FundsDeposited extends DomainEvent {
  final int amount;

  FundsDeposited({
    required super.eventId,
    required this.amount,
    super.occurredOn,
    super.metadata,
  });

  factory FundsDeposited.fromJson(Map<String, dynamic> json) {
    return FundsDeposited(
      eventId: EventId(json['eventId'] as String),
      amount: json['amount'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'amount': amount};
}
