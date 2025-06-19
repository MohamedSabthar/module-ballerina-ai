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

import ai.wso2;

import ballerina/uuid;

# Represents a dense vector with floating-point values.
public type Vector float[];

# Represents a sparse vector storing only non-zero values with their corresponding indices.
#
# + indices - Array of indices where non-zero values are located 
# + values - Array of non-zero floating-point values corresponding to the indices
public type SparseVector record {|
    int[] indices;
    Vector values;
|};

# Represents a hybrid embedding containing both dense and sparse vector representations.
#
# + dense - Dense vector representation of the embedding
# + sparse - Sparse vector representation of the embedding
public type HybridVector record {|
    Vector dense;
    SparseVector sparse;
|};

# Union type representing all possible embedding vector formats.
public type Embedding Vector|SparseVector|HybridVector;

# Enumeration of supported operators for metadata filtering.
# These operators define how metadata values should be compared during vector searches.
public enum MetadataFilterOperator {
    EQUALS = "==",
    NOT_EQUALS = "!=",
    GREATER_THAN = ">",
    LESS_THAN = "<",
    GREATER_THAN_OR_EQUAL = ">=",
    LESS_THAN_OR_EQUAL = "<=",
    IN = "in",
    NOT_IN = "nin"
}

# Enumeration of logical conditions for combining multiple metadata filters.
# Defines how multiple filter conditions should be combined in vector searches.
public enum MetadataFilterCondition {
    AND = "and",
    OR = "or"
}

# Metadata filter for vector search operations.
# Defines conditions to filter vectors based on their associated metadata values.
#
# + key - The metadata field name to filter on
# + operator - The comparison operator to use (optional, defaults to EQUALS)
# + value - The value to compare against
public type MetadataFilter record {|
    string key;
    MetadataFilterOperator operator?;
    anydata value;
|};

# Container for multiple metadata filters with logical combination.
# Allows complex filtering by combining multiple conditions with AND/OR logic.
#
# + filter - Array of individual metadata filters to apply
# + condition - Logical operator to combine filters (optional, defaults to AND)
public type MetadataFilters record {|
    MetadataFilter[] filter?;
    MetadataFilterCondition condition?;
|};

# Represents a complete vector store query with embedding and optional filters.
# Combines the query vector with metadata filters for precise search operations.
#
# + embeddingVector - The vector to search for similar matches
# + filters - Optional metadata filters to narrow down search results
public type VectorStoreQuery record {|
    Embedding embeddingVector;
    MetadataFilters filters?;
|};

# Represents a document with content and optional metadata.
#
# + content - The textual content of the document 
# + metadata - Optional key-value pairs containing additional information about the document
public type Document record {|
    string content;
    map<anydata> metadata?;
|};

# Represents a vector entry combining an embedding with its source document.
#
# + id - Unique identifier for the vector entry
# + embedding - The vector representation of the document content  
# + document - The original document associated with this embedding
public type VectorEntry record {|
    string id?;
    Embedding embedding;
    Document document;
|};

# Represents a vector match result with similarity score.
#
# + score - Similarity score indicating how closely the vector matches the query 
public type VectorMatch record {|
    *VectorEntry;
    float score;
|};

# Represents a document match result with similarity score.
#
# + document - The matched document  
# + score - Similarity score indicating document relevance to the query
public type DocumentMatch record {|
    Document document;
    float score;
|};

# Represents prompt templates for RAG (Retrieval-Augmented Generation) operations.
# Prompts structure how context documents and user queries are formatted and presented
# to language models for generating contextually relevant responses.
#
# + systemPrompt - System-level instructions that define the model's behavior, role, and response format
# + userPrompt - The user's question or query that needs to be answered using the provided context
public type Prompt record {|
    string systemPrompt?;
    string userPrompt?;
|};

# Enumeration of vector store query modes.
# Defines different search strategies for retrieving relevant documents
# based on the type of embeddings and search algorithms to be used.
public enum VectorStoreQueryMode {
    DENSE,
    SPARSE,
    HYBRID
};

# Configuration record for WSO2 model provider settings.
# Contains the necessary connection parameters for WSO2 AI services.
#
# + serviceUrl - The URL endpoint for the WSO2 AI service
# + accessToken - Authentication token for accessing WSO2 AI services
public type Wso2ModelProviderConfig record {|
    string serviceUrl;
    string accessToken;
|};

# Interface for document chunking strategies.
# Defines how large documents should be split into smaller, manageable pieces
# for embedding and vector storage operations.
public type ChunkStratery isolated object {
    # Splits content into smaller document chunks.
    #
    # + content - The input text content to be chunked
    # + return - Array of document chunks or an error if chunking fails
    public isolated function chunk(string content) returns Document[]|Error;
};

# Simple document splitter that divides content by line breaks.
# Each line becomes a separate document chunk, useful for structured text data.
public isolated class DocumentByLineSplitter {
    *ChunkStratery;

    # Splits content into documents based on line breaks.
    # Empty lines are filtered out from the resulting document array.
    #
    # + content - The input text content to be split by lines
    # + return - Array of documents, one per non-empty line, or an error if processing fails
    public isolated function chunk(string content) returns Document[]|Error {
        return re `\n`.split(content).'map(line => {content: line});
    }
}

# Configurable instance of WSO2 model provider configuration.
# This should be set in the application's configuration file (Config.toml).
configurable Wso2ModelProviderConfig? wso2ModelProviderConfig = ();

# Interface for vector storage and retrieval operations.
# Vector stores provide persistence and search capabilities for embeddings.
public type VectorStore isolated object {
    # Adds vector entries to the store.
    #
    # + entries - Array of vector entries to be stored
    # + return - An error if the operation fails, otherwise nil
    public isolated function add(VectorEntry[] entries) returns Error?;

    # Searches for similar vectors in the store.
    #
    # + queryEmbedding - The query embedding to search for
    # + return - Array of matching vectors with similarity scores or an error if search fails
    public isolated function query(VectorStoreQuery queryEmbedding) returns VectorMatch[]|Error;

    # Deletes a vector entry from the store.
    #
    # + referenceId - The reference ID of the vector entry to delete
    # + return - An error if the operation fails, otherwise nil
    public isolated function delete(string referenceId) returns Error?;
};

# Interface for embedding providers.
# Embedding providers convert text into vector representations for similarity search.
public type EmbeddingProvider isolated client object {
    # Converts text into an embedding vector.
    #
    # + document - The input text to be embedded
    # + return - The embedding vector representation or an error if embedding fails
    isolated remote function embed(string document) returns Embedding|Error;
};

# Document retriever for finding relevant documents based on query similarity.
# Retriever combines embedding generation and vector search to return matching documents.
public isolated class Retriever {
    private final VectorStore vectorStore;
    private final EmbeddingProvider embeddingModel;

    # Initializes a new retriever instance.
    # Sets up the retriever with the necessary components for
    # query embedding and vector search operations.
    #
    # + vectorStore - The vector store to search in
    # + embeddingProvider - The embedding provider to use for query embedding
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel) {
        self.vectorStore = vectorStore;
        self.embeddingModel = embeddingModel;
    }

    # Retrieves relevant documents for a given query.
    # Embeds the query text and searches for similar vectors,
    # returning matching documents with similarity scores.
    #
    # + query - The text query to search for
    # + filters - Optional metadata filters to apply during retrieval
    # + return - Array of matching documents with scores or an error if retrieval fails
    public isolated function retrieve(string query, MetadataFilters? filters = ()) returns DocumentMatch[]|Error {
        Embedding queryEmbedding = check self.embeddingModel->embed(query);
        VectorStoreQuery vectorStoreQuery = {
            embeddingVector: queryEmbedding,
            filters: filters
        };
        VectorMatch[] matches = check self.vectorStore.query(vectorStoreQuery);
        return from VectorMatch 'match in matches
            select {document: 'match.document, score: 'match.score};
    }
}

# Vector knowledge base for managing document indexing and retrieval operations.
# The vector knowledge base handles the process of converting documents to embeddings 
# and storing them for retrieval.
public isolated class VectorKnowledgeBase {
    private final VectorStore vectorStore;
    private final EmbeddingProvider embeddingModel;
    private final Retriever retriever;

    # Initializes a new vector knowledge base.
    # Creates a vector knowledge base with the specified storage and embedding capabilities.
    # The knowledge base manages the entire lifecycle from document ingestion to retrieval.
    #
    # + vectorStore - The vector store for persistence
    # + embeddingProvider - The embedding provider for vectorization
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel) {
        self.vectorStore = vectorStore;
        self.embeddingModel = embeddingModel;
        self.retriever = new Retriever(vectorStore, embeddingModel);
    }

    # Indexes a collection of documents.
    # Converts documents to embeddings and stores them in the vector store.
    # This operation makes the documents searchable through the retriever.
    #
    # + documents - Array of documents to be indexed
    # + return - An error if indexing fails, otherwise nil
    public isolated function index(Document[] documents) returns Error? {
        VectorEntry[] entries = [];
        foreach Document document in documents {
            Embedding embedding = check self.embeddingModel->embed(document.content);
            entries.push({id: uuid:createRandomUuid(), embedding, document});
        }
        check self.vectorStore.add(entries);
    }

    # Returns the retriever instance for this knowledge base.
    # Provides access to the retriever for performing document searches against the indexed document collection.
    #
    # + return - The retriever instance
    public isolated function getRetriever() returns Retriever {
        return self.retriever;
    }
}

# Interface for building prompts from context documents and queries.
# Prompt builders structure how retrieved documents and user queries 
# are formatted for presentation to language models in RAG systems.
public type RagPromptTemplate isolated object {
    # Builds a prompt from context documents and a query.
    # Combines retrieved documents with the user query to create
    # structured prompts for language model processing.
    #
    # + context - Array of relevant documents retrieved for the query
    # + query - The user's original query or question
    # + return - A structured prompt ready for language model consumption
    public isolated function format(Document[] context, string query) returns Prompt;
};

# Default implementation of prompt builder.
# Provides a standard template for combining context documents with user queries.
# Creates system prompts that instruct the model to answer based on provided context.
public isolated class DefaultRagPromptTemplate {
    *RagPromptTemplate;

    # Builds a default prompt template.
    # Creates a system prompt with context documents and a user prompt with the query.
    # The format follows common RAG patterns for context-aware question answering.
    #
    # + contextDocuments - Array of relevant documents to include as context
    # + query - The user's question to be answered
    # + return - A prompt with system instructions and user query
    public isolated function format(Document[] contextDocuments, string query) returns Prompt {
        string systemPrompt = string `Answer the question based on the following provided context: `
            + string `<CONTEXT>${string:'join("\n", ...contextDocuments.'map(doc => doc.content))}</CONTEXT>`;
        string userPrompt = "Question:\n" + query;
        return {systemPrompt, userPrompt};
    }
}

# WSO2 model provider implementation.
# Provides chat completion capabilities using WSO2's language model services.
# This is a concrete implementation of the ModelProvider interface.
public isolated client class Wso2ModelProvider {
    *ModelProvider;
    private final wso2:Client llmClient;

    # Initializes a new WSO2 model provider instance.
    # Sets up the HTTP client with authentication and service URL configuration.
    #
    # + config - WSO2 model provider configuration containing service URL and access token
    # + return - An error if initialization fails (e.g., invalid configuration), otherwise nil
    public isolated function init(*Wso2ModelProviderConfig config) returns Error? {
        wso2:Client|error llmClient = new (config = {auth: {token: config.accessToken}}, serviceUrl = config.serviceUrl);
        if llmClient is error {
            return error Error("Failed to initialize Wso2ModelProvider", llmClient);
        }
        self.llmClient = llmClient;
    }

    # Processes chat messages and returns assistant response.
    # Handles conversation context and optional tool integration for enhanced responses.
    #
    # + messages - Array of chat messages for conversation context
    # + tools - Array of available functions/tools for the model
    # + stop - Optional stop sequence for response generation
    # + return - Assistant message response or LLM error
    isolated remote function chat(ChatMessage[] messages, ChatCompletionFunctions[] tools, string? stop = ())
    returns ChatAssistantMessage|LlmError {
        wso2:CreateChatCompletionRequest request = {stop, messages: self.mapToChatCompletionRequestMessage(messages)};
        if tools.length() > 0 {
            request.functions = tools;
        }
        wso2:CreateChatCompletionResponse|error response = self.llmClient->/chat/completions.post(request);
        if response is error {
            return error LlmConnectionError("Error while connecting to the model", response);
        }

        var choices = response.choices;
        if choices.length() == 0 {
            return error LlmInvalidResponseError("Empty response from the model when using function call API");
        }
        wso2:ChatCompletionResponseMessage? message = choices[0].message;
        ChatAssistantMessage chatAssistantMessage = {role: ASSISTANT, content: message?.content};
        wso2:ChatCompletionFunctionCall? functionCall = message?.functionCall;
        if functionCall is wso2:ChatCompletionFunctionCall {
            chatAssistantMessage.toolCalls = [check self.mapToFunctionCall(functionCall)];
        }
        return chatAssistantMessage;
    }

    # Maps internal chat messages to WSO2 API format.
    # Converts the generic ChatMessage types to WSO2-specific request message format.
    #
    # + messages - Array of internal chat messages
    # + return - Array of WSO2 API compatible chat completion request messages
    private isolated function mapToChatCompletionRequestMessage(ChatMessage[] messages)
        returns wso2:ChatCompletionRequestMessage[] {
        wso2:ChatCompletionRequestMessage[] chatCompletionRequestMessages = [];
        foreach ChatMessage message in messages {
            if message is ChatAssistantMessage {
                wso2:ChatCompletionRequestMessage assistantMessage = {role: ASSISTANT};
                FunctionCall[]? toolCalls = message.toolCalls;
                if toolCalls is FunctionCall[] {
                    assistantMessage["function_call"] = {
                        name: toolCalls[0].name,
                        arguments: toolCalls[0].arguments.toJsonString()
                    };
                }
                if message?.content is string {
                    assistantMessage["content"] = message?.content;
                }
                chatCompletionRequestMessages.push(assistantMessage);
            } else {
                chatCompletionRequestMessages.push(message);
            }
        }
        return chatCompletionRequestMessages;
    }

    # Maps WSO2 function call response to internal format.
    # Converts WSO2 API function call format to internal FunctionCall type.
    #
    # + functionCall - WSO2 API function call response
    # + return - Internal FunctionCall representation or LLM error if parsing fails
    private isolated function mapToFunctionCall(wso2:ChatCompletionFunctionCall functionCall)
    returns FunctionCall|LlmError {
        do {
            json jsonArgs = check functionCall.arguments.fromJsonString();
            map<json>? arguments = check jsonArgs.cloneWithType();
            return {name: functionCall.name, arguments};
        } on fail error e {
            return error LlmError("Invalid or malformed arguments received in function call response.", e);
        }
    }
}

# In-memory vector store implementation.
# Provides a simple in-memory storage solution for vector entries.
# Suitable for development, testing, or small-scale applications where persistence is not required.
public isolated class InMemoryVectorStore {
    *VectorStore;
    private final VectorEntry[] entries = [];
    private final int topK;

    # Initializes a new in-memory vector store.
    # Sets up the store with a configurable limit on the number of results returned per query.
    #
    # + topK - Maximum number of top similar vectors to return in query results (default: 3)
    public isolated function init(int topK = 3) {
        self.topK = topK;
    }

    # Adds vector entries to the in-memory store.
    # Only supports dense vectors in this implementation.
    #
    # + entries - Array of vector entries to store
    # + return - Error if non-dense vectors are provided, otherwise nil
    public isolated function add(VectorEntry[] entries) returns Error? {
        foreach VectorEntry entry in entries {
            if entry.embedding !is Vector {
                return error Error("InMemoryVectorStore implementation only supports dense vectors");
            }
        }
        readonly & VectorEntry[] clonedEntries = entries.cloneReadOnly();
        lock {
            self.entries.push(...clonedEntries);
        }
    }

    # Queries the vector store for similar vectors.
    # Uses cosine similarity for dense vector comparison and returns top-K results.
    #
    # + query - The query containing the embedding vector and optional filters
    # + return - Array of vector matches sorted by similarity score (limited to topK) or error
    public isolated function query(VectorStoreQuery query) returns VectorMatch[]|Error {
        if query.embeddingVector !is Vector {
            return error Error("InMemoryVectorStore implementation only supports dense vectors");
        }

        lock {
            VectorMatch[] results = [];
            foreach var entry in self.entries {
                float similarity = self.cosineSimilarity(<Vector>query.embeddingVector.clone(), <Vector>entry.embedding);
                results.push({document: entry.document, embedding: entry.embedding, score: similarity});
            }
            var sorted = from var entry in results
                order by entry.score descending
                limit self.topK
                select entry;
            return sorted.clone();
        }
    }

    # Deletes a vector entry from the in-memory store.
    # Removes the entry that matches the given reference ID.
    #
    # + referenceId - The reference ID of the vector entry to delete
    # + return - Error if the reference ID is not found, otherwise nil
    public isolated function delete(string referenceId) returns Error? {
        lock {
            int? indexToRemove = ();
            foreach int i in 0 ..< self.entries.length() {
                if self.entries[i].id == referenceId {
                    indexToRemove = i;
                    break;
                }
            }

            if indexToRemove is int {
                _ = self.entries.remove(indexToRemove);
            } else {
                return error Error(string `Vector entry with reference ID '${referenceId}' not found`);
            }
        }
    }

    # Calculates cosine similarity between two dense vectors.
    # Cosine similarity measures the cosine of the angle between two vectors,
    # producing a value between -1 and 1 (typically normalized to 0-1 for similarity).
    #
    # + a - First vector for comparison
    # + b - Second vector for comparison  
    # + return - Cosine similarity score between 0 and 1, or 0.0 if vectors have different dimensions
    isolated function cosineSimilarity(Vector a, Vector b) returns float {
        if a.length() != b.length() {
            return 0.0;
        }

        float dot = 0.0; // Dot product
        float normA = 0.0; // Norm of vector A
        float normB = 0.0; // Norm of vector B

        foreach int i in 0 ..< a.length() {
            dot += a[i] * b[i];
            normA += a[i] * a[i];
            normB += b[i] * b[i];
        }

        float denom = normA.sqrt() * normB.sqrt();
        return denom == 0.0 ? 0.0 : dot / denom;
    }
}

# WSO2 embedding provider implementation.
# Provides text embedding capabilities using WSO2's embedding model services.
# This is a concrete implementation of the EmbeddingProvider interface.
public isolated client class Wso2EmbeddingProvider {
    *EmbeddingProvider;
    private final wso2:Client embeddingClient;

    # Initializes a new WSO2 embedding provider instance.
    # Sets up the HTTP client with authentication and service URL configuration.
    #
    # + config - WSO2 model provider configuration containing service URL and access token
    # + return - An error if initialization fails (e.g., invalid configuration), otherwise nil
    public isolated function init(*Wso2ModelProviderConfig config) returns Error? {
        wso2:Client|error embeddingClient = new (config = {auth: {token: config.accessToken}}, serviceUrl = config.serviceUrl);
        if embeddingClient is error {
            return error Error("Failed to initialize Wso2ModelProvider", embeddingClient);
        }
        self.embeddingClient = embeddingClient;
    }

    # Converts document text to embedding vector.
    # Transforms textual content into numerical vector representation for similarity search.
    #
    # + document - The text document to embed
    # + return - Embedding vector representation or error if the embedding service fails
    isolated remote function embed(string document) returns Embedding|Error {
        wso2:EmbeddingRequest request = {input: document};
        wso2:EmbeddingResponse|error response = self.embeddingClient->/embeddings.post(request);
        if response is error {
            return error Error("Error generating embedding for provided document", response);
        }
        return response.data[0].embedding;
    }
}

# Creates a default WSO2 model provider instance using global configuration.
# Uses the configurable wso2ModelProviderConfig to initialize the provider.
#
# + return - Configured WSO2ModelProvider instance or error if configuration is missing
isolated function getDefaultModelProvider() returns Wso2ModelProvider|Error {
    Wso2ModelProviderConfig? config = wso2ModelProviderConfig;
    if config is () {
        return error Error("Set the WSO2 model provider config in toml file");
    }
    return new Wso2ModelProvider(config);
}

# Creates a default vector knowledge base with WSO2 services.
# Sets up an in-memory vector store with WSO2 embedding provider using global configuration.
#
# + return - Configured VectorKnowledgeBase instance or error if configuration/initialization fails
isolated function getDefaultKnowledgeBase() returns VectorKnowledgeBase|Error {
    Wso2ModelProviderConfig? config = wso2ModelProviderConfig;
    if config is () {
        return error Error("Set the WSO2 model provider config in toml file");
    }
    EmbeddingProvider|Error wso2EmbeddingProvider = new Wso2EmbeddingProvider(config);
    if wso2EmbeddingProvider is Error {
        return error Error("error creating default vector knowledge base");
    }
    return new VectorKnowledgeBase(new InMemoryVectorStore(), wso2EmbeddingProvider);
}

# RAG (Retrieval-Augmented Generation) query engine.
# The RAG class orchestrates the entire RAG pipeline: document retrieval,
# prompt construction, and language model generation to answer user queries.
public isolated class Rag {
    private final ModelProvider model;
    private final VectorKnowledgeBase knowledgeBase;
    private final RagPromptTemplate promptTemplate;

    # Initializes a new RAG query engine.
    # Sets up the complete RAG pipeline with model provider, knowledge base, and prompt template.
    # Uses default implementations if specific components are not provided.
    #
    # + model - The language model provider for response generation (optional, uses default if nil)
    # + knowledgeBase - The vector knowledge base containing searchable documents (optional, uses default if nil)
    # + promptTemplate - Custom RAG prompt template (optional, defaults to DefaultRagPromptTemplate)
    # + return - An error if initialization fails, otherwise nil
    public isolated function init(ModelProvider? model = (),
            VectorKnowledgeBase? knowledgeBase = (),
            RagPromptTemplate promptTemplate = new DefaultRagPromptTemplate()) returns Error? {
        self.model = model ?: check getDefaultModelProvider();
        self.knowledgeBase = knowledgeBase ?: check getDefaultKnowledgeBase();
        self.promptTemplate = promptTemplate;
    }

    # Processes a query through the complete RAG pipeline.
    # Retrieves relevant documents, builds context-aware prompts, and generates responses.
    #
    # + query - The user's question or query
    # + filters - Optional metadata filters to apply during retrieval (defaults to empty filters)
    # + return - The generated response or an error if processing fails
    public isolated function query(string query, MetadataFilters? filters = {}) returns string|Error {
        DocumentMatch[] context = check self.knowledgeBase.getRetriever().retrieve(query, filters);
        Prompt prompt = self.promptTemplate.format(context.'map(ctx => ctx.document), query);
        ChatMessage[] messages = self.mapPromptToChatMessages(prompt);
        ChatAssistantMessage response = check self.model->chat(messages, []);
        return response.content ?: error Error("Unable to obtain valid answer");
    }

    # Ingests documents into the knowledge base.
    # Processes and indexes documents to make them searchable for future queries.
    #
    # + documents - Array of documents to ingest
    # + return - Error if ingestion fails, otherwise nil
    public isolated function ingest(Document[] documents) returns Error? {
        return self.knowledgeBase.index(documents);
    }

    # Converts a prompt to chat message format.
    # Transforms structured prompts into the chat message format expected by language models.
    #
    # + prompt - The prompt to convert
    # + return - Array of chat messages ready for model consumption
    private isolated function mapPromptToChatMessages(Prompt prompt) returns ChatMessage[] {
        string? systemPrompt = prompt?.systemPrompt;
        string? userPrompt = prompt?.userPrompt;
        ChatMessage[] messages = [];
        if systemPrompt is string {
            messages.push({role: SYSTEM, content: systemPrompt});
        }
        if userPrompt is string {
            messages.push({role: USER, content: userPrompt});
        }
        return messages;
    }
};
