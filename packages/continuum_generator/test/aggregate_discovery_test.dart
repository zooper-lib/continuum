import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:continuum_generator/src/aggregate_discovery.dart';
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

void main() {
  group('AggregateDiscovery', () {
    test('discovers abstract classes annotated with @Aggregate', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/domain.dart': r"""
import 'package:continuum/src/annotations/aggregate.dart';

@Aggregate()
abstract class UserBase {}
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

    test('associates @AggregateEvent events to abstract aggregates', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/domain.dart': r"""
import 'package:continuum/src/annotations/aggregate.dart';
import 'package:continuum/src/annotations/aggregate_event.dart';
import 'package:continuum/src/events/continuum_event.dart';

@Aggregate()
abstract class UserBase {}

@AggregateEvent(of: UserBase)
class EmailChanged implements ContinuumEvent {
  const EmailChanged();
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

    test('discovers interface classes annotated with @Aggregate', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/contracts.dart': r"""
import 'package:continuum/src/annotations/aggregate.dart';

@Aggregate()
interface class UserContract {}
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

    test('associates @AggregateEvent events to interface aggregates', () async {
      // Arrange
      final inputs = <String, String>{
        'continuum_generator|lib/contracts.dart': r"""
import 'package:continuum/src/annotations/aggregate.dart';
import 'package:continuum/src/annotations/aggregate_event.dart';
import 'package:continuum/src/events/continuum_event.dart';

@Aggregate()
interface class UserContract {}

@AggregateEvent(of: UserContract)
class UserRenamed implements ContinuumEvent {
  const UserRenamed();
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
import 'package:continuum/src/annotations/aggregate.dart';

@Aggregate()
abstract class AudioFile {}
""",
        'continuum_generator|lib/audio_file_deleted_event.dart': r"""
import 'package:continuum/src/annotations/aggregate_event.dart';
import 'package:continuum/src/events/continuum_event.dart';

import 'audio_file.dart';

@AggregateEvent(of: AudioFile)
class AudioFileDeletedEvent implements ContinuumEvent {
  const AudioFileDeletedEvent();
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
import 'package:continuum/src/annotations/aggregate.dart';
import 'package:continuum/src/annotations/aggregate_event.dart';
import 'package:continuum/src/events/continuum_event.dart';

@Aggregate()
class User {
  const User();

  static User createFromUserRegistered(UserRegistered event) {
    return const User();
  }
}

@AggregateEvent(of: User, creation: true)
class UserRegistered implements ContinuumEvent {
  const UserRegistered();
}

@AggregateEvent(of: User)
class UserRenamed implements ContinuumEvent {
  const UserRenamed();
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
import 'package:continuum/src/annotations/aggregate.dart';
import 'package:continuum/src/annotations/aggregate_event.dart';
import 'package:continuum/src/events/continuum_event.dart';

@Aggregate()
class User {
  const User();
}

@AggregateEvent(of: User, creation: true)
class UserRegistered implements ContinuumEvent {
  const UserRegistered();
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
