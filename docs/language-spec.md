# yamoon Language Specification v1.0: Technical Depth

Yamoon is a high-level, specification-compliant authoring language for the Urbit operating system. It provides a purely functional compilation pipeline from declarative YAML/Expression syntax to idiomatic, optimized Hoon.

---

## 1. Program Model

A yamoon project is a single YAML document representing an Urbit module (Library or Gall Agent).

### 1.1 Compilation Targets
- `library`: Outputs a core (`|%`) containing arms. Suitable for `/lib` or `/sur` files.
- `gall`: Outputs an agent door (`|_`) with standardized lifecycle arms.

---

## 2. Core Runes Coverage

Yamoon maps every core Hoon pattern to a named, high-level construct.

| Hoon Rune | yamoon Construct | Context |
|---|---|---|
| `?:` | `if/then/else` | Basic conditional logic. |
| `?.` | `if_not/then/else` | Inverted conditional (error-first). |
| `?>` | `assert: cond in: body` | Positive assertion (crash on fail). |
| `?<` | `unless: cond in: body` | Negative assertion (crash on true). |
| `=+` | `let: { x: val } in: body` | Subject composition (new variable). |
| `=.` | `set: { x: val } in: body` | Subject mutation (existing variable). |
| `?+` | `match: x cases: {...}` | Pattern matching on tag/mold. |
| `|-` | `loop: { args: {...}, return: ... }`| Trap initialization for recursion. |
| `$`  | `recurse(...)` | Trap re-entry (tail recursion). |
| `^-` | `cast(Type, Expr)` | Formal type enforcement. |
| `|=` | `functions: { name: ... }` | Gate definition (arms). |
| `|_` | `options: { target: "gall" }` | Door definition (agent). |
| `.~` | `nock(formula)` | Raw virtual machine access. |
| `.^` | `scry(Mark, path)` | Kernel-level scry. |

---

## 3. Data & Type Semantics

### 3.1 Atoms & Molds
- **Numbers**: Default to `@ud` (unsigned decimal). Supports `atom` option for `@`.
- **Text**: Controlled by `options.text`.
  - `cord`: Single-quoted `'text'`. Optimized for storage.
  - `tape`: Double-quoted `"text"`. Optimized for manipulation.
- **Booleans**: Maps to `?`. Represented as `true` (`%.y`) and `false` (`%.n`).

### 3.2 Containers
- **Cells**: Represented as `[a b]` or `pair<A, B>`. Nesting maps to standard binary trees.
- **Lists**: Strictly typed `list<T>`. Lowered to `(list T)`.
- **Maps/Sets**: High-level abstractions over Hoon's `%by` and `%in` engines.

---

## 4. Subject Tree Navigation

Yamoon implements Urbit's "Wing" navigation system:
- **Direct**: `obj.field`
- **Parent**: `..name` (maps to `..` search).
- **Outer Scope**: `^var` (maps to `^` skip).

---

## 5. Gall Lifecycle Logic

Generated agents follow the standard Gall transition model: `(quip card state)`.

### 5.1 Poke Dispatch
1.  Receive `[mark vase]`.
2.  Match `mark` against the `pokes:` map.
3.  Unpack `vase` to the handler's sample type.
4.  Execute logic and return `[cards state]`.

### 5.2 Scry Propagation
1.  Receive `path`.
2.  Match `path` against the `scries:` map.
3.  Execute logic and wrap result in `(unit (unit cage))`.

---

## 6. Syntactic Macros

Macros are expanded in a dedicated pre-processing pass.
1.  Identify macro call: `name(args)`.
2.  Substitute arguments into the macro's `expand` block.
3.  Recursively repeat until no macro calls remain.
4.  Circular expansion detection prevents compiler hangs.

---

## 7. Precise Diagnostics

The compiler maintains a **Position Map** for every node in the AST.
- **Syntax errors**: Point to the line and column within a YAML value string.
- **Type errors**: Include the logical path (e.g., `pokes.increment.return`) and the source coordinates.
- **Context-aware**: Error messages include the expected vs. actual types in Yamoon syntax (e.g., `expected list<number>, got text`).
