import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:continuum_generator/builder.dart';
import 'package:test/test.dart';

const _aggregateAnnotationSource = '''
class Aggregate {
  const Aggregate();
}
''';

const _aggregateEventAnnotationSource = '''
class AggregateEvent {
  final Type of;
  final String? type;

  const AggregateEvent({required this.of, this.type});
}
''';

const _continuumEventSource = '''
abstract interface class ContinuumEvent {}
''';

const _continuumFacadeSource = '''
library continuum;

export 'src/events/continuum_event.dart';

class GeneratedAggregate {
  final EventSerializerRegistry serializerRegistry;
  final AggregateFactoryRegistry aggregateFactories;
  final EventApplierRegistry eventAppliers;

  const GeneratedAggregate({
    required this.serializerRegistry,
    required this.aggregateFactories,
    required this.eventAppliers,
  });
}

class EventSerializerRegistry {
  const EventSerializerRegistry(Map<Type, EventSerializerEntry> entries);
}

class EventSerializerEntry {
  const EventSerializerEntry({
    required String eventType,
    required Object? Function(Object event) toJson,
    required Object? Function(Object json) fromJson,
  });
}

class AggregateFactoryRegistry {
  const AggregateFactoryRegistry(Map<Type, Map<Type, Object Function(Object)>> factories);
}

class EventApplierRegistry {
  const EventApplierRegistry(Map<Type, Map<Type, void Function(Object, Object)>> appliers);
}

class UnsupportedEventException implements Exception {
  final Type eventType;
  final Type aggregateType;

  UnsupportedEventException({required this.eventType, required this.aggregateType});
}

class InvalidCreationEventException implements Exception {
  final Type eventType;
  final Type aggregateType;

  InvalidCreationEventException({required this.eventType, required this.aggregateType});
}
''';

void main() {
  group('ContinuumGenerator (abstract/interface)', () {
    test('generates code for abstract @Aggregate and its events', () async {
      // Arrange
      final builder = continuumBuilder(const BuilderOptions({}));

      // Act + Assert
      await testBuilder(
        builder,
        {
          'continuum|lib/src/annotations/aggregate.dart': _aggregateAnnotationSource,
          'continuum|lib/src/annotations/aggregate_event.dart': _aggregateEventAnnotationSource,
          'continuum|lib/src/events/continuum_event.dart': _continuumEventSource,
          'continuum|lib/continuum.dart': _continuumFacadeSource,
          'continuum_generator|lib/domain.dart': r"""
import 'package:continuum/continuum.dart';
import 'package:continuum/src/annotations/aggregate.dart';
import 'package:continuum/src/annotations/aggregate_event.dart';

part 'domain.continuum.g.dart';

@Aggregate()
abstract class UserBase {}

@AggregateEvent(of: UserBase)
class EmailChanged implements ContinuumEvent {
  const EmailChanged();
}
""",
        },
        rootPackage: 'continuum_generator',
        outputs: {
          'continuum_generator|lib/domain.continuum.g.part': decodedMatches(
            allOf(
              contains(r'mixin _$UserBaseEventHandlers'),
              contains(r'void applyEmailChanged(EmailChanged event);'),
              contains(r'extension $UserBaseEventDispatch on UserBase'),
              contains(r'case EmailChanged():'),
              contains(r'applyEmailChanged(event);'),
              contains(r'final $UserBase = GeneratedAggregate('),
            ),
          ),
        },
      );
    });

    test('generates code for interface @Aggregate and its events', () async {
      // Arrange
      final builder = continuumBuilder(const BuilderOptions({}));

      // Act + Assert
      await testBuilder(
        builder,
        {
          'continuum|lib/src/annotations/aggregate.dart': _aggregateAnnotationSource,
          'continuum|lib/src/annotations/aggregate_event.dart': _aggregateEventAnnotationSource,
          'continuum|lib/src/events/continuum_event.dart': _continuumEventSource,
          'continuum|lib/continuum.dart': _continuumFacadeSource,
          'continuum_generator|lib/contracts.dart': r"""
import 'package:continuum/continuum.dart';
import 'package:continuum/src/annotations/aggregate.dart';
import 'package:continuum/src/annotations/aggregate_event.dart';

part 'contracts.continuum.g.dart';

@Aggregate()
interface class UserContract {}

@AggregateEvent(of: UserContract)
class UserRenamed implements ContinuumEvent {
  const UserRenamed();
}
""",
        },
        rootPackage: 'continuum_generator',
        outputs: {
          'continuum_generator|lib/contracts.continuum.g.part': decodedMatches(
            allOf(
              contains(r'mixin _$UserContractEventHandlers'),
              contains(r'void applyUserRenamed(UserRenamed event);'),
              contains(r'extension $UserContractEventDispatch on UserContract'),
              contains(r'case UserRenamed():'),
              contains(r'applyUserRenamed(event);'),
              contains(r'final $UserContract = GeneratedAggregate('),
            ),
          ),
        },
      );
    });

    test('discovers events without aggregate imports (package-wide scan)', () async {
      // Arrange
      final builder = continuumBuilder(const BuilderOptions({}));

      // Act + Assert
      await testBuilder(
        builder,
        {
          'continuum|lib/src/annotations/aggregate.dart': _aggregateAnnotationSource,
          'continuum|lib/src/annotations/aggregate_event.dart': _aggregateEventAnnotationSource,
          'continuum|lib/src/events/continuum_event.dart': _continuumEventSource,
          'continuum|lib/continuum.dart': _continuumFacadeSource,
          // IMPORTANT: Aggregate file does NOT import the event file.
          'continuum_generator|lib/audio_file.dart': r"""
import 'package:continuum/continuum.dart';
import 'package:continuum/src/annotations/aggregate.dart';

part 'audio_file.continuum.g.dart';

@Aggregate()
abstract class AudioFile {}
""",
          // Event lives in a separate library and imports the aggregate instead.
          'continuum_generator|lib/audio_file_deleted_event.dart': r"""
import 'package:continuum/continuum.dart';
import 'package:continuum/src/annotations/aggregate_event.dart';

import 'audio_file.dart';

@AggregateEvent(of: AudioFile)
class AudioFileDeletedEvent implements ContinuumEvent {
  const AudioFileDeletedEvent();
}
""",
        },
        rootPackage: 'continuum_generator',
        outputs: {
          'continuum_generator|lib/audio_file.continuum.g.part': decodedMatches(
            allOf(
              contains(r'mixin _$AudioFileEventHandlers'),
              // WHY: This proves we discovered the event even without imports.
              contains(r'void applyAudioFileDeletedEvent(AudioFileDeletedEvent event);'),
              contains(r'extension $AudioFileEventDispatch on AudioFile'),
              contains(r'case AudioFileDeletedEvent():'),
              contains(r'applyAudioFileDeletedEvent(event);'),
            ),
          ),
        },
      );
    });
  });
}
