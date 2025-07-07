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

import ballerina/jballerina.java;

# Represents a document chunking strategy.
# A `Chunker` is responsible for splitting a given `Document` into a list of smaller `Chunk`s.
# This is typically used in Retrieval-Augmented Generation (RAG) pipelines to enable more
# efficient retrieval and processing by breaking down large documents into manageable segments.
public type Chunker isolated object {

    # Splits the given document into smaller chunks.
    #
    # + document - The document to be chunked.
    # + return - An array of `Chunk`s if successful, or an `Error` otherwise.
    public isolated function chunk(Document document) returns Chunk[]|Error;
};

# Provides functionality to recursively chunk a text document using a configurable strategy.
# 
# The chunking process begins with the specified strategy and recursively falls back to 
# finer-grained strategies if the content exceeds the configured `maxChunkSize`. Overlapping content 
# between chunks can be controlled using `maxOverlapSize`.
public isolated class RecursiveChunkder {
    *Chunker;

    private final int maxChunkSize;
    private final int maxOverlapSize;
    private final RecursiveChunkStrategy stratergy;

    # Initializes the `RecursiveChunkder` with chunking constraints.
    #
    # + maxChunkSize - Maximum number of characters allowed per chunk
    # + maxOverlapSize - Number of overlapping characters allowed between chunks
    # + stratergy - The recursive chunking strategy to use. Defaults to `PARAGRAPH`
    public isolated function init(int maxChunkSize, int maxOverlapSize, RecursiveChunkStrategy stratergy = PARAGRAPH) {
        self.maxChunkSize = maxChunkSize;
        self.maxOverlapSize = maxOverlapSize;
        self.stratergy = stratergy;
    }

    # Chunks the given text document using the configured recursive strategy.
    #
    # + document - The input document to be chunked.
    # + return - An array of chunks, or an `Error` if the chunking fails.
    public isolated function chunk(Document document) returns Chunk[]|Error {
        if document !is TextDocument {
            return error Error("Only text documents are supported for chunking");
        }
        return chunkTextDocument(document, self.maxChunkSize, self.maxOverlapSize, self.stratergy);
    }
}

isolated function chunkTextDocument(TextDocument document, int chunkSize, int overlapSize, RecursiveChunkStrategy chunkStrategy)
returns TextChunk[]|Error = @java:Method {
    'class: "io.ballerina.stdlib.ai.Chunkers"
} external;
