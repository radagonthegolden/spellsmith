# Agent Registry

This project uses a head-agent orchestration model: talk in chat, and work is routed to specialist agents.

Default head agent: codebase-manager.
Main execution specialist for implementation: code-builder.

## Available Agents

- architecture-planner
  - Goal: define implementation plan, constraints, and sequencing before coding.
  - Use for: scoping features, migration plans, multi-file task decomposition, risk mapping.

- code-builder
  - Goal: implement the approved plan with minimal, testable changes.
  - Use for: writing code, wiring files, and delivering functional increments.

- refactor-reviewer
  - Goal: improve code quality and review for regressions.
  - Use for: cleanup passes, consistency refactors, bug-risk audits, and test gap checks.

- godot-expert
  - Goal: provide Godot-focused implementation and review guidance.
  - Use for: GDScript architecture, scenes/signals flow, NodePath safety, performance, and export/runtime concerns.

- codebase-manager
  - Goal: head-agent orchestration for this workspace.
  - Use for: routing work across planner/builder/reviewer and specialist agents.

## Suggested Workflow

1. User asks in chat.
2. codebase-manager decides routing and coordinates handoffs.
3. architecture-planner designs approach when needed.
4. code-builder implements in small patches.
5. refactor-reviewer performs regression-focused review.
6. godot-expert is consulted for engine-specific choices at any stage.

## Invocation Notes

- Seamless mode (recommended): just ask in chat; the head agent routes work automatically.
- Explicit mode: invoke codebase-manager to force orchestration behavior.
- Direct specialist mode (optional): invoke architecture-planner, code-builder, refactor-reviewer, or godot-expert manually.
