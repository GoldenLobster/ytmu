#import "YTMSmartShuffleManager.h"
#import <objc/runtime.h>
#import "YTMLogger.h"

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
- (void)removeQueueItemAtIndex:(unsigned long long)index;
- (YTQueueAutoplayController *)queueAutoplayController;
- (id)queueItemsController;
- (void)fetchAutoplaySectionIfNeeded;
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
    [YTMLogger log:@"[SmartShuffle] Resetting manager tracking state."];
    [self.insertedVideoIDs removeAllObjects];
    self.currentPlaylistID = nil;
    self.originalQueueSize = 0;
}

- (void)handleTrackChangeInQueueController:(YTQueueController *)controller {
    [YTMLogger log:@"[SmartShuffle] handleTrackChangeInQueueController entered."];
    if (![self isSmartShuffleActive]) {
        [YTMLogger log:@"[SmartShuffle] smartShuffleEnabled is OFF. Returning."];
        return;
    }
    if (self.isPerformingSmartShuffleInsertion) {
        [YTMLogger log:@"[SmartShuffle] isPerformingSmartShuffleInsertion is TRUE. Returning."];
        return;
    }
    
    NSArray *queueItems = nil;
    if ([controller respondsToSelector:@selector(playbackQueueItems)]) {
        queueItems = [controller playbackQueueItems];
    }
    
    [YTMLogger log:@"[SmartShuffle] playbackQueueItems count: %lu", (unsigned long)queueItems.count];
    if (queueItems.count == 0) {
        // Fallback to queueItemsController -> queueItems if playbackQueueItems is empty
        if ([controller respondsToSelector:@selector(queueItemsController)]) {
            id itemsController = [controller queueItemsController];
            if ([itemsController respondsToSelector:@selector(queueItems)]) {
                queueItems = [itemsController performSelector:@selector(queueItems)];
                [YTMLogger log:@"[SmartShuffle] Fallback queueItems count from itemsController: %lu", (unsigned long)queueItems.count];
            }
        }
    }
    
    if (queueItems.count == 0) {
        [YTMLogger log:@"[SmartShuffle] Queue items are empty. Returning."];
        return;
    }
    
    // 1. Detect Queue Identity Change & Reset State
    id firstItem = queueItems[0];
    NSString *firstVideoID = nil;
    if ([firstItem respondsToSelector:@selector(videoRenderer)]) {
        id renderer = [firstItem performSelector:@selector(videoRenderer)];
        if ([renderer respondsToSelector:@selector(videoId)]) {
            firstVideoID = [renderer performSelector:@selector(videoId)];
        }
    }
    
    [YTMLogger log:@"[SmartShuffle] firstVideoID: %@, currentPlaylistID: %@", firstVideoID, self.currentPlaylistID];
    if (firstVideoID && ![firstVideoID isEqualToString:self.currentPlaylistID]) {
        [self resetState];
        self.currentPlaylistID = firstVideoID;
        self.originalQueueSize = queueItems.count;
        [YTMLogger log:@"[SmartShuffle] Set originalQueueSize: %lu", (unsigned long)self.originalQueueSize];
    }
    
    // Auto-correct queue shrinkage
    if (self.originalQueueSize > queueItems.count) {
        [YTMLogger log:@"[SmartShuffle] Queue shrunk. Adjusting originalQueueSize from %lu to %lu", (unsigned long)self.originalQueueSize, (unsigned long)queueItems.count];
        self.originalQueueSize = queueItems.count;
    }
    
    // Fallback if originalQueueSize was not set
    if (self.originalQueueSize == 0) {
        self.originalQueueSize = queueItems.count;
    }
    
    unsigned long long nowPlayingIndex = [controller nowPlayingIndex];
    [YTMLogger log:@"[SmartShuffle] nowPlayingIndex: %llu", nowPlayingIndex];
    if (nowPlayingIndex >= queueItems.count) {
        [YTMLogger log:@"[SmartShuffle] nowPlayingIndex is out of bounds or NSNotFound. Returning."];
        return;
    }
    
    // 2. Scan Queue Spacing
    NSUInteger normalTrackCount = 0;
    BOOL recommendationFound = NO;
    for (NSUInteger idx = nowPlayingIndex + 1; idx < queueItems.count; idx++) {
        id item = queueItems[idx];
        if (YTMIsSmartShuffleRecommendation(item)) {
            recommendationFound = YES;
            break;
        } else {
            // Only count untagged tracks that are part of the original playlist as normal
            if (idx < self.originalQueueSize) {
                normalTrackCount++;
            }
        }
    }
    
    [YTMLogger log:@"[SmartShuffle] Spacing scan: normalTrackCount=%lu, recommendationFound=%d", (unsigned long)normalTrackCount, recommendationFound];
    
    // If a recommendation is already scheduled within the interval, do nothing
    if (recommendationFound && (normalTrackCount <= self.recommendationInterval)) {
        [YTMLogger log:@"[SmartShuffle] Recommendation already scheduled within interval. Returning."];
        return;
    }
    
    // We need to insert a recommendation after the interval (3 normal songs)
    unsigned long long insertIndex = nowPlayingIndex + self.recommendationInterval + 1;
    if (insertIndex > queueItems.count) {
        insertIndex = queueItems.count;
    }
    [YTMLogger log:@"[SmartShuffle] Target insertion index: %llu", insertIndex];
    
    // 3. Find Unused Recommendation (Strategy A: queue end, Strategy B: autoplay cache)
    id recItemToInsert = nil;
    NSUInteger recIndex = NSNotFound;
    
    // Strategy A: Check end of the queue for native recommendations
    for (NSUInteger idx = queueItems.count - 1; idx >= self.originalQueueSize; idx--) {
        if (idx < queueItems.count) {
            id item = queueItems[idx];
            if (!YTMIsSmartShuffleRecommendation(item)) {
                recItemToInsert = item;
                recIndex = idx;
                break;
            }
        }
    }
    
    // Strategy B: If no native recommendations at the end, check autoplay cache
    if (!recItemToInsert) {
        [YTMLogger log:@"[SmartShuffle] No native items found at queue end. Checking autoplay cache."];
        YTQueueAutoplayController *autoplay = nil;
        if ([controller respondsToSelector:@selector(queueAutoplayController)]) {
            autoplay = [controller queueAutoplayController];
        }
        
        if (autoplay && [autoplay respondsToSelector:@selector(autoplayItems)]) {
            NSArray *recItems = [autoplay autoplayItems];
            [YTMLogger log:@"[SmartShuffle] Autoplay cache count: %lu", (unsigned long)recItems.count];
            
            // Build set of existing video IDs in queue to avoid duplicates
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
    }
    
    // 4. Relocate recommendation or trigger fetch
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
                if (recIndex != NSNotFound) {
                    // Strategy A: Relocate native item
                    [controller removeQueueItemAtIndex:recIndex];
                    
                    // Adjust insert index if the removed item was before the insert index
                    unsigned long long finalInsertIndex = insertIndex;
                    if (recIndex < insertIndex) {
                        finalInsertIndex--;
                    }
                    
                    [controller insertQueueItems:@[recItemToInsert] atIndex:finalInsertIndex];
                    [YTMLogger log:@"[SmartShuffle] Relocated videoID: %@ from end index: %lu to final index: %llu", insertedID, (unsigned long)recIndex, finalInsertIndex];
                } else {
                    // Strategy B: Insert from autoplay cache
                    [controller insertQueueItems:@[recItemToInsert] atIndex:insertIndex];
                    [YTMLogger log:@"[SmartShuffle] Inserted videoID: %@ from autoplay cache to index: %llu", insertedID, insertIndex];
                }
            } @catch (NSException *exception) {
                [YTMLogger log:@"[SmartShuffle] Insertion/Relocation failed: %@", exception];
            } @finally {
                self.isPerformingSmartShuffleInsertion = NO;
            }
        });
    } else {
        // Cache empty, trigger next continuation fetch
        [YTMLogger log:@"[SmartShuffle] No recommendations available. Triggering fetchAutoplaySectionIfNeeded."];
        if ([controller respondsToSelector:@selector(fetchAutoplaySectionIfNeeded)]) {
            [controller fetchAutoplaySectionIfNeeded];
        }
    }
}

- (void)handleRecommendationsLoaded:(YTQueueController *)controller {
    [YTMLogger log:@"[SmartShuffle] handleRecommendationsLoaded callback received."];
    [self handleTrackChangeInQueueController:controller];
}

@end
