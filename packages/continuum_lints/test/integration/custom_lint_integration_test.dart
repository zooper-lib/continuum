import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _expectedLintCode = 'continuum_missing_apply_handlers';
const String _fixturePackageName = 'continuum_lints_integration_fixture';

const String _repoRootMarkerFileName = 'melos_continuum_workspace.iml';

void main() {
  test(
    'custom_lint emits continuum_missing_apply_handlers for missing apply methods',
    () async {
      // Why this test exists:
      // - Unit tests validate our element-based detection logic.
      // - This integration test validates the wiring through the actual
      //   `custom_lint` CLI, ensuring the rule is discoverable and reports a
      //   diagnostic end-to-end.

      final Directory tempDirectory = await Directory.systemTemp.createTemp('continuum_lints_custom_lint_integration_');

      try {
        await _writeFixturePackageAsync(tempDirectory);
        await _dartPubGetAsync(tempDirectory);

        final String customLintJsonOutput = await _runCustomLintJsonAsync(tempDirectory);

        final Map<String, Object?> decoded = jsonDecode(customLintJsonOutput) as Map<String, Object?>;

        final Object? diagnosticsRaw = decoded['diagnostics'];
        expect(
          diagnosticsRaw,
          isA<List<Object?>>(),
          reason: 'custom_lint JSON output should contain a top-level "diagnostics" list.',
        );

        final List<Object?> diagnostics = diagnosticsRaw! as List<Object?>;

        // We don’t assume a strict schema for each diagnostic object since
        // custom_lint may extend its JSON format over time.
        final bool hasExpectedCode = diagnostics.any((Object? diagnostic) {
          if (diagnostic is! Map) return false;

          final Object? code = diagnostic['code'] ?? diagnostic['name'] ?? diagnostic['lintCode'] ?? diagnostic['errorCode'];

          if (code is String) return code == _expectedLintCode;

          if (code is Map) {
            final Object? codeName = code['name'] ?? code['code'];
            return codeName is String && codeName == _expectedLintCode;
          }

          return diagnostic.toString().contains(_expectedLintCode);
        });

        // Why this assertion matters:
        // - Without this lint, users can accidentally ship implicitly-abstract
        //   aggregates and only discover missing apply methods later.
        expect(
          hasExpectedCode,
          isTrue,
          reason: 'Expected to find a diagnostic with code $_expectedLintCode in: $customLintJsonOutput',
        );
      } finally {
        await tempDirectory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _writeFixturePackageAsync(Directory packageDirectory) async {
  final String packageDirectoryPath = packageDirectory.path;

  await File(p.join(packageDirectoryPath, 'pubspec.yaml')).writeAsString(
    _fixturePubspecYaml(),
  );

  await File(p.join(packageDirectoryPath, 'analysis_options.yaml')).writeAsString(
    _fixtureAnalysisOptionsYaml(),
  );

  await File(p.join(packageDirectoryPath, 'custom_lint.yaml')).writeAsString(
    _fixtureCustomLintYaml(),
  );

  await Directory(p.join(packageDirectoryPath, 'lib')).create(recursive: true);

  await File(p.join(packageDirectoryPath, 'lib', 'main.dart')).writeAsString(
    _fixtureMainDart(),
  );
}

Future<void> _dartPubGetAsync(Directory packageDirectory) async {
  final ProcessResult result = await Process.run(
    'dart',
    const <String>['pub', 'get'],
    workingDirectory: packageDirectory.path,
  );

  if (result.exitCode == 0) return;

  throw StateError(
    'dart pub get failed (exitCode=${result.exitCode})\n'
    'stdout:\n${result.stdout}\n\n'
    'stderr:\n${result.stderr}',
  );
}

Future<String> _runCustomLintJsonAsync(Directory packageDirectory) async {
  final ProcessResult result = await Process.run(
    'dart',
    const <String>[
      'run',
      'custom_lint',
      '--format=json',
      '--no-fatal-infos',
      '--no-fatal-warnings',
    ],
    workingDirectory: packageDirectory.path,
  );

  if (result.exitCode == 0) {
    return result.stdout is String ? result.stdout as String : '${result.stdout}';
  }

  throw StateError(
    'custom_lint failed (exitCode=${result.exitCode})\n'
    'stdout:\n${result.stdout}\n\n'
    'stderr:\n${result.stderr}',
  );
}

String _fixturePubspecYaml() {
  // Why we use path dependencies:
  // - Keeps the fixture tied to the current workspace source.
  // - Avoids relying on published versions for continuum/continuum_lints.
  return ''
      'name: $_fixturePackageName\n'
      'publish_to: none\n'
      '\n'
      'environment:\n'
      '  sdk: ">=3.10.0 <4.0.0"\n'
      '\n'
      'dependencies:\n'
      '  continuum:\n'
      '    path: ${_workspacePath('packages/continuum')}\n'
      '\n'
      'dev_dependencies:\n'
      '  custom_lint: ^0.8.1\n'
      '  continuum_lints:\n'
      '    path: ${_workspacePath('packages/continuum_lints')}\n'
      '\n'
      'dependency_overrides:\n'
      '  continuum:\n'
      '    path: ${_workspacePath('packages/continuum')}\n';
}

String _fixtureAnalysisOptionsYaml() {
  return ''
      'analyzer:\n'
      '  plugins:\n'
      '    - custom_lint\n';
}

String _fixtureCustomLintYaml() {
  return ''
      'custom_lint:\n'
      '  rules:\n'
      '    - $_expectedLintCode\n';
}

String _fixtureMainDart() {
  // The mixin name must match the generator convention: _$<Aggregate>EventHandlers.
  // We declare it manually so that the test doesn't need build_runner.
  return r''
      "import 'package:continuum/continuum.dart';\n"
      '\n'
      'mixin _\$AudioFileEventHandlers {\n'
      '  void applyAudioFileDeletedEvent();\n'
      '}\n'
      '\n'
      '@Aggregate()\n'
      'class AudioFile with _\$AudioFileEventHandlers {}\n';
}

String _workspacePath(String relativeWorkspacePath) {
  // We intentionally compute this relative to the repository root so that:
  // - tests work from any working directory
  // - path dependencies are always absolute and stable.
  final Directory repoRoot = _findRepoRootDirectory();

  return p.normalize(p.join(repoRoot.path, relativeWorkspacePath));
}

Directory _findRepoRootDirectory() {
  Directory directory = Directory.current;

  // Why we search for a marker file:
  // - `dart test` can be invoked from the repo root, from a package folder, or
  //   via tooling that changes the working directory.
  // - This keeps the integration test stable regardless of invocation.
  while (true) {
    final File markerFile = File(p.join(directory.path, _repoRootMarkerFileName));
    if (markerFile.existsSync()) return directory;

    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Unable to locate repo root. Expected to find $_repoRootMarkerFileName '
        'in a parent directory of ${Directory.current.path}.',
      );
    }

    directory = parent;
  }
}
