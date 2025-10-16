public isolated distinct class EmbeddingSpan {
    *AiSpan;
    private final BaseSpanImp baseSpan;

    isolated function init(string embeddingModelName) {
        self.baseSpan = new (string `${EMBEDDINGS} ${embeddingModelName}`);
        self.addTag(OPERATION_NAME, EMBEDDINGS);
        self.addTag(REQUEST_MODEL, embeddingModelName);
    }

    public isolated function addResponseModel(string model) {
        self.addTag(RESPONSE_MODEL, model);
    }

    public isolated function addProvider(string providerName) {
        self.addTag(PROVIDER_NAME, providerName);
    }

    // Not mandated by spec
    public isolated function addInputContent(anydata content) {
        self.addTag(INPUT_CONTENT, content);
    }

    public isolated function addInputTokenCount(int count) {
        self.addTag(INPUT_TOKENS, count);
    }

    isolated function addTag(GenAiTagNames key, anydata value) {
        self.baseSpan.addTag(key, value);
    }

    public isolated function close(error? 'error = ()) {
        self.baseSpan.close('error);
    }
}
