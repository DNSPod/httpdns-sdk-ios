/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>

@interface MSDKDnsParamsManager : NSObject

@property (nonatomic, strong, readwrite)NSArray * hijackDomainArray;
@property (nonatomic, strong, readwrite)NSArray * noHijackDomainArray;

+ (instancetype)shareInstance;

- (void)msdkDnsSetMDnsIp:(NSString *) mdnsIp;
- (void)msdkDnsSetMOpenId:(NSString *) mdnsOpenId;
- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId MTimeOut:(int)mdnsTimeOut;
- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId MTimeOut:(int)mdnsTimeOut MChannel:(NSString *)mdnsChannel;
- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId MToken:(NSString* )mdnsToken MTimeOut:(int)mdnsTimeOut MChannel:(NSString *)mdnsChannel;
- (void)msdkDnsSetMDnsId:(int) mdnsId MDnsKey:(NSString *)mdnsKey;

- (NSString *) msdkDnsGetMDnsIp;
- (NSString *) msdkDnsGetMOpenId;
- (NSString *) msdkDnsGetMAppId;
- (int) msdkDnsGetMDnsId;
- (NSString *) msdkDnsGetMDnsKey;
- (float) msdkDnsGetMTimeOut;
- (NSString *)msdkDnsGetChannel;
- (NSString *)msdkDnsGetMToken;
@end
