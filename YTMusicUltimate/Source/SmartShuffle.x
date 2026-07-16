#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "YTMSmartShuffleManager.h"
#import "YTMLogger.h"

%hook YTQueueController

- (void)setNowPlayingIndex:(unsigned long long)index {
    %orig;
    
    [YTMLogger log:@"[SmartShuffle] setNowPlayingIndex hook hit with index: %llu", index];
    
    // Check and trigger dynamic insertions on track change
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        [[YTMSmartShuffleManager sharedManager] handleTrackChangeInQueueController:self];
    }
}

- (void)setQueueAutoplayController:(id)autoplayController {
    %orig;
    
    [YTMLogger log:@"[SmartShuffle] setQueueAutoplayController hook hit: %@", autoplayController];
    
    // Check and trigger insertions when the autoplay controller is initialized/updated
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        [[YTMSmartShuffleManager sharedManager] handleRecommendationsLoaded:self];
    }
}

- (void)autoplayController:(id)autoplayController didInsertRenderersAtIndexes:(id)indexes response:(id)response {
    %orig;
    
    [YTMLogger log:@"[SmartShuffle] autoplayController didInsertRenderers hook hit"];
    
    // Check and trigger insertions when new recommendations arrive from the server
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        [[YTMSmartShuffleManager sharedManager] handleRecommendationsLoaded:self];
    }
}

- (void)promoteAutoplayItemsAtIndexPaths:(id)paths userTriggered:(BOOL)userTriggered {
    // Disable default autoplay promotion when Smart Shuffle is active
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        return;
    }
    %orig;
}

- (void)setShuffleMode:(unsigned long long)mode forceApply:(BOOL)force {
    %orig;
    
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive] && mode != 0) {
        // Trigger recommendations check immediately when shuffle mode is activated
        [[YTMSmartShuffleManager sharedManager] handleTrackChangeInQueueController:self];
    }
}

%end

%ctor {
    [YTMLogger setupCrashReporter];
    [YTMLogger log:@"Smart Shuffle initialized successfully."];
}
