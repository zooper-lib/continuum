import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:continuum_generator/src/aggregate_discovery.dart';
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
          return AggregateDiscovery().discoverAggregates(library);
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
          return AggregateDiscovery().discoverAggregates(library);
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
          return AggregateDiscovery().discoverAggregates(library);
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
          return AggregateDiscovery().discoverAggregates(library);
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
  });
}

Future<LibraryElement> _libraryFor(Resolver resolver, String serializedAssetId) async {
  final assetId = AssetId.parse(serializedAssetId);
  return resolver.libraryFor(assetId);
}
