import 'dart:io';

import 'package:analyzer_plugin/protocol/protocol_common.dart' hide AnalysisError;
import 'package:continuum_lints/src/continuum_implement_missing_apply_handlers_fix.dart';
import 'package:continuum_lints/src/continuum_missing_apply_handlers_rule.dart';
import 'package:test/test.dart';

void main() {
  group('ContinuumImplementMissingApplyHandlersFix', () {
    test('inserts stub apply methods for missing handlers', () async {
      // Arrange
      // NOTE: The custom_lint test harness resolves Dart files using the current
      // package's analysis context. So the test file must live inside this
      // package folder, otherwise package imports/annotations won't resolve.
      final Directory tempDirectory = Directory(
        '${Directory.current.path}/test/__tmp__/continuum_lints_fix_test_${DateTime.now().microsecondsSinceEpoch}',
      );

      await tempDirectory.create(recursive: true);

      try {
        final File dartFile = File('${tempDirectory.path}/domain.dart');

        await dartFile.writeAsString(r'''
import 'package:continuum/continuum.dart';

sealed class AudioFileDeletedEvent implements ContinuumEvent {
  const AudioFileDeletedEvent();
}

mixin _$AudioFileEventHandlers {
  void applyAudioFileDeletedEvent(AudioFileDeletedEvent event);
}

@Aggregate()
class AudioFile with _$AudioFileEventHandlers {
  const AudioFile();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
''');

        // Act
        final lints = await const ContinuumMissingApplyHandlersRule().testAnalyzeAndRun(dartFile);

        final targetLint = lints.firstWhere(
          (error) => error.diagnosticCode.name == 'continuum_missing_apply_handlers',
          orElse: () => throw StateError('Expected continuum_missing_apply_handlers lint to be emitted.'),
        );

        final changes = await ContinuumImplementMissingApplyHandlersFix().testAnalyzeAndRun(
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

        final bool insertedApplyStub = sourceEdits.any((SourceEdit edit) {
          return edit.replacement.contains('void applyAudioFileDeletedEvent(AudioFileDeletedEvent event)') &&
              edit.replacement.contains('throw UnimplementedError();');
        });

        // WHY: This validates the VS Code quick-fix will actually implement the missing handler.
        expect(insertedApplyStub, isTrue);
      } finally {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('does not insert apply stubs for creation events', () async {
      // Arrange
      // NOTE: The custom_lint test harness resolves Dart files using the current
      // package's analysis context. So the test file must live inside this
      // package folder, otherwise package imports/annotations won't resolve.
      final Directory tempDirectory = Directory(
        '${Directory.current.path}/test/__tmp__/continuum_lints_fix_test_${DateTime.now().microsecondsSinceEpoch}',
      );

      await tempDirectory.create(recursive: true);

      try {
        final File dartFile = File('${tempDirectory.path}/domain.dart');

        await dartFile.writeAsString(r'''
import 'package:continuum/continuum.dart';

@AggregateEvent(of: AudioFile, creation: true)
class AudioFileCreatedEvent implements ContinuumEvent {
  const AudioFileCreatedEvent();
}

sealed class AudioFileDeletedEvent implements ContinuumEvent {
  const AudioFileDeletedEvent();
}

mixin _$AudioFileEventHandlers {
  void applyAudioFileCreatedEvent(AudioFileCreatedEvent event);
  void applyAudioFileDeletedEvent(AudioFileDeletedEvent event);
}

@Aggregate()
class AudioFile with _$AudioFileEventHandlers {
  const AudioFile();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
''');

        // Act
        final lints = await const ContinuumMissingApplyHandlersRule().testAnalyzeAndRun(dartFile);

        final targetLint = lints.firstWhere(
          (error) => error.diagnosticCode.name == 'continuum_missing_apply_handlers',
          orElse: () => throw StateError('Expected continuum_missing_apply_handlers lint to be emitted.'),
        );

        final changes = await ContinuumImplementMissingApplyHandlersFix().testAnalyzeAndRun(
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

        final String insertedText = sourceEdits.map((SourceEdit edit) => edit.replacement).join('\n');

        // WHY: Non-creation events still require apply handlers and should be stubbed.
        expect(
          insertedText.contains('void applyAudioFileDeletedEvent(AudioFileDeletedEvent event)') &&
              insertedText.contains('throw UnimplementedError();'),
          isTrue,
        );

        // WHY: Creation events should not be enforced via apply handlers.
        expect(insertedText.contains('applyAudioFileCreatedEvent'), isFalse);
      } finally {
        await tempDirectory.delete(recursive: true);
      }
    });
  });
}
