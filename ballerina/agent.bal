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

type ParallelToolExecutionResult (ExecutionResult|ExecutionError)[];

type ParallelCallOutput (ChatFunctionMessage|Error)[];

const INFER_TOOL_COUNT = "INFER_TOOL_COUNT";

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
    private final ModelProvider model;
    # The memory associated with the agent.
    private final Memory memory;
    # Represents if the agent is stateless or not.
    private final boolean stateless;
    private final ToolLoadingStrategy toolLoadingStrategy;

    # Initialize an Agent.
    #
    # + config - Configuration used to initialize an agent
    public isolated function init(@display {label: "Agent Configuration"} *AgentConfiguration config) returns Error? {
        observe:CreateAgentSpan span = observe:createCreateAgentSpan(config.systemPrompt.role);
        span.addId(self.uniqueId);
        span.addSystemInstructions(getFormattedSystemPrompt(config.systemPrompt));

        INFER_TOOL_COUNT|int maxIter = config.maxIter;
        self.maxIter = maxIter is INFER_TOOL_COUNT ? config.tools.length() + 1 : maxIter;
        self.verbose = config.verbose;
        self.systemPrompt = getFormattedSystemPrompt(config.systemPrompt);
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
            return withTrace ? buildTrace(executionId, userMessage, executionTrace.iterations,
                        self.toolSchemas, startTime, answer, toolCalls) : answer;
        } on fail Error err {
            log:printDebug("Agent execution failed",
                    err,
                    executionId = executionId,
                    steps = executionTrace.steps.toString()
            );
            span.close(err);
            return withTrace
                ? buildTrace(executionId, userMessage, executionTrace.iterations, self.toolSchemas,
                        startTime, err, toolCalls)
                : err;
        }
    }

    # Use LLM to decide the next tool/step based on the function calling APIs.
    #
    # + progress - Execution progress with the current query and execution history
    # + sessionId - The ID associated with the agent memory
    # + return - LLM response containing the tool or chat response (or an error if the call fails)
    isolated function selectNextTools(ExecutionProgress progress, string sessionId = DEFAULT_SESSION_ID) returns FunctionCall[]|string|Error {
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

        ChatAssistantMessage response = check self.model->chat(messages, filteredTools);
        FunctionCall[]? toolCall = getToolCalls(response);

        if toolCall is FunctionCall[] {
            log:printDebug("LLM selected tools",
                    executionId = progress.executionId,
                    sessionId = sessionId,
                    tools = toolCall
            );
            return toolCall;
        }

        log:printDebug("LLM provided chat response instead of tool call",
                executionId = progress.executionId,
                sessionId = sessionId,
                response = response?.content
        );
        string? content = response?.content;
        return content is string ? content : error LlmInvalidGenerationError("unable to obtain valid response from model");
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

        (ParallelToolExecutionResult|ExecutionResult|ExecutionError|Error)[] steps = [];
        string? content = ();
        var [history, systemMessage, userMessage] = initializeConversationHistory(
                self.memory, sessionId, self.systemPrompt, query, executionId);
        ExecutionProgress progress = {instruction: self.systemPrompt, query, context, executionId, history};
        ChatAssistantMessage? finalAssistantMessage = ();
        int iter = 0;
        while iter < self.maxIter {
            ParallelToolExecutionResult|ExecutionResult|ExecutionError|Error|string step;
            // Reason
            log:printDebug("LLM reasoning started",
                    executionId = executionId,
                    sessionId = sessionId,
                    history = progress.executionSteps.toString()
            );
            FunctionCall[]|string|Error reason = self.selectNextTools(progress, sessionId);
            if reason is Error {
                step = reason;
            } else {
                // Act
                if reason is string {
                    log:printDebug("Parsed LLM response as chat response",
                            executionId = executionId,
                            sessionId = sessionId,
                            response = reason
                    );
                    // here LLM chat repsonse
                    step = reason;
                } else {
                    step = self.executeParallelTools(reason, progress, executionId, sessionId, context);
                }
            }
            ParallelCallOutput|ChatAssistantMessage|ChatFunctionMessage|Error iterationOutput = getOutputOfIteration(step);
            ChatMessage[] iterationHistory = buildCurrentIterationHistory(progress, history);
            if self.verbose {
                verbosePrint(step, iter);
            }
            iterations.push({startTime, endTime: time:utcNow(), history: iterationHistory, output: iterationOutput});
            if step is Error {
                error? cause = step.cause();
                log:printDebug("Error occurred during agent iteration",
                        step,
                        executionId = executionId,
                        iteration = iter,
                        sessionId = sessionId,
                        cause = cause !is () ? cause.toString() : "none");
                steps.push(step);
                break;
            }
            if step is string {
                content = step;
                log:printDebug("Final answer generated by agent",
                        executionId = executionId,
                        iteration = iter,
                        answer = step,
                        sessionId = sessionId
                    );
                finalAssistantMessage = {role: ASSISTANT, content: step};
                break;
            }
            steps.push(step);
            iter += 1;
            log:printDebug("Agent iteration started",
                    executionId = executionId,
                    iteration = iter,
                    maxIterations = self.maxIter,
                    stepsCompleted = steps.length(),
                    sessionId = sessionId
            );
            startTime = time:utcNow();
        }

        finalizeConversationMemory(self.memory, sessionId, self.stateless, progress,
                systemMessage, userMessage, finalAssistantMessage);
        // Collect all the tool call actions
        FunctionCall[] toolCalls = from ExecutionStep step in progress.executionSteps
            let var llmResponse = step.llmResponse
            where llmResponse is FunctionCall
            select llmResponse;
        return {steps, iterations, answer: content, toolCalls};
    }

    private isolated function executeParallelTools(
            FunctionCall[] toolCalls,
            ExecutionProgress progress,
            string executionId,
            string sessionId,
            Context context
    ) returns ParallelToolExecutionResult {
        ParallelToolExecutionResult parallelToolResult = [];
        map<[FunctionCall, future<ExecutionResult|ExecutionError>]> futures = {};

        foreach FunctionCall toolCall in toolCalls {
            toolCall.id = toolCall.id is () ? uuid:createRandomUuid() : toolCall.id;
            string toolId = toolCall.id.toString();
            future<ExecutionResult|ExecutionError> executionFuture = start self.getExecutionResult(toolCall.clone(), executionId, sessionId, context);
            futures[toolId] = [toolCall, executionFuture];
        }

        foreach [FunctionCall, future<ExecutionResult|ExecutionError>] [toolRec, executionFuture] in futures {
            ExecutionResult|ExecutionError|error waitResult = trap wait executionFuture;
            if waitResult is error {
                ExecutionError execErr = {
                    llmResponse: toolRec,
                    'error: error LlmInvalidGenerationError("Unexpected error during tool execution", cause = waitResult),
                    observation: "Tool execution failed unexpectedly."
                };
                parallelToolResult.push(execErr);
                progress.executionSteps.push({llmResponse: toolRec, observation: execErr.observation});
            } else {
                parallelToolResult.push(waitResult);
                progress.executionSteps.push({llmResponse: toolRec, observation: waitResult.observation});
            }
        }

        return parallelToolResult;
    }

    isolated function getExecutionResult(FunctionCall toolCall, string executionId, string sessionId, Context ctx) returns ExecutionResult|ExecutionError {
        string toolName = toolCall.name;
        log:printDebug("Parsed LLM response as tool call",
                executionId = executionId,
                sessionId = sessionId,
                toolName = toolName,
                arguments = toolCall.arguments
        );
        observe:ExecuteToolSpan span = setupToolSpan(toolName, self.toolStore, toolCall);

        ExecutionResult|ExecutionError executionResult;
        ToolOutput|ToolExecutionError|LlmInvalidGenerationError output = self.toolStore.execute(toolCall, ctx);
        if output is Error {
            string errorMessage;
            if output is ToolNotFoundError {
                errorMessage = "Tool is not found. Please check the tool name and retry.";
            } else if output is ToolInvalidInputError {
                errorMessage = "Tool execution failed due to invalid inputs. Retry with correct inputs.";
            } else {
                errorMessage = "Tool execution failed. Retry with correct inputs.";
            }
            string errorObservation = string `${errorMessage} <detail>${output.toString()}</detail>`;
            executionResult = {
                llmResponse: toolCall,
                'error: output,
                observation: errorObservation
            };
            log:printDebug("Tool execution resulted in error",
                    executionId = executionId,
                    observation = errorObservation,
                    sessionId = sessionId,
                    toolName = toolName
            );
        } else {
            anydata|error value = output.value;
            log:printDebug("Tool execution successful",
                    executionId = executionId,
                    sessionId = sessionId,
                    toolName = toolName,
                    output = value is error ? value.toString() : value
            );
            executionResult = {
                tool: toolCall,
                observation: value
            };
        }
        closeToolSpan(span, executionResult);
        return executionResult;
    }
}

# Get the tools registered with the agent.
#
# + agent - Agent instance
# + return - Array of tools registered with the agent
public isolated function getTools(Agent agent) returns Tool[] => agent.toolStore.tools.toArray();
