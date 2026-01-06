/// Hybrid Mode Example - Backend as Source of Truth
///
/// This example demonstrates **Mode 3** from the Continuum specification:
/// The backend does event sourcing internally, but returns aggregate state
/// (not events) to the frontend. The frontend uses Continuum for optimistic
/// UI updates while the backend remains the source of truth.
///
/// **Key insight:** Frontend events are NOT sent to the backend!
/// They exist only for local state modeling. When calling the backend,
/// you convert the aggregate state to a regular API request.
///
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │ FRONTEND                                                    │
/// │                                                             │
/// │ User types → EmailChanged event → UI shows new email       │
/// │                    │                                        │
/// │                    ▼                                        │
/// │ Convert to: UpdateUserRequest { email: "new@example.com" } │
/// └─────────────────────────────────────────────────────────────┘
///                      │ HTTP POST
///                      ▼
/// ┌─────────────────────────────────────────────────────────────┐
/// │ BACKEND (does its own event sourcing internally)           │
/// │                                                             │
/// │ Validates → Creates own EmailChangedEvent → Persists       │
/// │                    │                                        │
/// │                    ▼                                        │
/// │ Returns: { id, name, email, ... } (aggregate JSON)         │
/// └─────────────────────────────────────────────────────────────┘
///                      │
///                      ▼
/// ┌─────────────────────────────────────────────────────────────┐
/// │ FRONTEND                                                    │
/// │                                                             │
/// │ Discard local events → Use backend-returned state          │
/// └─────────────────────────────────────────────────────────────┘
/// ```
///
/// To run this example:
///   cd example
///   dart pub get
///   dart run build_runner build
///   dart run hybrid_mode_example.dart
library;

import 'dart:math';

import 'package:continuum/continuum.dart';
import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HYBRID MODE IN ACTION
// ═══════════════════════════════════════════════════════════════════════════
//
// In hybrid mode, we DON'T need EventSourcingStore or EventStore at all!
// We just use aggregates + events for local state management.
// The "persistence" is the backend.

void main() async {
  final api = BackendApi();

  print('═══════════════════════════════════════════════════════════════════');
  print('HYBRID MODE: Backend as Source of Truth');
  print('═══════════════════════════════════════════════════════════════════');
  print('');
  print('Frontend events are for LOCAL STATE only.');
  print('Backend has its own events - we just get the resulting state.');
  print('');

  // ─────────────────────────────────────────────────────────────────────────
  // SCENARIO 1: Create User with Optimistic UI
  // ─────────────────────────────────────────────────────────────────────────

  print('SCENARIO 1: Optimistic User Creation');
  print('─────────────────────────────────────');

  // Step 1: User fills out registration form.
  // We can show the new user immediately using a local event.
  final optimisticUser = User.createUserRegistered(
    UserRegistered(
      eventId: EventId('temp-${DateTime.now().millisecondsSinceEpoch}'),
      userId: 'temp-new-user', // Temporary ID
      name: 'Jane Doe',
      email: 'jane@example.com',
    ),
  );

  print('  [UI] Showing optimistic state: ${optimisticUser.name}');
  print('  [UI] Spinner indicates "Saving..."');

  // Step 2: Convert aggregate state to API request.
  // NOTE: We send a REQUEST, not the event!
  final createRequest = CreateUserRequest(
    name: optimisticUser.name,
    email: optimisticUser.email,
  );

  print('  [API] Sending: ${createRequest.toJson()}');

  try {
    // Step 3: Call the backend
    final backendUser = await api.createUser(createRequest);

    // Step 4: SUCCESS! Discard optimistic state, use backend state.
    // In a real app, you'd update your state management here.
    print('  [Backend] Created user with ID: ${backendUser.id}');
    print('  [UI] Now showing authoritative state from backend');
    print('  ✓ Success!');
  } on ApiValidationException catch (e) {
    print('  [Backend] Validation error: $e');
    print('  [UI] Showing error, user can fix and retry');
  }

  print('');

  // ─────────────────────────────────────────────────────────────────────────
  // SCENARIO 2: Edit Profile with Instant Feedback
  // ─────────────────────────────────────────────────────────────────────────

  print('SCENARIO 2: Edit Profile with Instant Feedback');
  print('───────────────────────────────────────────────');

  // Imagine we loaded this user from a previous API call
  final existingUser = User.createUserRegistered(
    UserRegistered(
      eventId: const EventId('loaded-evt'),
      userId: 'user-456',
      name: 'Jane Doe',
      email: 'jane@example.com',
    ),
  );

  print('  [Initial] Email: ${existingUser.email}');

  // Step 1: User changes email in the form.
  // Apply event LOCALLY for instant UI update.
  existingUser.applyEvent(
    EmailChanged(
      eventId: EventId('local-${DateTime.now().millisecondsSinceEpoch}'),
      newEmail: 'jane.doe@company.com',
    ),
  );

  print('  [UI] Optimistic update: ${existingUser.email} (saving...)');

  // Step 2: Convert to API request (just the changed field)
  final updateRequest = UpdateUserRequest(email: existingUser.email);

  print('  [API] Sending: ${updateRequest.toJson()}');

  try {
    final updatedUser = await api.updateUser('user-456', updateRequest);
    print('  [Backend] Confirmed: ${updatedUser.email}');
    print('  ✓ Success!');
  } on ApiNetworkException catch (e) {
    print('  [Backend] Network error: $e');
    print('  [UI] "Save failed. Retry?" - optimistic state still shown');
    // User can retry - we still have the local state
  }

  print('');

  // ─────────────────────────────────────────────────────────────────────────
  // SCENARIO 3: Multi-Step Wizard with Undo
  // ─────────────────────────────────────────────────────────────────────────

  print('SCENARIO 3: Multi-Step Form with Cancel');
  print('────────────────────────────────────────');

  // User is filling out a multi-step registration wizard.
  // Each step applies an event locally.
  // Nothing is sent to backend until they click "Submit".

  final draftUser = User.createUserRegistered(
    UserRegistered(
      eventId: const EventId('draft-1'),
      userId: 'draft',
      name: 'Draft User',
      email: 'step1@example.com',
    ),
  );
  print('  [Step 1] Created: ${draftUser.email}');

  // User changes email on step 2
  draftUser.applyEvent(
    EmailChanged(eventId: const EventId('draft-2'), newEmail: 'step2@example.com'),
  );
  print('  [Step 2] Changed to: ${draftUser.email}');

  // User changes email again on step 3
  draftUser.applyEvent(
    EmailChanged(eventId: const EventId('draft-3'), newEmail: 'final@example.com'),
  );
  print('  [Step 3] Changed to: ${draftUser.email}');

  // User clicks "Cancel" - we just don't call the API!
  print('  [User] Clicks "Cancel"');
  print('  [Result] Nothing sent to backend. Draft discarded.');
  print('  ✓ No cleanup needed - local state is just garbage collected');

  print('');

  // ─────────────────────────────────────────────────────────────────────────
  // KEY TAKEAWAYS
  // ─────────────────────────────────────────────────────────────────────────

  print('═══════════════════════════════════════════════════════════════════');
  print('KEY TAKEAWAYS');
  print('═══════════════════════════════════════════════════════════════════');
  print('');
  print('1. Frontend events are for LOCAL STATE MODELING only');
  print('2. Backend does its own event sourcing - you never see those events');
  print('3. Convert aggregate state → API request (DTO), not events');
  print('4. On success: replace local state with backend response');
  print('5. On error: keep local state for retry/undo');
  print('6. No EventStore needed! Just aggregates + events + API client');
  print('');
  print('This pattern gives you:');
  print('  • Instant UI feedback (optimistic updates)');
  print('  • Type-safe state transitions');
  print('  • Easy undo (just don\'t send to backend)');
  print('  • Consistent domain model');
  print('');
}

// ═══════════════════════════════════════════════════════════════════════════
// SIMULATED BACKEND API (scroll down - this is just for the example)
// ═══════════════════════════════════════════════════════════════════════════
//
// Everything below simulates a backend. In a real app, this would be your
// HTTP client (e.g., Dio, http package). The backend does its own event
// sourcing internally - we never see those events.

class BackendApi {
  final _random = Random();

  Future<UserDto> createUser(CreateUserRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (request.email.contains('invalid')) {
      throw ApiValidationException('Email domain not allowed');
    }
    return UserDto(
      id: 'user-${_random.nextInt(10000)}',
      name: request.name,
      email: request.email,
      isActive: true,
    );
  }

  Future<UserDto> updateUser(String userId, UpdateUserRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_random.nextDouble() < 0.1) {
      throw ApiNetworkException('Connection timeout');
    }
    return UserDto(
      id: userId,
      name: request.name ?? 'Jane Doe',
      email: request.email ?? 'existing@example.com',
      isActive: true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DTOs - What the backend sends/receives
// ─────────────────────────────────────────────────────────────────────────────

class CreateUserRequest {
  final String name;
  final String email;
  CreateUserRequest({required this.name, required this.email});
  Map<String, dynamic> toJson() => {'name': name, 'email': email};
}

class UpdateUserRequest {
  final String? name;
  final String? email;
  UpdateUserRequest({this.name, this.email});
  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (email != null) 'email': email,
  };
}

class UserDto {
  final String id;
  final String name;
  final String email;
  final bool isActive;
  UserDto({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
  });
}

class ApiValidationException implements Exception {
  final String message;
  ApiValidationException(this.message);
  @override
  String toString() => message;
}

class ApiNetworkException implements Exception {
  final String message;
  ApiNetworkException(this.message);
  @override
  String toString() => message;
}
