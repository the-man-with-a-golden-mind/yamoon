# yamoon Language Reference: Full Coverage

This guide provides an exhaustive reference for the yamoon language, designed for professional developers building production-grade Urbit applications.

## 1. Top-Level Program Structure

A yamoon project is defined in a `.hyml` file. It organizes your code into logical blocks that the compiler transforms into a single, idiomatic Hoon module.

| Block | Syntax | Description |
|---|---|---|
| `module` | `module: lib.utils` | Hierarchical name. |
| `imports`| `- /+ dbug` | List of native Hoon import runes. |
| `options`| `{ target: "gall" }` | Compiler configuration. |
| `types` | `name: { kind: "record", fields: {...} }` | Custom data schemas. |
| `macros` | `name: { args: [...], expand: ... }` | Syntactic substitutions. |
| `native` | `name: { input: {...}, output: Type }` | External library type signatures. |
| `state` | `{ version: 0, data: {...} }` | (Gall) Persistent agent state. |
| `on_load` | `expr` | (Gall) State migration logic. |
| `pokes` | `name: { mark: "tas", return: ... }` | (Gall) Action handlers. |
| `watches`| `path: expr` | (Gall) Subscription handlers. |
| `scries` | `path: { output: Type, return: ... }` | (Gall) Read interface tree. |
| `constants`| `name: { type: Type, value: ... }` | Global values. |
| `functions`| `name: { type_args: [...], input: {...}, output: Type, jet: "tag", return: ... }` | Deterministic gates. |
| `tests` | `name: { kind: "unit", ... }` | Integrated test suite. |

---

## 2. Comprehensive Type System

yamoon's type system is strictly checked and ensures that your YAML logic is always valid Hoon.

### 2.1 Primitive Types
- `number` / `nat`: Unsigned decimal (`@ud`). The foundation of Urbit counting.
- `text`: Textual data. Mapped to `cord` (atom) or `tape` (list) based on `options.text`.
- `bool`: Boolean value (`?`). Constants are `true` (`%.y`) and `false` (`%.n`).
- `card`: A Gall system card used for inter-agent communication.
- `any`: A universal type that matches any Hoon noun. Use this when interfacing with external libraries.

### 2.2 Container Types
- `list<T>`: A standard Hoon list. Operations: `first()`, `rest()`, `append()`, `prepend()`, `map()`, `filter()`, `fold()`.
- `pair<A, B>`: A Hoon cell. Lowered to `[A B]`.
- `map<K, V>`: An associative array. Operations: `get()`, `put()`, `has()`. Lowered to the `%by` engine.
- `set<T>`: A collection of unique items. Operation: `has()`. Lowered to the `%in` engine.
- `T?`: A Hoon unit. Mapped to `(unit T)`. Shorthand for "value or null (`~`)".

### 2.3 Algebraic Data Types (ADTs)
- **Records**: Fixed sets of named fields. Mapped to idiomatic Hoon `,[]` structures.
- **Unions**: Sum types (enums with data). Mapped to Hoon `$%(...)` variants.
  ```yaml
  types:
    Shape:
      kind: union
      variants:
        Circle: { radius: number }
        Square: { side: number }
        Point: none
  ```

---

## 3. Control Flow & Rune Coverage

yamoon provides high-level named constructs for every core Hoon rune, achieving 100% coverage without the "tragic" rune syntax.

### 3.1 Logical Runes
- **If/Then/Else**: `if: cond then: val1 else: val2` (Maps to `?:`).
- **IfNot**: `if_not: cond then: val1 else: val2` (Maps to `?.`). Use this to handle error/success cases where the "error" branch is prioritized.

### 3.2 Assertion Runes
Assertions crash the Nock VM if the condition is not met, serving as runtime guards.
- **Assert**: `assert: condition in: body` (Maps to `?>`).
- **Unless**: `unless: condition in: body` (Maps to `?<`).

### 3.3 State & Binding Runes
- **Let**: `let: { x: 5 } in: x + 1` (Maps to `=+`). Creates a new variable in the subject.
- **Set**: `set: { x: 10 } in: body` (Maps to `=.`). Changes the value of an existing variable in the subject.

### 3.4 Pattern Matching
- **Match**: `match: target cases: { Tag: expr } default: expr` (Maps to `?+`).
  Yamoon automatically handles variant tag matching and field extraction hints.

---

## 4. Expressions & Object Literals

Yamoon supports complex nested expressions with modern syntax.

### 4.1 Object Literals
You can write JSON-like object literals directly in your expressions.
```yaml
return: "ja({ a: a + 1, b: b + 2 })"
```
Yamoon automatically transforms these into the optimized treap structures required by Hoon's standard library.

---

## 5. Loops & Tail Recursion

Urbit logic is built on "Traps" (`|-`). Yamoon provides a robust `loop` construct that ensures tail-call optimization for infinite or deep recursion.

### 5.1 The `loop` Block
A loop initializes a local state and defines a body that can call itself.

```yaml
functions:
  factorial:
    input: { n: number }
    output: number
    return:
      loop:
        args: { i: 1, acc: 1 }
        return:
          if: i > n
          then: acc
          else: recurse(i + 1, acc * i)
```

### 5.2 How it works
1. **Initialization**: `args` sets the starting values.
2. **Body**: The `return` expression defines the logic.
3. **Tail Recursion**: The `recurse(...)` built-in maps to the Hoon `$` (buc) rune. It restarts the loop with new values for the `args`, without growing the stack.

---

## 6. Subject Navigation (Wings)

Urbit's power comes from navigating the subject tree. Yamoon supports this natively:

- **Field Access**: `user.name` is the standard way to reach into a record.
- **Parent subject (`..`)**: Use `..name` to reach an arm or variable in the parent core/scope.
- **Outer scope (`^`)**: Use `^var` to bypass a local variable and reach one with the same name in the outer subject.

---

## 7. Native Interfaces (native:)

Use the `native:` block to "teach" Yamoon about existing Hoon libraries (`/+`, `/-`, etc.). This enables static type-checking for third-party code.

### 7.1 Defining an Interface
```yaml
imports:
  - /+  my-lib

native:
  my-lib:
    type_args: [T]
    input: { data: T }
    output: any
```

---

## 8. Generics & Polymorphism (type_args:)

Yamoon supports Rust-like strong generics for both custom functions and native library interfaces. This allows you to write reusable logic without losing type safety.

### 8.1 Generic Functions
Declare type parameters in the `type_args` list. These parameters can then be used in the `input` and `output` fields.

```yaml
functions:
  identity:
    type_args: [T]
    input: { val: T }
    output: T
    return: val
```

### 8.2 Type Inference & Instantiation
When you call a generic function, the Yamoon compiler automatically infers the types for the parameters based on the arguments you provide.

- `identity(42)` -> Compiler binds `T = number`. Result type is `number`.
- `identity("hello")` -> Compiler binds `T = text`. Result type is `text`.

### 8.3 Strict Constraint Checking
The compiler enforces consistency across all arguments. If a function expects `pair<T, T>` and you provide `pair<number, text>`, the compiler will throw a **Generic Conflict** error.

---

## 9. Macro System

Macros perform syntactic substitution before type-checking or compilation. Use them to create domain-specific languages within your project.

```yaml
macros:
  myGuard:
    args: [val]
    expand:
      assert: val != 0
      in: val
```
When you call `myGuard(x)`, the compiler replaces it with the full `assert` block before continuing.

---

## 10. Integrated Testing Framework

Yamoon is the first Urbit tool to provide declarative, state-aware testing.

- **Production Isolation**: Test code is completely separated from production output. `yamoon compile` produces lean agent/library code. `yamoon test` produces isolated `+test` generators.
- **Unit Tests**: Map inputs to expected outputs for pure functions.
- **Scenario Tests**: Thread state through a series of pokes and waits for Gall agents.

Use `yamoon test my_file.hyml` to generate an Urbit-ready `+test` generator.

---

## 11. Current Limitations (v1.0)

While Yamoon is production-ready for application development, there are a few architectural limitations to be aware of:

1.  **Vanes and Marks**: Yamoon currently targets `library` and `gall` (agents). It cannot currently be used to author custom system Vanes or Mark definition files natively.
2.  **Complex Migrations**: State migrations (`on_load`) support automatic threading of the `old=vase`. However, complex, multi-version leapfrogging (e.g., v0 -> v1 -> v2) may require leveraging the `raw-hoon` escape hatch for precise mold mapping.
3.  **Frontend Generation**: Yamoon orchestrates the backend Urbit logic. It does not currently generate frontend UI code (React/Svelte), though it plays perfectly with standard `@urbit/http-api` workflows.
