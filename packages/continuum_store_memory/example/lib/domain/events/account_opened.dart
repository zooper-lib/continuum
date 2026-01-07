import 'package:continuum/continuum.dart';

import '../account.dart';

/// Event fired when a new account is opened.
@Event(ofAggregate: Account, type: 'account.opened')
class AccountOpened extends DomainEvent {
  final String accountId;
  final String ownerId;

  AccountOpened({required super.eventId, required this.accountId, required this.ownerId, super.occurredOn, super.metadata});

  factory AccountOpened.fromJson(Map<String, dynamic> json) {
    return AccountOpened(eventId: EventId(json['eventId'] as String), accountId: json['accountId'] as String, ownerId: json['ownerId'] as String);
  }

  Map<String, dynamic> toJson() => {'accountId': accountId, 'ownerId': ownerId};
}
