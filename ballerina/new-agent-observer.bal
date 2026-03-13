import ballerina/log;

// --- 1. Define the events the agent can emit ---
type AgentEvent AgentStarted|AgentCompleted|AgentFailed;

type AgentStarted readonly & record {
    string executionId;
    string query;
    string sessionId;
};

type AgentCompleted readonly & record {
    string executionId;
    ExecutionTrace trace;
    string answer;
};

type AgentFailed readonly & record {
    string executionId;
    Error cause;
};

// --- 2. Define the observer contract ---
type Observer isolated object {
    isolated function onEvent(AgentEvent event) returns error?;
};

// --- 4. EventBus holds the observers and dispatches ---
isolated class EventBus {
    private Observer[] observers = [];

    isolated function subscribe(Observer observer) {
        lock {
            self.observers.push(observer);
        }
    }

    isolated function emit(AgentEvent event) {
        lock {
            foreach Observer o in self.observers {
                error? err = o.onEvent(event); // each observer reacts independently
                if err is error {
                    log:printError("Failed to process event: ", err);
                }
            }
        }
    }
}

isolated class LoggingObserver {
    *Observer;

    isolated function onEvent(AgentEvent event) {
        if event is AgentStarted {
            self.logAgentExecutionStarted(event);
        } else if event is AgentCompleted {
            self.logAgentExecutionCompleted(event);
        }
    }

    private isolated function logAgentExecutionStarted(AgentStarted event) {
        log:printDebug("Agent execution started", sessionId = event.sessionId, executionId = event.executionId, query = event.query);
    }

    private isolated function logAgentExecutionCompleted(AgentCompleted event) {
        log:printDebug("Agent execution completed successfully",
                executionId = event.executionId,
                steps = event.trace.executionSteps.toString(),
                answer = event.answer
        );
    }
}
