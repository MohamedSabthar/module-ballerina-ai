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

# Extracts a ToolConfig from a FunctionTool using its AgentTool annotation.
#
# + tool - The function tool to extract configuration from
# + return - The tool configuration or an error if the annotation is missing
isolated function getToolConfig(FunctionTool tool) returns ToolConfig|Error {
    typedesc<FunctionTool> typedescriptor = typeof tool;
    ToolAnnotationConfig? config = typedescriptor.@AgentTool;
    if config is () {
        return error Error("The function '" + getFunctionName(tool) + "' must be annotated with `@ai:AgentTool`.");
    }
    do {
        return {
            name: check config?.name.ensureType(),
            description: check config?.description.ensureType(),
            parameters: check config?.parameters.ensureType(),
            caller: tool
        };
    } on fail error e {
        return error Error("Unable to register the function '" + getFunctionName(tool) + "' as agent tool", e);
    }
}

# Validates and registers tools into the tool map.
# Ensures tool names are unique, valid, and not reserved.
#
# + toolMap - The map to register tools into
# + tools - The tool configurations to register
# + return - An error if registration fails
isolated function registerTool(map<Tool & readonly> toolMap, ToolConfig[] tools) returns Error? {
    foreach ToolConfig tool in tools {
        string name = tool.name;
        if name.toLowerAscii().matches(FINAL_ANSWER_REGEX) {
            return error Error(string ` Tool name '${name}' is reserved for the 'Final answer'.`);
        }
        if !name.matches(re `^[a-zA-Z0-9_-]{1,64}$`) {
            logInvalidToolName(name);
            if name.length() > 64 {
                name = name.substring(0, 64);
            }
            name = regexp:replaceAll(re `[^a-zA-Z0-9_-]`, name, "_");
        }
        if toolMap.hasKey(name) {
            logDuplicateToolName(name);
            return error Error("Duplicated tools. Tool name should be unique.", toolName = name);
        }

        map<json>|error? variables = tool.parameters.cloneWithType();
        if variables is error {
            return error Error("Unable to register tool", variables);
        }
        map<json> constants = {};

        if variables is map<json> {
            constants = resolveSchema(variables) ?: {};
        }

        Tool agentTool = {
            name,
            description: regexp:replaceAll(re `\n`, tool.description, " "),
            variables,
            constants,
            caller: tool.caller
        };
        toolMap[name] = agentTool.cloneReadOnly();
    }
}
