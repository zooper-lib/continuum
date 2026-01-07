/// Example 2: Applying Events to Change State
///
/// This example shows how to mutate aggregate state by applying events.
/// Each event represents a state transition with business meaning.
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_deactivated.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';

void main() {
  print('═══════════════════════════════════════════════════════════════════');
  print('Example 2: Applying Events to Change State');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // Start with a user
  final user = User.createUserRegistered(
    UserRegistered(
      eventId: const EventId('evt-1'),
      userId: 'user-456',
      email: 'bob@example.com',
      name: 'Bob Johnson',
    ),
  );

  print('Initial state:');
  print('  $user');
  print('');

  // Apply an event to change the email
  print('Applying EmailChanged event...');
  user.applyEvent(
    EmailChanged(
      eventId: const EventId('evt-2'),
      newEmail: 'bob.johnson@company.com',
    ),
  );

  print('After email change:');
  print('  $user');
  print('');

  // Apply another event to deactivate the account
  print('Applying UserDeactivated event...');
  user.applyEvent(
    UserDeactivated(
      eventId: const EventId('evt-3'),
      deactivatedAt: DateTime.now(),
      reason: 'User requested account closure',
    ),
  );

  print('After deactivation:');
  print('  $user');
  print('');

  print('✓ Each event represents a meaningful business state transition.');
}
