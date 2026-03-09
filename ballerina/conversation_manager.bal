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

# Manages conversation history and memory for agent sessions.
isolated class ConversationManager {
    private final Memory memory;
    private final boolean stateless;

    isolated function init(Memory memory, boolean stateless) {
        self.memory = memory;
        self.stateless = stateless;
    }

    # Initializes conversation history from memory for a new execution.
    #
    # + sessionId - The ID associated with the agent memory
    # + systemPrompt - The system prompt for the agent
    # + query - The user's query
    # + executionId - Unique identifier for this execution
    # + return - A tuple of [history, systemMessage, userMessage]
    isolated function initializeHistory(string sessionId, string systemPrompt, string query,
            string executionId) returns [ChatMessage[], ChatSystemMessage, ChatUserMessage] {
        ChatMessage[]|MemoryError prevHistory = self.memory.get(sessionId);
        if prevHistory is MemoryError {
            logMemoryRetrievalFailed(executionId, sessionId, prevHistory);
        }
        ChatMessage[] history = (prevHistory is ChatMessage[]) ? [...prevHistory] : [];
        ChatSystemMessage systemMessage = {role: SYSTEM, content: systemPrompt};
        if history.length() > 0 {
            ChatMessage firstMessage = history[0];
            if firstMessage is ChatSystemMessage && systemPrompt != toString(firstMessage.content) {
                history[0] = systemMessage;
            }
        } else {
            history.unshift(systemMessage);
        }
        ChatUserMessage userMessage = {role: USER, content: query};
        history.push(userMessage);
        return [history, systemMessage, userMessage];
    }

    # Finalizes conversation memory after execution completes.
    #
    # + sessionId - The ID associated with the agent memory
    # + progress - The execution progress containing intermediate steps
    # + systemMessage - The system message used in this execution
    # + userMessage - The user message for this execution
    # + finalAssistantMessage - The final assistant response, if any
    isolated function finalizeMemory(string sessionId, ExecutionProgress progress,
            ChatSystemMessage systemMessage, ChatUserMessage userMessage,
            ChatAssistantMessage? finalAssistantMessage) {
        ChatMessage[] temporaryMemory = [systemMessage, userMessage];
        ChatMessage[] intermediateFunctionCallMessages = createFunctionCallMessages(progress);
        temporaryMemory.push(...intermediateFunctionCallMessages);
        if finalAssistantMessage is ChatAssistantMessage {
            temporaryMemory.push(finalAssistantMessage);
        }
        MemoryError? updateResult = self.memory.update(sessionId, temporaryMemory);
        if updateResult is MemoryError {
            logMemoryUpdateFailed(updateResult);
        }
        if self.stateless {
            MemoryError? deleteResult = self.memory.delete(sessionId);
            if deleteResult is MemoryError {
                logMemoryDeleteFailed(deleteResult);
            }
        }
    }
}
