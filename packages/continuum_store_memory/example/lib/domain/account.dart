import 'package:continuum/continuum.dart';

import 'events/account_opened.dart';
import 'events/funds_deposited.dart';
import 'events/funds_withdrawn.dart';

export 'events/account_opened.dart';
export 'events/funds_deposited.dart';
export 'events/funds_withdrawn.dart';

part 'account.g.dart';

/// A bank Account aggregate demonstrating multiple aggregates in one project.
@Aggregate()
class Account with _$AccountEventHandlers {
  final String id;
  final String ownerId;
  int balance;

  Account._({required this.id, required this.ownerId, required this.balance});

  static Account createFromAccountOpened(AccountOpened event) {
    return Account._(id: event.accountId, ownerId: event.ownerId, balance: 0);
  }

  @override
  void applyFundsDeposited(FundsDeposited event) {
    balance += event.amount;
  }

  @override
  void applyFundsWithdrawn(FundsWithdrawn event) {
    balance -= event.amount;
  }
}
