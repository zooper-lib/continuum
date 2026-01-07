import 'package:continuum/continuum.dart';
import 'package:continuum_store_hive_example/domain/account.dart';
import 'package:continuum_store_hive_example/domain/user.dart';

/// Demonstrates atomic multi-stream saves in a persistent store.
final class AtomicScenarios {
  /// Saves changes to [userId] and [accountId] atomically.
  static Future<void> runAtomicSaveAsync({
    required EventSourcingStore store,
    required StreamId userId,
    required StreamId accountId,
  }) async {
    final Session session = store.openSession();

    final User userForAtomicUpdate = await session.loadAsync<User>(userId);
    final Account accountForAtomicUpdate = await session.loadAsync<Account>(accountId);
    final int balanceBeforeAtomicUpdate = accountForAtomicUpdate.balance;

    session.append(
      userId,
      EmailChanged(eventId: const EventId('evt-4'), newEmail: 'jane.atomic@company.com'),
    );
    session.append(
      accountId,
      FundsDeposited(eventId: const EventId('acct-evt-4'), amount: 10),
    );

    await session.saveChangesAsync();
    print('Session 6: Atomic save email=${userForAtomicUpdate.email}');
    print('Session 6: Atomic save balance \$$balanceBeforeAtomicUpdate → \$${accountForAtomicUpdate.balance}');
  }

  /// Demonstrates rollback when a stale session hits a concurrency conflict.
  static Future<void> runRollbackOnConflictAsync({
    required EventSourcingStore store,
    required StreamId userId,
    required StreamId accountId,
  }) async {
    final Session staleSession = store.openSession();
    await staleSession.loadAsync<User>(userId);
    final Account staleAccount = await staleSession.loadAsync<Account>(accountId);
    final int balanceBeforeConflict = staleAccount.balance;

    final Session concurrentWriterSession = store.openSession();
    await concurrentWriterSession.loadAsync<User>(userId);
    concurrentWriterSession.append(
      userId,
      EmailChanged(eventId: const EventId('evt-5'), newEmail: 'jane.concurrent@company.com'),
    );
    await concurrentWriterSession.saveChangesAsync();

    staleSession.append(
      userId,
      EmailChanged(eventId: const EventId('evt-6'), newEmail: 'jane.stale@company.com'),
    );
    staleSession.append(
      accountId,
      FundsDeposited(eventId: const EventId('acct-evt-5'), amount: 999),
    );

    try {
      await staleSession.saveChangesAsync();
    } on ConcurrencyException catch (e) {
      print('Session 7: Atomic save failed (expected ${e.expectedVersion}, found ${e.actualVersion})');
    }

    final Session verificationSession = store.openSession();
    final Account verifiedAccount = await verificationSession.loadAsync<Account>(accountId);
    print('Session 7: After conflict balance still \$${verifiedAccount.balance} (expected \$$balanceBeforeConflict)');
  }
}
