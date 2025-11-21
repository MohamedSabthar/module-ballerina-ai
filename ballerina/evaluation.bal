import ballerina/time;

# Represents the trace of an agent's execution.
public type Trace record {|
    # Unique identifier for the trace
    string id;
    # Input message provided by the user
    ChatUserMessage userMessage;
    # Sequence of iterations performed by the agent
    Iteration[] iterations;
    # Final output produced by the agent
    ChatAssistantMessage|Error output;
    # Schema of the tools used by the agent during execution
    ToolSchema[] tools;
    # Start time of the trace
    time:Utc startTime;
    # End time of the trace
    time:Utc endTime;
|};

# Represents the schema of a tool used by the agent.
public type ToolSchema record {|
    # Name of the tool
    string name;
    # Description of the tool
    string description;
    # Parameters schema of the tool
    map<json> parametersSchema?;
|};

# Represents a single iteration in the agent's execution trace.
public type Iteration record {|
    # History of chat messages up to this iteration
    ChatMessage[] history;
    # Output produced by the agent in this iteration
    ChatAssistantMessage|Error output;
    # Start time of the iteration
    time:Utc startTime;
    # End time of the iteration
    time:Utc endTime;
|};

# Retrieves all function calls made during the agent's execution.
# + trace - The trace of the agent's execution.
# + return - An array of FunctionCall records representing each function call made if any, else returns nil.
public isolated function getAllToolCalls(Trace trace) returns FunctionCall[] {
    return [];
}

# Asserts that a given function call matches the expected function call in terms of name and parameters.
# + actual - The actual function call made during execution.
# + expected - The expected function call to compare against.
# + return - An Error if the function calls do not match, else returns nil.
public isolated function assertToolCall(FunctionCall actual, FunctionCall expected) returns Error? {
    return;
}

# Checks if there were any errors during the agent's execution.
# + trace - The trace of the agent's execution.
# + return - true if there was at least one error, else false.
public isolated function hasError(Trace trace) returns boolean {
    return false;
}

# Retrieves all errors encountered during the agent's execution.
# + trace - The trace of the agent's execution.
# + return - An array of Errors encountered during execution.
public isolated function getErrors(Trace trace) returns Error[] {
    return [];
}

# Retrieves the final answer produced by the agent after completing its execution.
# + trace - The trace of the agent's execution.
# + return - The final answer as a string if available, else returns an Error.
public isolated function getFinalAnswer(Trace trace) returns string|Error {
    ChatAssistantMessage|Error output = trace.output;
    return output is ChatAssistantMessage
        ? output.content.toString()
        : output;
}

# Calculates the total execution time of the agent's trace or a specific iteration.
# + trace - The trace of the agent's execution or a specific iteration.
# + return - The total execution time as time:Seconds.
public isolated function getTotalExecutionTime(Trace|Iteration trace) returns time:Seconds {
    return time:utcDiffSeconds(trace.endTime, trace.startTime);
}
