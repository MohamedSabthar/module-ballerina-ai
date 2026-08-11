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

import ballerina/test;
import ballerina/ai;
import ballerina/http;

@test:Config {}
function testAgentChat() returns error? {
    ai:ChatClient chatClient = check new("http://localhost:9090/chatService");
    ai:ChatReqMessage req = {
        sessionId: "1",
        message: "Hello Ballerina!"
    };
    ai:ChatRespMessage resp = check chatClient->/chat.post(req);
    test:assertEquals(resp.message, "1: Hello Ballerina!", "Invalid response message");
}

@test:Config {}
function testAgentChatDecision() returns error? {
    ai:ChatClient chatClient = check new("http://localhost:9090/chatService");
    ai:DecisionMessage req = {
        sessionId: "1",
        decisions: {
            "req-1": {decision: ai:APPROVE},
            "req-2": {decision: ai:REJECT, reason: "not needed"}
        }
    };
    ai:ChatRespMessage resp = check chatClient->/decision.post(req);
    test:assertEquals(resp.message, "1: 2 decision(s)", "Invalid response message");
}

// Verifies the dispatcher converts a returned `ai:ApprovalRequiredError` into a structured HTTP
// response (custom status + `{requests: [...]}` body), without the service doing any mapping.
@test:Config {}
function testAgentChatApprovalPause() returns error? {
    http:Client httpClient = check new ("http://localhost:9090");
    http:Response resp = check httpClient->/pausingService/chat.post({sessionId: "1", message: "refund order"});

    test:assertEquals(resp.statusCode, 403, "Expected the pause to map to HTTP 403");
    json body = check resp.getJsonPayload();
    json[] requests = check (check body.requests).ensureType();
    test:assertEquals(requests.length(), 1, "Expected one pending approval request");
    test:assertEquals(check requests[0].toolName, "issueRefund", "Wrong tool name in pending request");
    test:assertEquals(check requests[0].id, "req-1", "Wrong request id in pending request");
}
