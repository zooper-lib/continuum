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

    test('emits apply dispatch for concrete aggregate root', () async {
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
