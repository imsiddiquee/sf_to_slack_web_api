// SlackFileUploadController2.uploadPdfToSlack('hello','');

public with sharing class SlackFileUploadController2 {

    private static final String SLACK_TOKEN = 'xxxxxxxxxxxxxxxxxx';
    private static final String SLACK_WEBHOOK = 'xxxxxxxxxxxxxxxx';
    //SlackFileUploadController2.webhookPublishMessageToSlack('Hello Slack!');
    @AuraEnabled
    public static String webhookPublishMessageToSlack(String msg) {
        String json_string = prepareJSON(msg).getAsString();

        // API callout
        HttpRequest request = new HttpRequest();
        request.setEndpoint(SLACK_WEBHOOK);
        request.setMethod('POST');
        request.setBody(json_string);

        Http http = new Http();
        try {
            HttpResponse response = http.send(request);              

           return JSON.serialize(new Map<String, String>{'status' => response.getStatus(), 'message' => 'Message uploaded to Slack successfully!'});
        } catch (Exception ex) {
            System.debug('Callout exception-->'+ex.getMessage());
            return JSON.serialize(new Map<String, String>{'status' => '400', 'message' => ex.getMessage()});
            
        }
    }

    // Utility method to generate JSON
    private static JSONGenerator prepareJSON(String msg) {
        JSONGenerator json = JSON.createGenerator(true);
        json.writeStartObject();
        json.writeStringField('text', msg);
        json.writeEndObject();
        return json;
    }


    // @AuraEnabled
    // public static void uploadPdfToSlack(String slackMessage, String selectedChannel) {
    //     try {
    //         // Generate PDF content from Visualforce page
    //         PageReference pdfPage = Page.FAST_StateSummaryPDF;
    //         Blob pdfBody = pdfPage.getContentAsPDF();
    //         Integer pdfLength = pdfBody.size();
    //         String filename = 'StateSummary.pdf';

    //         // Step 1: Get Upload URL from Slack
    //         String uploadUrlResponse = getUploadUrl(filename, pdfLength);
    //         Map<String, Object> uploadUrlMap = (Map<String, Object>) JSON.deserializeUntyped(uploadUrlResponse);
    //         String uploadUrl = (String) uploadUrlMap.get('uploadUrl');
    //         String fileId = (String) uploadUrlMap.get('fileId');

    //         // Step 2: Upload file to Slack
    //         String pdfBase64 = EncodingUtil.base64Encode(pdfBody);
    //         uploadFileToSlack(uploadUrl, pdfBase64, filename);

    //         // Step 3: Complete the upload and send the message
    //         completeUpload(fileId, slackMessage, selectedChannel);
    //     } catch (Exception e) {
    //         throw new AuraHandledException('Error uploading PDF to Slack: ' + e.getMessage());
    //     }
    // }

    @AuraEnabled
    public static String getUploadUrl(String filename, Integer length) {
        String endpoint = 'https://slack.com/api/files.getUploadURLExternal';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + SLACK_TOKEN);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        // Slack API expects the body as form-urlencoded
        String requestBody = 'filename=' + EncodingUtil.urlEncode(filename, 'UTF-8') +
                             '&length=' + length;
        req.setBody(requestBody);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            // Parse the response to get the upload URL and file ID
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if ((Boolean) responseMap.get('ok')) {
                String uploadUrl = (String) responseMap.get('upload_url');
                String fileId = (String) responseMap.get('file_id');
                return JSON.serialize(new Map<String, String>{'uploadUrl' => uploadUrl, 'fileId' => fileId});
            } else {
                throw new AuraHandledException('Error: ' + responseMap.get('error'));
            }
        } else {
            throw new AuraHandledException('HTTP Request failed: ' + res.getStatus());
        }
    }

    @AuraEnabled
    public static void uploadFileToSlack(String uploadUrl, String fileBase64, String filename) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(uploadUrl);
        req.setMethod('POST');
        
        // Use a unique boundary for each request
        String boundary = '----WebKitFormBoundary' + System.currentTimeMillis();
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);

        // Prepare file data
        String headerPart = '--' + boundary + '\r\n' +
                            'Content-Disposition: form-data; name="file"; filename="' + filename + '"\r\n' +
                            'Content-Type: ' + getContentType(filename) + '\r\n\r\n';

        String footerPart = '\r\n--' + boundary + '--';

        // Convert the base64 string to a Blob
        Blob fileBlob = EncodingUtil.base64Decode(fileBase64);
        Blob headerBlob = Blob.valueOf(headerPart);
        Blob footerBlob = Blob.valueOf(footerPart);

        // Combine the parts using hex conversion
        String combinedDataAsHex = EncodingUtil.convertToHex(headerBlob) + EncodingUtil.convertToHex(fileBlob) + EncodingUtil.convertToHex(footerBlob);
        Blob bodyBlob = EncodingUtil.convertFromHex(combinedDataAsHex);

        req.setBodyAsBlob(bodyBlob);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('Failed to upload file to Slack: ' + res.getStatus() + ' ' + res.getBody());
        }
    }

    private static String getContentType(String filename) {
        String extension = filename.substringAfterLast('.');
        if (extension.equalsIgnoreCase('jpg') || extension.equalsIgnoreCase('jpeg')) {
            return 'image/jpeg';
        } else if (extension.equalsIgnoreCase('png')) {
            return 'image/png';
        } else if (extension.equalsIgnoreCase('gif')) {
            return 'image/gif';
        } else if (extension.equalsIgnoreCase('bmp')) {
            return 'image/bmp';
        } else {
            return 'application/octet-stream';
        }
    }

    @AuraEnabled
    public static void completeUpload(String fileId, String slackMessage, String selectedChannel) {
        String endpoint = 'https://slack.com/api/files.completeUploadExternal';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + SLACK_TOKEN);
        req.setHeader('Content-Type', 'application/json');

        // Form the request body as JSON
        Map<String, Object> requestBodyMap = new Map<String, Object>();
        List<Map<String, Object>> filesList = new List<Map<String, Object>>();
        Map<String, Object> fileMap = new Map<String, Object>();
        fileMap.put('id', fileId);
        filesList.add(fileMap);
        requestBodyMap.put('files', filesList);
        requestBodyMap.put('channel_id', selectedChannel);
        requestBodyMap.put('initial_comment', slackMessage);

        // Convert the map to JSON string
        String requestBody = JSON.serialize(requestBodyMap);
        req.setBody(requestBody);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200 || !res.getBody().contains('"ok":true')) {
            throw new AuraHandledException('File upload completion failed: ' + res.getStatus());
        }
    }

    @AuraEnabled
    public static Map<String, Object> retriveChannels(){
        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setEndpoint('https://slack.com/api/conversations.list');
        httpRequest.setHeader('Authorization', 'Bearer ' + SLACK_TOKEN);
        httpRequest.setMethod('GET');

        Map<String, Object> newsJsonData = new Map<String, Object>();
        String strResponse = null;

        try{
            Http http = new Http();
            HttpResponse httpResponse = http.send(httpRequest);
            if(httpResponse.getStatusCode() == 200){
                strResponse = httpResponse.getBody();
            } else {
                throw new CalloutException(httpResponse.getBody());
            }

        } catch(Exception ex){
            throw ex;
        }

        if(!String.isBlank(strResponse)){
            newsJsonData = (Map<String, Object>)JSON.deserializeUntyped(strResponse);
        }
        if(!newsJsonData.isEmpty()){
            return newsJsonData;
        } else {
            return null;
        }
    }
}
