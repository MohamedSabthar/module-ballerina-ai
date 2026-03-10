import ballerina/test;

ToolConfig searchTool = {
    name: "Search",
    description: " A search engine. Useful for when you need to answer questions about current events",
    parameters: {
        properties: {
            params: {
                properties: {
                    query: {'type: "string", description: "The search query"}
                }
            }
        }
    },
    caller: searchToolMock
};

ToolConfig calculatorTool = {
    name: "Calculator",
    description: "Useful for when you need to answer questions about math.",
    parameters: {
        properties: {
            params: {
                properties: {
                    expression: {'type: "string", description: "The mathematical expression to evaluate"}
                }
            }
        }
    },
    caller: calculatorToolMock
};

ModelProvider model = new MockLLM();

@test:Config
function testAgentRunHavingErrorStep() returns error? {
    Agent agent = check new (systemPrompt = {role: "Assistant", instructions: "Answer the questions"},
        model = model, tools = [searchTool, calculatorTool], maxIter = 5, verbose = true
    );
    string query = "Random query";
    ExecutionTrace trace = agent.runExecutor(query);
    test:assertEquals(trace.answer is (), true);
    test:assertEquals(trace.steps.length(), 1);
    test:assertEquals(trace.steps[0] is Error, true);
}
