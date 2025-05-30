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

# Represents the memory interface for the agents.
public type Memory isolated object {

    # Retrieves all stored chat messages.
    #
    # + sessionId - The ID associated with the memory
    # + return - An array of messages or an `ai:Error`
    public isolated function get(string sessionId) returns ChatMessage[]|MemoryError;

    # Adds a chat message to the memory.
    #
    # + sessionId - The ID associated with the memory
    # + message - The message to store
    # + return - nil on success, or an `ai:Error` if the operation fails 
    public isolated function update(string sessionId, ChatMessage message) returns MemoryError?;

    # Deletes all stored messages.
    # + sessionId - The ID associated with the memory
    # + return - nil on success, or an `ai:Error` if the operation fails
    public isolated function delete(string sessionId) returns MemoryError?;
};

# Provides an in-memory chat message window with a limit on stored messages.
public isolated class MessageWindowChatMemory {
    *Memory;
    private final int size;
    private final map<ChatMessage[]> sessions = {};
    private final map<ChatSystemMessage> systemMessageSessions = {};

    # Initializes a new memory window with a default or given size.
    # + size - The maximum capacity for stored messages
    public isolated function init(int size = 10) {
        self.size = size;
    }

    # Retrieves a copy of all stored messages, with an optional system prompt.
    #
    # + sessionId - The ID associated with the memory
    # + return - A copy of the messages, or an `ai:Error`
    public isolated function get(string sessionId) returns ChatMessage[]|MemoryError {
        lock {
            self.createSessionIfNotExist(sessionId);
            ChatMessage[] memory = self.sessions.get(sessionId);
            if self.systemMessageSessions.hasKey(sessionId) {
                memory.unshift(self.systemMessageSessions.get(sessionId).clone());
            }
            return memory.clone();
        }
    }

    # Adds a message to the window.
    #
    # + sessionId - The ID associated with the memory
    # + message - The `ChatMessage` to store or use as system prompt
    # + return - nil on success, or an `ai:Error` if the operation fails 
    public isolated function update(string sessionId, ChatMessage message) returns MemoryError? {
        lock {
            self.createSessionIfNotExist(sessionId);
            ChatMessage[] memory = self.sessions.get(sessionId);
            if memory.length() >= self.size - 1 {
                _ = memory.shift();
            }
            if message is ChatSystemMessage {
                self.systemMessageSessions[sessionId] = message.clone();
                return;
            }
            memory.push(message.clone());
        }
    }

    # Removes all messages from the memory.
    #
    # + sessionId - The ID associated with the memory
    # + return - nil on success, or an `ai:Error` if the operation fails 
    public isolated function delete(string sessionId) returns MemoryError? {
        lock {
            if !self.sessions.hasKey(sessionId) {
                return;
            }
            if self.systemMessageSessions.hasKey(sessionId) {
                _ = self.systemMessageSessions.remove(sessionId);
            }
            self.sessions.get(sessionId).removeAll();
        }
    }

    private isolated function createSessionIfNotExist(string sessionId) {
        lock {
            if !self.sessions.hasKey(sessionId) {
                self.sessions[sessionId] = [];
            }
        }
    }
}
