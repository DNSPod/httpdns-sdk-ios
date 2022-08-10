/**
 * Copyright (c) Tencent. All rights reserved.
 */

@protocol HttpdnsSpeedTester <NSObject>

- (float)testSpeedOf:(NSString *)ip port:(int16_t)port;
- (NSArray<NSString *> *)ipRankingWithIPs:(NSArray<NSString *> *)IPs host:(NSString *)host;

@end

