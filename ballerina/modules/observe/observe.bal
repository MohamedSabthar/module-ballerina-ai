import ballerina/log;
import ballerina/observe;

final isolated map<AiSpan> aiSpans = {};

enum Status {
    OK = "Ok",
    ERROR = "Error"
}

enum GenAiTagNames {
    OPERATION_NAME = "gen_ai.operation.name",
    PROVIDER_NAME = "gen_ai.provider.name",
    CONVERSATION_ID = "gen_ai.conversation.id",
    OUTPUT_TYPE = "gen_ai.output.type",
    REQUEST_MODEL = "gen_ai.request.model",
    RESPONSE_MODEL = "gen_ai.response.model",
    STOP_SEQUENCE = "gen_ai.request.stop_sequences",
    TEMPERATURE = "gen_ai.request.temperature",
    FINISH_REASON = "gen_ai.response.finish_reasons",
    RESPONSE_ID = "gen_ai.response.id",
    INPUT_TOKENS = "gen_ai.usage.input_tokens",
    OUTPUT_TOKENS = "gen_ai.usage.output_tokens",
    INPUT_MESSAGES = "gen_ai.input.messages",
    OUTPUT_MESSAGES = "gen_ai.output.messages",
    SYSTEM_INSTRUCTIONS = "gen_ai.system_instructions",
    AGENT_ID = "gen_ai.agent.id",
    AGENT_NAME = "gen_ai.agent.name",
    AGENT_TOOLS = "gen_ai.agent.tools",
    TOOL_CALL_ID = "gen_ai.tool.call.id",
    TOOL_NAME = "gen_ai.tool.name",
    TOOL_DESCRIPTION = "gen_ai.tool.description",
    TOOL_TYPE = "gen_ai.tool.type",

    // Added by us not mandated by spec
    TOOL_ARGUMENTS = "gen_ai.tool.arguments",
    TOOL_OUTPUT = "gen_ai.tool.output",
    INPUT_CONTENT = "gen_ai.input.content",
    INPUT_TOOLS = "gen_ai.input.tools"
}

enum Operations {
    CHAT = "chat",
    INVOKE_AGENT = "invoke_agent",
    CREATE_AGENT = "create_agent",
    EMBEDDINGS = "embeddings",
    EXECUTE_TOOL = "execute_tool",
    GENERATE_CONTENT = "generate_content"
}

public enum OutputType {
    TEXT = "text",
    JSON = "json"
}

public enum ToolType {
    FUNCTION = "function",
    EXTENTION = "extension"
}

# Represents an AI tracing span that allows adding tags and closing the span.
public type AiSpan distinct isolated object {

    # Adds a tag to the span.
    #
    # + key - The name of the tag
    # + value - The value associated with the tag
    isolated function addTag(GenAiTagNames key, anydata value);

    # Closes the span and records its final status.
    #
    # + 'err - Optional error that indicates if the operation failed
    public isolated function close(error? err = ());
};

# Retrieves the current active AI span, if any.
#
# Returns the `AiSpan` associated with the current execution context.
# If tracing is not enabled or no span exists for the current context, returns `()`.
#
# + return - - The current active AI span, or `()` if none is active
public isolated function getCurrentAiSpan() returns AiSpan? {
    if !observe:isTracingEnabled() {
        return;
    }
    lock {
        return aiSpans[getUniqueIdOfCurrentSpan()];
    }
}

# Implementation of the `AiSpan` interface used to trace AI-related operations.
isolated class BaseSpanImp {
    *AiSpan;
    private final int|error spanId;

    # Initializes a new AI span with the given name.
    # Creates a new tracing span for the specified operation name.  
    # If tracing is disabled or span creation fails, the span is not recorded.
    #
    # + name - The name of the span to be created
    isolated function init(string name) {
        if !observe:isTracingEnabled() {
            return;
        }

        int|error spanId = observe:startSpan(name);
        self.spanId = spanId;
        if spanId is error {
            log:printError("failed to start span", 'error = spanId);
            return;
        }
        addOtherTags("span.type", "ai", spanId);
    }

    # Adds a tag to the current AI span.
    # Records a key-value pair as a tag for the current tracing span.
    #
    # + key - The tag name
    # + value - The tag value; can be anydata type
    isolated function addTag(GenAiTagNames key, anydata value) {
        if !observe:isTracingEnabled() {
            return;
        }

        int|error spanId = self.spanId;
        if spanId is error {
            log:printError("attempted to add a tag to an invalid span", 'error = spanId);
            return;
        }

        error? result = observe:addTagToSpan(key, value is string ? value : value.toJsonString(), spanId);
        if result is error {
            log:printError(string `failed to add tag '${key}' to span with ID '${spanId}'`, 'error = result);
        }
    }

    # Closes the AI span and marks it with a success or error status.
    # Removes the span from the current context and records its completion.
    # If an error is provided, the span is marked as failed; otherwise, it is marked as successful.
    #
    # + 'error - Optional error indicating the failure cause
    public isolated function close(error? 'error = ()) {
        if !observe:isTracingEnabled() {
            return;
        }

        int|error spanId = self.spanId;
        if spanId is error {
            log:printError("attempted to close an invalid span", 'error = spanId);
            return;
        }

        if 'error is () {
            addOtherTags("otel.status_code", OK, spanId);
            finishSpan(spanId);
            return;
        }

        addOtherTags("error.type", 'error.toString(), spanId);
        addOtherTags("otel.status_code", ERROR, spanId);
        removeCurrentAiSpan();
        finishSpan(spanId);
    }
}

isolated function getUniqueIdOfCurrentSpan() returns string {
    map<string> ctx = observe:getSpanContext();
    return string `${ctx.get("spanId")}:${ctx.get("traceId")}`;
}

isolated function removeCurrentAiSpan() {
    if !observe:isTracingEnabled() {
        return;
    }
    lock {
        string uniqueSpanId = getUniqueIdOfCurrentSpan();
        if aiSpans.hasKey(uniqueSpanId) {
            _ = aiSpans.remove(uniqueSpanId);
        }
    }
}

isolated function finishSpan(int spanId) {
    if !observe:isTracingEnabled() {
        return;
    }
    error? result = observe:finishSpan(spanId);
    if result is error {
        log:printError(string `failed to close span with ID '${spanId}'`, 'error = result);
    }
}

isolated function addOtherTags(string key, anydata value, int spanId) {
    if !observe:isTracingEnabled() {
        return;
    }
    error? result = observe:addTagToSpan(key, value is string ? value : value.toJsonString(), spanId);
    if result is error {
        log:printError(string `failed to add tag '${key}' to span with ID '${spanId}'`, 'error = result);
    }
}

isolated function recordAiSpan(AiSpan span) {
    lock {
        aiSpans[getUniqueIdOfCurrentSpan()] = span;
    }
}
