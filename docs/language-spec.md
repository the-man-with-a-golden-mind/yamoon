# yamoon Language Specification v1.0

yamoon is a high-level, DX-friendly abstraction over the Hoon programming language. It uses YAML for declarations and a natural expression language for logic.

## 1. Top-Level Structure

A yamoon file (`.hyml`) consists of a YAML object with the following fields:

- `module`: (Required) The dot-separated module name.
- `docs`: (Optional) A list of strings for documentation comments.
- `options`: (Optional) Compiler settings.
- `imports`: (Optional) List of Hoon import runes (`/+`, `/-`, `/lib`).
- `types`: (Optional) Custom type definitions (records, unions, aliases).
- `macros`: (Optional) Syntactic substitution macros.
- `state`: (Optional, Gall target only) Versioned state definition.
- `on_load`: (Optional, Gall target only) State migration expression.
- `pokes`: (Optional, Gall target only) Poke handlers.
- `watches`: (Optional, Gall target only) Subscription handlers.
- `scries`: (Optional, Gall target only) Scry tree logic.
- `constants`: (Optional) Global constants (values or expressions).
- `functions`: (Optional) Gate definitions with ordered arguments.

## 2. Options

- `target`: `library` (default) or `gall`.
- `text`: `cord` (default) or `tape`.
- `number`: `unsigned` (default) or `atom`.

## 3. Types

### Records
Ordered map of field names to types. Lowered to Hoon `,[]`.
```yaml
types:
  User:
    kind: record
    fields:
      id: number
      name: text
```

### Unions (Algebraic Data Types)
Polymorphic types with tagged variants. Lowered to Hoon `$%(...)`.
```yaml
types:
  Shape:
    kind: union
    variants:
      Circle: { radius: number }
      Square: { side: number }
      Point: none # Fieldless variant
```

### Type References
- `number`: `@ud`.
- `nat`: `@ud`.
- `text`: `cord` or `tape`.
- `bool`: `?`.
- `T?`: `(unit T)`.
- `list<T>`: `(list T)`.
- `pair<A, B>`: `[A B]`.
- `quip<card, state>`: `[(list card) state]`.
- `map<K, V>`: `(map K V)`.
- `set<T>`: `(set T)`.

## 4. Expression Language

yamoon supports a familiar expression syntax with character-level error diagnostics.

- **Arithmetic**: `+`, `-`, `*`
- **Comparison**: `==`, `!=`, `>`, `<`, `>=`, `<=`
- **Logical**: `if/then/else`, `if_not/then/else` (Hoon `?.`)
- **Assertions**: `assert: cond in: expr` (Hoon `?>`), `unless: cond in: expr` (Hoon `?<`)
- **Field Access**: `object.field` (Lowered to `field.object` or irregular wing).
- **Wing Navigation**: `..name` (parent subject), `^var` (outer scope lookup).
- **Interpolation**: `"Sum: {x + y}"` (Lowered to recursive `cat 3` trees).
- **Variant Construction**: `Type:Variant { fields }` or `Type:Variant: none`.
- **Loop & Recursion**:
  ```yaml
  loop:
    args: { i: 0 }
    return: if: i == 10 then: 10 else: recurse(i + 1)
  ```
- **Variable Binding**: `let: { y: x + 1 } in: y * 2`.
- **State Updates**: `set: { var: val } in: next_expr` (Hoon `=.`).
- **Pattern Matching**: `match: shape cases: { Circle: expr, Square: expr } default: expr`.

## 5. Built-in Functions (Standard Library)

- `first(list)`, `rest(list)`: List head/tail.
- `prepend(x, list)`, `append(list, x)`: List insertion.
- `map(list, func)`, `filter(list, pred)`, `fold(list, init, func)`.
- `get(m, k)`, `put(m, k, v)`, `has(m, k)`: Map/Set operations using `by`/`in` engines.
- `pure(state)`: Standard Gall transition `[~ state]`.
- `give(path, gift)`: Gall subscription update card.
- `scry(Mark, path)`: Urbit system lookup (`.^`).
- `scot(mark, value)`: Atomic string conversion.
- `nock(formula)`: Raw Nock access (`.~`).
- `recurse(...)`: Recursive call within a `loop` block (`$`).

## 6. Error Diagnostics

yamoon provides precise, path-aware diagnostics:
- **Syntax Errors**: Reported with `line` and `col` within the expression string.
- **Type Errors**: Reported with the logical path (e.g., `functions.myFunc.return`) and the exact coordinate of the failure.
