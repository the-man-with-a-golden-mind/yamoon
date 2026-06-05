# Testing in yamoon

Yamoon provides a comprehensive, multi-layer testing strategy to ensure that your code is not just syntactically correct, but logically sound and strictly Urbit-compliant.

## 1. Production vs. Test Isolation

**Yamoon strictly isolates test code from production code.** 
When you write a `tests:` block in your `.hyml` file, it is **never** included in the standard production output.

*   `yamoon compile <file.hyml>`: Generates *only* the production Gall agent or Library core (`|%` or `|_`).
*   `yamoon test <file.hyml>`: Generates *only* the isolated Urbit `+test` generator (which imports `/+  test` and uses `expect-eq`).

This ensures your production pier is never bloated with testing boilerplate.

## 2. Docker-Based Urbit Verification (Gold Standard)

To be 100% sure that the generated Hoon is correct, you can run a full end-to-end verification in a containerized Urbit environment. This guarantees that your tests evaluate to the correct values when run through the actual Nock VM.

### The Pipeline Workflow:
1.  **Boot**: A real Urbit binary is downloaded and boots a fake `~zod` development ship.
2.  **Compile & Isolate**: Yamoon compiles your `.hyml` files, separating the logic into production code (`zod/base/lib/`) and test code (`zod/base/tests/lib/`).
3.  **Sync**: The generated Hoon files are injected into the ship's filesystem.
4.  **Execute**: The native Urbit `-test` runner is triggered via the Dojo.
5.  **Evaluate**: The script asserts that the Nock VM successfully executed your code and that all `expect-eq` assertions passed.

### How to Run:
```bash
# Requires Docker to be installed and running on your machine
bun run test:docker
```

## 3. Writing Tests in .hyml

### Unit Tests
Test pure functions by providing input/expect pairs.
```yaml
tests:
  square_logic:
    kind: unit
    func: square
    cases:
      - input: { x: 4 }
        expect: 16
```

### Scenario Tests (Amazing Testing Framework)
Test stateful Gall agents by defining a journey. Yamoon automatically threads the agent state through a sequence of interactions.
```yaml
tests:
  counter_journey:
    kind: scenario
    setup: initialState
    steps:
      - action: { action: "poke", route: "increment", payload: { amount: 5 } }
        expect:
          state: { count: 5 }
      - action: { action: "wait", duration: "~h1" }
        expect:
          scries: { "/count": 5 }
```

## 4. Manual Verification
You can manually sync your code to a local pier and run tests in the Dojo without Docker.
```bash
# 1. Sync
yamoon sync my_agent.hyml /path/to/pier

# 2. In Dojo
|mount %base
-test /=base=/tests/lib/my_agent
```
