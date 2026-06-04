# yamoon

A DX-friendly, YAML-inspired authoring language that transpiles to idiomatic Hoon.

yamoon makes writing Hoon pleasant and efficient by hiding its complex rune-based syntax and specific atom molds behind familiar concepts. It provides a robust, type-checked pipeline for building Hoon libraries and Gall agents.

## Key Features

- **YAML-Native Declarations**: Use YAML for structural elements (modules, types, constants).
- **Natural Expression Language**: Write logic using standard operators (`+`, `-`, `==`, etc.).
- **Smart Type System**: High-level types (`number`, `text`, `bool`, `?`) map automatically to verified Hoon molds.
- **Advanced Gall Patterns**: Automated versioned state, automated poke routing, and structured scry trees.
- **Built-in Editor**: A web-based IDE with syntax highlighting, code completion, and a live compiler, accessible via `yamoon --serve`.
- **100% Rune Coverage**: Use the `rune` escape hatch to express any Hoon pattern while maintaining a clean DSL.
- **Precise Diagnostics**: Position-aware error reporting that points to the exact line and column in your expression strings.

## Quick Example

```yaml
module: examples.math

functions:
  square:
    input: { n: number }
    output: number
    return: n * n
```

Compiles to:

```hoon
|%
  ++  square
    |=  n=@ud
      (mul n n)
--
```

## Documentation

- [Getting Started](docs/getting-started.md)
- [Language Reference](docs/language-reference.md)
- [Gall Agent Patterns](docs/gall-agents.md)
- [Testing Framework](docs/testing.md)
- [Web Editor](docs/editor.md)
- [AI Subagent Reference](docs/AI.md)

## Development

The project is built in Elm with a Node.js wrapper.

```bash
# Install dependencies
npm install

# Build the compiler core
npx elm make src/Main.elm --output=wrapper/elm.js --optimize
mv wrapper/elm.js wrapper/elm.cjs

# Build the IDE
npm run ide:build

# Run tests
npx elm-test
./scripts/test_examples.sh
```

## License

MIT
