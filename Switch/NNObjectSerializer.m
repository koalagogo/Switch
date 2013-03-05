//
//  NNObjectSerializer.m
//  Switch
//
//  Created by Scott Perry on 03/04/13.
//  Copyright © 2013 Scott Perry.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//


#import "NNObjectSerializer.h"

#import "despatch.h"


static void *kNNSerializerKey = (void *)1784668075; // Guaranteed random by arc4random()


@interface NNObjectSerializer () {
    NSObject *target;
    dispatch_queue_t queue;
}
@end


@implementation NNObjectSerializer

#pragma mark Class Functionality Methods

+ (dispatch_queue_t)queueForObject:(id)obj;
{
    return ((NNObjectSerializer *)[self serializedObjectForObject:obj])->queue;
}

+ (id)serializedObjectForObject:(id)obj;
{
    return objc_getAssociatedObject(obj, kNNSerializerKey) ?: [[self alloc] initWithObject:obj];
}

#pragma mark Instance Methods

- (id)initWithObject:(id)obj;
{
    assert(!objc_getAssociatedObject(obj, kNNSerializerKey));
    
    self->target = obj;
    self->queue = despatch_lock_create([[NSString stringWithFormat:@"Locking queue for %@ <%p>", [obj class], obj] UTF8String]);
    objc_setAssociatedObject(obj, kNNSerializerKey, self, OBJC_ASSOCIATION_ASSIGN);
    
    return self;
}

- (BOOL)isProxy;
{
    return [super isProxy];
}

- (void)dealloc;
{
    NSLog(@"dealloc called on proxy for target %p", self->target);
    objc_setAssociatedObject(self->target, kNNSerializerKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

- (void)forwardInvocation:(NSInvocation *)invocation;
{
    [invocation setTarget:self->target];
    dispatch_block_t invoke = ^{ [invocation invoke]; };
    
    if ([[invocation methodSignature] methodReturnLength]) {
        dispatch_sync(self->queue, invoke);
    } else {
        dispatch_async(self->queue, invoke);
    }
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel;
{
    return [self->target methodSignatureForSelector:sel] ?: [super methodSignatureForSelector:sel];
}

@end