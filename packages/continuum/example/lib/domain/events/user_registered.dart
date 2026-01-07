import 'package:continuum/continuum.dart';

import '../user.dart';

/// Event fired when a new user registers.
@Event(ofAggregate: User, type: 'user.registered')
class UserRegistered extends DomainEvent {
  final String userId;
  final String email;
  final String name;

  UserRegistered({required super.eventId, required this.userId, required this.email, required this.name, super.occurredOn, super.metadata});

  factory UserRegistered.fromJson(Map<String, dynamic> json) {
    return UserRegistered(
      eventId: EventId(json['eventId'] as String),
      userId: json['userId'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'userId': userId, 'email': email, 'name': name};
}
