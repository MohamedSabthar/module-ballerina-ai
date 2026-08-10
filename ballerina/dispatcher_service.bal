// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
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

import ballerina/http;

# The HTTP response returned when a run pauses for human approval. Carries the pending approval
# requests in its body so the caller can gather decisions and resume via the `approval` resource.
#
# + body - The pending approval requests awaiting a decision
type ApprovalRequiredResponse record {|
    *http:UnprocessableEntity;
    record {| ApprovalRequest[] requests; |} body;
|};

# Internal service attached to the underlying `http:Listener` in place of the user's `ChatService`.
# For each request it forwards to the matching resource on the user's service (reflectively, via
# the native adaptor) and turns a paused run (`ApprovalRequiredError`) into an
# `ApprovalRequiredResponse`. This is what lets a user's chat service simply return the pause error
# and stay free of any HTTP error-to-response mapping.
#
# The dispatcher holds no Ballerina state: the user's `ChatService` is associated with it as native
# data by `Listener.attach`, keeping the dispatcher `isolated` so requests are served concurrently.
isolated service class ChatDispatcherService {
    *http:Service;

    isolated resource function post chat(@http:Payload ChatReqMessage request)
            returns ChatRespMessage|ApprovalRequiredResponse|error {
        return toResponse(invokeChat(self, request));
    }

    isolated resource function post approval(@http:Payload ChatApprovalMessage request)
            returns ChatRespMessage|ApprovalRequiredResponse|http:NotFound|error {
        if !hasApprovalResource(self) {
            return http:NOT_FOUND;
        }
        return toResponse(invokeApproval(self, request));
    }
}

# Maps a resource result to the wire response: a paused run becomes an `ApprovalRequiredResponse`
# carrying the pending requests; anything else (a normal answer or a genuine error) passes through.
#
# + result - The result returned by the user service's resource
# + return - The `ChatRespMessage`, an `ApprovalRequiredResponse` for a pause, or the original error
isolated function toResponse(ChatRespMessage|error result)
        returns ChatRespMessage|ApprovalRequiredResponse|error {
    if result is ApprovalRequiredError {
        return {body: {requests: result.detail().requests}};
    }
    return result;
}
