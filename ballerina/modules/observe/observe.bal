import ballerina/log;
import ballerina/observe;

final isolated map<AiSpan> aiSpans = {};

enum Status {
    OK = "Ok",
    ERROR = "Error"
}

public type AiSpan isolated object {
    public isolated function addTag(string key, anydata value);
    public isolated function close(error? 'error = ());
};

# Description.
public isolated class SpanImp {
    *AiSpan;
    private final int|error spanId;

    public isolated function init(string name) {
        if !observe:isTracingEnabled() {
            return;
        }
        int|error spanId = observe:startSpan(name);
        lock {
            aiSpans[getUniqueSpanId()] = self;
        }

        if spanId is error {
            log:printError("failed to start span", 'error = spanId);
        }
        self.spanId = spanId;
        self.addTag("span.type", "ai");
    }

    public isolated function addTag(string key, anydata value) {
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

    public isolated function close(error? 'error = ()) {
        if !observe:isTracingEnabled() {
            return;
        }
        lock {
            _ = aiSpans.remove(getUniqueSpanId());
        }
        if 'error is () {
            self.addTag("otel.status_code", OK);
            return;
        }
        int|error spanId = self.spanId;
        if spanId is error {
            log:printError("attempted to close an invalid span", 'error = spanId);
            return;
        }
        self.addTag("error.type", 'error.toString());
        self.addTag("otel.status_code", ERROR);
        error? result = observe:finishSpan(spanId);
        if result is error {
            log:printError(string `failed to close span with ID '${spanId}'`, 'error = result);
        }
    }
}

public isolated function getCurrentAiSpan() returns AiSpan? {
    if !observe:isTracingEnabled() {
        return;
    }
    lock {
        return aiSpans.get(getUniqueSpanId());
    }
}

isolated function getUniqueSpanId() returns string {
    map<string> ctx = observe:getSpanContext();
    return ctx.get("spanId") + ctx.get("traceId");
}
