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

# Resolves a JSON schema to extract constant values and default values.
# This function processes an ObjectInputSchema, extracting `const` values and `default` values
# from its properties. Constant properties are removed from the schema and returned separately.
#
# + schema - The JSON schema to resolve
# + return - A map of constant/default values, or nil if none found
isolated function resolveSchema(map<json> schema) returns map<json>? {
    // TODO fix when all values are removed as constant, to use null schema
    if schema is ObjectInputSchema {
        map<JsonSubSchema>? properties = schema.properties;
        if properties is () {
            return;
        }
        map<json> values = {};
        foreach [string, JsonSubSchema] [key, subSchema] in properties.entries() {
            json returnedValue = ();
            if subSchema is ArrayInputSchema {
                returnedValue = subSchema?.default;
            }
            else if subSchema is PrimitiveInputSchema {
                returnedValue = subSchema?.default;
            }
            else if subSchema is ConstantValueSchema {
                string tempKey = key; // TODO temporary reference to fix java null pointer issue
                returnedValue = subSchema.'const;
                _ = properties.remove(tempKey);
                string[]? required = schema.required;
                if required !is () {
                    schema.required = from string requiredKey in required
                        where requiredKey != tempKey
                        select requiredKey;
                }
            } else {
                returnedValue = resolveSchema(subSchema);
            }
            if returnedValue !is () {
                values[key] = returnedValue;
            }
        }
        if values.length() > 0 {
            return values;
        }
        return ();
    }
    // skip anyof, oneof, allof, not
    return ();
}

# Merges LLM-generated inputs with constant values defined in the tool configuration.
# Constants take precedence for non-map values; for nested maps, merging is recursive.
#
# + inputs - The LLM-generated input values (may be nil)
# + constants - The constant values defined in the tool configuration
# + return - The merged input map
isolated function mergeInputs(map<json>? inputs, map<json> constants) returns map<json> {
    if inputs is () {
        return constants;
    }
    foreach [string, json] [key, value] in constants.entries() {
        if inputs.hasKey(key) {
            json inputValue = inputs[key];
            if inputValue is map<json> && value is map<json> {
                inputs[key] = mergeInputs(inputValue, value);
            }
        } else {
            inputs[key] = value;
        }
    }
    return inputs;
}
