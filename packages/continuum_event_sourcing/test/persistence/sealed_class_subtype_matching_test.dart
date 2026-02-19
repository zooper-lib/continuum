import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test fixtures simulating a Freezed-like sealed class hierarchy.
//
// In real Freezed usage, the user annotates `@AggregateEvent(...)` on the
// public sealed base class (e.g., `ItemCreatedEvent`). Freezed then generates
// PRIVATE subclasses (e.g., `_PhysicalItemCreatedEvent`) for each factory
// constructor. At runtime, `event.runtimeType` returns the private subclass
// type, NOT the annotated base class type. The registries must handle this
// by matching via `is` predicates when exact `runtimeType` lookup fails.
// ---------------------------------------------------------------------------

/// Aggregate used in sealed-class subtype matching tests.
final class Item {
  final String name;
  final String kind;
  int quantity;

  /// Creates an Item.
  Item({required this.name, required this.kind, this.quantity = 0});
}

// -- Creation event: sealed base with two "Freezed-like" subtypes -----------

/// Sealed base event annotated with `@AggregateEvent(creation: true)`.
///
/// In production, Freezed generates the subclasses. Here we simulate
/// the pattern manually so we can test the subtype matching logic.
sealed class ItemCreatedEvent implements ContinuumEvent {
  /// The item name carried by all variants.
  String get name;
}

/// Simulates `_PhysicalItemCreatedEvent` — a Freezed-generated subclass.
final class PhysicalItemCreatedEvent implements ItemCreatedEvent {
  PhysicalItemCreatedEvent({
    required this.name,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final String name;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  /// Deserialization factory.
  factory PhysicalItemCreatedEvent.fromJson(Map<String, dynamic> json) {
    return PhysicalItemCreatedEvent(
      eventId: EventId(json['eventId'] as String),
      name: json['name'] as String,
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }
}

/// Simulates `_DigitalItemCreatedEvent` — another Freezed-generated subclass.
final class DigitalItemCreatedEvent implements ItemCreatedEvent {
  DigitalItemCreatedEvent({
    required this.name,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final String name;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  /// Deserialization factory.
  factory DigitalItemCreatedEvent.fromJson(Map<String, dynamic> json) {
    return DigitalItemCreatedEvent(
      eventId: EventId(json['eventId'] as String),
      name: json['name'] as String,
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }
}

// -- Mutation event: sealed base with two "Freezed-like" subtypes -----------

/// Sealed base mutation event.
sealed class ItemQuantityChangedEvent implements ContinuumEvent {
  /// The quantity delta carried by all variants.
  int get delta;
}

/// Simulates a Freezed subclass for quantity increase.
final class ItemQuantityIncreasedEvent implements ItemQuantityChangedEvent {
  ItemQuantityIncreasedEvent({
    required this.delta,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final int delta;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  /// Deserialization factory.
  factory ItemQuantityIncreasedEvent.fromJson(Map<String, dynamic> json) {
    return ItemQuantityIncreasedEvent(
      eventId: EventId(json['eventId'] as String),
      delta: json['delta'] as int,
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }
}

/// Simulates a Freezed subclass for quantity decrease.
final class ItemQuantityDecreasedEvent implements ItemQuantityChangedEvent {
  ItemQuantityDecreasedEvent({
    required this.delta,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final int delta;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  /// Deserialization factory.
  factory ItemQuantityDecreasedEvent.fromJson(Map<String, dynamic> json) {
    return ItemQuantityDecreasedEvent(
      eventId: EventId(json['eventId'] as String),
      delta: json['delta'] as int,
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }
}

// -- Registry builders with matchers ----------------------------------------

/// Builds an [AggregateFactoryRegistry] with matchers for sealed class subtypes.
///
/// The factory is registered under the BASE class type [ItemCreatedEvent],
/// but the matchers ensure lookup works for subtype instances too.
AggregateFactoryRegistry _buildItemFactoryRegistry() {
  return AggregateFactoryRegistry(
    {
      Item: {
        ItemCreatedEvent: (event) {
          final created = event as ItemCreatedEvent;
          return Item(name: created.name, kind: 'unknown');
        },
      },
    },
    matchers: {
      Item: {
        ItemCreatedEvent: (Object event) => event is ItemCreatedEvent,
      },
    },
  );
}

/// Builds an [EventApplierRegistry] with matchers for sealed class subtypes.
EventApplierRegistry _buildItemApplierRegistry() {
  return EventApplierRegistry(
    {
      Item: {
        ItemQuantityChangedEvent: (aggregate, event) {
          final item = aggregate as Item;
          final changed = event as ItemQuantityChangedEvent;
          item.quantity += changed.delta;
        },
      },
    },
    matchers: {
      Item: {
        ItemQuantityChangedEvent: (Object event) => event is ItemQuantityChangedEvent,
      },
    },
  );
}

/// Builds an [EventSerializerRegistry] with matchers for sealed class subtypes.
EventSerializerRegistry _buildItemSerializerRegistry() {
  return EventSerializerRegistry(
    {
      ItemCreatedEvent: EventSerializerEntry(
        eventType: 'item.created',
        toJson: (event) {
          final created = event as ItemCreatedEvent;
          return {'name': created.name};
        },
        fromJson: PhysicalItemCreatedEvent.fromJson,
      ),
      ItemQuantityChangedEvent: EventSerializerEntry(
        eventType: 'item.quantity_changed',
        toJson: (event) {
          final changed = event as ItemQuantityChangedEvent;
          return {'delta': changed.delta};
        },
        fromJson: ItemQuantityIncreasedEvent.fromJson,
      ),
    },
    matchers: {
      ItemCreatedEvent: (Object event) => event is ItemCreatedEvent,
      ItemQuantityChangedEvent: (Object event) => event is ItemQuantityChangedEvent,
    },
  );
}

void main() {
  // -------------------------------------------------------------------------
  // AggregateFactoryRegistry — sealed class subtype matching
  // -------------------------------------------------------------------------
  group('AggregateFactoryRegistry – sealed class subtype matching', () {
    late AggregateFactoryRegistry registry;

    setUp(() {
      registry = _buildItemFactoryRegistry();
    });

    test('getFactory returns null for subtype runtimeType (exact match fails)', () {
      // Arrange — PhysicalItemCreatedEvent's runtimeType is NOT ItemCreatedEvent.
      final subtypeEvent = PhysicalItemCreatedEvent(name: 'widget');

      // Act — exact Type lookup uses the subtype's runtimeType.
      final factory = registry.getFactory<Item>(Item, subtypeEvent.runtimeType);

      // Assert — exact lookup should fail because the key is ItemCreatedEvent.
      expect(factory, isNull);
    });

    test('getFactoryForEvent resolves factory via predicate for subtype instance', () {
      // Arrange
      final subtypeEvent = PhysicalItemCreatedEvent(name: 'gadget');

      // Act — predicate-based lookup falls back to `is ItemCreatedEvent`.
      final factory = registry.getFactoryForEvent<Item>(Item, subtypeEvent);

      // Assert — the factory should be found via the matcher.
      expect(factory, isNotNull);
      final item = factory!(subtypeEvent);
      // Verifies the factory actually received the event correctly.
      expect(item.name, equals('gadget'));
    });

    test('getFactoryForEvent resolves factory for a different subtype too', () {
      // Arrange
      final digitalEvent = DigitalItemCreatedEvent(name: 'ebook');

      // Act
      final factory = registry.getFactoryForEvent<Item>(Item, digitalEvent);

      // Assert — both subtypes should match the same base class predicate.
      expect(factory, isNotNull);
      final item = factory!(digitalEvent);
      expect(item.name, equals('ebook'));
    });

    test('getFactoryForEvent uses exact match as fast path when runtimeType matches', () {
      // Arrange — register a factory with the EXACT concrete type.
      final directRegistry = AggregateFactoryRegistry({
        Item: {
          PhysicalItemCreatedEvent: (event) {
            return Item(name: (event as PhysicalItemCreatedEvent).name, kind: 'physical');
          },
        },
      });
      final event = PhysicalItemCreatedEvent(name: 'bolt');

      // Act
      final factory = directRegistry.getFactoryForEvent<Item>(Item, event);

      // Assert — should find via exact match, no matchers needed.
      expect(factory, isNotNull);
      final item = factory!(event);
      expect(item.kind, equals('physical'));
    });

    test('getFactoryByEvent resolves factory by event instance across all aggregates', () {
      // Arrange
      final event = DigitalItemCreatedEvent(name: 'soundtrack');

      // Act — scans all aggregate types to find a match.
      final result = registry.getFactoryByEvent(event);

      // Assert — should resolve to Item aggregate with the correct factory.
      expect(result, isNotNull);
      expect(result!.aggregateType, equals(Item));
      final item = result.factory(event) as Item;
      expect(item.name, equals('soundtrack'));
    });

    test('getFactoryByEvent returns null when no matcher matches', () {
      // Arrange — use an event type that is not registered at all.
      final unregisteredEvent = ItemQuantityIncreasedEvent(delta: 5);

      // Act
      final result = registry.getFactoryByEvent(unregisteredEvent);

      // Assert — ItemQuantityIncreasedEvent is not a creation event.
      expect(result, isNull);
    });

    test('merge preserves matchers from both registries', () {
      // Arrange
      final otherRegistry = AggregateFactoryRegistry(
        {
          Item: {
            // Add a second creation event type for Item.
          },
        },
        matchers: {
          Item: {
            // A different matcher entry that should survive merge.
            ItemQuantityChangedEvent: (Object event) => event is ItemQuantityChangedEvent,
          },
        },
      );

      // Act
      final merged = registry.merge(otherRegistry);

      // Assert — both the original ItemCreatedEvent matcher and the
      // newly merged ItemQuantityChangedEvent matcher should work.
      final creationEvent = PhysicalItemCreatedEvent(name: 'merged');
      expect(merged.getFactoryForEvent<Item>(Item, creationEvent), isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // EventApplierRegistry — sealed class subtype matching
  // -------------------------------------------------------------------------
  group('EventApplierRegistry – sealed class subtype matching', () {
    late EventApplierRegistry registry;

    setUp(() {
      registry = _buildItemApplierRegistry();
    });

    test('getApplier returns null for subtype runtimeType (exact match fails)', () {
      // Arrange
      final subtypeEvent = ItemQuantityIncreasedEvent(delta: 3);

      // Act — exact lookup uses the subtype's runtimeType.
      final applier = registry.getApplier<Item>(Item, subtypeEvent.runtimeType);

      // Assert — should fail because the key is ItemQuantityChangedEvent.
      expect(applier, isNull);
    });

    test('getApplierForEvent resolves applier via predicate for increase subtype', () {
      // Arrange
      final item = Item(name: 'bolt', kind: 'physical', quantity: 10);
      final event = ItemQuantityIncreasedEvent(delta: 5);

      // Act — predicate fallback matches via `is ItemQuantityChangedEvent`.
      final applier = registry.getApplierForEvent<Item>(Item, event);

      // Assert
      expect(applier, isNotNull);
      applier!(item, event);
      // Verifies the applier actually mutated the aggregate.
      expect(item.quantity, equals(15));
    });

    test('getApplierForEvent resolves applier via predicate for decrease subtype', () {
      // Arrange
      final item = Item(name: 'bolt', kind: 'physical', quantity: 10);
      final event = ItemQuantityDecreasedEvent(delta: -3);

      // Act
      final applier = registry.getApplierForEvent<Item>(Item, event);

      // Assert
      expect(applier, isNotNull);
      applier!(item, event);
      expect(item.quantity, equals(7));
    });

    test('getApplierForEvent uses exact match as fast path', () {
      // Arrange — register applier with EXACT concrete type.
      final directRegistry = EventApplierRegistry({
        Item: {
          ItemQuantityIncreasedEvent: (aggregate, event) {
            (aggregate as Item).quantity += 100;
          },
        },
      });
      final item = Item(name: 'x', kind: 'y', quantity: 0);
      final event = ItemQuantityIncreasedEvent(delta: 1);

      // Act
      final applier = directRegistry.getApplierForEvent<Item>(Item, event);

      // Assert — should find via exact match, no matchers needed.
      expect(applier, isNotNull);
      applier!(item, event);
      expect(item.quantity, equals(100));
    });

    test('merge preserves matchers from both registries', () {
      // Arrange
      final otherRegistry = EventApplierRegistry(
        {},
        matchers: {
          Item: {
            ItemCreatedEvent: (Object event) => event is ItemCreatedEvent,
          },
        },
      );

      // Act
      final merged = registry.merge(otherRegistry);

      // Assert — the original ItemQuantityChangedEvent matcher should survive.
      final event = ItemQuantityIncreasedEvent(delta: 2);
      expect(merged.getApplierForEvent<Item>(Item, event), isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // EventSerializerRegistry — sealed class subtype matching
  // -------------------------------------------------------------------------
  group('EventSerializerRegistry – sealed class subtype matching', () {
    late EventSerializerRegistry registry;

    setUp(() {
      registry = _buildItemSerializerRegistry();
    });

    test('operator[] returns null for subtype runtimeType (exact match fails)', () {
      // Arrange
      final subtypeEvent = PhysicalItemCreatedEvent(name: 'test');

      // Act — exact lookup uses the subtype's runtimeType.
      final entry = registry[subtypeEvent.runtimeType];

      // Assert — should fail because the key is ItemCreatedEvent, not PhysicalItemCreatedEvent.
      expect(entry, isNull);
    });

    test('getEntryForEvent resolves entry via predicate for creation subtype', () {
      // Arrange
      final subtypeEvent = PhysicalItemCreatedEvent(name: 'sensor');

      // Act — predicate fallback matches via `is ItemCreatedEvent`.
      final entry = registry.getEntryForEvent(subtypeEvent);

      // Assert — should find the entry registered under ItemCreatedEvent.
      expect(entry, isNotNull);
      expect(entry!.eventType, equals('item.created'));
    });

    test('getEntryForEvent resolves entry via predicate for mutation subtype', () {
      // Arrange
      final subtypeEvent = ItemQuantityDecreasedEvent(delta: -1);

      // Act
      final entry = registry.getEntryForEvent(subtypeEvent);

      // Assert
      expect(entry, isNotNull);
      expect(entry!.eventType, equals('item.quantity_changed'));
    });

    test('getEntryForEvent resolves entry for different creation subtype', () {
      // Arrange
      final digitalEvent = DigitalItemCreatedEvent(name: 'album');

      // Act
      final entry = registry.getEntryForEvent(digitalEvent);

      // Assert — both subtypes should match the same base class predicate.
      expect(entry, isNotNull);
      expect(entry!.eventType, equals('item.created'));
    });

    test('getEntryForEvent uses exact match as fast path', () {
      // Arrange — register an entry with the EXACT concrete type.
      final directRegistry = EventSerializerRegistry({
        PhysicalItemCreatedEvent: EventSerializerEntry(
          eventType: 'item.created.physical',
          toJson: (event) => {'name': (event as PhysicalItemCreatedEvent).name},
          fromJson: PhysicalItemCreatedEvent.fromJson,
        ),
      });
      final event = PhysicalItemCreatedEvent(name: 'direct');

      // Act
      final entry = directRegistry.getEntryForEvent(event);

      // Assert — should find via exact match, no matchers needed.
      expect(entry, isNotNull);
      expect(entry!.eventType, equals('item.created.physical'));
    });

    test('getEntryForEvent returns null when no matcher matches', () {
      // Arrange — empty registry.
      const emptyRegistry = EventSerializerRegistry.empty();

      // Act
      final entry = emptyRegistry.getEntryForEvent(
        PhysicalItemCreatedEvent(name: 'orphan'),
      );

      // Assert
      expect(entry, isNull);
    });

    test('merge preserves matchers from both registries', () {
      // Arrange
      final otherRegistry = EventSerializerRegistry(
        {},
        matchers: {
          // A totally different matcher.
          PhysicalItemCreatedEvent: (Object event) => event is PhysicalItemCreatedEvent,
        },
      );

      // Act
      final merged = registry.merge(otherRegistry);

      // Assert — the original matchers should survive.
      final event = DigitalItemCreatedEvent(name: 'merged');
      expect(merged.getEntryForEvent(event), isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // Without matchers — verifies the try-each fallback works with old
  // generated code that does not provide matchers.
  // -------------------------------------------------------------------------
  group('Try-each fallback – works without matchers (old generated code)', () {
    test('AggregateFactoryRegistry: getFactoryForEvent resolves without matchers', () {
      // Arrange — registry has NO matchers, simulating old generated code.
      final registry = AggregateFactoryRegistry({
        Item: {
          ItemCreatedEvent: (event) {
            final created = event as ItemCreatedEvent;
            return Item(name: created.name, kind: 'from-try-each');
          },
        },
      });
      final subtypeEvent = PhysicalItemCreatedEvent(name: 'no-matcher');

      // Act — exact match fails, matchers are empty, try-each kicks in.
      final factory = registry.getFactoryForEvent<Item>(Item, subtypeEvent);

      // Assert — should resolve via the try-each fallback.
      expect(factory, isNotNull);
      final item = factory!(subtypeEvent);
      expect(item.name, equals('no-matcher'));
      expect(item.kind, equals('from-try-each'));
    });

    test('AggregateFactoryRegistry: getFactoryByEvent resolves without matchers', () {
      // Arrange — no matchers.
      final registry = AggregateFactoryRegistry({
        Item: {
          ItemCreatedEvent: (event) {
            final created = event as ItemCreatedEvent;
            return Item(name: created.name, kind: 'scanned');
          },
        },
      });
      final subtypeEvent = DigitalItemCreatedEvent(name: 'digital-no-matcher');

      // Act
      final result = registry.getFactoryByEvent(subtypeEvent);

      // Assert
      expect(result, isNotNull);
      expect(result!.aggregateType, equals(Item));
      final item = result.factory(subtypeEvent) as Item;
      expect(item.name, equals('digital-no-matcher'));
    });

    test('AggregateFactoryRegistry: getFactoryByEvent returns null for unrelated event', () {
      // Arrange — no matchers, event type is completely unrelated.
      final registry = AggregateFactoryRegistry({
        Item: {
          ItemCreatedEvent: (event) {
            final created = event as ItemCreatedEvent;
            return Item(name: created.name, kind: 'x');
          },
        },
      });
      // ItemQuantityIncreasedEvent is NOT an ItemCreatedEvent.
      final unrelatedEvent = ItemQuantityIncreasedEvent(delta: 5);

      // Act
      final result = registry.getFactoryByEvent(unrelatedEvent);

      // Assert — the try-each fallback cast fails, returns null.
      expect(result, isNull);
    });

    test('EventApplierRegistry: getApplierForEvent resolves without matchers', () {
      // Arrange — no matchers.
      final registry = EventApplierRegistry({
        Item: {
          ItemQuantityChangedEvent: (aggregate, event) {
            final item = aggregate as Item;
            final changed = event as ItemQuantityChangedEvent;
            item.quantity += changed.delta;
          },
        },
      });
      final item = Item(name: 'test', kind: 'test', quantity: 10);
      final subtypeEvent = ItemQuantityIncreasedEvent(delta: 7);

      // Act
      final applier = registry.getApplierForEvent<Item>(Item, subtypeEvent);

      // Assert
      expect(applier, isNotNull);
      applier!(item, subtypeEvent);
      expect(item.quantity, equals(17));
    });

    test('EventSerializerRegistry: getEntryForEvent resolves without matchers', () {
      // Arrange — no matchers.
      final registry = EventSerializerRegistry({
        ItemCreatedEvent: EventSerializerEntry(
          eventType: 'item.created',
          toJson: (event) {
            final created = event as ItemCreatedEvent;
            return {'name': created.name};
          },
          fromJson: PhysicalItemCreatedEvent.fromJson,
        ),
      });
      final subtypeEvent = PhysicalItemCreatedEvent(name: 'no-matcher-serializer');

      // Act
      final entry = registry.getEntryForEvent(subtypeEvent);

      // Assert
      expect(entry, isNotNull);
      expect(entry!.eventType, equals('item.created'));
    });
  });
}
