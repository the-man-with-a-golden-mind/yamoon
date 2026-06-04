# yamoon Language Reference

This document provides a detailed reference for the yamoon language, including types, expressions, and the standard library.

## 1. Top-Level Structure

A `.hyml` file is a YAML document containing:

| Field | Description | Required |
|---|---|---|
| `module` | The hierarchical module name (e.g., `lib.utils`). | Yes |
| `docs` | List of documentation comments. | No |
| `options` | Compiler configuration (target, text, number). | No |
| `imports` | Native Hoon import runes (`/+`, `/-`, `/lib`). | No |
| `types` | Custom record and union definitions. | No |
| `macros` | Syntactic substitution macros. | No |
| `state` | Gall agent state definition. | No |
| `pokes` | Gall agent poke handlers. | No |
| `watches` | Gall agent subscription handlers. | No |
| `scries` | Gall agent scry tree. | No |
| `on_load` | Gall agent state migration logic. | No |
| `constants`| Global values or expressions. | No |
| `functions`| Reusable gate definitions. | No |

## 2. Type System

yamoon features a strict, formal type system that supports recursion and algebraic data types.

### Primitive Types
- `number`: Unsigned decimal (`@ud`).
- `nat`: Unsigned decimal (`@ud`).
- `text`: Textual data (controlled by `options.text`).
- `bool`: Boolean value (`?`).
- `card`: A Gall system card.

### Complex Types
- `list<T>`: A Hoon list (e.g., `list<number>`).
- `pair<A, B>`: A Hoon cell (e.g., `pair<text, bool>`).
- `quip<card, state>`: A Gall transition tuple `[(list card) state]`.
- `map<K, V>`: A Hoon map.
- `set<T>`: A Hoon set.
- `T?`: A Hoon unit (e.g., `text?`).

### Custom Types
```yaml
types:
  # Record: Fixed fields
  User:
    kind: record
    fields:
      id: number
      name: text
  
  # Union: Tagged variants
  Shape:
    kind: union
    variants:
      Circle: { radius: number }
      Square: { side: number }
      Point: none # Fieldless variant
```

## 3. Expression Language

The expression language supports common programming constructs.

### Arithmetic & Comparison
- `+`, `-`, `*`
- `==`, `!=`, `>`, `<`, `>=`, `<=`

### String Interpolation
Modern string formatting using curly braces:
```yaml
return: "User {name} has ID {id}"
```
Automatically handles type conversion (`scot %ud` for numbers, `scot %t` for text).

### Control Flow
- **If/Then/Else**: `if: condition then: val1 else: val2`
- **IfNot**: `if_not: condition then: val1 else: val2` (Maps to `?.`)
- **Assert**: `assert: condition in: next_expr` (Maps to `?>`)
- **Unless**: `unless: condition in: next_expr` (Maps to `?<`)
- **Set**: `set: { var: val } in: next_expr` (Maps to `=.`)
- **Match**: Pattern matching on unions.
  ```yaml
  match: shape
  cases:
    Circle: shape.radius
    Square: shape.side
  default: 0
  ```

### Functional Constructs
- **Let Binding**: `let: { y: x + 1 } in: y * 2`
- **Loop & Recursion**:
  ```yaml
  loop:
    args: { i: 0 }
    return:
      if: i == 10
      then: 10
      else: recurse(i + 1)
  ```

## 4. Standard Library (Built-ins)

yamoon provides "friendly" names for common Hoon operations:

| Function | Hoon Equivalent | Description |
|---|---|---|
| `first(list)` | `i.list` | Head of a list. |
| `rest(list)` | `t.list` | Tail of a list. |
| `prepend(x, list)`| `[x list]` | Cons an item to a list. |
| `append(list, x)` | `(snoc list x)` | Append an item. |
| `map(list, f)` | `(turn list f)` | Map over a list. |
| `filter(list, p)` | `(skim list p)` | Filter a list. |
| `fold(list, i, f)`| `(roll list f)` | Reduce a list. |
| `get(coll, k)` | `(~(get by coll) k)`| Get from map. |
| `put(coll, k, v)`| `(~(put by coll) k v)`| Put into map. |
| `has(coll, k)` | `(~(has by coll) k)`| Check map/set existence. |
| `scot(mark, v)` | `(scot mark v)` | Convert to atom/text. |
| `scry(Mark, path)`| `.^(Mark path)` | Urbit system scry. |
| `nock(formula)` | `.~ formula` | Raw Nock access. |
| `pure(state)` | `[~ state]` | Basic Gall transition. |

## 5. Subject Navigation (Wings)

Traverse the Hoon subject using native wing syntax:
- `..name`: Access the parent subject (`..`).
- `^var`: Access the parent value of `var` (`^`).
- `var.obj`: Field access (maps to `var.obj` or `obj.var` in Hoon).
