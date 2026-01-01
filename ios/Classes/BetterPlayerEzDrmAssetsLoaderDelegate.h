// // Copyright 2017 The Chromium Authors. All rights reserved.
// // Use of this source code is governed by a BSD-style license that can be
// // found in the LICENSE file.

// #import <Foundation/Foundation.h>
// #import <AVKit/AVKit.h>
// #import <AVFoundation/AVFoundation.h>

// @interface BetterPlayerEzDrmAssetsLoaderDelegate : NSObject

// @property(readonly, nonatomic) NSURL* certificateURL;
// @property(readonly, nonatomic) NSURL* licenseURL;
// - (instancetype)init:(NSURL *)certificateURL withLicenseURL:(NSURL *)licenseURL;

// @end


// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Foundation/Foundation.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

@interface BetterPlayerEzDrmAssetsLoaderDelegate : NSObject

@property(readonly, nonatomic) NSURL* certificateURL;
@property(readonly, nonatomic) NSURL* licenseURL;
@property(readonly, nonatomic) NSDictionary* headers;
@property(readonly, nonatomic) NSString* videoId;
@property(readonly, nonatomic) NSString* libraryId;

- (instancetype)init:(NSURL *)certificateURL 
     withLicenseURL:(NSURL *)licenseURL 
            headers:(NSDictionary *)headers
            videoId:(NSString *)videoId 
          libraryId:(NSString *)libraryId;

@end
