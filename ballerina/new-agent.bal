import ai.observe;

import ballerina/jballerina.java;
import ballerina/time;
import ballerina/uuid;

# Represents an AI agent capable of executing tasks using a language model and a set of registered tools.
#
# An `Agent` coordinates interactions between the language model, conversation memory, and tool
# execution. It maintains the system instructions, manages conversation history, and orchestrates
# tool usage during execution.
#
# The agent supports both stateful and stateless execution depending on the configured memory
# implementation.
public isolated distinct class Agent {
    private final string agentId = uuid:createRandomUuid();
    private final string instructions;
    private final string role;
    private final readonly & ToolSchema[] toolSchemas;
    private final AgentExecutor executor;
    private final ConversationManager conversationManager;
    private final EventBus eventBus = new;
    final ToolRegistry toolRegistry;

    # Initializes the agent with the provided configuration.
    #
    # + config - Configuration used to initialize the agent
    # + return - `nil` on success, otherwise an `ai:Error`
    public isolated function init(@display {label: "Agent Configuration"} *AgentConfiguration config) returns Error? {
        string instructions = getFormattedSystemPrompt(config.systemPrompt);
        observe:CreateAgentSpan span = observe:createCreateAgentSpan(config.systemPrompt.role);
        span.addId(self.agentId);
        span.addSystemInstructions(instructions);

        INFER_TOOL_COUNT|int maxIter = config.maxIter;
        int resolvedMaxIter = maxIter is INFER_TOOL_COUNT ? config.tools.length() + 1 : maxIter;
        self.instructions = instructions;
        self.role = config.systemPrompt.role;
        Memory? memory = config.hasKey("memory") ? config?.memory : check new ShortTermMemory();
        do {
            self.toolRegistry = check new (...config.tools);
            Memory resolvedMemory = memory ?: check new ShortTermMemory();
            boolean stateless = memory is ();
            self.toolSchemas = self.toolRegistry.getToolSchema().cloneReadOnly();

            ToolExecutionHandler toolHandler = new (self.toolRegistry);
            self.executor = new (config.model, self.toolRegistry, toolHandler,
                config.toolLoadingStrategy, resolvedMaxIter, config.verbose
            );
            self.conversationManager = new (resolvedMemory, stateless);

            span.addTools(self.toolRegistry.getToolsInfo());
            span.close();
        } on fail Error err {
            span.close(err);
            return err;
        }
    }

    # Executes the agent for a given user query.
    #
    # **Note:** Calls to this function using the same session ID must be invoked
    # sequentially by the caller. Concurrent invocations with the same session ID are not
    # supported and may lead to inconsistent conversation state.
    #
    # + query - The natural language input provided to the agent
    # + sessionId - Identifier used to associate the request with a conversation session
    # + context - Additional contextual data available during tool execution
    # + td - Type descriptor specifying the expected return type (`string` or `ai:Trace`)
    # + return - The agent's response or an `ai:Error`
    public isolated function run(@display {label: "Query"} string query,
            @display {label: "Session ID"} string sessionId = DEFAULT_SESSION_ID,
            Context context = new, typedesc<string|Trace> td = <>) returns td|Error = @java:Method {
        'class: "io.ballerina.stdlib.ai.Agent"
    } external;

    private isolated function runInternal(string query, string sessionId, Context context, boolean withTrace)
    returns string|Trace|Error {
        time:Utc startTime = time:utcNow();
        string executionId = uuid:createRandomUuid();
        AgentStarted startEvent = {sessionId, executionId, query};
        self.eventBus.emit(startEvent);

        observe:InvokeAgentSpan span = observe:createInvokeAgentSpan(self.role);
        span.addId(self.agentId);
        span.addSessionId(sessionId);
        span.addInput(query);
        span.addSystemInstruction(self.instructions);

        var [history, systemMessage, userMessage] = self.conversationManager.initializeHistory(sessionId, self.instructions, query, executionId);
        readonly & ExecutionTrace executionTrace = self.executor.execute(query, sessionId, context, executionId, history);
        ExecutionProgress progress = {
            instruction: self.instructions,
            query,
            context,
            executionId,
            history,
            executionSteps: executionTrace.executionSteps
        };
        self.conversationManager.finalizeMemory(sessionId, progress,
                systemMessage, userMessage, getAssistantMessage(executionTrace));

        ChatUserMessage userMsg = {role: USER, content: query};
        FunctionCall[]? toolCalls = executionTrace.toolCalls.length() == 0 ? () : executionTrace.toolCalls;
        do {
            string answer = check getAnswer(executionTrace, self.executor.getMaxIter());
            AgentCompleted completeEvent = {executionId, answer, trace: executionTrace};
            self.eventBus.emit(completeEvent);
            span.addOutput(observe:TEXT, answer);
            span.close();
            return withTrace ? buildTrace(executionId, userMsg, executionTrace.iterations,
                        self.toolSchemas, startTime, answer, toolCalls) : answer;
        } on fail Error err {
            logAgentExecutionFailed(executionId, executionTrace.steps.toString(), err);
            span.close(err);
            return !withTrace ? err : buildTrace(executionId, userMsg, executionTrace.iterations, self.toolSchemas,
                        startTime, err, toolCalls);
        }
    }
}

# Returns the tools registered with the agent.
#
# + agent - The agent instance
# + return - An array containing the tools registered with the agent
public isolated function getTools(Agent agent) returns Tool[] => agent.toolRegistry.tools.toArray();

isolated function getAssistantMessage(ExecutionTrace trace) returns ChatAssistantMessage? {
    string? answer = trace.answer;
    return answer is string ? {role: ASSISTANT, content: answer} : ();
}
