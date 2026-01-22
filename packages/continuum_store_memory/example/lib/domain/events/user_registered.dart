import 'package:continuum/continuum.dart';

import '../user.dart';

/// Event fired when a new user registers.
@AggregateEvent(of: User, type: 'user.registered', creation: true)
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

  final UserId userId;
  final String email;
  final String name;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory UserRegistered.fromJson(Map<String, dynamic> json) {
    return UserRegistered(
      eventId: EventId.fromJson(json['eventId'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
      userId: UserId(json['userId'] as String),
      email: json['email'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId.value,
    'email': email,
    'name': name,
  };
}
