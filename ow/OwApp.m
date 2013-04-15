//
//  OwApp.m
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OwAbstractSubcommand.h"
#import "OwParseBinaryData.h"
#import "OwNetworkLoader.h"

#import "OwApp.h"

NSString *OwErrorDomain = @"Ow Error";

@interface OwApp()
@property(nonatomic, strong) NSMutableDictionary* subcommandRegistry;
@property(nonatomic, strong) NSMutableArray* subcommandInventory;
@property(nonatomic) BOOL verbose;
@property(nonatomic) BOOL help;
@end

@implementation OwApp
static OwApp* _sharedInstance;

+ (id)sharedInstance
{
	assert( _sharedInstance ); // set in -init by way of DDCli
	return _sharedInstance;
}

- (id)init
{
    self = [super init];
    if (self) {
		_sharedInstance = self;
		_subcommandRegistry = [NSMutableDictionary new];
		_subcommandInventory = [NSMutableArray new];
		[self _registerSubcommandClass: [OwParseBinaryData class]];
		[self _registerSubcommandClass: [OwNetworkLoader class]];
    }
    return self;
}

- (void)_registerSubcommandClass:(Class)aClass
{
	id<OwSubcommandP> subcommand = [aClass new];
	
	for(NSString* subcommandName in [subcommand subcommandNameAndSynonyms])
	{
		[_subcommandRegistry setObject:subcommand forKey:subcommandName];
	}
	[_subcommandInventory addObject:subcommand];
}

- (void) printUsage: (FILE *) stream;
{
    ddfprintf(stream, @"%@: Usage [OPTIONS] <sub-command> [...]\n", DDCliApp);
}

- (void) printHelp;
{
    [self printUsage: stdout];
    printf("\n"
		   "--verbose       Turn on verbose logging.\n"
		   "--help          Show this help message.\n"
           "\n"
           "Subcommands:\n"
           );
	for(id<OwSubcommandP> subcommand in _subcommandInventory)
	{
        NSFileHandle *standardOut = [NSFileHandle fileHandleWithStandardOutput];
		[standardOut writeData:[[subcommand subcommandUsage] dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES]];
		printf("\n\n");
	}
}

- (void) application: (DDCliApplication *) app willParseOptions: (DDGetoptLongParser *) optionsParser;
{
    DDGetoptOption optionTable[] =
    {
        {@"verbose", 'v', DDGetoptNoArgument},
        {@"help", 'h', DDGetoptNoArgument},
        {nil,           0,      0},
    };
    [optionsParser addOptionsFromTable: optionTable];
}

- (int) application: (DDCliApplication *) app
   runWithArguments: (NSArray *) arguments;
{
    if (_help)
    {
        [self printHelp];
        return EXIT_SUCCESS;
    }
    
    if ([arguments count] < 1)
    {
        ddfprintf(stderr, @"%@: Must specify a sub-command.\n", DDCliApp);
        [self printUsage: stderr];
        ddfprintf(stderr, @"Try `%@ --help' for more information.\n",
                  DDCliApp);
        return EX_USAGE;
    }
    
	NSString* subcommand = [arguments objectAtIndex:0];
	id<OwSubcommandP> subcommandInstance = [_subcommandRegistry objectForKey:subcommand];
	if ( subcommandInstance == nil )
	{
		ddfprintf(stderr, @"%@: sub-command '%@' not recognized (see --help).\n", DDCliApp, subcommand);
		[self printUsage: stderr];
		return EX_USAGE;
	}
    return [DDCliApp runWithDelegate:subcommandInstance arguments:arguments];
}

- (void) exitWithStatus:(int)status error:(NSError*)anError;
{
	if ( anError )
	{
		NSLog( @"**ERROR**: %@", anError );
	}
	exit( status );
}
@end

