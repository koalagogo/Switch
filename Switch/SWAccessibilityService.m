//
//  SWAccessibilityService.m
//  Switch
//
//  Created by Scott Perry on 10/20/13.
//  Copyright © 2013 Scott Perry.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "SWAccessibilityService.h"

#import <Haxcessibility/HAXElement+Protected.h>
#import <Haxcessibility/Haxcessibility.h>
#import <NNKit/NNService+Protected.h>

#import "NSScreen+SWAdditions.h"
#import "SWAPIEnabledWorker.h"
#import "SWAppDelegate.h"
#import "SWApplication.h"
#import "SWWindow.h"
#import "SWWindowGroup.h"


@interface SWAccessibilityService ()

@property (nonatomic, copy) NSSet *windows;
@property (nonatomic, strong) SWAPIEnabledWorker *worker;
@property (nonatomic, strong, readonly) dispatch_queue_t haxQueue;

@end


@implementation SWAccessibilityService

#pragma mark - Initialization

- (instancetype)init;
{
    BailUnless(self = [super init], nil);
    
    _haxQueue = dispatch_queue_create("haxQueue", DISPATCH_QUEUE_SERIAL);
    
    return self;
}

#pragma mark - NNService

+ (NNServiceType)serviceType;
{
    return NNServiceTypePersistent;
}

- (void)startService;
{
    [super startService];
    
    [self checkAPI];
}

#pragma mark - SWAccessibilityService

- (void)setWorker:(SWAPIEnabledWorker *)worker;
{
    if (worker == _worker) {
        return;
    }
    if (_worker) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:SWAPIEnabledWorker.notificationName object:_worker];
    }
    if (worker) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:NNSelfSelector1(private_accessibilityAPIAvailabilityChangedNotification:) name:SWAPIEnabledWorker.notificationName object:self.worker];
    }
    _worker = worker;
}

- (void)checkAPI;
{
    if (![SWAPIEnabledWorker isAPIEnabled]) {
        self.worker = [SWAPIEnabledWorker new];
        
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{ (__bridge NSString *)kAXTrustedCheckOptionPrompt : @YES });
    }
}

- (void)raiseWindow:(SWWindow *)window completion:(void (^)(NSError *))completionBlock;
{
    dispatch_async(self.haxQueue, ^{
        // If sending events to Switch itself, we have to use the main thread!
        if ([window.application isLiveApplication]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self _raiseWindow:window completion:completionBlock];
            });
        } else {
            [self _raiseWindow:window completion:completionBlock];
        }
    });
}

- (void)closeWindow:(SWWindow *)window completion:(void (^)(NSError *))completionBlock;
{
    dispatch_async(self.haxQueue, ^{
        // If sending events to Switch itself, we have to use the main thread!
        if ([window.application isLiveApplication]) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self _closeWindow:window completion:completionBlock];
            });
        } else {
            [self _closeWindow:window completion:completionBlock];
        }
    });
}

#pragma mark - Internal

- (void)private_accessibilityAPIAvailabilityChangedNotification:(NSNotification *)notification;
{
    BOOL accessibilityEnabled = [notification.userInfo[SWAXAPIEnabledKey] boolValue];
    
    SWLog(@"Accessibility API is %@abled", accessibilityEnabled ? @"en" : @"dis");
    
    if (accessibilityEnabled) {
        self.worker = nil;
        [(SWAppDelegate *)NSApplication.sharedApplication.delegate relaunch:nil];
    }
}

- (void)_raiseWindow:(SWWindow *)window completion:(void (^)(NSError *))completionBlock;
{
    if (!completionBlock) {
        completionBlock = ^(NSError *error){};
    }
    
    if (!window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(nil);
        });
        return;
    }

    NSError *error = nil;
    HAXWindow *haxWindow = [self _haxWindowForWindow:window];
    if (!Check(haxWindow)) {
        NSString *errorString = [NSString stringWithFormat:@"Failed to get accessibility object for window %@", window];
        SWLog(@"%@", errorString);
        error = [NSError errorWithDomain:@"SWAccessibilityServiceDomain" code:__LINE__ userInfo:@{NSLocalizedDescriptionKey : errorString}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(error);
        });
        return;
    }
    
    SWTimeTask(SWCodeBlock({
        // First, raise the window
        if (![haxWindow performAction:(__bridge NSString *)kAXRaiseAction error:&error]) {
            SWLog(@"Raise operation for %@ failed after %.3fs: %@", window, [[NSDate date] timeIntervalSinceDate:start], error);
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(error);
            });
            return;
        }
        
        // Then raise the application (if it's not already topmost)
        if (![window.application isActiveApplication]) {
            NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:window.application.pid];
            if (![runningApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps]) {
                NSString *errorString = [NSString stringWithFormat:@"Raise operation for %@ failed.", window.application];
                SWLog(@"%@", errorString);
                error = [NSError errorWithDomain:@"SWAccessibilityServiceDomain" code:__LINE__ userInfo:@{NSLocalizedDescriptionKey : errorString}];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock(error);
                });
                return;
            }
        }
    }), @"Raise operation for %@", window);

    dispatch_async(dispatch_get_main_queue(), ^{
        completionBlock(nil);
    });
}

- (void)_closeWindow:(SWWindow *)window completion:(void (^)(NSError *))completionBlock;
{
    if (!completionBlock) {
        completionBlock = ^(NSError *error){};
    }
    
    if (!window) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(nil);
        });
        return;
    }

    NSError *error = nil;
    HAXWindow *haxWindow = [self _haxWindowForWindow:window];
    if (!Check(haxWindow)) {
        NSString *errorString = [NSString stringWithFormat:@"Failed to get accessibility object for window %@", window];
        SWLog(@"%@", errorString);
        error = [NSError errorWithDomain:@"SWAccessibilityServiceDomain" code:__LINE__ userInfo:@{NSLocalizedDescriptionKey : errorString}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(error);
        });
        return;
    }
    
    SWTimeTask(SWCodeBlock({
        HAXElement *element = [haxWindow elementOfClass:[HAXElement class] forKey:(__bridge NSString *)kAXCloseButtonAttribute error:&error];
        if (!element) {
            SWLog(@"Couldn't get close button for %@ window %@ after %.3fs: %@", window.application.name, window, [[NSDate date] timeIntervalSinceDate:start], error);
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(error);
            });
            return;
        }
        
        if (![element performAction:(__bridge NSString *)kAXPressAction error:&error]) {
            SWLog(@"Closing %@ window %@ failed after %.3fs: %@", window.application.name, window, [[NSDate date] timeIntervalSinceDate:start], error);
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(error);
            });
            return;
        }
    }), @"Closing %@ window %@", window.application.name, window);

    dispatch_async(dispatch_get_main_queue(), ^{
        completionBlock(nil);
    });
}

- (HAXWindow *)_haxWindowForWindow:(SWWindow *)window;
{
    // If window is a group, the frame will be calculated incorrectly, and no accessibility object for the window will be found!
    while (![window isMemberOfClass:[SWWindow class]]) {
        if ([window isKindOfClass:[SWWindowGroup class]]) {
            window = [(SWWindowGroup *)window mainWindow];
        } else {
            // TODO: If I had nothing but time, I'd trap on launch if SWWindow had any other subclasses but ain't nobody got time for that, maybe if this project ever has more than one developer.
            DebugBreak();
            break;
        }
    }

    HAXApplication *haxApplication = [HAXApplication applicationWithPID:window.application.pid];
    BailUnless(haxApplication, nil);
    
    return [[haxApplication windows] nn_reduce:^id(id accumulator, HAXWindow *haxWindow){
        NSString *haxTitle = haxWindow.title;
        
        // This should ultimately be flipped in Haxcessibility, per #89.
        CGRect haxFrame = haxWindow.carbonFrame;
        haxFrame.origin.y = NSScreen.sw_totalScreenHeight - (haxFrame.origin.y + haxFrame.size.height);
        
        BOOL framesMatch = NNCGRectsEqual(window.frame, haxFrame);
        // AX will return an empty string when CG returns nil/unset!
        BOOL namesMatch = (window.name.length == 0 && haxTitle.length == 0) || [window.name isEqualToString:haxTitle];
        
        // For some reason, the window names for Dash have been seen to differ.
        if (framesMatch && (!accumulator || namesMatch)) {
            return haxWindow;
        }
        
        return accumulator;
    }];
}

@end
