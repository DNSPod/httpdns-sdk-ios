/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "MSDKDnsHttpMessageTools.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsParamsManager.h"
#import "MSDKDnsManager.h"
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
    NSLog(@"MSDKDnsHttpMessageTools");
    
    if([[request.URL absoluteString] isEqual:@"about:blank"]) {
        return NO;
    }
    
    /* 防止无限循环，因为一个请求在被拦截处理过程中，也会发起一个请求，这样又会走到这里，如果不进行处理，就会造成无限循环 */
    if ([NSURLProtocol propertyForKey:protocolKey inRequest:request]) {
        return NO;
    }
    NSString * url = request.URL.absoluteString;
    NSURL *URL = request.URL;
//    NSString * domain = [request.allHTTPHeaderFields objectForKey:@"host"];
    NSString * originHost = [request.allHTTPHeaderFields objectForKey:@"host"];
    NSString * domain = request.URL.host;
        
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
    NSString *dnsIp = [[MSDKDnsManager shareInstance] currentDnsServer];
    if (![url containsString:dnsIp]) {
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
    self.curRequest = [self applyHttpDnsIpDirectConnect:request];
    [self startRequest];
}

- (NSString *)cookieForURL:(NSURL *)URL {
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSMutableArray *cookieList = [NSMutableArray array];
    for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
        if (![self p_checkCookie:cookie URL:URL]) {
            continue;
        }
        [cookieList addObject:cookie];
    }
    
    if (cookieList.count > 0) {
        NSDictionary *cookieDic = [NSHTTPCookie requestHeaderFieldsWithCookies:cookieList];
        if ([cookieDic objectForKey:@"Cookie"]) {
            return cookieDic[@"Cookie"];
        }
    }
    return nil;
}


- (BOOL)p_checkCookie:(NSHTTPCookie *)cookie URL:(NSURL *)URL {
    if (cookie.domain.length <= 0 || URL.host.length <= 0) {
        return NO;
    }
    if ([URL.host containsString:cookie.domain]) {
        return YES;
    }
    return NO;
}

- (NSURLRequest*)applyHttpDnsIpDirectConnect:(NSURLRequest*)request {
    NSURL* originUrl = request.URL;
    NSString* originHost = originUrl.host;
    NSString *cookie = [self cookieForURL:originUrl];
    NSURL* newUrl = [self getIpAndReplace:[originUrl absoluteString]];
    
    NSMutableURLRequest* mutableRequest = [request copy];
    mutableRequest.URL = newUrl;
    [mutableRequest setValue:originHost forHTTPHeaderField:@"Host"];
    [mutableRequest setValue:cookie forHTTPHeaderField:@"Cookie"];
    
    return [mutableRequest copy];
}

- (NSURL*)getIpAndReplace:(NSString*)urlString {
    NSURL* url = [NSURL URLWithString:urlString];
    NSString* originHost = url.host;
    
    NSTimeInterval start = [[NSDate date] timeIntervalSince1970];
    NSArray* result = [[MSDKDns sharedInstance] WGGetHostByName:url.host];
    NSString* ip = nil;
    if (result && result.count > 1) {
        if (![result[0] isEqualToString:@"0"]) {
            ip = result[0];
        } else {
            ip = result[1];
        }
    }
    // 通过HTTPDNS获取IP成功，进行URL替换和HOST头设置
    if (originHost.length > 0 && ip.length > 0) {
        NSString* originUrlStringafterdispatch = [url absoluteString];
        NSRange hostRange = [originUrlStringafterdispatch rangeOfString:url.host];
        NSString* urlString = [originUrlStringafterdispatch stringByReplacingCharactersInRange:hostRange withString:ip];
        url = [NSURL URLWithString:urlString];
    }
    return url;
}

/**
 * 取消请求
 */
- (void)stopLoading {
    if (_inputStream.streamStatus == NSStreamStatusOpen) {
        [self closeStream:_inputStream];
    }
    [self.client URLProtocol:self didFailWithError:[[NSError alloc] initWithDomain:@"stop loading" code:-1 userInfo:nil]];
}

/**
 * 使用CFHTTPMessage转发请求
 */
- (void)startRequest {
    // 原请求的header信息
    NSDictionary *headFields = _curRequest.allHTTPHeaderFields;
    CFStringRef url = (__bridge CFStringRef) [_curRequest.URL absoluteString];
    CFURLRef requestURL = CFURLCreateWithString(kCFAllocatorDefault, url, NULL);
    // 原请求所使用的方法，GET或POST
    CFStringRef requestMethod = (__bridge_retained CFStringRef) _curRequest.HTTPMethod;
    // 根据请求的url、方法、版本创建CFHTTPMessageRef对象
    CFHTTPMessageRef cfrequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, requestURL, kCFHTTPVersion1_1);
    // 添加http post请求所附带的数据
    CFStringRef requestBody = CFSTR("");
    CFDataRef bodyData = CFStringCreateExternalRepresentation(kCFAllocatorDefault, requestBody, kCFStringEncodingUTF8, 0);
    if (_curRequest.HTTPBody) {
        bodyData = (__bridge_retained CFDataRef) _curRequest.HTTPBody;
    }  else if(_curRequest.HTTPBodyStream) {
        NSData *data = [self dataWithInputStream:_curRequest.HTTPBodyStream];
        CFDataRef body = (__bridge_retained CFDataRef) data;
        CFHTTPMessageSetBody(cfrequest, body);
        CFRelease(body);
    } else {
        CFHTTPMessageSetBody(cfrequest, bodyData);
    }
    
//    // copy原请求的header信息
//    for (NSString *header in headFields) {
//        if (![header isEqualToString:@"originalBody"]) {
//            // 不包含POST请求时存放在header的body信息
//            CFStringRef requestHeader = (__bridge CFStringRef) header;
//            CFStringRef requestHeaderValue = (__bridge CFStringRef) [headFields valueForKey:header];
//            CFHTTPMessageSetHeaderFieldValue(cfrequest, requestHeader, requestHeaderValue);
//        }
//    }
    // copy原请求的header信息
    for (NSString* header in headFields) {
        CFStringRef requestHeader = (__bridge CFStringRef) header;
        CFStringRef requestHeaderValue = (__bridge CFStringRef) [headFields valueForKey:header];
        CFHTTPMessageSetHeaderFieldValue(cfrequest, requestHeader, requestHeaderValue);
    }
    
    // 创建CFHTTPMessage对象的输入流
    CFReadStreamRef readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, cfrequest);
    self.inputStream = (__bridge_transfer NSInputStream *) readStream;
    
    // 设置SNI host信息，关键步骤
    NSString *host = [_curRequest.allHTTPHeaderFields objectForKey:@"host"];
    if (!host) {
        host = _curRequest.URL.host;
    }
    
    NSLog(@"requestMethod = %@", requestMethod);
    NSLog(@"requestURL = %@", requestURL);
    NSLog(@"host = %@", host);
    
    // 可以选择使用SSL或者TLS1.2，目前CFNetwork不支持HTTP2.0.
//    [_inputStream setProperty:(__bridge id)CFSTR("kCFStreamSocketSecurityLevelTLSv1_2") forKey:(__bridge id)kCFStreamPropertySocketSecurityLevel];
    
    [_inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    NSDictionary *sslProperties = [[NSDictionary alloc] initWithObjectsAndKeys: host, (__bridge id) kCFStreamSSLPeerName, nil];
    [_inputStream setProperty:sslProperties forKey:(__bridge_transfer NSString *) kCFStreamPropertySSLSettings];
    [_inputStream setDelegate:self];
    
    if (!_curRunLoop) {
        // 保存当前线程的runloop，这对于重定向的请求很关键
        self.curRunLoop = [NSRunLoop currentRunLoop];
    }
    // 将请求放入当前runloop的事件队列
    [_inputStream scheduleInRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
    [_inputStream open];
    
    CFRelease(bodyData);
    CFRelease(requestURL);
    CFRelease(cfrequest);
}

-(NSData*)dataWithInputStream:(NSInputStream*)stream {
  NSMutableData *data = [NSMutableData data];
  [stream open];
  NSInteger result;
  uint8_t buffer[1024];

  while ((result = [stream read:buffer maxLength:1024]) != 0) {
    if (result > 0) {
      // buffer contains result bytes of data to be handled
      [data appendBytes:buffer length:result];
    } else if (result < 0) {
      // The stream had an error. You can get an NSError object using [iStream streamError]
      data = nil;
      break;
    }
  }
  [stream close];
  return data;
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
            CFDictionaryRef allheaderFields = CFHTTPMessageCopyAllHeaderFields(message);
            NSDictionary *headDict = (__bridge NSDictionary *)allheaderFields;
            CFRelease(allheaderFields);
            NSNumber *alreadyAdded = objc_getAssociatedObject(aStream, (__bridge const void *)(kAnchorAlreadyAdded));
            if (!alreadyAdded || ![alreadyAdded boolValue]) {
                objc_setAssociatedObject(aStream, (__bridge const void *)(kAnchorAlreadyAdded), [NSNumber numberWithBool:YES], OBJC_ASSOCIATION_COPY);
                // 通知client已收到response，只通知一次
                
//                NSDictionary *headDict = (__bridge NSDictionary *) (CFHTTPMessageCopyAllHeaderFields(message));
                CFStringRef httpVersion = CFHTTPMessageCopyVersion(message);
                // 获取响应头部的状态码
                CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(message);
                NSLog(@"response header, url is %@, code is %ld, headDict = %@", [_curRequest.URL absoluteString], (long)statusCode, [headDict objectForKey:@"Content-Type"]);
                NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:_curRequest.URL statusCode:statusCode
                                                                         HTTPVersion:(__bridge NSString *) httpVersion headerFields:headDict];
                
                
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
                    [self closeStream:aStream];
                    [self.client URLProtocol:self didFailWithError:[[NSError alloc] initWithDomain:@"can not evaluate the server trust" code:-1 userInfo:nil]];
                    return;
                }
                if (res != kSecTrustResultProceed && res != kSecTrustResultUnspecified) {
                    /* 证书验证不通过，关闭input stream */
                    [self closeStream:aStream];
                    [self.client URLProtocol:self didFailWithError:[[NSError alloc] initWithDomain:@"fail to evaluate the server trust" code:-1 userInfo:nil]];
                } else {
                    // 证书校验通过
                    if (statusCode >= 300 && statusCode < 400) {
                        // 处理重定向错误码
                        [self closeStream:aStream];
                        [self handleRedirect:message];
                    } else {
                        // 返回成功收到的数据
                        if (![inputstream getBuffer:&buf length:&length]) {
                            NSInteger amount = [inputstream read:buffer maxLength:sizeof(buffer)];
                            buf = buffer;
                            length = amount;
                        }
                        if ((NSInteger)length >= 0) {
                            NSData *data = [[NSData alloc] initWithBytes:buf length:length];
                            if([[headDict objectForKey:@"Content-Type"] isEqualToString:@"text/css"]){
                                NSLog(@"处理css文件内容");
                                // 处理CSS文件内容，修改相对路径
                                NSString *cssString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                // 这里需要写一个函数来解析CSS文件内容，并转换所有的相对路径为绝对路径
                                cssString = [self convertRelativePathsInCSS:cssString];
                                NSData *newData = [cssString dataUsingEncoding:NSUTF8StringEncoding];
                                [self.client URLProtocol:self didLoadData:data];
                            }else{
                                [self.client URLProtocol:self didLoadData:data];
                            }
                            
                        } else {
                            NSError *error = inputstream.streamError;
                            if (!error) {
                                error = [[NSError alloc] initWithDomain:@"inputstream length is invalid"
                                                                   code:-2
                                                               userInfo:nil];
                            }
                            [aStream removeFromRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
                            [aStream setDelegate:nil];
                            [aStream close];
                            [self.client URLProtocol:self didFailWithError:error];
                        }
                    }
                }
            } else {
                // 证书已验证过，返回数据
                if (![inputstream getBuffer:&buf length:&length]) {
                    NSInteger amount = [inputstream read:buffer maxLength:sizeof(buffer)];
                    buf = buffer;
                    length = amount;
                }
                if ((NSInteger)length >= 0) {
                    NSData *data = [[NSData alloc] initWithBytes:buf length:length];
                    if([[headDict objectForKey:@"Content-Type"] isEqualToString:@"text/css"]){
                        NSLog(@"处理css文件内容");
                        // 处理CSS文件内容，修改相对路径
                        NSString *cssString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        // 这里需要写一个函数来解析CSS文件内容，并转换所有的相对路径为绝对路径
                        cssString = [self convertRelativePathsInCSS:cssString];
                        NSData *newData = [cssString dataUsingEncoding:NSUTF8StringEncoding];
                        [self.client URLProtocol:self didLoadData:data];
                    }else{
                        [self.client URLProtocol:self didLoadData:data];
                    }
                    
                } else {
                    NSError *error = inputstream.streamError;
                    if (!error) {
                        error = [[NSError alloc] initWithDomain:@"inputstream length is invalid"
                                                                    code:-2
                                                                userInfo:nil];
                    }
                    [aStream removeFromRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
                    [aStream setDelegate:nil];
                    [aStream close];
                    [self.client URLProtocol:self didFailWithError:error];
                }
            }
            CFRelease((CFReadStreamRef)inputstream);
            CFRelease(message);
        }
    } else if (eventCode == NSStreamEventErrorOccurred) {
        [self closeStream:aStream];
        // 通知client发生错误了
//        [self.client URLProtocol:self didFailWithError:[aStream streamError]];
        [self.client URLProtocol:self didFailWithError:
        [[NSError alloc] initWithDomain:@"NSStreamEventErrorOccurred" code:-1 userInfo:nil]];
    } else if (eventCode == NSStreamEventEndEncountered) {
        [self closeStream:_inputStream];
        [self.client URLProtocolDidFinishLoading:self];
//        [self handleResponse];
    }
}

- (NSString *)convertRelativePathsInCSS:(NSString *)cssContent {
    // 使用适当的正则表达式找到相对路径并替换为绝对路径
    // 以下代码仅作为示例：
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"url\\([']?(?:\\.\\./)*([^')]+)[']?\\)" options:NSRegularExpressionCaseInsensitive error:nil];
    NSString *modifiedCSS = [regex stringByReplacingMatchesInString:cssContent options:0 range:NSMakeRange(0, cssContent.length) withTemplate:@"url(https://actcdn.eebbk.com/parent_manage/$1)"];
    return modifiedCSS;
}

- (void)closeStream:(NSStream*)stream {
    [stream removeFromRunLoop:_curRunLoop forMode:NSRunLoopCommonModes];
    [stream setDelegate:nil];
    [stream close];
}

- (void)handleRedirect:(CFHTTPMessageRef)messageRef {
    // 响应头
    CFDictionaryRef headerFieldsRef = CFHTTPMessageCopyAllHeaderFields(messageRef);
    NSDictionary *headDict = (__bridge_transfer NSDictionary *)headerFieldsRef;
    [self redirect:headDict];
}

- (void)redirect:(NSDictionary *)headDict {
    // 重定向时如果有cookie需求的话，注意处理
    NSString *location = headDict[@"Location"];
    if (!location)
        location = headDict[@"location"];
    NSURL *url = [[NSURL alloc] initWithString:location];
    NSLog(@"location = %@", location);
    _curRequest.URL = url;
    if ([[_curRequest.HTTPMethod lowercaseString] isEqualToString:@"post"]) {
        // 根据RFC文档，当重定向请求为POST请求时，要将其转换为GET请求
        _curRequest.HTTPMethod = @"GET";
        _curRequest.HTTPBody = nil;
    }
    
    _curRequest.URL = [self getIpAndReplace:[url absoluteString]];
    [_curRequest setValue:url.host forHTTPHeaderField:@"host"];
    [self startRequest];
}

@end
