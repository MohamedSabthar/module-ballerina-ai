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

final readonly & Prompt defaultSummarizationPrompt = `
    You are an expert at summarizing conversations. You will summarize a chat history between a 
    user and an AI agent to create a concise summary that preserves the most important information.
    
    Before coming up with the summary, think through:
    - the main topics, questions, or issues discussed in the chat history
    - key information, decisions, or conclusions that should be preserved
    - what details can be omitted or condensed
    - how the summary can be structured to be useful for future reference

    Prioritize:
    - the most recent user request or question to ensure the summary reflects the immediate context
    - key decisions or conclusions reached during the conversation
    - critical context that affects ongoing conversations
    - unresolved issues that may need follow-up
    - specific details that are likely to be referenced again
    
    Expected structure:
    - Use clear, concise sentences
    - Group related topics together
    - Maintain chronological order when the sequence of events matters.`;

# Represents configuration to trim messages when overflow occurs.
public type TrimOverflowHandlerConfiguration record {|
    # Number of messages to trim when overflow occurs.
    int trimCount = 1;
|};

# Represents configuration to handle messages using a model when overflow occurs.
public type ModelAssistedOverflowHandlerConfiguration record {|
    # The model to use; if not provided, the default model is used.
    ModelProvider model?;
    # The prompt to use; if not provided, a default summarization prompt is used.
    Prompt prompt = defaultSummarizationPrompt;
|};

# Represents configuration for handling overflow in short-term memory.
public type OverflowHandlerConfiguration TrimOverflowHandlerConfiguration|ModelAssistedOverflowHandlerConfiguration;

type OverflowHandlerFunction isolated function (
        ChatInteractiveMessage[] messages) returns ChatInteractiveMessage[]|MemoryError;

type OverflowHandler TrimOverflowHandlerConfiguration|OverflowHandlerFunction;

# Represents short-term memory for agents.
public isolated class ShortTermMemory {
    *Memory;
    *Checkpointer;

    private final OverflowHandler overflowHandler;
    // Where conversation messages live. This should be final, but is not final intentionally, to
    // enforce using locks.
    private ShortTermMemoryStore store;
    // Where human-in-the-loop pause checkpoints live, resolved once at init: the `store` itself
    // when it is checkpoint-capable (so pauses share the store's durability), otherwise a private
    // in-memory checkpointer. Mirrors `store` - one unconditional home per concern.
    private final Checkpointer checkpointer;

    # Initializes short-term memory with an optional store and overflow configuration.
    #
    # + store - The memory store to use; if not provided, an in-memory store is used. If this
    # store also implements `Checkpointer`, it is used to persist human-in-the-loop pause
    # checkpoints too - see `checkpointer` below.
    # + overflowConfiguration - The strategy to handle overflow; if not provided, trimming is used
    # + checkpointer - Where human-in-the-loop pause checkpoints are persisted. Only needed if you
    # want durable checkpoints backed by something other than `store` (e.g. a dedicated backend, or
    # `store` doesn't implement `Checkpointer`). If not provided: `store` is used when it implements
    # `Checkpointer` (so one backend serves both concerns), otherwise checkpoints are kept in an
    # in-memory fallback that does not survive a restart.
    # + return - nil on success, or an `ai:MemoryError` error if the initialization fails
    public isolated function init(ShortTermMemoryStore? store = (),
                                  OverflowHandlerConfiguration overflowConfiguration = <TrimOverflowHandlerConfiguration> {},
                                  Checkpointer? checkpointer = ())
                            returns MemoryError? {
        do {
            ShortTermMemoryStore resolvedStore = store ?: check new InMemoryShortTermMemoryStore();
            self.store = resolvedStore;
            self.checkpointer = checkpointer ?: resolveCheckpointerFromStore(resolvedStore);

            if overflowConfiguration is TrimOverflowHandlerConfiguration {
                self.overflowHandler = overflowConfiguration.cloneReadOnly();
            } else {
                final ModelProvider model = overflowConfiguration.model ?: check getDefaultModelProvider();
                final Prompt prompt = overflowConfiguration.prompt;
                final string[] & readonly strings = prompt.strings;
                final anydata[] & readonly insertions = prompt.insertions.cloneReadOnly();
                self.overflowHandler = isolated function (
                        ChatInteractiveMessage[] messages) returns ChatInteractiveMessage[]|MemoryError {
                    return handleOverflow(model, createPrompt(strings, insertions), messages);
                };
            }
        } on fail error e {
            return error("Failed to initialize short term memory: " + e.message(), e);
        }
    }

    # Retrieves all stored chat messages.
    #
    # + key - The key associated with the memory
    # + return - An array of messages or an `ai:MemoryError` error if the operation fails
    public isolated function get(string key) returns ChatMessage[]|MemoryError {
        lock {
            return self.store.getAll(key);
        }
    }

    # Adds one or more chat messages to the memory, handling overflow as configured.
    #
    # + key - The key associated with the memory
    # + message - The chat message or array of messages to store in memory
    # + return - nil on success, or an `ai:MemoryError` error if the operation fails 
    public isolated function update(string key, ChatMessage|ChatMessage[] message) returns MemoryError? {
        if message is ChatMessage[] {
            return self.batchUpdate(key, message);
        }
        final readonly & MemoryChatMessage memoryChatMessage = check mapToMemoryChatMessage(message);
        lock {
            if memoryChatMessage is ChatSystemMessage {
                return self.store.put(key, memoryChatMessage);
            }

            if check self.exceedsMemoryLimit(key, memoryChatMessage) {
                final OverflowHandler overflowHandler = self.overflowHandler;
                if overflowHandler is TrimOverflowHandlerConfiguration {
                    check self.store.removeChatInteractiveMessages(key, overflowHandler.trimCount);
                    return self.store.put(key, memoryChatMessage);
                }
                ChatMessage[] updatedMessages = check overflowHandler(check self.store.getChatInteractiveMessages(key));
                check self.store.removeChatInteractiveMessages(key);
                return self.store.put(key, [...updatedMessages, memoryChatMessage]);
            }
            return self.store.put(key, memoryChatMessage);
        }
    }

    private isolated function batchUpdate(string key, ChatMessage[] messages) returns MemoryError? {
        final readonly & MemoryChatMessage[] memoryChatMessages = from ChatMessage msg in messages
            select check mapToMemoryChatMessage(msg);
        lock {
            var [systemMessages, interactiveMessages] = partitionChatMessagesByType(memoryChatMessages);
            ChatMessage[] allMessages = [];
            if systemMessages.length() > 0 {
                // Update only the latest system message, ignore others
                allMessages = [systemMessages.pop()];
            }

            if check self.exceedsMemoryLimit(key, interactiveMessages) {
                final OverflowHandler overflowHandler = self.overflowHandler;
                ChatMessage[] overflowHandledMessages = overflowHandler is TrimOverflowHandlerConfiguration
                    ? check self.getInteractiveMessagesAfterTrim(key, overflowHandler, interactiveMessages)
                    : check self.getInteractiveMessagesAfterSummarization(key, overflowHandler, interactiveMessages);
                allMessages.push(...overflowHandledMessages);
            } else {
                allMessages.push(...interactiveMessages);
            }
            
            if allMessages.length() == 0 {
                return;
            }
            return self.store.put(key, allMessages);
        }
    }

    private isolated function exceedsMemoryLimit(string key, ChatMessage|ChatMessage[] message)
        returns boolean|MemoryError {
        lock {
            int storeCapacity = self.store.getCapacity();
            int incomingMessageLength = message is ChatMessage ? 1 : message.length();
            // Early return to avoid a network-call/unnecessary store operation if incoming alone exceeds capacity
            if incomingMessageLength > storeCapacity {
                return true;
            }
            int currentLength = (check self.store.getChatInteractiveMessages(key)).length();
            return currentLength + incomingMessageLength > storeCapacity;
        }
    }

    private isolated function getInteractiveMessagesAfterTrim(string key, TrimOverflowHandlerConfiguration trimHandler,
            MemoryChatInteractiveMessage[] incomingInteractiveMsgs) returns MemoryError|ChatMessage[] {
        lock {
            int incomingCount = incomingInteractiveMsgs.length();
            ChatMessage[] existing = check self.store.getChatInteractiveMessages(key);
            check self.store.removeChatInteractiveMessages(key);

            int currentSize = existing.length();
            int trimCount = trimHandler.trimCount;
            int capacity = self.store.getCapacity();

            // Count how many times trimming needs to occur during the simulation
            int totalMessages = currentSize + incomingCount;
            int trimCycles = totalMessages > capacity  ? ((totalMessages - capacity + trimCount - 1) / trimCount) : 0;
            int totalRemovals = trimCycles * trimCount;

            ChatMessage[] combined = [...existing, ...incomingInteractiveMsgs.clone()];
            combined = totalRemovals > 0 ? combined.slice(totalRemovals) : combined;
            return combined.'map(msg => check mapToMemoryChatMessage(msg)).clone();
        }
    }

    private isolated function getInteractiveMessagesAfterSummarization(string key, OverflowHandlerFunction summarizationHandler,
            MemoryChatInteractiveMessage[] incomingInteractiveMsgs) returns MemoryError|ChatMessage[] {
        lock {
            MemoryChatInteractiveMessage[] interactiveMsgs = incomingInteractiveMsgs.clone();
            ChatInteractiveMessage[] currentMessages = check self.store.getChatInteractiveMessages(key);
            int incoming = interactiveMsgs.length();
            int maxSize = self.store.getCapacity();

            int effectiveCount = incoming % maxSize == 0 ? maxSize : incoming % maxSize;
            ChatInteractiveMessage[] tailMessages = interactiveMsgs.slice(incoming - effectiveCount);

            ChatInteractiveMessage[] headMessages = interactiveMsgs.slice(0, incoming - effectiveCount);
            ChatMessage[] processedHead = check summarizationHandler([...currentMessages, ...headMessages]);

            check self.store.removeChatInteractiveMessages(key);
            ChatMessage[] combined = [...processedHead, ...tailMessages];
            return combined.'map(msg => check mapToMemoryChatMessage(msg)).clone();
        }
    }

    # Deletes all messages stored against a key.
    # 
    # + key - The key associated with the memory
    # + return - nil on success, or an `ai:MemoryError` error if the operation fails
    public isolated function delete(string key) returns MemoryError? {
        lock {
            return self.store.removeAll(key);
        }
    }

    # Stores (or replaces) the pending approval for its session.
    #
    # + approval - The pending approval to persist
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function putCheckpoint(PendingApproval approval) returns Error? =>
        self.checkpointer.putCheckpoint(approval);

    # Returns the pending approval for a session, if any.
    #
    # + sessionId - The session to look up
    # + return - The pending approval, `()` if none is pending, or an `ai:Error` if the operation fails
    public isolated function getCheckpoint(string sessionId) returns PendingApproval?|Error =>
        self.checkpointer.getCheckpoint(sessionId);

    # Removes the pending approval for a session, if any.
    #
    # + sessionId - The session to clear
    # + return - `()` on success, or an `ai:Error` if the operation fails
    public isolated function removeCheckpoint(string sessionId) returns Error? =>
        self.checkpointer.removeCheckpoint(sessionId);

    # Atomically fetches and removes the pending approval for a session, if any.
    #
    # + sessionId - The session to claim
    # + return - The claimed pending approval, `()` if none was pending, or an `ai:Error` if the operation fails
    public isolated function takeCheckpoint(string sessionId) returns PendingApproval?|Error =>
        self.checkpointer.takeCheckpoint(sessionId);
}

# Resolves the default checkpoint home when no explicit `checkpointer` is supplied to
# `ShortTermMemory.init`: `store` itself when it also implements `Checkpointer` (so one backend
# durably serves both messages and human-in-the-loop pause state), otherwise a fresh in-memory
# checkpointer (pauses will not survive a restart or a run on another replica).
#
# + store - The resolved message store to check for checkpoint capability
# + return - `store` narrowed to `Checkpointer` if it implements it, otherwise a new `InMemoryCheckpointer`
isolated function resolveCheckpointerFromStore(ShortTermMemoryStore store) returns Checkpointer {
    // Narrow through `any`: testing `store is Checkpointer` directly yields the object-intersection
    // type `ShortTermMemoryStore & Checkpointer`, which the code generator cannot emit ("jVM
    // generation is not supported for type other"). A `ShortTermMemoryStore` genuinely can also be
    // a `Checkpointer` - Ballerina objects are structurally typed, so a concrete class can include
    // both `*ShortTermMemoryStore;` and `*Checkpointer;` (this is exactly how one store backs both
    // concerns); widening to `any` first lets the check narrow to a plain `Checkpointer` instead.
    any storeValue = store;
    return storeValue is Checkpointer ? storeValue : new InMemoryCheckpointer();
}

isolated function handleOverflow(
            ModelProvider model, Prompt & readonly prompt, ChatInteractiveMessage[] memory) 
        returns ChatInteractiveMessage[]|MemoryError {
    int memoryLength = memory.length();
    if memoryLength == 0 {
        return [];
    }

    int memoryLastIndex = memoryLength - 1;

    ChatInteractiveMessage lastMessage = memory[memoryLastIndex];

    MemoryChatInteractiveMessage[] memoryChatMessages = check mapToMemoryChatInteractiveMessages(memory);
    
    // Since we add the summary as an assistant message, we only summarize up to the last user message,
    // to maintain an interactive flow.
    boolean isLastMessageFromUser = lastMessage.role == USER;

    MemoryChatInteractiveMessage[] sliceToSummarize = isLastMessageFromUser ? 
        memoryChatMessages.slice(0, memoryLastIndex) : memoryChatMessages;

    ChatAssistantMessage|Error summaryMessage = callModelToHandleOverflow(sliceToSummarize, model, prompt);
    if summaryMessage is Error {
        return error("Failed to generate summary: " + summaryMessage.message(), summaryMessage);
    }

    ChatInteractiveMessage[] updatedMessages = [summaryMessage];
    if isLastMessageFromUser {
        updatedMessages.push(lastMessage);
    }
    return updatedMessages;
}

isolated function callModelToHandleOverflow(MemoryChatMessage[] memorySlice, ModelProvider model, Prompt prompt) 
        returns ChatAssistantMessage|Error {
    return model->chat([
        {
            role: SYSTEM,
            content: prompt
        },
        {
            role: USER, 
            content: `Summarize this chat history: ${memorySlice.toString()}`
        }
    ]);
}

isolated function toString(Prompt|string prompt) returns string {
    if prompt is string {
        return prompt;
    }
    string[] & readonly strings = prompt.strings;
    anydata[] insertions = prompt.insertions;

    string promptString = strings[0];
    foreach int i in 0 ..< insertions.length() {
        promptString += insertions[i].toJsonString() + strings[i + 1];
    }
    return promptString;
}

isolated function partitionChatMessagesByType(MemoryChatMessage[] memoryChatMessages)
    returns [MemoryChatSystemMessage[], MemoryChatInteractiveMessage[]] {
    MemoryChatSystemMessage[] systemMessages = [];
    MemoryChatInteractiveMessage[] interactiveMessages = [];
    from MemoryChatMessage msg in memoryChatMessages
    do {
        if msg is MemoryChatSystemMessage {
            systemMessages.push(msg);
        } else {
            interactiveMessages.push(msg);
        }
    };
    return [systemMessages, interactiveMessages];
}
