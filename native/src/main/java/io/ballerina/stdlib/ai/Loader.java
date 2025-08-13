package io.ballerina.stdlib.ai;

import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.RecordType;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;
import org.apache.tika.exception.TikaException;
import org.apache.tika.metadata.Metadata;
import org.apache.tika.parser.AutoDetectParser;
import org.apache.tika.parser.ParseContext;
import org.apache.tika.sax.BodyContentHandler;
import org.xml.sax.SAXException;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;

public class Loader {
    public static Object externReadAsTextDocument(BString filePath) {
        try (InputStream stream = new FileInputStream(filePath.getValue())) {
            AutoDetectParser parser = new AutoDetectParser();
            BodyContentHandler handler = new BodyContentHandler(-1); // -1 = unlimited length
            Metadata metadata = new Metadata();
            ParseContext context = new ParseContext();
            parser.parse(stream, handler, metadata, context);
            RecordType textDocumentType = TypeCreator.createRecordType("TextDocument", ModuleUtils.getModule(), 0, true, 0);
            BMap<BString, Object> textDocument = ValueCreator.createRecordValue(textDocumentType);
            textDocument.put(StringUtils.fromString("content"), StringUtils.fromString(handler.toString()));

//            RecordType MetadataType = TypeCreator.createRecordType("Metadata", ModuleUtils.getModule(),0, true, 0);
//            BMap<BString, Object> metadataRecord = ValueCreator.createRecordValue(textDocumentType);
//
            System.out.println(metadata.toString());
            return textDocument;
        } catch (TikaException | IOException | SAXException e) {
            return ModuleUtils.createError("unable to read document: " + e.getMessage());
        }
    }
}
