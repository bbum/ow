//
//  OwAbstractSubcommand.h
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DDCliApplication.h"

@protocol OwSubcommandP <NSObject, DDCliApplicationDelegate>
@required
- (NSArray*)subcommandNameAndSynonyms;
- (NSString*)subcommandUsage;
@end

@interface OwAbstractSubcommand : NSObject

@end
