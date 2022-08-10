/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "HttpdnsSpeedTester.h"

#define HTTPDNS_SOCKET_CONNECT_TIMEOUT 10 //单位秒
#define HTTPDNS_SOCKET_CONNECT_TIMEOUT_RTT 600000//10分钟 单位毫秒

@interface HttpdnsTCPSpeedTester : NSObject <HttpdnsSpeedTester>

@end
