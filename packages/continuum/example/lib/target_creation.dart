/// Example 1: Creating Targets
///
/// This example shows how to create a target from a creation event.
/// Every target starts with a creation event that captures its initial state.
library;

import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';

void main() {
  print('═══════════════════════════════════════════════════════════════════');
  print('Example 1: Creating Targets from Events');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // Every target begins its life with a creation event.
  // The creation event captures all the data needed to initialize the target.
  final user = User.createFromUserRegistered(
    UserRegistered(
      userId: const UserId('user-123'),
      email: 'alice@example.com',
      name: 'Alice Smith',
    ),
  );

  print('User created:');
  print('  $user');
  print('');

  print('✓ The target is now in memory and ready for mutations.');
}
