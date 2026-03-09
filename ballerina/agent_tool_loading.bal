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

import ballerina/lang.regexp;
import ballerina/log;

isolated function modifyUserPromptWithToolsInfo(ChatUserMessage chatUserMsg, ToolInfo[] toolInfo)
returns ChatUserMessage {
    string toolsPrompt = string `

These are the tools available to you:
${BACKTICKS}
${toolInfo.toJsonString()}
${BACKTICKS}

Select only the tools required to complete the task and return them as a JSON array of tool names:
${BACKTICKS}
["toolNameOne","toolNameTwo","toolNameN"]
${BACKTICKS}

If no tools are needed, return an empty array:
${BACKTICKS}
[]
${BACKTICKS}`;

    string|Prompt content = chatUserMsg.content;
    if content is string {
        content += toolsPrompt;
    } else {
        content.insertions.push(toolsPrompt);
    }

    return {role: USER, content, name: chatUserMsg.name};
}

isolated function getSelectedToolsFromAssistantMessage(ChatAssistantMessage assistantMsg) returns string[]? {
    do {
        string rawResponse = assistantMsg.content ?: "[]";
        string cleanedJson = regexp:replaceAll(check regexp:fromString("```"), rawResponse, "");
        return check cleanedJson.fromJsonStringWithType();
    } on fail {
        // In case of failure try to load all tools and ignore the error
        return;
    }
}

isolated function lazyLoadTools(ChatMessage[] messages, ChatCompletionFunctions[] registeredTools,
        ModelProvider model) returns ChatCompletionFunctions[]? {
    ChatMessage lastMessage = messages[messages.length() - 1];
    if lastMessage !is ChatUserMessage {
        return;
    }
    ToolInfo[] toolInfo = registeredTools.'map(tool => {name: tool.name, description: tool.description});
    ChatUserMessage modifiedUserMessage = modifyUserPromptWithToolsInfo(lastMessage, toolInfo);

    // Replace the last user message with the modified one that includes the tools prompt
    _ = messages.pop();
    messages.push(modifiedUserMessage);

    ChatAssistantMessage|Error response = model->chat(messages, []);
    if response is Error {
        return;
    }

    log:printDebug(string `Calling model for lazy tool loading. Raw response: ${response.content.toString()}`);
    string[]? selectedTools = getSelectedToolsFromAssistantMessage(response);
    log:printDebug(string `Extracted tools from model response: ${selectedTools.toString()}`);

    if selectedTools is string[] {
        // Only load the tool schemas picked by the model
        return from ChatCompletionFunctions tool in registeredTools
            let string toolName = tool.name
            where selectedTools.some(selected => selected == toolName)
            select tool;
    }
    return;
}

isolated function getToolCalls(ChatAssistantMessage msg) returns FunctionCall[]? {
    FunctionCall[]? toolCalls = msg?.toolCalls;
    if toolCalls is () || toolCalls.length() == 0 {
        return;
    }
    return toolCalls;
}

# Returns the filtered set of tools based on the tool loading strategy.
#
# + toolStore - The tool store containing registered tools
# + strategy - The tool loading strategy to apply
# + messages - The current conversation messages
# + model - The model provider for LLM-based filtering
# + return - The filtered set of tool schemas
isolated function getFilteredTools(ToolRegistry toolStore, ToolLoadingStrategy strategy,
        ChatMessage[] messages, ModelProvider model) returns ChatCompletionFunctions[] {
    ChatCompletionFunctions[] registeredTools = from Tool tool in toolStore.tools.toArray()
        select {
            name: tool.name,
            description: tool.description,
            parameters: tool.variables
        };
    if strategy == LLM_FILTER {
        ChatMessage lastMessage = messages[messages.length() - 1];
        if lastMessage is ChatUserMessage {
            ChatCompletionFunctions[]? selectedTools = lazyLoadTools(cloneMessages(messages), registeredTools, model);
            if selectedTools !is () {
                return selectedTools;
            }
        }
    }
    return registeredTools;
}
