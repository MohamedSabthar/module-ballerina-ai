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

import ballerina/time;

isolated function buildTrace(string executionId, ChatUserMessage userMessage, Iteration[] iterations,
        readonly & ToolSchema[] tools, time:Utc startTime,
        string|Error output, FunctionCall[]? toolCalls) returns Trace {
    return {
        id: executionId,
        userMessage,
        iterations,
        tools,
        startTime,
        endTime: time:utcNow(),
        output: output is Error ? output : {role: ASSISTANT, content: output},
        toolCalls
    };
}

isolated function getAnswer(ExecutionTrace executionTrace, int maxIter) returns string|Error {
    string? answer = executionTrace.answer;
    return answer ?: constructError(executionTrace.steps, maxIter);
}

isolated function constructError((ParallelToolExecutionResult|ExecutionResult|ExecutionError|Error)[] steps, int maxIter) returns Error {
    if (steps.length() == maxIter) {
        return error MaxIterationExceededError("Maximum iteration limit exceeded while processing the query.",
                                                                                steps = steps);
    }
    // Validates whether the execution steps contain only one memory error.
    // If there is exactly one memory error, it is returned; otherwise, null is returned.
    if steps.length() == 1 {
        ParallelToolExecutionResult|ExecutionResult|ExecutionError|Error step = steps[0];
        if step is ParallelToolExecutionResult {
            foreach var item in step {
                if item is ExecutionError && item.'error is MemoryError {
                    return <MemoryError>item.'error;
                }
            }
        }
        if step is ExecutionError && step.'error is MemoryError {
            return <MemoryError>step.'error;
        }
    }
    return error Error("Unable to obtain valid answer from the agent", steps = steps);
}

isolated function getFormattedSystemPrompt(SystemPrompt systemPrompt) returns string {
    return string `# Role
${systemPrompt.role}

# Instructions
${systemPrompt.instructions}`;
}

isolated function getOutputOfIteration(ParallelToolExecutionResult|ExecutionResult|ExecutionError|Error|string step)
    returns ChatAssistantMessage|ChatFunctionMessage|Error|ParallelCallOutput {
    if step is Error {
        return step;
    }
    if step is string {
        return {role: ASSISTANT, content: step};
    }
    if step is ExecutionError {
        return step.'error;
    }
    if step is ParallelToolExecutionResult {
        ParallelCallOutput result = [];
        foreach var item in step {
            if item is ExecutionError {
                result.push(item.'error);
            } else {
                ChatFunctionMessage msg = {
                    role: FUNCTION,
                    name: item.tool.name,
                    id: item.tool.id,
                    content: getObservationString(item.observation)
                };
                result.push(msg);
            }
        }
        return result;
    }
    return {
        role: FUNCTION,
        name: step.tool.name,
        id: step.tool.id,
        content: getObservationString(step.observation)
    };
}

isolated function buildCurrentIterationHistory(ExecutionProgress progress,
        ChatMessage[] conversationHistoryUpToCurrentUserQuery) returns ChatMessage[] {
    ChatMessage[] messages = createFunctionCallMessages(progress);
    messages.unshift(...conversationHistoryUpToCurrentUserQuery);
    return messages;
}

isolated function getObservationString(anydata|error observation) returns string {
    if observation is () {
        return TOOL_NO_OUTPUT_MSG;
    } else if observation is error {
        record {|string message; string cause?;|} errorInfo = {
            message: observation.message().trim()
        };
        error? cause = observation.cause();
        if cause is error {
            errorInfo.cause = cause.message().trim();
        }
        return TOOL_ERROR_PREFIX + errorInfo.toString();
    } else {
        return observation.toString().trim();
    }
}

isolated function setupToolSpan(string toolName, ToolStore toolStore, FunctionCall toolCall) returns observe:ExecuteToolSpan {
    observe:ExecuteToolSpan span = observe:createExecuteToolSpan(toolName);
    string? toolCallId = toolCall.id;
    if toolCallId is string {
        span.addId(toolCallId);
    }
    string? toolDescription = toolStore.getToolDescription(toolName);
    if toolDescription is string {
        span.addDescription(toolDescription);
    }
    span.addType(toolStore.isMcpTool(toolName) ? observe:EXTENTION : observe:FUNCTION);
    span.addArguments(toolCall.arguments);
    return span;
}

isolated function closeToolSpan(observe:ExecuteToolSpan span, ExecutionResult|ExecutionError result) {
    if result is ExecutionError {
        Error toolExecutionError = error(result.observation, details = {llmResponse: result.llmResponse});
        span.close(toolExecutionError);
    } else {
        anydata|error value = result.observation;
        anydata observation = value is error ? value.toString() : value;
        span.addOutput(observation);
        span.close();
    }
}

isolated function createFunctionCallMessages(ExecutionProgress progress) returns ChatMessage[] {
    ChatMessage[] messages = [];
    foreach ExecutionStep step in progress.executionSteps {
        FunctionCall|error functionCall = step.llmResponse.fromJsonWithType();
        if functionCall is error {
            panic error Error("Badly formatted history for function call agent", llmResponse = step.llmResponse);
        }

        messages.push({
            role: ASSISTANT,
            toolCalls: [functionCall]
        },
        {
            role: FUNCTION,
            name: functionCall.name,
            content: getObservationString(step.observation),
            id: functionCall?.id
        });
    }
    return messages;
}
