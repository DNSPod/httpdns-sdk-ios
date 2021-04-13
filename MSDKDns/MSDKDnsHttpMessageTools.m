/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "MSDKDnsHttpMessageTools.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsParamsManager.h"
#import <objc/runtime.h>
#import "MSDKDns.h"

static NSString *const protocolKey = @"MSDKDnsHttpMessagePropertyKey";
static NSString *const kAnchorAlreadyAdded = @"AnchorAlreadyAdded";

@interface MSDKDnsHttpMessageTools () <NSStreamDelegate>

@property (strong, readwrite, nonatomic) NSMutableURLRequest *curRequest;
@property (strong, readwrite, nonatomic) NSRunLoop *curRunLoop;
@property (strong, readwrite, nonatomic) NSInputStream *inputStream;

@end

@implementation MSDKDnsHttpMessageTools

/**
 *  是否拦截处理指定的请求
 *
 *  @param request 指定的请求
 *
 *  @return 返回YES表示要拦截处理，返回NO表示不拦截处理
 */
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    
    /* 防止无限循环，因为一个请求在被拦截处理过程中，也会发起一个请求，这样又会走到这里，如果不进行处理，就会造成无限循环 */
    if ([NSURLProtocol propertyForKey:protocolKey inRequest:request]) {
        return NO;
    }
    NSString * url = request.URL.absoluteString;
    NSString * domain = [request.allHTTPHeaderFields objectForKey:@"host"];
    
    NSArray * hijackDomainArray = [[[MSDKDnsParamsManager shareInstance] hijackDomainArray] copy];
    NSArray * noHijackDomainArray = [[[MSDKDnsParamsManager shareInstance] noHijackDomainArray] copy];
    
    if (hijackDomainArray && (hijackDomainArray.count > 0)) {
        if ([url hasPrefix:@"https"] && [hijackDomainArray containsObject:domain]) {
            return YES;
        } else {
            return NO;
        }
    }
    if (noHijackDomainArray && (noHijackDomainArray.count > 0)) {
        if ([noHijackDomainArray containsObject:domain]) {
            return NO;
        }
    }
    // 如果url以https开头，且不为httpdns服务器ip，则进行拦截处理，否则不处理
    NSString *dnsIp = [[MSDKDnsParamsManager shareInstance] msdkDnsGetMDnsIp];
    if ([url hasPrefix:@"https"] && ![url containsString:dnsIp]) {
        return YES;
    }
    return NO;
}

/**
 * 如果需要对请求进行重定向，添加指定头部等操作，可以在该方法中进行
 */
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

/**
 * 开始加载，在该方法中，加载一个请求
 */
- (void)startLoading {
    NSMutableURLRequest *request = [self.request mutableCopy];
    // 表示该请求已经被处理，防止无限循环
    [NSURLProtocol setProperty:@(YES) forKey:protocolKey inRequest:request];
    self.curRequest = request;
    [self startRequest];
}

/**
 * 取消请求
 */
- (void)stopLoading {
    if (_inputStream.streamStatus == NSStreamStatusOpen) {
        [_inputStream removeFromRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
        [_inputStream setDelegate:nil];
        [_inputStream close];
    }
    [self.client URLProtocol:self didFailWithError:[[NSError alloc] initWithDomain:@"stop loading" code:-1 userInfo:nil]];
}

/**
 * 使用CFHTTPMessage转发请求
 */
- (void)startRequest {
    // 原请求的header信息
    NSDictionary *headFields = _curRequest.allHTTPHeaderFields;
    // 添加http post请求所附带的数据
    CFStringRef requestBody = CFSTR("");
    CFDataRef bodyData = CFStringCreateExternalRepresentation(kCFAllocatorDefault, requestBody, kCFStringEncodingUTF8, 0);
    if (_curRequest.HTTPBody) {
        bodyData = (__bridge_retained CFDataRef) _curRequest.HTTPBody;
    } else if (headFields[@"originalBody"]) {
        // 使用NSURLSession发POST请求时，将原始HTTPBody从header中取出
        bodyData = (__bridge_retained CFDataRef) [headFields[@"originalBody"] dataUsingEncoding:NSUTF8StringEncoding];
    }
    
    CFStringRef url = (__bridge CFStringRef) [_curRequest.URL absoluteString];
    CFURLRef requestURL = CFURLCreateWithString(kCFAllocatorDefault, url, NULL);
    
    // 原请求所使用的方法，GET或POST
    CFStringRef requestMethod = (__bridge_retained CFStringRef) _curRequest.HTTPMethod;
    
    // 根据请求的url、方法、版本创建CFHTTPMessageRef对象
    CFHTTPMessageRef cfrequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, requestURL, kCFHTTPVersion1_1);
    CFHTTPMessageSetBody(cfrequest, bodyData);
    
    // copy原请求的header信息
    for (NSString *header in headFields) {
        if (![header isEqualToString:@"originalBody"]) {
            // 不包含POST请求时存放在header的body信息
            CFStringRef requestHeader = (__bridge CFStringRef) header;
            CFStringRef requestHeaderValue = (__bridge CFStringRef) [headFields valueForKey:header];
            CFHTTPMessageSetHeaderFieldValue(cfrequest, requestHeader, requestHeaderValue);
        }
    }
    
    // 创建CFHTTPMessage对象的输入流
    CFReadStreamRef readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, cfrequest);
    self.inputStream = (__bridge_transfer NSInputStream *) readStream;
    
    // 设置SNI host信息，关键步骤
    NSString *host = [_curRequest.allHTTPHeaderFields objectForKey:@"host"];
    if (!host) {
        host = _curRequest.URL.host;
    }
    [_inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    NSDictionary *sslProperties = [[NSDictionary alloc] initWithObjectsAndKeys: host, (__bridge id) kCFStreamSSLPeerName, nil];
    [_inputStream setProperty:sslProperties forKey:(__bridge_transfer NSString *) kCFStreamPropertySSLSettings];
    [_inputStream setDelegate:self];
    
    if (!_curRunLoop)
        // 保存当前线程的runloop，这对于重定向的请求很关键
        self.curRunLoop = [NSRunLoop currentRunLoop];
    // 将请求放入当前runloop的事件队列
    [_inputStream scheduleInRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
    [_inputStream open];
    
    CFRelease(cfrequest);
    CFRelease(requestURL);
    // ARC模式下，需注释此句
    // CFRelease(url);
    cfrequest = NULL;
    CFRelease(bodyData);
    CFRelease(requestBody);
    CFRelease(requestMethod);
}

/**
 * 根据服务器返回的响应内容进行不同的处理
 */
- (void)handleResponse {
    // 获取响应头部信息
    CFReadStreamRef readStream = (__bridge_retained CFReadStreamRef) _inputStream;
    CFHTTPMessageRef message = (CFHTTPMessageRef) CFReadStreamCopyProperty(readStream, kCFStreamPropertyHTTPResponseHeader);
    if (CFHTTPMessageIsHeaderComplete(message)) {
        // 确保response头部信息完整
        NSDictionary *headDict = (__bridge NSDictionary *) (CFHTTPMessageCopyAllHeaderFields(message));
        
        // 获取响应头部的状态码
        CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(message);
        
        // 把当前请求关闭
        [_inputStream removeFromRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
        [_inputStream setDelegate:nil];
        [_inputStream close];
        
        if (statusCode >= 200 && statusCode < 300) {
            // 返回码为2xx，直接通知client
            [self.client URLProtocolDidFinishLoading:self];
        } else if (statusCode >= 300 && statusCode < 400) {
            // 返回码为3xx，需要重定向请求，继续访问重定向页面
            NSString *location = headDict[@"Location"];
            if (!location) {
                location = headDict[@"location"];
            }
            if (!location) {
                // 直接返回响应信息给client
                if (statusCode == 304) {
                    NSURL* url = (__bridge NSURL *) CFHTTPMessageCopyRequestURL(message);
                    NSString* httpVersion = (__bridge NSString *) CFHTTPMessageCopyVersion(message);
                    NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:statusCode HTTPVersion:httpVersion headerFields:headDict];
                    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                }
                [self.client URLProtocolDidFinishLoading:self];
                return;
            }
            NSURL *url = [[NSURL alloc] initWithString:location];
            _curRequest.URL = url;
            if ([[_curRequest.HTTPMethod lowercaseString] isEqualToString:@"post"]) {
                // 根据RFC文档，当重定向请求为POST请求时，要将其转换为GET请求
                _curRequest.HTTPMethod = @"GET";
                _curRequest.HTTPBody = nil;
            }
            
            /***********重定向通知client处理或内部处理*************/
            // client处理
            // NSURLResponse* response = [[NSURLResponse alloc] initWithURL:curRequest.URL MIMEType:headDict[@"Content-Type"] expectedContentLength:[headDict[@"Content-Length"] integerValue] textEncodingName:@"UTF8"];
            // [self.client URLProtocol:self wasRedirectedToRequest:curRequest redirectResponse:response];
            
            // 内部处理，将url中的host通过HTTPDNS转换为IP，不能在startLoading线程中进行同步网络请求，会被阻塞
            __block NSArray* result;
            [[MSDKDns sharedInstance] WGGetHostByNameAsync:url.host returnIps:^(NSArray *ipsArray) {
                result = ipsArray;
            }];
            NSString *ip = nil;
            if (result && result.count > 1) {
                if (![result[1] isEqualToString:@"0"]) {
                    ip = result[1];
                } else {
                    ip = result[0];
                }
            }
            if (ip && ip.length > 0 && ![ip isEqualToString:@"0"]) {
                MSDKDNSLOG(@"Get IP from HTTPDNS Successfully!");
                NSRange hostFirstRange = [location rangeOfString:url.host];
                if (NSNotFound != hostFirstRange.location) {
                    NSString *Url = [location stringByReplacingCharactersInRange:hostFirstRange withString:ip];
                    _curRequest.URL = [NSURL URLWithString:Url];
                    [_curRequest setValue:url.host forHTTPHeaderField:@"host"];
                }
            }
            [self startRequest];
        } else {
            // 其他情况，直接返回响应信息给client
            [self.client URLProtocolDidFinishLoading:self];
        }
    } else {
        // 头部信息不完整，关闭inputstream，通知client
        [_inputStream removeFromRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
        [_inputStream setDelegate:nil];
        [_inputStream close];
        [self.client URLProtocolDidFinishLoading:self];
    }
}

#pragma mark - NSStreamDelegate
/**
 * input stream 收到header complete后的回调函数
 */
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    if (eventCode == NSStreamEventHasBytesAvailable) {
        CFReadStreamRef readStream = (__bridge_retained CFReadStreamRef) aStream;
        CFHTTPMessageRef message = (CFHTTPMessageRef) CFReadStreamCopyProperty(readStream, kCFStreamPropertyHTTPResponseHeader);
        if (CFHTTPMessageIsHeaderComplete(message)) {
            // 以防response的header信息不完整
            UInt8 buffer[16 * 1024];
            UInt8 *buf = NULL;
            NSUInteger length = 0;
            NSInputStream *inputstream = (NSInputStream *) aStream;
            NSNumber *alreadyAdded = objc_getAssociatedObject(aStream, (__bridge const void *)(kAnchorAlreadyAdded));
            if (!alreadyAdded || ![alreadyAdded boolValue]) {
                objc_setAssociatedObject(aStream, (__bridge const void *)(kAnchorAlreadyAdded), [NSNumber numberWithBool:YES], OBJC_ASSOCIATION_COPY);
                // 通知client已收到response，只通知一次
                NSDictionary *headDict = (__bridge NSDictionary *) (CFHTTPMessageCopyAllHeaderFields(message));
                CFStringRef httpVersion = CFHTTPMessageCopyVersion(message);
                // 获取响应头部的状态码
                CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(message);
                NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:_curRequest.URL statusCode:statusCode HTTPVersion:(__bridge NSString *) httpVersion headerFields:headDict];
                
                [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                
                // 验证证书
                SecTrustRef trust = (__bridge SecTrustRef) [aStream propertyForKey:(__bridge NSString *) kCFStreamPropertySSLPeerTrust];
                SecTrustResultType res = kSecTrustResultInvalid;
                NSMutableArray *policies = [NSMutableArray array];
                NSString *domain = [[_curRequest allHTTPHeaderFields] valueForKey:@"host"];
                if (domain) {
                    [policies addObject:(__bridge_transfer id) SecPolicyCreateSSL(true, (__bridge CFStringRef) domain)];
                } else {
                    [policies addObject:(__bridge_transfer id) SecPolicyCreateBasicX509()];
                }
                /*
                 * 绑定校验策略到服务端的证书上
                 */
                SecTrustSetPolicies(trust, (__bridge CFArrayRef) policies);
                if (SecTrustEvaluate(trust, &res) != errSecSuccess) {
                    [aStream removeFromRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
                    [aStream setDelegate:nil];
                    [aStream close];
                    [self.client URLProtocol:self didFailWithError:[[NSError alloc] initWithDomain:@"can not evaluate the server trust" code:-1 userInfo:nil]];
                }
                if (res != kSecTrustResultProceed && res != kSecTrustResultUnspecified) {
                    /* 证书验证不通过，关闭input stream */
                    [aStream removeFromRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
                    [aStream setDelegate:nil];
                    [aStream close];
                    [self.client URLProtocol:self didFailWithError:[[NSError alloc] initWithDomain:@"fail to evaluate the server trust" code:-1 userInfo:nil]];
                    
                } else {
                    // 证书通过，返回数据
                    if (![inputstream getBuffer:&buf length:&length]) {
                        NSInteger amount = [inputstream read:buffer maxLength:sizeof(buffer)];
                        buf = buffer;
                        length = amount;
                    }
                    NSData *data = [[NSData alloc] initWithBytes:buf length:length];
                    
                    [self.client URLProtocol:self didLoadData:data];
                }
            } else {
                // 证书已验证过，返回数据
                if (![inputstream getBuffer:&buf length:&length]) {
                    NSInteger amount = [inputstream read:buffer maxLength:sizeof(buffer)];
                    buf = buffer;
                    length = amount;
                }
                NSData *data = [[NSData alloc] initWithBytes:buf length:length];
                
                [self.client URLProtocol:self didLoadData:data];
            }
        }
    } else if (eventCode == NSStreamEventErrorOccurred) {
        [aStream removeFromRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
        [aStream setDelegate:nil];
        [aStream close];
        // 通知client发生错误了
        [self.client URLProtocol:self didFailWithError:[aStream streamError]];
    } else if (eventCode == NSStreamEventEndEncountered) {
        [self handleResponse];
    }
}

@end
