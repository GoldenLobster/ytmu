#import "YTMLogger.h"

static void handleUncaughtException(NSException *exception) {
    NSString *name = [exception name];
    NSString *reason = [exception reason];
    NSArray *symbols = [exception callStackSymbols];
    
    NSString *crashLog = [NSString stringWithFormat:@"\n=== CRASH DETECTED ===\nName: %@\nReason: %@\nCall Stack:\n%@\n======================\n",
                          name, reason, [symbols componentsJoinedByString:@"\n"]];
    
    NSLog(@"[YTMUltimate] CRASH DETECTED: %@", crashLog);
    
    NSString *filePath = [YTMLogger logFilePath];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    if (!fileHandle) {
        [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    }
    
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[crashLog dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
}

@implementation YTMLogger

+ (NSString *)logFilePath {
    NSString *docsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docsDir stringByAppendingPathComponent:@"YTMUltimate.log"];
}

+ (void)log:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[YTMUltimate] %@", message);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    NSString *filePath = [self logFilePath];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    if (!fileHandle) {
        [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    }
    
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
}

+ (void)clearLog {
    NSString *filePath = [self logFilePath];
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
}

+ (void)setupCrashReporter {
    NSSetUncaughtExceptionHandler(&handleUncaughtException);
}

@end
