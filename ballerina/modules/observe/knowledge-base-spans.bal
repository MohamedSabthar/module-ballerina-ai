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

public isolated distinct class CreateKnowledgeBaseSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string kbName) {
        self.baseSpan = new (string `${CREATE_KNOWLEDGE_BASE} ${kbName}`);
        self.addTag(OPERATION_NAME, CREATE_KNOWLEDGE_BASE);
        self.addTag(KNOWLEDGE_BASE_NAME, kbName);
    }

    public isolated function addId(string|int id) {
        self.addTag(KNOWLEDGE_BASE_ID, id);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}

public isolated distinct class KnowledgeBaseIngestSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string kbName) {
        self.baseSpan = new (string `${KNOWLEDGE_BASE_INGEST} ${kbName}`);
        self.addTag(OPERATION_NAME, KNOWLEDGE_BASE_INGEST);
        self.addTag(KNOWLEDGE_BASE_NAME, kbName);
    }

    public isolated function addId(string|int id) {
        self.addTag(KNOWLEDGE_BASE_ID, id);
    }

    public isolated function addInputChunks(json chunks) {
        self.addTag(KNOWLEDGE_BASE_INGEST_INPUT_CHUNKS, chunks);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}

public isolated distinct class KnowledgeBaseRetrieveSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string kbName) {
        self.baseSpan = new (string `${KNOWLEDGE_BASE_RETRIEVE} ${kbName}`);
        self.addTag(OPERATION_NAME, KNOWLEDGE_BASE_RETRIEVE);
        self.addTag(KNOWLEDGE_BASE_NAME, kbName);
    }

    public isolated function addId(string|int id) {
        self.addTag(KNOWLEDGE_BASE_ID, id);
    }

    public isolated function addInputQuery(json query) {
        self.addTag(KNOWLEDGE_BASE_INGEST_INPUT_CHUNKS, query);
    }

    public isolated function addLimit(int maxLimit) {
        self.addTag(KNOWLEDGE_BASE_RETRIEVE_INPUT_LIMIT, maxLimit);
    }

    public isolated function addFilter(json filter) {
        self.addTag(KNOWLEDGE_BASE_RETRIEVE_INPUT_FILTER, filter);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    public isolated function close(error? err = ()) {
        self.baseSpan.close(err);
    }
}
