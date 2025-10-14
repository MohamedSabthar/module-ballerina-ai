import ballerina/log;
import ballerina/observe;

public enum Status {
    OK = "Ok",
    ERROR = "Error"
}

public type Span isolated object {
    public isolated function addTag(string key, anydata|error value);
    public isolated function close(Status status);
};

public isolated class SpanImp {
    *Span;
    private final int|error spanId;

    public isolated function init(string name) {
        int|error spanId = observe:startSpan(name);

        if spanId is error {
            log:printError("failed to start span", 'error = spanId);
        }
        self.spanId = spanId;
        self.addTag("span.type", "ai");
    }

    public isolated function addTag(string key, anydata|error value) {
        int|error spanId = self.spanId;
        if spanId is error {
            log:printError("attempted to add a tag to an invalid span", 'error = spanId);
            return;
        }
        error? result = observe:addTagToSpan(key, value is error ? value.toString() : value is string ? value : value.toJsonString(), spanId);
        if result is error {
            log:printError(string `faliled to add tag '${key}' to span with ID '${spanId}'`, 'error = result);
        }
    }

    public isolated function close(Status status) {
        int|error spanId = self.spanId;
        if spanId is error {
            log:printError("attempted to close an invalid span", 'error = spanId);
            return;
        }
        self.addTag("otel.status_code", status);
        error? result = observe:finishSpan(spanId);
        if result is error {
            log:printError(string `failed to close span with ID '${spanId}'`, 'error = result);
        }
    }
}