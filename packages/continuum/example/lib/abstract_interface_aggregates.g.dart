// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'abstract_interface_aggregates.dart';

// **************************************************************************
// ContinuumGenerator
// **************************************************************************

/// Generated mixin requiring apply methods for AbstractUserBase mutation events.
///
/// Implement this mixin and provide the required apply methods.
mixin _$AbstractUserBaseEventHandlers {
  /// Applies a AbstractUserEmailChanged event to this aggregate.
  void applyAbstractUserEmailChanged(AbstractUserEmailChanged event);
}

/// Generated extension providing event dispatch for AbstractUserBase.
extension $AbstractUserBaseEventDispatch on AbstractUserBase {
  /// Applies a continuum event to this aggregate.
  ///
  /// Routes supported mutation events to the corresponding apply method.
  /// Throws [UnsupportedEventException] for unknown event types.
  void applyEvent(ContinuumEvent event) {
    switch (event) {
      case AbstractUserEmailChanged():
        applyAbstractUserEmailChanged(event);
      default:
        throw UnsupportedEventException(
          eventType: event.runtimeType,
          aggregateType: AbstractUserBase,
        );
    }
  }

  /// Replays multiple events in order.
  ///
  /// Applies each event sequentially via [applyEvent].
  void replayEvents(Iterable<ContinuumEvent> events) {
    for (final event in events) {
      applyEvent(event);
    }
  }
}

/// Generated extension providing creation dispatch for AbstractUserBase.
extension $AbstractUserBaseCreation on Never {
  /// Creates a AbstractUserBase from a creation event.
  ///
  /// Routes to the appropriate static createFrom<Event> method.
  /// Throws [InvalidCreationEventException] for unknown event types.
  static AbstractUserBase createFromEvent(ContinuumEvent event) {
    switch (event) {
      default:
        throw InvalidCreationEventException(
          eventType: event.runtimeType,
          aggregateType: AbstractUserBase,
        );
    }
  }
}

/// Generated aggregate bundle for AbstractUserBase.
///
/// Contains all serializers, factories, and appliers for this aggregate.
/// Add to the `aggregates` list when creating an [EventSourcingStore].
final $AbstractUserBase = GeneratedAggregate(
  serializerRegistry: EventSerializerRegistry({
    AbstractUserEmailChanged: EventSerializerEntry(
      eventType: 'example.abstract_user.email_changed',
      toJson: (event) => (event as AbstractUserEmailChanged).toJson(),
      fromJson: AbstractUserEmailChanged.fromJson,
    ),
  }),
  aggregateFactories: AggregateFactoryRegistry({}),
  eventAppliers: EventApplierRegistry({
    AbstractUserBase: {
      AbstractUserEmailChanged: (aggregate, event) =>
          (aggregate as AbstractUserBase).applyAbstractUserEmailChanged(
            event as AbstractUserEmailChanged,
          ),
    },
  }),
);

/// Generated mixin requiring apply methods for UserContract mutation events.
///
/// Implement this mixin and provide the required apply methods.
mixin _$UserContractEventHandlers {
  /// Applies a ContractUserRenamed event to this aggregate.
  void applyContractUserRenamed(ContractUserRenamed event);
}

/// Generated extension providing event dispatch for UserContract.
extension $UserContractEventDispatch on UserContract {
  /// Applies a continuum event to this aggregate.
  ///
  /// Routes supported mutation events to the corresponding apply method.
  /// Throws [UnsupportedEventException] for unknown event types.
  void applyEvent(ContinuumEvent event) {
    switch (event) {
      case ContractUserRenamed():
        applyContractUserRenamed(event);
      default:
        throw UnsupportedEventException(
          eventType: event.runtimeType,
          aggregateType: UserContract,
        );
    }
  }

  /// Replays multiple events in order.
  ///
  /// Applies each event sequentially via [applyEvent].
  void replayEvents(Iterable<ContinuumEvent> events) {
    for (final event in events) {
      applyEvent(event);
    }
  }
}

/// Generated extension providing creation dispatch for UserContract.
extension $UserContractCreation on Never {
  /// Creates a UserContract from a creation event.
  ///
  /// Routes to the appropriate static createFrom<Event> method.
  /// Throws [InvalidCreationEventException] for unknown event types.
  static UserContract createFromEvent(ContinuumEvent event) {
    switch (event) {
      default:
        throw InvalidCreationEventException(
          eventType: event.runtimeType,
          aggregateType: UserContract,
        );
    }
  }
}

/// Generated aggregate bundle for UserContract.
///
/// Contains all serializers, factories, and appliers for this aggregate.
/// Add to the `aggregates` list when creating an [EventSourcingStore].
final $UserContract = GeneratedAggregate(
  serializerRegistry: EventSerializerRegistry({
    ContractUserRenamed: EventSerializerEntry(
      eventType: 'example.contract_user.renamed',
      toJson: (event) => (event as ContractUserRenamed).toJson(),
      fromJson: ContractUserRenamed.fromJson,
    ),
  }),
  aggregateFactories: AggregateFactoryRegistry({}),
  eventAppliers: EventApplierRegistry({
    UserContract: {
      ContractUserRenamed: (aggregate, event) => (aggregate as UserContract)
          .applyContractUserRenamed(event as ContractUserRenamed),
    },
  }),
);
