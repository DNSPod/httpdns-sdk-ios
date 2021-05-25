# HTTPDNS SDK iOS
## 原理介绍

HttpDNS服务的详细介绍可以参见文章[全局精确流量调度新思路-HttpDNS服务详解](https://cloud.tencent.com/developer/article/1035562)。 总的来说，HttpDNS作为移动互联网时代DNS优化的一个通用解决方案，主要解决了以下几类问题：
- LocalDNS劫持/故障
- LocalDNS调度不准确

HttpDNS 的 SDK，主要提供了基于HttpDNS服务的域名解析和缓存管理能力：
- SDK在进行域名解析时，优先通过HttpDNS服务得到域名解析结果，极端情况下如果HttpDNS服务不可用，则使用LocalDNS解析结果
- HttpDNS服务返回的域名解析结果会携带相关的TTL信息，SDK会使用该信息进行HttpDNS解析结果的缓存管理
## 接入指南
**请参阅文档[HTTPDNS iOS客户端接入文档](https://cloud.tencent.com/document/product/379/17669)**
