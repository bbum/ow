//
//  main.m
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "DDCommandLineInterface.h"
#import "OwApp.h"

int main (__attribute__((unused)) int argc,__attribute__((unused)) const char * argv[])
{
    return DDCliAppRunWithClass([OwApp class]);
}
