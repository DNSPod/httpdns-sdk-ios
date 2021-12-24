/**
 * Copyright (c) Tencent. All rights reserved.
 */

#ifndef MSDKDns_MSDKDnsPrivate_h
#define MSDKDns_MSDKDnsPrivate_h

static NSString * const HTTP_DNS_UNKNOWN_STR = @"UNKNOWN";

//cacheDictionary
static NSString * const kIP = @"ips";
static NSString * const kClientIP = @"clientIP";
static NSString * const kTTL = @"ttl";
static NSString * const kTTLExpired = @"ttlExpried";
static NSString * const kChannel = @"channel";
static NSString * const kDnsTimeConsuming = @"timeConsuming";
static NSString * const kDnsErrCode = @"errCode";
static NSString * const kDnsErrMsg = @"errMsg";
static NSString * const kDnsRetry = @"retry";
static NSString * const kMSDKHttpDnsCache_A = @"httpDnsCache_A";
static NSString * const kMSDKHttpDnsCache_4A = @"httpDnsCache_4A";
static NSString * const kMSDKHttpDnsInfo_A = @"httpDnsInfo_A";
static NSString * const kMSDKHttpDnsInfo_4A = @"httpDnsInfo_4A";
static NSString * const kMSDKLocalDnsCache = @"localDnsCache";

//HttpDns解析结果数据上报相关
static NSString * const MSDKDnsEventName = @"HDNSGetHostByName";

static NSString * const kMSDKDnsSDK_Version = @"sdk_Version";        // SDK版本号
static NSString * const kMSDKDnsAppID = @"appID";                    // 业务AppId
static NSString * const kMSDKDnsID = @"id";                          // 业务DnsId，内部业务固定为1
static NSString * const kMSDKDnsKEY = @"key";                        // 业务DnsKey，内部业务固定为>srW/8;&
static NSString * const kMSDKDnsUserID = @"userID";                  // 用户Id，内部业务为OpenId
static NSString * const kMSDKDnsChannel = @"channel";                // HTTPDNS服务渠道， http/https/udp
static NSString * const kMSDKDnsNetType = @"netType";                // 用户网络类型
static NSString * const kMSDKDnsSSID = @"ssid";                      //  WiFi SSID，网络类型不为WiFi时为空
static NSString * const kMSDKDnsDomain = @"domain";                  // 解析域名
static NSString * const kMSDKDnsLDNS_IP = @"ldns_ip";                // LocalDns解析结果IP
static NSString * const kMSDKDnsLDNS_Time = @"ldns_time";            // LocalDns解析耗时
static NSString * const kMSDKDnsNet_Stack = @"net_stack";            // 域名解析发起时网络栈 - 0: 无网络/未知 - 1: IPv4 Only - 2: IPv6 Only - 3: Dual Stack
static NSString * const kMSDKDns_A_IsCache = @"isCache";             // 域名解析A记录是否命中缓存
static NSString * const kMSDKDns_A_ErrCode = @"hdns_a_err_code";     // 域名解析A记录解析错误码
static NSString * const kMSDKDns_A_ErrMsg = @"hdns_a_err_msg";       // 域名解析A记录解析错误信息
static NSString * const kMSDKDns_A_IP = @"hdns_ip";                  // 域名解析A记录解析结果IP，多个ip以“,”拼接
static NSString * const kMSDKDns_A_TTL = @"ttl";                     // 域名解析A记录解析结果TTL(单位s)
static NSString * const kMSDKDns_A_ClientIP = @"clientIP";           // 域名解析A记录结果客户端IP
static NSString * const kMSDKDns_A_Time = @"hdns_time";              // 域名解析A记录耗时(单位ms)
static NSString * const kMSDKDns_A_Retry = @"hdns_a_retry";          // 域名解析A记录重试次数
static NSString * const kMSDKDns_4A_IsCache = @"hdns_4a_cache_hit";  // 域名解析AAAA记录是否命中缓存
static NSString * const kMSDKDns_4A_ErrCode = @"hdns_4a_err_code";   // 域名解析AAAA记录解析错误码
static NSString * const kMSDKDns_4A_ErrMsg = @"hdns_4a_err_msg";     // 域名解析AAAA记录解析错误信息
static NSString * const kMSDKDns_4A_IP = @"hdns_4a_ips";             // 域名解析AAAA记录解析结果IP，多个ip以“,”拼接
static NSString * const kMSDKDns_4A_TTL = @"hdns_4a_ttl";            // 域名解析AAAA记录解析结果TTL(单位s)
static NSString * const kMSDKDns_4A_ClientIP = @"hdns_4a_client_ip"; // 域名解析AAAA记录结果客户端IP
static NSString * const kMSDKDns_4A_Time = @"hdns_4a_time_ms";       // 域名解析AAAA记录耗时(单位ms)
static NSString * const kMSDKDns_4A_Retry = @"hdns_4a_retry";        // 域名解析AAAA记录重试次数
static NSString * const kMSDKDns_DNS_A_IP = @"dns_ips";              // 域名解析结果v4 IP，多个ip以“,”拼接
static NSString * const kMSDKDns_DNS_4A_IP = @"dns_4a_ips";          // 域名解析结果v6 IP，多个ip以“,”拼接

/*** 域名解析错误码*/
static NSString * const MSDKDns_Fail = @"-1";   // 失败
static NSString * const MSDKDns_Success = @"0"; // 成功

/** 上报事件*/
static NSString * const MSDKDnsEventHttpDnsfail = @"HttpDnsfail";
static NSString * const MSDKDnsEventHttpDnsSpend = @"HttpDnsSpend";

#endif
