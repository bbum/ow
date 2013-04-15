//
//  OwParseBinaryData.m
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import "OwBinFile.h"
#import "OwParseBinaryData.h"
#import "DDCommandLineInterface.h"

@interface OwParseBinaryData()
@property(nonatomic) BOOL csv;
@end

@implementation OwParseBinaryData
- (NSArray*)subcommandNameAndSynonyms
{
	return [NSArray arrayWithObjects: @"bin", nil];
}

- (NSString*)subcommandUsage
{
	return @"... bin [options] file1 [file2 ...]\n"
	"	Parses and summarizes Owon bin files.\n"
    "     --csv      Convert file to CSV (writes new in same directory as .bin)";
}

- (void) application: (DDCliApplication *) app
    willParseOptions: (DDGetoptLongParser *) optionsParser;
{
    DDGetoptOption optionTable[] =
    {
        {@"csv", 0, DDGetoptNoArgument},
        {nil,           0,      0},
    };
    [optionsParser addOptionsFromTable: optionTable];
}

- (int) application: (DDCliApplication *) app
   runWithArguments: (NSArray *) arguments;
{
	int exitValue = 0;
    
    if ([arguments count] < 1) {
        ddfprintf(stderr, @"%@: Must specify a file (or files) to process.\n", DDCliApp);
        ddfprintf(stderr, @"Try `%@ --help' for more information.\n",
                  DDCliApp);
        return EX_USAGE;
    }
    
    if (_csv) {
        NSLog(@"WARNING:  csv conversion not yet supported.");
    }
    
    [arguments enumerateObjectsUsingBlock:^(NSString* arg, NSUInteger idx, BOOL *stop) {
        NSURL *fileURL = [NSURL fileURLWithPath:arg];
        fileURL = [fileURL URLByStandardizingPath];
        NSError *error;
        
        NSDictionary *fileResourceValues = [fileURL resourceValuesForKeys:@[NSURLIsDirectoryKey] error:&error];
        if (!fileResourceValues) {
            NSLog(@"Failed to load %@ because;\n%@", fileURL, error);
            return;
        }
        
        NSArray* files;
        if ([[fileResourceValues objectForKey:NSURLIsDirectoryKey] boolValue]) {
            NSFileManager *fileManager = [NSFileManager defaultManager];
            files = [fileManager contentsOfDirectoryAtURL:fileURL includingPropertiesForKeys:@[] options:0 error:&error];
            if (!files) {
                NSLog(@"Failed to load %@ because;\n%@", fileURL, error);
                return;
            }
        } else {
            files = @[fileURL];
        }
        
        for(NSURL *aFile in files)
        {
            if (![[aFile pathExtension] isEqualToString:@"bin"]) continue;
            OwBinFile *binFile = [OwBinFile binFileWithContentsOfURL:aFile error:&error];
            if (!binFile) {
                NSLog(@"Failed to load %@ because;\n%@", aFile, error);
                return;
            }
            NSLog(@"%@", binFile);
        }
    }];
    
    return exitValue;
}
@end
