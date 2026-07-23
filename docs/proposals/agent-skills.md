# Proposal: Agent Skills for `ballerina/ai`

- Authors: @MohamedSabthar
- Reviewers: TBD
- Created: 2026-07-21
- Status: Draft
- Related module version: `ballerina/ai` 1.12.0

## Summary

Introduce **Skills** to the `ballerina/ai` agent framework: filesystem-based, discoverable bundles
of instructions (and, optionally, tools and reference material) that an `Agent` loads
*progressively* rather than all at once. This follows the same model Claude (Claude Code / the
Claude Agent SDK) uses for Agent Skills:

- A skill is a directory containing a `SKILL.md` file — YAML front matter (`name`, `description`,
  ...) plus a markdown body of instructions — and, optionally, sibling resource files
  (reference docs, templates, examples) the instructions can point to.
- Only the front matter (`name` + `description`) is visible to the model up front, as a cheap
  catalogue. The full instruction body is loaded only when the agent decides the skill is relevant.
  Bundled resource files are loaded later still, only if the instructions tell the agent it needs
  them for the task at hand.
- This is a **three-level progressive disclosure** scheme: metadata (always resident) → instructions
  (loaded on activation) → bundled resources (loaded on demand). Each level costs more context, so
  each level is loaded later and more selectively than the one before it.

Tool code itself is not written in the markdown file (Ballerina is compiled, unlike Claude Code's
scriptable bash environment) — a skill's front matter *names* the tools it needs, and those names
are resolved against Ballerina tool implementations the developer supplies in code. Everything else
about the skill (what it's for, when to use it, how to use it, what reference material backs it) is
authored as markdown, editable without recompilation.

## Motivation

Today everything an agent knows how to do is supplied at construction time via
`AgentConfiguration.tools` (a flat list of `BaseToolKit|ToolConfig|FunctionTool`) and a single
`SystemPrompt.instructions` string:

```ballerina
ai:Agent agent = check new (
    systemPrompt = {role: "...", instructions: "... one long string covering every capability ..."},
    model = model,
    tools = [tool1, tool2, tool3, /* every tool the agent might ever need */]
);
```

This doesn't scale as an agent accumulates capabilities:

1. **Context bloat.** Every tool's JSON schema and every capability's instructions are sent to the
   model on every turn, whether relevant or not. `ballerina/ai` already has `ToolLoadingStrategy`
   (`NO_FILTER` / `LLM_FILTER`, see `ballerina/tool_types.bal` / `agent.bal`'s `selectNextTools`) for
   the *tool-schema* half of this, but there's no equivalent for bundled *instructions* — they all
   live in one flat string.
2. **Instructions and prose live in code, not in an editable document.** Today, the only way to give
   an agent detailed operating procedure for a specific capability (e.g. "when filing a ticket,
   always ask for severity first, use the `bug` template unless told otherwise") is to inline it into
   `SystemPrompt.instructions` or a docstring. There's no unit that a non-engineer (a domain expert,
   support lead, etc.) can edit directly, the way a markdown file can be edited without touching
   Ballerina source.
3. **No cheap discoverability contract.** There's no way to ask "what can this agent do?" without
   dumping every tool schema and every instruction into context. Claude's Agent Skills solve this
   with a metadata-only catalogue expanded on demand; `ballerina/ai` has no equivalent.

Adopting the same directory + `SKILL.md` + progressive disclosure model used by Claude keeps the
authoring experience familiar (skills already written for Claude Code are a close template to copy
from) and gives non-Ballerina-engineers a way to extend an agent's behavior by writing markdown.

## Goals

- Define a skill as a directory with a `SKILL.md` file (YAML front matter + markdown instructions)
  plus optional sibling resource files, matching Claude's Agent Skills layout closely enough that
  existing skill-authoring conventions transfer.
- Implement the same three-level progressive disclosure: metadata always resident; instructions
  loaded on activation; bundled resource files loaded on demand, individually.
- Provide a loader (`ai:readSkill` / `ai:readSkills`) that parses a directory (or a directory of
  skill directories) into `Skill` values at agent-construction time.
- Let a skill's front matter declare the *names* of tools it needs; resolve those names against a
  developer-supplied registry of Ballerina tool implementations (`FunctionTool`/`ToolConfig`/
  `BaseToolKit`) — the same union type `AgentConfiguration.tools` already accepts.
  supplied in code — so tool *behavior* stays compiled Ballerina while everything else about the
  skill stays editable markdown.
- Let `AgentConfiguration` accept a `skills` field alongside `tools`, defaulting to `[]`, so no
  existing agent-construction code needs to change.
- Implement activation and resource loading as ordinary tool calls (`activate_skill`,
  `read_skill_resource`) that ride the agent's existing function-calling loop — no changes needed to
  `Executor`, `ModelProvider`, or the `FunctionCall`/`LlmToolResponse` types.
- Keep an activated skill's tools subject to `ToolLoadingStrategy`, `executeToolCallsInParallel`, and
  `ToolStore` auth/scopes handling exactly like statically configured tools.

## Non-Goals

- Executing arbitrary scripts bundled in a skill directory. Claude Code's skills can ship executable
  scripts because its agent runs in a shell; `ballerina/ai` agents call typed Ballerina functions, so
  a skill's "tools" are always pre-compiled Ballerina tool implementations, referenced by name —
  never code loaded from the skill directory at runtime.
- A skill marketplace/registry service. This proposal defines the in-process/on-disk convention only;
  distribution (a shared Ballerina Central package of skill directories, a company-internal skills
  repo, etc.) is follow-up work.
- Changing `ReAct`/`FunctionCall` execution semantics, `Memory`, or `ModelProvider` interfaces.
- Mid-conversation skill deactivation (see Open Questions).

## Design

### On-disk layout

```
skills/
  incident-response/
    SKILL.md
    references/
      escalation-policy.md
      severity-matrix.md
  expense-report/
    SKILL.md
    templates/
      client-entertainment.md
```

### `SKILL.md` format

```markdown
---
name: incident-response
description: >
  Use when the user reports a production incident. Provides tools to page on-call
  and create a postmortem doc, and a reference escalation policy.
version: 1.0.0
tags: [ops, incident]
tools: [pageOncall, createPostmortem]
---

# Incident Response

When a user reports a production incident:

1. Ask for the affected service and severity if not already given.
2. Page on-call using `pageOncall` for severity 1/2 incidents.
3. Create a postmortem doc with `createPostmortem` once the incident is mitigated.

For escalation timing rules, see `references/escalation-policy.md`.
For how severity is determined, see `references/severity-matrix.md`.
```

Front matter fields:

| Field         | Required | Meaning                                                                                    |
|---------------|----------|----------------------------------------------------------------------------------------------|
| `name`        | yes      | Unique skill identifier; what the model passes to `activate_skill`.                          |
| `description` | yes      | The **only** content visible before activation — must be enough for the model to self-select.|
| `version`     | no       | Free-form version string, useful once skills are shared/versioned independently of the agent.|
| `tags`        | no       | Free-form categorization, not sent to the model.                                             |
| `tools`       | no       | Names of tools this skill needs, resolved against a caller-supplied registry (see below).    |

Everything after the closing `---` is the instruction body, injected verbatim as a system-prompt
fragment on activation. Any relative link in that body (`references/escalation-policy.md`) is a
bundled resource, loadable on demand — see Level 3 below.

### Runtime types

```ballerina
# Metadata parsed from a skill's YAML front matter. The only part of a skill visible
# to the model before it is activated.
public type SkillMetadata record {|
    string name;
    string description;
    string 'version?;
    string[] tags?;
    string[] tools?;
|};

# A skill loaded from a `SKILL.md` file (plus its sibling resource files, if any).
public isolated class Skill {
    private final SkillMetadata metadata;
    private final string instructions;
    private final (BaseToolKit|ToolConfig|FunctionTool)[] & readonly tools;
    private final string skillDir;

    # + return - Metadata used to advertise the skill before activation
    public isolated function getMetadata() returns SkillMetadata => self.metadata;

    # + return - The SKILL.md body, injected as a system-prompt fragment on activation
    public isolated function getInstructions() returns string => self.instructions;

    # + return - Tools resolved from `metadata.tools`, made available once this skill is activated
    public isolated function getTools() returns (BaseToolKit|ToolConfig|FunctionTool)[] => self.tools;

    # Reads a bundled resource file, relative to the skill's directory. Loaded lazily —
    # only called when the model asks for a specific file the instructions referenced.
    # + relativePath - Path relative to the skill directory, e.g. "references/escalation-policy.md"
    # + return - File contents, or an error if the path escapes the skill directory or doesn't exist
    public isolated function getResource(string relativePath) returns string|Error;
}

# Parses a single skill directory (must contain SKILL.md).
#
# + skillDir - Path to the skill's directory
# + toolRegistry - Maps tool names declared in `SKILL.md`'s `tools:` front matter to their
#   Ballerina implementations. Names not found here are reported as an `Error` at load time.
# + return - The parsed skill, or an `Error` on a missing/malformed SKILL.md or unresolved tool name
public isolated function readSkill(string skillDir,
        map<BaseToolKit|ToolConfig|FunctionTool> toolRegistry = {}) returns Skill|Error;

# Parses every immediate subdirectory of `skillsRootDir` that contains a SKILL.md.
#
# + skillsRootDir - Directory containing one subdirectory per skill (e.g. "skills/")
# + toolRegistry - Shared registry used to resolve every skill's `tools:` front matter
# + return - One `Skill` per subdirectory with a valid SKILL.md, or an `Error`
public isolated function readSkills(string skillsRootDir,
        map<BaseToolKit|ToolConfig|FunctionTool> toolRegistry = {}) returns Skill[]|Error;
```

`readSkill`/`readSkills` parse the YAML front matter with a small bundled front-matter parser (the
Ballerina standard library has no YAML module; front matter here is a flat `key: value`/list
subset, not general YAML, so a purpose-built parser is sufficient and avoids a new dependency).

### `AgentConfiguration` changes

```ballerina
public type AgentConfiguration record {|
    SystemPrompt systemPrompt;
    ModelProvider model;
    (BaseToolKit|ToolConfig|FunctionTool)[] tools = [];
    # Skills available to the agent. Metadata is folded into the system prompt at construction;
    # instructions and tools load lazily on activation; bundled resources load lazily on request.
    Skill[] skills = [];
    INFER_TOOL_COUNT|int maxIter = INFER_TOOL_COUNT;
    boolean verbose = false;
    Memory? memory?;
    ToolLoadingStrategy toolLoadingStrategy = NO_FILTER;
    boolean executeToolCallsInParallel = true;
    Credential credential?;
|};
```

`skills` defaults to `[]`; every existing `new Agent(...)` call is unaffected.

### The three progressive-disclosure levels

**Level 1 — metadata (always resident).** At construction, `Agent.init()` builds a catalogue from
each skill's `name` + `description` and appends it to the effective system prompt:

```
You have the following skills available. Call `activate_skill` with a skill's name if its
description matches the current task, before using anything it provides:
- "incident-response": Use when the user reports a production incident. Provides tools to
  page on-call and create a postmortem doc, and a reference escalation policy.
- "expense-report": Use when the user wants to file or check the status of an expense report.
```

This is the only per-skill content in context regardless of how many skills are configured, or how
long their instructions/resources are.

**Level 2 — instructions (loaded on activation).** Whenever `config.skills` is non-empty, the agent
registers one reserved tool, `activate_skill(name: string) returns SkillActivationResult|Error`.
Calling it:
- looks up the named `Skill`,
- appends `getInstructions()` (the SKILL.md body) to the conversation as a tool result — following
  the same path every other tool result already takes through `Executor`,
- registers `getTools()` into the `ToolStore` so they participate in the next `selectNextTools()`
  call,
- returns a confirmation, e.g. `{activated: "incident-response", toolsAdded: ["pageOncall", "createPostmortem"], resources: ["references/escalation-policy.md", "references/severity-matrix.md"]}`.

**Level 3 — bundled resources (loaded on demand, individually).** Whenever any activated skill lists
resource files, the agent also exposes `read_skill_resource(skill: string, path: string) returns string|Error`,
resolved via `Skill.getResource()`. The model only calls this for a specific file, only if the
activated skill's own instructions told it that file exists and is relevant — e.g. after activating
`incident-response`, the model reads `references/escalation-policy.md` only if it needs escalation
timing rules for the incident at hand, not `severity-matrix.md` as well unless it separately needs
that too. This is the same "load only what the current step needs" principle as Level 2, one layer
deeper.

Because all three levels are exposed as ordinary tool calls and tool results, `Executor`,
`ModelProvider`, and the existing `FunctionCall`/`LlmToolResponse` types require no changes.

### Interaction with existing toolkits and strategies

A skill's `tools:` front matter resolves through the caller-supplied `toolRegistry`, which can map a
name directly to a `BaseToolKit` — so an `McpToolKit` or `HttpServiceToolKit` can back a skill
without any special-casing:

```ballerina
ai:McpToolKit githubToolkit = check new ("https://github-mcp.example.com");

ai:Skill[] skills = check ai:readSkills("skills",
    toolRegistry = {
        "pageOncall": pageOncall,
        "createPostmortem": createPostmortem,
        "github": githubToolkit
    }
);

ai:Agent agent = check new (
    systemPrompt = {role: "Support agent", instructions: "Help users with their requests."},
    model = model,
    skills = skills
);
```

Once activated, a skill's tools are ordinary entries in `ToolStore` and are filtered by
`ToolLoadingStrategy`, executed with `executeToolCallsInParallel`, and subject to auth/scope handling
exactly like tools passed directly through `AgentConfiguration.tools`.

### Example: end-to-end

```
skills/expense-report/SKILL.md:
---
name: expense-report
description: Use when the user wants to file or check the status of an expense report.
tools: [submitExpense, getExpenseStatus]
---
When filing an expense report:
1. Ask for the amount, currency, and business justification if not provided.
2. Reports over $500 require a manager-approval tag.
3. Always confirm the final report contents before calling submitExpense.
```

```ballerina
ai:Skill[] skills = check ai:readSkills("skills",
    toolRegistry = {"submitExpense": submitExpense, "getExpenseStatus": getExpenseStatus});

ai:Agent agent = check new (
    systemPrompt = {role: "Assistant", instructions: "You help employees with internal requests."},
    model = openAiModel,
    skills = skills
);

// Turn 1: model sees only the skill catalogue (name + description), decides "expense-report"
// matches, calls activate_skill("expense-report"), receives the instructions + tool list back.
// Turn 2 onward: model calls submitExpense / getExpenseStatus directly, guided by the
// injected instructions — no resource files exist for this skill, so Level 3 never triggers.
_ = check agent->run("I need to file an expense report for a $120 client dinner.");
```

## Alternatives Considered

- **Pure in-code `Skill` objects (no files), e.g. a `FunctionSkill` you build with a Ballerina record
  literal.** Simpler to implement but forfeits the main benefit motivating this proposal: letting
  someone iterate on a skill's operating instructions by editing a markdown file, without touching
  Ballerina source or waiting on a recompile/redeploy of the service embedding the agent. Kept as a
  possible companion API (see Future Work) but not the primary authoring path.
- **Just use more `BaseToolKit`s / `ToolLoadingStrategy.LLM_FILTER`.** Already solves dynamic
  tool-schema loading, but has no notion of a document, no bundled reference files, and no
  metadata-only catalogue step — `LLM_FILTER` still runs a filtering pass over full tool metadata,
  not a cheap name+description list.
- **A general YAML/frontmatter dependency.** Rejected for v1 in favor of a small bundled parser,
  since `SKILL.md` front matter only needs flat scalars and string lists, not general YAML.

## Backward Compatibility

Fully additive. `AgentConfiguration.skills` defaults to `[]`; `Agent.init()` only builds a skill
catalogue and registers `activate_skill`/`read_skill_resource` when `skills` is non-empty. No
existing field, type, or public function signature changes.

## Open Questions / Future Work

- **Deactivation.** Should a skill's tools be removable mid-session? Raises questions about
  in-flight `FunctionCall`s referencing a tool being removed; deferred for v1 (skills stay active for
  the life of the `Memory` session once activated).
- **Companion in-code authoring API.** A `Skill` constructible directly from Ballerina values (no
  file), for generated/dynamic skills, analogous to how `FunctionTool` doesn't require an on-disk
  spec. Not needed for v1 but likely wanted once skills are used programmatically.
- **Distribution.** Package common skill directories as their own Ballerina Central artifact
  (analogous to how model providers ship as separate packages from `ballerina/ai`), so teams can
  share a `skills/` folder across services.
- **Observability.** `ai.observe` already spans agent/tool execution; skill activation and resource
  reads should likely get their own spans so they're visible in traces alongside tool calls.
- **Security.** `getResource` must resolve paths relative to the skill directory and reject any
  path that escapes it (`..` traversal), since resource paths ultimately come from model output.

## Testing Plan

- Unit tests for `readSkill`/`readSkills`: valid front matter, missing required fields, unresolved
  tool names in `toolRegistry`, and multiple skill directories under one root.
- Unit tests for `Skill.getResource`: valid relative path, missing file, and path-traversal attempt.
- Unit test verifying `Agent.init()` builds the correct skill catalogue string and registers
  `activate_skill` (and `read_skill_resource`, when applicable) only when `skills` is non-empty.
- Integration test: an agent configured with two skills where only one's tools are relevant; assert
  the model only sees the activated skill's tool schemas after calling `activate_skill`, and the
  other skill's tools are absent from that turn's `ChatCompletionFunctions`.
- Integration test: a skill with bundled resources, asserting `read_skill_resource` returns file
  contents only after the skill is activated, and rejects paths outside the skill directory.
- Interop test: a skill whose `tools:` front matter resolves to an `McpToolKit`, asserting
  `getTools()` correctly surfaces the underlying MCP tool configs after activation.
