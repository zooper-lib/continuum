/// Example: Abstract and Interface Aggregates
///
/// This example demonstrates that Continuum can generate event handlers and
/// dispatch logic for aggregates declared as an `abstract class` or an
/// `interface class`.
library;

import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

part 'abstract_interface_aggregates.g.dart';

void main() {
  print('═══════════════════════════════════════════════════════════════════');
  print('Example: Abstract and Interface Aggregates');
  print('═══════════════════════════════════════════════════════════════════');
  print('');

  _runAbstractAggregateExample();
  print('');
  _runInterfaceAggregateExample();
}

void _runAbstractAggregateExample() {
  print('ABSTRACT AGGREGATE');

  final user = AbstractUser(
    id: const AbstractUserId('abstract-user-1'),
    email: 'alice@example.com',
    name: 'Alice',
  );

  print('  Initial state: email=${user.email}');

  user.applyEvent(
    AbstractUserEmailChanged(
      newEmail: 'alice@company.com',
    ),
  );

  print('  After event:   email=${user.email}');
  print('  ✓ Event dispatch works via AbstractUserBase');
}

void _runInterfaceAggregateExample() {
  print('CONCRETE AGGREGATE');

  final user = UserContract(
    id: const UserContractId('contract-user-1'),
    displayName: 'Bob',
  );

  print('  Initial state: displayName=${user.displayName}');

  user.applyEvent(
    ContractUserRenamed(
      newDisplayName: 'Bobby',
    ),
  );

  print('  After event:   displayName=${user.displayName}');
  print('  ✓ Event dispatch works via UserContract');
}

final class AbstractUserId extends TypedIdentity<String> {
  const AbstractUserId(super.value);
}

/// An abstract aggregate base type.
///
/// The generator produces:
/// - `mixin _$AbstractUserBaseEventHandlers`
/// - `extension $AbstractUserBaseEventDispatch on AbstractUserBase`
abstract class AbstractUserBase extends AggregateRoot<AbstractUserId> with _$AbstractUserBaseEventHandlers {
  AbstractUserBase({
    required AbstractUserId id,
    required this.email,
    required this.name,
  }) : super(id);

  String email;
  final String name;
}

/// A concrete implementation of the abstract aggregate.
class AbstractUser extends AbstractUserBase {
  AbstractUser({
    required super.id,
    required super.email,
    required super.name,
  });

  @override
  void applyAbstractUserEmailChanged(AbstractUserEmailChanged event) {
    email = event.newEmail;
  }
}

final class UserContractId extends TypedIdentity<String> {
  const UserContractId(super.value);
}

/// A concrete implementation of the interface aggregate.
class UserContract extends AggregateRoot<UserContractId> with _$UserContractEventHandlers {
  UserContract({
    required UserContractId id,
    required this.displayName,
  }) : super(id);

  String displayName;

  @override
  void applyContractUserRenamed(ContractUserRenamed event) {
    displayName = event.newDisplayName;
  }
}

/// Event that changes an abstract user's email.
@AggregateEvent(of: AbstractUserBase, type: 'example.abstract_user.email_changed')
class AbstractUserEmailChanged implements ContinuumEvent {
  AbstractUserEmailChanged({
    required this.newEmail,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String newEmail;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory AbstractUserEmailChanged.fromJson(Map<String, dynamic> json) {
    return AbstractUserEmailChanged(
      newEmail: json['newEmail'] as String,
      eventId: EventId.fromJson(json['eventId'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }

  Map<String, dynamic> toJson() => {
    'newEmail': newEmail,
    'eventId': id.value,
    'occurredOn': occurredOn.toIso8601String(),
    'metadata': metadata,
  };
}

/// Event that renames a user implementing an interface aggregate.
@AggregateEvent(of: UserContract, type: 'example.contract_user.renamed')
class ContractUserRenamed implements ContinuumEvent {
  ContractUserRenamed({
    required this.newDisplayName,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String newDisplayName;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory ContractUserRenamed.fromJson(Map<String, dynamic> json) {
    return ContractUserRenamed(
      newDisplayName: json['newDisplayName'] as String,
      eventId: EventId.fromJson(json['eventId'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }

  Map<String, dynamic> toJson() => {
    'newDisplayName': newDisplayName,
    'eventId': id.value,
    'occurredOn': occurredOn.toIso8601String(),
    'metadata': metadata,
  };
}
