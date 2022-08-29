//  Created by eric hu on 2022/8/23.
//  Copyright © 2022 Tencent. All rights reserved.
//

#import "MSDKDnsDB.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsPrivate.h"

#if __cplusplus >= 201103L
    #import <WCDB/WCDB.h>
    #import "HTTPDNSORM.h"
    #import "HTTPDNSORM+WCTTableCoding.h"
#endif

@interface MSDKDnsDB ()

@property (strong, nonatomic, readwrite) id database;
@property (strong, nonatomic, readwrite) NSString *tableName;

@end

@implementation MSDKDnsDB

#pragma mark - init

static MSDKDnsDB * _sharedInstance = nil;
+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[MSDKDnsDB alloc] init];
    });
    return _sharedInstance;
}

- (instancetype) init {
    if (self = [super init]) {
        _tableName = @"HttpDNSTable";
        // 获取WCTDatabase类
        Class databaseClass = NSClassFromString(@"WCTDatabase");
        // 获取HTTPDNSORM类
        Class HTTPDNSORMClass = NSClassFromString(@"HTTPDNSORM");
        if (databaseClass == 0x0) {
            MSDKDNSLOG(@"WCTDatabase framework is not imported");
        } else if (HTTPDNSORMClass == 0x0) {
            MSDKDNSLOG(@"MSDKDns does not support persistent cache, we recommend using MSDKDns_C11");
        } else {
            @try {
                NSTimeInterval time1 = [[NSDate date] timeIntervalSince1970];
                _database = [[databaseClass alloc] initWithPath:@"/Users/erichu/Library/HttpDNSTable"];
                // 获取方法编号
                SEL createTableAndIndexesOfNameSEL = NSSelectorFromString(@"createTableAndIndexesOfName:withClass:");
                // 调用WCTDatabase类的方法
                if (_database && [_database respondsToSelector:createTableAndIndexesOfNameSEL] ) {
                    IMP imp = [_database methodForSelector:createTableAndIndexesOfNameSEL];
                    using connectDatabase = BOOL (*)(id, SEL, NSString *, Class);
                    BOOL success = ((connectDatabase) imp)(_database, createTableAndIndexesOfNameSEL, _tableName, HTTPDNSORMClass.class);
                    if (!success) {
                        MSDKDNSLOG(@"database connection failed");
                    }
                }
                NSTimeInterval time2 = [[NSDate date] timeIntervalSince1970];
                NSLog(@"===创建数据库==本次耗时=====：%fms", (time2 - time1) * 1000);
            } @catch (NSException *exception) {
                MSDKDNSLOG(@"database connection failed");
            }
        }
    }
    return self;
}

- (void)insertOrReplaceDomainInfo:(NSDictionary *)domainInfo Domain:(NSString *)domain {
    
    NSDictionary * hresultDict_A = domainInfo[kMSDKHttpDnsCache_A];
    NSDictionary * hresultDict_4A = domainInfo[kMSDKHttpDnsCache_4A];
    
    // 获取HTTPDNSORM类
    Class HTTPDNSORMClass = NSClassFromString(@"HTTPDNSORM");
    
    if (HTTPDNSORMClass == 0x0) {
        MSDKDNSLOG(@"MSDKDns does not support persistent cache, we recommend using MSDKDns_C11");
        return;
    }
    
    id httpDnsData = [[HTTPDNSORMClass alloc] init];
        
    [httpDnsData setValue:[domain copy] forKey:@"domain"];
    
    if (hresultDict_A){
        [httpDnsData setValue:hresultDict_A[kChannel] forKey:@"httpDnsIPV4Channel"];
        [httpDnsData setValue:hresultDict_A[kClientIP] forKey:@"httpDnsIPV4ClientIP"];
        [httpDnsData setValue:hresultDict_A[kIP] forKey:@"httpDnsIPV4IPs"];
        [httpDnsData setValue:hresultDict_A[kDnsTimeConsuming] forKey:@"httpDnsIPV4TimeConsuming"];
        [httpDnsData setValue:hresultDict_A[kTTL] forKey:@"httpDnsIPV4TTL"];
        [httpDnsData setValue:hresultDict_A[kTTLExpired] forKey:@"httpDnsIPV4TTLExpried"];
    }
    
    if (hresultDict_4A) {
        [httpDnsData setValue:hresultDict_4A[kChannel] forKey:@"httpDnsIPV6Channel"];
        [httpDnsData setValue:hresultDict_4A[kClientIP] forKey:@"httpDnsIPV6ClientIP"];
        [httpDnsData setValue:hresultDict_4A[kIP] forKey:@"httpDnsIPV6IPs"];
        [httpDnsData setValue:hresultDict_4A[kDnsTimeConsuming] forKey:@"httpDnsIPV6TimeConsuming"];
        [httpDnsData setValue:hresultDict_4A[kTTL] forKey:@"httpDnsIPV6TTL"];
        [httpDnsData setValue:hresultDict_4A[kTTLExpired] forKey:@"httpDnsIPV6TTLExpried"];
    }
    // 获取方法编号
    SEL insertOrReplaceObjectSEL = NSSelectorFromString(@"insertOrReplaceObject:into:");
    
    if (_database && [_database respondsToSelector:insertOrReplaceObjectSEL] ) {
        NSTimeInterval time1 = [[NSDate date] timeIntervalSince1970];
                    
        @try {
            IMP imp = [_database methodForSelector:insertOrReplaceObjectSEL];
            using insertData = BOOL (*)(id, SEL, id, NSString *);
            BOOL success = ((insertData) imp)(_database, insertOrReplaceObjectSEL, httpDnsData, _tableName);
            if (!success) {
                MSDKDNSLOG(@"Failed to insert data into database");
            }
        } @catch (NSException *exception) {
            MSDKDNSLOG(@"Failed to insert data into database");
        }

        NSTimeInterval time2 = [[NSDate date] timeIntervalSince1970];
        NSLog(@"===插入数据库==本次耗时=====：%fms", (time2 - time1) * 1000);
  
        NSDictionary *result = [self getDataFromDB];
        NSLog(@"loadDB domainInfo = %@",result);
    }
}

- (NSDictionary *)getDataFromDB {
    // 获取HTTPDNSORM类
    Class HTTPDNSORMClass = NSClassFromString(@"HTTPDNSORM");
    SEL getAllObjectsOfClassSEL = NSSelectorFromString(@"getAllObjectsOfClass:fromTable:");
    
    NSMutableDictionary *newResult = [[NSMutableDictionary alloc] init];
    
    if (HTTPDNSORMClass == 0x0) {
        MSDKDNSLOG(@"MSDKDns does not support persistent cache, we recommend using MSDKDns_C11");
    }
    
    if (_database && [_database respondsToSelector:getAllObjectsOfClassSEL] && HTTPDNSORMClass != 0x0) {
        NSTimeInterval time1 = [[NSDate date] timeIntervalSince1970];
        @try {
            IMP imp = [_database methodForSelector:getAllObjectsOfClassSEL];
            using GetAllData = NSArray* (*)(id, SEL, Class, NSString *);
            NSArray *result = ((GetAllData) imp)(_database, getAllObjectsOfClassSEL, HTTPDNSORMClass.class, _tableName);
            if (!result) {
                MSDKDNSLOG(@"Failed to insert data into database");
            }
            for (id item in result) {
                NSMutableDictionary *domainInfo = [[NSMutableDictionary alloc] init];
                NSMutableDictionary *httpDnsIPV4Info = [[NSMutableDictionary alloc] init];
                NSMutableDictionary *httpDnsIPV6Info = [[NSMutableDictionary alloc] init];
     
                [httpDnsIPV4Info setObject:[item valueForKey:@"httpDnsIPV4Channel"] forKey:kChannel];
                [httpDnsIPV4Info setObject:[item valueForKey:@"httpDnsIPV4ClientIP"] forKey:kClientIP];
                [httpDnsIPV4Info setObject:[item valueForKey:@"httpDnsIPV4IPs"] forKey:kIP];
                [httpDnsIPV4Info setObject:[item valueForKey:@"httpDnsIPV4TimeConsuming"] forKey:kDnsTimeConsuming];
                [httpDnsIPV4Info setObject:[item valueForKey:@"httpDnsIPV4TTL"] forKey:kTTL];
                [httpDnsIPV4Info setObject:[item valueForKey:@"httpDnsIPV4TTLExpried"] forKey:kTTLExpired];

                [httpDnsIPV6Info setObject:[item valueForKey:@"httpDnsIPV6Channel"] forKey:kChannel];
                [httpDnsIPV6Info setObject:[item valueForKey:@"httpDnsIPV6ClientIP"] forKey:kClientIP];
                [httpDnsIPV6Info setObject:[item valueForKey:@"httpDnsIPV6IPs"] forKey:kIP];
                [httpDnsIPV6Info setObject:[item valueForKey:@"httpDnsIPV6TimeConsuming"] forKey:kDnsTimeConsuming];
                [httpDnsIPV6Info setObject:[item valueForKey:@"httpDnsIPV6TTL"] forKey:kTTL];
                [httpDnsIPV6Info setObject:[item valueForKey:@"httpDnsIPV6TTLExpried"] forKey:kTTLExpired];
                
                [domainInfo setObject:httpDnsIPV4Info forKey:kMSDKHttpDnsCache_A];
                [domainInfo setObject:httpDnsIPV6Info forKey:kMSDKHttpDnsCache_4A];
                
                [newResult setObject:domainInfo forKey:[item valueForKey:@"domain"]];
            }
        } @catch (NSException *exception) {
            MSDKDNSLOG(@"Failed to insert data into database");
        }
        
        NSTimeInterval time2 = [[NSDate date] timeIntervalSince1970];
        NSLog(@"===读取数据库==本次耗时=====：%fms", (time2 - time1) * 1000);
    }
    return newResult;
}


@end
