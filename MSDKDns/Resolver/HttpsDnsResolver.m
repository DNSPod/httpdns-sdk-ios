/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "HttpsDnsResolver.h"
#import "MSDKDnsService.h"
#import "MSDKDnsManager.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsInfoTool.h"
#import "MSDKDns.h"

@interface HttpsDnsResolver() <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (copy, nonatomic) NSString * dnsKey;
@property (nonatomic, assign) HttpDnsIPType ipType;
@property (nonatomic, assign) NSInteger encryptType;  // 0 des  1 aes

@end

@implementation HttpsDnsResolver

static NSURLSession *_resolveHOSTSession = nil;

- (instancetype)init {
    if (self = [super init]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
            _resolveHOSTSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
        });
    }
    return self;
}

- (void)dealloc {
    MSDKDNSLOG(@"HttpDnsResolver dealloc!");
}

- (void)startWithDomains:(NSArray *)domains timeOut:(float)timeOut dnsId:(int)dnsId dnsKey:(NSString *)dnsKey netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType
{
    [super startWithDomains:domains timeOut:timeOut dnsId:dnsId dnsKey:dnsKey netStack:netStack];
    NSString *domainStr = [domains componentsJoinedByString:@","];
    id<MSDKDnsResolverDelegate> delegate = self.delegate;
    self.errorCode = MSDKDns_UnResolve;
    if (!domainStr || domainStr.length == 0) {
        MSDKDNSLOG(@"HttpDns domain is must needed!"); 
        self.errorInfo = @"Domian is null";
        [self handleEmptyDomainWithDelegate:delegate];
        return;
    }
    [self initializePropertiesWithEncryptType:encryptType domains:domains dnsKey:dnsKey netStack:netStack];
    
    NSURL *httpDnsUrl = [MSDKDnsInfoTool httpsUrlWithDomain:domainStr dnsId:dnsId dnsKey:self.dnsKey ipType:self.ipType encryptType:_encryptType];
    
    if (httpDnsUrl) {
        [self startDataTaskWithHttpDnsUrl:httpDnsUrl domains:domains timeOut:timeOut delegate:delegate];
    } else {
        MSDKDNSLOG("HttpDns Request URL is null");
        self.errorInfo = @"httpUrl is null";
        [self handleEmptyDomainWithDelegate:delegate];
    }
}

- (void)handleEmptyDomainWithDelegate:(id<MSDKDnsResolverDelegate>)delegate {
    self.domainInfo = nil;
    self.isFinished = YES;
    self.isSucceed = NO;
    if (delegate && [delegate respondsToSelector:@selector(resolver:getDomainError:retry:)]) {
        [delegate resolver:self getDomainError:self.errorInfo retry:NO];
    }
}

- (void)initializePropertiesWithEncryptType:(NSInteger)encryptType domains:(NSArray *)domains dnsKey:(NSString *)dnsKey netStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack {
    self.dnsKey = [dnsKey copy];
    self.domainInfo = nil;
    self.errorInfo = nil;
    self.isFinished = NO;
    self.isSucceed = NO;
    self.encryptType = encryptType;
    MSDKDNSLOG(@"HttpDns startWithDomain: %@!", domains);
    self.ipType = HttpDnsTypeIPv4;
    if (netStack == msdkdns::MSDKDNS_ELocalIPStack_IPv6) {
        self.ipType = HttpDnsTypeIPv6;
    } else if (netStack == msdkdns::MSDKDNS_ELocalIPStack_Dual) {
        self.ipType = HttpDnsTypeDual;
    }
}

- (void)startDataTaskWithHttpDnsUrl:(NSURL *)httpDnsUrl domains:(NSArray *)domains timeOut:(float)timeOut delegate:(id<MSDKDnsResolverDelegate>)delegate {
    MSDKDNSLOG("HttpDns Request URL: %@", httpDnsUrl);
    NSURLRequest *request = [NSURLRequest requestWithURL:httpDnsUrl
                                               cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                           timeoutInterval:timeOut];
    NSURLSessionTask *task = [_resolveHOSTSession dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            [self handleDataTaskError:error delegate:delegate];
        } else {
            [self handleDataTaskSuccessWithData:data domains:domains response:response delegate:delegate];
        }
    }];
    [task resume];
}

- (void)handleDataTaskError:(NSError *)error delegate:(id<MSDKDnsResolverDelegate>)delegate {
    MSDKDNSLOG(@"HttpDns Failed:%@", [error userInfo]);
    self.domainInfo = nil;
    self.isFinished = YES;
    self.errorCode = MSDKDns_Timeout;
    self.isSucceed = NO;
    self.errorInfo = error.userInfo[@"NSLocalizedDescription"];
    if (delegate && [delegate respondsToSelector:@selector(resolver:getDomainError:retry:)]) {
        [delegate resolver:self getDomainError:self.errorInfo retry:YES];
    }
}

- (void)handleDataTaskSuccessWithData:(NSData *)data domains:(NSArray *)domains response:(NSURLResponse *)response delegate:(id<MSDKDnsResolverDelegate>)delegate {
    BOOL openOptimismCache = [[MSDKDnsManager shareInstance] isOpenOptimismCache];
    MSDKDNSLOG(@"HttpDns didReceiveData!");
    NSString * errorInfo = @"";
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
    self.statusCode = [httpResponse statusCode];
    if (data && data.length > 0) {
        NSString * decryptStr = nil;
        NSString * responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        MSDKDNSLOG(@"The httpdns responseStr:%@", responseStr);
        decryptStr = [self getDecryptStrWithResponseStr:responseStr];
        
        self.domainInfo = [self parseResultString:decryptStr];
        
        if (self.domainInfo && [self.domainInfo count] > 0) {
            self.isFinished = YES;
            self.errorCode = MSDKDns_Success;
            self.isSucceed = YES;
            if (openOptimismCache) {
                // 当开启了乐观DNS，将解析请求中部分数据为空的domains，执行清除缓存
                NSArray *successDomains = [self.domainInfo allKeys];
                NSMutableArray *needClearDomains = [[NSMutableArray alloc] init];;
                for (NSString *domain in domains) {
                    if (![successDomains containsObject:domain]){
                        //不包含成功的数据进行清除
                        [needClearDomains addObject:domain];
                    }
                }
                if (needClearDomains && needClearDomains.count > 0) {
                    [[MSDKDnsManager shareInstance] clearCacheForDomains:needClearDomains];
                }
            }
            if (delegate && [delegate respondsToSelector:@selector(resolver:didGetDomainInfo:)]) {
                [delegate resolver:self didGetDomainInfo:self.domainInfo];
            }
            return;
        } else {
            errorInfo = @"HttpDns Failed, responseStr is not format.";
            if (openOptimismCache) {
                // 当开启了乐观DNS 并且 解析请求返回的所有数据都为空，对domains执行清除缓存
                [[MSDKDnsManager shareInstance] clearCacheForDomains:domains];
            }
        }
    } else {
        errorInfo = @"HttpDns response data error!";
    }
    
    if (openOptimismCache && self.statusCode == 401) {
        // 当开启了乐观DNS 并且 底层解析接口返回401时，清除此解析请求涉及到的域名的本地缓存和持久化缓存
        [[MSDKDnsManager shareInstance] clearCacheForDomains:domains];
    }
    self.domainInfo = nil;
    self.isFinished = YES;
    self.isSucceed = NO;
    self.errorCode = MSDKDns_NoData;
    self.errorInfo = errorInfo;
    if (delegate && [delegate respondsToSelector:@selector(resolver:getDomainError:retry:)]) {
        [delegate resolver:self getDomainError:self.errorInfo retry:NO];
    }
}

- (NSString *)getDecryptStrWithResponseStr:(NSString *)responseStr {
    NSString *decryptStr = nil;
    if (self.encryptType != HttpDnsEncryptTypeHTTPS && self.dnsKey && self.dnsKey.length > 0) {
        if (self.encryptType == HttpDnsEncryptTypeDES) {
            decryptStr = [MSDKDnsInfoTool decryptUseDES:responseStr key:self.dnsKey];
        } else {
            decryptStr = [MSDKDnsInfoTool decryptUseAES:responseStr key:self.dnsKey];
        }
    } else if (self.encryptType == HttpDnsEncryptTypeHTTPS) {
        decryptStr = [responseStr copy];
    }
    return decryptStr;
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * __nullable credential))completionHandler {
    if (!challenge) {
        return;
    }
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential *credential = nil;

    NSURLRequest *request = task.originalRequest;
    NSDictionary *headerDict = request.allHTTPHeaderFields;

    //获取原始域名信息
    NSString *host = [headerDict objectForKey:@"host"];
    if (!host) {
        host = request.URL.host;
    }
    if ([challenge.protectionSpace.authenticationMethod  isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:host]) {
            disposition = NSURLSessionAuthChallengeUseCredential;
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    } else {
        disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    }
    // 对于其他的 challenges 直接使用默认的验证方案
    completionHandler(disposition,credential);
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain {
    /*
     * 创建证书校验策略
     */
    NSMutableArray *policies = [NSMutableArray array];
    if (domain) {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }
    
    /*
     * 绑定校验策略到服务端的证书上
     */
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
    
    /*
     * 评估当前serverTrust是否可信任，
     * 官方建议在result = kSecTrustResultUnspecified 或 kSecTrustResultProceed
     * 的情况下serverTrust可以被验证通过，https://developer.apple.com/library/ios/technotes/tn2232/_index.html
     * 关于SecTrustResultType的详细信息请参考SecTrust.h
     */
    SecTrustResultType result;
    SecTrustEvaluate(serverTrust, &result);
    
    return (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
}

#pragma mark - util
- (NSString *)getQueryDomain:(NSString *)str {
    // 删除域名后面添加的.
    if ([[str substringFromIndex:str.length - 1]  isEqual: @"."]) {
        return [str substringToIndex:str.length - 1];
    }
    return str;
}

- (void)parseSingleDomain:(NSString *)string intoDic:(NSDictionary *)resultDic {
    // 找到第一个冒号，进行拆分
    NSRange range = [string rangeOfString:@":"];
    if (range.location != NSNotFound) {
        NSString* queryDomain = [self getQueryDomain:[string substringToIndex:range.location]];
        NSString* ipString = [string substringFromIndex:range.location + 1];
        NSDictionary *domainInfo = [self parseAllIPString:ipString];
        if (queryDomain && domainInfo) {
            [resultDic setValue:domainInfo forKey:queryDomain];
        }
    }
}

- (NSDictionary *)parseResultString:(NSString *)string {
    NSDictionary *resultDic = [NSMutableDictionary dictionary];
    if ([MSDKDnsInfoTool isExist:string]){
        if ([string containsString:@"\n"]) {
            NSArray *lineArray = [string componentsSeparatedByString:@"\n"];
            for (int i = 0; i < [lineArray count]; i++) {
                NSString *lineString = [lineArray objectAtIndex:i];
                [self parseSingleDomain:lineString intoDic:resultDic];
            }
        } else {
            [self parseSingleDomain:string intoDic:resultDic];
        }
    }
    return resultDic;
}

- (NSDictionary *)parseAllIPString:(NSString *)ipString {
    NSArray *array = [ipString componentsSeparatedByString:@"|"];
    if (array && array.count == 2) {
        NSString * clientIP = array[1];
        NSString * tmp = array[0];
        if(tmp){
            if (self.ipType == HttpDnsTypeDual) {
                NSString *ipv4 = nil;
                NSString *ipv6 = nil;
                NSMutableDictionary *bothIPDict = [NSMutableDictionary dictionary];
                NSArray * tmpArr = [tmp componentsSeparatedByString:@"-"];
                if (tmpArr && [tmpArr count] == 2) {
                    ipv4 = tmpArr[0];
                    ipv6 = tmpArr[1];
                }
                if (ipv4) {
                    NSDictionary *result = [self parseIPString:ipv4 ClientIP:clientIP use4A:false];
                    if (result) {
                        [bothIPDict setObject:result forKey:@"ipv4"];
                    }
                }
                if (ipv6) {
                    NSDictionary *result = [self parseIPString:ipv6 ClientIP:clientIP use4A:true];
                    if (result) {
                        [bothIPDict setObject:result forKey:@"ipv6"];
                    }
                   
                }
                // 当双栈解析请求中ipv4和ipv6的结果都不符合预期，就返回ni走getDomainError逻辑
                if (bothIPDict.count == 0){
                    return nil;
                }
                return bothIPDict;
            } else {
                BOOL use4A = false;
                if (self.ipType == HttpDnsTypeIPv6) {
                    use4A = true;
                }
                return [self parseIPString:tmp ClientIP:clientIP use4A:use4A];
            }
        }
    }
    return nil;
}

-(NSDictionary *)parseIPString:(NSString *)ipString ClientIP:(NSString *)clientIP use4A:(BOOL)use4A {
    NSString *ipsStr = nil;
    NSString *ttl = nil;
    NSArray * tmpArr = [ipString componentsSeparatedByString:@","];
    if (tmpArr && [tmpArr count] == 2) {
        ipsStr = tmpArr[0];
        ttl = tmpArr[1];
    }
    NSString * tempStr = ipsStr.length > 1 ? [ipsStr substringFromIndex:ipsStr.length - 1] : @"";
    if ([tempStr isEqualToString:@";"]) {
        ipsStr = [ipsStr substringToIndex:ipsStr.length - 1];
    }
    NSArray *ipsArray = [ipsStr componentsSeparatedByString:@";"];
    //校验ip合法性
    BOOL isIPLegal = [self isIPLegal:ipsArray use4A:use4A];
    
    if (isIPLegal) {
        double timeInterval = [[NSDate date] timeIntervalSince1970];
        NSString * ttlExpried = [NSString stringWithFormat:@"%0.0f", (timeInterval + ttl.floatValue * 0.75)];
        NSString * timeConsuming = [NSString stringWithFormat:@"%d", [self dnsTimeConsuming]];
        NSString * channel = @"http";
        return @{kIP:ipsArray, kClientIP:clientIP, kTTL:ttl, kTTLExpired:ttlExpried, kDnsTimeConsuming:timeConsuming, kChannel:channel};
    }
    return nil;
}

@end
