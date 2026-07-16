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
