/// Continuum - Event Sourcing for Dart
///
/// This example demonstrates the core event sourcing pattern using a User
/// aggregate. All packages in Continuum use the same User example for
/// consistency.
///
/// To run this example:
///   cd example
///   dart pub get
///   dart run build_runner build
///   dart run main.dart
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_deactivated.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Creating a User
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Every aggregate starts with a creation event. The event captures the
  // initial state.

  final user = User.createUserRegistered(UserRegistered(eventId: EventId('evt-1'), userId: 'user-123', email: 'alice@example.com', name: 'Alice Smith'));

  print('User registered: ${user.name} <${user.email}>');

  // ─────────────────────────────────────────────────────────────────────────
  // Mutating State with Events
  // ─────────────────────────────────────────────────────────────────────────
  //
  // State changes are represented as events. The aggregate's apply methods
  // update internal state based on each event.

  user.applyEvent(EmailChanged(eventId: EventId('evt-2'), newEmail: 'alice.smith@company.com'));

  print('Email updated to: ${user.email}');

  // ─────────────────────────────────────────────────────────────────────────
  // Deactivating the User
  // ─────────────────────────────────────────────────────────────────────────

  user.applyEvent(UserDeactivated(eventId: EventId('evt-3'), deactivatedAt: DateTime.now(), reason: 'Account closed by user request'));

  print('User active: ${user.isActive}');

  // ─────────────────────────────────────────────────────────────────────────
  // Replaying Events
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Given the same events, we rebuild the exact same state. This is how
  // event stores load aggregates.

  final events = [
    EmailChanged(eventId: EventId('evt-2'), newEmail: 'alice.smith@company.com'),
    UserDeactivated(eventId: EventId('evt-3'), deactivatedAt: DateTime.now(), reason: 'Account closed by user request'),
  ];

  final rebuiltUser = User.createUserRegistered(UserRegistered(eventId: EventId('evt-1'), userId: 'user-123', email: 'alice@example.com', name: 'Alice Smith'));

  rebuiltUser.replayEvents(events);

  print('Rebuilt user email: ${rebuiltUser.email}');
  print('Rebuilt user active: ${rebuiltUser.isActive}');
}
