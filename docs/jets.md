# Jet Support in Yamoon

Jets are high-performance C implementations of Hoon functions that allow the Nock VM to bypass slow interpreted code. Yamoon provides first-class support for registering jets in your Urbit applications.

## 1. Overview

When you specify a `jet` in a Yamoon function, the compiler emits the idiomatic Urbit `~%` (sig-cen) signaling rune. This tells the Urbit binary (Vere or King) to look for a matching implementation in its internal jet registry.

## 2. Syntax

To jet a function, add the `jet:` field to any top-level function definition.

```yaml
functions:
  fast_compute:
    input: { x: number, y: number }
    output: number
    jet: "my-custom-tag"
    return:
      # Nock-equivalent fallback logic
      # This runs if the jet is not found in the binary.
      x + y 
```

### Generated Hoon
```hoon
++  fast-compute
  ~%  %my-custom-tag  ..  |=( [x=@ud y=@ud] (add x y) )
```

## 3. Common Use Cases

### 3.1 Standard Urbit Jets
You can use Yamoon to override or explicitly use standard kernel jets if you are building libraries that require extreme performance.
- `jet: "add"`
- `jet: "dec"`
- `jet: "sha256"`

### 3.2 Custom Native Drivers
If you are running a custom Urbit binary with specialized drivers (e.g., for a jetted database, a high-performance regex engine, or a hardware security module), you can register them via Yamoon.

```yaml
functions:
  query_db:
    input: { query: text }
    output: any
    jet: "db-driver-v1"
    return:
      # Fallback to an external API call or a slow Nock implementation
      scry(%x, /my-db/query/{query})
```

### 3.3 Cryptography
Sophisticated cryptographic operations (Zero-Knowledge Proofs, BLS signatures, etc.) are often too slow in Nock. Use jets to bridge to optimized C/Rust implementations.

## 4. Examples

### Example: High-Performance Hashing
```yaml
functions:
  secure_hash:
    input: { val: text }
    output: raw-hoon<atom>
    jet: "sha256"
    return:
      # Slow fallback implementation (if needed) or raw hoon
      rune: ".^"
      args: ["%vx", "/some-fallback"]
```

## 5. Limitations & Best Practices

1.  **Tag Matching**: The string provided in `jet:` must match the `%tag` registered in the Urbit binary exactly (case-sensitive).
2.  **Fallback Requirement**: Yamoon **requires** a `return:` block even for jetted functions. This is a safety feature: jetted functions must be "deterministic" and have a valid Nock implementation for portability across different Urbit binaries.
3.  **Library Target**: Jets are most effective when used in `options: { target: library }`. While they work in Gall agents, they are typically registered at the core/library level.
4.  **No Type-Checking for Jet Tags**: Yamoon verifies your Hoon logic and Yamoon types, but it cannot verify if the `jet` tag actually exists in your Urbit binary until runtime.

## 6. Testing Jetted Functions

Since jets are transparent to the logic, you can test jetted functions using standard Yamoon unit tests.

```yaml
tests:
  test_jet:
    kind: unit
    func: secure_hash
    cases:
      - input: { val: "test" }
        expect: 0x9f86... # Expected Nock result
```

If the test passes, your logic is correct. If the function runs significantly faster than expected, your jet is being picked up by the VM.
