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

# Augments the user's query with relevant context.
#
# + context - Array of matched chunks or documents to include as context
# + query - The user's original question
# + return - The augmented query with injected context
public isolated function augmentUserQuery(QueryMatch[]|Document[] context, string query) returns ChatUserMessage {
    Chunk[]|Document[] relevantContext = [];
    if context is QueryMatch[] {
        relevantContext = context.'map(queryMatch => queryMatch.chunk);
    } else if context is Document[] {
        relevantContext = context;
    }
    Prompt userPrompt = `Answer the question based on the following provided context: 
    <CONTEXT>${relevantContext}</CONTEXT>
    
    Question: ${query}`;
    return {role: USER, content: getPromptParts(userPrompt)};
}
