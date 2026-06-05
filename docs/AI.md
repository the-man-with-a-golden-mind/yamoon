# yamoon for AI Agents

This is a technical reference for AI subagents to author, refactor, and debug yamoon (`.hyml`) files.

## 1. Syntax Rules

### Top-Level Keys
- `module`: dot-separated string.
- `options`: `{ target: "library" | "gall", text: "cord" | "tape" }`.
- `imports`: List of Hoon runes (e.g., `- /+  dbug`).
- `native`: Map of lib-name -> `{ type_args: List, input: Map, output: Type }`.
- `types`: Map of name -> `{ kind: "record", fields: Map }` or `{ kind: "union", variants: Map }`.
- `functions`: Map of name -> `{ type_args: List, input: Map, output: Type, return: Expr }`.
- `state`: (Gall only) `{ version: Int, data: Map }`.
- `tests`: Map of name -> `UnitTest | ScenarioTest | MigrationTest`.

### Expression Language (Expr)
Expressions are strings within YAML values or nested objects.
- **Literals**: `42`, `"text"`, `true`, `~`.
- **Object Literals**: `{ key: val, ... }` (Lowered to Hoon treaps).
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
| `any` | `*` (universal match) |

## 3. Generics & Native Interfaces

Use `native:` to declare signatures for imported Hoon libraries.
Use `type_args:` in functions or native blocks to declare polymorphic parameters.

```yaml
native:
  external-lib:
    type_args: [T]
    input: { arg1: T }
    output: T
```

## 4. Gall Agent Patterns

### Standard Transition
`return: pure(state)` or `return: [ [note1 note2] state ]`.

### State Update
```yaml
return:
  pure:
    state:
      count: state.count + 1
```

## 5. Testing Framework (tests:)

Yamoon strictly isolates test code. Tests are compiled separately to a `+test` generator to avoid bloating the production agent.

### Unit Test
```yaml
tests:
  my_test:
    kind: unit
    func: my_func
    cases: [{ input: { x: 1 }, expect: 2 }]
```

## 6. Debugging & Error Mapping

- **Position Awareness**: Errors report `At line X, col Y`.
- **Path Awareness**: Errors report `In functions.name.return`.
- **Common Fixes**:
  - `Generic Conflict`: Multiple arguments matched same parameter `T` to different types.
  - `Type mismatch`: Check `options.text`, add `^-` via `cast(Type, Expr)`, or use `any`.

## 7. Current Limitations

When authoring Yamoon code, be aware of these constraints:
1. **Compilation Targets**: You can only generate `library` or `gall` targets. Do NOT attempt to generate Mark files or System Vanes.
2. **Migrations**: For complex state leapfrogging (e.g. state v0 to v3), use the `raw-hoon` escape hatch inside `on_load`.

## 8. Built-in Primitives (Prompting)

Use these built-ins for idiomatic code:
- `first(l)`, `rest(l)`, `append(l, x)`, `prepend(x, l)`, `map(l, f)`, `filter(l, p)`, `fold(l, i, f)`.
- `get(m, k)`, `put(m, k, v)`, `has(m, k)`.
- `scry(Mark, Path)`, `pure(State)`, `give(Path, Gift)`, `scot(Mark, Val)`.
- `init(Door, Sample)` (Tiggar rune `~.`).
- `my(List)` (Treap construction).
- `nock(formula)` (Raw access).
