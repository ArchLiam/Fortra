/**
 * @description Invocable Apex class to parse multi-select picklist values into a loopable collection
 * @author Claude Code
 * @date 2025-10-06
 */
public with sharing class MultiSelectPicklistParser {

    /**
     * @description Parses a semicolon-delimited string (from multi-select picklist) into a Text collection
     * @param requests List of Request wrapper objects containing the multi-select picklist value
     * @return List of Result wrapper objects containing the parsed Text collection
     */
    @InvocableMethod(
        label='Parse Multi-Select Picklist'
        description='Converts semicolon-separated picklist values into a loopable text collection'
        category='Flow Helper'
    )
    public static List<Result> parseMultiSelectPicklist(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Process each request
        for (Request req : requests) {
            Result result = new Result();
            result.textCollection = new List<String>();

            // Handle null or empty input
            if (String.isBlank(req.multiSelectValue)) {
                results.add(result);
                continue;
            }

            // Split by semicolon and process each value
            List<String> rawValues = req.multiSelectValue.split(';');

            for (String value : rawValues) {
                // Trim whitespace
                String trimmedValue = value.trim();

                // Only add non-blank values
                if (String.isNotBlank(trimmedValue)) {
                    result.textCollection.add(trimmedValue);
                }
            }

            results.add(result);
        }

        return results;
    }

    /**
     * @description Input wrapper class for the invocable method
     */
    public class Request {
        @InvocableVariable(
            label='Multi-Select Picklist Value'
            description='Semicolon-separated string from multi-select picklist field'
            required=true
        )
        public String multiSelectValue;
    }

    /**
     * @description Output wrapper class for the invocable method
     */
    public class Result {
        @InvocableVariable(
            label='Text Collection'
            description='Parsed values as a loopable text collection'
        )
        public List<String> textCollection;
    }
}