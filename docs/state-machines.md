# State Machine Support in Yamoon

Yamoon provides first-class support for state machines, making it easier to build complex Gall agents with distinct operational modes.

## 1. Overview

Instead of a single flat `state`, you can define a `machine` block. This allows you to:
- Group pokes, scries, and watches by state.
- Ensure certain actions are only possible in specific states.
- Explicitly manage transitions between states.
- Shared data across all states via `common`.

## 2. Syntax

```yaml
machine:
  # Initial state and its required data
  initial:
    to: Idle
    data: { }

  # Data available in all states
  common:
    owner: ship
    logs: list<text>

  states:
    Idle:
      pokes:
        start:
          input: { task: text }
          transition:
            to: Running
            data: { current_task: task, progress: 0 }
            common: { logs: "prepend('Started task', logs)" }

    Running:
      # Data specific to this state
      data:
        current_task: text
        progress: number
      
      pokes:
        update:
          input: { inc: number }
          transition:
            to: Running
            data: { progress: "progress + inc" }
        
        finish:
          transition:
            to: Idle
            common: { logs: "prepend('Finished task', logs)" }

      scries:
        /status/progress:
          output: number
          body: progress
```

## 3. Key Concepts

### Initial State
The `initial` block defines which state the agent starts in and provides any initial values for that state's data.

### Common Fields
Fields defined in `common` are always available in the `state` scope across all handlers. They are preserved during transitions unless explicitly updated.

### State Data
Each state can have its own `data` block. These fields are only accessible when the agent is in that specific state. When transitioning to a new state, you must provide all fields required by that state's `data` block.

### Transitions
The `transition` expression is used to change the agent's state.
- `to`: The name of the target state.
- `data`: A dictionary of values for the target state's data fields.
- `common`: (Optional) A dictionary of updates for common fields.

### Scope
Inside a state-specific handler (poke, scry, or watch):
- `state.field` or just `field` (if unambiguous) provides access to both `common` fields and the current state's `data` fields.
- Yamoon automatically binds these fields into the Hoon subject.

## 4. Compilation to Hoon

Yamoon compiles the state machine into an idiomatic Hoon pattern:
- The state mold is a tagged union of state modes.
- Core Gall arms (`+on-poke`, `+on-peek`, `+on-watch`) use `?-` (wut-hep) to dispatch based on the current state mode.
- Handlers are generated as private arms within the agent core.
- Transitions are lowered to state updates that change the mode tag and associated data.
