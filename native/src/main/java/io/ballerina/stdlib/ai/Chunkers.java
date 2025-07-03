/*
 * Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.stdlib.ai;

import dev.langchain4j.data.document.Document;
import dev.langchain4j.data.document.Metadata;
import dev.langchain4j.data.document.splitter.DocumentByLineSplitter;
import dev.langchain4j.data.segment.TextSegment;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;

import java.util.*;

public class Chunkers {
    public static Object chunkDocumentByLine(BMap document, int chunkSize, int overlapSize) {
        System.out.println("chunk hit");
        Document newDocument = Document.from(document.getStringValue(StringUtils.fromString("content")).getValue());
        DocumentByLineSplitter splitter = new DocumentByLineSplitter(chunkSize, overlapSize);
        List<TextSegment> chunks = splitter.split(newDocument);
        List<Object> initValues = new ArrayList<>();
        chunks.forEach(chunk -> {
            Map<String, Object> values = new HashMap<>();
            values.put("content", chunk.text());
            Metadata metadata = chunk.metadata();
            BMap<BString, Object> mymap = document.containsKey(StringUtils.fromString("metadata")) ? (BMap<BString, Object>) document.get(StringUtils.fromString("metadata")) : ValueCreator.createMapValue();
            var map = metadata.toMap();
            for (Map.Entry<String, Object> entry : map.entrySet()) {
                if (entry.getKey().equals("index") && entry.getValue() instanceof String strVal) {
                    mymap.put(StringUtils.fromString(entry.getKey()), Integer.parseInt(strVal));
                }else if (entry.getValue() instanceof String strVal) {
                    mymap.put(StringUtils.fromString(entry.getKey()), StringUtils.fromString(strVal));
                } else if (!(entry.getValue() instanceof UUID)) {
                    mymap.put(StringUtils.fromString(entry.getKey()), entry.getValue());
                }
            }
            values.put("metadata", ValueCreator.createRecordValue(ModuleUtils.getModule(), "MetaData", mymap));
            BMap<BString, Object> textChunk = ValueCreator.createRecordValue(ModuleUtils.getModule(), "TextChunk", values);
            initValues.add(textChunk);
        });
        BMap<BString, Object> type = ValueCreator.createRecordValue(ModuleUtils.getModule(), "TextChunk");
        return ValueCreator.createArrayValue(initValues.toArray(),
                TypeCreator.createArrayType(
                        type.getType()));
    }
}
