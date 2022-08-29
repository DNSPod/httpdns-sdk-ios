/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>

@interface HTTPDNSORM : NSObject

@property(retain) NSString *domain;

@property(retain) NSString *httpDnsIPV4Channel;
@property(retain) NSString *httpDnsIPV4ClientIP;
@property(retain) NSArray *httpDnsIPV4IPs;
@property(retain) NSString *httpDnsIPV4TimeConsuming;
@property(retain) NSString *httpDnsIPV4TTL;
@property(retain) NSString *httpDnsIPV4TTLExpried;

@property(retain) NSString *httpDnsIPV6Channel;
@property(retain) NSString *httpDnsIPV6ClientIP;
@property(retain) NSArray *httpDnsIPV6IPs;
@property(retain) NSString *httpDnsIPV6TimeConsuming;
@property(retain) NSString *httpDnsIPV6TTL;
@property(retain) NSString *httpDnsIPV6TTLExpried;


@end
