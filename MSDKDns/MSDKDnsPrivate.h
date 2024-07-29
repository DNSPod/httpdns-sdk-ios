/**
 * Copyright (c) Tencent. All rights reserved.
 */

#ifndef HTTPDNS_SDK_IOS_MSDKDNS_MSDKDNSPRIVATE_H_
#define HTTPDNS_SDK_IOS_MSDKDNS_MSDKDNSPRIVATE_H_

#define HTTP_DNS_UNKNOWN_STR @"UNKNOWN"

// cacheDictionary
#define kIP @"ips"
#define kClientIP @"clientIP"
#define kTTL @"ttl"
#define kTTLExpired @"ttlExpried"
#define kChannel @"channel"
#define kDnsTimeConsuming @"timeConsuming"
#define kDnsErrCode @"errCode"
#define kDnsErrMsg @"errMsg"
#define kDnsRetry @"retry"
#define kMSDKHttpDnsCache_A @"httpDnsCache_A"
#define kMSDKHttpDnsCache_4A @"httpDnsCache_4A"
#define kMSDKHttpDnsInfo_A @"httpDnsInfo_A"
#define kMSDKHttpDnsInfo_4A @"httpDnsInfo_4A"
#define kMSDKHttpDnsInfo_BOTH @"httpDnsInfo_BOTH"
#define kMSDKLocalDnsCache @"localDnsCache"

// HttpDns解析结果数据上报相关
#define MSDKDnsEventName @"HDNSGetHostByName"

#define kMSDKDnsSDK_Version @"sdk_Version"        // SDK版本号
#define kMSDKDnsAppID @"appID"                    // 业务AppId
#define kMSDKDnsID @"id"                          // 业务DnsId，内部业务固定为1
#define kMSDKDnsKEY @"key"                        // 业务DnsKey，内部业务固定为>srW/8&
#define kMSDKDnsUserID @"userID"                  // 用户Id，内部业务为OpenId
#define kMSDKDnsChannel @"channel"                // HTTPDNS服务渠道， http/https/udp
#define kMSDKDnsNetType @"netType"                // 用户网络类型
#define kMSDKDnsSSID @"ssid"                      //  WiFi SSID，网络类型不为WiFi时为空
#define kMSDKDnsDomain @"domain"                  // 解析域名
#define kMSDKDnsLDNS_IP @"ldns_ip"                // LocalDns解析结果IP
#define kMSDKDnsLDNS_Time @"ldns_time"            // LocalDns解析耗时
// 域名解析发起时网络栈 - 0: 无网络/未知 - 1: IPv4 Only - 2: IPv6 Only - 3: Dual Stack
#define kMSDKDnsNet_Stack @"net_stack"
#define kMSDKDns_A_IsCache @"isCache"             // 域名解析A记录是否命中缓存
#define kMSDKDns_A_ErrCode @"hdns_a_err_code"     // 域名解析A记录解析错误码
#define kMSDKDns_A_ErrMsg @"hdns_a_err_msg"       // 域名解析A记录解析错误信息
#define kMSDKDns_A_IP @"hdns_ip"                  // 域名解析A记录解析结果IP，多个ip以“,”拼接
#define kMSDKDns_A_TTL @"ttl"                     // 域名解析A记录解析结果TTL(单位s)
#define kMSDKDns_A_ClientIP @"clientIP"           // 域名解析A记录结果客户端IP
#define kMSDKDns_A_Time @"hdns_time"              // 域名解析A记录耗时(单位ms)
#define kMSDKDns_A_Retry @"hdns_a_retry"          // 域名解析A记录重试次数
#define kMSDKDns_4A_IsCache @"hdns_4a_cache_hit"  // 域名解析AAAA记录是否命中缓存
#define kMSDKDns_4A_ErrCode @"hdns_4a_err_code"   // 域名解析AAAA记录解析错误码
#define kMSDKDns_4A_ErrMsg @"hdns_4a_err_msg"     // 域名解析AAAA记录解析错误信息
#define kMSDKDns_4A_IP @"hdns_4a_ips"             // 域名解析AAAA记录解析结果IP，多个ip以“,”拼接
#define kMSDKDns_4A_TTL @"hdns_4a_ttl"            // 域名解析AAAA记录解析结果TTL(单位s)
#define kMSDKDns_4A_ClientIP @"hdns_4a_client_ip"  // 域名解析AAAA记录结果客户端IP
#define kMSDKDns_4A_Time @"hdns_4a_time_ms"       // 域名解析AAAA记录耗时(单位ms)
#define kMSDKDns_4A_Retry @"hdns_4a_retry"        // 域名解析AAAA记录重试次数
#define kMSDKDns_BOTH_Retry @"hdns_both_retry"        // 双栈域名解析重试次数
#define kMSDKDns_BOTH_ErrCode @"hdns_both_err_code"   // 双栈域名解析解析错误码
#define kMSDKDns_BOTH_ErrMsg @"hdns_both_err_msg"     // 双栈域名解析解析错误信息
#define kMSDKDns_DNS_A_IP @"dns_ips"              // 域名解析结果v4 IP，多个ip以“,”拼接
#define kMSDKDns_DNS_4A_IP @"dns_4a_ips"          // 域名解析结果v6 IP，多个ip以“,”拼接

/*** 域名解析错误码*/
#define MSDKDns_Fail @"-1"    // 失败
#define MSDKDns_Success @"0"  // 成功
#define MSDKDns_UnResolve @"1"  // 未解析
#define MSDKDns_Timeout @"2"  // 解析超时
#define MSDKDns_NoData @"3"   // 没有解析数据
#define MSDKDns_ErrorCode @"errorCode"

/** 上报事件*/
#define MSDKDnsEventHttpDnsfail @"HttpDnsfail"
#define MSDKDnsEventHttpDnsSpend @"HttpDnsSpend"
#define MSDKDnsEventHttpDnsCached @"HDNSLookupCached"         // 命中缓存
#define MSDKDnsEventHttpDnsNormal @"HDNSGetHostByName"        // 常规解析请求
#define MSDKDnsEventHttpDnsPreResolved @"HDNSPreLookup"       // 预解析请求
#define MSDKDnsEventHttpDnsAutoRefresh @"HDNSLookupAsync"     // 缓存自动刷新
#define MSDKDnsEventHttpDnsExpiredAsync @"HDNSLookupExpiredAsync"  // 乐观DNS中缓存异步刷新请求
#define MSDKDnsEventHttpDnsGetHTTPDNSDomainIP @"HDNSGetDomainIP"  // 获取三网域名的IP

// 命中缓存的状态
#define MSDKDnsDomainCacheHit @"domainCacheHit"          // 命中缓存
#define MSDKDnsDomainCacheExpired @"domainCacheExpired"  // 缓存过期
#define MSDKDnsDomainCacheEmpty @"domainCacheEmpty"      // 没有缓存

// 本地DB存储字段
#define DB_HttpDNS_IPV4_Channel [kMSDKHttpDnsCache_A stringByAppendingString:kChannel]
#define DB_HttpDNS_IPV4_ClientIP [kMSDKHttpDnsCache_A stringByAppendingString:kClientIP]
#define DB_HttpDNS_IPV4_TimeConsuming [kMSDKHttpDnsCache_A stringByAppendingString:kDnsTimeConsuming]
#define DB_HttpDNS_IPV4_TTL [kMSDKHttpDnsCache_A stringByAppendingString:kTTL]
#define DB_HttpDNS_IPV4_TTLExpired [kMSDKHttpDnsCache_A stringByAppendingString:kTTLExpired]

#endif  // HTTPDNS_SDK_IOS_MSDKDNS_MSDKDNSPRIVATE_H_
