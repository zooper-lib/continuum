import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:continuum_lints/src/continuum_required_apply_handlers.dart';
import 'package:test/test.dart';

void main() {
  group('ContinuumRequiredApplyHandlers', () {
    test('returns empty list when class does not mix in handler mixin', () async {
      // Arrange
      final Map<String, String> inputs = <String, String>{
        'continuum_lints|lib/domain.dart': r'''
class User {}
''',
      };

      // Act
      final List<String> missing = await resolveSources(
        inputs,
        (Resolver resolver) async {
          final LibraryElement library = await _libraryFor(resolver, 'continuum_lints|lib/domain.dart');
          final ClassElement userClass = _classNamed(library, 'User');

          // WHY: The lint should only apply when the class opted into handlers.
          return const ContinuumRequiredApplyHandlers().findMissingApplyHandlers(userClass);
        },
        rootPackage: 'continuum_lints',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(missing, isEmpty);
    });

    test('returns missing handlers when class mixes in handler mixin', () async {
      // Arrange
      final Map<String, String> inputs = <String, String>{
        'continuum_lints|lib/domain.dart': r'''
part 'domain.g.dart';

class User with _$UserEventHandlers {
  void applyEmailChanged(EmailChanged event) {}
}
''',
        'continuum_lints|lib/domain.g.dart': r'''
part of 'domain.dart';

mixin _$UserEventHandlers {
  void applyEmailChanged(EmailChanged event);
  void applyNameChanged(NameChanged event);
}

class EmailChanged {
  const EmailChanged();
}

class NameChanged {
  const NameChanged();
}
''',
      };

      // Act
      final List<String> missing = await resolveSources(
        inputs,
        (Resolver resolver) async {
          final LibraryElement library = await _libraryFor(resolver, 'continuum_lints|lib/domain.dart');
          final ClassElement userClass = _classNamed(library, 'User');

          // WHY: This is the core enforcement logic used by the lint.
          return const ContinuumRequiredApplyHandlers().findMissingApplyHandlers(userClass);
        },
        rootPackage: 'continuum_lints',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(missing, contains('applyNameChanged'));
      expect(missing, isNot(contains('applyEmailChanged')));
    });
  });
}

Future<LibraryElement> _libraryFor(Resolver resolver, String serializedAssetId) async {
  final AssetId assetId = AssetId.parse(serializedAssetId);
  return resolver.libraryFor(assetId);
}

ClassElement _classNamed(LibraryElement library, String name) {
  for (final ClassElement classElement in library.classes) {
    if (classElement.displayName == name) return classElement;
  }

  throw StateError('Class $name not found in test library.');
}
