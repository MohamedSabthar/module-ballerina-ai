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

# This is the tool used by LLMs during reasoning.
# This tool is same as the Tool record, but it has a clear separation between the variables that should be generated with the help of the LLMs and the constants that are defined by the users. 
public type Tool record {|
    # Name of the tool
    string name;
    # Description of the tool
    string description;
    # Variables that should be generated with the help of the LLMs
    map<json> variables?;
    # Constants that are defined by the users
    map<json> constants = {};
    # Function that should be called to execute the tool
    isolated function caller;
|};

type ToolInfo record {|
    string name;
    string description;
|};

public isolated class ToolRegistry {
    public final map<Tool> & readonly tools;
    private map<()> mcpTools = {};

    # Register tools to the agent. 
    # These tools will be by the LLM to perform tasks.
    #
    # + tools - A list of tools that are available to the LLM
    # + return - An error if the tool is already registered
    public isolated function init((BaseToolKit|ToolConfig|FunctionTool)... tools) returns Error? {
        logToolRegistration(tools.toString());

        if tools.length() == 0 {
            self.tools = {};
            return;
        }
        ToolConfig[] toolList = [];
        foreach BaseToolKit|ToolConfig|FunctionTool tool in tools {
            if tool is FunctionTool {
                ToolConfig toolConfig = check getToolConfig(tool);
                toolList.push(toolConfig);
            } else if tool is BaseToolKit {
                ToolConfig[] toolsFromToolKit = tool.getTools(); // TODO remove this after Ballerina fixes nullpointer exception
                if tool is McpBaseToolKit {
                    foreach ToolConfig element in toolsFromToolKit {
                        lock {
                            self.mcpTools[element.name] = ();
                        }
                    }
                }
                toolList.push(...toolsFromToolKit);
            } else {
                toolList.push(tool);
            }
        }
        map<Tool & readonly> toolMap = {};
        check registerTool(toolMap, toolList);
        self.tools = toolMap.cloneReadOnly();

        logToolRegistrationCompleted(toolList.toString());
    }

    # Execute the tool decided by the LLM.
    #
    # + action - Action object that contains the tool name and inputs
    # + context - Additional context for the tool execution
    # + return - ActionResult containing the results of the tool execution or an error if tool execution fails
    public isolated function execute(LlmToolResponse action, Context context = new)
        returns ToolOutput|LlmInvalidGenerationError|ToolExecutionError {
        string name = action.name;
        map<json>? inputs = action.arguments;
        if !self.tools.hasKey(name) {
            logToolNotFound(name, self.tools.keys());
            return error ToolNotFoundError("Cannot find the tool.", toolName = name,
                instruction = string `Tool "${name}" does not exists.`
                + string ` Use a tool from the list: ${self.tools.keys().toString()}}`);
        }
        Tool tool = self.tools.get(name);
        map<json>|error inputValues = mergeInputs(inputs, tool.constants);
        if inputValues is error {
            logToolInputValidationFailed(inputValues, name);
            string instruction = string `Tool "${name}"  execution failed due to invalid inputs provided.` +
                string ` Use the schema to provide inputs: ${tool.variables.toString()}`;
            return error ToolInvalidInputError("Tool is provided with invalid inputs.", inputValues, toolName = name,
                inputs = inputs ?: (), instruction = instruction);
        }

        logToolExecuting(name, self.isMcpTool(name), inputValues);
        ToolExecutionResult|error execution;
        lock {
            readonly & map<json> toolInput = self.isMcpTool(name)
                ? {params: {name, arguments: inputValues}}.cloneReadOnly()
                : inputValues.cloneReadOnly();
            execution = trap executeTool(tool.caller, toolInput, context);
        }
        if execution is error {
            logToolFailed(execution, name);
            return error ToolExecutionError("Tool execution failed.", execution, toolName = name,
                inputs = inputValues.length() == 0 ? {} : inputValues);
        }
        return convertToolOutput(execution.result, name, inputValues, tool.variables);
    }

    isolated function getToolDescription(string toolName) returns string? {
        if self.tools.hasKey(toolName) {
            return self.tools.get(toolName).description;
        }
        return;
    }

    isolated function isMcpTool(string toolName) returns boolean {
        lock {
            return self.mcpTools.hasKey(toolName);
        }
    }

    isolated function getToolsInfo() returns ToolInfo[] {
        ToolInfo[] toolList = [];
        foreach [string, Tool] [name, tool] in self.tools.entries() {
            toolList.push({name, description: tool.description});
        }
        return toolList;
    }

    isolated function getToolSchema() returns ToolSchema[] {
        ToolSchema[] toolSchemas = [];
        foreach [string, Tool] [name, tool] in self.tools.entries() {
            toolSchemas.push({name, description: tool.description, parametersSchema: tool.variables});
        }
        return toolSchemas;
    }
}

