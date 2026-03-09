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

import ballerina/log;

// Tool registration logging

isolated function logToolRegistration(string tools) {
    log:printDebug("Registering tools",
            tools = tools
    );
}

isolated function logToolRegistrationCompleted(string tools) {
    log:printDebug("Tool registration completed",
            tools = tools
    );
}

isolated function logDuplicateToolName(string toolName) {
    log:printDebug("Duplicate tool name detected",
            toolName = toolName
    );
}

isolated function logInvalidToolName(string toolName) {
    log:printWarn(string `Tool name '${toolName}' contains invalid characters. Only alphanumeric, underscore and hyphen are allowed.`);
}

// Tool execution logging (ToolRegistry.execute)

isolated function logToolNotFound(string toolName, string[] availableTools) {
    log:printDebug("Tool not found",
            toolName = toolName,
            availableTools = availableTools
    );
}

isolated function logToolInputValidationFailed(error err, string toolName) {
    log:printDebug("Tool input validation failed",
            err,
            toolName = toolName
    );
}

isolated function logToolExecuting(string toolName, boolean isMcpTool, map<json> arguments) {
    log:printDebug("Executing tool",
            toolName = toolName,
            isMcpTool = isMcpTool,
            arguments = arguments
    );
}

isolated function logToolFailed(error err, string toolName) {
    log:printDebug("Tool execution failed",
            err,
            toolName = toolName
    );
}

isolated function logToolSucceeded(string toolName, string output) {
    log:printDebug("Tool executed successfully",
            toolName = toolName,
            output = output
    );
}

isolated function logToolInvalidOutput(string outputType, string toolName, map<json> inputs) {
    log:printDebug("Tool returns an invalid output. Expected anydata or error.",
            outputType = outputType,
            toolName = toolName,
            inputs = inputs
    );
}

isolated function logToolIncompatibleArguments(string instruction, string toolName, map<json> inputs) {
    log:printDebug(instruction,
            toolName = toolName,
            inputs = inputs
    );
}

// MCP toolkit logging

isolated function logMcpServerConnecting(string serverUrl, anydata clientInfo) {
    log:printDebug("Connecting to MCP server",
            serverUrl = serverUrl,
            clientInfo = clientInfo
    );
}

isolated function logMcpServerConnectionFailed(error err, string serverUrl) {
    log:printDebug("Failed to connect to MCP server",
            err,
            serverUrl = serverUrl
    );
}

isolated function logMcpClientInitFailed(error err, string serverUrl) {
    log:printDebug("Failed to initialize MCP client",
            err,
            serverUrl = serverUrl
    );
}

isolated function logMcpToolsRetrievalFailed(error err, string serverUrl) {
    log:printDebug("Failed to retrieve tools from MCP server",
            err,
            serverUrl = serverUrl
    );
}

isolated function logMcpToolsRetrieved(string serverUrl, anydata tools, anydata filteredTools) {
    log:printDebug("Retrieved tools from MCP server",
            serverUrl = serverUrl,
            tools = tools,
            filteredTools = filteredTools
    );
}

// HTTP toolkit logging

isolated function logHttpRequestStarted(string serverUrl, string path, string method) {
    log:printDebug(string `Executing HTTP ${method} request`,
            serverUrl = serverUrl,
            path = path,
            method = method
    );
}

isolated function logHttpRequestCompleted(string serverUrl, string path, string method, int statusCode) {
    log:printDebug("HTTP request completed",
            serverUrl = serverUrl,
            path = path,
            method = method,
            statusCode = statusCode
    );
}

isolated function logHttpRequestFailed(string serverUrl, string path, string method, string errorMessage) {
    log:printDebug("HTTP request failed",
            serverUrl = serverUrl,
            path = path,
            method = method,
            errorMessage = errorMessage
    );
}
