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

import ballerina/file;
import ballerina/jballerina.java;

public isolated function readAsTextDocument(string filePath) returns TextDocument|Error {
    string|error absolutePath = file:getAbsolutePath(filePath);
    if absolutePath is error {
        return error Error("failed to read file: " + absolutePath.message());
    }
    return externReadAsTextDocument(absolutePath);
};

isolated function externReadAsTextDocument(string filePath) returns TextDocument|Error = @java:Method {
    'class: "io.ballerina.stdlib.ai.Loader"
} external;
