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

# Represents a dense vector with floating-point values.
public type DenseVector float[];

# Represents a sparse vector storing only non-zero values with their corresponding indices.
#
# + indices - Array of indices where non-zero values are located 
# + values - Array of non-zero floating-point values corresponding to the indices
public type SparseVector record {|
    int[] indices;
    float[] values;
|};

# Represents a hybrid embedding containing both dense and sparse vector representations..
#
# + dense - Dense vector representation of the embedding
# + sparse - Sparse vector representation of the embedding
public type HybridEmbedding record {|
    DenseVector dense;
    SparseVector sparse;
|};

# Union type representing all possible embedding vector formats.
public type EmbeddingVector DenseVector|SparseVector|HybridEmbedding;

# Represents a document with content and optional metadata..
#
# + content - The textual content of the document 
# + metadata - Optional key-value pairs containing additional information about the document
public type Document record {|
    string content;
    map<anydata> metadata?;
|};

# Represents a vector entry combining an embedding with its source document.
#
# + embedding - The vector representation of the document content  
# + document - The original document associated with this embedding
public type VectorEntry record {|
    EmbeddingVector embedding;
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

# Description.
#
# + systemPrompt - field description  
# + userPrompt - field description
public type Prompt record {|
    string systemPrompt?;
    string userPrompt?;
|};

# Description.
public enum VectorStoreQueryMode {
    DENSE,
    SPARSE,
    HYBRID
};

# Interface for document chunking strategies.
# Chunking strategies define how large documents are split into smaller, manageable pieces.
public type ChunkingStrategy isolated object {
    # Splits content into multiple document chunks.
    #
    # + content - The input text content to be chunked
    # + return - Array of document chunks or an error if chunking fails
    public isolated function chunk(string content) returns Document[]|Error;
};

# Line-based document splitter implementation.
# Splits documents by line breaks, creating one document per line.
public isolated class LineBasedDocumentSplitter {
    *ChunkingStrategy;

    # Splits content into documents based on line breaks.
    #
    # + content - The input text content to be split
    # + return - Array of documents, one per line, or an error if splitting fails
    public isolated function chunk(string content) returns Document[]|Error {
        return re `\n`.split(content).'map(line => {content: line});
    }
}

# Interface for embedding providers.
# Embedding providers convert text into vector representations for similarity search.
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
    public isolated function search(EmbeddingVector queryEmbedding) returns VectorMatch[]|Error;
};

# Interface for embedding providers.
# Embedding providers convert text into vector representations for similarity search.
public type EmbeddingProvider isolated object {
    # Converts text into an embedding vector.
    #
    # + text - The input text to be embedded
    # + return - The embedding vector representation or an error if embedding fails
    public isolated function embed(string text) returns EmbeddingVector|Error;
};

# Document retriever for finding relevant documents based on query similarity.
# Retriever combines embedding generation and vector search to return
public isolated class Retriever {
    private final VectorStore vectorStore;
    private final EmbeddingProvider embeddingProvider;

    # Initializes a new retriever instance.
    # Sets up the retriever with the necessary components for
    # query embedding and vector search operations.
    #
    # + vectorStore - The vector store to search in
    # + embeddingProvider - The embedding provider to use for query embedding
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingProvider) {
        self.vectorStore = vectorStore;
        self.embeddingProvider = embeddingProvider;
    }

    # Retrieves relevant documents for a given query.
    # Embeds the query text and searches for similar vectors,
    # returning matching documents with similarity scores.
    #
    # + query - The text query to search for
    # + return - Array of matching documents with scores or an error if retrieval fails
    public isolated function retrieve(string query) returns DocumentMatch[]|Error {
        EmbeddingVector queryEmbedding = check self.embeddingProvider.embed(query);
        VectorMatch[] matches = check self.vectorStore.search(queryEmbedding);
        return from VectorMatch 'match in matches
            select {document: 'match.document, score: 'match.score};
    }
}

# Vector index for managing document indexing and retrieval operations.
# The vector index handles the process of converting documents to embeddings and storing them for retrieval.
public isolated class VectorIndex {
    // Need hybrid index or seperate vector store (one for dense and one for sparse)? then we need to change the init API
    // If we have seperate vector store we need to provide seperate embedding modesl for each vector store (one for dense one for sparse); 
    // How to assosiate vector store with embedding model?

    // Or do we need to compe up with hierarchy of vector indexes?
    // VectorIndex
    // - HybridVectorIndex
    // - DefaultVectorIndex
    //      - SparseVectorIndex
    //      - DenseVectorIndex
    private final VectorStore vectorStore;
    private final EmbeddingProvider embeddingProvider;
    private final Retriever retriever;

    # Initializes a new vector index.
    # Creates a vector index with the specified storage and embedding capabilities.
    # The index manages the entire lifecycle from document ingestion to retrieval.
    #
    # + vectorStore - The vector store for persistence
    # + embeddingProvider - The embedding provider for vectorization
    public isolated function init(VectorStore vectorStore, EmbeddingProvider embeddingProvider) {
        self.vectorStore = vectorStore;
        self.embeddingProvider = embeddingProvider;
        self.retriever = new Retriever(vectorStore, embeddingProvider);
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
            EmbeddingVector embedding = check self.embeddingProvider.embed(document.content);
            VectorEntry entry = {embedding, document};
            // generate sparse vectors
            entries.push(entry);
        }
        check self.vectorStore.add(entries);
    }

    # Returns the retriever instance for this index.
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
public type PromptBuilder isolated object {
    # Builds a prompt from context documents and a query.
    # Combines retrieved documents with the user query to create
    # structured prompts for language model processing.
    #
    # + contextDocuments - Array of relevant documents retrieved for the query
    # + query - The user's original query or question
    # + return - A structured prompt ready for language model consumption
    public isolated function build(Document[] contextDocuments, string query) returns Prompt;
};

# # Default implementation of prompt builder.
# Provides a standard template for combining context documents with user queries.
# Creates system prompts that instruct the model to answer based on provided context.
public isolated class DefaultPromptBuilder {
    *PromptBuilder;

    # Builds a default prompt template.
    # Creates a system prompt with context documents and a user prompt with the query.
    # The format follows common RAG patterns for context-aware question answering.
    #
    # + contextDocuments - Array of relevant documents to include as context
    # + query - The user's question to be answered
    # + return - A prompt with system instructions and user query
    public isolated function build(Document[] contextDocuments, string query) returns Prompt {
        // following is a sample implementation
        string systemPrompt = string `Answer the question based on the following provided context: `
            + string `<CONTEXT>${string:'join("\n", ...contextDocuments.'map(doc => doc.content))}</CONTEXT>"""`;
        string userPrompt = "Question:\n" + query;
        return {systemPrompt, userPrompt};
    }
}

# Query engine for end-to-end RAG (Retrieval-Augmented Generation) operations.
# The query engine orchestrates the entire RAG pipeline: document retrieval,
# prompt construction, and language model generation to answer user queries.
public isolated class QueryEngine {
    private final ModelProvider modelProvider;
    private final VectorIndex vectorIndex;
    private final PromptBuilder promptBuilder;

    # Initializes a new query engine.
    # Sets up the complete RAG pipeline with model provider, vector index,
    # and optional custom prompt builder.
    #
    # + modelProvider - The language model provider for response generation
    # + vectorIndex - The vector index containing searchable documents
    # + promptBuilder - Optional custom prompt builder (defaults to DefaultPromptBuilder)
    public isolated function init(ModelProvider modelProvider, VectorIndex vectorIndex,
            PromptBuilder? promptBuilder = ()) {
        self.modelProvider = modelProvider;
        self.vectorIndex = vectorIndex;
        self.promptBuilder = promptBuilder ?: new DefaultPromptBuilder();
    }

    # Processes a query through the complete RAG pipeline.
    # Retrieves relevant documents, builds a prompt, and generates a response
    # using the configured language model.
    #
    # + query - The user's question or query
    # + return - The generated response or an error if processing fails
    public isolated function query(string query) returns string|Error {
        DocumentMatch[] contextDocuments = check self.vectorIndex.getRetriever().retrieve(query);
        // later when we allow re-reankers we can use the score in the document match
        Prompt prompt = self.promptBuilder.build(contextDocuments.'map(ctx => ctx.document), query);
        ChatMessage[] messages = self.buildChatMessages(prompt);
        ChatAssistantMessage response = check self.modelProvider->chat(messages, []);
        return response.content ?: error Error("Unable to obtain valid response from model");
    }
    
    # Converts a prompt to chat message format.
    # Transforms the structured prompt into the message format expected
    # by the language model provider's chat interface.
    #
    # + prompt - The prompt to convert
    # + return - Array of chat messages ready for model consumption
    private isolated function buildChatMessages(Prompt prompt) returns ChatMessage[] {
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
