/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDnsLog.h"
#import "MSDKDnsPrivate.h"
#import "MSDKDnsInfoTool.h"
#import "MSDKDns.h"

@implementation MSDKDnsLog

static MSDKDnsLog * gSharedInstance = nil;
//方法实现
+ (MSDKDnsLog *) sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSharedInstance = [[MSDKDnsLog alloc] init];
    });
    return gSharedInstance;
}

- (id)init {
    if (self = [super init]) {
        _enableLog = NO;
    }
    return self;
}

- (void)msdkDnsLog:(NSString *)format {
    @synchronized(self) {
        if (format && _enableLog) {
            NSLog(@"%@",format);
        }
    }
}

@end
