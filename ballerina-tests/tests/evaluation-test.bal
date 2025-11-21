import ballerina/ai;
import ballerina/test;

@test:Config {
    dataProvider: toolCallOrderDataSet,
    confidence: 0.8
}
isolated function evaluateToolCallOrder(ToolCallEvalDataProvider entry) returns error? {
    ai:Trace trace = check agent.run(data.input);
    ai:FunctionCall[] toolCalls = ai:getAllToolCalls(trace);
    string[] actualToolCallNames = toolCalls.'map(tool => tool.name);
    test:assertEquals(actualToolCallNames, entry.expectedTools);
}

public type ToolCallEvalDataProvider record {|
    string input;
    string[] expectedTools;
|};

isolated function toolCallOrderDataSet() returns ToolCallEvalDataProvider[][] {
    return [
        // Simple greeting, no tools expected
        [{input: "Hi", expectedTools: []}],

        // Email-related tasks
        [{input: "Summarize the latest emails.", expectedTools: ["readEmail", "summarizeEmail"]}],
        [{input: "Check if I received any emails from John today.", expectedTools: ["readEmail"]}],
        [{input: "Forward the last email from HR to my manager.", expectedTools: ["readEmail", "sendEmail"]}],
        [{input: "Delete all unread promotional emails.", expectedTools: ["readEmail", "deleteEmail"]}],

        // Calendar and scheduling tasks
        [{input: "Book a meeting with raj@wso2.com?", expectedTools: ["readCalendar", "bookCalendar"]}],
        [{input: "Cancel my meeting with the design team tomorrow.", expectedTools: ["readCalendar", "updateCalendar"]}],
        [{input: "Reschedule my call with Alice to next Monday.", expectedTools: ["readCalendar", "updateCalendar"]}],
        [{input: "List all my meetings for this week.", expectedTools: ["readCalendar"]}],

        // Mixed tasks
        [{input: "Summarize my unread emails and schedule a follow-up meeting.", expectedTools: ["readEmail", "summarizeEmail", "readCalendar", "bookCalendar"]}],
        [{input: "Send an email to Raj and add a calendar invite.", expectedTools: ["sendEmail", "bookCalendar"]}],

        // Miscellaneous
        [{input: "What is the weather today?", expectedTools: ["getWeather"]}],
        [{input: "Set a reminder for my doctor's appointment tomorrow.", expectedTools: ["setReminder"]}]
    ];
}
