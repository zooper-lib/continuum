import 'package:continuum/continuum.dart';

import '../user.dart';

/// Event fired when a user account is deactivated.
@Event(ofAggregate: User, type: 'user.deactivated')
class UserDeactivated extends DomainEvent {
  final DateTime deactivatedAt;
  final String? reason;

  UserDeactivated({
    required super.eventId,
    required this.deactivatedAt,
    this.reason,
    super.occurredOn,
    super.metadata,
  });

  factory UserDeactivated.fromJson(Map<String, dynamic> json) {
    return UserDeactivated(
      eventId: EventId(json['eventId'] as String),
      deactivatedAt: DateTime.parse(json['deactivatedAt'] as String),
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'deactivatedAt': deactivatedAt.toIso8601String(),
    if (reason != null) 'reason': reason,
  };
}
