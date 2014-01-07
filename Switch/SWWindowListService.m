//
//  SWWindowListService.m
//  Switch
//
//  Created by Scott Perry on 12/24/13.
//  Copyright © 2013 Scott Perry.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "SWWindowListService.h"

#import "SWWindow.h"
#import "SWWindowGroup.h"
#import "SWWindowListWorker.h"
#import "SWApplication.h"

#import <NNKit/NNService+Protected.h>


@interface SWWindowListService ()

@property (nonatomic, copy, readwrite) NSOrderedSet *windows;
@property (nonatomic, strong, readwrite) SWWindowListWorker *worker;

@end


@implementation SWWindowListService

- (id)init;
{
    NSAssert([NSThread isMainThread], @"Boundary call was not made on main thread");

    if (!(self = [super init])) { return nil; }
    
    [[NSNotificationCenter defaultCenter] addWeakObserver:self selector:@selector(_workerUpdatedWindowList:) name:[SWWindowListWorker notificationName] object:nil];
    
    return self;
}

#pragma mark NNService

- (NNServiceType)serviceType;
{
    return NNServiceTypeOnDemand;
}

- (Protocol *)subscriberProtocol;
{
    return @protocol(SWWindowListSubscriber);
}

- (void)startService;
{
    NSAssert([NSThread isMainThread], @"Boundary call was not made on main thread");

    [super startService];
    
    self.worker = [SWWindowListWorker new];

    [(id<SWWindowListSubscriber>)self.subscriberDispatcher windowListServiceStarted:self];
}

- (void)stopService;
{
    NSAssert([NSThread isMainThread], @"Boundary call was not made on main thread");
    
    self.worker = nil;
    self.windows = nil;
    
    [(id<SWWindowListSubscriber>)self.subscriberDispatcher windowListServiceStopped:self];
    
    [super stopService];
}

#pragma mark - Private

- (NSOrderedSet *)_filterInfoDictionariesToWindowObjects:(NSArray *)infoDicts;
{
    NSMutableOrderedSet *rawWindowList = [NSMutableOrderedSet orderedSetWithArray:infoDicts];
    
    for (NSInteger i = (NSInteger)rawWindowList.count - 1; i >= 0; --i) {
        // Non-normal windows are filtered out as the accuracy of their ordering in the window list cannot be guaranteed.
        if ([rawWindowList[(NSUInteger)i][(__bridge NSString *)kCGWindowLayer] longValue] != kCGNormalWindowLevel) {
            [rawWindowList removeObjectAtIndex:(NSUInteger)i];
        } else {
            [rawWindowList replaceObjectAtIndex:(NSUInteger)i withObject:[SWWindow windowWithDescription:rawWindowList[(NSUInteger)i]]];
        }
    }

    return rawWindowList;
}

- (NSOrderedSet *)_filterWindowObjectsToWindowGroups:(NSOrderedSet *)rawWindowList;
{
    NSMutableOrderedSet *mutableWindowGroupList = [NSMutableOrderedSet new];
    
    __block NSMutableOrderedSet *windows = [NSMutableOrderedSet new];
    __block SWWindow *mainWindow = nil;
    dispatch_block_t addWindowGroup = ^{
        if (windows.count) {
            SWWindowGroup *group = [[SWWindowGroup alloc] initWithWindows:[windows reversedOrderedSet] mainWindow:mainWindow];
            
            if (mutableWindowGroupList.count && [group isRelatedToLowerGroup:mutableWindowGroupList.lastObject]) {
                NSMutableOrderedSet *windowList = [group.windows mutableCopy];
                [windowList addObjectsFromArray:((SWWindowGroup *)mutableWindowGroupList.lastObject).windows.array];
                group = [[SWWindowGroup alloc] initWithWindows:windowList mainWindow:((SWWindowGroup *)mutableWindowGroupList.lastObject).mainWindow];
                [mutableWindowGroupList removeObject:mutableWindowGroupList.lastObject];
            }
            
            [mutableWindowGroupList addObject:group];

            windows = [NSMutableOrderedSet new];
            mainWindow = nil;
        }
    };
    
    for (NSInteger i = (NSInteger)rawWindowList.count - 1; i >= 0; --i) {
        SWWindow *window = rawWindowList[(NSUInteger)i];

        if (mainWindow && ![window isRelatedToLowerWindow:mainWindow]) {
            addWindowGroup();
        }
        
        if (window.application.canBeActivated) {
            // Some applications don't name their windows, some people juggle geese. Make sure there's always a main window for the group.
            if (!mainWindow) {
                mainWindow = window;
            } else
            // Named windows always supercede unnamed siblings in the same window group.
            if (window.name.length && !mainWindow.name.length) {
                mainWindow = window;
            }
        }
        
        [windows addObject:window];
    }
    if (mainWindow) {
        addWindowGroup();
    }
    
    return [mutableWindowGroupList reversedOrderedSet];
}

// This is also declared in the tests as the entry point in which to insert data
- (void)_updateWindowList:(NSArray *)windowInfoList;
{
    BailUnless(windowInfoList,);
    NSOrderedSet *windowObjectList = [self _filterInfoDictionariesToWindowObjects:windowInfoList];
    NSOrderedSet *windowGroupList = [self _filterWindowObjectsToWindowGroups:windowObjectList];
    
    if (![self.windows isEqualToOrderedSet:windowGroupList]) {
        self.windows = windowGroupList;
        [(id<SWWindowListSubscriber>)self.subscriberDispatcher windowListService:self updatedList:self.windows];
    }
}


#pragma mark - Notifications

- (void)_workerUpdatedWindowList:(NSNotification *)notification;
{
    NSAssert([NSThread isMainThread], @"Boundary call was not made on main thread");
    
    if (notification.object != self.worker) { NotTested(); return; }
    
    NSParameterAssert([notification.userInfo[@"windows"] isKindOfClass:[NSArray class]]);

    [self _updateWindowList:notification.userInfo[@"windows"]];
}

@end