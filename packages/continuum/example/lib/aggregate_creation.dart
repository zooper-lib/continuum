/// Example 1: Creating Aggregates
///
/// This example shows how to create an aggregate from a creation event.
/// Every aggregate starts with a creation event that captures its initial state.
library;

import 'package:continuum_example/domain/events/user_registered.dart';
import 'package:continuum_example/domain/user.dart';

void main() {
  print('═══════════════════════════════════════════════════════════════════');
  print('Example 1: Creating Aggregates from Events');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  // Every aggregate begins its life with a creation event.
  // The creation event captures all the data needed to initialize the aggregate.
  final user = User.createFromUserRegistered(
    UserRegistered(
      userId: 'user-123',
      email: 'alice@example.com',
      name: 'Alice Smith',
    ),
  );

  print('User created:');
  print('  $user');
  print('');

  print('✓ The aggregate is now in memory and ready for mutations.');
}
