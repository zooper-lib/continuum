/// Continuum - Event Sourcing for Dart
///
/// This package contains standalone examples demonstrating different aspects
/// of event sourcing with Continuum. Each example is self-contained and runnable.
///
/// OPERATION TARGET FUNDAMENTALS:
///   target_creation.dart     - Creating targets from events
///   target_mutations.dart    - Mutating state by applying events
///   event_replay.dart           - Rebuilding state by replaying event history
///   abstract_interface_targets.dart - Abstract/interface target support
///
/// PERSISTENCE (EventSourcingStore + Session):
///   store_creating_streams.dart     - Creating new target streams
///   store_loading_and_updating.dart - Loading and updating targets
///   store_handling_conflicts.dart   - Detecting concurrency conflicts
///   store_atomic_saves.dart         - Atomic multi-stream saves
///   store_atomic_rollback.dart      - Atomic rollback on conflict
///
/// STATE-BASED PERSISTENCE (StateBasedStore + Adapter):
///   store_state_based.dart                - State-based backend persistence
///   store_state_based_transactional.dart  - State-based with TransactionalRunner
///   store_state_based_local_db.dart       - State-based with local database
///
/// PROJECTIONS (Read Models):
///   projection_example.dart         - Projection with code generation
///
/// HYBRID MODE (Frontend Events + Backend State):
///   (removed - hybrid examples consolidated into state-based examples)
///
/// To run any example:
///   cd example
///   dart pub get
///   dart run build_runner build
///   dart run <example_name>.dart
library;

void main() {
  print('═══════════════════════════════════════════════════════════════════');
  print('Continuum Examples');
  print('═══════════════════════════════════════════════════════════════════');
  print('');
  print('OPERATION TARGET FUNDAMENTALS:');
  print('  target_creation.dart     - Creating targets from events');
  print('  target_mutations.dart    - Mutating state by applying events');
  print('  event_replay.dart           - Rebuilding state by replaying history');
  print('  abstract_interface_targets.dart - Abstract/interface target support');
  print('');
  print('PERSISTENCE (EventSourcingStore + Session):');
  print('  store_creating_streams.dart     - Creating target streams');
  print('  store_loading_and_updating.dart - Loading and updating');
  print('  store_handling_conflicts.dart   - Conflict detection');
  print('  store_atomic_saves.dart         - Atomic multi-stream saves');
  print('  store_atomic_rollback.dart      - Atomic rollback on conflict');
  print('');
  print('STATE-BASED PERSISTENCE (StateBasedStore + Adapter):');
  print('  store_state_based.dart                - State-based backend persistence');
  print('  store_state_based_transactional.dart  - State-based with TransactionalRunner');
  print('  store_state_based_local_db.dart       - State-based with local database');
  print('');
  print('PROJECTIONS (Read Models):');
  print('  projection_example.dart         - Projection with code generation');
  print('');
  print('HYBRID MODE (Frontend Events + Backend State):');
  print('  (removed - see store_state_based_transactional.dart)');
  print('');
  print('Run any example:');
  print('  dart run target_creation.dart');
  print('');
}
