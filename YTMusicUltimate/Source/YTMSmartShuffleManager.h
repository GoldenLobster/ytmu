#import <Foundation/Foundation.h>

@class YTQueueController;

@interface YTMSmartShuffleManager : NSObject

@property (nonatomic, assign) BOOL isSmartShuffleActive;
@property (nonatomic, assign) NSInteger recommendationInterval;
@property (nonatomic, strong) NSMutableSet<NSString *> *insertedVideoIDs;
@property (nonatomic, copy) NSString *currentPlaylistID;
@property (nonatomic, assign) BOOL isPerformingSmartShuffleInsertion;

+ (instancetype)sharedManager;

- (void)resetState;
- (void)handleTrackChangeInQueueController:(YTQueueController *)controller;
- (void)handleRecommendationsLoaded:(YTQueueController *)controller;

@end
