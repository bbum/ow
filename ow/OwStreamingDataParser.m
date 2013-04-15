//
//  OwStreamingDataParser.m
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import "OwStreamingDataParser.h"

@interface OwStreamingDataParser()
@property(nonatomic, readwrite) NSData *data;
@property(nonatomic, readwrite) uint8_t *bytes;
@end

@implementation OwStreamingDataParser
+ (instancetype) streamingDataParserWithData:(NSData*)data
{
    if (!data) return nil;

    OwStreamingDataParser *dataParser = [[self alloc] init];
    [dataParser setData:data];
    return dataParser;
}

- (void) setData:(NSData *)data
{
    _data = data;
    [self setBytes:(uint8_t *)[data bytes]];
    [self setCurrentSeek:0];
}

- (NSUInteger) length
{
    return [_data length];
}

- (NSString*)readASCIIStringOfLength:(NSUInteger)length
{
    if ( (_currentSeek + length) > [self length] ) return nil;
    
    NSString *returnString = [[NSString alloc] initWithBytes:[self currentBytePointer] length:length encoding:NSASCIIStringEncoding];
    _currentSeek = _currentSeek + length;
    return returnString;
}

- (uint8_t *)currentBytePointer
{
    return _bytes + _currentSeek;
}

- (NSUInteger) remainingByteCount
{
    return [self length] - _currentSeek;
}

- (int32_t)readInt32
{
    static unsigned int _dataSize = 4;
    
    if ( (_currentSeek + _dataSize) > [self length] ) return 0;
    
    int32_t returnValue;
    assert(sizeof(_dataSize) == sizeof(returnValue));

    uint8_t *currentByte = [self currentBytePointer];
    
    returnValue =
    ((int32_t)(currentByte[3]) << 24) |
    ((int32_t)(currentByte[2]) << 16) |
    ((int32_t)(currentByte[1]) << 8) |
    ((int32_t)(currentByte[0]));
    
    _currentSeek = _currentSeek + _dataSize;
    
    return returnValue;
}

- (float)readFloat
{
    static unsigned int _dataSize = 4;

    if ( (_currentSeek + _dataSize) > [self length] ) return 0;

    float returnValue;
    assert(sizeof(_dataSize) == sizeof(returnValue));
    
    memcpy(&returnValue, [self currentBytePointer], _dataSize);
    
    _currentSeek = _currentSeek + _dataSize;

    return returnValue;
}
@end
