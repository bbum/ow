//
//  OwNetworkLoader.m
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import "OwBinFile.h"
#import "DDCommandLineInterface.h"
#import "OwNetworkLoader.h"
#import "OwOscilloscope.h"

@interface OwNetworkLoader()
@property(nonatomic) NSString *host;
@property(nonatomic) NSString *port;
@property(nonatomic) NSString *name;
@property(nonatomic) BOOL write;

@property(nonatomic) NSInteger numericPort;

@property(nonatomic, strong) OwOscilloscope *scope;

- (void) processConnectionCommands;
@end

@implementation OwNetworkLoader
- (id)init
{
    self = [super init];
    if (!self) return nil;
    
    return self;
}

- (NSArray*)subcommandNameAndSynonyms
{
	return [NSArray arrayWithObjects: @"net", @"network", nil];
}

- (NSString*)subcommandUsage
{
	return @"... net {screen,data} filename\n"
	"   Downloads screenshot or binary data from Owon oscilloscope over the LAN.\n"
    "   Host / port can be specified with options or will be read from database ('host','port').\n"
    "     defaults write com.friday.ow host 10.0.1.230\n"
    "     defaults write com.friday.ow port 3000\n"
    "     --host HOST   IP address of Owon oscilloscope.\n"
    "     --port PORT#  Port #.\n"
    "     --write       Write values to defaults database.\n";
}

- (void) application: (DDCliApplication *) app
    willParseOptions: (DDGetoptLongParser *) optionsParser;
{
    DDGetoptOption optionTable[] =
    {
        {@"host", 0, DDGetoptRequiredArgument},
        {@"port", 0, DDGetoptRequiredArgument},
        {@"name", 0, DDGetoptRequiredArgument},
        {@"write", 0, DDGetoptNoArgument},
        {nil,           0,      0},
    };
    [optionsParser addOptionsFromTable: optionTable];
}

- (int) application: (DDCliApplication *) app
   runWithArguments: (NSArray *) arguments;
{
	int exitValue = 0;
    NSString *screenOrData;
    
    if ([arguments count] != 2)
    {
        ddfprintf(stderr, @"%@: Must specify one of screen or data and a filename\n", DDCliApp);
        ddfprintf(stderr, @"Try `%@ --help' for more information.\n", DDCliApp);
        return EX_USAGE;
    }
    
    screenOrData = [arguments objectAtIndex:0];
    if (![@[@"screen", @"data"] containsObject:screenOrData])
    {
        ddfprintf(stderr, @"%@: '@' was not 'screen' or 'data'.\n", DDCliApp, screenOrData);
        ddfprintf(stderr, @"Try `%@ --help' for more information.\n", DDCliApp);
        return EX_USAGE;
    }
    
    BOOL isScreen = [screenOrData isEqualToString:@"screen"];
    
    NSString *filePath = [arguments objectAtIndex:1];
    filePath = [filePath stringByStandardizingPath];
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults addSuiteNamed:@"com.friday.ow"];
    
    if (!_host) {
        _host = [userDefaults stringForKey:@"host"];
    }
    
    if (!_port) {
        _numericPort = [userDefaults integerForKey:@"port"];
    } else {
        _numericPort = [_port integerValue];
    }
    
    if (!_host || (_numericPort == 0))
    {
        ddfprintf(stderr, @"%@: Must specify host and port (or write values into defaults database).\n", DDCliApp);
        ddfprintf(stderr, @"Try `%@ --help' for more information.\n", DDCliApp);
        return EX_USAGE;
    }
    
    if (_write)
    {
        [userDefaults setValue:_host forKey:@"host"];
        [userDefaults setInteger:_numericPort forKey:@"port"];
    }
    
    _scope = [OwOscilloscope networkOscilloscopeWithHostname:_host port:_numericPort];
    [_scope connect];
    
    if (isScreen)
        [_scope downloadScreenshot:filePath];
    else
        [_scope downloadData:filePath];
    
    [[NSRunLoop currentRunLoop] run];
    
    return exitValue;
}

- (void) processConnectionCommands
{
}
@end
