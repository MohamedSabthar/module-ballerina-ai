// https: //opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/#create-agent-span
public isolated distinct class CreateAgentSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string agentName) {
        self.baseSpan = new (string `${CREATE_AGENT} ${agentName}`);
        self.addTag(OPERATION_NAME, CREATE_AGENT);
        self.addTag(PROVIDER_NAME, "Ballerina");
        self.addTag(AGENT_NAME, agentName);
    }

    public isolated function addId(string agentId) {
        self.addTag(AGENT_ID, agentId);
    }

    public isolated function addSystemInstructions(string instructions) {
        self.addTag(SYSTEM_INSTRUCTIONS, instructions);
    }

    // Not mandated by spec
    public isolated function addTools(json tools) {
        self.addTag(AGENT_TOOLS, tools);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    public isolated function close(error? 'error = ()) {
        self.baseSpan.close('error);
    }
}

// https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/#invoke-agent-span
public isolated distinct class InvokeAgentSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string agentName) {
        self.baseSpan = new (string `${INVOKE_AGENT} ${agentName}`);
        self.addTag(OPERATION_NAME, INVOKE_AGENT);
        self.addTag(PROVIDER_NAME, "Ballerina");
        self.addTag(AGENT_NAME, agentName);
    }

    public isolated function addId(string agentId) {
        self.addTag(AGENT_ID, agentId);
    }

    public isolated function addSystemInstructions(string instructions) {
        self.addTag(SYSTEM_INSTRUCTIONS, instructions);
    }

    public isolated function addSessionId(string sessionId) {
        self.addTag(CONVERSATION_ID, sessionId);
    }

    public isolated function addInput(string query) {
        self.addTag(INPUT_MESSAGES, query);
    }

    public isolated function addOutput(OutputType outputType, json output) {
        self.addTag(OUTPUT_TYPE, outputType);
        self.addTag(OUTPUT_MESSAGES, output);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    public isolated function close(error? 'error = ()) {
        self.baseSpan.close('error);
    }
}

// https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/#execute-tool-span
public isolated distinct class ExecuteToolSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string toolName) {
        self.baseSpan = new (string `${EXECUTE_TOOL} ${toolName}`);
        self.addTag(OPERATION_NAME, EXECUTE_TOOL);
        self.addTag(TOOL_NAME, toolName);
    }

    public isolated function addId(string|int toolCallId) {
        self.addTag(TOOL_CALL_ID, toolCallId);
    }

    public isolated function addDescription(string description) {
        self.addTag(TOOL_DESCRIPTION, description);
    }

    public isolated function addType(ToolType toolType) {
        self.addTag(TOOL_TYPE, toolType);
    }

    // Not mandated by spec
    public isolated function addArguments(json arguments) {
        self.addTag(TOOL_ARGUMENTS, arguments);
    }

    // Not mandated by spec
    public isolated function addOutput(anydata output) {
        self.addTag(TOOL_OUTPUT, output);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    public isolated function close(error? 'error = ()) {
        self.baseSpan.close('error);
    }
}

// TODO: agent iteration span

