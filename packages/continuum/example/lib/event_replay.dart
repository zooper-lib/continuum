// ignore_for_file: file_names

/// Example 3: Rebuilding State by Replaying Events
///
/// This example demonstrates event sourcing's core principle: rebuilding
/// aggregate state by replaying its event history. This is how event stores
/// load aggregates from persistence.
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_deactivated.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';

void main() {
  print('═══════════════════════════════════════════════════════════════════');
  print('Example 3: Rebuilding State by Replaying Events');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // Simulate an event history (as if loaded from an event store)
  print('Event history:');
  final events = <DomainEvent>[
    UserRegistered(
      eventId: const EventId('evt-1'),
      userId: 'user-789',
      email: 'carol@example.com',
      name: 'Carol White',
    ),
    EmailChanged(
      eventId: const EventId('evt-2'),
      newEmail: 'carol.white@newcompany.com',
    ),
    EmailChanged(
      eventId: const EventId('evt-3'),
      newEmail: 'carol.white@finalcompany.com',
    ),
    UserDeactivated(
      eventId: const EventId('evt-4'),
      deactivatedAt: DateTime.now(),
      reason: 'Migration to new system',
    ),
  ];

  for (final event in events) {
    print('  - ${event.runtimeType}');
  }
  print('');

  // Rebuild the aggregate by replaying events
  print('Replaying events to rebuild state...');
  final creationEvent = events.first as UserRegistered;
  final user = User.createFromUserRegistered(creationEvent);

  // Apply all mutation events
  user.replayEvents(events.skip(1));

  print('');
  print('Rebuilt aggregate state:');
  print('  $user');
  print('');

  print('✓ Given the same events, we always rebuild the same state.');
  print('  This is the foundation of event sourcing!');
}
