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

# Represents possible vector types.
public type Embedding Vector|SparseVector|HybridVector;

# Represents the set of supported operators used for metadata filtering during vector search operations.
public enum MetadataFilterOperator {
    EQUAL = "==",
    NOT_EQUAL = "!=",
    GREATER_THAN = ">",
    LESS_THAN = "<",
    GREATER_THAN_OR_EQUAL = ">=",
    LESS_THAN_OR_EQUAL = "<=",
    IN = "in",
    NOT_IN = "nin"
}

# Represents logical conditions for combining multiple metadata filtering during vector search operations.
public enum MetadataFilterCondition {
    AND = "and",
    OR = "or"
}

# Represents a metadata filter for vector search operations.
# Defines conditions to filter vectors based on their associated metadata values.
#
# + key - The name of the metadata field to filter
# + operator - The comparison operator to use. Defaults to `EQUAL`
# + value - - The value to compare the metadata field against
public type MetadataFilter record {|
    string key;
    MetadataFilterOperator operator = EQUAL;
    json value;
|};

# Represents a container for combining multiple metadata filters using logical operators.
# Enables complex filtering by applying multiple conditions with AND/OR logic during vector search.
#
# + filters - An array of `MetadataFilter` or nested `MetadataFilters` to apply.
# + condition - The logical operator (`AND` or `OR`) used to combine the filters. Defaults to `AND`.
public type MetadataFilters record {|
    (MetadataFilters|MetadataFilter)[] filters;
    MetadataFilterCondition condition = AND;
|};

# Defines a query to the vector store with an embedding vector and optional metadata filters.
# Supports precise search operations by combining vector similarity with metadata conditions.
#
# + embedding - The vector to use for similarity search.
# + filters - Optional metadata filters to refine the search results.
public type VectorStoreQuery record {|
    Embedding embedding;
    MetadataFilters filters?;
|};

# Represents a document with content and optional metadata.
#
# + content - The main text content of the document
# + metadata - Optional key-value pairs that provide additional information about the document
public type Document record {|
    string content;
    map<anydata> metadata?;
|};

# Represents a vector entry combining an embedding with its source document.
#
# + id - Optional unique identifier for the vector entry
# + embedding - The vector representation of the document content
# + document - The original document associated with the embedding
public type VectorEntry record {|
    string id?;
    Embedding embedding;
    Document document;
|};

type DenseVectorEntry record {|
    string id?;
    Vector embedding;
    Document document;
|};

# Represents a vector match result with similarity score.
#
# + similarityScore - Similarity score indicating how closely the vector matches the query 
public type VectorMatch record {|
    *VectorEntry;
    float similarityScore;
|};

# Represents a document match result with similarity score.
#
# + document - The matched document
# + similarityScore - Similarity score indicating document relevance to the query
public type DocumentMatch record {|
    Document document;
    float similarityScore;
|};

# Represents a prompt constructed by `RagPromptTemplate` object.
#
# + systemPrompt - System-level instructions that given to a Large Language Model
# + userPrompt - The user's question or query given to the Large Language Model
public type Prompt record {|
    string systemPrompt?;
    string userPrompt;
|};

# Represents query modes to be used with vector store.
# Defines different search strategies for retrieving relevant documents
# based on the type of embeddings and search algorithms to be used.
public enum VectorStoreQueryMode {
    DENSE,
    SPARSE,
    HYBRID
};

# Represents configuratations of WSO2 provider.
#
# + serviceUrl - The URL for the WSO2 AI service
# + accessToken - Access token for accessing WSO2 AI service
public type Wso2ProviderConfig record {|
    string serviceUrl;
    string accessToken;
|};

# Configurable for WSO2 provider.
configurable Wso2ProviderConfig? wso2ProviderConfig = ();

# Represents a vector store that provides persistence, management, and search capabilities for vector embeddings.
public type VectorStore isolated object {

    # Adds vector entries to the store.
    #
    # + entries - The array of vector entries to add
    # + return - An `Error` if the operation fails; otherwise, `nil`
    public isolated function add(VectorEntry[] entries) returns Error?;

    # Searches for vectors in the store that are most similar to a given query.
    #
    # + query - The vector store query that specifies the search criteria
    # + return - An array of matching vectors with their similarity scores,
    # or an `Error` if the operation fails
    public isolated function query(VectorStoreQuery query) returns VectorMatch[]|Error;

    # Deletes a vector entry from the store by its unique ID.
    #
    # + id - The unique identifier of the vector entry to delete
    # + return - An `Error` if the operation fails; otherwise, `nil`
    public isolated function delete(string id) returns Error?;
};

# Represents an embedding provider that converts text documents into vector embeddings for similarity search.
public type EmbeddingProvider isolated client object {

    # Converts the given document into a vector embedding.
    #
    # + document - The document to convert into an embedding.
    # + return - The embedding vector representation on success, or an `Error` if the operation fails.
    isolated remote function embed(Document document) returns Embedding|Error;
};

# Represents document retriever that finds relevant documents based on query similarity.
# The `Retriever` combines query embedding generation and vector search
# to return matching documents along with their similarity scores.
public isolated class Retriever {
    private final VectorStore vectorStore;
    private final EmbeddingProvider embeddingModel;

    # Initializes a new `Retriever` instance.
    #
    #
    # + vectorStore - The vector store to search in.
    # + embeddingModel - The embedding provider to use for generating query embeddings
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel) {
        self.vectorStore = vectorStore;
        self.embeddingModel = embeddingModel;
    }

    # Retrieves relevant documents for the given query.
    #
    #
    # + query - The text query to search for
    # + filters - Optional metadata filters to apply during retrieval
    # + return - An array of matching documents with similarity scores, or an `Error` if retrieval fails
    public isolated function retrieve(string query, MetadataFilters? filters = ()) returns DocumentMatch[]|Error {
        Embedding queryEmbedding = check self.embeddingModel->embed({content: query});
        VectorStoreQuery vectorStoreQuery = {
            embedding: queryEmbedding,
            filters: filters
        };
        VectorMatch[] matches = check self.vectorStore.query(vectorStoreQuery);
        return from VectorMatch 'match in matches
            select {document: 'match.document, similarityScore: 'match.similarityScore};
    }
}

# Represents a vector knowledge base for managing document indexing and retrieval operations.
# The `VectorKnowledgeBase` handles converting documents to embeddings,
# storing them in a vector store, and enabling retrieval through a `Retriever`.
public isolated class VectorKnowledgeBase {
    private final VectorStore vectorStore;
    private final EmbeddingProvider embeddingModel;
    private final Retriever retriever;

    # Initializes a new `VectorKnowledgeBase` instance.
    #
    # + vectorStore - The vector store for embedding persistence
    # + embeddingModel - The embedding provider for generating vector representations
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingModel) {
        self.vectorStore = vectorStore;
        self.embeddingModel = embeddingModel;
        self.retriever = new Retriever(vectorStore, embeddingModel);
    }

    # Indexes a collection of documents.
    #
    # Converts each document to an embedding and stores it in the vector store,
    # making the documents searchable through the retriever.
    #
    # + documents - The array of documents to index
    # + return - An `Error` if indexing fails; otherwise, `nil`
    public isolated function index(Document[] documents) returns Error? {
        VectorEntry[] entries = [];
        foreach Document document in documents {
            Embedding embedding = check self.embeddingModel->embed(document);
            entries.push({id: uuid:createRandomUuid(), embedding, document});
        }
        check self.vectorStore.add(entries);
    }

    # Returns the retriever for this knowledge base.
    #
    # + return - The `Retriever` instance for performing document searches
    public isolated function getRetriever() returns Retriever {
        return self.retriever;
    }
}

# Represents a RAG prompt template that builds structured prompts from retrieved context and user queries
# for presentation to Large Language Models in RAG systems.
public type RagPromptTemplate isolated object {

    # Builds a prompt from the given context documents and query.
    #
    # + context - The array of relevant documents to include as context
    # + query - The user's original query or question
    # + return - A formatted prompt ready for LLM consumption
    public isolated function format(Document[] context, string query) returns Prompt;
};

# Default implementation of a RAG prompt template.
# Provides a standard template for combining context documents with user queries,
# creating system prompts that instruct the model to answer based on the provided context.
public isolated class DefaultRagPromptTemplate {
    *RagPromptTemplate;

    # Builds a default prompt. Creates a system prompt that includes the context documents,
    # and a user prompt containing the query. Follows common RAG patterns
    # for context-aware question answering.
    #
    # + context - The array of relevant documents to include as context
    # + query - The user's question to be answered
    # + return - A prompt containing system instructions and the user query
    public isolated function format(Document[] context, string query) returns Prompt {
        string systemPrompt = string `Answer the question based on the following provided context: `
            + string `<CONTEXT>${string:'join("\n", ...context.'map(doc => doc.content))}</CONTEXT>`;
        string userPrompt = "Question:\n" + query;
        return {systemPrompt, userPrompt};
    }
}

# WSO2 model provider implementation that provides chat completion capabilities using WSO2's AI services.
public isolated client class Wso2ModelProvider {
    *ModelProvider;
    private final wso2:Client llmClient;

    # Initializes a new `WSO2ModelProvider` instance.
    #
    # + config - The configuration containing the service URL and access token
    # + return - `nil` on success, or an `Error` if initialization fails
    public isolated function init(*Wso2ProviderConfig config) returns Error? {
        wso2:Client|error llmClient = new (config = {auth: {token: config.accessToken}}, serviceUrl = config.serviceUrl);
        if llmClient is error {
            return error Error("Failed to initialize Wso2ModelProvider", llmClient);
        }
        self.llmClient = llmClient;
    }

    # Sends a chat request to the model with the given messages and tools.
    #
    # + messages - List of chat messages 
    # + tools - Tool definitions to be used for the tool call
    # + stop - Stop sequence to stop the completion
    # + return - Function to be called, chat response or an error in-case of failures
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
        if response.choices.length() == 0 {
            return error LlmInvalidResponseError("Empty response from the model when using function call API");
        }
        wso2:ChatCompletionResponseMessage? message = response.choices[0].message;
        ChatAssistantMessage chatAssistantMessage = {role: ASSISTANT, content: message?.content};
        wso2:ChatCompletionFunctionCall? functionCall = message?.functionCall;
        if functionCall is wso2:ChatCompletionFunctionCall {
            chatAssistantMessage.toolCalls = [check self.mapToFunctionCall(functionCall)];
        }
        return chatAssistantMessage;
    }

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

# An in-memory vector store implementation that provides simple storage for vector entries.
public isolated class InMemoryVectorStore {
    *VectorStore;
    private final VectorEntry[] entries = [];
    private final int topK;

    # Initializes a new in-memory vector store.
    #
    # + topK - The maximum number of top similar vectors to return in query results
    public isolated function init(int topK = 3) {
        self.topK = topK;
    }

    # Adds vector entries to the in-memory store.
    # Only supports dense vectors in this implementation.
    #
    # + entries - Array of vector entries to store
    # + return - `nil` on success; an Error if non-dense vectors are provided
    public isolated function add(VectorEntry[] entries) returns Error? {
        if entries !is DenseVectorEntry[] {
            return error Error("InMemoryVectorStore supports dense vectors exclusively");
        }
        readonly & VectorEntry[] clonedEntries = entries.cloneReadOnly();
        lock {
            self.entries.push(...clonedEntries);
        }
    }

    # Queries the vector store for vectors similar to the given query.
    # Uses cosine similarity for dense vector comparison and returns the top-K results.
    #
    # + query - The query containing the embedding vector and optional filters
    # + return - An array of vector matches sorted by similarity score (limited to topK), 
    # or an `Error` if the query fails
    public isolated function query(VectorStoreQuery query) returns VectorMatch[]|Error {
        if query.embedding !is Vector {
            return error Error("InMemoryVectorStore supports dense vectors exclusively");
        }

        lock {
            VectorMatch[] results = from var entry in self.entries
                let float similarity = self.cosineSimilarity(<Vector>query.clone().embedding, <Vector>entry.embedding)
                limit self.topK
                select {document: entry.document, embedding: entry.embedding, similarityScore: similarity};
            return results.clone();
        }
    }

    # Deletes a vector entry from the in-memory store.
    # Removes the entry that matches the given reference ID.
    #
    # + id - The reference ID of the vector entry to delete
    # + return - `Error` if the reference ID is not found, otherwise `nil`
    public isolated function delete(string id) returns Error? {
        lock {
            int? indexToRemove = ();
            foreach int i in 0 ..< self.entries.length() {
                if self.entries[i].id == id {
                    indexToRemove = i;
                    break;
                }
            }

            if indexToRemove is () {
                return error Error(string `Vector entry with reference ID '${id}' not found`);
            }
            _ = self.entries.remove(indexToRemove);
        }
    }

    private isolated function cosineSimilarity(Vector a, Vector b) returns float {
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

# WSO2 embedding provider implementation that provides embedding capabilities using WSO2's AI service.
public isolated client class Wso2EmbeddingProvider {
    *EmbeddingProvider;
    private final wso2:Client embeddingClient;

    # Initializes a new `Wso2EmbeddingProvider` instance.
    #
    # + config - The configuration containing the service URL and access token
    # + return - `nil` on success, or an `Error` if initialization fails
    public isolated function init(*Wso2ProviderConfig config) returns Error? {
        wso2:Client|error embeddingClient = new (config = {auth: {token: config.accessToken}}, serviceUrl = config.serviceUrl);
        if embeddingClient is error {
            return error Error("Failed to initialize Wso2ModelProvider", embeddingClient);
        }
        self.embeddingClient = embeddingClient;
    }

    # Converts document to embedding.
    #
    # + document - The document to embed
    # + return - Embedding representation of document or an `Error` if the embedding service fails
    isolated remote function embed(Document document) returns Embedding|Error {
        wso2:EmbeddingRequest request = {input: document.content};
        wso2:EmbeddingResponse|error response = self.embeddingClient->/embeddings.post(request);
        if response is error {
            return error Error("Error generating embedding for provided document", response);
        }
        return response.data[0].embedding;
    }
}

isolated function getDefaultModelProvider() returns Wso2ModelProvider|Error {
    Wso2ProviderConfig? config = wso2ProviderConfig;
    if config is () {
        return error Error("The `wso2ProviderConfig` is not configured correctly."
        + " Ensure that the WSO2 model provider configuration is defined in your TOML file.");
    }
    return new Wso2ModelProvider(config);
}

isolated function getDefaultKnowledgeBase() returns VectorKnowledgeBase|Error {
    Wso2ProviderConfig? config = wso2ProviderConfig;
    if config is () {
        return error Error("The `wso2ProviderConfig` is not configured correctly."
        + " Ensure that the WSO2 model provider configuration is defined in your TOML file.");
    }
    EmbeddingProvider|Error wso2EmbeddingProvider = new Wso2EmbeddingProvider(config);
    if wso2EmbeddingProvider is Error {
        return error Error("error creating default vector knowledge base");
    }
    return new VectorKnowledgeBase(new InMemoryVectorStore(), wso2EmbeddingProvider);
}

# Orchestrates a Retrieval-Augmented Generation (RAG) pipeline.
# The `Rag` class manages document retrieval, prompt construction, and language model interaction
# to generate context-aware responses to user queries.
public isolated class Rag {
    private final ModelProvider model;
    private final VectorKnowledgeBase knowledgeBase;
    private final RagPromptTemplate promptTemplate;

    # Creates a new `Rag` instance.
    #
    # + model - The large language model used by the RAG pipeline. If `nil`, `Wso2ModelProvider` is used as the default
    # + knowledgeBase - The knowledge base containing indexed documents.
    # If `nil`, a default `VectorKnowledgeBase` is created, backed by `InMemoryVectorStore` and `Wso2EmbeddingProvider`
    # + promptTemplate - The RAG prompt template used by the language model to construct context-aware prompts.
    # Defaults to `DefaultRagPromptTemplate` if not provided
    # + return - `nil` on success, or an `Error` if initialization fails
    public isolated function init(ModelProvider? model = (),
            VectorKnowledgeBase? knowledgeBase = (),
            RagPromptTemplate promptTemplate = new DefaultRagPromptTemplate()) returns Error? {
        self.model = model ?: check getDefaultModelProvider();
        self.knowledgeBase = knowledgeBase ?: check getDefaultKnowledgeBase();
        self.promptTemplate = promptTemplate;
    }

    # Executes a query through the RAG pipeline.
    # Retrieves context documents, builds a prompt, and generates a model response.
    #
    # + query - The user’s input question or query.
    # + filters - Optional metadata filters for document retrieval.
    # + return - The generated response, or an `Error` if the operation fails.
    public isolated function query(string query, MetadataFilters? filters = ()) returns string|Error {
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
    # + return - `nil` on success; `Error` if ingestion fails 
    public isolated function ingest(Document[] documents) returns Error? {
        return self.knowledgeBase.index(documents);
    }

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
}

# Splits content into documents based on line breaks.
# Each non-empty line becomes a separate document with the line content.
# Empty lines and lines containing only whitespace are filtered out.
#
# + content - The input text content to be split by lines
# + return - Array of documents, one per non-empty line
public isolated function splitDocumentByLine(string content) returns Document[] {
    string[] lines = re `\n`.split(content);
    return from string line in lines
        where line.trim() != ""
        select {content: line.trim()};
}
