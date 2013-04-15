//
//  OwOscilloscope.m
//  ow
//
//  Created by Bill Bumgarner on 4/6/13.
//  Copyright (c) 2013 Bill Bumgarner. All rights reserved.
//

#import "OwOscilloscope.h"
#import "OwStreamingDataParser.h"

@interface OwOscilloscope() <NSStreamDelegate>
- (instancetype)initWithHostname:(NSString*)hostname port:(NSInteger)port;

@property(nonatomic, copy) NSString *hostname;
@property(nonatomic, strong) NSHost *host;
@property(nonatomic) NSInteger port;

@property(nonatomic) BOOL connected;
@property(nonatomic, strong) NSInputStream *streamFromOscilloscope;
@property(nonatomic, strong) NSOutputStream *streamToOscilloscope;

@property(nonatomic, strong) dispatch_queue_t operationSerializationQueue;

@property(nonatomic, strong) NSFileHandle *outputFileHandle;

- (void)connect;

- (void)readAvailableData;

@property(nonatomic) BOOL hasProcessedHeader;
@property(nonatomic) NSUInteger expectedDataLength;
@property(nonatomic) NSUInteger currentDataLength;
@property(nonatomic) NSMutableData *temporaryDataAccumulator;
@end

@implementation OwOscilloscope
+ (instancetype)networkOscilloscopeWithHostname:(NSString*)hostname port:(NSInteger)port
{
    return [[self alloc] initWithHostname:hostname port:port];
}

- (instancetype)initWithHostname:(NSString*)hostname port:(NSInteger)port;
{
    self = [super init];
    if (!self) return nil;
    
    _hostname = hostname;
    _port = port;
    
    _operationSerializationQueue = dispatch_queue_create("OwOscilliscope Serial Queue", DISPATCH_QUEUE_SERIAL);
    
    return self;
}

- (void)connect
{
    if ([self connected]) return;
    
    _host = [NSHost hostWithName:_hostname];
    
    NSInputStream *inputStream;
    NSOutputStream *outputStream;
    [NSStream getStreamsToHost:_host port:_port inputStream:&inputStream outputStream:&outputStream];

    _streamToOscilloscope = outputStream;
    _streamFromOscilloscope = inputStream;

    [_streamToOscilloscope setDelegate:self];
    [_streamFromOscilloscope setDelegate:self];
    
    [_streamToOscilloscope scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_streamFromOscilloscope scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    [_streamToOscilloscope open];
    [_streamFromOscilloscope open];
    
    _connected = YES;
}

- (void)disconnect
{
    if (![self connected]) return;

    [_streamToOscilloscope close];
    [_streamFromOscilloscope close];
    
    [_streamToOscilloscope removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_streamFromOscilloscope removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

    _streamToOscilloscope = nil;
    _streamFromOscilloscope = nil;
    
    _connected = NO;
}

- (void)downloadCommandResults:(const char *)command toFile:(NSString *)filePath
{
    dispatch_sync(_operationSerializationQueue, ^{
        assert(!_outputFileHandle); // only write to one at a time
        NSInteger written = [_streamToOscilloscope write:(uint8_t *)command maxLength:strlen(command)];
        if (written == -1) {
            NSLog(@"ERROR sending command '%s': %@", command, [_streamToOscilloscope streamError]);
            exit(1);
        }
        
        if (![[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil]) {
            NSLog(@"ERROR: Failed to create or zero file at '%@'", filePath);
            exit(1);
        }
        
        _outputFileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
        if(!_outputFileHandle) {
            NSLog(@"ERROR writing to '%@'.", filePath);
            exit(1);
        }
        
        NSLog(@"Writing to %@....", filePath);
    });
}

- (void)downloadScreenshot:(NSString*)filePath
{
    const char *command = "STARTBMP\n";
    [self downloadCommandResults:command toFile:filePath];
}

- (void)downloadData:(NSString*)filePath
{
    const char *command = "STARTBIN\n";
    [self downloadCommandResults:command toFile:filePath];
}

- (void)_processDataHeader:(uint8_t *)header
{
    NSData *data = [[NSData alloc] initWithBytesNoCopy:header length:12 freeWhenDone:NO];
    OwStreamingDataParser *parser = [OwStreamingDataParser streamingDataParserWithData:data];
    _expectedDataLength = [parser readInt32];
    [parser readInt32]; // unused
    int32_t flag = [parser readInt32];
    
    if (flag > 128) {
        NSLog(@"Stream is a deep memory dump. Can't handle.");
        exit(1);
    }
    _hasProcessedHeader = YES;
    _currentDataLength = 0;
    
    NSLog(@"Expected %ld bytes.", (unsigned long)_expectedDataLength);
    
    [data self];
}

- (void)readAvailableData
{
    dispatch_sync(_operationSerializationQueue, ^{
        while([_streamFromOscilloscope hasBytesAvailable]) {
            uint8_t buffer[1024];
            NSInteger bytesRead;
            bytesRead = [_streamFromOscilloscope read:buffer maxLength:sizeof(buffer)];
            if (bytesRead > 0) {
                if (!_hasProcessedHeader) {
                    if (_temporaryDataAccumulator)
                    {
                        [_temporaryDataAccumulator appendBytes:buffer length:bytesRead];
                        if ([_temporaryDataAccumulator length] > 12) {
                            [self _processDataHeader:(uint8_t *)[_temporaryDataAccumulator bytes]];
                            [_outputFileHandle writeData:_temporaryDataAccumulator];
                            _currentDataLength = [_temporaryDataAccumulator length];
                            _temporaryDataAccumulator = nil;
                        }
                    } else {
                        if (bytesRead >= 12)
                        {
                            [self _processDataHeader:buffer];
                            if (bytesRead > 12)
                            {
                                NSData *data = [[NSData alloc] initWithBytesNoCopy:buffer+12 length:bytesRead-12 freeWhenDone:NO];
                                [_outputFileHandle writeData:data];
                                _currentDataLength = [data length];
                                [data self];
                            }
                        }
                    }
                
                } else {
                    NSData *data = [[NSData alloc] initWithBytesNoCopy:buffer length:bytesRead freeWhenDone:NO];
                    [_outputFileHandle writeData:data];
                    _currentDataLength = _currentDataLength + [data length];

                    if (_currentDataLength > _expectedDataLength) {
                        NSLog(@"ERROR: received more data than expected (%ld > %ld).", (unsigned long)_currentDataLength, (unsigned long)_expectedDataLength);
                        exit(1);
                    } else if (_currentDataLength == _expectedDataLength) {
                        NSLog(@"Successfully wrote %ld bytes (as expected).", (unsigned long)_currentDataLength);
                        [_outputFileHandle closeFile];
                        _outputFileHandle = nil;
                        exit(0);
                    } else {
                        fprintf(stdout, ".");
                        fflush(stdout);
                    }
                }
            }
        }
    });
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventNone:
            break;
        case NSStreamEventOpenCompleted:
            break;
        case NSStreamEventHasBytesAvailable:
            assert(aStream == _streamFromOscilloscope);
            [self readAvailableData];
            break;
        case NSStreamEventHasSpaceAvailable:
            break;
        case NSStreamEventErrorOccurred:
            NSLog(@"Stream error %@", [aStream streamError]);
            exit(1);
            break;
        case NSStreamEventEndEncountered:
            break;
    }
}

@end
