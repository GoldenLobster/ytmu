#import "YTMLogger.h"

static void handleUncaughtException(NSException *exception) {
    NSString *name = [exception name];
    NSString *reason = [exception reason];
    NSArray *symbols = [exception callStackSymbols];
    
    NSString *crashLog = [NSString stringWithFormat:@"\n=== CRASH DETECTED ===\nName: %@\nReason: %@\nCall Stack:\n%@\n======================\n",
                          name, reason, [symbols componentsJoinedByString:@"\n"]];
    
    NSLog(@"[YTMUltimate] CRASH DETECTED: %@", crashLog);
    
    NSString *filePath = [YTMLogger logFilePath];
    NSString *existingContent = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    if (!existingContent) existingContent = @"";
    NSString *newContent = [existingContent stringByAppendingString:crashLog];
    [newContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
    NSString *existingContent = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
    if (!existingContent) existingContent = @"";
    NSString *newContent = [existingContent stringByAppendingString:logLine];
    
    NSError *error = nil;
    BOOL success = [newContent writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!success) {
        NSLog(@"[YTMUltimate] Failed to write to log file: %@", error);
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
