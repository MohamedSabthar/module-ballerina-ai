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

import ballerina/time;

# Manages the agent execution loop and LLM reasoning.
isolated class AgentExecutor {
    private final ModelProvider model;
    private final ToolStore toolStore;
    private final ToolExecutionHandler toolHandler;
    private final ToolLoadingStrategy toolLoadingStrategy;
    private final int maxIter;
    private final boolean verbose;

    isolated function init(ModelProvider model, ToolStore toolStore, ToolExecutionHandler toolHandler,
            ToolLoadingStrategy toolLoadingStrategy, int maxIter, boolean verbose) {
        self.model = model;
        self.toolStore = toolStore;
        self.toolHandler = toolHandler;
        self.toolLoadingStrategy = toolLoadingStrategy;
        self.maxIter = maxIter;
        self.verbose = verbose;
    }

    # Executes the agent loop for a given query.
    #
    # + query - Natural language commands to the agent
    # + sessionId - The ID associated with the memory
    # + context - Context values to be used by the agent to execute the task
    # + executionId - Unique identifier for this execution
    # + history - Conversation history including the current user query
    # + return - Returns the execution trace
    isolated function execute(string query, string sessionId, Context context,
            string executionId, ChatMessage[] history) returns ExecutionTrace {
        time:Utc startTime = time:utcNow();
        Iteration[] iterations = [];
        logExecutionLoopStarted(executionId, sessionId, self.maxIter);

        (ParallelToolExecutionResult|ExecutionResult|ExecutionError|Error)[] steps = [];
        string? content = ();
        ExecutionProgress progress = {instruction: "", query, context, executionId, history};
        ChatAssistantMessage? finalAssistantMessage = ();
        int iter = 0;

        while iter < self.maxIter {
            IterationResult iterResult = self.executeIteration(progress, sessionId, context, executionId);
            ParallelCallOutput|ChatAssistantMessage|ChatFunctionMessage|Error iterationOutput =
                    getOutputOfIteration(iterResult.step);
            ChatMessage[] iterationHistory = buildCurrentIterationHistory(progress, history);
            if self.verbose {
                verbosePrint(iterResult.step, iter);
            }
            iterations.push({startTime, endTime: time:utcNow(), history: iterationHistory, output: iterationOutput});

            ParallelToolExecutionResult|ExecutionResult|ExecutionError|Error|string step = iterResult.step;
            if iterResult.shouldStop {
                if step is Error {
                    steps.push(step);
                }
                if iterResult.content is string {
                    content = iterResult.content;
                    finalAssistantMessage = iterResult.assistantMessage;
                }
                break;
            }

            if step is ParallelToolExecutionResult|ExecutionResult|ExecutionError|Error {
                steps.push(step);
            }
            iter += 1;
            logIterationStarted(executionId, iter, self.maxIter, steps.length(), sessionId);
            startTime = time:utcNow();
        }

        FunctionCall[] toolCalls = from ExecutionStep step in progress.executionSteps
            let var llmResponse = step.llmResponse
            where llmResponse is FunctionCall
            select llmResponse;
        return {steps, iterations, answer: content, toolCalls, executionSteps: progress.executionSteps};
    }

    # Executes a single iteration of the agent loop: reason then act.
    private isolated function executeIteration(ExecutionProgress progress, string sessionId,
            Context context, string executionId) returns IterationResult {
        logLlmReasoningStarted(executionId, sessionId, progress.executionSteps.toString());

        FunctionCall[]|string|Error reason = self.selectNextTools(progress, sessionId);

        if reason is Error {
            logIterationError(executionId, sessionId, reason);
            return {step: reason, shouldStop: true, content: (), assistantMessage: ()};
        }

        if reason is string {
            logFinalAnswer(executionId, reason, sessionId);
            return {
                step: reason,
                shouldStop: true,
                content: reason,
                assistantMessage: {role: ASSISTANT, content: reason}
            };
        }

        ParallelToolExecutionResult step = self.toolHandler.executeParallel(
                reason, progress, executionId, sessionId, context);
        return {step, shouldStop: false, content: (), assistantMessage: ()};
    }

    # Uses the LLM to decide the next tool/step based on function calling APIs.
    #
    # + progress - Execution progress with the current query and execution history
    # + sessionId - The ID associated with the agent memory
    # + return - LLM response containing the tool or chat response
    isolated function selectNextTools(ExecutionProgress progress, string sessionId = DEFAULT_SESSION_ID)
            returns FunctionCall[]|string|Error {
        ChatMessage[] messages = createFunctionCallMessages(progress);
        messages.unshift(...progress.history);
        ChatCompletionFunctions[] filteredTools = getFilteredTools(
                self.toolStore, self.toolLoadingStrategy, messages, self.model);

        logToolSelectionRequest(progress.executionId, sessionId,
                messages.toString(), filteredTools.toString());

        ChatAssistantMessage response = check self.model->chat(messages, filteredTools);
        FunctionCall[]? toolCall = getToolCalls(response);

        if toolCall is FunctionCall[] {
            logToolsSelected(progress.executionId, sessionId, toolCall);
            return toolCall;
        }

        logChatResponse(progress.executionId, sessionId, response?.content);
        string? content = response?.content;
        return content is string ? content : error LlmInvalidGenerationError(LLM_INVALID_RESPONSE_MSG);
    }

    # Returns the maximum iteration count.
    isolated function getMaxIter() returns int => self.maxIter;
}
