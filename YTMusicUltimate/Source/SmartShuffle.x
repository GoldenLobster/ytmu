#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "YTMSmartShuffleManager.h"
#import "YTMLogger.h"

%hook YTQueueController

- (void)setNowPlayingIndex:(unsigned long long)index {
    %orig;
    
    // Check and trigger dynamic insertions on track change
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        [[YTMSmartShuffleManager sharedManager] handleTrackChangeInQueueController:self];
    }
}

- (void)autoplayController:(id)autoplayController didInsertRenderersAtIndexes:(id)indexes response:(id)response {
    %orig;
    
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
