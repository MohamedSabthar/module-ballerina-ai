// import ballerina/observe;
// import ballerina/log;

// # Implementation of the `AiSpan` interface used to trace AI-related operations.
// public isolated class CreateAgentSpan {
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

//         int|error spanId = observe:startSpan(string `create_agent ${name}`);
//         self.spanId = spanId;
//         if spanId is error {
//             log:printError("failed to start span", 'error = spanId);
//             return;
//         }

//         lock {
//             aiSpans[getUniqueIdOfCurrentSpan()] = self;
//         }
//         self.addTag("span.type", "ai");
//         self.addTag(OPERATION_NAME, "create_agent");
//         self.addTag(PROVIDER_NAME,, "Ballerina");
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
//         // self.addTag("gen_ai.agent.id", uniqueId);
//         // self.addTag("gen_ai.system_instructions", systemInstructions);
//         // self.addTag("gen_ai.agent.tools", toolsInfo); // Added by us not mandated by spec
//         // self.addTag("gen_ai.agent.name", self.systemPrompt.role);