import 'package:continuum/continuum.dart';
import 'package:continuum_store_hive_example/domain/account.dart';

/// Runs the account scenarios using a persistent event store.
final class AccountScenarios {
  /// Opens an account.
  static Future<void> openAccountAsync({
    required EventSourcingStore store,
    required StreamId accountId,
    required String ownerId,
  }) async {
    final Session session = store.openSession();

    final Account account = session.startStream<Account>(
      accountId,
      AccountOpened(
        eventId: const EventId('acct-evt-1'),
        accountId: accountId.value,
        ownerId: ownerId,
      ),
    );

    await session.saveChangesAsync();
    print('Session 4: Account "${account.id}" opened for owner: ${account.ownerId}');
  }

  /// Loads the account and performs a deposit/withdraw sequence.
  static Future<void> depositAndWithdrawAsync({
    required EventSourcingStore store,
    required StreamId accountId,
  }) async {
    final Session session = store.openSession();

    final Account loadedAccount = await session.loadAsync<Account>(accountId);
    print('Session 5: Loaded account with balance: \$${loadedAccount.balance}');

    session.append(
      accountId,
      FundsDeposited(eventId: const EventId('acct-evt-2'), amount: 250),
    );
    session.append(
      accountId,
      FundsWithdrawn(eventId: const EventId('acct-evt-3'), amount: 75),
    );

    await session.saveChangesAsync();
    print('Session 5: After deposit \$250 and withdraw \$75: \$${loadedAccount.balance}');
  }
}
