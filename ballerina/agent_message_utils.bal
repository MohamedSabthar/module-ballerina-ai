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

isolated function cloneMessages(ChatMessage[] messages) returns readonly & ChatMessage[] {
    (ChatMessage & readonly)[] clonedMessages = [];
    foreach ChatMessage msg in messages {
        if msg is ChatUserMessage {
            clonedMessages.push(cloneUserMessage(msg));
            continue;
        }
        if msg is ChatSystemMessage {
            clonedMessages.push(cloneSystemMessage(msg));
            continue;
        }
        if msg is ChatAssistantMessage|ChatFunctionMessage {
            clonedMessages.push(msg.cloneReadOnly());
        }
    }
    return clonedMessages.cloneReadOnly();
}

isolated function cloneUserMessage(ChatUserMessage message) returns readonly & ChatUserMessage {
    string|Prompt content = message.content;
    (string|Prompt) & readonly clonedContent = content is string ? content
        : createPrompt(content.strings, content.insertions.cloneReadOnly());
    return {
        role: USER,
        content: clonedContent,
        name: message?.name
    };
}

isolated function cloneSystemMessage(ChatSystemMessage message) returns readonly & ChatSystemMessage {
    string|Prompt content = message.content;
    (string|Prompt) & readonly clonedContent = content is string ? content
        : createPrompt(content.strings, content.insertions.cloneReadOnly());
    return {
        role: SYSTEM,
        content: clonedContent,
        name: message?.name
    };
}
