# Projections (Developer Guide)

This document is a *developer-facing* guide for implementing projections in Continuum.
It focuses on the practical decisions that determine whether your projections stay correct over time:

- Choosing a projection key (`extractKey`)
- Designing events so the key is derivable
- Handling “multi-stream joins” without loading aggregates

## What a projection is (in Continuum terms)

A projection is a pure event consumer that transforms a sequence of events into a read model.

Key constraints:

- A projection **must not load aggregates**.
- A projection **must not issue commands**.
- A projection should be **deterministic**: applying the same event to the same current read model must always yield the same result.

In code, this is represented by `ProjectionBase<TReadModel, TKey>`.
The critical method for correctness is:

- `TKey extractKey(StoredEvent event)`

## The meaning of the key

The key is **the identity of the read model instance** that should be updated by a given event.

Think of it as the primary key of the table/record that stores your read model:

- `UserId` for a “user profile” read model
- `TenantId` for a “tenant dashboard” read model
- `ConversationId` for a “conversation summary” read model

### Rule of thumb

- **Single-stream projections**: key is often the stream ID.
- **Multi-stream projections**: key is usually a *domain identifier shared across events*, not the event stream ID.

## SingleStreamProjection: typical key strategy

A single-stream projection consumes events from exactly one stream per read model instance.

Common choice:

- `extractKey(event) => event.streamId`

This works because:

- all events for that read model instance come from the same stream
- the stream’s identity is the read model’s identity

## MultiStreamProjection: how to build the key correctly

A multi-stream projection intentionally merges events from **multiple streams** into **one** read model instance.

This is exactly why “use `event.streamId` as the key” is usually wrong in multi-stream:

- Different aggregates (different streams) would produce different keys
- You would accidentally create multiple read models where you wanted one

### Correct mental model

For multi-stream projections, `extractKey` must answer:

> “Which read model row does this event belong to?”

Not:

> “Which stream did this event come from?”

### Practical key sources (in order of preference)

#### 1) The key is present in the event payload

This is the cleanest design:

- Events emitted by different aggregates include a shared identifier
- Your projection key is that identifier

Example idea:

- `OrderPlaced(orderId, customerId)` and `CustomerEmailChanged(customerId, ...)`
- Read model is “CustomerSummary” keyed by `customerId`

Then:

- For `OrderPlaced`, key is `customerId` (not the order stream ID)
- For `CustomerEmailChanged`, key is `customerId` (often matches the customer stream ID, but you still use the field)

#### 2) The key is derivable from event metadata/stream naming

Sometimes you can derive a domain identifier from the stream ID.
For example, if stream IDs are structured like `customer-<customerId>`.

This can work, but it’s brittle unless your stream ID format is treated as a stable API.

Prefer explicit IDs in the event payload when you can.

#### 3) The key is resolvable via a projection-maintained mapping (“join/index”)

This is the common case when later events do not contain the grouping key.

Example:

- `OrderPlaced(orderId, customerId)` contains both IDs
- later `OrderShipped(orderId)` does *not* contain `customerId`

If your read model is keyed by `customerId`, you need a mapping:

- When you see `OrderPlaced`, store `orderId -> customerId`
- When you see `OrderShipped`, look up `orderId -> customerId` and route to that read model key

Important constraint:

- The mapping must be stored in your read model (or a dedicated auxiliary read model)
- You still do not load aggregates

### What about the very first event?

It’s normal that the first event you see comes from exactly one stream.
That does **not** mean the key should be that stream ID.

The key should still be the read model’s true identity.

If the first event does not contain enough information to determine the key, you have two options:

1) **Change the event schema** to include the required identifier.
2) **Maintain a mapping** seeded by earlier events that *do* contain the identifier.

If neither is possible, you cannot build a correct multi-stream projection.

## “Join” patterns that work well

### Pattern A: Emit correlation IDs in every event

If multiple aggregates contribute to the same read model, ensure each event includes the grouping key.

Pros:

- simplest `extractKey`
- no extra read model/index

Cons:

- requires careful event design discipline

### Pattern B: Maintain an index read model

Create a small read model dedicated to joins.

Example:

- `OrderToCustomerIndex` keyed by `orderId` containing `customerId`

Then other projections can:

- resolve `customerId` from `orderId` deterministically

Pros:

- handles events that only carry local IDs

Cons:

- increases projection surface area

### Pattern C: Use a “root stream” key

Pick one aggregate as the “root” identity of the read model.

Example:

- Read model “CustomerSummary” is keyed by `customerId`
- Customer aggregate is the root
- Order events must carry `customerId` to join

This is essentially Pattern A with an explicit “owner”.

## Type routing vs persistence shape (important for generated projections)

Continuum stores event payloads in `StoredEvent.data` as a serialized map.

Generated projection handlers dispatch on the typed domain event (when available).
Practically:

- Inline paths can provide a typed `domainEvent`
- Persisted events loaded from storage may only have serialized `data` unless your store/executor provides a way to deserialize

Developer takeaway:

- If you rely on typed dispatch in projections, ensure the execution path provides domain events (or a deserialization step) consistently.

## Example (conceptual): multi-stream projection keyed by CustomerId

Below is a conceptual sketch (names are illustrative).

- Read model key: `CustomerId`
- Streams:
  - `customer-<customerId>` emits customer events
  - `order-<orderId>` emits order events

Events:

- `CustomerRegistered(customerId, email)`
- `OrderPlaced(orderId, customerId, total)`
- `OrderShipped(orderId)`

Key strategy:

- `CustomerRegistered` → key is `customerId` (present)
- `OrderPlaced` → key is `customerId` (present)
- `OrderShipped` → requires `orderId -> customerId` mapping

The mapping can be stored in the read model or in an auxiliary index.

## Checklist for adding a MultiStreamProjection

- Decide the read model identity (the key) first.
- Verify that **every event type** you plan to consume can be mapped to that key:
  - directly (event includes the key), or
  - indirectly via deterministic mapping/index.
- Avoid “key = first event’s stream ID” unless the stream is genuinely the read model identity.
- Keep the projection pure: no aggregate loads, no commands, no external IO.

## Common pitfalls

- Using `event.streamId` as the key for multi-stream projections and accidentally creating one read model per aggregate stream.
- Depending on arrival order of events to decide identity.
- Needing the key but not encoding it anywhere (no payload field, no deterministic mapping).
- Treating serialized payload (`StoredEvent.data`) as a typed event object.
