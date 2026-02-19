import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:continuum_generator/src/projection_code_emitter.dart';
import 'package:continuum_generator/src/projection_discovery.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectionCodeEmitter', () {
    test('emits apply() using Operation directly (not StoredEvent.domainEvent)', () async {
      final inputs = <String, String>{
        'continuum_generator|lib/projection_domain.dart': r'''
import 'package:continuum/src/annotations/projection.dart';
import 'package:continuum/src/projections/single_stream_projection.dart';
import 'package:continuum/src/events/continuum_event.dart';

part 'projection_domain.g.dart';

class UserRegistered implements ContinuumEvent {
  const UserRegistered();

  @override
  String get id => 'id';

  @override
  DateTime get occurredOn => DateTime(1970);

  @override
  Map<String, Object?> get metadata => const {};
}

@Projection(name: 'user-profile', events: [UserRegistered])
class UserProfileProjection extends SingleStreamProjection<int>
    with _$UserProfileProjectionHandlers {
  @override
  int createInitial(streamId) => 0;

  @override
  int applyUserRegistered(int current, UserRegistered event) => current + 1;
}
''',
      };

      final output = await resolveSources(
        inputs,
        (resolver) async {
          final library = await _libraryFor(resolver, 'continuum_generator|lib/projection_domain.dart');
          final projections = ProjectionDiscovery().discoverProjections(library);
          return ProjectionCodeEmitter().emit(projections);
        },
        rootPackage: 'continuum_generator',
        readAllSourcesFromFilesystem: true,
      );

      // apply() must accept Operation directly — no StoredEvent unwrapping.
      expect(output, contains('apply(int current, Operation operation)'));
      expect(output, isNot(contains('StoredEvent')));
      expect(output, isNot(contains('domainEvent')));

      // Must use UnsupportedProjectionOperationException, not the legacy event exception.
      expect(output, contains('UnsupportedProjectionOperationException'));
      expect(output, isNot(contains('UnsupportedEventException')));
    });
  });
}

Future<LibraryElement> _libraryFor(Resolver resolver, String serializedAssetId) async {
  final assetId = AssetId.parse(serializedAssetId);
  return resolver.libraryFor(assetId);
}
