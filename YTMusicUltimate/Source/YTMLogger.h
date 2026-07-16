#import <Foundation/Foundation.h>

@interface YTMLogger : NSObject

+ (NSString *)logFilePath;
+ (void)log:(NSString *)format, ...;
+ (void)clearLog;
+ (void)setupCrashReporter;

@end
