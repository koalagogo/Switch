//
//  NNPreferencesService.m
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

#import "NNPreferencesService.h"

#import "NNEventManager.h"
#import "NNHotKey.h"
#import "NNPreferencesWindowController.h"


@interface NNPreferencesService ()

@property (nonatomic, strong) NNPreferencesWindowController *preferencesWindowController;

@end


@implementation NNPreferencesService

- (NNServiceType)serviceType;
{
    return NNServiceTypePersistent;
}

- (void)startService;
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
#pragma message "Keys (and default values) should be DRYed up a bit more."
    NSDictionary *userDefaultsValues = @{ @"firstLaunch" : @YES };
    [defaults registerDefaults:userDefaultsValues];
    
#   if DEBUG
    {
        BOOL resetDefaults = NO;
        
        if (resetDefaults) {
            [defaults removeObjectForKey:@"firstLaunch"];
        }
    }
#   endif
    
    NNEventManager *keyManager = [NNEventManager sharedManager];
    [keyManager registerHotKey:[NNHotKey hotKeyWithKeycode:kVK_Tab modifiers:NNHotKeyModifierOption] forEvent:NNEventManagerEventTypeInvoke];
    [keyManager registerHotKey:[NNHotKey hotKeyWithKeycode:kVK_Tab modifiers:(NNHotKeyModifierOption | NNHotKeyModifierShift)] forEvent:NNEventManagerEventTypeDecrement];
    [keyManager registerHotKey:[NNHotKey hotKeyWithKeycode:kVK_ANSI_W modifiers:NNHotKeyModifierOption] forEvent:NNEventManagerEventTypeCloseWindow];
    [keyManager registerHotKey:[NNHotKey hotKeyWithKeycode:kVK_Escape modifiers:NNHotKeyModifierOption] forEvent:NNEventManagerEventTypeCancel];
    [keyManager registerHotKey:[NNHotKey hotKeyWithKeycode:kVK_ANSI_Comma modifiers:NNHotKeyModifierOption] forEvent:NNEventManagerEventTypeShowPreferences];
    
    self.preferencesWindowController = [[NNPreferencesWindowController alloc] initWithWindowNibName:@"NNPreferencesWindowController"];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"firstLaunch"]) {
        [self.preferencesWindowController showWindow:self];
        [defaults setBool:NO forKey:@"firstLaunch"];
    }

    [defaults synchronize];
}

- (void)showPreferencesWindow:(id)sender;
{
    [self.preferencesWindowController showWindow:sender];
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [self.preferencesWindowController.window makeKeyAndOrderFront:sender];
}

@end