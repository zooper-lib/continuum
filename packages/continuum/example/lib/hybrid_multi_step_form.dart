// ignore_for_file: file_names

/// Example 6: Hybrid Mode - Multi-Step Forms with Cancel
///
/// This example shows how to use events for multi-step forms where the user
/// can cancel without persisting anything. Events are only applied locally
/// until the user clicks "Submit".
///
/// IMPORTANT: In hybrid mode there's NO EventSourcingStore or Session!
/// The aggregate is just a regular Dart object in memory. When you navigate
/// away, it gets garbage collected automatically if nothing references it.
library;

import 'package:continuum_example/domain/events/email_changed.dart';
import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';

void main() {
  print('═══════════════════════════════════════════════════════════════════');
  print('Example 6: Hybrid Mode - Multi-Step Forms with Cancel');
  print('═══════════════════════════════════════════════════════════════════');
  print('');
  print('User fills out a registration wizard with multiple steps.');
  print('Each step applies events locally. Nothing sent until "Submit".');
  print('');

  // User starts the registration wizard
  print('Step 1: User enters basic info');
  final draftUser = User.createFromUserRegistered(
    UserRegistered(
      userId: 'draft',
      name: 'Draft User',
      email: 'step1@example.com',
    ),
  );
  print('  Current email: ${draftUser.email}');
  print('');

  // User progresses to step 2
  print('Step 2: User updates email');
  draftUser.applyEvent(
    EmailChanged(
      newEmail: 'step2@example.com',
    ),
  );
  print('  Current email: ${draftUser.email}');
  print('');

  // User progresses to step 3
  print('Step 3: User finalizes email');
  draftUser.applyEvent(
    EmailChanged(
      newEmail: 'final@example.com',
    ),
  );
  print('  Current email: ${draftUser.email}');
  print('');

  // User clicks "Cancel"
  print('User clicks "Cancel" button');
  print('  [Action] Navigate away - the draftUser object goes out of scope');
  print('  [Backend] No API calls made');
  print('  [Memory] draftUser has no more references → garbage collected');
  print('');

  print('✓ No cleanup needed! Just let the object go out of scope.');
  print('  Dart\'s GC automatically reclaims memory when nothing references it.');
  print('');
  print('If user clicked "Submit" instead:');
  print('  → Convert draftUser state to CreateUserRequest(...)');
  print('  → Send to backend API');
  print('  → Replace with backend-returned authoritative state');
}
