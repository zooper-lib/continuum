// ignore_for_file: file_names

/// Example 5: Hybrid Mode - Optimistic Profile Editing
///
/// This example shows instant UI feedback when editing a profile. The frontend
/// applies events locally while the backend request is in flight.
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';
import 'package:continuum_example/hybrid/backend_api.dart';
import 'package:continuum_example/hybrid/dtos.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Example 5: Hybrid Mode - Optimistic Profile Editing');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  final api = BackendApi();

  // Imagine we loaded this user from a previous API call
  print('Initial state (loaded from backend):');
  final existingUser = User.createUserRegistered(
    UserRegistered(
      eventId: const EventId('loaded-evt'),
      userId: 'user-456',
      name: 'Jane Doe',
      email: 'jane@example.com',
    ),
  );

  print('  Email: ${existingUser.email}');
  print('');

  // Step 1: User changes email in the form.
  // Apply event LOCALLY for instant UI update.
  print('Step 1: User changes email in form');
  existingUser.applyEvent(
    EmailChanged(
      eventId: EventId('local-${DateTime.now().millisecondsSinceEpoch}'),
      newEmail: 'jane.doe@company.com',
    ),
  );

  print('  [UI] Instant update: ${existingUser.email}');
  print('  [UI] Saving icon appears...');
  print('');

  // Step 2: Convert to API request (just the changed field)
  print('Step 2: Send update to backend');
  final updateRequest = UpdateUserRequest(email: existingUser.email);
  print('  [API] PATCH /users/user-456 ${updateRequest.toJson()}');
  print('');

  try {
    final updatedUser = await api.updateUser('user-456', updateRequest);
    print('Step 3: Backend confirms');
    print('  [Backend] Updated: ${updatedUser.email}');
    print('  [UI] Remove saving icon');
    print('');
    print('✓ User saw instant feedback, no waiting for network!');
  } on ApiNetworkException catch (e) {
    print('Step 3: Network error');
    print('  [Backend] Error: $e');
    print('  [UI] Show "Save failed. Retry?" button');
    print('  [UI] Optimistic state still visible: ${existingUser.email}');
    print('');
    print('✓ Local state preserved - user can retry without losing changes.');
  }
}
