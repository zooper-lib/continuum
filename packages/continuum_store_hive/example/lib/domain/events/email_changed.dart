import 'package:continuum/continuum.dart';

import '../user.dart';

/// Event fired when a user changes their email address.
@AggregateEvent(of: User, type: 'user.email_changed')
class EmailChanged implements ContinuumEvent {
  EmailChanged({
    required this.newEmail,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String newEmail;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory EmailChanged.fromJson(Map<String, dynamic> json) {
    return EmailChanged(
      eventId: EventId.fromJson(json['eventId'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
      newEmail: json['newEmail'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'newEmail': newEmail,
  };
}
