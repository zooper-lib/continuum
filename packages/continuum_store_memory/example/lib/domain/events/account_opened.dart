import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

import '../account.dart';

/// Event fired when a new account is opened.
@AggregateEvent(of: Account, type: 'account.opened')
class AccountOpened implements ContinuumEvent {
  AccountOpened({
    required this.accountId,
    required this.ownerId,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  factory AccountOpened.fromJson(Map<String, dynamic> json) {
    return AccountOpened(
      eventId: EventId(json['eventId'] as String),
      accountId: json['accountId'] as String,
      ownerId: json['ownerId'] as String,
    );
  }

  final String accountId;
  final String ownerId;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() => {'accountId': accountId, 'ownerId': ownerId};
}
