import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

import '../user.dart';

/// Event fired when a user account is deactivated.
@AggregateEvent(of: User, type: 'user.deactivated')
class UserDeactivated implements ContinuumEvent {
  UserDeactivated({
    required this.deactivatedAt,
    this.reason,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final DateTime deactivatedAt;
  final String? reason;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory UserDeactivated.fromJson(Map<String, dynamic> json) {
    return UserDeactivated(
      eventId: EventId(json['eventId'] as String),
      deactivatedAt: DateTime.parse(json['deactivatedAt'] as String),
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'deactivatedAt': deactivatedAt.toIso8601String(), if (reason != null) 'reason': reason};
}
