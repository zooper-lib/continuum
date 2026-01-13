import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:continuum_generator/src/aggregate_discovery.dart';
import 'package:continuum_generator/src/code_emitter.dart';
import 'package:test/test.dart';

void main() {
  group('CodeEmitter', () {
    test('emits apply dispatch and required apply methods for abstract base', () async {
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
      final output = await resolveSources(
        inputs,
        (resolver) async {
          final library = await _libraryFor(resolver, 'continuum_generator|lib/domain.dart');
          final aggregates = AggregateDiscovery().discoverAggregates(
            library,
            candidateEventLibraries: <LibraryElement>[library],
          );
          return CodeEmitter().emit(aggregates);
        },
        rootPackage: 'continuum_generator',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(output, contains('extension \$UserBaseEventDispatch on UserBase'));

      // WHY: The entire point of generating for a base type is to ensure the
      // apply method exists (possibly as an abstract member on the base).
      expect(output, contains('void applyEmailChanged(EmailChanged event);'));
      expect(output, contains('case EmailChanged():'));
    });

    test('emits apply dispatch for interface class', () async {
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
      final output = await resolveSources(
        inputs,
        (resolver) async {
          final library = await _libraryFor(resolver, 'continuum_generator|lib/contracts.dart');
          final aggregates = AggregateDiscovery().discoverAggregates(
            library,
            candidateEventLibraries: <LibraryElement>[library],
          );
          return CodeEmitter().emit(aggregates);
        },
        rootPackage: 'continuum_generator',
        readAllSourcesFromFilesystem: true,
      );

      // Assert
      expect(output, contains('extension \$UserContractEventDispatch on UserContract'));
      expect(output, contains('void applyUserRenamed(UserRenamed event);'));
      expect(output, contains('case UserRenamed():'));
    });
  });
}

Future<LibraryElement> _libraryFor(Resolver resolver, String serializedAssetId) async {
  final assetId = AssetId.parse(serializedAssetId);
  return resolver.libraryFor(assetId);
}
