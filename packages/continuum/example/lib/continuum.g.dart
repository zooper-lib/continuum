// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: type=lint

import 'package:continuum/continuum.dart';

import 'abstract_interface_aggregates.dart';
import 'domain/user.dart';
import 'abstract_interface_aggregates.dart';

/// All discovered aggregates in this package.
///
/// Pass this list to [EventSourcingStore] for automatic
/// registration of all serializers, factories, and appliers.
///
/// ```dart
/// final store = EventSourcingStore(
///   eventStore: InMemoryEventStore(),
///   aggregates: $aggregateList,
/// );
/// ```
final List<GeneratedAggregate> $aggregateList = [
  $AbstractUserBase,
  $User,
  $UserContract,
];
