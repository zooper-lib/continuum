import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:continuum_generator/builder.dart';
import 'package:package_config/package_config.dart';
import 'package:test/test.dart';

void main() {
  late final PackageConfig packageConfig;
  late TestReaderWriter readerWriter;

  setUpAll(() async {
    // In some CI environments (notably when running tests via workspace tooling),
    // `Isolate.packageConfig` can be null. Fall back to locating the
    // `.dart_tool/package_config.json` file relative to the working directory.
    Uri? packageConfigUri = await Isolate.packageConfig;
    packageConfigUri ??= _tryFindPackageConfigUriFromWorkingDirectory();

    if (packageConfigUri == null) {
      throw StateError(
        'Missing package config. `Isolate.packageConfig` was null and no '
        '`.dart_tool/package_config.json` could be found from `${Directory.current.path}`.',
      );
    }

    packageConfig = await loadPackageConfigUri(packageConfigUri);
  });

  setUp(() async {
    readerWriter = TestReaderWriter(rootPackage: 'continuum_generator');
    await readerWriter.testing.loadIsolateSources();
  });

  group('ContinuumGenerator (abstract/interface)', () {
    test('generates code for abstract AggregateRoot and its events', () async {
      // Arrange
      final builder = continuumBuilder(const BuilderOptions({}));

      // Act + Assert
      await testBuilder(
        builder,
        {
          'continuum_generator|lib/domain.dart': r"""
import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

part 'domain.continuum.g.dart';

final class UserId extends TypedIdentity<String> {
  const UserId(super.value);
}

Uri? _tryFindPackageConfigUriFromWorkingDirectory() {
  Directory currentDirectory = Directory.current;
  while (true) {
    final Uri candidateUri = currentDirectory.uri.resolve('.dart_tool/package_config.json');
    if (File.fromUri(candidateUri).existsSync()) {
      return candidateUri;
    }

    final Directory parentDirectory = currentDirectory.parent;
    if (parentDirectory.path == currentDirectory.path) {
      return null;
    }

    currentDirectory = parentDirectory;
  }
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
        },
        rootPackage: 'continuum_generator',
        packageConfig: packageConfig,
        readerWriter: readerWriter,
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

    test('generates code for concrete AggregateRoot and its events', () async {
      // Arrange
      final builder = continuumBuilder(const BuilderOptions({}));

      // Act + Assert
      await testBuilder(
        builder,
        {
          'continuum_generator|lib/contracts.dart': r"""
import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

part 'contracts.continuum.g.dart';

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
        },
        rootPackage: 'continuum_generator',
        packageConfig: packageConfig,
        readerWriter: readerWriter,
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
          // IMPORTANT: Aggregate file does NOT import the event file.
          'continuum_generator|lib/audio_file.dart': r"""
import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

part 'audio_file.continuum.g.dart';

final class AudioFileId extends TypedIdentity<String> {
  const AudioFileId(super.value);
}

abstract class AudioFile extends AggregateRoot<AudioFileId> {
  AudioFile(super.id);
}
""",
          // Event lives in a separate library and imports the aggregate instead.
          'continuum_generator|lib/audio_file_deleted_event.dart': r"""
import 'package:continuum/continuum.dart';

import 'audio_file.dart';

@AggregateEvent(of: AudioFile)
class AudioFileDeletedEvent implements ContinuumEvent {
  AudioFileDeletedEvent({
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
        },
        rootPackage: 'continuum_generator',
        packageConfig: packageConfig,
        readerWriter: readerWriter,
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

Uri? _tryFindPackageConfigUriFromWorkingDirectory() {
  Directory currentDirectory = Directory.current;
  while (true) {
    final Uri candidateUri = currentDirectory.uri.resolve('.dart_tool/package_config.json');
    if (File.fromUri(candidateUri).existsSync()) {
      return candidateUri;
    }

    final Directory parentDirectory = currentDirectory.parent;
    if (parentDirectory.path == currentDirectory.path) {
      return null;
    }

    currentDirectory = parentDirectory;
  }
}
