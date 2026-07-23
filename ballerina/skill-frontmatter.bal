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

import ballerina/lang.regexp;

const FRONT_MATTER_DELIMITER = "---";

// `SKILL.md` front matter only needs flat scalars, inline lists (`[a, b]`), block lists
// (`- item` under a key), and folded/literal block scalars (`>`/`|`) — a small subset of
// YAML. A purpose-built parser for that subset avoids pulling in a full YAML dependency.

# Splits a `SKILL.md` document into its front matter (as a flat key/value map) and the
# markdown instruction body that follows it.
#
# + content - Raw contents of a `SKILL.md` file
# + sourcePath - Path of the file being parsed, used only for error messages
# + return - The parsed front matter and the instruction body, or an `Error`
isolated function parseSkillDocument(string content, string sourcePath) returns [map<json>, string]|Error {
    string normalized = regexp:replaceAll(re `\r\n`, content, "\n");
    string[] lines = regexp:split(re `\n`, normalized);
    if lines.length() == 0 || lines[0].trim() != FRONT_MATTER_DELIMITER {
        return error Error(string `'${sourcePath}' must start with a '${FRONT_MATTER_DELIMITER}' front matter block.`);
    }
    int closingIndex = -1;
    foreach int i in 1 ..< lines.length() {
        if lines[i].trim() == FRONT_MATTER_DELIMITER {
            closingIndex = i;
            break;
        }
    }
    if closingIndex == -1 {
        return error Error(string `The front matter block in '${sourcePath}' is not closed with ` +
            string `'${FRONT_MATTER_DELIMITER}'.`);
    }
    map<json> frontMatter = check parseFrontMatterLines(lines.slice(1, closingIndex), sourcePath);
    string body = string:'join("\n", ...lines.slice(closingIndex + 1)).trim();
    return [frontMatter, body];
}

isolated function parseFrontMatterLines(string[] lines, string sourcePath) returns map<json>|Error {
    map<json> result = {};
    int i = 0;
    while i < lines.length() {
        string line = lines[i];
        string trimmedLine = line.trim();
        if trimmedLine.length() == 0 || trimmedLine.startsWith("#") {
            i += 1;
            continue;
        }
        int? colonIndex = trimmedLine.indexOf(":");
        if colonIndex is () {
            return error Error(string `Invalid front matter line in '${sourcePath}': '${line}'`);
        }
        string key = trimmedLine.substring(0, colonIndex).trim();
        string valuePart = trimmedLine.substring(colonIndex + 1).trim();
        if valuePart.length() == 0 {
            [string[], int] [items, nextIndex] = readBlockList(lines, i + 1);
            result[key] = items;
            i = nextIndex;
            continue;
        }
        if valuePart == ">" || valuePart == "|" {
            [string, int] [blockValue, nextIndex] = readBlockScalar(lines, i + 1, valuePart == ">");
            result[key] = blockValue;
            i = nextIndex;
            continue;
        }
        if valuePart.startsWith("[") && valuePart.endsWith("]") {
            string inner = valuePart.substring(1, valuePart.length() - 1).trim();
            result[key] = inner.length() == 0
                ? []
                : (from string item in regexp:split(re `,`, inner)
                    select unquote(item.trim()));
        } else {
            result[key] = unquote(valuePart);
        }
        i += 1;
    }
    return result;
}

isolated function readBlockList(string[] lines, int startIndex) returns [string[], int] {
    string[] items = [];
    int j = startIndex;
    while j < lines.length() {
        string itemLine = lines[j].trim();
        if !itemLine.startsWith("-") {
            break;
        }
        items.push(unquote(itemLine.substring(1).trim()));
        j += 1;
    }
    return [items, j];
}

isolated function readBlockScalar(string[] lines, int startIndex, boolean folded) returns [string, int] {
    string[] blockLines = [];
    int j = startIndex;
    while j < lines.length() && (lines[j].trim().length() == 0 || lines[j].startsWith(" ") || lines[j].startsWith("\t")) {
        if lines[j].trim().length() > 0 {
            blockLines.push(lines[j].trim());
        }
        j += 1;
    }
    return [string:'join(folded ? " " : "\n", ...blockLines), j];
}

isolated function unquote(string value) returns string {
    if value.length() >= 2 {
        if (value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'")) {
            return value.substring(1, value.length() - 1);
        }
    }
    return value;
}

isolated function buildSkillMetadata(map<json> frontMatter, string sourcePath) returns SkillMetadata|Error {
    json? name = frontMatter["name"];
    if name !is string || name.trim().length() == 0 {
        return error Error(string `'${sourcePath}' front matter must declare a non-empty 'name'.`);
    }
    json? description = frontMatter["description"];
    if description !is string || description.trim().length() == 0 {
        return error Error(string `'${sourcePath}' front matter must declare a non-empty 'description'.`);
    }
    SkillMetadata metadata = {name: name.trim(), description: description.trim()};
    json? version = frontMatter["version"];
    if version is string && version.trim().length() > 0 {
        metadata.version = version.trim();
    }
    string[]? tags = check toStringArray(frontMatter["tags"], "tags", sourcePath);
    if tags is string[] {
        metadata.tags = tags;
    }
    string[]? tools = check toStringArray(frontMatter["tools"], "tools", sourcePath);
    if tools is string[] {
        metadata.tools = tools;
    }
    return metadata;
}

isolated function toStringArray(json? value, string fieldName, string sourcePath) returns string[]?|Error {
    if value is () {
        return ();
    }
    if value is string[] {
        return value;
    }
    if value is json[] {
        string[] result = [];
        foreach json item in value {
            if item !is string {
                return error Error(string `Expected '${fieldName}' in '${sourcePath}' to be a list of strings.`);
            }
            result.push(item);
        }
        return result;
    }
    return error Error(string `Expected '${fieldName}' in '${sourcePath}' to be a list of strings.`);
}
