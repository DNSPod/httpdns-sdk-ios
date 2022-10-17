/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "HttpsDnsResolver.h"
#import "MSDKDnsService.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsInfoTool.h"

@interface HttpsDnsResolver() <NSURLConnectionDelegate,NSURLConnectionDataDelegate>

@property (strong, nonatomic) NSMutableData * responseData;
@property (strong, nonatomic) NSURLConnection * connection;
@property (nonatomic , assign) CFRunLoopRef rl;
@property (copy, nonatomic) NSString * dnsKey;
@property (nonatomic, assign) HttpDnsIPType ipType;
@property (nonatomic, assign) NSInteger encryptType;  // 0 des  1 aes

@end

@implementation HttpsDnsResolver

- (void)dealloc {
    MSDKDNSLOG(@"HttpDnsResolver dealloc!");
    [self setResponseData:nil];
    [self.connection cancel];
    [self setConnection:nil];
}

- (void)startWithDomains:(NSArray *)domains TimeOut:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType
{
    [super startWithDomains:domains TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack];
    NSString *domainStr = [domains componentsJoinedByString:@","];
    self.errorCode = MSDKDns_UnResolve;
    if (!domainStr || domainStr.length == 0) {
        MSDKDNSLOG(@"HttpDns Domain is must needed!");
        self.domainInfo = nil;
        self.isFinished = YES;
        self.isSucceed = NO;
        self.errorInfo = @"Domian is null";
        if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:getDomainError:retry:)]) {
            [self.delegate resolver:self getDomainError:self.errorInfo retry:NO];
        }
        return;
    }
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
    }else if (netStack == msdkdns::MSDKDNS_ELocalIPStack_Dual) {
        self.ipType = HttpDnsTypeDual;
    }
    
    NSURL * httpDnsUrl = [MSDKDnsInfoTool httpsUrlWithDomain:domainStr DnsId:dnsId DnsKey:_dnsKey IPType:self.ipType encryptType:_encryptType];
    if (httpDnsUrl) {
        MSDKDNSLOG(@"HttpDns TimeOut is %f", timeOut);
        NSURLRequest * request = [NSURLRequest requestWithURL:httpDnsUrl cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeOut];
        self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
        [self.connection start];
        self.rl = CFRunLoopGetCurrent();
        CFRunLoopRun();
    } else {
        self.domainInfo = nil;
        self.isFinished = YES;
        self.isSucceed = NO;
        self.errorInfo = @"httpUrl is null";
        if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:getDomainError:retry:)]) {
            [self.delegate resolver:self getDomainError:self.errorInfo retry:NO];
        }
    }
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    MSDKDNSLOG(@"https willSendRequestForAuthenticationChallenge");
    if (!challenge) {
        return;
    }
    
    /*
     * URL里面的host在使用HTTPDNS的情况下被设置成了IP，此处从HTTP Header中获取真实域名
     */
    NSURLRequest *request = connection.originalRequest;
    NSDictionary *headerDict = request.allHTTPHeaderFields;
    NSString *host = headerDict[@"Host"];
    if (host == nil || [host length] == 0) {
        host = headerDict[@"host"];
    }
    
    /*
     * 判断challenge的身份验证方法是否是NSURLAuthenticationMethodServerTrust（HTTPS模式下会进行该身份验证流程），
     * 在没有配置身份验证方法的情况下进行默认的网络请求流程。
     */
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:host]) {
            /*
             * 验证完以后，需要构造一个NSURLCredential发送给发起方
             */
            NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
        } else {
            /*
             * 验证失败，取消这次验证流程
             */
            [[challenge sender] cancelAuthenticationChallenge:challenge];
        }
    } else {
        /*
         * 对于其他验证方法直接进行处理流程
         */
        [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
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

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    MSDKDNSLOG(@"HttpDnsResolver didReceiveResponse!");
    self.responseData = nil;
    self.responseData = [NSMutableData new];
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
    self.statusCode = [httpResponse statusCode];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    MSDKDNSLOG(@"HttpDnsResolver didReceiveData!");
    if (data && data.length > 0) {
        [self.responseData appendData:data];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    MSDKDNSLOG(@"connectionDidFinishLoading: %@", self.responseData);
    NSString * errorInfo = @"";
    if (self.responseData.length > 0) {
        NSString * decryptStr = nil;
        NSString * responseStr = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
        MSDKDNSLOG(@"The httpdns responseStr:%@", responseStr);
        if (_encryptType != 2 && _dnsKey && _dnsKey.length > 0) {
            if (_encryptType == 0) {
                decryptStr = [MSDKDnsInfoTool decryptUseDES:responseStr key:_dnsKey];
            } else {
                decryptStr = [MSDKDnsInfoTool decryptUseAES:responseStr key:_dnsKey];
            }
        } else if (_encryptType == 2) {
            decryptStr = [responseStr copy];
        }
        
        self.domainInfo = [self parseResultString:decryptStr];
        
        if (self.domainInfo && [self.domainInfo count] > 0) {
            self.isFinished = YES;
            self.errorCode = MSDKDns_Success;
            self.isSucceed = YES;
            if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:didGetDomainInfo:)]) {
                [self.delegate resolver:self didGetDomainInfo:self.domainInfo];
            }
            CFRunLoopStop(self.rl);
            return;
        } else {
            errorInfo = @"HttpDns Failed, responseStr is not format.";
        }
    } else {
        errorInfo = @"HttpDns response data error!";
    }
    
    self.domainInfo = nil;
    self.isFinished = YES;
    self.isSucceed = NO;
    self.errorCode = MSDKDns_NoData;
    self.errorInfo = errorInfo;
    if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:getDomainError:retry:)]) {
        [self.delegate resolver:self getDomainError:self.errorInfo retry:NO];
    }
    CFRunLoopStop(self.rl);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    MSDKDNSLOG(@"HttpDns Failed:%@",[error userInfo]);
    self.domainInfo = nil;
    self.isFinished = YES;
    self.errorCode = MSDKDns_Timeout;
    self.isSucceed = NO;
    self.errorInfo = error.userInfo[@"NSLocalizedDescription"];
    if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:getDomainError:retry:)]) {
        [self.delegate resolver:self getDomainError:self.errorInfo retry:YES];
    }
    CFRunLoopStop(self.rl);
}

#pragma mark -
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
    if ([string containsString:@"\n"]) {
        NSArray *lineArray = [string componentsSeparatedByString:@"\n"];
        for (int i = 0; i < [lineArray count]; i++) {
            NSString *lineString = [lineArray objectAtIndex:i];
            [self parseSingleDomain:lineString intoDic:resultDic];
        }
    } else {
        [self parseSingleDomain:string intoDic:resultDic];
    }
    return resultDic;
}

- (NSDictionary *)parseAllIPString:(NSString *)iPstring {
    NSArray *array = [iPstring componentsSeparatedByString:@"|"];
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
                    NSDictionary *result = [self parseIPString:ipv4 ClientIP:clientIP Use4A:false];
                    if (result) {
                        [bothIPDict setObject:result forKey:@"ipv4"];
                    }
                }
                if (ipv6) {
                    NSDictionary *result = [self parseIPString:ipv6 ClientIP:clientIP Use4A:true];
                    if (result) {
                        [bothIPDict setObject:result forKey:@"ipv6"];
                    }
                   
                }
                return bothIPDict;
            } else {
                BOOL use4A = false;
                if (self.ipType == HttpDnsTypeIPv6) {
                    use4A = true;
                }
                return [self parseIPString:tmp ClientIP:clientIP Use4A:use4A];
            }
        }
    }
    return nil;
}

-(NSDictionary *)parseIPString:(NSString *)iPstring ClientIP:(NSString *)clientIP Use4A:(BOOL)use4A {
    NSString *ipsStr = nil;
    NSString *ttl = nil;
    NSArray * tmpArr = [iPstring componentsSeparatedByString:@","];
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
    BOOL isIPLegal = [self isIPLegal:ipsArray Use4A:use4A];
    
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
