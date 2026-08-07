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

- (instancetype)init:(NSURL *)certificateURL withLicenseURL:(NSURL *)licenseURL {
    self = [super init];
    if (self) {
        _certificateURL = certificateURL;
        _licenseURL = licenseURL;
        
        // Extract videoId and libraryId from URL if possible
        [self extractIdsFromURL:licenseURL];
    }
    return self;
}

- (void)extractIdsFromURL:(NSURL *)url {
    NSString *path = url.path;
    NSArray *components = [path componentsSeparatedByString:@"/"];
    
    // Extract libraryId and videoId from path like /FairPlayLicense/571008/72ee526e...
    if ([path containsString:@"FairPlayLicense"]) {
        for (int i = 0; i < components.count; i++) {
            if ([components[i] isEqualToString:@"FairPlayLicense"] && i + 2 < components.count) {
                _libraryId = components[i + 1];
                _videoId = components[i + 2];
                NSLog(@"Extracted libraryId: %@, videoId: %@", _libraryId, _videoId);
                break;
            }
        }
    }
}

/*------------------------------------------
 **
 ** getCertificateData
 **
 ** Fetch certificate from server using NSURLSession
 ** ---------------------------------------*/
- (NSData *)getCertificateData:(NSError **)errorOut {
    NSLog(@"Fetching certificate from: %@", _certificateURL.absoluteString);
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *certificateData = nil;
    __block NSError *requestError = nil;
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_certificateURL];
    [request setHTTPMethod:@"GET"];
    [request setTimeoutInterval:30.0];
    
    // Add headers if available
    if (_headers) {
        for (NSString *key in _headers) {
            [request setValue:_headers[key] forHTTPHeaderField:key];
        }
    }
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            requestError = error;
            NSLog(@"Certificate request error: %@", error);
        } else if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"Certificate response: %@", responseString);
            
            // Try to parse as JSON
            NSError *jsonError;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (!jsonError && jsonResponse) {
                NSString *certBase64 = jsonResponse[@"certificate"];
                if (certBase64 && [certBase64 isKindOfClass:[NSString class]]) {
                    certificateData = [[NSData alloc] initWithBase64EncodedString:certBase64 options:0];
                    if (certificateData) {
                        NSLog(@"Successfully parsed certificate from JSON: %lu bytes", (unsigned long)certificateData.length);
                    }
                }
            } else {
                // Assume raw certificate
                certificateData = data;
                NSLog(@"Assuming raw certificate data: %lu bytes", (unsigned long)certificateData.length);
            }
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    if (errorOut && requestError) {
        *errorOut = requestError;
    }
    
    return certificateData;
}

/*------------------------------------------
 **
 ** getContentKeyFromLicenseServer
 **
 ** Takes the SPC and sends it to BunnyCDN license server.
 ** Returns CKC from JSON response.
 ** ---------------------------------------*/
- (NSData *)getContentKeyFromLicenseServerWithRequest:(NSData*)requestBytes error:(NSError **)errorOut {
    NSLog(@"Sending license request...");
    
    // Determine license URL
    NSURL *licenseURL = _licenseURL;
    if (!licenseURL && _videoId && _libraryId) {
        NSString *urlString = [NSString stringWithFormat:@"https://video.bunnycdn.com/FairPlayLicense/%@/%@", _libraryId, _videoId];
        licenseURL = [NSURL URLWithString:urlString];
        NSLog(@"Constructed license URL: %@", urlString);
    }
    
    if (!licenseURL) {
        if (errorOut) {
            *errorOut = [NSError errorWithDomain:@"FairPlay" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"No license URL available"}];
        }
        return nil;
    }
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSError *requestError = nil;
    
    // Prepare JSON request body with base64 SPC
    NSString *spcBase64 = [requestBytes base64EncodedStringWithOptions:0];
    NSDictionary *requestBody = @{@"spc": spcBase64};
    
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:requestBody options:0 error:&jsonError];
    
    if (jsonError) {
        if (errorOut) *errorOut = jsonError;
        return nil;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:licenseURL];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:jsonData];
    [request setTimeoutInterval:30.0];
    
    // Debug log
    NSString *requestBodyString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSLog(@"Sending license request to: %@", licenseURL.absoluteString);
    NSLog(@"Request body: %@", requestBodyString);
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            requestError = error;
            NSLog(@"License request error: %@", error);
        } else if (data) {
            NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"License server response (%lu bytes): %@", (unsigned long)data.length, responseString);
            
            // Check HTTP status code
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                NSLog(@"HTTP status code: %ld", (long)httpResponse.statusCode);
                
                if (httpResponse.statusCode != 200) {
                    requestError = [NSError errorWithDomain:@"FairPlay" 
                                                       code:httpResponse.statusCode 
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status %ld", (long)httpResponse.statusCode]}];
                }
            }
            
            if (!requestError) {
                // Parse JSON response
                NSError *parseError;
                NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
                
                if (!parseError && jsonResponse) {
                    NSString *ckcBase64 = jsonResponse[@"ckc"];
                    if (ckcBase64 && [ckcBase64 isKindOfClass:[NSString class]]) {
                        responseData = [[NSData alloc] initWithBase64EncodedString:ckcBase64 options:0];
                        if (responseData) {
                            NSLog(@"Successfully parsed CKC: %lu bytes", (unsigned long)responseData.length);
                        } else {
                            NSLog(@"Failed to decode base64 CKC");
                        }
                    } else if (jsonResponse[@"error"]) {
                        NSLog(@"License server error: %@", jsonResponse[@"error"]);
                    }
                } else {
                    // If not JSON, assume raw CKC
                    responseData = data;
                    NSLog(@"Assuming raw CKC: %lu bytes", (unsigned long)responseData.length);
                }
            }
        } else {
            NSLog(@"No data received from license server");
        }
        dispatch_semaphore_signal(semaphore);
    }];
    
    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    if (errorOut && requestError) {
        *errorOut = requestError;
    }
    
    return responseData;
}

/*------------------------------------------
 **
 ** getAppCertificate
 **
 ** Returns the app certificate
 ** ---------------------------------------*/
- (NSData *)getAppCertificate:(NSString *)assetId error:(NSError **)errorOut {
    return [self getCertificateData:errorOut];
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSURL *assetURI = loadingRequest.request.URL;
    NSString *str = assetURI.absoluteString;
    NSString *scheme = assetURI.scheme;
    
    if (![scheme isEqualToString:@"skd"]) {
        return NO;
    }
    
    // Extract assetId
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
