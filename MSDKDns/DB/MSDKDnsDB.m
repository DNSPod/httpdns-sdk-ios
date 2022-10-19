//  Created by eric hu on 2022/8/23.
//  Copyright © 2022 Tencent. All rights reserved.
//

#import "MSDKDnsDB.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsPrivate.h"
#import <sqlite3.h>


@interface MSDKDnsDB ()

@property (nonatomic,assign) sqlite3 *db;
@property char *error;


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
        @try {
            NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES);
            NSString *baseDirectory = [documentPaths objectAtIndex:0];
            
            // 设置数据库文件路径
            NSString *fileName = [baseDirectory stringByAppendingPathComponent:@"httpdns.sqlite"];
            NSLog(@"fileName === %@", fileName);
            //打开数据库文件（如果数据库文件不存在，那么该函数会自动创建数据库文件）
            int result = sqlite3_open([fileName UTF8String], &_db);
            if (result == SQLITE_OK) {//打开成功
                NSLog(@"成功打开数据库");
                //                NSString *createSql = @"create table if not exists myTable(id integer primary key autoincrement, name text UNIQUE, age integer, address text)";
                NSString *createSql = @"create table if not exists HttpDNSTable(id integer primary key autoincrement, domain text UNIQUE, httpDnsIPV4Channel text, httpDnsIPV4ClientIP text, httpDnsIPV4IPs text, httpDnsIPV4TimeConsuming text, httpDnsIPV4TTL text, httpDnsIPV4TTLExpried text, httpDnsIPV6Channel text, httpDnsIPV6ClientIP text, httpDnsIPV6IPs text, httpDnsIPV6TimeConsuming text, httpDnsIPV6TTL text, httpDnsIPV6TTLExpried text)";
                
                if (sqlite3_exec(_db, [createSql UTF8String], NULL, NULL, &_error) == SQLITE_OK) {
                    NSLog(@"create table is ok.");
                } else {
                    NSLog(@"error: %s", _error);
                    
                    // 每次使用完毕清空 error 字符串，提供给下一次使用
                    sqlite3_free(_error);
                }
            }else{
                NSLog(@"打开数据库失败");
            }
        } @catch (NSException *exception) {
            MSDKDNSLOG(@"database connection failed");
        }
    }
    return self;
}

- (void)insertOrReplaceDomainInfo:(NSDictionary *)domainInfo Domain:(NSString *)domain {
    
    NSDictionary * hresultDict_A = domainInfo[kMSDKHttpDnsCache_A];
    NSDictionary * hresultDict_4A = domainInfo[kMSDKHttpDnsCache_4A];
    
    NSString *hresultDict_A_kChannel = @"";
    NSString *hresultDict_A_kClientIP = @"";
    NSString *hresultDict_A_kIP = @"";
    NSString *hresultDict_A_kDnsTimeConsuming = @"";
    NSString *hresultDict_A_kTTL = @"";
    NSString *hresultDict_A_kTTLExpired = @"";
    NSString *hresultDict_4A_kChannel = @"";
    NSString *hresultDict_4A_kClientIP = @"";
    NSString *hresultDict_4A_kIP = @"";
    NSString *hresultDict_4A_kDnsTimeConsuming = @"";
    NSString *hresultDict_4A_kTTL = @"";
    NSString *hresultDict_4A_kTTLExpired = @"";
    
    if(hresultDict_A){
        if(hresultDict_A[kChannel]){
            hresultDict_A_kChannel = hresultDict_A[kChannel];
        }
        if(hresultDict_A[kClientIP]){
            hresultDict_A_kClientIP = hresultDict_A[kClientIP];
        }
        if(hresultDict_A[kIP]){
            hresultDict_A_kIP = [hresultDict_A[kIP] componentsJoinedByString:@","];
        }
        if(hresultDict_A[kDnsTimeConsuming]){
            hresultDict_A_kDnsTimeConsuming = hresultDict_A[kDnsTimeConsuming];
        }
        if(hresultDict_A[kTTL]){
            hresultDict_A_kTTL = hresultDict_A[kTTL];
        }
        if(hresultDict_A[kTTLExpired]){
            hresultDict_A_kTTLExpired = hresultDict_A[kTTLExpired];
        }
    }
    
    if(hresultDict_4A){
        if(hresultDict_4A[kChannel]){
            hresultDict_4A_kChannel = hresultDict_4A[kChannel];
        }
        if(hresultDict_4A[kClientIP]){
            hresultDict_4A_kClientIP = hresultDict_4A[kClientIP];
        }
        if(hresultDict_4A[kIP]){
            hresultDict_4A_kIP = [hresultDict_4A[kIP] componentsJoinedByString:@","];
        }
        if(hresultDict_4A[kDnsTimeConsuming]){
            hresultDict_4A_kDnsTimeConsuming = hresultDict_4A[kDnsTimeConsuming];
        }
        if(hresultDict_4A[kTTL]){
            hresultDict_4A_kTTL = hresultDict_4A[kTTL];
        }
        if(hresultDict_4A[kTTLExpired]){
            hresultDict_4A_kTTLExpired = hresultDict_4A[kTTLExpired];
        }
    }
    
    //    NSString *createSql = @"create table if not exists myTable(id integer primary key autoincrement, name text UNIQUE, age integer, address text)";
    NSString *insertSql = [NSString stringWithFormat:@"INSERT OR REPLACE into HttpDNSTable(domain, httpDnsIPV4Channel, httpDnsIPV4ClientIP, httpDnsIPV4IPs, httpDnsIPV4TimeConsuming, httpDnsIPV4TTL, httpDnsIPV4TTLExpried, httpDnsIPV6ClientIP, httpDnsIPV6IPs, httpDnsIPV6TimeConsuming, httpDnsIPV6TTL, httpDnsIPV6TTLExpried) values('%@','%@','%@','%@','%@','%@','%@','%@','%@','%@','%@','%@')",[domain copy],hresultDict_A_kChannel,hresultDict_A_kClientIP,hresultDict_A_kIP,hresultDict_A_kDnsTimeConsuming,hresultDict_A_kTTL,hresultDict_A_kTTLExpired,hresultDict_4A_kClientIP,hresultDict_4A_kIP,hresultDict_4A_kDnsTimeConsuming,hresultDict_4A_kTTL,hresultDict_4A_kTTLExpired];
    
    if (sqlite3_exec(_db, [insertSql UTF8String], NULL, NULL, &_error) == SQLITE_OK) {
        NSLog(@"insert operation is ok.");
    } else {
        NSLog(@"error: %s", _error);
        
        // 每次使用完毕清空 error 字符串，提供给下一次使用
        sqlite3_free(_error);
    }
}

- (NSDictionary *)getDataFromDB {
    NSMutableDictionary *newResult = [[NSMutableDictionary alloc] init];
    
    sqlite3_stmt *statement;
    
    // @"select * from myTable"  查询所有 key 值内容
    //    NSString *selectSql = @"select id, name, age, address from myTable";
    NSString *selectSql = @"select domain, httpDnsIPV4Channel, httpDnsIPV4ClientIP, httpDnsIPV4IPs, httpDnsIPV4TimeConsuming, httpDnsIPV4TTL, httpDnsIPV4TTLExpried, httpDnsIPV6Channel, httpDnsIPV6ClientIP, httpDnsIPV6IPs, httpDnsIPV6TimeConsuming, httpDnsIPV6TTL, httpDnsIPV6TTLExpried from HttpDNSTable";
    
    if (sqlite3_prepare_v2(_db, [selectSql UTF8String], -1, &statement, nil) == SQLITE_OK) {
        
        while(sqlite3_step(statement) == SQLITE_ROW) {
            NSMutableDictionary *domainInfo = [[NSMutableDictionary alloc] init];
            NSMutableDictionary *httpDnsIPV4Info = [[NSMutableDictionary alloc] init];
            NSMutableDictionary *httpDnsIPV6Info = [[NSMutableDictionary alloc] init];
            
            NSString *domain = [NSString stringWithUTF8String:(char *)sqlite3_column_text(statement, 0)];
            
            char *httpDnsIPV4Channel_char = (char *)sqlite3_column_text(statement, 1);
            NSString *httpDnsIPV4Channel = httpDnsIPV4Channel_char ? [NSString stringWithUTF8String:httpDnsIPV4Channel_char] : nil;
            
            char *httpDnsIPV4ClientIP_char = (char *)sqlite3_column_text(statement, 2);
            NSString *httpDnsIPV4ClientIP = httpDnsIPV4ClientIP_char ? [NSString stringWithUTF8String:httpDnsIPV4ClientIP_char] : nil;
            
            char *httpDnsIPV4IPs_char = (char *)sqlite3_column_text(statement, 3);
            NSString *httpDnsIPV4IPs = httpDnsIPV4IPs_char ? [NSString stringWithUTF8String:httpDnsIPV4IPs_char] : nil;
            
            char *httpDnsIPV4TimeConsuming_char = (char *)sqlite3_column_text(statement, 4);
            NSString *httpDnsIPV4TimeConsuming = httpDnsIPV4TimeConsuming_char ? [NSString stringWithUTF8String:httpDnsIPV4TimeConsuming_char] : nil;
            
            char *httpDnsIPV4TTL_char = (char *)sqlite3_column_text(statement, 5);
            NSString *httpDnsIPV4TTL = httpDnsIPV4TTL_char ? [NSString stringWithUTF8String:httpDnsIPV4TTL_char] : nil;
            
            char *httpDnsIPV4TTLExpried_char = (char *)sqlite3_column_text(statement, 6);
            NSString *httpDnsIPV4TTLExpried = httpDnsIPV4TTLExpried_char ? [NSString stringWithUTF8String:httpDnsIPV4TTLExpried_char] : nil;
            
            char *httpDnsIPV6Channel_char = (char *)sqlite3_column_text(statement, 7);
            NSString *httpDnsIPV6Channel = httpDnsIPV6Channel_char ? [NSString stringWithUTF8String:httpDnsIPV6Channel_char] : nil;
            
            char *httpDnsIPV6ClientIP_char = (char *)sqlite3_column_text(statement, 8);
            NSString *httpDnsIPV6ClientIP = httpDnsIPV6ClientIP_char ? [NSString stringWithUTF8String:httpDnsIPV6ClientIP_char] : nil;
            
            char *httpDnsIPV6IPs_char = (char *)sqlite3_column_text(statement, 9);
            NSString *httpDnsIPV6IPs = httpDnsIPV6IPs_char ? [NSString stringWithUTF8String:httpDnsIPV6IPs_char] : nil;
            
            char *httpDnsIPV6TimeConsuming_char = (char *)sqlite3_column_text(statement, 10);
            NSString *httpDnsIPV6TimeConsuming = httpDnsIPV6TimeConsuming_char ? [NSString stringWithUTF8String:httpDnsIPV6TimeConsuming_char] : nil;
            
            char *httpDnsIPV6TTL_char = (char *)sqlite3_column_text(statement, 11);
            NSString *httpDnsIPV6TTL = httpDnsIPV6TTL_char ? [NSString stringWithUTF8String:httpDnsIPV6TTL_char] : nil;
            
            char *httpDnsIPV6TTLExpried_char = (char *)sqlite3_column_text(statement, 12);
            NSString *httpDnsIPV6TTLExpried = httpDnsIPV6TTLExpried_char ? [NSString stringWithUTF8String:httpDnsIPV6TTLExpried_char] : nil;
            
            @try {
                if([self isExist:httpDnsIPV4Channel]){
                    [httpDnsIPV4Info setObject:httpDnsIPV4Channel forKey:kChannel];
                }
                if([self isExist:httpDnsIPV4ClientIP]){
                    [httpDnsIPV4Info setObject:httpDnsIPV4ClientIP forKey:kClientIP];
                }
                if([self isExist:httpDnsIPV4IPs]){
                    [httpDnsIPV4Info setObject:[httpDnsIPV4IPs componentsSeparatedByString:@","] forKey:kIP];
                }
                if([self isExist:httpDnsIPV4TimeConsuming]){
                    [httpDnsIPV4Info setObject:httpDnsIPV4TimeConsuming forKey:kDnsTimeConsuming];
                }
                if([self isExist:httpDnsIPV4TTL]){
                    [httpDnsIPV4Info setObject:httpDnsIPV4TTL forKey:kTTL];
                }
                if([self isExist:httpDnsIPV4TTLExpried]){
                    [httpDnsIPV4Info setObject:httpDnsIPV4TTLExpried forKey:kTTLExpired];
                }
                
                if([self isExist:httpDnsIPV6Channel]){
                    [httpDnsIPV6Info setObject:httpDnsIPV6Channel forKey:kChannel];
                }
                if([self isExist:httpDnsIPV6ClientIP]){
                    [httpDnsIPV6Info setObject:httpDnsIPV6ClientIP forKey:kClientIP];
                }
                if([self isExist:httpDnsIPV6IPs]){
                    [httpDnsIPV6Info setObject:[httpDnsIPV6IPs componentsSeparatedByString:@","] forKey:kIP];
                }
                if([self isExist:httpDnsIPV6TimeConsuming]){
                    [httpDnsIPV6Info setObject:httpDnsIPV6TimeConsuming forKey:kDnsTimeConsuming];
                }
                if([self isExist:httpDnsIPV6TTL]){
                    [httpDnsIPV6Info setObject:httpDnsIPV6TTL forKey:kTTL];
                }
                if([self isExist:httpDnsIPV6TTLExpried]){
                    [httpDnsIPV6Info setObject:httpDnsIPV6TTLExpried forKey:kTTLExpired];
                }
                
            } @catch (NSException *exception) {}
            [domainInfo setObject:httpDnsIPV4Info forKey:kMSDKHttpDnsCache_A];
            [domainInfo setObject:httpDnsIPV6Info forKey:kMSDKHttpDnsCache_4A];
            
            [newResult setObject:domainInfo forKey:domain];
        }
        NSLog(@"========newResult========%@", newResult);
    } else {
        NSLog(@"select operation is fail.");
    }
    
    sqlite3_finalize(statement);
    return newResult;
}

- (BOOL)isExist: (NSString *)value {
    if(value && ![value isEqual:@""]){
        return YES;
    }
    return NO;
}

- (void)deleteDBData: (NSArray *)domains {
    @try {
        NSString *sql = [NSString stringWithFormat:@"DELETE FROM HttpDNSTable WHERE domain IN ('%@')", [domains componentsJoinedByString:@"','"]];
        if (sqlite3_exec(_db, [sql UTF8String], NULL, NULL, &_error) == SQLITE_OK) {
            NSLog(@"delete operation is ok.");
        } else {
            NSLog(@"Failed to delete data into database. error:%s", _error);
            // 每次使用完毕清空 error 字符串，提供给下一次使用
            sqlite3_free(_error);
        }
    } @catch (NSException *exception) {
        MSDKDNSLOG(@"Failed to delete data into database");
    }
}

- (BOOL)close {
    
    if (!_db) {
        return YES;
    }
    
    int  rc;
    BOOL retry;
    BOOL triedFinalizingOpenStatements = NO;
    
    do {
        retry   = NO;
        rc      = sqlite3_close(_db);
        if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
            if (!triedFinalizingOpenStatements) {
                triedFinalizingOpenStatements = YES;
                sqlite3_stmt *pStmt;
                while ((pStmt = sqlite3_next_stmt(_db, nil)) !=0) {
                    NSLog(@"Closing leaked statement");
                    sqlite3_finalize(pStmt);
                    retry = YES;
                }
            }
        }
        else if (SQLITE_OK != rc) {
            NSLog(@"error closing!: %d", rc);
        }
    }
    while (retry);
    
    _db = nil;
    return YES;
}

- (void)dealloc {
    [self close];
}


@end
