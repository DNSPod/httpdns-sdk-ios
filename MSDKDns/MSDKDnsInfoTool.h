/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "Resolver/HttpsDnsResolver.h"

@interface MSDKDnsInfoTool : NSObject

+ (dispatch_queue_t) msdkdns_queue;
+ (dispatch_queue_t) msdkdns_resolver_queue;
+ (dispatch_queue_t) msdkdns_local_queue;
+ (dispatch_queue_t) msdkdns_retry_queue;
+ (NSString *) wifiSSID;

+ (NSString *) encryptUseDES:(NSString *)plainText key:(NSString *)key;
+ (NSString *) decryptUseDES:(NSString *)cipherString key:(NSString *)key;
+ (NSURL *) httpsUrlWithDomain:(NSString *)domain DnsId:(int)dnsId DnsKey:(NSString *)dnsKey IPType:(HttpDnsIPType)ipType;

+ (NSString *)encryptUseAES:(NSString *)plainText key:(NSString *)key;
+ (NSString *)decryptUseAES:(NSString *)cipherString key:(NSString *)key;
+ (NSURL *) httpsUrlWithDomain:(NSString *)domain DnsId:(int)dnsId DnsKey:(NSString *)dnsKey IPType:(HttpDnsIPType)ipType encryptType:(NSInteger)encryptType; //encryptType: 0 des,1 aes
+ (NSString *)generateSessionID;
@end
