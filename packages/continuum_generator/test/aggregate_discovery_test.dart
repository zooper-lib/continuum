import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:continuum_generator/src/aggregate_discovery.dart';
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

void main() {
  group('AggregateDiscovery', () {
    test('discovers abstract aggregate roots', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/domain.dart': r"""
import 'package:bounded/bounded.dart';

final class UserId extends TypedIdentity<String> {
  const UserId(super.value);
}

abstract class UserBase extends AggregateRoot<UserId> {
  UserBase(super.id);
}
""",
      };

      // Act
      final aggregates = await resolveSources(
        inputs,
        (resolver) async {
          final library = await _libraryFor(resolver, 'continuum_generator|lib/domain.dart');
          return AggregateDiscovery().discoverAggregates(
            library,
            candidateEventLibraries: <LibraryElement>[library],
          );
        },
        rootPackage: 'continuum_generator',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(aggregates, hasLength(1));
      expect(aggregates.single.name, 'UserBase');
    });

    test('associates @AggregateEvent events to abstract aggregate roots', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/domain.dart': r"""
import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

final class UserId extends TypedIdentity<String> {
  const UserId(super.value);
}

abstract class UserBase extends AggregateRoot<UserId> {
  UserBase(super.id);
}

@AggregateEvent(of: UserBase)
class EmailChanged implements ContinuumEvent {
  EmailChanged({
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime(2020, 1, 1),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}
""",
      };

      // Act
      final aggregates = await resolveSources(
        inputs,
        (resolver) async {
          final library = await _libraryFor(resolver, 'continuum_generator|lib/domain.dart');
          return AggregateDiscovery().discoverAggregates(
            library,
            candidateEventLibraries: <LibraryElement>[library],
          );
        },
        rootPackage: 'continuum_generator',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(aggregates, hasLength(1));
      expect(aggregates.single.name, 'UserBase');
      expect(
        aggregates.single.mutationEvents.map((e) => e.name),
        contains('EmailChanged'),
      );
    });

    test('discovers concrete aggregate roots', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/contracts.dart': r"""
import 'package:bounded/bounded.dart';

final class UserId extends TypedIdentity<String> {
  const UserId(super.value);
}

class UserContract extends AggregateRoot<UserId> {
  UserContract(super.id);
}
""",
      };

      // Act
      final aggregates = await resolveSources(
        inputs,
        (resolver) async {
          final library = await _libraryFor(resolver, 'continuum_generator|lib/contracts.dart');
          return AggregateDiscovery().discoverAggregates(
            library,
            candidateEventLibraries: <LibraryElement>[library],
          );
        },
        rootPackage: 'continuum_generator',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(aggregates, hasLength(1));
      expect(aggregates.single.name, 'UserContract');
    });

    test('associates @AggregateEvent events to concrete aggregate roots', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/contracts.dart': r"""
import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

final class UserId extends TypedIdentity<String> {
  const UserId(super.value);
}

class UserContract extends AggregateRoot<UserId> {
  UserContract(super.id);
}

@AggregateEvent(of: UserContract)
class UserRenamed implements ContinuumEvent {
  UserRenamed({
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime(2020, 1, 1),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}
""",
      };

      // Act
      final aggregates = await resolveSources(
        inputs,
        (resolver) async {
          final library = await _libraryFor(resolver, 'continuum_generator|lib/contracts.dart');
          return AggregateDiscovery().discoverAggregates(
            library,
            candidateEventLibraries: <LibraryElement>[library],
          );
        },
        rootPackage: 'continuum_generator',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(aggregates, hasLength(1));
      expect(aggregates.single.name, 'UserContract');
      expect(
        aggregates.single.mutationEvents.map((e) => e.name),
        contains('UserRenamed'),
      );
    });

    test('discovers events in separate libraries without imports', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/audio_file.dart': r"""
import 'package:bounded/bounded.dart';

final class AudioFileId extends TypedIdentity<String> {
  const AudioFileId(super.value);
}

abstract class AudioFile extends AggregateRoot<AudioFileId> {
  AudioFile(super.id);
}
""",
        'continuum_generator|lib/audio_file_deleted_event.dart': r"""
import 'package:continuum/continuum.dart';

import 'audio_file.dart';

@AggregateEvent(of: AudioFile)
class AudioFileDeletedEvent implements ContinuumEvent {
  AudioFileDeletedEvent({
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime(2020, 1, 1),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}
""",
      };

      // Act
      final aggregates = await resolveSources(
        inputs,
        (resolver) async {
          final aggregateLibrary = await _libraryFor(resolver, 'continuum_generator|lib/audio_file.dart');
          final eventLibrary = await _libraryFor(resolver, 'continuum_generator|lib/audio_file_deleted_event.dart');

          return AggregateDiscovery().discoverAggregates(
            aggregateLibrary,
            candidateEventLibraries: <LibraryElement>[aggregateLibrary, eventLibrary],
          );
        },
        rootPackage: 'continuum_generator',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(aggregates, hasLength(1));
      expect(aggregates.single.name, 'AudioFile');
      expect(
        aggregates.single.mutationEvents.map((e) => e.name),
        contains('AudioFileDeletedEvent'),
      );
    });

    test('classifies creation events via explicit annotation flag', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/domain.dart': r"""
import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

final class UserId extends TypedIdentity<String> {
  const UserId(super.value);
}

class User extends AggregateRoot<UserId> {
  User(super.id);

  static User createFromUserRegistered(UserRegistered event) {
    return User(event.userId);
  }
}

@AggregateEvent(of: User, creation: true)
class UserRegistered implements ContinuumEvent {
  UserRegistered(
    this.userId, {
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime(2020, 1, 1),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final UserId userId;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}

@AggregateEvent(of: User)
class UserRenamed implements ContinuumEvent {
  UserRenamed({
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime(2020, 1, 1),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}
""",
      };

      // Act
      final aggregates = await resolveSources(
        inputs,
        (resolver) async {
          final library = await _libraryFor(resolver, 'continuum_generator|lib/domain.dart');
          return AggregateDiscovery().discoverAggregates(
            library,
            candidateEventLibraries: <LibraryElement>[library],
          );
        },
        rootPackage: 'continuum_generator',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(aggregates, hasLength(1));
      expect(aggregates.single.name, 'User');

      // WHY: Creation events should not require apply handlers.
      expect(
        aggregates.single.creationEvents.map((e) => e.name),
        contains('UserRegistered'),
      );
      expect(
        aggregates.single.mutationEvents.map((e) => e.name),
        contains('UserRenamed'),
      );
    });

    test('throws when a creation event is missing its createFrom<Event> factory', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/domain.dart': r"""
import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

final class UserId extends TypedIdentity<String> {
  const UserId(super.value);
}

class User extends AggregateRoot<UserId> {
  User(super.id);
}

@AggregateEvent(of: User, creation: true)
class UserRegistered implements ContinuumEvent {
  UserRegistered({
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime(2020, 1, 1),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}
""",
      };

      // Act + Assert
      await expectLater(
        () async {
          await resolveSources(
            inputs,
            (resolver) async {
              final library = await _libraryFor(resolver, 'continuum_generator|lib/domain.dart');
              return AggregateDiscovery().discoverAggregates(
                library,
                candidateEventLibraries: <LibraryElement>[library],
              );
            },
            rootPackage: 'continuum_generator',
            readAllSourcesFromFilesystem: true,
          );
        },
        throwsA(isA<InvalidGenerationSourceError>()),
      );
    });
  });
}

Future<LibraryElement> _libraryFor(Resolver resolver, String serializedAssetId) async {
  final assetId = AssetId.parse(serializedAssetId);
  return resolver.libraryFor(assetId);
}
