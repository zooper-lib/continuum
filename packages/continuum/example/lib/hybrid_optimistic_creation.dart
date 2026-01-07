// ignore_for_file: file_names

/// Example 4: Hybrid Mode - Optimistic User Creation
///
/// This example demonstrates hybrid mode where the frontend uses events for
/// local state modeling but sends DTOs (not events) to the backend. The backend
/// is the source of truth.
library;

import 'package:continuum/continuum.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';
import 'package:continuum_example/hybrid/backend_api.dart';
import 'package:continuum_example/hybrid/dtos.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════════');
  print('Example 4: Hybrid Mode - Optimistic User Creation');
  print('═══════════════════════════════════════════════════════════════════');
  print('');
  print('Frontend events are for LOCAL STATE only.');
  print('Backend has its own events - we just get the resulting state.');
  print('');

  final api = BackendApi();

  // Step 1: User fills out registration form.
  // Show the new user immediately using a local event (optimistic update).
  print('Step 1: User fills out form');
  final optimisticUser = User.createFromUserRegistered(
    UserRegistered(
      eventId: EventId('temp-${DateTime.now().millisecondsSinceEpoch}'),
      userId: 'temp-new-user',
      name: 'Jane Doe',
      email: 'jane@example.com',
    ),
  );

  print('  [UI] Showing optimistic state: ${optimisticUser.name}');
  print('  [UI] Spinner indicates "Saving..."');
  print('');

  // Step 2: Convert aggregate state to API request (NOT the event!)
  print('Step 2: Send request to backend');
  final createRequest = CreateUserRequest(
    name: optimisticUser.name,
    email: optimisticUser.email,
  );

  print('  [API] POST /users ${createRequest.toJson()}');
  print('');

  try {
    // Step 3: Call the backend
    final backendUser = await api.createUser(createRequest);

    // Step 4: SUCCESS! Discard optimistic state, use backend state.
    print('Step 3: Backend responds');
    print('  [Backend] Created user with ID: ${backendUser.id}');
    print('  [UI] Replace optimistic state with authoritative backend state');
    print('');
    print('✓ Success! User sees instant feedback, backend remains source of truth.');
  } on ApiValidationException catch (e) {
    print('Step 3: Backend error');
    print('  [Backend] Validation error: $e');
    print('  [UI] Show error message, user can fix and retry');
    print('');
    print('✓ Local state preserved for retry.');
  }
}
