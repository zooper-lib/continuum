import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

import '../user.dart';

/// Event fired when a new user registers.
@AggregateEvent(of: User, type: 'user.registered')
class UserRegistered implements ContinuumEvent {
  UserRegistered({
    required this.userId,
    required this.email,
    required this.name,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  factory UserRegistered.fromJson(Map<String, dynamic> json) {
    return UserRegistered(
      userId: json['userId'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      eventId: EventId(json['eventId'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.unmodifiable(json['metadata'] as Map<String, Object?>),
    );
  }

  final String userId;
  final String email;
  final String name;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'email': email,
    'name': name,
    'eventId': id,
    'occurredOn': occurredOn.toIso8601String(),
    'metadata': metadata,
  };
}
