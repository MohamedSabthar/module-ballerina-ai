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

import ballerina/test;

const GREETER_SKILL_DIR = "tests/resources/skills/greeter";
const NO_TOOLS_SKILL_DIR = "tests/resources/skills/no-tools";
const BAD_SKILL_DIR = "tests/resources/skills/bad-skill";
const SKILLS_ROOT_DIR = "tests/resources/skills-root";

isolated function greetToolMock(string name) returns string {
    return string `Hello, ${name}`;
}

isolated function mockGreetToolConfig() returns ToolConfig {
    isolated function caller = greetToolMock;
    return {
        name: "greetTool",
        description: "Greets a person by name.",
        parameters: {
            properties: {
                name: {'type: STRING}
            },
            required: ["name"]
        },
        caller
    };
}

@test:Config {}
function testReadSkillWithToolsAndResources() returns error? {
    Skill skill = check readSkill(GREETER_SKILL_DIR, {"greetTool": mockGreetToolConfig()});

    SkillMetadata metadata = skill.getMetadata();
    test:assertEquals(metadata.name, "greeter");
    test:assertEquals(metadata.description, "Use when the user wants to be greeted by name.");
    test:assertEquals(metadata.version, "1.0.0");
    test:assertEquals(metadata.tags, ["demo", "greeting"]);
    test:assertEquals(metadata.tools, ["greetTool"]);

    string instructions = skill.getInstructions();
    test:assertTrue(instructions.includes("greetTool"));

    (ToolConfig|FunctionTool)[] tools = skill.getTools();
    test:assertEquals(tools.length(), 1);

    string resourceContent = check skill.getResource("references/style-guide.md");
    test:assertTrue(resourceContent.includes("Keep greetings short"));
}

@test:Config {}
function testReadSkillWithoutTools() returns error? {
    Skill skill = check readSkill(NO_TOOLS_SKILL_DIR);
    test:assertEquals(skill.getMetadata().name, "no-tools");
    test:assertEquals(skill.getTools().length(), 0);
}

@test:Config {}
function testReadSkillMissingName() {
    Skill|Error result = readSkill(BAD_SKILL_DIR);
    test:assertTrue(result is Error);
}

@test:Config {}
function testReadSkillMissingDirectory() {
    Skill|Error result = readSkill("tests/resources/skills/does-not-exist");
    test:assertTrue(result is Error);
}

@test:Config {}
function testReadSkillUnresolvedToolName() {
    Skill|Error result = readSkill(GREETER_SKILL_DIR);
    test:assertTrue(result is Error);
}

@test:Config {}
function testGetResourceRejectsPathTraversal() returns error? {
    Skill skill = check readSkill(NO_TOOLS_SKILL_DIR);
    string|Error result = skill.getResource("../greeter/SKILL.md");
    test:assertTrue(result is Error);
}

@test:Config {}
function testGetResourceMissingFile() returns error? {
    Skill skill = check readSkill(NO_TOOLS_SKILL_DIR);
    string|Error result = skill.getResource("does-not-exist.md");
    test:assertTrue(result is Error);
}

@test:Config {}
function testReadSkillsSkipsDirectoriesWithoutSkillFile() returns error? {
    Skill[] skills = check readSkills(SKILLS_ROOT_DIR);
    test:assertEquals(skills.length(), 2);
    string[] names = [];
    foreach Skill skill in skills {
        names.push(skill.getMetadata().name);
    }
    test:assertTrue(names.indexOf("skill-a") is int);
    test:assertTrue(names.indexOf("skill-b") is int);
}

@test:Config {}
function testAgentRegistersSkillToolsAndMetaTools() returns error? {
    Skill skill = check readSkill(GREETER_SKILL_DIR, {"greetTool": mockGreetToolConfig()});
    Agent agent = check new (
        systemPrompt = {role: "Assistant", instructions: "Help the user."},
        model = new MockLLM(),
        skills = [skill]
    );

    Tool[] tools = getTools(agent);
    string[] toolNames = [];
    foreach Tool tool in tools {
        toolNames.push(tool.name);
    }
    test:assertTrue(toolNames.indexOf("greetTool") is int);
    test:assertTrue(toolNames.indexOf(ACTIVATE_SKILL_TOOL_NAME) is int);
    test:assertTrue(toolNames.indexOf(READ_SKILL_RESOURCE_TOOL_NAME) is int);

    // The skill's tool is hidden from the model until the skill is activated.
    boolean greetToolVisibleBeforeActivation = false;
    foreach Tool tool in tools {
        if tool.name == "greetTool" {
            greetToolVisibleBeforeActivation = agent.isToolVisible(tool);
        }
    }
    test:assertFalse(greetToolVisibleBeforeActivation);

    SkillActivationResult|Error activation = agent.activateSkillTool("greeter");
    if activation is Error {
        test:assertFail("Expected skill activation to succeed: " + activation.message());
    }
    test:assertEquals(activation.activated, "greeter");
    test:assertTrue(activation.instructions.includes("greetTool"));
    test:assertEquals(activation.toolsAdded, ["greetTool"]);

    boolean greetToolVisibleAfterActivation = false;
    foreach Tool tool in tools {
        if tool.name == "greetTool" {
            greetToolVisibleAfterActivation = agent.isToolVisible(tool);
        }
    }
    test:assertTrue(greetToolVisibleAfterActivation);
}

@test:Config {}
function testAgentReadSkillResourceRequiresActivation() returns error? {
    Skill skill = check readSkill(GREETER_SKILL_DIR, {"greetTool": mockGreetToolConfig()});
    Agent agent = check new (
        systemPrompt = {role: "Assistant", instructions: "Help the user."},
        model = new MockLLM(),
        skills = [skill]
    );

    string|Error beforeActivation = agent.readSkillResourceTool("greeter", "references/style-guide.md");
    test:assertTrue(beforeActivation is Error);

    SkillActivationResult|Error activation = agent.activateSkillTool("greeter");
    test:assertTrue(activation is SkillActivationResult);

    string|Error afterActivation = agent.readSkillResourceTool("greeter", "references/style-guide.md");
    if afterActivation is Error {
        test:assertFail("Expected resource read to succeed: " + afterActivation.message());
    }
    test:assertTrue(afterActivation.includes("Keep greetings short"));
}

@test:Config {}
function testAgentWithoutSkillsHasNoMetaTools() returns error? {
    Agent agent = check new (
        systemPrompt = {role: "Assistant", instructions: "Help the user."},
        model = new MockLLM()
    );
    Tool[] tools = getTools(agent);
    string[] toolNames = [];
    foreach Tool tool in tools {
        toolNames.push(tool.name);
    }
    test:assertTrue(toolNames.indexOf(ACTIVATE_SKILL_TOOL_NAME) is ());
    test:assertTrue(toolNames.indexOf(READ_SKILL_RESOURCE_TOOL_NAME) is ());
}
