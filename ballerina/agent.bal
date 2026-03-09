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
import ballerina/time;
import ballerina/uuid;

type ParallelToolExecutionResult (ExecutionResult|ExecutionError)[];

type ParallelCallOutput (ChatFunctionMessage|Error)[];

const INFER_TOOL_COUNT = "INFER_TOOL_COUNT";

# Represents an agent.
public isolated distinct class Agent {
    private final string agentId = uuid:createRandomUuid();
    private final string instructions;
    private final string role;
    private final readonly & ToolSchema[] toolSchemas;
    private final AgentExecutor executor;
    private final ConversationManager conversationManager;
    final ToolRegistry toolStore;

    # Initialize an Agent.
    #
    # + config - Configuration used to initialize an agent
    public isolated function init(@display {label: "Agent Configuration"} *AgentConfiguration config) returns Error? {
        string instructions = getFormattedSystemPrompt(config.systemPrompt);
        observe:CreateAgentSpan span = observe:createCreateAgentSpan(config.systemPrompt.role);
        span.addId(self.agentId);
        span.addSystemInstructions(instructions);

        INFER_TOOL_COUNT|int maxIter = config.maxIter;
        int resolvedMaxIter = maxIter is INFER_TOOL_COUNT ? config.tools.length() + 1 : maxIter;
        self.instructions = instructions;
        self.role = config.systemPrompt.role;
        Memory? memory = config.hasKey("memory") ? config?.memory : check new ShortTermMemory();
        do {
            self.toolStore = check new (...config.tools);
            Memory resolvedMemory = memory ?: check new ShortTermMemory();
            boolean stateless = memory is ();
            self.toolSchemas = self.toolStore.getToolSchema().cloneReadOnly();

            ToolExecutionHandler toolHandler = new (self.toolStore);
            self.executor = new (config.model, self.toolStore, toolHandler,
                config.toolLoadingStrategy, resolvedMaxIter, config.verbose
            );
            self.conversationManager = new (resolvedMemory, stateless);

            span.addTools(self.toolStore.getToolsInfo());
            span.close();
        } on fail Error err {
            span.close(err);
            return err;
        }
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

        logAgentExecutionStarted(executionId, query, sessionId);
        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.role);
        span.addId(self.agentId);
        span.addSessionId(sessionId);
        span.addInput(query);
        span.addSystemInstruction(self.instructions);

        var [history, systemMessage, userMessage] = self.conversationManager.initializeHistory(
                sessionId, self.instructions, query, executionId);
        ExecutionTrace executionTrace = self.executor.execute(query, sessionId, context, executionId, history);
        ExecutionProgress progress = {
            instruction: self.instructions,
            query,
            context,
            executionId,
            history,
            executionSteps: executionTrace.executionSteps
        };
        self.conversationManager.finalizeMemory(sessionId, progress,
                systemMessage, userMessage, getAssistantMessage(executionTrace));

        ChatUserMessage userMsg = {role: USER, content: query};
        FunctionCall[]? toolCalls = executionTrace.toolCalls.length() == 0 ? () : executionTrace.toolCalls;
        do {
            string answer = check getAnswer(executionTrace, self.executor.getMaxIter());
            logAgentExecutionCompleted(executionId, executionTrace.steps.toString(), answer);
            span.addOutput(observe:TEXT, answer);
            span.close();
            return withTrace ? buildTrace(executionId, userMsg, executionTrace.iterations,
                        self.toolSchemas, startTime, answer, toolCalls) : answer;
        } on fail Error err {
            logAgentExecutionFailed(executionId, executionTrace.steps.toString(), err);
            span.close(err);
            return withTrace
                ? buildTrace(executionId, userMsg, executionTrace.iterations, self.toolSchemas,
                        startTime, err, toolCalls)
                : err;
        }
    }

    // Executes the agent loop for a given query (package-level access for testing).
    isolated function runExecutor(string query, string sessionId = DEFAULT_SESSION_ID, Context context = new,
            string executionId = DEFAULT_EXECUTION_ID) returns ExecutionTrace {
        var [history, _, _] = self.conversationManager.initializeHistory(
                sessionId, self.instructions, query, executionId);
        return self.executor.execute(query, sessionId, context, executionId, history);
    }
}

# Get the tools registered with the agent.
#
# + agent - Agent instance
# + return - Array of tools registered with the agent
public isolated function getTools(Agent agent) returns Tool[] => agent.toolStore.tools.toArray();

// Extracts the final assistant message from an execution trace.
isolated function getAssistantMessage(ExecutionTrace trace) returns ChatAssistantMessage? {
    string? answer = trace.answer;
    return answer is string ? {role: ASSISTANT, content: answer} : ();
}
