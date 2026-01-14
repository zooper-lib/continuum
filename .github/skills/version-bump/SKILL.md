---
name: dart-version-bumping
description: Bump Dart and Flutter package versions based on the Unreleased section of CHANGELOG.md files.
---

# Dart Version Bumping Skill

## When to use this skill

Use this skill when:

- You are asked to bump versions for Dart or Flutter packages
- You are modifying pubspec.yaml versions
- You are working with CHANGELOG.md files that contain an Unreleased section
- Semantic versioning decisions are required

## Source of Truth

The only source of truth for version decisions is:

CHANGELOG.md → ## [Unreleased]

Content outside this section must be ignored.

## Semantic Versioning Rules

Versions follow MAJOR.MINOR.PATCH.

Exactly one increment must be applied.

### Major Version Bump

Apply a major bump if and only if:

- A section named ### BREAKING exists
- Or an entry explicitly describes a breaking change

Result:
MAJOR = MAJOR + 1  
MINOR = 0  
PATCH = 0  

### Minor Version Bump

Apply a minor bump if and only if:

- No ### BREAKING section exists
- New functionality is introduced via:
  - ### Added
  - ### Features
  - ### Changed (non-breaking)

Result:
MINOR = MINOR + 1  
PATCH = 0  

### Patch Version Bump

Apply a patch bump if and only if:

- No breaking changes
- No new features
- Only fixes or maintenance work exist

Typical sections:
- ### Fixed
- ### Refactored
- ### Docs
- ### Chore

Result:
PATCH = PATCH + 1  

## Required Actions

For each Dart or Flutter package:

1. Read the current version from pubspec.yaml
2. Parse CHANGELOG.md and extract ## [Unreleased]
3. Determine the bump type using the rules above
4. Compute the next version
5. Update workspace-internal dependency references that point to this package to use the new version (e.g. update other packages' `pubspec.yaml` entries like `my_package: ^<new_version>`).

### pubspec.yaml

- Update the version field to the new version
- Do not change formatting
- Do not modify dependencies

### CHANGELOG.md

- Rename ## [Unreleased] to ## [<new_version>] - <yyyy-MM-dd> (use the current date in `yyyy-MM-dd` format)
- Insert a new empty ## [Unreleased] section above it
- Preserve all existing content

## Multi-Package Repositories

- Evaluate each package independently
- Versions may differ between packages
- Never synchronize versions unless explicitly instructed

## Constraints

The agent must NOT:

- Guess version numbers
- Skip versions
- Combine multiple version increments
- Bump versions if ## [Unreleased] is empty
- Modify unrelated files

## Completion Criteria

The task is complete when:

- All affected pubspec.yaml files contain the new version
- All affected CHANGELOG.md files are updated correctly
- No unrelated changes exist
