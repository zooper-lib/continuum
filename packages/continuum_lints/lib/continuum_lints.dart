import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/continuum_missing_apply_handlers_rule.dart';
import 'src/continuum_missing_creation_factories_rule.dart';
import 'src/continuum_missing_projection_handlers_rule.dart';

/// Creates the custom_lint plugin for continuum.
PluginBase createPlugin() => _ContinuumLintsPlugin();

final class _ContinuumLintsPlugin extends PluginBase {
  _ContinuumLintsPlugin();

  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) {
    return const <LintRule>[
      ContinuumMissingApplyHandlersRule(),
      ContinuumMissingCreationFactoriesRule(),
      ContinuumMissingProjectionHandlersRule(),
    ];
  }
}
