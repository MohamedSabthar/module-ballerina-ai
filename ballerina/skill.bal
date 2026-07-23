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

import ballerina/file;
import ballerina/io;

# Name of the file expected at the root of every skill directory.
const SKILL_FILE_NAME = "SKILL.md";

# Reserved name of the built-in tool used to activate a skill.
const ACTIVATE_SKILL_TOOL_NAME = "activate_skill";

# Reserved name of the built-in tool used to read a skill's bundled resource file.
const READ_SKILL_RESOURCE_TOOL_NAME = "read_skill_resource";

# Metadata parsed from a skill's `SKILL.md` front matter.
# This is the only part of a skill visible to the model before it is activated.
@display {label: "Skill Metadata"}
public type SkillMetadata record {|
    # Unique, human-readable name of the skill. This is what the model passes to
    # the `activate_skill` tool.
    string name;
    # A short description of what the skill does and when to use it. This is the only
    # content shown to the model before the skill is activated, so it must be enough
    # for the model to decide, on its own, whether the skill applies to the current task.
    string description;
    # Optional semantic version of the skill.
    string version?;
    # Optional free-form tags used to organize skills. Not sent to the model.
    string[] tags?;
    # Names of the tools this skill needs, resolved against the `toolRegistry` passed
    # to `readSkill`/`readSkills`.
    string[] tools?;
|};

# Result returned by the built-in `activate_skill` tool once a skill is activated.
public type SkillActivationResult record {|
    # Name of the skill that was activated
    string activated;
    # The skill's full instructions, injected into the conversation to guide subsequent tool calls
    string instructions;
    # Names of the tools that became available to the agent as a result of this activation
    string[] toolsAdded;
|};

# Represents a skill loaded from a `SKILL.md` file and its sibling resource files, if any.
#
# A skill bundles instructions (a system-prompt fragment) together with the tools needed to
# carry them out. Only the metadata is consulted before the skill is activated; the instructions
# and tools are only used once an agent activates the skill, and a resource is only read for
# files the instructions explicitly point the agent at.
public isolated class Skill {
    private final SkillMetadata & readonly metadata;
    private final string & readonly instructions;
    // A bare `FunctionTool` (an `isolated function` value) or `BaseToolKit` (a plain, non-isolated
    // `object`) cannot be made `readonly` at runtime, even though the compiler accepts `& readonly`
    // on a union that includes one of them — constructing that type panics at module init.
    // `resolveSkillTools` converts every resolved tool to `ToolConfig` up front (a `FunctionTool`
    // is only readonly-safe as a *field inside* a record, which is exactly what `ToolConfig.caller`
    // is), so this field only ever holds the one, genuinely readonly-safe, member type.
    private final ToolConfig[] & readonly tools;
    private final string & readonly skillDir;

    # Initializes a skill.
    #
    # + metadata - Metadata parsed from the skill's front matter
    # + instructions - The markdown body of the skill's `SKILL.md`, used as a system-prompt fragment
    # + skillDir - Absolute path to the skill's directory, used to resolve bundled resource files
    # + tools - Tools resolved for this skill; empty if the skill declares none
    public isolated function init(SkillMetadata metadata, string instructions, string skillDir,
            ToolConfig[] tools = []) {
        self.metadata = metadata.cloneReadOnly();
        self.instructions = instructions;
        self.skillDir = skillDir;
        self.tools = tools.cloneReadOnly();
    }

    # + return - Metadata used to advertise the skill before activation
    public isolated function getMetadata() returns SkillMetadata => self.metadata;

    # + return - The `SKILL.md` body, injected as a system-prompt fragment on activation
    public isolated function getInstructions() returns string => self.instructions;

    # + return - Tools made available to the agent once this skill is activated
    public isolated function getTools() returns ToolConfig[] => self.tools;

    # Reads a bundled resource file, relative to the skill's directory. Intended to be called
    # lazily, only when the skill's instructions point the agent at a specific file it needs.
    #
    # + relativePath - Path relative to the skill directory, e.g. "references/escalation-policy.md"
    # + return - The file contents, or an `Error` if the path escapes the skill directory,
    # or the file does not exist
    public isolated function getResource(string relativePath) returns string|Error {
        string resolvedSkillDir = check normalizeDir(self.skillDir);
        string|file:Error joined = file:joinPath(self.skillDir, relativePath);
        if joined is file:Error {
            return error Error(string `Invalid resource path '${relativePath}' for skill '${self.metadata.name}'`,
                    joined);
        }
        string|file:Error resolved = file:normalizePath(joined, file:CLEAN);
        if resolved is file:Error {
            return error Error(string `Unable to resolve resource path '${relativePath}' for skill ` +
                string `'${self.metadata.name}'`, resolved);
        }
        if resolved != resolvedSkillDir && !resolved.startsWith(resolvedSkillDir + "/") {
            return error Error(string `Resource path '${relativePath}' escapes the directory of skill ` +
                string `'${self.metadata.name}'`);
        }
        string|io:Error content = io:fileReadString(resolved);
        if content is io:Error {
            return error Error(string `Unable to read resource '${relativePath}' for skill ` +
                string `'${self.metadata.name}'`, content);
        }
        return content;
    }
}

# Parses a single skill directory, which must contain a `SKILL.md` file.
#
# + skillDir - Path to the skill's directory
# + toolRegistry - Maps tool names declared in the `tools` front matter field to their
# Ballerina implementations. A name declared in `SKILL.md` but missing from this registry
# is reported as an `Error`.
# + return - The parsed skill, or an `Error` if `SKILL.md` is missing, malformed,
# or declares a tool name absent from `toolRegistry`
public isolated function readSkill(string skillDir,
        map<BaseToolKit|ToolConfig|FunctionTool> toolRegistry = {}) returns Skill|Error {
    string|file:Error skillFilePath = file:joinPath(skillDir, SKILL_FILE_NAME);
    if skillFilePath is file:Error {
        return error Error(string `Invalid skill directory path: '${skillDir}'`, skillFilePath);
    }
    string|io:Error content = io:fileReadString(skillFilePath);
    if content is io:Error {
        return error Error(string `Unable to read '${skillFilePath}'. Every skill directory must ` +
            string `contain a ${SKILL_FILE_NAME} file.`, content);
    }
    [map<json>, string] [frontMatter, instructions] = check parseSkillDocument(content, skillFilePath);
    SkillMetadata metadata = check buildSkillMetadata(frontMatter, skillFilePath);
    ToolConfig[] tools = check resolveSkillTools(metadata, toolRegistry);
    string|file:Error resolvedSkillDir = file:normalizePath(skillDir, file:CLEAN);
    if resolvedSkillDir is file:Error {
        return error Error(string `Invalid skill directory path: '${skillDir}'`, resolvedSkillDir);
    }
    return new Skill(metadata, instructions, resolvedSkillDir, tools);
}

# Parses every immediate subdirectory of `skillsRootDir` that contains a `SKILL.md` file.
# Subdirectories without one are silently skipped, since not every directory under a skills
# root is necessarily a skill (e.g. shared resource directories).
#
# + skillsRootDir - Directory containing one subdirectory per skill
# + toolRegistry - Shared registry used to resolve every skill's `tools` front matter field
# + return - One `Skill` per subdirectory containing a valid `SKILL.md`, or an `Error`
public isolated function readSkills(string skillsRootDir,
        map<BaseToolKit|ToolConfig|FunctionTool> toolRegistry = {}) returns Skill[]|Error {
    file:MetaData[]|file:Error entries = file:readDir(skillsRootDir);
    if entries is file:Error {
        return error Error(string `Unable to read skills directory: '${skillsRootDir}'`, entries);
    }
    Skill[] skills = [];
    foreach file:MetaData entry in entries {
        if !entry.dir {
            continue;
        }
        string skillDir = entry.absPath;
        string|file:Error skillFilePath = file:joinPath(skillDir, SKILL_FILE_NAME);
        if skillFilePath is file:Error {
            continue;
        }
        boolean|file:Error hasSkillFile = file:test(skillFilePath, file:EXISTS);
        if hasSkillFile is file:Error || !hasSkillFile {
            continue;
        }
        Skill skill = check readSkill(skillDir, toolRegistry);
        skills.push(skill);
    }
    return skills;
}

isolated function resolveSkillTools(SkillMetadata metadata,
        map<BaseToolKit|ToolConfig|FunctionTool> toolRegistry) returns ToolConfig[]|Error {
    string[]? toolNames = metadata.tools;
    if toolNames is () {
        return [];
    }
    ToolConfig[] tools = [];
    foreach string toolName in toolNames {
        BaseToolKit|ToolConfig|FunctionTool? tool = toolRegistry[toolName];
        if tool is () {
            return error Error(string `Skill '${metadata.name}' declares tool '${toolName}', but it ` +
                "was not found in the provided tool registry.");
        }
        if tool is BaseToolKit {
            ToolConfig[] toolsFromToolKit = tool.getTools();
            foreach ToolConfig toolConfig in toolsFromToolKit {
                tools.push(toolConfig);
            }
            continue;
        }
        ToolConfig resolvedToolConfig;
        if tool is ToolConfig {
            resolvedToolConfig = tool;
        } else {
            resolvedToolConfig = check getToolConfig(tool);
        }
        tools.push(resolvedToolConfig);
    }
    return tools;
}

isolated function normalizeDir(string dir) returns string|Error {
    string|file:Error normalized = file:normalizePath(dir, file:CLEAN);
    if normalized is file:Error {
        return error Error(string `Invalid directory path: '${dir}'`, normalized);
    }
    return normalized;
}
