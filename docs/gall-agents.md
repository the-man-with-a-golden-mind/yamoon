# Advanced Gall Agent Development with yamoon

This guide covers professional patterns for building production-ready Gall agents using yamoon. It focuses on state management, Arvo kernel compatibility, and reactive messaging.

## 1. The Agent Anatomy

When `target: gall` is set in the project options, yamoon transforms your YAML project into a standard Urbit "Door" (`|_`). This door implements all 10+ standard Gall arms, routing them to your custom handlers or standard defaults.

### 1.1 Door Structure
The compiler automatically generates the boilerplate for:
- `+on-init`: Primary initialization.
- `+on-save`: State serialization.
- `+on-load`: State migration and reload logic.
- `+on-poke`: Action routing.
- `+on-watch`: Subscription handling.
- `+on-peek`: Read interface (scries).
- `+on-leave`, `+on-agent`, `+on-arvo`, `+on-fail`: Defaulted handlers.

---

## 2. Professional State Management

Yamoon treats state as a first-class, versioned object.

### 2.1 State Versioning
Define your state schema in the `state:` block.
```yaml
state:
  version: 0
  data:
    count: number
    logs: list<text>
```
The compiler generates a `state-v0` mold and a `state` alias. When you increment the version, you enable the `on_load` migration path.

### 2.2 Initial State
You **must** define an `initialState` constant that matches your state schema.
```yaml
constants:
  initialState:
    state:
      count: 0
      logs: []
```

### 2.3 State Migration (`on_load`)
Use the `on_load` block to upgrade state when your code is reloaded.
```yaml
on_load:
  let: { old: "((unit state) (mole [old state]))" }
  in:
    if: old == ~
    then: pure(initialState) # Fresh install
    else: pure(first(old))  # Upgrade existing state
```

---

## 3. High-Performance Poke Routing

Yamoon simplifies poke handling by automating mark matching and payload unpacking.

### 3.1 Declarative Routing
Define your pokes in the `pokes:` block.
```yaml
pokes:
  increment:
    mark: count-action # Matches %count-action mark
    input: { amount: number }
    return:
      pure:
        state:
          count: state.count + amount
```

### 3.2 Mark-Based Dispatch
The compiler generates a central `+on-poke` arm that matches the incoming mark. 
- If a `mark` is specified, it matches that exact mark.
- If omitted, it matches `%tas` (standard atom).
- It automatically uses `q.vase` to unpack the data for your handler.

---

## 4. Structured Scry Trees (`on-peek`)

Scries are the primary way to read data from an agent. Yamoon generates a highly optimized `+on-peek` tree from your `scries:` block.

```yaml
scries:
  /count:
    output: number
    return: state.count
  
  /logs/all:
    output: list<text>
    return: state.logs
```

### 4.1 Path Matching
The compiler transforms paths like `/logs/all` into idiomatic Hoon path matches: `[%logs %all ~]`.

### 4.2 Type Casting & Wrapping
Generated scries are automatically:
1.  **Casted**: Wrapped in `^- (unit (unit cage))`.
2.  **Vased**: Packed using `!>` for type safety.
3.  **Scoped**: Connected to your agent's current state.

---

## 5. Reactive Messaging (Cards)

Agents communicate using "Cards". Yamoon provides high-level helpers for the two primary communication patterns.

### 5.1 Gifts (Subscriptions)
Notify subscribers of changes using `give()`.
```yaml
watches:
  /updates: pure(state) # Auto-send state on subscribe
```

### 5.2 Notes (Outbound Actions)
Send messages to other agents or system vanes using `pass()`.
```yaml
# Syntax: pass(path, vane, task, payload)
let: { note: "pass(/timer, %b, %wait, now+~h1)" }
in: [ [note] state ]
```

---

## 6. Arvo Compatibility Hardening

Yamoon-generated agents are strictly compliant with the **Urbit Arvo/Gall kernel specification**. They handle:
- **Vase Unpacking**: Safe extraction of nouns from system vases.
- **Cage Packing**: Standardized wrapping of results for inter-vane communication.
- **Door Semantics**: Proper door samples (`bowl`) are available via the subject.

**Yamoon allows you to focus on the business logic of your agent while it handles the complex, low-level mechanics of the Urbit kernel.**
