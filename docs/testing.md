# Testing with yamoon

yamoon features a first-of-its-kind, declarative testing framework built directly into the language. You can define your tests alongside your code in the same `.hyml` file, and the compiler will automatically generate idiomatic Hoon `+test` generators.

## 1. Pure Unit Tests

Test your logic functions by providing a list of input/expect pairs.

```yaml
functions:
  square:
    input: { n: number }
    output: number
    return: n * n

tests:
  square_logic:
    kind: unit
    func: square
    cases:
      - input: { n: 4 }
        expect: 16
      - input: { n: 0 }
        expect: 0
    # Future: Automatically generates property tests based on the `number` type!
    fuzz: true 
```

## 2. Stateful Scenario Tests (Gall Agents)

Testing Gall agents is notoriously verbose in Hoon. yamoon's "Scenario" DSL eliminates the boilerplate of state threading and manual dispatch.

```yaml
tests:
  todo_lifecycle:
    kind: scenario
    # Automatically starts with the agent's `initialState`
    setup: initialState 
    steps:
      # Step 1: Add a task
      - action: poke
        route: addTask
        payload: { title: "Buy milk" }
        expect:
          # Assert against your agent's scry endpoints!
          scries: 
            /tasks: [{ id: 1, title: "Buy milk", done: false }]

      # Step 2: Toggle a task (automatically uses the state from Step 1)
      - action: poke
        route: toggleTask
        payload: { id: 1 }
        expect:
          scries:
            /tasks: [{ id: 1, title: "Buy milk", done: true }]

      # Step 3: Advance virtual time
      - action: wait
        duration: ~h1
```

## 3. Migration Tests

Easily verify that your `on_load` logic correctly handles old state versions.

```yaml
tests:
  v0_to_v1_migration:
    kind: migration
    from_version: 0
    old_state: "[%0 count=5]" # Raw Hoon noun representing old state
    expect_state:
      count: 5
      new_field: "default"
```

## 4. Running Tests

To generate a Hoon test file from your yamoon project, use the `test` command:

```bash
yamoon test my_agent.hyml > tests/my_agent_test.hoon
```

The output is a standard Urbit `+test` generator that can be run using the native Urbit test runner.

## Why it's Better

*   **Zero Boilerplate**: No more manual state threading or `+on-poke` dispatch code in tests.
*   **Behavioral Focus**: Tests read like user stories or functional requirements.
*   **Type-Safe**: Test inputs and expectations are validated against your actual schemas during compilation.
*   **Integrated**: Keep your documentation, code, and tests in a single, readable YAML file.
