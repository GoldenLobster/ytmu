#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "YTMSmartShuffleManager.h"
#import "YTMLogger.h"

// Force-enable Autoplay configs when Smart Shuffle is active
%hook YTDefaultQueueConfig
- (BOOL)autoplayEnabled {
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        return YES;
    }
    return %orig;
}
%end

%hook YTMQueueConfig
- (BOOL)autoplayEnabled {
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        return YES;
    }
    return %orig;
}
%end

%hook YTMQueueConfigImpl
- (BOOL)autoplayEnabled {
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        return YES;
    }
    return %orig;
}
%end

%hook YTMSettings
- (BOOL)autoplayEnabled {
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        return YES;
    }
    return %orig;
}
%end

%hook YTMSettingsImpl
- (BOOL)autoplayEnabled {
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        return YES;
    }
    return %orig;
}
%end

%hook YTUserDefaults
- (BOOL)autoplayEnabled {
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        return YES;
    }
    return %orig;
}
%end

%hook YTQueueShuffleController
- (void)setShuffleMode:(unsigned long long)mode forceApply:(BOOL)force nowPlayingIndex:(unsigned long long)index nowPlayingVideoID:(id)videoID completion:(id)completion {
    [YTMLogger log:@"[SmartShuffle] YTQueueShuffleController setShuffleMode hook hit: mode=%llu, force=%d, isInserting=%d", 
                  mode, force, [[YTMSmartShuffleManager sharedManager] isPerformingSmartShuffleInsertion]];
                  
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive] && 
        [[YTMSmartShuffleManager sharedManager] isPerformingSmartShuffleInsertion] && 
        mode == 0) {
        [YTMLogger log:@"[SmartShuffle] Blocking shuffle controller setShuffleMode:0 during insertion."];
        if (completion) {
            void (^block)(void) = completion;
            block();
        }
        return;
    }
    %orig;
}
%end

%hook YTQueueController

- (BOOL)isAutoplaySupported {
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        return YES;
    }
    return %orig;
}

- (void)setNowPlayingIndex:(unsigned long long)index {
    %orig;
    
    [YTMLogger log:@"[SmartShuffle] setNowPlayingIndex hook hit with index: %llu", index];
    
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        [[YTMSmartShuffleManager sharedManager] handleTrackChangeInQueueController:self];
    }
}

- (void)insertQueueItems:(id)items atIndex:(unsigned long long)index {
    %orig;
    
    // Avoid recursion if this insertion was triggered by our manager
    if ([[YTMSmartShuffleManager sharedManager] isPerformingSmartShuffleInsertion]) {
        return;
    }
    
    [YTMLogger log:@"[SmartShuffle] insertQueueItems hook hit: inserting %lu items at index %llu", (unsigned long)[items count], index];
    
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        [[YTMSmartShuffleManager sharedManager] handleTrackChangeInQueueController:self];
    }
}

- (void)setQueueAutoplayController:(id)autoplayController {
    %orig;
    
    [YTMLogger log:@"[SmartShuffle] setQueueAutoplayController hook hit: %@", autoplayController];
    
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        [[YTMSmartShuffleManager sharedManager] handleRecommendationsLoaded:self];
    }
}

- (void)autoplayController:(id)autoplayController didInsertRenderersAtIndexes:(id)indexes response:(id)response {
    %orig;
    
    [YTMLogger log:@"[SmartShuffle] autoplayController didInsertRenderers hook hit"];
    
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        [[YTMSmartShuffleManager sharedManager] handleRecommendationsLoaded:self];
    }
}

- (void)promoteAutoplayItemsAtIndexPaths:(id)paths userTriggered:(BOOL)userTriggered {
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive]) {
        return;
    }
    %orig;
}

- (void)setShuffleMode:(unsigned long long)mode forceApply:(BOOL)force {
    [YTMLogger log:@"[SmartShuffle] setShuffleMode hook hit: mode=%llu, force=%d, isInserting=%d", 
                  mode, force, [[YTMSmartShuffleManager sharedManager] isPerformingSmartShuffleInsertion]];
                  
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive] && 
        [[YTMSmartShuffleManager sharedManager] isPerformingSmartShuffleInsertion] && 
        mode == 0) {
        [YTMLogger log:@"[SmartShuffle] Blocking setShuffleMode:0 during insertion."];
        return;
    }
    
    %orig;
    
    if ([[YTMSmartShuffleManager sharedManager] isSmartShuffleActive] && mode != 0) {
        [[YTMSmartShuffleManager sharedManager] handleTrackChangeInQueueController:self];
    }
}

%end

%ctor {
    [YTMLogger setupCrashReporter];
    [YTMLogger log:@"Smart Shuffle initialized successfully."];
}
