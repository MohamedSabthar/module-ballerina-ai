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

// TODO

# Splits the provided `TextDocument` into lines and attempts to fit as many lines as possible into a single `TextChunk`, adhering to the limit set by `chunkSize`.
# Line boundaries are detected by a minimum of one newline character ("\n"). Any additional whitespaces before or after are ignored. So, the following examples are all valid line separators: "\n", "\n\n", " \n", "\n " and so on.
# If multiple lines fit within `chunkSize`, they are joined together using a newline ("\n").
# If a single line is too long and exceeds `maxChunkSize` and can't be split further an Error is returned.
# Each TextChunk inherits all metadata from the TextDocument and includes an "index" metadata key representing its position within the document (starting from 0).
#
# + document - The input text document to be chunked
# + maxChunkSize - The maximum size of each chunk
# + maxOverlapSize - The size of overlap between chunks
# + return - Array of text chunks on success, or an `ai:Error` if the operation fails
public isolated function chunkDocumentByLine(TextDocument document, int maxChunkSize = 512, int maxOverlapSize = 0)
returns TextChunk[]|Error {
    return chunkDocument(document, maxChunkSize, maxOverlapSize, LINE);
}

isolated function chunkDocument(TextDocument document, int chunkSize, int overlapSize, ChunkStrategy chunkStrategy)
returns TextChunk[]|Error = @java:Method {
    'class: "io.ballerina.stdlib.ai.Chunkers"
} external;
