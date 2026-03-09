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

import ballerina/uuid;

# Handles single and parallel tool execution, error classification, and span management.
isolated class ToolExecutionHandler {
    private final ToolStore toolStore;

    isolated function init(ToolStore toolStore) {
        self.toolStore = toolStore;
    }

    # Executes multiple tool calls in parallel and records results in the execution progress.
    #
    # + toolCalls - The tool calls to execute
    # + progress - The execution progress to record results into
    # + executionId - Unique identifier for this execution
    # + sessionId - The session identifier
    # + context - Additional context for tool execution
    # + return - Results from all parallel tool executions
    isolated function executeParallel(FunctionCall[] toolCalls, ExecutionProgress progress,
            string executionId, string sessionId, Context context) returns ParallelToolExecutionResult {
        ParallelToolExecutionResult parallelToolResult = [];
        map<[FunctionCall, future<ExecutionResult|ExecutionError>]> futures = {};

        foreach FunctionCall toolCall in toolCalls {
            toolCall.id = toolCall.id is () ? uuid:createRandomUuid() : toolCall.id;
            string toolId = toolCall.id.toString();
            future<ExecutionResult|ExecutionError> executionFuture =
                    start self.executeTool(toolCall.clone(), executionId, sessionId, context);
            futures[toolId] = [toolCall, executionFuture];
        }

        foreach [FunctionCall, future<ExecutionResult|ExecutionError>] [toolRec, executionFuture] in futures {
            ExecutionResult|ExecutionError|error waitResult = trap wait executionFuture;
            ExecutionResult|ExecutionError result;
            if waitResult is error {
                result = {
                    llmResponse: toolRec,
                    'error: error LlmInvalidGenerationError(UNEXPECTED_TOOL_ERROR_MSG, cause = waitResult),
                    observation: TOOL_EXECUTION_FAILED_OBSERVATION
                };
            } else {
                result = waitResult;
            }
            parallelToolResult.push(result);
            progress.executionSteps.push({llmResponse: toolRec, observation: result.observation});
        }

        return parallelToolResult;
    }

    # Executes a single tool call with span tracing and error handling.
    #
    # + toolCall - The tool call to execute
    # + executionId - Unique identifier for this execution
    # + sessionId - The session identifier
    # + ctx - Additional context for tool execution
    # + return - The execution result or error
    isolated function executeTool(FunctionCall toolCall, string executionId, string sessionId, Context ctx)
            returns ExecutionResult|ExecutionError {
        string toolName = toolCall.name;
        logToolCallParsed(executionId, sessionId, toolName, toolCall.arguments);
        observe:ExecuteToolSpan span = setupToolSpan(toolName, self.toolStore, toolCall);

        ToolOutput|ToolExecutionError|LlmInvalidGenerationError output = self.toolStore.execute(toolCall, ctx);
        ExecutionResult|ExecutionError executionResult;
        if output is Error {
            ExecutionError errorResult = buildToolErrorResult(toolCall, output);
            executionResult = errorResult;
            logToolExecutionError(executionId, errorResult.observation, sessionId, toolName);
        } else {
            anydata|error value = output.value;
            logToolExecutionSuccess(executionId, sessionId, toolName, value);
            executionResult = {
                tool: toolCall,
                observation: value
            };
        }
        closeToolSpan(span, executionResult);
        return executionResult;
    }
}

# Builds an ExecutionError from a tool execution failure with classified error message.
isolated function buildToolErrorResult(FunctionCall toolCall, LlmInvalidGenerationError|ToolExecutionError output) returns ExecutionError {
    string errorMessage;
    if output is ToolNotFoundError {
        errorMessage = TOOL_NOT_FOUND_MSG;
    } else if output is ToolInvalidInputError {
        errorMessage = TOOL_INVALID_INPUT_MSG;
    } else {
        errorMessage = TOOL_EXECUTION_FAILED_MSG;
    }
    return {
        llmResponse: toolCall,
        'error: output,
        observation: string `${errorMessage} <detail>${output.toString()}</detail>`
    };
}
