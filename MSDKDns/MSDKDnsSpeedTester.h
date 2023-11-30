/**
 * Copyright (c) Tencent. All rights reserved.
 */

@protocol MSDKDnsSpeedTester <NSObject>

- (float)testSpeedOf:(NSString *)ip port:(int16_t)port;
- (NSArray<NSString *> *)ipRankingWithIPs:(NSArray<NSString *> *)ips host:(NSString *)host;

@end

