
// https://opentelemetry.io/docs/specs/semconv/gen-ai/non-normative/examples-llm-calls/
public type LlmSpan distinct isolated object {
    *AiSpan;
    public isolated function addProvider(string providerName);
    public isolated function addTemperature(float|decimal temperature);
    public isolated function addInputMessages(json messages);
    public isolated function addOutputMessages(json messages);
    public isolated function addResponseModel(string modelName);
    public isolated function addResponseId(string|int id);
    public isolated function addInputTokenCount(int count);
    public isolated function addOutputTokenCount(int count);
    public isolated function addFinishReason(string|string[] reason);
    public isolated function addOutputType(OutputType outputType);
    public isolated function addStopSequence(string|string[] stopSequence);
    // Not mandated by spec
    public isolated function addTools(json[] tools);
};

public isolated distinct class ChatSpan {
    *LlmSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string modelName) {
        self.baseSpan = new (string `${CHAT} ${modelName}`);
        self.addTag(OPERATION_NAME, CHAT);
        self.addTag(REQUEST_MODEL, modelName);
    }

    public isolated function addProvider(string providerName) {
        self.addTag(PROVIDER_NAME, providerName);
    }

    public isolated function addTemperature(float|decimal temperature) {
        self.addTag(TEMPERATURE, temperature);
    }

    public isolated function addInputMessages(json messages) {
        self.addTag(INPUT_MESSAGES, messages);
    }

    public isolated function addOutputMessages(json messages) {
        self.addTag(OUTPUT_MESSAGES, messages);
    }

    public isolated function addResponseModel(string modelName) {
        self.addTag(RESPONSE_MODEL, modelName);
    }

    // Not mandated by spec
    public isolated function addTools(json[] tools) {
        self.addTag(INPUT_TOOLS, tools);
    }

    public isolated function addResponseId(string|int id) {
        self.addTag(RESPONSE_ID, id);
    }

    public isolated function addInputTokenCount(int count) {
        self.addTag(INPUT_TOKENS, count);
    }

    public isolated function addOutputTokenCount(int count) {
        self.addTag(OUTPUT_TOKENS, count);
    }

    public isolated function addFinishReason(string|string[] reason) {
        string[] reasons = reason is string[] ? reason : [reason];
        self.addTag(FINISH_REASON, reasons);
    }

    public isolated function addOutputType(OutputType outputType) {
        self.addTag(OUTPUT_TYPE, outputType);
    }

    public isolated function addStopSequence(string|string[] stopSequence) {
        self.addTag(STOP_SEQUENCE, stopSequence);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    public isolated function close(error? 'error = ()) {
        self.baseSpan.close('error);
    }
}

public isolated distinct class GenerateContentSpan {
    *LlmSpan;
    private final BaseSpanImp baseSpan;

    public isolated function init(string modelName) {
        self.baseSpan = new (string `${GENERATE_CONTENT} ${modelName}`);
        self.addTag(OPERATION_NAME, GENERATE_CONTENT);
        self.addTag(REQUEST_MODEL, modelName);
    }

    public isolated function addProvider(string providerName) {
        self.addTag(PROVIDER_NAME, providerName);
    }

    public isolated function addTemperature(float|decimal temperature) {
        self.addTag(TEMPERATURE, temperature);
    }

    public isolated function addInputMessages(json messages) {
        self.addTag(INPUT_MESSAGES, messages);
    }

    public isolated function addOutputMessages(json messages) {
        self.addTag(OUTPUT_MESSAGES, messages);
    }

    public isolated function addResponseModel(string modelName) {
        self.addTag(RESPONSE_MODEL, modelName);
    }

    // Not mandated by spec
    public isolated function addTools(json[] tools) {
        self.addTag(INPUT_TOOLS, tools);
    }

    public isolated function addResponseId(string|int id) {
        self.addTag(RESPONSE_ID, id);
    }

    public isolated function addInputTokenCount(int count) {
        self.addTag(INPUT_TOKENS, count);
    }

    public isolated function addOutputTokenCount(int count) {
        self.addTag(OUTPUT_TOKENS, count);
    }

    public isolated function addFinishReason(string|string[] reason) {
        string[] reasons = reason is string[] ? reason : [reason];
        self.addTag(FINISH_REASON, reasons);
    }

    public isolated function addOutputType(OutputType outputType) {
        self.addTag(OUTPUT_TYPE, outputType);
    }

    public isolated function addStopSequence(string|string[] stopSequence) {
        self.addTag(STOP_SEQUENCE, stopSequence);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    public isolated function close(error? 'error = ()) {
        self.baseSpan.close('error);
    }
}
