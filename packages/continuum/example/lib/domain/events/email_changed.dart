import 'package:continuum/continuum.dart';

import '../user.dart';

/// Event fired when a user changes their email address.
@AggregateEvent(of: User, type: 'user.email_changed')
class EmailChanged extends ContinuumEvent {
  final String newEmail;

  EmailChanged({required super.eventId, required this.newEmail, super.occurredOn, super.metadata});

  factory EmailChanged.fromJson(Map<String, dynamic> json) {
    return EmailChanged(eventId: EventId(json['eventId'] as String), newEmail: json['newEmail'] as String);
  }

  Map<String, dynamic> toJson() => {'newEmail': newEmail};
}
