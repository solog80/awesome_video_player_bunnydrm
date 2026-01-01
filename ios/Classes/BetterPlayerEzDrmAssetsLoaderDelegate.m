// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "BetterPlayerEzDrmAssetsLoaderDelegate.h"

@implementation BetterPlayerEzDrmAssetsLoaderDelegate {
    NSString *_assetId;
    NSDictionary *_headers;
    NSString *_videoId;
    NSString *_libraryId;
}

- (instancetype)init:(NSURL *)certificateURL withLicenseURL:(NSURL *)licenseURL headers:(NSDictionary *)headers videoId:(NSString *)videoId libraryId:(NSString *)libraryId {
    self = [super init];
    _certificateURL = certificateURL;
    _licenseURL = licenseURL;
    _headers = headers;
    _videoId = videoId;
    _libraryId = libraryId;
    return self;
}

/*------------------------------------------
 **
 ** getContentKeyFromLicenseServer
 **
 ** Takes the SPC and sends it to BunnyCDN license server.
 ** Returns CKC from JSON response.
 ** ---------------------------------------*/
- (NSData *)getContentKeyFromLicenseServerWithRequest:(NSData*)requestBytes error:(NSError **)errorOut {
    NSData *responseData;
    NSURLResponse *response;
    
    // Determine license URL
    NSURL *finalLicenseURL;
    if (_licenseURL != nil && ![_licenseURL isEqual:[NSNull null]]) {
        finalLicenseURL = _licenseURL;
    } else if (_videoId != nil && _libraryId != nil) {
        // Construct BunnyCDN URL format
        NSString *urlString = [NSString stringWithFormat:@"https://video.bunnycdn.com/FairPlayLicense/%@/%@", _libraryId, _videoId];
        finalLicenseURL = [NSURL URLWithString:urlString];
        NSLog(@"Constructed BunnyCDN license URL: %@", urlString);
    } else {
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:@"FairPlay" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"No license URL or videoId/libraryId provided"}];
        }
        return nil;
    }
    
    // Prepare JSON request body with base64 SPC
    NSString *spcBase64 = [requestBytes base64EncodedStringWithOptions:0];
    NSDictionary *requestBody = @{@"spc": spcBase64};
    
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:requestBody options:0 error:&jsonError];
    
    if (jsonError) {
        NSLog(@"Failed to serialize JSON: %@", jsonError);
        if (errorOut) *errorOut = jsonError;
        return nil;
    }
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:finalLicenseURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:jsonData];
    
    // Add custom headers
    if (_headers) {
        for (NSString *key in _headers) {
            NSString *value = _headers[key];
            [request setValue:value forHTTPHeaderField:key];
        }
    }
    
    NSLog(@"Sending license request to: %@", finalLicenseURL.absoluteString);
    
    // Use synchronous request (keeps compatibility with original code)
    @try {
        responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:errorOut];
        
        if (responseData) {
            // Debug: Log response
            NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
            NSLog(@"License server response: %@", responseString);
            
            // Parse JSON response
            NSError *parseError;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&parseError];
            
            if (!parseError && jsonResponse) {
                NSString *ckcBase64 = jsonResponse[@"ckc"];
                if (ckcBase64 && [ckcBase64 isKindOfClass:[NSString class]]) {
                    // Decode base64 CKC
                    NSData *ckcData = [[NSData alloc] initWithBase64EncodedString:ckcBase64 options:0];
                    if (ckcData) {
                        NSLog(@"Successfully parsed CKC: %lu bytes", (unsigned long)ckcData.length);
                        return ckcData;
                    } else {
                        NSLog(@"Failed to decode base64 CKC");
                    }
                } else if (jsonResponse[@"error"]) {
                    NSLog(@"License server error: %@", jsonResponse[@"error"]);
                }
            } else {
                // If not JSON, assume raw CKC
                NSLog(@"Response is not JSON, assuming raw CKC: %lu bytes", (unsigned long)responseData.length);
                return responseData;
            }
        }
    }
    @catch (NSException* excp) {
        NSLog(@"Exception in license request: %@", excp);
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:@"FairPlay" code:-1 userInfo:@{NSLocalizedDescriptionKey: excp.reason}];
        }
    }
    
    return nil;
}

/*------------------------------------------
 **
 ** getAppCertificate
 **
 ** Returns the app certificate from BunnyCDN
 ** BunnyCDN returns JSON with certificate field
 ** ---------------------------------------*/
- (NSData *)getAppCertificate:(NSString *)assetId error:(NSError **)errorOut {
    NSData *certificateData;
    
    @try {
        // Fetch certificate data
        certificateData = [NSData dataWithContentsOfURL:_certificateURL options:0 error:errorOut];
        
        if (certificateData) {
            // Debug: Log response
            NSString *responseString = [[NSString alloc] initWithData:certificateData encoding:NSUTF8StringEncoding];
            NSLog(@"Certificate response: %@", responseString);
            
            // Try to parse as JSON
            NSError *parseError;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:certificateData options:0 error:&parseError];
            
            if (!parseError && jsonResponse) {
                NSString *certBase64 = jsonResponse[@"certificate"];
                if (certBase64 && [certBase64 isKindOfClass:[NSString class]]) {
                    // Decode base64 certificate
                    NSData *decodedCert = [[NSData alloc] initWithBase64EncodedString:certBase64 options:0];
                    if (decodedCert) {
                        NSLog(@"Successfully parsed certificate from JSON: %lu bytes", (unsigned long)decodedCert.length);
                        return decodedCert;
                    }
                }
            }
            
            // If not JSON, assume raw certificate
            NSLog(@"Assuming raw certificate data: %lu bytes", (unsigned long)certificateData.length);
            return certificateData;
        }
    }
    @catch (NSException* excp) {
        NSLog(@"Exception getting certificate: %@", excp);
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:@"FairPlay" code:-1 userInfo:@{NSLocalizedDescriptionKey: excp.reason}];
        }
    }
    
    return nil;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSURL *assetURI = loadingRequest.request.URL;
    NSString *str = assetURI.absoluteString;
    
    // Extract assetId from skd:// URL
    NSString *scheme = assetURI.scheme;
    if (![scheme isEqualToString:@"skd"]) {
        return NO;
    }
    
    // Extract assetId (last 36 chars or use videoId if available)
    if (str.length >= 36) {
        _assetId = [str substringFromIndex:str.length - 36];
    } else {
        _assetId = str;
    }
    
    NSLog(@"Processing FairPlay request for asset: %@", _assetId);
    
    // Get certificate
    NSError *certError;
    NSData *certificate = [self getAppCertificate:_assetId error:&certError];
    
    if (certError || !certificate) {
        NSLog(@"Failed to get certificate: %@", certError);
        [loadingRequest finishLoadingWithError:certError ?: [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorClientCertificateRejected userInfo:nil]];
        return YES;
    }
    
    NSLog(@"Certificate loaded: %lu bytes", (unsigned long)certificate.length);
    
    // Generate SPC
    NSData *requestBytes;
    NSError *spcError;
    
    @try {
        requestBytes = [loadingRequest streamingContentKeyRequestDataForApp:certificate 
                                                          contentIdentifier:[str dataUsingEncoding:NSUTF8StringEncoding] 
                                                                    options:nil 
                                                                      error:&spcError];
    }
    @catch (NSException* excp) {
        NSLog(@"Exception generating SPC: %@", excp);
        [loadingRequest finishLoadingWithError:nil];
        return YES;
    }
    
    if (spcError || !requestBytes) {
        NSLog(@"Failed to generate SPC: %@", spcError);
        [loadingRequest finishLoadingWithError:spcError];
        return YES;
    }
    
    NSLog(@"SPC generated: %lu bytes", (unsigned long)requestBytes.length);
    
    // Get CKC from license server
    NSError *licenseError;
    NSData *responseData = [self getContentKeyFromLicenseServerWithRequest:requestBytes error:&licenseError];
    
    if (responseData && responseData.length > 0) {
        NSLog(@"CKC received: %lu bytes", (unsigned long)responseData.length);
        AVAssetResourceLoadingDataRequest *dataRequest = loadingRequest.dataRequest;
        [dataRequest respondWithData:responseData];
        [loadingRequest finishLoading];
    } else {
        NSLog(@"Failed to get CKC: %@", licenseError);
        [loadingRequest finishLoadingWithError:licenseError ?: [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:nil]];
    }
    
    return YES;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForRenewalOfRequestedResource:(AVAssetResourceRenewalRequest *)renewalRequest {
    return [self resourceLoader:resourceLoader shouldWaitForLoadingOfRequestedResource:renewalRequest];
}

@end
