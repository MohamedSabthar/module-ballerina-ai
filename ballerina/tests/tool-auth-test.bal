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

import ballerina/cache;
import ballerina/http;
import ballerina/test;
import ballerina/time;

const int MOCK_AUTH_SERVER_PORT = 9098;
const string MOCK_AUTH_SERVER_BASE_URL = "http://localhost:9098";

isolated int mockAuthServerTokenRequestCount = 0;

isolated function getMockAuthServerTokenRequestCount() returns int {
    lock {
        return mockAuthServerTokenRequestCount;
    }
}

// Builds a JWT with an arbitrary "signature" segment: `jwt:decode` (used by `validateToken` in
// token.bal) only base64url-decodes the header/payload, it never verifies the signature, so a
// mock authorization server does not need real signing keys to exercise the success path.
isolated function buildMockAccessToken(string scope) returns string|error {
    [int, decimal] currentTime = time:utcNow();
    json header = {alg: "HS256", typ: "JWT"};
    json payload = {
        exp: currentTime[0] + 3600,
        client_id: "test-client",
        sub: "test-agent",
        scope: scope
    };
    return base64UrlEncode(header.toJsonString().toBytes()) + "." +
        base64UrlEncode(payload.toJsonString().toBytes()) + "." + "signature";
}

// Mock Authorization Server standing in for the real WSO2 IdP flow `getFreshToken` (token.bal)
// drives: POST /authorize -> flow id, POST /authn -> auth code, POST /token -> access token.
// Every tool in these tests is granted the "orders:read" scope.
service / on new http:Listener(MOCK_AUTH_SERVER_PORT) {

    resource function post authorize(http:Request request) returns json {
        return {
            flowId: "test-flow-id",
            nextStep: {authenticators: [{authenticatorId: "basic-authenticator"}]}
        };
    }

    resource function post authn(@http:Payload json body) returns json {
        return {authData: {code: "test-auth-code"}};
    }

    resource function post token(http:Request request) returns json|error {
        lock {
            mockAuthServerTokenRequestCount += 1;
        }
        return {
            access_token: check buildMockAccessToken("orders:read"),
            expires_in: 3600,
            token_type: "Bearer"
        };
    }
}

@test:Config {}
isolated function testAuthorizeToolAcquiresAndCachesToken() returns error? {
    Credential credential = {id: "agent-success", secret: "shh"};
    AgentIdAuthConfig auth = {
        baseAuthUrl: MOCK_AUTH_SERVER_BASE_URL,
        clientId: "test-client",
        redirectUri: "https://localhost/callback",
        scopes: ["orders:read"]
    };
    Context context = new;
    cache:Cache tokenManager = new;

    TokenAcquisitionError|TokenValidationError? result =
        authorizeTool(credential, auth, "lookupOrder", context, tokenManager);
    test:assertExactEquals(result, ());

    string accessToken = check context.getAccessToken("lookupOrder");
    test:assertTrue(accessToken.length() > 0);

    // The token must be stored in the caller-provided cache, keyed by credential + tool name.
    test:assertTrue(tokenManager.hasKey(tokenCacheKey(credential.id, "lookupOrder")));
}

@test:Config {}
isolated function testAuthorizeToolFailsWithInsufficientScope() returns error? {
    Credential credential = {id: "agent-insufficient-scope", secret: "shh"};
    AgentIdAuthConfig auth = {
        baseAuthUrl: MOCK_AUTH_SERVER_BASE_URL,
        clientId: "test-client",
        redirectUri: "https://localhost/callback",
        // The mock server only ever grants "orders:read"; requiring a different scope must fail.
        scopes: ["orders:write"]
    };
    Context context = new;
    cache:Cache tokenManager = new;

    TokenAcquisitionError|TokenValidationError? result =
        authorizeTool(credential, auth, "lookupOrder", context, tokenManager);
    test:assertTrue(result is InsufficientScopeError);
    test:assertTrue(context.getAccessToken("lookupOrder") is error);
}

@test:Config {}
isolated function testAuthorizeToolReusesCachedTokenAcrossCalls() returns error? {
    Credential credential = {id: "agent-cache-reuse", secret: "shh"};
    AgentIdAuthConfig auth = {
        baseAuthUrl: MOCK_AUTH_SERVER_BASE_URL,
        clientId: "test-client",
        redirectUri: "https://localhost/callback",
        scopes: ["orders:read"]
    };
    cache:Cache tokenManager = new;

    Context context1 = new;
    TokenAcquisitionError|TokenValidationError? result1 =
        authorizeTool(credential, auth, "lookupOrder", context1, tokenManager);
    test:assertExactEquals(result1, ());
    int requestCountAfterFirstCall = getMockAuthServerTokenRequestCount();

    Context context2 = new;
    TokenAcquisitionError|TokenValidationError? result2 =
        authorizeTool(credential, auth, "lookupOrder", context2, tokenManager);
    test:assertExactEquals(result2, ());
    int requestCountAfterSecondCall = getMockAuthServerTokenRequestCount();

    // A second call for the same credential and tool, sharing the same `tokenManager`, must reuse
    // the cached token instead of acquiring a new one from the authorization server.
    test:assertEquals(requestCountAfterSecondCall, requestCountAfterFirstCall);
    test:assertEquals(check context2.getAccessToken("lookupOrder"), check context1.getAccessToken("lookupOrder"));
}

@test:Config {}
isolated function testAuthorizeToolDoesNotShareCachedTokenAcrossCredentials() returns error? {
    // End-to-end regression test for the cross-credential cache collision fixed by keying the
    // cache with `credential.id + toolName` instead of `toolName` alone (see `tokenCacheKey`).
    AgentIdAuthConfig auth = {
        baseAuthUrl: MOCK_AUTH_SERVER_BASE_URL,
        clientId: "test-client",
        redirectUri: "https://localhost/callback",
        scopes: ["orders:read"]
    };
    cache:Cache tokenManager = new;

    Context contextA = new;
    TokenAcquisitionError|TokenValidationError? resultA =
        authorizeTool({id: "agent-cross-a", secret: "shh"}, auth, "lookupOrder", contextA, tokenManager);
    test:assertExactEquals(resultA, ());
    int requestCountAfterA = getMockAuthServerTokenRequestCount();

    Context contextB = new;
    TokenAcquisitionError|TokenValidationError? resultB =
        authorizeTool({id: "agent-cross-b", secret: "shh"}, auth, "lookupOrder", contextB, tokenManager);
    test:assertExactEquals(resultB, ());
    int requestCountAfterB = getMockAuthServerTokenRequestCount();

    // Credential B must trigger its own token acquisition against the authorization server rather
    // than reusing credential A's cache entry for the same tool name and shared `tokenManager`.
    test:assertEquals(requestCountAfterB, requestCountAfterA + 1);
}

@test:Config {}
isolated function testAuthorizeToolFailsClosedWithoutCredentialOrConfig() returns error? {
    // `Scopes`-only auth with no credential must fail closed rather than silently invoking the
    // tool without a token.
    Context context = new;
    cache:Cache tokenManager = new;
    TokenAcquisitionError|TokenValidationError? result =
        authorizeTool((), {scopes: ["orders:read"]}, "lookupOrder", context, tokenManager);
    test:assertTrue(result is TokenAcquisitionError);
}

@test:Config {}
isolated function testAuthorizeToolFailsClosedWhenAgentIdAuthConfigHasNoCredential() returns error? {
    // An `AgentIdAuthConfig` requiring scopes, but invoked with no credential, must also fail
    // closed instead of skipping token acquisition.
    Context context = new;
    cache:Cache tokenManager = new;
    AgentIdAuthConfig auth = {
        baseAuthUrl: "https://localhost:9999",
        clientId: "client",
        redirectUri: "https://localhost:9999/callback",
        scopes: ["orders:read"]
    };
    TokenAcquisitionError|TokenValidationError? result =
        authorizeTool((), auth, "lookupOrder", context, tokenManager);
    test:assertTrue(result is TokenAcquisitionError);
}

@test:Config {}
isolated function testAuthorizeToolNoOpWhenToolDeclaresNoAuth() returns error? {
    // A tool with no scopes requirement and no credential must be a no-op: no error, and no
    // access token populated into the context.
    Context context = new;
    cache:Cache tokenManager = new;
    TokenAcquisitionError|TokenValidationError? result =
        authorizeTool((), {}, "lookupOrder", context, tokenManager);
    test:assertExactEquals(result, ());
    test:assertTrue(context.getAccessToken("lookupOrder") is error);
}

@test:Config {}
isolated function testTokenCacheKeyIsScopedPerCredential() {
    // Regression test for the cross-credential cache collision: two different credentials
    // invoking a same-named tool against a shared `cache:Cache` must never resolve to the same
    // cache entry, otherwise one credential's cached token/scopes could authorize another
    // credential's tool call without re-validating.
    string keyForCredentialA = tokenCacheKey("agent-a", "lookupOrder");
    string keyForCredentialB = tokenCacheKey("agent-b", "lookupOrder");
    test:assertNotEquals(keyForCredentialA, keyForCredentialB);

    // Same credential and tool must always resolve to the same key, so caching still works.
    test:assertEquals(keyForCredentialA, tokenCacheKey("agent-a", "lookupOrder"));
}
