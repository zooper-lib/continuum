## REMOVED Requirements

### Requirement: EventSourcingStore configuration

**Reason**: `EventSourcingStore` moves to the `continuum_es` package. Projection configuration is defined in the `continuum-es` capability spec.
**Migration**: Import `EventSourcingStore` from `package:continuum_es/continuum_es.dart`.

### Requirement: Session saveChangesAsync with projections

**Reason**: Session and projection types move to `continuum_es` package. Projection execution during save is defined in the `continuum-es` capability spec.
**Migration**: Import session and projection types from `package:continuum_es/continuum_es.dart`.
