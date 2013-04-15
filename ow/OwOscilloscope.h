//
//  OwOscilloscope.h
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface OwOscilloscope : NSObject
+ (instancetype)networkOscilloscopeWithHostname:(NSString*)hostname port:(NSInteger)port;

- (void)connect;
- (void)disconnect;

- (void)downloadScreenshot:(NSString*)filePath;
- (void)downloadData:(NSString*)filePath;

@end
