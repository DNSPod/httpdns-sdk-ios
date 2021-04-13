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
@property (nonatomic, assign) BOOL use4A;
@property (nonatomic, assign) NSInteger encryptType;  // 0 des  1 aes

@end

@implementation HttpsDnsResolver

- (void)dealloc {
    MSDKDNSLOG(@"HttpDnsResolver dealloc!");
    [self setResponseData:nil];
    [self.connection cancel];
    [self setConnection:nil];
}

- (void)startWithDomain:(NSString *)domain TimeOut:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack
{
    [self startWithDomain:domain TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack encryptType:0];
}

- (void)startWithDomain:(NSString *)domain TimeOut:(float)timeOut DnsId:(int)dnsId DnsKey:(NSString *)dnsKey NetStack:(msdkdns::MSDKDNS_TLocalIPStack)netStack encryptType:(NSInteger)encryptType
{
    [super startWithDomain:domain TimeOut:timeOut DnsId:dnsId DnsKey:dnsKey NetStack:netStack];
    if (!domain || domain.length == 0) {
        MSDKDNSLOG(@"HttpDns Domain is must needed!");
        self.domainInfo = nil;
        self.isFinished = YES;
        self.isSucceed = NO;
        self.errorInfo = @"Domian is null";
        if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:getDomainError:)]) {
            [self.delegate resolver:self getDomainError:self.errorInfo];
        }
        return;
    }
    self.dnsKey = [dnsKey copy];
    self.domainInfo = nil;
    self.errorInfo = nil;
    self.isFinished = NO;
    self.isSucceed = NO;
    self.encryptType = encryptType;
    MSDKDNSLOG(@"HttpDns startWithDomain: %@!", domain);
    self.use4A = NO;
    if (netStack == msdkdns::MSDKDNS_ELocalIPStack_IPv6) {
        self.use4A = YES;
    }
    NSURL * httpDnsUrl = [MSDKDnsInfoTool httpsUrlWithDomain:domain DnsId:dnsId DnsKey:_dnsKey Use4A:_use4A encryptType:_encryptType];
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
        if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:getDomainError:)]) {
            [self.delegate resolver:self getDomainError:self.errorInfo];
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
        NSArray * resultArr = nil;
        NSString * responseStr = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding];
        MSDKDNSLOG(@"The httpdns responseStr:%@", responseStr);
        if (_dnsKey && _dnsKey.length > 0) {
            if (_encryptType == 0) {
                decryptStr = [MSDKDnsInfoTool decryptUseDES:responseStr key:_dnsKey];
            } else {
                decryptStr = [MSDKDnsInfoTool decryptUseAES:responseStr key:_dnsKey];
            }
        }
        if (decryptStr) {
            resultArr = [decryptStr componentsSeparatedByString:@"|"];
        }

        // 返回格式 59.37.96.63;14.17.42.40;14.17.32.211,152|59.37.125.44
        if (resultArr && resultArr.count == 2) {
            MSDKDNSLOG(@"HttpDns Succeed:%@", decryptStr);
            NSString * ipsStr = nil;
            NSString * ttl = nil;
            NSString * clientIP = resultArr[1];
            NSString * tmp = resultArr[0];
            if (tmp) {
                NSArray * tmpArr = [tmp componentsSeparatedByString:@","];
                if (tmpArr && [tmpArr count] == 2) {
                    ipsStr = tmpArr[0];
                    ttl = tmpArr[1];
                }
            }
            NSString * tempStr = ipsStr.length > 1 ? [ipsStr substringFromIndex:ipsStr.length - 1] : @"";
            if ([tempStr isEqualToString:@";"]) {
                ipsStr = [ipsStr substringToIndex:ipsStr.length - 1];
            }
            NSArray * ipsArray = [ipsStr componentsSeparatedByString:@";"];
            //校验ip合法性
            BOOL isIPLegal = [self isIPLegal:ipsArray Use4A:_use4A];
            
            if (isIPLegal) {
                double timeInterval = [[NSDate date] timeIntervalSince1970];
                NSString * ttlExpried = [NSString stringWithFormat:@"%0.0f", (timeInterval + ttl.floatValue * 0.75)];
                NSString * timeConsuming = [NSString stringWithFormat:@"%d", [self dnsTimeConsuming]];
                NSString * channel = @"http";
                self.domainInfo = @{kIP:ipsArray, kClientIP:clientIP, kTTL:ttl, kTTLExpired:ttlExpried, kDnsTimeConsuming:timeConsuming, kChannel:channel};
                self.isFinished = YES;
                self.isSucceed = YES;
                if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:didGetDomainInfo:)]) {
                    [self.delegate resolver:self didGetDomainInfo:self.domainInfo];
                }
                CFRunLoopStop(self.rl);
                return;
            } else {
                MSDKDNSLOG(@"HttpDns Failed with errorInfo:%@", errorInfo);
            }
        } else {
            MSDKDNSLOG(@"HttpDns Failed, resultArr is not format.");
        }
    } else {
        errorInfo = @"HttpDns response data error!";
    }
    
    self.domainInfo = nil;
    self.isFinished = YES;
    self.isSucceed = NO;
    self.errorInfo = errorInfo;
    if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:getDomainError:)]) {
        [self.delegate resolver:self getDomainError:self.errorInfo];
    }
    CFRunLoopStop(self.rl);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    MSDKDNSLOG(@"HttpDns Failed:%@",[error userInfo]);
    self.domainInfo = nil;
    self.isFinished = YES;
    self.isSucceed = NO;
    self.errorInfo = error.userInfo[@"NSLocalizedDescription"];
    if (self.delegate && [self.delegate respondsToSelector:@selector(resolver:getDomainError:)]) {
        [self.delegate resolver:self getDomainError:self.errorInfo];
    }
    CFRunLoopStop(self.rl);
}

@end
