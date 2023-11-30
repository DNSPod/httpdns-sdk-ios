/**
 * Copyright (c) Tencent. All rights reserved.
 */

#import "MSDKDnsInfoTool.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsManager.h"
#import "MSDKDnsParamsManager.h"
#import <SystemConfiguration/CaptiveNetwork.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <err.h>
#import "aes.h"
#import "MSDKDns.h"
#if defined(__has_include)
    #if __has_include("httpdnsIps.h")
        #include "httpdnsIps.h"
    #endif
#endif

@implementation MSDKDnsInfoTool

+ (dispatch_queue_t) msdkdns_queue {
    static dispatch_queue_t msdkdns_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        msdkdns_queue = dispatch_queue_create("com.tencent.msdkdns", DISPATCH_QUEUE_SERIAL);
    });
    return msdkdns_queue;
}

+ (dispatch_queue_t) msdkdns_resolver_queue {
    static dispatch_queue_t msdkdns_resolver_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        msdkdns_resolver_queue = dispatch_queue_create("com.tencent.msdkdns.resolver_queue",DISPATCH_QUEUE_CONCURRENT);
    });
    return msdkdns_resolver_queue;
}

+ (dispatch_queue_t) msdkdns_local_queue {
    static dispatch_queue_t msdkdns_local_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        msdkdns_local_queue = dispatch_queue_create("com.tencent.msdkdns.local_queue", DISPATCH_QUEUE_SERIAL);
    });
    return msdkdns_local_queue;
}

+ (NSString *) getIPv6: (const char *)mHost {
    if (NULL == mHost)
        return nil;
    const char * newChar = "No";
    struct addrinfo * res0;
    struct addrinfo hints;
    struct addrinfo * res;
    int n, s;
    
    memset(&hints, 0, sizeof(hints));
    
    hints.ai_flags = AI_DEFAULT;
    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    
    n = getaddrinfo(mHost, "http", &hints, &res0);
    if (n != 0) {
        printf("getaddrinfo error: %s\n",gai_strerror(n));
        return nil;
    }
    
    struct sockaddr_in6 * addr6;
    struct sockaddr_in * addr;
    NSString * NewStr = nil;
    char ipbuf[32];
    s = -1;
    for (res = res0; res; res = res->ai_next) {
        if (res->ai_family == AF_INET6) {
            addr6 = (struct sockaddr_in6 *)res->ai_addr;
            newChar = inet_ntop(AF_INET6, &addr6->sin6_addr, ipbuf, sizeof(ipbuf));
            if (newChar != NULL) {
                NSString * TempA = [[NSString alloc] initWithCString:(const char *)newChar encoding:NSASCIIStringEncoding];
                if (TempA) {
                    NewStr = [NSString stringWithFormat:@"[%@]", TempA];
                    break;
                }
            }
        } else if (res->ai_family == AF_INET) {
            addr = (struct sockaddr_in *)res->ai_addr;
            newChar = inet_ntop(AF_INET, &addr->sin_addr, ipbuf, sizeof(ipbuf));
            if (newChar != NULL) {
                NSString * TempA = [[NSString alloc] initWithCString:(const char *)newChar encoding:NSASCIIStringEncoding];
                if (TempA) {
                    NewStr = TempA;
                    break;
                }
            }
        } else {
            MSDKDNSLOG(@"Neither IPv4 nor IPv6!");
        }
    }
    freeaddrinfo(res0);
    return NewStr;
}

char MSDKDnsByteToHexByte(char byte) {
    if (byte < 10) {
        return byte + '0';
    }
    return byte - 10 + 'a';
}

void MSDKDnsByteToHexChar(char byte, char *hex) {
    hex[0] = MSDKDnsByteToHexByte((byte >> 4) & 0x0F);
    hex[1] = MSDKDnsByteToHexByte(byte & 0x0F);
}

NSString * MSDKDnsDataToHexString(NSData *data) {
    if (!data) {
        return nil;
    }
    char hex[data.length * 2 + 1];
    const char *bytes = (const char *)data.bytes;
    for (NSUInteger i = 0; i < data.length; ++i) {
        MSDKDnsByteToHexChar(bytes[i], &hex[i * 2]);
    }
    hex[data.length * 2] = 0;
    return [NSString stringWithUTF8String:hex];
}

NSData * MSDKDNSHexStringToData(NSString *string) {
    if (!string) {
        return nil;
    }
    const char *tempBytes = [string UTF8String];
    NSUInteger tempLength = [string length];
    NSUInteger dataLength = tempLength / 2;
    char textBytes[dataLength];
    if (tempLength > 0) {
        for (int i  = 0; i < tempLength - 1; i = i + 2)
        {
            char high = tempBytes[i];
            char low = tempBytes[i + 1];
            char hex = MSDKDnsHexCharToChar(high, low);
            textBytes[i / 2] = hex;
        }
    }
    return [NSData dataWithBytes:textBytes length:dataLength];
}

char MSDKDnsHexByteToChar(char hex) {
    if (hex >= '0' && hex <= '9') {
        return hex - '0';
    }
    if (hex >= 'a' && hex <= 'f') {
        return hex - 'a' + 10;
    }
    if (hex >= 'A' && hex <= 'F') {
        return hex - 'A' + 10;
    }
    return 0;
}

char MSDKDnsHexCharToChar(char high, char low) {
    high = MSDKDnsHexByteToChar(high);
    low = MSDKDnsHexByteToChar(low);
    return (high << 4) | low;
}

+ (NSString *) encryptUseDES:(NSString *)plainText key:(NSString *)key {
    NSData *srcData = [plainText dataUsingEncoding:NSUTF8StringEncoding];
    size_t dataOutAvilable = ([srcData length] + kCCBlockSizeDES) & ~(kCCBlockSizeDES - 1);
    unsigned char dataOut[dataOutAvilable];
    memset(dataOut, 0x0, dataOutAvilable);
    size_t dataOutMoved = 0;
    
    char encryptKey[kCCKeySizeDES] = {0};
    strncpy(encryptKey, [key UTF8String], kCCKeySizeDES);
    
    CCCryptorStatus ccStatus = CCCrypt(kCCEncrypt,
                                       kCCAlgorithmDES,
                                       kCCOptionPKCS7Padding | kCCOptionECBMode,
                                       encryptKey,
                                       kCCKeySizeDES,
                                       NULL,
                                       srcData.bytes,
                                       srcData.length,
                                       dataOut,
                                       dataOutAvilable,
                                       &dataOutMoved);
    if (ccStatus == kCCSuccess) {
        NSData * resultData = [NSData dataWithBytes:dataOut length:(NSUInteger)dataOutMoved];
        return MSDKDnsDataToHexString(resultData);
    }
    return nil;
}

+ (NSString *) decryptUseDES:(NSString *)cipherString key:(NSString *)key {
    if (cipherString && key) {
        const char *tempBytes = [cipherString UTF8String];
        NSUInteger tempLength = [cipherString length];
        if (tempLength > 0) {
            NSUInteger dataLength = tempLength / 2;
            char textBytes[dataLength];
            for (int i  = 0; i < tempLength - 1; i = i + 2)
            {
                char high = tempBytes[i];
                char low = tempBytes[i + 1];
                char hex = MSDKDnsHexCharToChar(high, low);
                textBytes[i / 2] = hex;
            }
            
            size_t dataOutAvilable = (dataLength + kCCBlockSizeDES) & ~(kCCBlockSizeDES - 1);
            unsigned char dataOut[dataOutAvilable];
            memset(dataOut, 0x0, dataOutAvilable);
            size_t dataOutMoved = 0;
            
            char decryptKey[kCCKeySizeDES] = {0};
            strncpy(decryptKey, [key UTF8String], kCCKeySizeDES);
            CCCryptorStatus ccStatus = CCCrypt(kCCDecrypt,
                                               kCCAlgorithmDES,
                                               kCCOptionPKCS7Padding | kCCOptionECBMode,
                                               decryptKey,
                                               kCCKeySizeDES,
                                               NULL,
                                               textBytes,
                                               dataLength,
                                               dataOut,
                                               dataOutAvilable,
                                               &dataOutMoved);
            
            NSString *plainText = nil;
            if (ccStatus == kCCSuccess) {
                NSData *data = [NSData dataWithBytes:dataOut length:(NSUInteger)dataOutMoved];
                if (data) {
                    plainText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                }
            }
            return plainText;
        }
    }
    return nil;
}

// AES加密
+ (NSString *)encryptUseAES:(NSString *)plainText key:(NSString *)key
{
    if (!plainText || !key) {
        return nil;
    }
    NSString *ivStr = [self generateRandom];
//    plainText = @"t.tt";
//    ivStr = @"d3ddee42c7e6f08a1077abc4f7a59d6c";
//    Byte bytes[] = {0xd3,0xdd,0xee,0x42,0xc7,0xe6,0xf0,0x8a,0x10,0x77,0xab,0xc4,0xf7,0xa5,0x9d,0x6c};
//    MSDKDNSLOG(@"bytes 的16进制数为:%@",[self hexStringFromBytes:bytes length:16]);
    NSData *ivByte = [self bytesFromHexString:ivStr length:16];
    if (!ivStr) {
        return nil;
    }
    NSData *encryData = [self aesCryptWithKey:AES_ENCRYPT src:(unsigned char *)plainText.UTF8String srcLen:(int)plainText.length key:(unsigned char *)key.UTF8String aesIv:(unsigned char *)[ivByte bytes]];//(unsigned char *)temphead.bytes];
    NSString *encryString = MSDKDnsDataToHexString(encryData);
    
//    MSDKDNSLOG(@"加密 ||| realText:%@ encryString：%@，iv：%@",plainText,encryString,ivStr);
    return [ivStr stringByAppendingString:encryString];
}

// AES解密
+ (NSString *)decryptUseAES:(NSString *)cipherString key:(NSString *)key
{
    if (!cipherString || !key || cipherString.length <= 32) {
        return nil;
    }
    
    NSString *ivStr = [cipherString substringWithRange:NSMakeRange(0, 32)];
    NSData *ivByte = [self bytesFromHexString:ivStr length:16];

    NSString *realContent = [cipherString substringWithRange:NSMakeRange(32, cipherString.length - 32)];
    NSData *encryData = MSDKDNSHexStringToData(realContent);
    if (!encryData) {
        return nil;
    }
    NSData *dencryData = [self aesCryptWithKey:AES_DECRYPT src:(unsigned char *)[encryData bytes] srcLen:(int)encryData.length key:(unsigned char *)key.UTF8String aesIv:(unsigned char *)[ivByte bytes]];
    if (!dencryData) {
        return nil;
    }
    NSString *dencryString = [[NSString alloc] initWithData:dencryData encoding:NSUTF8StringEncoding];
    
//    MSDKDNSLOG(@"解密 === realContent：%@，iv：%@   dencryString:%@",realContent,ivStr,dencryString);

    return dencryString;
}

+ (NSData *)aesCryptWithKey:(int)mode
                        src:(unsigned char *)src
                     srcLen:(int)src_len
                        key:(unsigned char *)aes_key
                      aesIv:(unsigned char *)AES_IV
{
    int res_len = self_dns::AesGetOutLen(src_len, mode);
    unsigned char *res_buf = nullptr;
    // 注意这里是非字符串，二进制形式，不需要额外加一，留给\0
    if (res_len > 0) {
        res_buf = (unsigned char *)calloc(res_len, sizeof(unsigned char));
        // 注意: 解密后的长度可能会比output的长度要短，因为要预留padding长度
        if (res_buf != nullptr) { // 进行空指针判断
            int decodedLen = self_dns::AesCryptWithKey(src, src_len, res_buf, mode, aes_key, AES_IV);
            res_len = decodedLen < res_len ? decodedLen : res_len;
            NSData *ret = [NSData dataWithBytes:res_buf length:res_len];
            free(res_buf); // 在返回值之前释放res_buf
            return ret;
        }
    }
    return nil; // 如果分配内存失败，则返回nil
}

// 获取16个字节的随机串
+ (NSString *)generateRandom
{
    static int size = 16;
    uint8_t randomBytes[size];
    int result = SecRandomCopyBytes(kSecRandomDefault, size, randomBytes);
    if (result == errSecSuccess) {
        NSMutableString *randomString = [[NSMutableString alloc] initWithCapacity:size * 2];
        for (int i = 0; i < size; i++) {
            [randomString appendFormat:@"%02x", randomBytes[i]];
        }

        return randomString;
    } else {
        return nil;
    }
}

// bytes -> hexstring
+ (NSString *)hexStringFromBytes:(Byte *)bytes length:(int)strLen
{
    NSMutableString *hexStr = [NSMutableString string];
    for(int i=0; i < strLen; i++)
    {
        NSString *newHexStr = [NSString stringWithFormat:@"%x",bytes[i]&0xff];///16进制数
        if([newHexStr length]==1)
        {
            [hexStr appendFormat:@"0%@",newHexStr];
        } else {
            [hexStr appendFormat:@"%@",newHexStr];
        }
    }
    return [hexStr copy];
}

// hexstring -> bytes
+ (NSData *)bytesFromHexString:(NSString *)hexString length:(int)len
{
    int j=0;
    Byte bytes[len];
    for(int i=0;i<[hexString length];i++)
    {
        int int_ch;  /// 两位16进制数转化后的10进制数

        unichar hex_char1 = [hexString characterAtIndex:i]; ////两位16进制数中的第一位(高位*16)
        int int_ch1;
        if(hex_char1 >= '0' && hex_char1 <='9')
        int_ch1 = (hex_char1-48)*16;   //// 0 的Ascll - 48
        else if(hex_char1 >= 'A' && hex_char1 <='F')
        int_ch1 = (hex_char1-55)*16; //// A 的Ascll - 65
        else
        int_ch1 = (hex_char1-87)*16; //// a 的Ascll - 97
        i++;

        unichar hex_char2 = [hexString characterAtIndex:i]; ///两位16进制数中的第二位(低位)
        int int_ch2;
        if(hex_char2 >= '0' && hex_char2 <='9')
        int_ch2 = (hex_char2-48); //// 0 的Ascll - 48
        else if(hex_char1 >= 'A' && hex_char1 <='F')
        int_ch2 = hex_char2-55; //// A 的Ascll - 65
        else
        int_ch2 = hex_char2-87; //// a 的Ascll - 97

        int_ch = int_ch1+int_ch2;
        bytes[j] = int_ch;  ///将转化后的数放入Byte数组里
        j++;
    }
    NSData *newData = [[NSData alloc] initWithBytes:bytes length:len];
//    MSDKDNSLOG(@"newData=%@",newData);
    return newData;
}

+ (NSURL *) httpsUrlWithDomain:(NSString *)domain dnsId:(int)dnsId dnsKey:(NSString *)dnsKey ipType:(HttpDnsIPType)ipType
{
    return [self httpsUrlWithDomain:domain dnsId:dnsId dnsKey:dnsKey ipType:ipType encryptType:HttpDnsEncryptTypeDES];
}

+ (NSURL *) httpsUrlWithDomain:(NSString *)domain dnsId:(int)dnsId dnsKey:(NSString *)dnsKey ipType:(HttpDnsIPType)ipType encryptType:(NSInteger)encryptType
{
    if (!domain || domain.length == 0) {
        MSDKDNSLOG(@"HttpDns domain cannot be empty!");
        return nil;
    }
    
    if (!dnsId) {
        MSDKDNSLOG(@"dnsId cannot be empty! Please check your dns config params.");
        return nil;
    }
        
    NSString *token =  [[MSDKDnsParamsManager shareInstance] msdkDnsGetMToken];
    if (encryptType != HttpDnsEncryptTypeHTTPS && (!dnsKey || dnsKey.length == 0)) {
        MSDKDNSLOG(@"dnsKey cannot be empty! Please check your dns config params");
        return nil;
    } else if (encryptType == HttpDnsEncryptTypeHTTPS && (!token || token.length == 0)) {
        MSDKDNSLOG(@"Token cannot be empty! Please check your dns config params");
        return nil;
    }
    
    //域名需加密，内外部加密秘钥以及url字段需要区分
    NSString *domainEncrypStr = nil;
    NSString *protocol = @"http";
    if (encryptType == HttpDnsEncryptTypeDES) {
        domainEncrypStr = [self encryptUseDES:domain key:dnsKey];
    } else if (encryptType == HttpDnsEncryptTypeAES) {
        domainEncrypStr = [self encryptUseAES:domain key:dnsKey];
    } else if (encryptType == HttpDnsEncryptTypeHTTPS) {
        domainEncrypStr = [domain copy];
        protocol = @"https";
    }

    NSString *serviceIp = [[MSDKDnsManager shareInstance] currentDnsServer];
    NSString *routeIp = [[MSDKDnsParamsManager shareInstance] msdkDnsGetRouteIp];
    
    BOOL isHTTPDNSDomain = NO;
    
#ifdef httpdnsIps_h
#if IS_INTL
    if ([MSDKDnsServerDomain_INTL isEqualToString:domain]){
        isHTTPDNSDomain = YES;
    }
#else
    if ([MSDKDnsServerDomain isEqualToString:domain]){
        isHTTPDNSDomain = YES;
    }
#endif
#endif
    
    if (domainEncrypStr && domainEncrypStr.length > 0) {
        NSString * httpServer = [self getIPv6:[serviceIp UTF8String]];
        if (!httpServer || httpServer.length == 0) {
            httpServer = serviceIp;
        }
        NSString * urlStr = [NSString stringWithFormat:@"%@://%@/d?dn=%@&clientip=1&ttl=1&query=1&id=%d", protocol, httpServer, domainEncrypStr, dnsId];
        if (ipType == HttpDnsTypeIPv6) {
            urlStr = [urlStr stringByAppendingString:@"&type=aaaa"];
        }else if (ipType == HttpDnsTypeDual) {
            urlStr = [urlStr stringByAppendingString:@"&type=addrs"];
        }
        if (encryptType == HttpDnsEncryptTypeAES) {
            urlStr = [urlStr stringByAppendingFormat:@"&alg=aes"];
        } else if (encryptType == HttpDnsEncryptTypeHTTPS) {
            urlStr = [urlStr stringByAppendingFormat:@"&token=%@", token];
        } else if (encryptType == HttpDnsEncryptTypeDES){
            urlStr = [urlStr stringByAppendingFormat:@"&alg=des"];
        }
        // 当解析域名为三网域名的时候，默认为是SDK默认解析行为，不加入routeIp参数
        if (routeIp && routeIp.length > 0 && !isHTTPDNSDomain) {
            urlStr = [urlStr stringByAppendingFormat:@"&ip=%@", routeIp];
        }
        NSURL * url = [NSURL URLWithString:urlStr];
        MSDKDNSLOG(@"httpdns service url: %@",url);
        return url;
    } else {
        MSDKDNSLOG(@"HttpDns domain Crypt Error!");
    }
    return nil;
}

+ (NSString *) wifiSSID {
    // 移动网络下返回-1
    NSString *wifiName = @"-1";
    NSArray *ifs = (__bridge_transfer id)CNCopySupportedInterfaces();
    
    for (NSString *ifnam in ifs) {
        NSDictionary *info = (__bridge_transfer id)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
        if (info[@"SSID"]) {
            wifiName = info[@"SSID"];
        }
    }
    return wifiName;
}

/**
 生成sessionId,sessionId为12位，采用base62编码
 @return 返回sessionId
 */
+ (NSString *)generateSessionID {
    static NSString *sessionId = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
        NSUInteger length = alphabet.length;
        if (![self isValidString:sessionId]) {
            NSMutableString *mSessionId = [NSMutableString string];
            for (int i = 0; i < 12; i++) {
                [mSessionId appendFormat:@"%@", [alphabet substringWithRange:NSMakeRange(arc4random() % length, 1)]];
            }
            sessionId = [mSessionId copy];
        }
    });
    return sessionId;
}

+ (BOOL)isValidString:(id)notValidString {
    if (!notValidString) {
        return NO;
    }
    BOOL isKindOf = NO;
    @try {
        isKindOf = [notValidString isKindOfClass:[NSString class]];
    } @catch (NSException *exception) {}
    if (!isKindOf) {
        return NO;
    }
    
    NSInteger stringLength = 0;
    @try {
        stringLength = [notValidString length];
    } @catch (NSException *exception) {
        MSDKDNSLOG(@"类名与方法名：%@（在第%@行）, 描述：%@", @(__PRETTY_FUNCTION__), @(__LINE__), exception);
    }
    if (stringLength == 0) {
        return NO;
    }
    return YES;
}

+ (NSArray *)arrayTransLowercase:(NSArray *)data {
    NSMutableArray *lowerCaseArray = [NSMutableArray array];
    for(int i = 0; i < [data count]; i++) {
        NSString *d = [data objectAtIndex:i];
        if (d && d.length > 0) {
            [lowerCaseArray addObject:[d lowercaseString]];
        }
    }
    return lowerCaseArray;
}

+ (NSString *)getIPsStringFromIPsArray:(NSArray *)ipsArray {
    NSMutableString *ipsStr = [NSMutableString stringWithString:@""];
    if (ipsArray && [ipsArray isKindOfClass:[NSArray class]] && ipsArray.count > 0) {
        for (int i = 0; i < ipsArray.count; i++) {
            NSString *ip = ipsArray[i];
            if (i != ipsArray.count - 1) {
                [ipsStr appendFormat:@"%@,",ip];
            } else {
                [ipsStr appendString:ip];
            }
        }
    }
    return ipsStr;
}

@end
