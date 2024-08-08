/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "MSDKDns.h"

@interface MSDKDnsParamsManager : NSObject

@property (nonatomic, strong, readwrite)NSArray * hijackDomainArray;
@property (nonatomic, strong, readwrite)NSArray * noHijackDomainArray;

+ (instancetype)shareInstance;

- (void)msdkDnsSetMOpenId:(NSString *) mdnsOpenId;
- (void)msdkDnsSetMAppId:(NSString *) mdnsAppId timeOut:(int)mdnsTimeOut encryptType:(HttpDnsEncryptType)mdnsEncryptType;
- (void)msdkDnsSetMDnsId:(int) mdnsId dnsKey:(NSString *)mdnsKey token:(NSString* )mdnsToken;
- (void)msdkDnsSetRouteIp:(NSString *)routeIp;
- (void)msdkDnsSetHttpOnly:(BOOL)httpOnly;
// 设置切换ip之前重试次数
- (void)msdkDnsSetRetryTimesBeforeSwitchServer:(NSUInteger)times;
// 设置切回主ip间隔时长
- (void)msdkDnsSetMinutesBeforeSwitchToMain:(NSUInteger)minutes;
// 设置备份ip
- (void)msdkDnsSetBackupServerIps: (NSArray *)ips;
- (void)msdkDnsSetEnableReport: (BOOL)enableReport;
- (void)msdkDnsSetEnableDetectHostServer: (BOOL)enableDetectHostServer;
- (void)msdkDnsSetPreResolvedDomains: (NSArray *)domains;
- (void)msdkDnsSetHijackDomainArray: (NSArray *)domains;
- (void)msdkDnsSetNoHijackDomainArray: (NSArray *)domains;
- (void)msdkDnsSetAddressType: (HttpDnsAddressType)addressType;
- (void)msdkDnsSetKeepAliveDomains: (NSArray *)domains;
- (void)msdkDnsSetIPRankData: (NSDictionary *)ipRankData;
- (void)msdkDnsSetEnableKeepDomainsAlive: (BOOL)enableKeepDomainsAlive;
- (void)msdkDnsSetExpiredIPEnabled: (BOOL)enable;
- (void)msdkDnsSetPersistCacheIPEnabled: (BOOL)enable;

- (NSString *) msdkDnsGetMDnsIp;
- (NSString *) msdkDnsGetMOpenId;
- (NSString *) msdkDnsGetMAppId;
- (int) msdkDnsGetMDnsId;
- (NSString *) msdkDnsGetMDnsKey;
- (float) msdkDnsGetMTimeOut;
- (HttpDnsEncryptType)msdkDnsGetEncryptType;
- (NSString *)msdkDnsGetMToken;
- (NSString *)msdkDnsGetRouteIp;
- (BOOL)msdkDnsGetHttpOnly;
- (NSArray *)msdkDnsGetServerIps;
- (NSUInteger)msdkDnsGetRetryTimesBeforeSwitchServer;
- (NSUInteger)msdkDnsGetMinutesBeforeSwitchToMain;
- (BOOL)msdkDnsGetEnableReport;
- (BOOL)msdkDnsGetEnableDetectHostServer;
- (NSArray *)msdkDnsGetPreResolvedDomains;
- (NSArray *)msdkDnsGetHijackDomainArray;
- (NSArray *)msdkDnsGetNoHijackDomainArray;
- (HttpDnsAddressType)msdkDnsGetAddressType;
- (NSArray *)msdkDnsGetKeepAliveDomains;
- (NSDictionary *)msdkDnsGetIPRankData;
- (BOOL)msdkDnsGetEnableKeepDomainsAlive;
- (BOOL)msdkDnsGetExpiredIPEnabled;
- (BOOL)msdkDnsGetPersistCacheIPEnabled;

@end
