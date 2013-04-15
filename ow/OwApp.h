//
//  OwApp.h
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DDCommandLineInterface.h"

extern NSString *OwErrorDomain;

@interface OwApp : NSObject <DDCliApplicationDelegate>
+ (id) sharedInstance;
- (void) exitWithStatus:(int)status error:(NSError*)anError;
@end
