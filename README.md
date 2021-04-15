# HTTPDNS SDK iOS
## 原理介绍

HttpDNS服务的详细介绍可以参见文章[全局精确流量调度新思路-HttpDNS服务详解](https://cloud.tencent.com/developer/article/1035562)。 总的来说，HttpDNS作为移动互联网时代DNS优化的一个通用解决方案，主要解决了以下几类问题：
- LocalDNS劫持/故障
- LocalDNS调度不准确

HttpDNS的Android SDK，主要提供了基于HttpDNS服务的域名解析和缓存管理能力：
- SDK在进行域名解析时，优先通过HttpDNS服务得到域名解析结果，极端情况下如果HttpDNS服务不可用，则使用LocalDNS解析结果
- HttpDNS服务返回的域名解析结果会携带相关的TTL信息，SDK会使用该信息进行HttpDNS解析结果的缓存管理
## 接入指南
### SDK集成
#### 已接入灯塔（Beacon）的业务
仅需引入项目打包生成的的MSDKDns.framework（或MSDKDns_C11.framework，根据工程配置选其一）即可。
#### 未接入灯塔（Beacon）的业务
灯塔(beacon)SDK是腾讯灯塔团队开发的用于移动应用统计分析的SDK, HttpDNS SDK使用灯塔(beacon)SDK收集域名解析质量数据, 辅助定位问题
- 引入依赖库（[下载地址](https://github.com/tencentyun/httpdns-ios-sdk/tree/master/HTTPDNSLibs)）：
	- BeaconAPI_Base.framework
	- MSDKDns.framework（或MSDKDns_C11.framework，根据工程配置选其一）
- 引入系统库：
	- libz.tdb
	- libsqlite3.tdb
	- libc++.tdb
	- Foundation.framework
	- CoreTelephony.framework
	- SystemConfiguration.framework
	- CoreGraphics.framework
	- Security.framework
- 并在application:didFinishLaunchingWithOptions:加入注册灯塔代码：

        //已正常接入灯塔的业务无需关注以下代码，未接入灯塔的业务调用以下代码注册灯塔
        //******************************
        [BeaconBaseInterface setAppKey:@"0000066HQK3XNL5U"];
        [BeaconBaseInterface enableAnalytics:@"" gatewayIP:nil];
        //******************************

**注意：需要在Other linker flag里加入-ObjC标志。**

## API及使用示例

### 设置业务基本信息

#### 接口声明

    /**
     设置业务基本信息（腾讯云业务使用）

     @param appkey  业务appkey，腾讯云官网（https://console.cloud.tencent.com/httpdns）申请获得，用于上报
     @param dnsid   dns解析id，腾讯云官网（https://console.cloud.tencent.com/httpdns）申请获得，用于域名解析鉴权
     @param dnsKey  dns解析key，腾讯云官网（https://console.cloud.tencent.com/httpdns）申请获得，用于域名解析鉴权
     @param debug   是否开启Debug日志，YES：开启，NO：关闭。建议联调阶段开启，正式上线前关闭
     @param timeout 超时时间，单位ms，如设置0，则设置为默认值2000ms
     @param useHttp 是否使用http路解析，YES：使用http路解析，NO：使用https路解析，强烈建议使用http路解析，解析速度更快
     
     @return YES:设置成功 NO:设置失败
     */
    - (BOOL) WGSetDnsAppKey:(NSString *) appkey DnsID:(int)dnsid DnsKey:(NSString *)dnsKey Debug:(BOOL)debug TimeOut:(int)timeout UseHttp:(BOOL)useHttp;

#### 示例代码

接口调用示例：

     [[MSDKDns sharedInstance] WGSetDnsAppKey: @"业务appkey，由腾讯云官网申请获得" DnsID:dns解析id DnsKey:@"dns解析key" Debug:YES TimeOut:1000 UseHttp:YES];

### 域名解析接口

获取IP共有两个接口，同步接口**WGGetHostByName**，异步接口**WGGetHostByNameAsync**，引入头文件，调用相应接口即可。

返回的地址格式为NSArray，固定长度为2，其中第一个值为ipv4地址，第二个值为ipv6地址。以下为返回格式的详细说明：

- ipv4下，仅返回ipv4地址，即返回格式为：[ipv4, 0]
- ipv6下，仅返回ipv6地址，即返回格式为：[0, ipv6]
- 双栈网络下，返回解析到ipv4&ipv6（如果存在）地址，即返回格式为：[ipv4, ipv6]
- 解析失败，返回[0, 0]，业务重新调用WGGetHostByName接口即可。

**注意：使用ipv6地址进行URL请求时，需加方框号[ ]进行处理，例如：http://[64:ff9b::b6fe:7475]/*********

**使用建议：**

1. ipv6为0，直接使用ipv4地址连接
2. ipv6地址不为0，优先使用ipv6连接，如果ipv6连接失败，再使用ipv4地址进行连接

#### 同步解析接口: WGGetHostByName

##### 接口声明
    /**
     域名同步解析（通用接口）
     
     @param domain 域名
     
     @return 查询到的IP数组，超时（1s）或者未未查询到返回[0,0]数组
     */
     - (NSArray *) WGGetHostByName:(NSString *) domain;

##### 示例代码

接口调用示例：

    NSArray *ipsArray = [[MSDKDns sharedInstance] WGGetHostByName: @"www.qq.com"];
    if (ipsArray && ipsArray.count > 1) {
        NSString *ipv4 = ipsArray[0];
        NSString *ipv6 = ipsArray[1];
        if (![ipv6 isEqualToString:@"0"]) {
            //TODO 使用ipv6地址进行URL连接时，注意格式，ipv6需加方框号[]进行处理，例如：http://[64:ff9b::b6fe:7475]/
        } else if (![ipv4 isEqualToString:@"0"]){
            //使用ipv4地址进行连接
        } else {
            //异常情况返回为0,0，建议重试一次
        }
    }

#### 异步解析接口: WGGetHostByNameAsync

##### 接口声明

    /**
     域名异步解析（通用接口）
     
     @param domain  域名
     @param handler 返回查询到的IP数组，超时（1s）或者未未查询到返回[0,0]数组
     */
     - (void) WGGetHostByNameAsync:(NSString *) domain returnIps:(void (^)(NSArray *ipsArray))handler;

##### 示例代码

**接口调用示例1**：等待完整解析过程结束后，拿到结果，进行连接操作

    [[MSDKDns sharedInstance] WGGetHostByNameAsync:domain returnIps:^(NSArray *ipsArray) {
        //等待完整解析过程结束后，拿到结果，进行连接操作
        if (ipsArray && ipsArray.count > 1) {
            NSString *ipv4 = ipsArray[0];
            NSString *ipv6 = ipsArray[1];
            if (![ipv6 isEqualToString:@"0"]) {
                //TODO 使用ipv6地址进行URL连接时，注意格式，ipv6需加方框号[]进行处理，例如：http://[64:ff9b::b6fe:7475]/
            } else if (![ipv4 isEqualToString:@"0"]){
                //使用ipv4地址进行连接
            } else {
                //异常情况返回为0,0，建议重试一次
            }
        }
    }];

**接口调用示例2**：无需等待，可直接拿到缓存结果，如无缓存，则result为nil

    __block NSArray* result;
    [[MSDKDns sharedInstance] WGGetHostByNameAsync:domain returnIps:^(NSArray *ipsArray) {
        result = ipsArray;
    }];
    //无需等待，可直接拿到缓存结果，如无缓存，则result为nil
    if (result) {
        //拿到缓存结果，进行连接操作
    } else {
        //本次请求无缓存，业务可走原始逻辑
    }

**注意**：业务可根据自身需求，任选一种调用方式：

示例1，优点：可保证每次请求都能拿到返回结果进行接下来的连接操作；
缺点：异步接口的处理较同步接口稍显复杂。

示例2，优点：对于解析时间有严格要求的业务，使用本示例，可无需等待，直接拿到缓存结果进行后续的连接操作，完全避免了同步接口中解析耗时可能会超过100ms的情况；缺点：第一次请求时，result一定会nil，需业务增加处理逻辑。

#### 详细数据查询接口: WGGetDnsDetail

	/**
	详细数据查询接口

	@param domain 域名

	@return 查询到的详细信息
	 格式示例：
 	{
	 "v4_ips":"1.1.1.1,2.2.2.2",
	 "v6_ips":"FF01::1,FF01::2",
	 "v4_ttl":"100",
	 "v6_ttl":"100",
	 "v4_client_ip":"6.6.6.6"
	 "v6_client_ip":"FF01::6"
	 }
	*/
	- (NSDictionary *) WGGetDnsDetail:(NSString *) domain;

##### 示例代码

接口调用示例：

    NSDictionary *ipsDic = [[MSDKDns sharedInstance] WGGetDnsDetail: @"www.qq.com"];
    if (ipsDic && ipsDic.count > 0) {
        NSString *ipv4 = ipsDic[@"v4_ips"];
        NSString *ipv6 = ipsDic[@"v6_ips"];
        if (![ipv6 isEqualToString:@"0"]) {
            //TODO 使用ipv6地址进行URL连接时，注意格式，ipv6需加方框号[]进行处理，例如：http://[64:ff9b::b6fe:7475]/
        } else if (![ipv4 isEqualToString:@"0"]){
            //使用ipv4地址进行连接
        } else {
            //异常情况返回为0,0，建议重试一次
        }
    }

## 注意事项

1. 如果客户端的业务是与host绑定的，比如是绑定了host的http服务或者是cdn的服务，那么在用HTTPDNS返回的IP替换掉URL中的域名以后，还需要指定下Http头的host字段。

    - 以NSURLConnection为例：
    
            NSURL *httpDnsURL = [NSURL URLWithString:@"使用解析结果ip拼接的URL"];
            float timeOut = 设置的超时时间;
            NSMutableURLRequest *mutableReq = [NSMutableURLRequest requestWithURL:httpDnsURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval: timeOut];
            [mutableReq setValue:@"原域名" forHTTPHeaderField:@"host"];
            NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:mutableReq delegate:self];
            [connection start];
    
    - 以NSURLSession为例：
    
            NSURL *httpDnsURL = [NSURL URLWithString:@"使用解析结果ip拼接的URL"];
            float timeOut = 设置的超时时间;
            NSMutableURLRequest *mutableReq = [NSMutableURLRequest requestWithURL:httpDnsURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval: timeOut];
            [mutableReq setValue:@"原域名" forHTTPHeaderField:@"host"];
            NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
            NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:[NSOperationQueue currentQueue]];
            NSURLSessionTask *task = [session dataTaskWithRequest:mutableReq];
            [task resume];
            
	- 以curl为例：

        假设你要访问www.qq.com，通过HTTPDNS解析出来的IP为192.168.0.111，那么通过这个方式来调用即可：

            curl -H "host:www.qq.com" http://192.168.0.111/aaa.txt.

	- 以Unity的WWW接口为例：
    
            string httpDnsURL = "使用解析结果ip拼接的URL";
            Dictionary<string, string> headers = new Dictionary<string, string> ();
            headers["host"] = "原域名";
            WWW conn = new WWW (url, null, headers);
            yield return conn;
            if (conn.error != null) {
                print("error is happened:"+ conn.error);
            } else {
                print("request ok" + conn.text);
            }

2. 检测本地是否使用了HTTP代理，如果使用了HTTP代理，建议不要使用HTTPDNS做域名解析

	- 检测是否使用了HTTP代理：
    
            - (BOOL)isUseHTTPProxy {
                CFDictionaryRef dicRef = CFNetworkCopySystemProxySettings();
                const CFStringRef proxyCFstr = (const CFStringRef)CFDictionaryGetValue(dicRef, (const void*)kCFNetworkProxiesHTTPProxy);
                NSString *proxy = (__bridge NSString *)proxyCFstr;
                if (proxy) {
                    return YES;
                } else {
                    return NO;
                }
            }

	- 检测是否使用了HTTPS代理：
    
            - (BOOL)isUseHTTPSProxy {
                CFDictionaryRef dicRef = CFNetworkCopySystemProxySettings();
                const CFStringRef proxyCFstr = (const CFStringRef)CFDictionaryGetValue(dicRef, (const void*)kCFNetworkProxiesHTTPSProxy);
                NSString *proxy = (__bridge NSString *)proxyCFstr;
                if (proxy) {
                    return YES;
                } else {
                    return NO;
                }
            }
