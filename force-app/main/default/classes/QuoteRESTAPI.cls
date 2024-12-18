@RestResource(urlMapping='/ApexCallFromQCP/*')
global class QuoteRESTAPI {
    @HttpPost
    global static List<SBQQ__QuoteLine__c>  calculateUnitPrice(){
        try{
            List<SBQQ__QuoteLine__c> updatedQuoteLineList = new List<SBQQ__QuoteLine__c>();
            
            String reqBody = RestContext.request.requestBody.toString();
            CPQRequest req = (CPQRequest)JSON.deserialize(reqBody, CPQRequest.class);
            
            updatedQuoteLineList = sendQuoteRestRequest(req);
            /*

for(SBQQ__QuoteLine__c objQuoteLine : req.quoteLines){
System.debug('objQuoteLine@@'+objQuoteLine.SBQQ__Number__c);
if(objQuoteLine.Product_Item_Code__c == '10-0009-9606'){
objQuoteLine.SBQQ__ListPrice__c = 7460;
//objQuoteLine.SBQQ__CustomerPrice__c = 7460;
}else if(objQuoteLine.Product_Item_Code__c == '10-0011-6102'){
objQuoteLine.SBQQ__ListPrice__c = 39145; 
//objQuoteLine.SBQQ__CustomerPrice__c = 39145;
}else if(objQuoteLine.Product_Item_Code__c == '10-0006-7104'){
objQuoteLine.SBQQ__ListPrice__c = 8993;
//objQuoteLine.SBQQ__CustomerPrice__c = 8993;
}else{
objQuoteLine.SBQQ__ListPrice__c = objQuoteLine.SBQQ__ListPrice__c * 0.9;
}
System.debug('objQuoteLine@@'+objQuoteLine.Product_Item_Code__c+'price-->'+objQuoteLine.SBQQ__ListPrice__c);
//objQuoteLine.SBQQ__ListPrice__c = objQuoteLine.SBQQ__ListPrice__c+20;
updatedQuoteLineList.add(objQuoteLine);
}

*/
            return updatedQuoteLineList; 
        }catch (Exception e) {
            return null;
        }
    }
    
    // Method to create and send the REST request
    public static List<SBQQ__QuoteLine__c> sendQuoteRestRequest(CPQRequest objCPQRequest) {
        List<SBQQ__QuoteLine__c> updatedQuoteLineList = new List<SBQQ__QuoteLine__c>();
        
        if (objCPQRequest == null 
            || objCPQRequest.quoteId == null 
            || objCPQRequest.quoteLines == null 
            || objCPQRequest.quoteLines.isEmpty()) {
                return null;
            }
        
        SBQQ__Quote__c objQuote = [SELECT Id, SBQQ__Account__c, SBQQ__Account__r.Code_account_ext__c,
                                   Payer__c, Payer__r.Partner_Account_Lookup__r.Code_account_ext__c,
                                   SBQQ__EndDate__c, SBQQ__Account__r.BillingCountry
                                   FROM SBQQ__Quote__c WHERE Id = :objCPQRequest.quoteId];
        
        // Create the wrapper object
        QuoteRequestWrapper objQuoteRequestWrapper = new QuoteRequestWrapper();
        objQuoteRequestWrapper.QuoteId = objCPQRequest.quoteId;
        string soldTo = '';
        if(objQuote.SBQQ__Account__r.Code_account_ext__c != null){
            soldTo = objQuote.SBQQ__Account__r.Code_account_ext__c;
            for(integer i=soldTo.length();i<10;i++){
                soldTo = '0'+soldTo;
            }
        }
        string payerId = '';
        if(objQuote.Payer__r.Partner_Account_Lookup__r.Code_account_ext__c != null){
            payerId = objQuote.Payer__r.Partner_Account_Lookup__r.Code_account_ext__c;
            for(integer i=payerId.length();i<10;i++){
                payerId = '0'+payerId;
            }
        }
        objQuoteRequestWrapper.SoldTo = soldTo; 
        objQuoteRequestWrapper.Payer = payerId;
        
        String effDate = '';
        if (objQuote.SBQQ__EndDate__c != null) {
            effDate = String.valueOf(objQuote.SBQQ__EndDate__c).left(10);
        }
        objQuoteRequestWrapper.EffectiveDate = effDate;
        
        if (objQuote.SBQQ__Account__r.BillingCountry == 'USA') {
            objQuoteRequestWrapper.SalesOrgId = 'D300';
        } else if (objQuote.SBQQ__Account__r.BillingCountry == 'Canada') {
            objQuoteRequestWrapper.SalesOrgId = 'E200';
        } else {
            objQuoteRequestWrapper.SalesOrgId = 'D300';
        }
        
        for (SBQQ__QuoteLine__c objQuoteLine : objCPQRequest.quoteLines) {
            // Create the QuoteLineItemRequestWrapper object
            QuoteLineItemRequestWrapper objQuoteLineItemReq = new QuoteLineItemRequestWrapper();
            objQuoteLineItemReq.Quantity = Integer.valueOf(objQuoteLine.SBQQ__Quantity__c);
            objQuoteLineItemReq.UOM = 'EA';
            objQuoteLineItemReq.QuoteLineItemId = string.valueof(objQuoteLine.SBQQ__Number__c);
            objQuoteLineItemReq.ProductItemCode = objQuoteLine.Product_Item_Code__c;
            
            // Add the line item to the request wrapper
            objQuoteRequestWrapper.QuoteLineItems.add(objQuoteLineItemReq);
        }
        
        // Serialize the wrapper class to JSON string
        String jsonRequest = JSON.serialize(objQuoteRequestWrapper);
        system.debug('Request@@'+jsonRequest);
        // Create an HttpRequest object
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:SAP_CPQ');  // Use the Named Credential 'SAP_CPQ' here
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonRequest);
        
        // Create an Http object to send the request
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        // Check the response
        if (res.getStatusCode() == 200) {
            
            String jsonResponse = res.getBody();
            system.debug('Response@@@ '+jsonResponse);
            // Deserialize the JSON response into the QuoteResponse class
            QuoteReponseWrapper parsedResponse = (QuoteReponseWrapper) JSON.deserialize(jsonResponse, QuoteReponseWrapper.class);
            // Handle the parsed response
            Map<String,QuoteLineItemResponseWrapper> qliToResponseWrapper  = new  Map<String,QuoteLineItemResponseWrapper>();
            if(parsedResponse != null && parsedResponse.ResponseData != null){
                for(QuoteLineItemResponseWrapper objQLIResponse : parsedResponse.ResponseData){
                    qliToResponseWrapper.put(objQLIResponse.QuoteLineItemId,objQLIResponse);
                } 
            }
            
            if(!qliToResponseWrapper.isEmpty()){
                for (SBQQ__QuoteLine__c objQuoteLine : objCPQRequest.quoteLines) {
                    String strQuoteNumber = String.valueOf(objQuoteLine.SBQQ__Number__c);
                    
                    if(qliToResponseWrapper.containsKey(strQuoteNumber)){
                        system.debug('Response@@'+qliToResponseWrapper.get(strQuoteNumber));
                        objQuoteLine.Customer_Price__c = qliToResponseWrapper.get(strQuoteNumber).FinalPrice;
                        objQuoteLine.SBQQ__ListPrice__c = qliToResponseWrapper.get(strQuoteNumber).ListPrice;
                        objQuoteLine.SBQQ__UnitCost__c = qliToResponseWrapper.get(strQuoteNumber).COGS;
                        if(qliToResponseWrapper.get(strQuoteNumber).ErrorType == 'E'){
                            objQuoteLine.Error_Code__c = qliToResponseWrapper.get(strQuoteNumber).ErrorCode;
                            objQuoteLine.Error_Message__c = qliToResponseWrapper.get(strQuoteNumber).ErrorMessage;
                        }
                        system.debug('Customer_Price__c@@'+objQuoteLine.Customer_Price__c);
                        system.debug('SBQQ__ListPrice__c@@'+objQuoteLine.SBQQ__ListPrice__c);
                        system.debug('SBQQ__UnitCost__c@@'+objQuoteLine.SBQQ__UnitCost__c);
                    }
                    updatedQuoteLineList.add(objQuoteLine);
                }
            }
            
            
        } else {
            System.debug('Request failed: ' + res.getStatusCode() + ' - ' + res.getBody());
        }
        return updatedQuoteLineList;
    }
    
    
    public class CPQRequest {
        public String quoteId;
        public List<SBQQ__QuoteLine__c> quoteLines;
    }
    
    public class QuoteLineItemRequestWrapper {
        public Integer Quantity;
        public String UOM;
        public String QuoteLineItemId;
        public String ProductItemCode;
    }
    
    // Define the wrapper class for QuoteRequest
    public class QuoteRequestWrapper {
        public String QuoteId;
        public String SoldTo;
        public String Payer;
        public String EffectiveDate;
        public String SalesOrgId;
        public List<QuoteLineItemRequestWrapper> QuoteLineItems;
        
        // Constructor to initialize the QuoteLineItems list
        public QuoteRequestWrapper() {
            QuoteLineItems = new List<QuoteLineItemRequestWrapper>();
        }
    }
    
    
    public class QuoteReponseWrapper {
        public String QuoteId;
        public String HeaderErrorType;
        public String HeaderErrorCode;  // Changed to String to allow empty string
        public String HeaderErrorMessage;
        public List<QuoteLineItemResponseWrapper> ResponseData;
        
        public QuoteReponseWrapper() {
            ResponseData = new List<QuoteLineItemResponseWrapper>();
        }
    }
    
    public class QuoteLineItemResponseWrapper {
        public String ProductCode;
        public String AvailableQuantity; // Changed to String
        public String CurrencyValue;
        public Double FinalPrice;
        public Double ListPrice;
        public Double COGS;
        public String UOM;
        public String QuoteLineItemId; // Changed to String for consistency with the JSON
        public String PriceRationale;
        public String RebateInformation;
        public String ErrorType;
        public String ErrorCode;
        public String ErrorMessage;
    }
    
    
    
}