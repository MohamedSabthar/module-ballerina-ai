// public type KnowledgeBaseConfigs VectorKnowledgeBaseConfigs|GraphKnowledgeBaseConfigs;

// public type GraphKnowledgeBaseConfigs record {

// };

// public type VectorKnowledgeBaseConfigs record {
//     VectorStoreConfigs vectorStoreConfigs;
//     EmbeddingProviderConfigs embeddingProviderConfigs;
// };

// public type VectorStoreConfigs PineConeVectorStoreConfigs|
//     WeaviateVectorStoreConfigs|
//     PgVectorVectorStoreConfigs;

// public type PineConeVectorStoreConfigs record {
// }

// public type WeaviateVectorStoreConfigs record {
// }

// public type PgVectorVectorStoreConfigs record {
// };

// public type EmbeddingProviderConfigs OpenAiEmbeddingProviderConfigs|
//     AzureOpenAiEmbedingProviderConfig;

// public type OpenAiEmbeddingProviderConfigs record {
// }

// public type AzureOpenAiEmbedingProviderConfig record {
// };

// public distinct isolated class Rag {
//     private final ModelProvider model;
//     private final KnowledgeBase knowledgeBase;
//     private final RagPromptTemplateBuilder promptTemplate;

//     public isolated function init(ModelProvider? model = (),
//             KnowledgeBaseConfigs knowledgeBaseConfigs = defautltInMemoryKnowledgeBaseConfigs,
//             RagPromptTemplateBuilder promptTemplate = defaultRagPromptTemplateBuilder) returns Error? {
//         self.model = model;
//         self.knowledgeBase = createKnowledgeBase(knowledgeBaseConfigs); // Looks at the share of the configs and creates the appropriate knowledge base
//         self.promptTemplate = promptTemplate;
//     }

//     public isolated function query(string query, MetadataFilters? filters = ()) returns string|Error {

//     }

//     public isolated function ingest(Document[] documents) returns Error? {
//         return self.knowledgeBase.index(documents);
//     }
// };
