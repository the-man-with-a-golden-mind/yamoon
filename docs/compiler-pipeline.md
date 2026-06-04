# yamoon Compiler Pipeline

The yamoon compiler is architected as a series of purely functional transformations, primarily implemented in Elm with a Node.js wrapper for I/O and YAML normalization.

## 1. Pipeline Overview

The compilation process follows these stages:

1.  **Normalization (Node.js)**: Reads the `.hyml` file, parses YAML into a JSON object, and passes it to the Elm core.
2.  **Decoding (Elm)**:
    - Parses the JSON structure into the `Source.Ast.Program` type.
    - Specialized **Expression Parser** (`Source.ExprParser`) captures character-level `line` and `col` positions for all expressions.
3.  **Macro Expansion (Elm)**:
    - Recursively expands all `macros` in the program.
    - Prevents circular expansions and preserves source positions.
4.  **Type Checking (Elm)**:
    - Validates types across functions, constants, and Gall sections.
    - Tracks "Context Paths" (e.g., `functions.fib.return`) for detailed error reporting.
    - Propagates source positions to pinpoint failure coordinates.
5.  **Lowering (Elm)**:
    - Transforms the high-level `Source.Ast` into a structured `Hoon.Ast`.
    - Handles complex mappings: String interpolation to `cat 3` trees, Gall routing to door matches, and collection calls to `by`/`in` engines.
6.  **Pretty Printing (Elm)**:
    - Renders the `Hoon.Ast` into idiomatic, multi-line Hoon source code.
    - Ensures correct indentation and uses Irregular Forms (`=(...)`, `$()`, etc.) where appropriate.

## 2. Key Data Structures

### Source AST (`src/Source/Ast.elm`)
A position-aware AST where every expression is wrapped in a `LocatedExpr` record.

### Hoon AST (`src/Hoon/Ast.elm`)
A semantic representation of Hoon code, including structured nodes for Core Runes (`HIf`, `HLet`, `HMatch`, etc.) and a generic `HRune` escape hatch.

## 3. Position Awareness & Diagnostics

The compiler implements character-level diagnostics by:
1.  Using the `Parser` library's `getRow` and `getCol` during expression parsing.
2.  Storing these coordinates in the `Source.Ast.LocatedExpr`.
3.  Propagating these coordinates through the macro and type-checking phases.
4.  Reporting errors with both the **Logical Path** and the **Source Coordinates**.
