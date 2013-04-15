//
//  OwBinFile.m
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import "OwBinFile.h"
#import "OwStreamingDataParser.h"

#import <CoreFoundation/CFByteOrder.h>

@interface OwBinFile()
- (instancetype)initBinFileWithContentsOfURL:(NSURL*)anURL error:(NSError**)error;
@property(nonatomic,strong) NSData* fileData;
@property(nonatomic,strong) NSData* sampleData;

- (BOOL)_parseFile:(NSError**)error;

@property(nonatomic,copy,readwrite) NSString* deviceIdentifier;
@property(nonatomic, readwrite) NSInteger fileLength;

@property(nonatomic,copy,readwrite) NSString* channelIdentifier;
@property(nonatomic, readwrite) NSInteger blockLength;

@property(nonatomic, readwrite) BOOL extendedCapture;
@property(nonatomic, readwrite) BOOL deepMemoryCapture;
@property(nonatomic, readwrite) BOOL deepMemoryCapable;

@property(nonatomic, readwrite) BOOL hasBlockOffset;
@property(nonatomic, readwrite) NSInteger blockOffset;

@property(nonatomic, readwrite) NSInteger collectionPoint;
@property(nonatomic, readwrite) NSInteger collectionPointCount;

@property(nonatomic, readwrite) NSInteger slowScanningRange;
@property(nonatomic, readwrite) NSInteger timeDivisor;

@property(nonatomic, readwrite) NSInteger zeroPoint;
@property(nonatomic, readwrite) NSInteger voltsDivisor;

@property(nonatomic, readwrite) NSInteger attenuation;
@property(nonatomic, readwrite) CGFloat timeMultiplier;
@property(nonatomic, readwrite) CGFloat frequency;
@property(nonatomic, readwrite) CGFloat period;
@property(nonatomic, readwrite) CGFloat voltsMultiplier;

@end

@implementation OwBinFile
+ (instancetype) binFileWithContentsOfURL:(NSURL*)anURL error:(NSError**)error
{
    return [[self alloc] initBinFileWithContentsOfURL:anURL error:error];
}

- (instancetype)initBinFileWithContentsOfURL:(NSURL*)anURL error:(NSError**)error;
{
    self = [super init];
    if (!self) return nil;
    
    _fileData = [NSData dataWithContentsOfURL:anURL options:NSDataReadingMappedIfSafe error:error];
    if (!_fileData) return nil;
    
    if (![self _parseFile:error]) return nil;
    
    return self;
}

static inline BOOL _deviceIsSDS(NSString *deviceIdentifier)
{
    return [deviceIdentifier hasPrefix:@"SPBS0"] ? YES : NO;
}

- (BOOL)_parseFile:(NSError**)error
{
    OwStreamingDataParser *dataParser = [OwStreamingDataParser streamingDataParserWithData:_fileData];
    
    [self setDeviceIdentifier:[dataParser readASCIIStringOfLength:6]];
    [self setFileLength:[dataParser readInt32]];
    
    [self setChannelIdentifier:[dataParser readASCIIStringOfLength:3]];

    int32_t blockLength = [dataParser readInt32];
    if (blockLength < 0) {
        int32_t extendedValue = [dataParser readInt32];
        [self setExtendedCapture:YES];
        
        [self setDeepMemoryCapture:(extendedValue & (1 << 0)) ? YES : NO];
        [self setDeepMemoryCapable:(extendedValue & (1 << 1)) ? YES : NO];
    } else {
        [self setExtendedCapture:NO];
        [self setDeepMemoryCapture:NO];
        [self setDeepMemoryCapable:NO];
    }
    [self setBlockLength:abs(blockLength)];
    
    if (_deviceIsSDS([self deviceIdentifier]))
    {
        [self setHasBlockOffset:YES];
        [self setBlockOffset:[dataParser readInt32]];
    } else {
        [self setHasBlockOffset:NO];
        [self setBlockOffset:0];
    }
    
    [self setCollectionPoint:[dataParser readInt32]];
    [self setCollectionPointCount:[dataParser readInt32]];
    [self setSlowScanningRange:[dataParser readInt32]];
    [self setTimeDivisor:[dataParser readInt32]];
    [self setZeroPoint:[dataParser readInt32]];
    [self setVoltsDivisor:[dataParser readInt32]];
    [self setAttenuation:[dataParser readInt32]];
    [self setTimeMultiplier:[dataParser readFloat]];
    [self setFrequency:[dataParser readFloat]];
    [self setPeriod:[dataParser readFloat]];
    [self setVoltsMultiplier:[dataParser readFloat]];
    
    [self setSampleData:[NSData dataWithBytesNoCopy:[dataParser currentBytePointer] length:[dataParser remainingByteCount] freeWhenDone:NO]];
    
    return YES;
}

static inline NSString *_StringFromBool(BOOL f) { return f ? @"YES" : @"NO"; }
- (NSString*)description
{
    NSMutableString *returnString = [NSMutableString stringWithFormat:@"<%@:%p Dev:%@ Len:%ld Chan:%@ Blk:%ld", [self class], self, [self deviceIdentifier], [self fileLength], [self channelIdentifier], [self blockLength]];
    [returnString appendFormat:@" Deep Capt:%@", _StringFromBool([self deepMemoryCapture])];
    [returnString appendFormat:@" Deep Capab::%@", _StringFromBool([self deepMemoryCapable])];
    [returnString appendFormat:@" Coll.Pt:%ld", [self collectionPoint]];
    [returnString appendFormat:@" Coll.Pt Ct.:%ld", [self collectionPointCount]];
    [returnString appendFormat:@" Scan Range:%ld", [self slowScanningRange]];
    [returnString appendFormat:@" Time Div.:%ld", [self timeDivisor]];
    [returnString appendFormat:@" Zero:%ld", [self zeroPoint]];
    [returnString appendFormat:@" Volts Div.:%ld", [self voltsDivisor]];
    [returnString appendFormat:@" Time Mult.:%4.2f", [self timeMultiplier]];
    [returnString appendFormat:@" Frequency:%4.2f", [self frequency]];
    [returnString appendFormat:@" Period:%4.2f", [self period]];
    [returnString appendFormat:@" Volts Mult:%4.2f", [self voltsMultiplier]];
    
    NSUInteger sampleDataLength = [[self sampleData] length];
    [returnString appendFormat:@" Data length:%ld", sampleDataLength];
    [returnString appendFormat:@" Data: %@...", [[self sampleData] subdataWithRange:NSMakeRange(0, (sampleDataLength < 15) ? sampleDataLength : 15)]];
    [returnString appendString:@">"];
    
    return returnString;
}
@end
