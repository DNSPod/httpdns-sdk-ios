/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "MSDKDnsSpeedTester.h"

#define MSDKDns_SOCKET_CONNECT_TIMEOUT 10 //单位秒
#define MSDKDns_SOCKET_CONNECT_TIMEOUT_RTT 600000//10分钟 单位毫秒

@interface MSDKDnsTCPSpeedTester : NSObject <MSDKDnsSpeedTester>

@end
