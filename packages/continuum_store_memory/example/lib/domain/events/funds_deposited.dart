import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

import '../account.dart';

/// Event fired when funds are deposited into an account.
@AggregateEvent(of: Account, type: 'account.funds_deposited')
class FundsDeposited implements ContinuumEvent {
  FundsDeposited({
    required this.amount,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final int amount;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory FundsDeposited.fromJson(Map<String, dynamic> json) {
    return FundsDeposited(eventId: EventId(json['eventId'] as String), amount: json['amount'] as int);
  }

  Map<String, dynamic> toJson() => {'amount': amount};
}
