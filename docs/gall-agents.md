# Developing Gall Agents with yamoon

yamoon simplifies Gall agent development by automating boilerplate management, state versioning, and routing.

## 1. Enabling Gall Target

To build an agent, set the target in your options:

```yaml
options:
  target: gall
```

This enables the specialized `state`, `pokes`, `scries`, and `watches` sections.

## 2. State Management

yamoon manages your agent's state as a versioned record.

```yaml
state:
  version: 1
  data:
    count: number
    friends: set<text>
```

The compiler automatically generates:
- `state-v1` mold.
- A transition `on-init` that sets the initial state (must define `initialState` in `constants`).
- Standard `on-save` and `on-load` logic.

### State Migration (`on_load`)
Define how to handle state updates when the agent is reloaded:

```yaml
on_load:
  let: { old_state: "((unit state) (mole [old state]))" }
  in:
    if: old_state == ~
    then: pure(initialState)
    else: pure(first(old_state))
```

## 3. Poke Routing

Instead of a giant nested `?+` tree in `+on-poke`, define handlers declaratively:

```yaml
pokes:
  addFriend:
    mark: friend-action
    input: { name: text }
    return:
      pure:
        state:
          friends: "put(state.friends, name)"
```

- `mark`: The Urbit mark for the poke.
- `input`: The fields to unpack from the noun.
- `return`: A `quip<card, state>` expression.

## 4. Scry Tree (on-peek)

Define your agent's read interface as a map of paths to logic:

```yaml
scries:
  /friends:
    output: list<text>
    return: "map(state.friends, identity)"
  /friend/exists:
    output: bool
    return: "has(state.friends, name)" # name is inferred from path? (future)
```

The compiler generates an optimized `+on-peek` door with path matching and type casting.

## 5. Subscriptions (on-watch)

Handle incoming subscription requests:

```yaml
watches:
  /updates: pure(state)
```

## 6. Messaging & Cards

yamoon provides helpers for generating Gall cards:

| Pattern | Expression | Hoon Equivalent |
|---|---|---|
| **Transition** | `pure(state)` | `[~ state] |
| **Emit Gift** | `give(/path, Gift:Update { ... })` | `[%give /path [%update ...]]` |
| **Pass Note** | `pass(/path, %vane, %task, noun)` | `[%pass /path [%arvo %vane %task noun]]` |

Example of a complex transition:
```yaml
pokes:
  notifyAll:
    input: { msg: text }
    return:
      let: { card: "give(/updates, Task:Notice { text: msg })" }
      in: [ [card] state ]
```
