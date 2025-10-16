// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

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

public isolated function createCreateKnowledgeBaseSpan(string kbName) returns CreateKnowledgeBaseSpan {
    CreateKnowledgeBaseSpan span = new (kbName);
    recordAiSpan(span);
    return span;
}

public isolated function createKnowledgeBaseIngestSpan(string kbName) returns KnowledgeBaseIngestSpan {
    KnowledgeBaseIngestSpan span = new (kbName);
    recordAiSpan(span);
    return span;
}

public isolated function createKnowledgeBaseRetrieveSpan(string kbName) returns KnowledgeBaseRetrieveSpan {
    KnowledgeBaseRetrieveSpan span = new (kbName);
    recordAiSpan(span);
    return span;
}

