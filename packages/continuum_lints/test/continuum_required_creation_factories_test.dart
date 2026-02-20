import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:continuum_lints/src/continuum_required_creation_factories.dart';
import 'package:test/test.dart';

void main() {
  group('ContinuumRequiredCreationFactories', () {
    test('detects missing createFrom factories for OperationFor creation operations', () async {
      // Arrange
      final Map<String, String> inputs = <String, String>{
        'continuum_lints|lib/domain.dart': r'''
import 'package:continuum/continuum.dart';

@OperationTarget()
class UserProfile {
  UserProfile();
}

@OperationFor(type: UserProfile, creation: true)
class UserProfileCreated implements ContinuumEvent {
  const UserProfileCreated();

  @override
  EventId get id => const EventId('evt_1');

  @override
  DateTime get occurredOn => DateTime.utc(2020);

  @override
  Map<String, Object?> get metadata => const <String, Object?>{};
}
''',
      };

      // Act
      final List<String> missing = await resolveSources(
        inputs,
        (Resolver resolver) async {
          final LibraryElement library = await _libraryFor(resolver, 'continuum_lints|lib/domain.dart');
          final ClassElement profile = _classNamed(library, 'UserProfile');
          return const ContinuumRequiredCreationFactories().findMissingCreationFactories(profile);
        },
        rootPackage: 'continuum_lints',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      // WHY: Creation operations must have a matching static createFrom<Op> factory.
      expect(missing, contains('createFromUserProfileCreated'));
    });

    test('does not report missing factory when createFrom factory exists', () async {
      // Arrange
      final Map<String, String> inputs = <String, String>{
        'continuum_lints|lib/domain.dart': r'''
import 'package:continuum/continuum.dart';

@OperationTarget()
class UserProfile {
  UserProfile();

  static UserProfile createFromUserProfileCreated(UserProfileCreated event) {
    return UserProfile();
  }
}

@OperationFor(type: UserProfile, creation: true)
class UserProfileCreated implements ContinuumEvent {
  const UserProfileCreated();

  @override
  EventId get id => const EventId('evt_1');

  @override
  DateTime get occurredOn => DateTime.utc(2020);

  @override
  Map<String, Object?> get metadata => const <String, Object?>{};
}
''',
      };

      // Act
      final List<String> missing = await resolveSources(
        inputs,
        (Resolver resolver) async {
          final LibraryElement library = await _libraryFor(resolver, 'continuum_lints|lib/domain.dart');
          final ClassElement profile = _classNamed(library, 'UserProfile');
          return const ContinuumRequiredCreationFactories().findMissingCreationFactories(profile);
        },
        rootPackage: 'continuum_lints',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(missing, isEmpty);
    });
  });
}

Future<LibraryElement> _libraryFor(Resolver resolver, String assetId) async {
  return resolver.libraryFor(AssetId.parse(assetId));
}

ClassElement _classNamed(LibraryElement library, String name) {
  for (final ClassElement element in library.classes) {
    if (element.displayName == name) return element;
  }
  throw StateError('Class not found: $name');
}
