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
|};

# Represents an agent.
public isolated distinct class Agent {
    private final int maxIter;
    private final string systemPrompt;
    private final string role;
    private final boolean verbose;
    private final string uniqueId = uuid:createRandomUuid();
    private final readonly & ToolSchema[] toolSchemas;

    # Tool store to be used by the agent
    final ToolStore toolStore;
    # LLM model instance (should be a function call model)
    final ModelProvider model;
    # The memory associated with the agent.
    final Memory memory;
    # Represents if the agent is stateless or not.
    final boolean stateless;
    final ToolLoadingStrategy toolLoadingStrategy;

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
        self.systemPrompt = getFomatedSystemPrompt(config.systemPrompt);
        self.role = config.systemPrompt.role;
        Memory? memory = config.hasKey("memory") ? config?.memory : check new ShortTermMemory();
        do {
            self.toolStore = check new (...config.tools);
            self.model = config.model;
            self.memory = memory ?: check new ShortTermMemory();
            self.stateless = memory is ();
            self.toolLoadingStrategy = config.toolLoadingStrategy;
            self.toolSchemas = self.toolStore.getToolSchema().cloneReadOnly();
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

        log:printDebug("Agent execution started",
                executionId = executionId,
                query = query,
                sessionId = sessionId
        );
        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.role);
        span.addId(self.uniqueId);
        span.addSessionId(sessionId);
        span.addInput(query);
        span.addSystemInstruction(self.systemPrompt);

        ExecutionTrace executionTrace = self.runExecutor(query, sessionId, context, executionId);
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

    # Parse the function calling API response and extract the tool to be executed.
    #
    # + llmResponse - Raw LLM response
    # + return - A record containing the tool decided by the LLM, chat response or an error if the response is invalid
    isolated function parseLlmResponse(json llmResponse) returns LlmToolResponse|LlmChatResponse|LlmInvalidGenerationError {
        if llmResponse is string {
            return {content: llmResponse};
        }
        if llmResponse !is FunctionCall {
            return error LlmInvalidGenerationError("Invalid response", llmResponse = llmResponse);
        }
        string? name = llmResponse.name;
        if name is () {
            return error LlmInvalidGenerationError("Missing name", name = llmResponse.name, arguments = llmResponse.arguments);
        }
        return {
            name,
            arguments: llmResponse.arguments,
            id: llmResponse.id
        };
    }

    # Use LLM to decide the next tool/step based on the function calling APIs.
    #
    # + progress - Execution progress with the current query and execution history
    # + sessionId - The ID associated with the agent memory
    # + return - LLM response containing the tool or chat response (or an error if the call fails)
    isolated function selectNextTool(ExecutionProgress progress, string sessionId = DEFAULT_SESSION_ID) returns json|Error {
        ChatMessage[] messages = createFunctionCallMessages(progress);
        messages.unshift(...progress.history);
        ToolLoadingStrategy toolLoadingStrategy = self.toolLoadingStrategy;
        ChatMessage lastMessage = messages[messages.length() - 1];
        ChatCompletionFunctions[] registeredTools = from Tool tool in self.toolStore.tools.toArray()
            select {
                name: tool.name,
                description: tool.description,
                parameters: tool.variables
            };
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

        // TODO: Improve handling of multiple tool calls returned by the LLM.
        // Currently, tool calls are executed sequentially in separate chat responses.
        // Update the logic to execute all tool calls together and return a single response.
        ChatAssistantMessage response = check self.model->chat(messages, filteredTools);
        FunctionCall? toolCall = getFirstToolCall(response);

        if toolCall is FunctionCall {
            log:printDebug("LLM selected tool",
                    executionId = progress.executionId,
                    sessionId = sessionId,
                    toolName = toolCall.name,
                    toolArguments = toolCall.arguments
            );
            return toolCall;
        }

        log:printDebug("LLM provided chat response instead of tool call",
                executionId = progress.executionId,
                sessionId = sessionId,
                response = response?.content
        );
        return response?.content;
    }

    # Execute the agent for a given user's query.
    #
    # + query - Natural langauge commands to the agent  
    # + context - Context values to be used by the agent to execute the task
    # + sessionId - The ID associated with the memory
    # + executionId - Unique identifier for this execution
    # + return - Returns the execution steps tracing the agent's reasoning and outputs from the tools
    isolated function runExecutor(string query, string sessionId = DEFAULT_SESSION_ID, Context context = new, string executionId = DEFAULT_EXECUTION_ID)
        returns ExecutionTrace {
        time:Utc startTime = time:utcNow();
        Iteration[] iterations = [];
        log:printDebug("Agent execution loop started",
                executionId = executionId,
                sessionId = sessionId,
                maxIterations = self.maxIter,
                tools = self.toolStore.tools.toString(),
                isStateless = self.stateless
        );

        (ExecutionResult|ExecutionError|Error)[] steps = [];
        string? content = ();
        // Retrieve the conversation history from memory, update the system message at the start,
        // and append the user message for the current interaction.
        // After iterating and collecting execution steps in temporary memory,
        // update the actual memory in a single batch, including the system prompt and user message for this interaction.
        ChatMessage[]|MemoryError prevHistory = self.memory.get(sessionId);
        if prevHistory is MemoryError {
            log:printDebug("Failed to retrieve conversation history from memory",
                    prevHistory,
                    executionId = executionId,
                    sessionId = sessionId
            );
        }
        ChatMessage[] history = (prevHistory is ChatMessage[]) ? [...prevHistory] : [];
        ChatSystemMessage systemMessage = {role: SYSTEM, content: self.systemPrompt};
        if history.length() > 0 {
            ChatMessage firstMessage = history[0];
            if firstMessage is ChatSystemMessage && self.systemPrompt != toString(firstMessage.content) {
                history[0] = systemMessage;
            }
        } else {
            history.unshift(systemMessage);
        }
        ChatUserMessage userMessage = {role: USER, content: query};
        history.push(userMessage);
        ExecutionProgress progress = {instruction: self.systemPrompt, query, context, executionId, history};
        Executor executor = new (self, sessionId, progress);
        ChatMessage[] temporaryMemory = [systemMessage, userMessage];
        ChatAssistantMessage? finalAssistantMessage = ();
        int iter = 0;
        foreach ExecutionResult|LlmChatResponse|ExecutionError|Error step in executor {
            ChatAssistantMessage|ChatFunctionMessage|Error iterationOutput = getOutputOfIteration(step);
            ChatMessage[] iterationHistory = buildCurrentIterationHistory(executor.progress, history);
            if self.verbose {
                verbosePrint(step, iter);
            }
            if iter == self.maxIter {
                log:printDebug("Maximum iterations reached without final answer",
                        executionId = executionId,
                        iterations = iter,
                        stepsCompleted = steps.length(),
                        sessionId = sessionId
                );
                break;
            }
            if step is Error {
                error? cause = step.cause();
                log:printDebug("Error occurred during agent iteration",
                        step,
                        executionId = executionId,
                        iteration = iter,
                        sessionId = sessionId,
                        cause = cause !is () ? cause.toString() : "none");
                steps.push(step);
                iterations.push({startTime, endTime: time:utcNow(), history: iterationHistory, output: iterationOutput});
                break;
            }
            if step is LlmChatResponse {
                content = step.content;
                log:printDebug("Final answer generated by agent",
                        executionId = executionId,
                        iteration = iter,
                        answer = step.content,
                        sessionId = sessionId
                    );
                finalAssistantMessage = {role: ASSISTANT, content: step.content};
                iterations.push({startTime, endTime: time:utcNow(), history: iterationHistory, output: iterationOutput});
                break;
            }
            iter += 1;
            log:printDebug("Agent iteration started",
                    executionId = executionId,
                    iteration = iter,
                    maxIterations = self.maxIter,
                    stepsCompleted = steps.length(),
                    sessionId = sessionId
            );

            steps.push(step);
            iterations.push({startTime, endTime: time:utcNow(), history: iterationHistory, output: iterationOutput});

            startTime = time:utcNow();
        }

        ChatMessage[] intermediateFunctionCallMessages = createFunctionCallMessages(executor.progress);
        temporaryMemory.push(...intermediateFunctionCallMessages);
        if finalAssistantMessage is ChatAssistantMessage {
            temporaryMemory.push(finalAssistantMessage);
        }

        // Batch update the memory with the user message, system message, and all intermediate steps from tool execution
        updateMemory(self.memory, sessionId, temporaryMemory);
        if self.stateless {
            MemoryError? err = self.memory.delete(sessionId);
            // Ignore this error since the stateless agent always relies on DefaultMessageWindowChatMemoryManager,  
            // which never return an error.
        }
        // Collect all the tool call actions
        FunctionCall[] toolCalls = from ExecutionStep step in executor.progress.executionSteps
            let var llmResponse = step.llmResponse
            where llmResponse is FunctionCall
            select llmResponse;
        return {steps, iterations, answer: content, toolCalls};
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
