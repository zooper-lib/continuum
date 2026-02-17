## 1. Runnable Example

- [x] 1.1 Create `example/lib/store_state_based.dart` with a fake `AggregatePersistenceAdapter<User>` that simulates backend fetch/persist with print statements
- [x] 1.2 In the example, construct a `StateBasedStore` with the fake adapter and `$aggregateList`
- [x] 1.3 In the example, open a session, apply a creation event and a mutation event via `applyAsync`, call `saveChangesAsync`, and print committed events
- [x] 1.4 In the example, open a second session, load the aggregate via `loadAsync`, and print its state
- [x] 1.5 Verify the example compiles and runs with `dart run store_state_based.dart`

## 2. Example Index

- [x] 2.1 Add `store_state_based.dart` to the `example/main.dart` library doc comment under a "STATE-BASED PERSISTENCE" heading
- [x] 2.2 Add `store_state_based.dart` to the `main()` print output under the same heading

## 3. README — State-Based Store Section

- [x] 3.1 Add a "### State-Based Store" subsection after the existing "### Event Sourcing Store" subsection under "Core Concepts"
- [x] 3.2 Include a construction snippet showing `StateBasedStore(adapters: {User: UserApiAdapter(...)}, aggregates: $aggregateList)`
- [x] 3.3 Include a concrete `AggregatePersistenceAdapter` implementation example showing `fetchAsync` and `persistAsync`
- [x] 3.4 Add brief explanatory text and key properties (parallel structure to Event Sourcing Store section)

## 4. README — Mode 3 Quick-Start Update

- [x] 4.1 Replace the "Mode 3: Hybrid with Backend" code snippet in the "Use Your Aggregate" section with a `StateBasedStore`-based snippet showing `store.openSession()` → `applyAsync` → `saveChangesAsync`
- [x] 4.2 Verify the updated snippet is visually parallel to the Mode 2 (Event Sourcing) snippet above it

## 5. Verification

- [x] 5.1 Run `dart analyze` on the example package to verify no errors
- [x] 5.2 Verify all existing examples still compile
- [x] 5.3 Review the README for consistent formatting and no broken markdown
