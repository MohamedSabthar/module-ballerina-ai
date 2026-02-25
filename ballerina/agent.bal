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

import ballerina/jballerina.java;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;

const INFER_TOOL_COUNT = "INFER_TOOL_COUNT";

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

    # The maximum number of iterations the agent performs to complete the task.
    # By default, it is set to the number of tools + 1.
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

    # Names of tools that require human approval before execution.
    # When the LLM selects one of these tools, `run()` pauses and returns an `HITLResponse`.
    # Call `run()` again with the same `sessionId` and an `HITLApproval` to resume.
    @display {label: "HITL Tools"}
    string[] hitlTools = [];
|};

# Represents an agent.
public isolated distinct class Agent {
    final FunctionCallAgent functionCallAgent;
    private final int maxIter;
    private final readonly & SystemPrompt systemPrompt;
    private final boolean verbose;
    private final string uniqueId = uuid:createRandomUuid();
    private final readonly & ToolSchema[] toolSchemas;
    private final readonly & string[] hitlTools;
    # Stores pending LLM responses keyed by sessionId for HITL resume.
    private final map<json> pendingHitl = {};

    # Initialize an Agent.
    #
    # + config - Configuration used to initialize an agent
    public isolated function init(@display {label: "Agent Configuration"} *AgentConfiguration config) returns Error? {
        observe:CreateAgentSpan span = observe:createCreateAgentSpan(config.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSystemInstructions(getFomatedSystemPrompt(config.systemPrompt));

        INFER_TOOL_COUNT|int maxIter = config.maxIter;
        self.maxIter = maxIter is INFER_TOOL_COUNT ? config.tools.length() + 1 : maxIter;
        self.verbose = config.verbose;
        self.systemPrompt = config.systemPrompt.cloneReadOnly();
        self.hitlTools = config.hitlTools.cloneReadOnly();
        Memory? memory = config.hasKey("memory") ? config?.memory : check new ShortTermMemory();
        do {
            self.functionCallAgent = check new FunctionCallAgent(config.model, config.tools, memory,
                config.toolLoadingStrategy);
            self.toolSchemas = self.functionCallAgent.toolStore.getToolSchema().cloneReadOnly();
            span.addTools(self.functionCallAgent.toolStore.getToolsInfo());
            span.close();
        } on fail Error err {
            span.close(err);
            return err;
        }
    }

    # Executes the agent for a given user query.
    # If the LLM selects a tool listed in `hitlTools`, execution pauses and returns an
    # `HITLResponse` instead of the final answer. To resume, call `run()` again with the
    # same `sessionId` and an `HITLApproval` containing the human decision.
    #
    # **Note:** Calls using the same session ID must be sequential (not thread-safe).
    #
    # + query - The natural language input (pass `""` when resuming a HITL execution)
    # + sessionId - The session/thread ID for memory and HITL state
    # + context - Additional context for tool execution
    # + hitlApproval - Approval decision when resuming a paused HITL execution
    # + td - Type descriptor for the return format (`string` or `Trace`)
    # + return - The agent's answer, a `Trace`, an `HITLResponse` (if paused), or an error
    public isolated function run(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new,
            HITLApproval? hitlApproval = (),
            typedesc<Trace|HITLResponse|string> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.Agent"
    } external;

    private isolated function runInternal(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new, boolean withTrace = false,
            HITLApproval? hitlApproval = ()) returns string|Trace|HITLResponse|Error {
        time:Utc startTime = time:utcNow();
        string executionId = uuid:createRandomUuid();

        log:printDebug("Agent execution started",
            executionId = executionId,
            query = query,
            sessionId = sessionId
        );
        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSessionId(sessionId);
        span.addInput(query);
        string systemPrompt = getFomatedSystemPrompt(self.systemPrompt);
        span.addSystemInstruction(systemPrompt);

        // On resume: retrieve the pending LLM response saved from the previous HITL pause.
        json? resumeLlmResponse = ();
        if hitlApproval !is () {
            lock {
                if self.pendingHitl.hasKey(sessionId) {
                    resumeLlmResponse = self.pendingHitl.get(sessionId).clone();
                    _ = self.pendingHitl.remove(sessionId);
                }
            }
        }

        ExecutionTrace executionTrace = self.functionCallAgent
            .run(query, systemPrompt, self.maxIter, self.verbose, sessionId, context, executionId,
                 self.hitlTools, resumeLlmResponse, hitlApproval);

        // If execution paused for HITL, persist the pending state and return HITLResponse.
        readonly & HitlPause? hitlPause = executionTrace?.hitlPause.cloneReadOnly();
        if hitlPause !is () {
            lock {
                self.pendingHitl[sessionId] = hitlPause.pendingLlmResponse;
            }
            log:printDebug("Agent execution paused for HITL",
                executionId = executionId,
                toolName = hitlPause.toolCall.name,
                sessionId = sessionId
            );
            span.close();
            return {toolCall: hitlPause.toolCall, sessionId};
        }

        ChatUserMessage userMessage = {role: USER, content: query};
        Iteration[] iterations = executionTrace.iterations;
        FunctionCall[]? toolCalls = executionTrace.toolCalls.length() == 0 ? () : executionTrace.toolCalls;
        do {
            string answer = check getAnswer(executionTrace, self.maxIter);
            log:printDebug("Agent execution completed successfully",
                executionId = executionId,
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
}

isolated function getAnswer(ExecutionTrace executionTrace, int maxIter) returns string|Error {
    string? answer = executionTrace.answer;
    return answer ?: constructError(executionTrace.steps, maxIter);
}

isolated function constructError((ExecutionResult|ExecutionError|Error)[] steps, int maxIter) returns Error {
    if (steps.length() == maxIter) {
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

isolated function getFomatedSystemPrompt(SystemPrompt systemPrompt) returns string {
    return string `# Role  
${systemPrompt.role}  

# Instructions  
${systemPrompt.instructions}`;
}
