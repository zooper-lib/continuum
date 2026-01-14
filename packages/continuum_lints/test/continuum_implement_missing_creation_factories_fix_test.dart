import 'dart:io';

import 'package:analyzer_plugin/protocol/protocol_common.dart' hide AnalysisError;
import 'package:continuum_lints/src/continuum_implement_missing_creation_factories_fix.dart';
import 'package:continuum_lints/src/continuum_missing_creation_factories_rule.dart';
import 'package:test/test.dart';

void main() {
  group('ContinuumImplementMissingCreationFactoriesFix', () {
    test('inserts stub creation factories for missing createFrom<Event> methods', () async {
      // Arrange
      // NOTE: The custom_lint test harness resolves Dart files using the current
      // package's analysis context. So the test file must live inside this
      // package folder, otherwise package imports/annotations won't resolve.
      final Directory tempDirectory = Directory(
        '${Directory.current.path}/test/__tmp__/continuum_lints_creation_fix_test_${DateTime.now().microsecondsSinceEpoch}',
      );

      await tempDirectory.create(recursive: true);

      try {
        final File dartFile = File('${tempDirectory.path}/domain.dart');

        await dartFile.writeAsString(r'''
import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

@Aggregate()
class AudioFile {
  const AudioFile();
}

@AggregateEvent(of: AudioFile, creation: true)
class AudioFileCreated implements ContinuumEvent {
  AudioFileCreated({EventId? eventId, DateTime? occurredOn, Map<String, Object?> metadata = const {}})
    : id = eventId ?? EventId.fromUlid(),
      occurredOn = occurredOn ?? DateTime.now(),
      metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}
''');

        // Act
        final lints = await const ContinuumMissingCreationFactoriesRule().testAnalyzeAndRun(dartFile);

        final targetLint = lints.firstWhere(
          (error) => error.diagnosticCode.name == 'continuum_missing_creation_factories',
          orElse: () => throw StateError(
            'Expected continuum_missing_creation_factories lint to be emitted.',
          ),
        );

        final changes = await ContinuumImplementMissingCreationFactoriesFix().testAnalyzeAndRun(
          dartFile,
          targetLint,
          const [],
        );

        // Assert
        expect(changes, isNotEmpty, reason: 'Expected the fix to produce a source change.');

        final SourceChange sourceChange = changes.single.change;
        final List<SourceFileEdit> edits = sourceChange.edits;

        expect(edits, hasLength(1), reason: 'Expected a single file edit for the analyzed file.');

        final List<SourceEdit> sourceEdits = edits.single.edits;
        expect(sourceEdits, isNotEmpty, reason: 'Expected at least one insertion edit.');

        final bool insertedFactoryStub = sourceEdits.any((SourceEdit edit) {
          return edit.replacement.contains(
                'static AudioFile createFromAudioFileCreated(AudioFileCreated event)',
              ) &&
              edit.replacement.contains('throw UnimplementedError();');
        });

        // WHY: This validates the VS Code quick-fix will actually implement the
        // missing factory method.
        expect(insertedFactoryStub, isTrue);
      } finally {
        await tempDirectory.delete(recursive: true);
      }
    });
  });
}
