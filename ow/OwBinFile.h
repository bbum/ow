//
//  OwBinFile.h
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface OwBinFile : NSObject
+ (instancetype) binFileWithContentsOfURL:(NSURL*)anURL error:(NSError**)error;

@property(nonatomic,copy,readonly) NSString* deviceIdentifier;
@property(nonatomic, readonly) NSInteger fileLength;
@property(nonatomic,copy,readonly) NSString* channelIdentifier;
@property(nonatomic, readonly) NSInteger blockLength;

@property(nonatomic, readonly) BOOL extendedCapture;
@property(nonatomic, readonly) BOOL deepMemoryCapture;
@property(nonatomic, readonly) BOOL deepMemoryCapable;

@property(nonatomic, readonly) BOOL hasBlockOffset;
@property(nonatomic, readonly) NSInteger blockOffset;

@property(nonatomic, readonly) NSInteger collectionPoint;
@property(nonatomic, readonly) NSInteger collectionPointCount;

@property(nonatomic, readonly) NSInteger slowScanningRange;
@property(nonatomic, readonly) NSInteger timeDivisor;

@property(nonatomic, readonly) NSInteger zeroPoint;
@property(nonatomic, readonly) NSInteger voltsDivisor;

@property(nonatomic, readonly) NSInteger attenuation;
@property(nonatomic, readonly) CGFloat timeMultiplier;
@property(nonatomic, readonly) CGFloat frequency;
@property(nonatomic, readonly) CGFloat period;
@property(nonatomic, readonly) CGFloat voltsMultiplier;

@end
