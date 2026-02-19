import 'package:continuum/continuum.dart';

import '../user.dart';

/// Event fired when a user changes their email address.
@AggregateEvent(of: User, type: 'user.email_changed')
class EmailChanged implements ContinuumEvent {
  EmailChanged({
    required this.newEmail,
    this.userId,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  /// The user this event belongs to.
  ///
  /// Optional because the aggregate context provides the stream ID
  /// during event sourcing. Required for projection key extraction
  /// when events are processed outside the aggregate context.
  final UserId? userId;
  
  final String newEmail;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory EmailChanged.fromJson(Map<String, dynamic> json) {
    return EmailChanged(
      newEmail: json['newEmail'] as String,
      eventId: EventId(json['eventId'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }

  Map<String, dynamic> toJson() => {
    'newEmail': newEmail,
    'eventId': id.value,
    'occurredOn': occurredOn.toIso8601String(),
    'metadata': metadata,
  };
}
