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

isolated function toChatMessageArrayForTest(ChatMessage[]|ChatUserMessage messages) returns ChatMessage[] {
    if messages is ChatUserMessage {
        return [messages];
    }
    return messages;
}

isolated function countCompletedToolCallsForTest(ChatMessage[] history) returns int {
    int completed = 0;
    foreach ChatMessage message in history {
        if message is ChatFunctionMessage {
            completed = completed + 1;
        }
    }
    return completed;
}

// Scripts activate_skill -> greetTool -> a final answer, so a real `agent.run()` call
// exercises the actual tool-execution path (ToolStore.execute -> executeTool ->
// getInputArgumentsOfTool), not just a direct call to `Agent.activateSkillTool`. This is
// what proves the `Context` auto-injection into a *bound instance method* (as opposed to a
// plain function) actually works end to end.
isolated client class ScriptedGreeterModel {
    *ModelProvider;

    isolated remote function chat(ChatMessage[]|ChatUserMessage messages, ChatCompletionFunctions[] tools = [],
            string? stop = ()) returns ChatAssistantMessage|Error {
        ChatMessage[] history = toChatMessageArrayForTest(messages);
        int completed = countCompletedToolCallsForTest(history);
        if completed == 0 {
            return {
                role: ASSISTANT,
                toolCalls: [{name: ACTIVATE_SKILL_TOOL_NAME, arguments: {"name": "greeter"}}]
            };
        }
        if completed == 1 {
            return {
                role: ASSISTANT,
                toolCalls: [{name: "greetTool", arguments: {"name": "World"}}]
            };
        }
        return {role: ASSISTANT, content: "Done greeting."};
    }

    isolated remote function generate(Prompt prompt, typedesc<anydata> td = <>) returns td|Error = external;
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

    // The skill's tool is hidden from the model until the skill is activated, in this session.
    boolean greetToolVisibleBeforeActivation = false;
    foreach Tool tool in tools {
        if tool.name == "greetTool" {
            greetToolVisibleBeforeActivation = agent.isToolVisible(DEFAULT_SESSION_ID, tool);
        }
    }
    test:assertFalse(greetToolVisibleBeforeActivation);

    SkillActivationResult|Error activation = agent.activateSkillTool(new Context(), "greeter");
    if activation is Error {
        test:assertFail("Expected skill activation to succeed: " + activation.message());
    }
    test:assertEquals(activation.activated, "greeter");
    test:assertTrue(activation.instructions.includes("greetTool"));
    test:assertEquals(activation.toolsAdded, ["greetTool"]);

    boolean greetToolVisibleAfterActivation = false;
    foreach Tool tool in tools {
        if tool.name == "greetTool" {
            greetToolVisibleAfterActivation = agent.isToolVisible(DEFAULT_SESSION_ID, tool);
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

    string|Error beforeActivation = agent.readSkillResourceTool(new Context(), "greeter", "references/style-guide.md");
    test:assertTrue(beforeActivation is Error);

    SkillActivationResult|Error activation = agent.activateSkillTool(new Context(), "greeter");
    test:assertTrue(activation is SkillActivationResult);

    string|Error afterActivation = agent.readSkillResourceTool(new Context(), "greeter", "references/style-guide.md");
    if afterActivation is Error {
        test:assertFail("Expected resource read to succeed: " + afterActivation.message());
    }
    test:assertTrue(afterActivation.includes("Keep greetings short"));
}

@test:Config {}
function testSkillActivationIsScopedPerSession() returns error? {
    Skill skill = check readSkill(GREETER_SKILL_DIR, {"greetTool": mockGreetToolConfig()});
    Agent agent = check new (
        systemPrompt = {role: "Assistant", instructions: "Help the user."},
        model = new MockLLM(),
        skills = [skill]
    );

    Context sessionAContext = new;
    sessionAContext.set(SKILL_SESSION_CONTEXT_KEY, "session-a");
    SkillActivationResult|Error activation = agent.activateSkillTool(sessionAContext, "greeter");
    test:assertTrue(activation is SkillActivationResult);

    test:assertTrue(agent.isSkillActivated("session-a", "greeter"));
    test:assertFalse(agent.isSkillActivated("session-b", "greeter"));

    // A resource read scoped to session-b should fail even though session-a activated the skill.
    Context sessionBContext = new;
    sessionBContext.set(SKILL_SESSION_CONTEXT_KEY, "session-b");
    string|Error sessionBRead = agent.readSkillResourceTool(sessionBContext, "greeter", "references/style-guide.md");
    test:assertTrue(sessionBRead is Error);

    // The same read, scoped to session-a, succeeds.
    string|Error sessionARead = agent.readSkillResourceTool(sessionAContext, "greeter", "references/style-guide.md");
    if sessionARead is Error {
        test:assertFail("Expected resource read to succeed: " + sessionARead.message());
    }
    test:assertTrue(sessionARead.includes("Keep greetings short"));
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

@test:Config {}
function testSkillActivationThroughRealToolExecutionLoop() returns error? {
    Skill skill = check readSkill(GREETER_SKILL_DIR, {"greetTool": mockGreetToolConfig()});
    Agent agent = check new (
        systemPrompt = {role: "Assistant", instructions: "Help the user."},
        model = new ScriptedGreeterModel(),
        skills = [skill]
    );

    // The model only ever sees `greetTool` after it calls `activate_skill` itself — proving
    // the framework's `Context` auto-injection (used here to scope activation to
    // "session-x") works for a bound instance method exactly as it does for a plain
    // `@ai:AgentTool` function.
    string answer = check agent.run("Greet the user named World.", "session-x");
    test:assertEquals(answer, "Done greeting.");
    test:assertTrue(agent.isSkillActivated("session-x", "greeter"));
    test:assertFalse(agent.isSkillActivated("some-other-session", "greeter"));
}
