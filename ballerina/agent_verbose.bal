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

import ballerina/io;

isolated function printExecution(ExecutionResult|ExecutionError step) {
    if step is ExecutionResult {
        LlmToolResponse tool = step.tool;
        io:println(string `Action:
    ${BACKTICKS}
    {
        ${ACTION_NAME_KEY}: ${tool.name},
        ${ACTION_ARGUEMENTS_KEY}: ${(tool.arguments ?: "None").toString()}
    }
    ${BACKTICKS}`);

        anydata|error observation = step?.observation;
        if observation is error {
            io:println(string `${OBSERVATION_KEY} (Error): ${observation.toString()}`);
        } else if observation !is () {
            io:println(string `${OBSERVATION_KEY}: ${observation.toString()}`);
        }
        return;
    }
    error? cause = step.'error.cause();
    io:println(string `LLM Generation Error:
    ${BACKTICKS}
    {
        message: ${step.'error.message()},
        cause: ${(cause is error ? cause.message() : "Unspecified")},
        llmResponse: ${step.llmResponse.toString()}
    }
    ${BACKTICKS}`);
}

isolated function verbosePrint(ParallelToolExecutionResult|ExecutionResult|ExecutionError|Error|string step, int iter) {
    io:println(string `${"\n\n"}Agent Iteration ${iter.toString()}`);
    if step is ParallelToolExecutionResult {
        step.forEach(item => printExecution(item));
        return;
    }
    if step is string {
        io:println(string `${"\n\n"}Final Answer: ${step}${"\n\n"}`);
        return;
    }
    if step is ExecutionResult|ExecutionError {
        printExecution(step);
    }
}
