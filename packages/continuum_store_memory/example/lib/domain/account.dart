import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

import 'events/account_opened.dart';
import 'events/funds_deposited.dart';
import 'events/funds_withdrawn.dart';

export 'events/account_opened.dart';
export 'events/funds_deposited.dart';
export 'events/funds_withdrawn.dart';

part 'account.g.dart';

/// A strongly-typed account identifier.
final class AccountId extends TypedIdentity<String> {
  /// Creates an account identifier from a stable string value.
  const AccountId(super.value);
}

/// A bank Account aggregate demonstrating multiple aggregates in one project.
class Account extends AggregateRoot<AccountId> with _$AccountEventHandlers {
  final String ownerId;
  int balance;

  Account._({required AccountId id, required this.ownerId, required this.balance}) : super(id);

  static Account createFromAccountOpened(AccountOpened event) {
    // WHY: Creation events establish initial state for replay.
    return Account._(id: event.accountId, ownerId: event.ownerId, balance: 0);
  }

  @override
  void applyFundsDeposited(FundsDeposited event) {
    // WHY: Balance is derived from event history.
    balance += event.amount;
  }

  @override
  void applyFundsWithdrawn(FundsWithdrawn event) {
    // WHY: Balance is derived from event history.
    balance -= event.amount;
  }
}
