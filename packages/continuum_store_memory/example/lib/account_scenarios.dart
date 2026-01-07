import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory_example/domain/account.dart';

/// Runs the bank account scenarios.
final class AccountScenarios {
  /// Creates an account for [ownerId] and performs a deposit/withdraw sequence.
  static Future<StreamId> runAccountLifecycleAsync({
    required EventSourcingStore store,
    required String ownerId,
  }) async {
    final StreamId accountId = const StreamId('account-001');

    // Create the account.
    Session session = store.openSession();
    final Account account = session.startStream<Account>(
      accountId,
      AccountOpened(
        eventId: const EventId('acct-evt-1'),
        accountId: 'account-001',
        ownerId: ownerId,
      ),
    );

    await session.saveChangesAsync();
    print('Account "${account.id}" opened for owner: ${account.ownerId}');

    // Deposit.
    session = store.openSession();
    final Account loadedAccount = await session.loadAsync<Account>(accountId);

    session.append(
      accountId,
      FundsDeposited(eventId: const EventId('acct-evt-2'), amount: 250),
    );

    await session.saveChangesAsync();
    print('Deposited \$250. New balance: \$${loadedAccount.balance}');

    // Withdraw.
    session = store.openSession();
    final Account withdrawAccount = await session.loadAsync<Account>(accountId);

    session.append(
      accountId,
      FundsWithdrawn(eventId: const EventId('acct-evt-3'), amount: 75),
    );

    await session.saveChangesAsync();
    print('Withdrew \$75. Final balance: \$${withdrawAccount.balance}');

    return accountId;
  }
}
