# yamoon for AI Agents

This is a technical reference for AI subagents to author, refactor, and debug yamoon (`.hyml`) files.

## 1. Syntax Rules

### Top-Level Keys
- `module`: dot-separated string.
- `options`: `{ target: "library" | "gall", text: "cord" | "tape" }`.
- `imports`: List of Hoon runes (e.g., `- /+  dbug`).
- `types`: Map of name -> `{ kind: "record", fields: Map }` or `{ kind: "union", variants: Map }`.
- `functions`: Map of name -> `{ input: Map, output: Type, return: Expr }`.
- `state`: (Gall only) `{ version: Int, data: Map }`.
- `tests`: Map of name -> `UnitTest | ScenarioTest | MigrationTest`.

### Expression Language (Expr)
Expressions are strings within YAML values or nested objects.
- **Literals**: `42`, `"text"`, `true`, `~`.
- **Interpolation**: `"Hello, {name}"`.
- **Operators**: `+`, `-`, `*`, `==`, `!=`, `>`, `<`, `>=`, `<=`.
- **Control Flow**:
  - `if: <Expr> then: <Expr> else: <Expr>`
  - `if_not: <Expr> then: <Expr> else: <Expr>` (Hoon `?.`)
  - `assert: <Expr> in: <Expr>` (Hoon `?>`)
  - `unless: <Expr> in: <Expr>` (Hoon `?<`)
  - `match: <Expr> cases: { Tag: <Expr>, ... } default: <Expr>`
- **Recursion**: `loop: { args: { i: 0 }, return: recurse(i + 1) }`.
- **Wings**: `..name` (parent subject), `^var` (outer scope).
- **ADTs**: `TypeName:VariantName { field: value }` or `TypeName:VariantName: none`.

## 2. Type Authoring Reference

| Type Syntax | Hoon Equivalent |
|---|---|
| `number` | `@ud` |
| `text` | `cord` or `tape` |
| `bool` | `?` |
| `list<T>` | `(list T)` |
| `pair<A, B>`| `[A B]` |
| `T?` | `(unit T)` |
| `map<K, V>` | `(map K V)` |

## 3. Gall Agent Patterns

### Standard Transition
`return: pure(state)` or `return: [ [note1 note2] state ]`.

### State Update
```yaml
return:
  pure:
    state:
      count: state.count + 1
```

### State Migration
```yaml
on_load:
  let: { old: "((unit state) (mole [old state]))" }
  in: if: old == ~ then: pure(init) else: pure(first(old))
```

## 4. Testing Framework (tests:)

### Unit Test
```yaml
tests:
  my_test:
    kind: unit
    func: my_func
    cases: [{ input: { x: 1 }, expect: 2 }]
```

### Scenario Test
```yaml
tests:
  my_scenario:
    kind: scenario
    setup: initialState
    steps:
      - action: poke
        route: my_poke
        payload: { x: 1 }
        expect: { scries: { /val: 1 } }
```

## 5. Debugging & Error Mapping

- **Position Awareness**: Errors report `At line X, col Y`.
- **Path Awareness**: Errors report `In functions.name.return`.
- **Common Fixes**:
  - `Type mismatch`: Check `options.text` or add `^-` via `cast(Type, Expr)`.
  - `Unknown name`: Check wing syntax (`^`) or ensure variable is in `let` / `loop.args`.
  - `Arity mismatch`: Built-ins like `scry` or `get` require exact argument counts.

### Web Editor
Run `yamoon --serve` to launch the IDE. AI agents can use this to visually debug generated Hoon code.

## 6. Built-in Primitives (Prompting)

Use these built-ins for idiomatic code:
- `first(l)`, `rest(l)`, `append(l, x)`, `prepend(x, l)`, `map(l, f)`, `filter(l, p)`, `fold(l, i, f)`.
- `get(m, k)`, `put(m, k, v)`, `has(m, k)`.
- `scry(Mark, Path)`, `pure(State)`, `give(Path, Gift)`, `scot(Mark, Val)`.
- `nock(formula)` (Raw access).
