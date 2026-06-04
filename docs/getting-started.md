# Getting Started with yamoon

yamoon is a high-level, developer-friendly language that transpiles to idiomatic, production-ready Hoon. It combines the declarative power of YAML with a natural expression language to bring modern DX to Urbit development.

## 1. Installation

yamoon requires Node.js 18+ and a compiled version of the compiler core.

```bash
# Clone the repository
git clone https://github.com/your-org/yamoon
cd yamoon

# Install dependencies
npm install

# Build the compiler
npx elm make src/Main.elm --output=wrapper/elm.js --optimize
mv wrapper/elm.js wrapper/elm.cjs
```

The `yamoon` CLI is now ready to use via `./wrapper/cli.js`.

## 2. Your First Library

Create a file named `math.hyml`:

```yaml
module: math

docs:
  - "A simple math library built with yamoon"

functions:
  square:
    input: { n: number }
    output: number
    return: n * n

  sumOfSquares:
    input: { a: number, b: number }
    output: number
    return: square(a) + square(b)
```

Compile it to Hoon:
```bash
./wrapper/cli.js compile math.hyml
```

Output:
```hoon
::  A simple math library built with yamoon

|%
  ++  square
    |=  n=@ud
      (mul n n)

  ++  sumOfSquares
    |=  [a=@ud b=@ud]
      (add (square a) (square b))
--
```

## 3. Your First Gall Agent

yamoon automates the boilerplate of state management and routing. Create `counter.hyml`:

```yaml
module: examples.counter

options:
  target: gall

state:
  version: 0
  data:
    count: number

pokes:
  increment:
    mark: count-action
    input: { amount: number }
    return:
      pure:
        state:
          count: state.count + amount

scries:
  /val:
    output: number
    return: state.count
```

Compile it to a full Gall door:
```bash
./wrapper/cli.js compile counter.hyml
```

The compiler will automatically generate:
- The versioned `state-v0` mold.
- The `+on-poke` router that dispatches `%increment`.
- The `+on-peek` scry tree for `/val`.
- Standard agent boilerplate (`on-init`, `on-save`, etc.).

## 4. Next Steps

- Explore the [Language Reference](./language-reference.md) for advanced types and expressions.
- Learn about [Gall Agent Patterns](./gall-agents.md) for complex agent development.
- Check out the `examples/` directory for real-world usage.
