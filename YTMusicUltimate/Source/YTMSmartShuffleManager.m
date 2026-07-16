#import "YTMSmartShuffleManager.h"
#import <objc/runtime.h>

// Forward class declarations for static analyzer
@interface YTIPlaylistPanelVideoRenderer : NSObject
@property (nonatomic, copy) NSString *videoId;
@end

@interface YTQueueItem : NSObject
@property (nonatomic, strong) YTIPlaylistPanelVideoRenderer *videoRenderer;
@end

@interface YTQueueAutoplayController : NSObject
- (NSArray *)autoplayItems;
- (void)fetchNextItems;
@end

@interface YTQueueController : NSObject
- (unsigned long long)nowPlayingIndex;
- (NSArray *)playbackQueueItems;
- (void)insertQueueItems:(NSArray *)items atIndex:(unsigned long long)index;
- (YTQueueAutoplayController *)queueAutoplayController;
@end

#define SMART_SHUFFLE_TAG "YTMSmartShuffleTag"

// Tag helper functions
static BOOL YTMIsSmartShuffleRecommendation(id queueItem) {
    if (!queueItem) return NO;
    return [objc_getAssociatedObject(queueItem, SMART_SHUFFLE_TAG) boolValue];
}

static void YTMSetSmartShuffleRecommendation(id queueItem, BOOL isRec) {
    if (!queueItem) return;
    objc_setAssociatedObject(queueItem, SMART_SHUFFLE_TAG, @(isRec), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation YTMSmartShuffleManager

+ (instancetype)sharedManager {
    static YTMSmartShuffleManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _insertedVideoIDs = [[NSMutableSet alloc] init];
        _recommendationInterval = 3; // Default interval of 3 normal songs
        _isPerformingSmartShuffleInsertion = NO;
        _currentPlaylistID = nil;
    }
    return self;
}

// Read Preference from YTMusicUltimate defaults dictionary
- (BOOL)isSmartShuffleActive {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [dict[@"smartShuffleEnabled"] boolValue];
}

- (void)setIsSmartShuffleActive:(BOOL)active {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[defaults dictionaryForKey:@"YTMUltimate"]];
    dict[@"smartShuffleEnabled"] = @(active);
    [defaults setObject:dict forKey:@"YTMUltimate"];
    [defaults synchronize];
}

- (void)resetState {
    NSLog(@"[SmartShuffle] Resetting manager tracking state.");
    [self.insertedVideoIDs removeAllObjects];
    self.currentPlaylistID = nil;
}

- (void)handleTrackChangeInQueueController:(YTQueueController *)controller {
    if (![self isSmartShuffleActive]) return;
    if (self.isPerformingSmartShuffleInsertion) return;
    
    NSArray *queueItems = [controller playbackQueueItems];
    if (queueItems.count == 0) return;
    
    // 1. Detect Queue Identity Change & Reset State
    id firstItem = queueItems[0];
    NSString *firstVideoID = nil;
    if ([firstItem respondsToSelector:@selector(videoRenderer)]) {
        id renderer = [firstItem performSelector:@selector(videoRenderer)];
        if ([renderer respondsToSelector:@selector(videoId)]) {
            firstVideoID = [renderer performSelector:@selector(videoId)];
        }
    }
    
    if (firstVideoID && ![firstVideoID isEqualToString:self.currentPlaylistID]) {
        [self resetState];
        self.currentPlaylistID = firstVideoID;
    }
    
    unsigned long long nowPlayingIndex = [controller nowPlayingIndex];
    if (nowPlayingIndex >= queueItems.count) return;
    
    // 2. Scan Queue Spacing
    NSUInteger normalTrackCount = 0;
    BOOL recommendationFound = NO;
    for (NSUInteger idx = nowPlayingIndex + 1; idx < queueItems.count; idx++) {
        id item = queueItems[idx];
        if (YTMIsSmartShuffleRecommendation(item)) {
            recommendationFound = YES;
            break;
        } else {
            normalTrackCount++;
        }
    }
    
    // If a recommendation is already scheduled within the interval, do nothing
    if (recommendationFound && (normalTrackCount < self.recommendationInterval)) {
        return;
    }
    
    // If spacing is already filled or no recommendation is upcoming, insert one
    // Target position: nowPlayingIndex + recommendationInterval + 1
    unsigned long long insertIndex = nowPlayingIndex + self.recommendationInterval + 1;
    if (insertIndex > queueItems.count) {
        insertIndex = queueItems.count;
    }
    
    // 3. Find Unused Recommendation
    NSMutableSet *existingIDs = [NSMutableSet set];
    for (id item in queueItems) {
        if ([item respondsToSelector:@selector(videoRenderer)]) {
            id renderer = [item performSelector:@selector(videoRenderer)];
            if ([renderer respondsToSelector:@selector(videoId)]) {
                NSString *vId = [renderer performSelector:@selector(videoId)];
                if (vId) [existingIDs addObject:vId];
            }
        }
    }
    
    id recItemToInsert = nil;
    YTQueueAutoplayController *autoplay = nil;
    if ([controller respondsToSelector:@selector(queueAutoplayController)]) {
        autoplay = [controller queueAutoplayController];
    }
    
    if (autoplay && [autoplay respondsToSelector:@selector(autoplayItems)]) {
        NSArray *recItems = [autoplay autoplayItems];
        for (id recItem in recItems) {
            if ([recItem respondsToSelector:@selector(videoRenderer)]) {
                id renderer = [recItem performSelector:@selector(videoRenderer)];
                if ([renderer respondsToSelector:@selector(videoId)]) {
                    NSString *vId = [renderer performSelector:@selector(videoId)];
                    if (vId && ![existingIDs containsObject:vId]) {
                        recItemToInsert = recItem;
                        break;
                    }
                }
            }
        }
    }
    
    // 4. Perform Main-Thread Safe Insertion or Fetch recommendations
    if (recItemToInsert) {
        YTMSetSmartShuffleRecommendation(recItemToInsert, YES);
        
        NSString *insertedID = nil;
        id renderer = [recItemToInsert performSelector:@selector(videoRenderer)];
        if ([renderer respondsToSelector:@selector(videoId)]) {
            insertedID = [renderer performSelector:@selector(videoId)];
        }
        if (insertedID) {
            [self.insertedVideoIDs addObject:insertedID];
        }
        
        self.isPerformingSmartShuffleInsertion = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [controller insertQueueItems:@[recItemToInsert] atIndex:insertIndex];
                NSLog(@"[SmartShuffle] Inserted recommendation videoID: %@ at index: %llu", insertedID, insertIndex);
            } @catch (NSException *exception) {
                NSLog(@"[SmartShuffle] Queue insertion failed: %@", exception);
            } @finally {
                self.isPerformingSmartShuffleInsertion = NO;
            }
        });
    } else {
        // Cache empty, trigger next continuation fetch
        if (autoplay && [autoplay respondsToSelector:@selector(fetchNextItems)]) {
            NSLog(@"[SmartShuffle] Recommendation cache exhausted, fetching next items...");
            [autoplay fetchNextItems];
        }
    }
}

- (void)handleRecommendationsLoaded:(YTQueueController *)controller {
    // When autoplay controller yields new items, re-check track changes to insert if needed
    [self handleTrackChangeInQueueController:controller];
}

@end
