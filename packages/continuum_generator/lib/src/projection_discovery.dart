import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

import 'models/projection_info.dart';

/// Type checker for the @Projection annotation.
const _projectionChecker = TypeChecker.fromUrl(
  'package:continuum/src/annotations/projection.dart#Projection',
);

/// Type checker for SingleStreamProjection base class.
const _singleStreamProjectionChecker = TypeChecker.fromUrl(
  'package:continuum/src/projections/single_stream_projection.dart#SingleStreamProjection',
);

/// Type checker for MultiStreamProjection base class.
const _multiStreamProjectionChecker = TypeChecker.fromUrl(
  'package:continuum/src/projections/multi_stream_projection.dart#MultiStreamProjection',
);

/// Discovers projections from library elements.
///
/// Scans a library for classes annotated with `@Projection()` and extracts
/// the projection name, handled event types, and read model type.
final class ProjectionDiscovery {
  /// Discovers all projections in the given library.
  ///
  /// Returns a list of [ProjectionInfo] with projection metadata.
  List<ProjectionInfo> discoverProjections(LibraryElement library) {
    final projections = <ProjectionInfo>[];

    for (final element in library.classes) {
      // Skip classes without @Projection annotation.
      if (!_projectionChecker.hasAnnotationOf(element)) continue;

      final annotation = _projectionChecker.firstAnnotationOf(element);
      if (annotation == null) continue;

      // Extract projection name from annotation.
      final nameValue = annotation.getField('name');
      final projectionName = nameValue?.toStringValue();
      if (projectionName == null || projectionName.isEmpty) {
        throw InvalidGenerationSourceError(
          '@Projection annotation requires a non-empty "name" parameter.',
          element: element,
        );
      }

      // Extract events list from annotation.
      final eventsField = annotation.getField('events');
      final eventTypes = <DartType>[];
      if (eventsField != null && !eventsField.isNull) {
        final eventsList = eventsField.toListValue();
        if (eventsList != null) {
          for (final eventValue in eventsList) {
            final eventType = eventValue.toTypeValue();
            if (eventType != null) {
              eventTypes.add(eventType);
            }
          }
        }
      }

      if (eventTypes.isEmpty) {
        throw InvalidGenerationSourceError(
          '@Projection annotation requires a non-empty "events" list.',
          element: element,
        );
      }

      // Infer read model type and key type from base class.
      final (readModelType, keyType) = _inferTypesFromBaseClass(element);

      projections.add(
        ProjectionInfo(
          element: element,
          projectionName: projectionName,
          eventTypes: eventTypes,
          readModelType: readModelType,
          keyType: keyType,
        ),
      );
    }

    return projections;
  }

  /// Infers the read model type and key type from the projection's base class.
  ///
  /// - `SingleStreamProjection<T>` → readModel: T, key: StreamId
  /// - `MultiStreamProjection<T, K>` → readModel: T, key: K
  (DartType?, DartType?) _inferTypesFromBaseClass(ClassElement element) {
    // Check all supertypes to find the projection base class.
    for (final supertype in element.allSupertypes) {
      final superElement = supertype.element;

      // Check for SingleStreamProjection<T>.
      if (_singleStreamProjectionChecker.isExactlyType(supertype)) {
        final typeArgs = supertype.typeArguments;
        if (typeArgs.isNotEmpty) {
          // SingleStreamProjection<T> has StreamId as key type (built-in).
          return (typeArgs[0], null);
        }
      }

      // Check for MultiStreamProjection<T, K>.
      if (_multiStreamProjectionChecker.isExactlyType(supertype)) {
        final typeArgs = supertype.typeArguments;
        if (typeArgs.length >= 2) {
          return (typeArgs[0], typeArgs[1]);
        }
      }

      // Also check using assignable check for extended classes.
      if (superElement is ClassElement) {
        if (_singleStreamProjectionChecker.isAssignableFromType(supertype) && !_multiStreamProjectionChecker.isAssignableFromType(supertype)) {
          final typeArgs = supertype.typeArguments;
          if (typeArgs.isNotEmpty) {
            return (typeArgs[0], null);
          }
        }
        if (_multiStreamProjectionChecker.isAssignableFromType(supertype)) {
          final typeArgs = supertype.typeArguments;
          if (typeArgs.length >= 2) {
            return (typeArgs[0], typeArgs[1]);
          }
        }
      }
    }

    return (null, null);
  }
}
