// import ballerina/log;
// import ballerina/observe;

// final isolated map<AiSpan> aiSpans = {};

// enum Status {
//     OK = "Ok",
//     ERROR = "Error"
// }

// # Represents an AI tracing span that allows adding tags and closing the span.
// public type AiSpan isolated object {

//     # Adds a tag to the span.
//     #
//     # + key - The name of the tag
//     # + value - The value associated with the tag
//     public isolated function addTag(string key, anydata value);

//     # Closes the span and records its final status.
//     #
//     # + 'error - Optional error that indicates if the operation failed
//     public isolated function close(error? 'error = ());
// };

// # Retrieves the current active AI span, if any.
// #
// # Returns the `AiSpan` associated with the current execution context.
// # If tracing is not enabled or no span exists for the current context, returns `()`.
// #
// # + return - - The current active AI span, or `()` if none is active
// public isolated function getCurrentAiSpan() returns AiSpan? {
//     if !observe:isTracingEnabled() {
//         return;
//     }
//     lock {
//         return aiSpans[getUniqueIdOfCurrentSpan()];
//     }
// }

// # Implementation of the `AiSpan` interface used to trace AI-related operations.
// public isolated class SpanImp {
//     *AiSpan;
//     private final int|error spanId;

//     # Initializes a new AI span with the given name.
//     # Creates a new tracing span for the specified operation name.  
//     # If tracing is disabled or span creation fails, the span is not recorded.
//     #
//     # + name - The name of the span to be created
//     public isolated function init(string name) {
//         if !observe:isTracingEnabled() {
//             return;
//         }

//         int|error spanId = observe:startSpan(name);
//         self.spanId = spanId;
//         if spanId is error {
//             log:printError("failed to start span", 'error = spanId);
//             return;
//         }

//         lock {
//             aiSpans[getUniqueIdOfCurrentSpan()] = self;
//         }
//         self.addTag("span.type", "ai");
//     }

//     # Adds a tag to the current AI span.
//     # Records a key-value pair as a tag for the current tracing span.
//     #
//     # + key - The tag name
//     # + value - The tag value; can be anydata type
//     public isolated function addTag(string key, anydata value) {
//         if !observe:isTracingEnabled() {
//             return;
//         }

//         int|error spanId = self.spanId;
//         if spanId is error {
//             log:printError("attempted to add a tag to an invalid span", 'error = spanId);
//             return;
//         }

//         error? result = observe:addTagToSpan(key, value is string ? value : value.toJsonString(), spanId);
//         if result is error {
//             log:printError(string `failed to add tag '${key}' to span with ID '${spanId}'`, 'error = result);
//         }
//     }

//     # Closes the AI span and marks it with a success or error status.
//     # Removes the span from the current context and records its completion.
//     # If an error is provided, the span is marked as failed; otherwise, it is marked as successful.
//     #
//     # + 'error - Optional error indicating the failure cause
//     public isolated function close(error? 'error = ()) {
//         if !observe:isTracingEnabled() {
//             return;
//         }
//         removeCurrentAiSpan();

//         int|error spanId = self.spanId;
//         if spanId is error {
//             log:printError("attempted to close an invalid span", 'error = spanId);
//             return;
//         }

//         if 'error is () {
//             self.addTag("otel.status_code", OK);
//             finishSpan(spanId);
//             return;
//         }

//         self.addTag("error.type", 'error.toString());
//         self.addTag("otel.status_code", ERROR);
//         finishSpan(spanId);
//     }
// }

// isolated function getUniqueIdOfCurrentSpan() returns string {
//     map<string> ctx = observe:getSpanContext();
//     return string `${ctx.get("spanId")}:${ctx.get("traceId")}`;
// }

// isolated function removeCurrentAiSpan() {
//     if !observe:isTracingEnabled() {
//         return;
//     }
//     lock {
//         string uniqueSpanId = getUniqueIdOfCurrentSpan();
//         if aiSpans.hasKey(uniqueSpanId) {
//             _ = aiSpans.remove(uniqueSpanId);
//         }
//     }
// }

// isolated function finishSpan(int spanId) {
//     if !observe:isTracingEnabled() {
//         return;
//     }
//     error? result = observe:finishSpan(spanId);
//     if result is error {
//         log:printError(string `failed to close span with ID '${spanId}'`, 'error = result);
//     }
// }
