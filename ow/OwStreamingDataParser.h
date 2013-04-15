//
//  OwStreamingDataParser.h
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface OwStreamingDataParser : NSObject
+ (instancetype) streamingDataParserWithData:(NSData*)data;

@property(nonatomic, readonly) NSData *data;

@property(nonatomic) NSUInteger currentSeek;
@property(nonatomic, readonly) NSUInteger length;
@property(nonatomic, readonly) NSUInteger remainingByteCount;

- (uint8_t *)currentBytePointer;

- (NSString*)readASCIIStringOfLength:(NSUInteger)length;
- (int32_t)readInt32;
- (float)readFloat;
@end
