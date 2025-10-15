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

import ballerina/uuid;

const INFER_TOOL_COUNT = "INFER_TOOL_COUNT";

# Represents the system prompt given to the agent.
@display {label: "System Prompt"}
public type SystemPrompt record {|

    # The role or responsibility assigned to the agent
    @display {label: "Role"}
    string role;

    # Specific instructions for the agent
    @display {label: "Instructions"}
    string instructions;
|};

# Represents the different types of agents supported by the module.
@display {label: "Agent Type"}
public enum AgentType {
    # Represents a ReAct agent
    REACT_AGENT,
    # Represents a function call agent
    FUNCTION_CALL_AGENT
}

# Provides a set of configurations for the agent.
@display {label: "Agent Configuration"}
public type AgentConfiguration record {|

    # The system prompt assigned to the agent
    @display {label: "System Prompt"}
    SystemPrompt systemPrompt;

    # The model used by the agent
    @display {label: "Model"}
    ModelProvider model;

    # The tools available for the agent
    @display {label: "Tools"}
    (BaseToolKit|ToolConfig|FunctionTool)[] tools = [];

    # The maximum number of iterations the agent performs to complete the task.
    # By default, it is set to the number of tools + 1.
    @display {label: "Maximum Iterations"}
    INFER_TOOL_COUNT|int maxIter = INFER_TOOL_COUNT;

    # Specifies whether verbose logging is enabled
    @display {label: "Verbose"}
    boolean verbose = false;

    # The memory used by the agent to store and manage conversation history
    @display {label: "Memory"}
    Memory? memory = new MessageWindowChatMemory();
|};

# Represents an agent.
public isolated distinct class Agent {
    final FunctionCallAgent functionCallAgent;
    private final int maxIter;
    private final readonly & SystemPrompt systemPrompt;
    private final boolean verbose;
    private final string uniqueId = uuid:createRandomUuid();

    # Initialize an Agent.
    #
    # + config - Configuration used to initialize an agent
    public isolated function init(@display {label: "Agent Configuration"} *AgentConfiguration config) returns Error? {
        INFER_TOOL_COUNT|int maxIter = config.maxIter;
        self.maxIter = maxIter is INFER_TOOL_COUNT ? config.tools.length() + 1 : maxIter;
        self.verbose = config.verbose;
        self.systemPrompt = config.systemPrompt.cloneReadOnly();
        FunctionCallAgent|Error functionCallAgent = new (config.model, config.tools, config.memory);
        // https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/#create-agent-span
        observe:AiSpan span = new observe:SpanImp(string `create_agent ${self.systemPrompt.role}`);
        span.addTag(observe:OPERATION_NAME, "create_agent");
        span.addTag(observe:PROVIDER_NAME, "Ballerina");
        span.addTag(observe:AGENT_ID, self.uniqueId);
        span.addTag(observe:AGENT_NAME, self.systemPrompt.role);
        span.addTag(observe:SYSTEM_INSTRUCTIONS, getFomatedSystemPrompt(self.systemPrompt));
        if functionCallAgent is Error {
            span.close(functionCallAgent); // what is the standard way?
            return functionCallAgent;
        }
        self.functionCallAgent = functionCallAgent;
        span.addTag(observe:AGENT_TOOLS, functionCallAgent.toolStore.getToolsInfo()); // Added by us not mandated by spec
        span.close();
    }

    # Executes the agent for a given user query.
    #
    # + query - The natural language input provided to the agent
    # + sessionId - The ID associated with the agent memory
    # + context - The additional context that can be used during agent tool execution
    # + return - The agent's response or an error
    public isolated function run(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new) returns string|Error {
        // https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/#invoke-agent-span
        observe:AiSpan span = new observe:SpanImp(string `invoke_agent ${self.systemPrompt.role}`);
        span.addTag(observe:OPERATION_NAME, "invoke_agent");
        span.addTag(observe:PROVIDER_NAME, "Ballerina");
        span.addTag(observe:AGENT_ID, self.uniqueId);
        span.addTag(observe:AGENT_NAME, self.systemPrompt.role);
        span.addTag(observe:CONVERSATION_ID, sessionId);
        span.addTag(observe:OUTPUT_TYPE, "text");
        span.addTag(observe:INPUT_MESSAGES, query);
        span.addTag(observe:SYSTEM_INSTRUCTIONS, getFomatedSystemPrompt(self.systemPrompt));
        ExecutionTrace result = self.functionCallAgent.run(query, getFomatedSystemPrompt(self.systemPrompt),
            self.maxIter, self.verbose, sessionId, context);
        string? answer = result.answer;
        if answer is string {
            span.addTag(observe:OUTPUT_MESSAGES, answer);
            span.close();
            return answer;
        }
        Error err = constructError(result.steps, self.maxIter);
        span.close(err);
        return err;
    }
}

isolated function constructError((ExecutionResult|ExecutionError|Error)[] steps, int maxIter) returns Error {
    if (steps.length() == maxIter) {
        return error MaxIterationExceededError("Maximum iteration limit exceeded while processing the query.",
            steps = steps);
    }
    // Validates whether the execution steps contain only one memory error.
    // If there is exactly one memory error, it is returned; otherwise, null is returned.
    if steps.length() == 1 {
        ExecutionResult|ExecutionError|Error step = steps[0];
        if step is ExecutionError && step.'error is MemoryError {
            return <MemoryError>step.'error;
        }
    }
    return error Error("Unable to obtain valid answer from the agent", steps = steps);
}

isolated function getFomatedSystemPrompt(SystemPrompt systemPrompt) returns string {
    return string `# Role  
${systemPrompt.role}  

# Instructions  
${systemPrompt.instructions}`;
}
