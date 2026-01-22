/// Continuum - Event Sourcing for Dart
///
/// This package contains standalone examples demonstrating different aspects
/// of event sourcing with Continuum. Each example is self-contained and runnable.
///
/// AGGREGATE FUNDAMENTALS:
///   aggregate_creation.dart     - Creating aggregates from events
///   aggregate_mutations.dart    - Mutating state by applying events
///   event_replay.dart           - Rebuilding state by replaying event history
///   abstract_interface_aggregates.dart - Abstract/interface aggregate support
///
/// PERSISTENCE (EventSourcingStore + Session):
///   store_creating_streams.dart     - Creating new aggregate streams
///   store_loading_and_updating.dart - Loading and updating aggregates
///   store_handling_conflicts.dart   - Detecting concurrency conflicts
///   store_atomic_saves.dart         - Atomic multi-stream saves
///   store_atomic_rollback.dart      - Atomic rollback on conflict
///
/// PROJECTIONS (Read Models):
///   projection_example.dart         - Projection with code generation
///
/// HYBRID MODE (Frontend Events + Backend State):
///   hybrid_optimistic_creation.dart - Optimistic user creation
///   hybrid_profile_edit.dart        - Instant feedback when editing
///   hybrid_multi_step_form.dart     - Multi-step forms with cancel
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
  print('AGGREGATE FUNDAMENTALS:');
  print('  aggregate_creation.dart     - Creating aggregates from events');
  print('  aggregate_mutations.dart    - Mutating state by applying events');
  print('  event_replay.dart           - Rebuilding state by replaying history');
  print('  abstract_interface_aggregates.dart - Abstract/interface support');
  print('');
  print('PERSISTENCE (EventSourcingStore + Session):');
  print('  store_creating_streams.dart     - Creating aggregate streams');
  print('  store_loading_and_updating.dart - Loading and updating');
  print('  store_handling_conflicts.dart   - Conflict detection');
  print('  store_atomic_saves.dart         - Atomic multi-stream saves');
  print('  store_atomic_rollback.dart      - Atomic rollback on conflict');
  print('');
  print('PROJECTIONS (Read Models):');
  print('  projection_example.dart         - Projection with code generation');
  print('');
  print('HYBRID MODE (Frontend Events + Backend State):');
  print('  hybrid_optimistic_creation.dart - Optimistic user creation');
  print('  hybrid_profile_edit.dart        - Instant feedback editing');
  print('  hybrid_multi_step_form.dart     - Multi-step forms with cancel');
  print('');
  print('Run any example:');
  print('  dart run aggregate_creation.dart');
  print('');
}
