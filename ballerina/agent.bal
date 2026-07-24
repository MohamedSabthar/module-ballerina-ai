// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ai.observe;

import ballerina/cache;
import ballerina/jballerina.java;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;

const INFER_TOOL_COUNT = "INFER_TOOL_COUNT";
const DEFAULT_MINIMUM_MAX_ITERATIONS = 10;

# Represents the system prompt given to the agent.
@display {label: "System Prompt"}
public type SystemPrompt record {|

    # The role or responsibility assigned to the agent
    @display {label: "Role"}
    string role;

    # Specific instructions for the agent
    @display {label: "Instructions"}
    string instructions;
|};

# Represents the different types of agents supported by the module.
@display {label: "Agent Type"}
public enum AgentType {
    # Represents a ReAct agent
    REACT_AGENT,
    # Represents a function call agent
    FUNCTION_CALL_AGENT
}

# Represents the authentication credentials of an autonomous agent.
@display {label: "Agent Credential"}
public type Credential record {|

    # The unique identifier assigned to the agent.
    @display {label: "Agent ID"}
    string id;

    # The secret associated with the agent.
    @display {label: "Agent Secret"}
    string secret;
|};

# Provides a set of configurations for the agent.
@display {label: "Agent Configuration"}
public type AgentConfiguration record {|

    # The system prompt assigned to the agent
    @display {label: "System Prompt"}
    SystemPrompt systemPrompt;

    # The model used by the agent
    @display {label: "Model"}
    ModelProvider model;

    # The tools available for the agent
    @display {label: "Tools"}
    (BaseToolKit|ToolConfig|FunctionTool)[] tools = [];

    # Skills available to the agent. Each skill's metadata (name + description) is folded into
    # the system prompt at construction; its instructions and tools are loaded only once the
    # agent activates it via the built-in `activate_skill` tool.
    @display {label: "Skills"}
    Skill[] skills = [];

    # The maximum number of reasoning-action cycles the agent performs to complete the task.
    # A single cycle is one LLM call plus the execution of every tool call returned in
    # that response, so multiple tool calls from one response count as one iteration.
    # Defaults to `max(number of tools, 10)` — i.e., at least 10, or more if the
    # agent has more tools available.
    @display {label: "Maximum Iterations"}
    INFER_TOOL_COUNT|int maxIter = INFER_TOOL_COUNT;

    # Specifies whether verbose logging is enabled
    @display {label: "Verbose"}
    boolean verbose = false;

    # The memory used by the agent to store and manage conversation history.
    # Defaults to use an in-memory message store that trims on overflow, if unspecified.
    @display {label: "Memory"}
    Memory? memory?;

    # Defines the strategies for loading tool schemas into an Agent.
    # By default, all tools are loaded without any filtering.
    @display {label: "Tool Loading Strategy"}
    ToolLoadingStrategy toolLoadingStrategy = NO_FILTER;

    # Specifies whether multiple tool calls returned in a single LLM response are executed in parallel.
    # If `true`, all tool calls from one LLM response are executed concurrently;
    # otherwise, they are executed sequentially, one after another.
    @display {label: "Execute Tool Calls in Parallel"}
    boolean executeToolCallsInParallel = true;

    # Optional authentication details of the agent.
    @display {label: "Agent Credential"}
    Credential credential?;
|};

# Represents an agent.
public isolated distinct class Agent {
    # Tool store to be used by the agent
    final ToolStore toolStore;
    # LLM model instance (should be a function call model)
    final ModelProvider model;
    # The memory associated with the agent.
    final Memory memory;
    # Represents if the agent is stateless or not.
    final boolean stateless;
    # Strategy used to control how and when tools are loaded for the agent.
    final ToolLoadingStrategy toolLoadingStrategy;
    # Cache used to store and reuse authentication tokens for tool access.
    final cache:Cache tokenManager = new ();
    # Authentication configuration used for acquiring OAuth tokens when accessing secured tools.
    final readonly & Credential? agentCredential;
    # Indicates whether multiple tool calls from a single LLM response are executed in parallel.
    final boolean executeToolCallsInParallel;
    private final int maxIter;
    private final readonly & SystemPrompt systemPrompt;
    private final boolean verbose;
    private final string uniqueId = uuid:createRandomUuid();
    private final readonly & ToolSchema[] toolSchemas;
    private string? agentId = ();
    # Skill catalogue (name + description only) appended to the system prompt when skills are configured.
    private final string skillsCatalogue;
    # Skills registered with the agent, keyed by name. Guarded by `lock` since `Skill` is not `readonly`.
    private map<Skill> skillsByName = {};
    # Names of the skills activated so far, keyed by session ID — activation is scoped to a
    # session, not to the agent instance, so two conversations on the same agent activate
    # skills independently. Guarded by `lock`.
    private map<map<()>> activatedSkillNamesBySession = {};

    # Initialize an Agent.
    #
    # + config - Configuration used to initialize an agent
    public isolated function init(@display {label: "Agent Configuration"} *AgentConfiguration config) returns Error? {
        Skill[] skills = config.skills;
        string skillsCatalogue = buildSkillsCatalogue(skills);

        observe:CreateAgentSpan span = observe:createCreateAgentSpan(config.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSystemInstructions(getFomatedSystemPrompt(config.systemPrompt, skillsCatalogue));

        INFER_TOOL_COUNT|int maxIter = config.maxIter;
        self.verbose = config.verbose;
        self.systemPrompt = config.systemPrompt.cloneReadOnly();
        self.skillsCatalogue = skillsCatalogue;
        Memory? memory = config.hasKey("memory") ? config?.memory : check new ShortTermMemory();
        observe:CreateAgentIdentitySpan? agentIdentitySpan = ();
        Credential? agentCredential = config.credential;
        if agentCredential is Credential {
            agentIdentitySpan = observe:createCreateAgentIdentitySpan(config.systemPrompt.role);
            self.agentId = agentCredential.id.cloneReadOnly();
            if agentIdentitySpan is observe:CreateAgentIdentitySpan {
                agentIdentitySpan.addId(agentCredential.id);
            }
        }
        do {
            (BaseToolKit|ToolConfig|FunctionTool)[] allTools = [];
            foreach BaseToolKit|ToolConfig|FunctionTool tool in config.tools {
                allTools.push(tool);
            }
            foreach Skill skill in skills {
                ToolConfig[] taggedSkillTools = tagSkillTools(skill);
                foreach ToolConfig taggedTool in taggedSkillTools {
                    allTools.push(taggedTool);
                }
            }
            if skills.length() > 0 {
                isolated function activateSkillCaller = self.activateSkillTool;
                ToolConfig activateSkillTool = {
                    name: ACTIVATE_SKILL_TOOL_NAME,
                    description: "Activates a skill by its exact name, loading its full instructions " +
                        "and tools into the conversation. Call this before using anything a skill provides.",
                    parameters: {
                        'type: OBJECT,
                        properties: {
                            name: {'type: STRING, description: "The exact name of the skill to activate."}
                        },
                        required: ["name"]
                    },
                    caller: activateSkillCaller
                };
                isolated function readResourceCaller = self.readSkillResourceTool;
                ToolConfig readResourceTool = {
                    name: READ_SKILL_RESOURCE_TOOL_NAME,
                    description: "Reads a bundled resource file belonging to an already-activated " +
                        "skill. Only call this for a file that the skill's instructions specifically referenced.",
                    parameters: {
                        'type: OBJECT,
                        properties: {
                            skill: {
                                'type: STRING,
                                description: "The name of the activated skill that owns the resource."
                            },
                            path: {
                                'type: STRING,
                                description: "Path to the resource file, relative to the skill directory."
                            }
                        },
                        required: ["skill", "path"]
                    },
                    caller: readResourceCaller
                };
                allTools.push(activateSkillTool);
                allTools.push(readResourceTool);
            }
            foreach Skill skill in skills {
                string skillName = skill.getMetadata().name;
                lock {
                    self.skillsByName[skillName] = skill;
                }
            }
            self.toolStore = check new (...allTools);
            self.model = config.model;
            self.memory = memory ?: check new ShortTermMemory();
            self.stateless = memory is ();
            self.toolLoadingStrategy = config.toolLoadingStrategy;
            self.executeToolCallsInParallel = config.executeToolCallsInParallel;
            self.agentCredential = agentCredential.cloneReadOnly();
            self.toolSchemas = self.toolStore.getToolSchema().cloneReadOnly();
            self.maxIter = maxIter is INFER_TOOL_COUNT ?
                int:max(self.toolSchemas.length(), DEFAULT_MINIMUM_MAX_ITERATIONS) : maxIter;
            span.addTools(self.toolStore.getToolsInfo());
            if agentIdentitySpan is observe:CreateAgentIdentitySpan {
                agentIdentitySpan.close();
            }
            span.close();
        } on fail Error err {
            if agentIdentitySpan is observe:CreateAgentIdentitySpan {
                agentIdentitySpan.close(err);
            }
            span.close(err);
            return err;
        }
    }

    # Use LLM to decide the next tool/step(s) based on the function calling APIs.
    #
    # + progress - Execution progress with the current query and execution history
    # + sessionId - The ID associated with the agent memory
    # + return - LLM response containing the tool or chat response (or an error if the call fails)
    isolated function selectNextTools(ExecutionProgress progress, string sessionId = DEFAULT_SESSION_ID)
    returns FunctionCall[]|string|Error {
        ChatMessage[] messages = check createFunctionCallMessages(progress);
        messages.unshift(...progress.history);
        ToolLoadingStrategy toolLoadingStrategy = self.toolLoadingStrategy;
        ChatMessage lastMessage = messages[messages.length() - 1];
        // A tool tagged with a skill name stays hidden from the model until `activate_skill` is
        // called for that skill, in this session.
        ChatCompletionFunctions[] registeredTools = [];
        foreach Tool tool in self.toolStore.tools.toArray() {
            if self.isToolVisible(sessionId, tool) {
                ChatCompletionFunctions fn = {name: tool.name, description: tool.description, parameters: tool.variables};
                registeredTools.push(fn);
            }
        }
        ChatCompletionFunctions[] filteredTools = registeredTools;
        if toolLoadingStrategy == LLM_FILTER && lastMessage is ChatUserMessage {
            ChatCompletionFunctions[]? selectedTools = lazyLoadTools(cloneMessages(messages), registeredTools, self.model);
            if selectedTools !is () {
                filteredTools = selectedTools;
            }
        }

        log:printDebug("Requesting tool selection from LLM",
                executionId = progress.executionId,
                sessionId = sessionId,
                messages = messages.toString(),
                availableTools = filteredTools.toString()
        );

        ChatAssistantMessage response = check self.model->chat(messages, filteredTools);
        // All tool calls returned in this single LLM response are executed together
        // (see `Executor.next()`) before the LLM is consulted again, instead of executing
        // them one at a time across separate chat requests.
        FunctionCall[]? toolCalls = getToolCalls(response);
        if toolCalls is FunctionCall[] {
            log:printDebug("LLM selected tool(s)",
                    executionId = progress.executionId,
                    sessionId = sessionId,
                    toolNames = from FunctionCall toolCall in toolCalls
                        select toolCall.name,
                    toolArguments = from FunctionCall toolCall in toolCalls
                        select toolCall.arguments
            );
            return toolCalls;
        }

        log:printDebug("LLM provided chat response instead of tool call",
                executionId = progress.executionId,
                sessionId = sessionId,
                response = response?.content
        );
        string? content = response?.content;
        if content is string {
            return content;
        }
        log:printDebug("Failed to parse LLM response as valid tool or chat",
                agentId = self.agentId,
                executionId = progress.executionId,
                sessionId = sessionId
        );
        return error LlmInvalidGenerationError("Failed to parse the LLM response into a function call or chat message.",
            llmResponse = content);
    }

    # Executes the agent for a given user query.
    #
    # **Note:** Calls to this function using the same session ID must be invoked sequentially by the caller, 
    # as this operation is not thread-safe.
    #
    # + query - The natural language input provided to the agent
    # + sessionId - The ID associated with the agent memory
    # + context - The additional context that can be used during agent tool execution
    # + td - Type descriptor specifying the expected return type format
    # + return - The agent's response or an error
    public isolated function run(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new,
            typedesc<Trace|string> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.Agent"
    } external;

    private isolated function runInternal(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new, boolean withTrace = false) returns string|Trace|Error {
        time:Utc startTime = time:utcNow();
        string executionId = uuid:createRandomUuid();
        log:printDebug("Agent execution started",
                executionId = executionId,
                agentId = self.agentId,
                query = query,
                sessionId = sessionId
        );

        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSessionId(sessionId);
        span.addInput(query);
        string systemPrompt = getFomatedSystemPrompt(self.systemPrompt, self.skillsCatalogue);
        span.addSystemInstruction(systemPrompt);

        Credential? & readonly agentCredential = self.agentCredential;
        string? agentId = agentCredential is Credential ? agentCredential.id : ();
        // Stamped so `activateSkillTool`/`readSkillResourceTool` — invoked as ordinary tools,
        // with no direct access to this call's `sessionId` parameter — can scope skill
        // activation to this session instead of to the agent instance.
        context.set(SKILL_SESSION_CONTEXT_KEY, sessionId);
        ExecutionTrace executionTrace = run(self, systemPrompt, query, self.maxIter, self.verbose, agentId,
                sessionId, context, executionId);
        ChatUserMessage userMessage = {role: USER, content: query};
        Iteration[] iterations = executionTrace.iterations;
        FunctionCall[]? toolCalls = executionTrace.toolCalls.length() == 0 ? () : executionTrace.toolCalls;
        do {
            string answer = check getAnswer(executionTrace);
            log:printDebug("Agent execution completed successfully",
                    executionId = executionId,
                    agentId = self.agentId,
                    steps = executionTrace.steps.toString(),
                    answer = answer
            );
            span.addOutput(observe:TEXT, answer);
            span.close();

            return withTrace
                ? {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: {role: ASSISTANT, content: answer},
                    toolCalls
                }
                : answer;
        } on fail Error err {
            log:printDebug("Agent execution failed",
                    err,
                    executionId = executionId,
                    agentId = self.agentId,
                    steps = executionTrace.steps.toString()
            );
            span.close(err);

            return withTrace
                ? {
                    id: executionId,
                    userMessage,
                    iterations,
                    tools: self.toolSchemas,
                    startTime,
                    endTime: time:utcNow(),
                    output: err,
                    toolCalls
                }
                : err;
        }
    }

    isolated function findSkill(string name) returns Skill? {
        lock {
            return self.skillsByName[name];
        }
    }

    isolated function isSkillActivated(string sessionId, string name) returns boolean {
        lock {
            map<()>? activatedForSession = self.activatedSkillNamesBySession[sessionId];
            return activatedForSession is map<()> && activatedForSession.hasKey(name);
        }
    }

    isolated function isToolVisible(string sessionId, Tool tool) returns boolean {
        string? owningSkill = tool.skillName;
        return owningSkill is () || self.isSkillActivated(sessionId, owningSkill);
    }

    isolated function activateSkillTool(Context context, string name) returns SkillActivationResult|Error {
        string sessionId = getSkillSessionId(context);
        Skill? skill = self.findSkill(name);
        if skill is () {
            string[] availableSkills;
            lock {
                availableSkills = self.skillsByName.keys().clone();
            }
            return error Error(string `No skill named '${name}' is available. ` +
                string `Available skills: ${availableSkills.toString()}`);
        }
        lock {
            map<()> activatedForSession = self.activatedSkillNamesBySession[sessionId] ?: {};
            activatedForSession[name] = ();
            self.activatedSkillNamesBySession[sessionId] = activatedForSession;
        }
        SkillMetadata metadata = skill.getMetadata();
        return {
            activated: name,
            instructions: skill.getInstructions(),
            toolsAdded: metadata.tools ?: []
        };
    }

    isolated function readSkillResourceTool(Context context, string skill, string path) returns string|Error {
        string sessionId = getSkillSessionId(context);
        if !self.isSkillActivated(sessionId, skill) {
            return error Error(string `Skill '${skill}' has not been activated yet. ` +
                string `Call '${ACTIVATE_SKILL_TOOL_NAME}' first.`);
        }
        Skill? found = self.findSkill(skill);
        if found is () {
            return error Error(string `No skill named '${skill}' is available.`);
        }
        return found.getResource(path);
    }
}

# Key used to stamp the current `run()` call's session ID into its `Context`, so that
# `Agent.activateSkillTool`/`Agent.readSkillResourceTool` — invoked as ordinary tools via the
# same reflection-based `Context` injection any tool function can use — can scope skill
# activation to that session.
const SKILL_SESSION_CONTEXT_KEY = "ai.internal.skillSessionId";

isolated function getSkillSessionId(Context context) returns string {
    if context.hasKey(SKILL_SESSION_CONTEXT_KEY) {
        ContextEntry sessionId = context.get(SKILL_SESSION_CONTEXT_KEY);
        if sessionId is string {
            return sessionId;
        }
    }
    return DEFAULT_SESSION_ID;
}

isolated function withSkillName(ToolConfig toolConfig, string skillName) returns ToolConfig {
    // `toolConfig` comes from `Skill.getTools()`, which returns a `& readonly` array — `.clone()`
    // on an already-readonly value returns the same readonly reference, so mutating a field on it
    // panics at runtime. Building a fresh record literal avoids that.
    return {
        name: toolConfig.name,
        description: toolConfig.description,
        parameters: toolConfig.parameters,
        caller: toolConfig.caller,
        auth: toolConfig.auth,
        skillName
    };
}

isolated function tagSkillTools(Skill skill) returns ToolConfig[] {
    string skillName = skill.getMetadata().name;
    ToolConfig[] tagged = [];
    foreach ToolConfig toolConfig in skill.getTools() {
        ToolConfig taggedConfig = withSkillName(toolConfig, skillName);
        tagged.push(taggedConfig);
    }
    return tagged;
}

isolated function getAnswer(ExecutionTrace executionTrace) returns string|Error {
    string? answer = executionTrace.answer;
    return answer ?: constructError(executionTrace);
}

isolated function constructError(ExecutionTrace executionTrace) returns Error {
    (ExecutionResult|ExecutionError|Error)[] steps = executionTrace.steps;
    if executionTrace.maxIterationsExceeded {
        return error MaxIterationExceededError("Maximum iteration limit exceeded while processing the query.",
            steps = steps);
    }
    // Validates whether the execution steps contain only one memory error.
    // If there is exactly one memory error, it is returned; otherwise, null is returned.
    if steps.length() == 1 {
        ExecutionResult|ExecutionError|Error step = steps[0];
        if step is ExecutionError && step.'error is MemoryError {
            return <MemoryError>step.'error;
        }
    }
    return error Error("Unable to obtain valid answer from the agent", steps = steps);
}

isolated function buildSkillsCatalogue(Skill[] skills) returns string {
    if skills.length() == 0 {
        return "";
    }
    string[] entries = [];
    foreach Skill skill in skills {
        SkillMetadata metadata = skill.getMetadata();
        entries.push(string `- "${metadata.name}": ${metadata.description}`);
    }
    return string `

# Skills
You have the following skills available. Each skill's full instructions and tools stay hidden
until you activate it. Call '${ACTIVATE_SKILL_TOOL_NAME}' with a skill's exact name if its
description matches the current task, before using anything it provides:
${string:'join("\n", ...entries)}`;
}

isolated function getFomatedSystemPrompt(SystemPrompt systemPrompt, string skillsCatalogue = "") returns string {
    return string `# Role
${systemPrompt.role}

# Instructions
${systemPrompt.instructions}
${skillsCatalogue}
`;
}
