public isolated function createCreateAgentSpan(string agentName) returns CreateAgentSpan {
    CreateAgentSpan span = new (agentName);
    recordAiSpan(span);
    return span;
}

public isolated function createInvokeAgentSpan(string agentName) returns InvokeAgentSpan {
    InvokeAgentSpan span = new (agentName);
    recordAiSpan(span);
    return span;
}

public isolated function createExecuteToolSpan(string toolName) returns ExecuteToolSpan {
    ExecuteToolSpan span = new (toolName);
    recordAiSpan(span);
    return span;
}

public isolated function createEmbeddingSpan(string embeddingModel) returns EmbeddingSpan {
    EmbeddingSpan span = new (embeddingModel);
    recordAiSpan(span);
    return span;
}

public isolated function createChatSpan(string llmModel) returns ChatSpan {
    ChatSpan span = new (llmModel);
    recordAiSpan(span);
    return span;
}
