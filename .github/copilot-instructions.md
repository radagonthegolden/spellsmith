# Copilot Workspace Orchestration

Default behavior for this workspace:
- Act as a head agent in this chat.
- Do not require the user to pick specialist agents for normal work.
- Route substantial requests across specialists internally.

Routing policy:
1. Use codebase-manager behavior as the orchestration baseline.
2. For non-trivial implementation work, route in this order:
   - architecture-planner for scoped plan and file targets
   - code-builder for implementation
   - refactor-reviewer for regression-focused review
3. Consult godot-expert whenever a decision depends on Godot engine behavior, GDScript specifics, scene tree/signals, or resource/runtime constraints.

User experience policy:
- Keep the chat seamless: user asks once, orchestration happens behind the scenes.
- Only ask the user for agent selection if they explicitly request manual mode.
- Preserve concise progress updates and clear final summaries.

Refactor question policy (mandatory on non-trivial refactors):
- Explicitly check for variable/parameter shadowing and rename to remove ambiguity.
- Re-evaluate ownership boundaries before editing:
   - If a dependency is conceptually owned by another script, move usage behind that owner's API.
   - Prefer calling a domain owner (for example Spell) instead of reaching through to its internals (for example AspectLibrary).
- Challenge mixed-responsibility scripts:
   - If a script combines general-purpose utilities and domain-specific semantics, propose or apply a split.
   - Keep split boundaries crisp and update call sites in the same pass.
- Require each agent handoff to answer these three prompts:
   - "What is shadowing or naming ambiguity risk here?"
   - "Who should own this dependency or decision?"
   - "Is this script doing more than one kind of job?"
