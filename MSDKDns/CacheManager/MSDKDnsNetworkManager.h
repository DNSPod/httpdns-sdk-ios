/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "MSDKDnsReachability.h"

@interface MSDKDnsNetworkManager : NSObject

@property (assign, nonatomic, readonly) BOOL networkAvailable;
@property (assign, nonatomic, readonly) MSDKDnsNetworkStatus networkStatus;
@property (strong, nonatomic, readonly) NSString *networkType;

+ (instancetype)shareInstance;
+ (void)start;

@end
