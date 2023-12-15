//  Created by eric hu on 2022/8/23.
//  Copyright © 2022 Tencent. All rights reserved.
//

#import "MSDKDnsDB.h"
#import "MSDKDnsLog.h"
#import "MSDKDnsInfoTool.h"
#import "MSDKDnsPrivate.h"
#import <sqlite3.h>


@interface MSDKDnsDB ()

@property (nonatomic,assign) sqlite3 *db;
@property char *error;


@end

@implementation MSDKDnsDB

#pragma mark - init

static MSDKDnsDB * gSharedInstance = nil;

+ (instancetype)shareInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSharedInstance = [[MSDKDnsDB alloc] init];
    });
    return gSharedInstance;
}

- (instancetype) init {
    if (self = [super init]) {
        @try {
            NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES);
            NSString *baseDirectory = [documentPaths objectAtIndex:0];
            
            // 设置数据库文件路径
            NSString *fileName = [baseDirectory stringByAppendingPathComponent:@"httpdns.sqlite"];
            //打开数据库文件（如果数据库文件不存在，那么该函数会自动创建数据库文件）
            int result = sqlite3_open([fileName UTF8String], &_db);
            if (result == SQLITE_OK) {//打开成功
                NSString *createSql = @"create table if not exists HttpDNSTable(id integer primary key autoincrement, domain text UNIQUE, httpDnsIPV4Channel text, httpDnsIPV4ClientIP text, httpDnsIPV4IPs text, httpDnsIPV4TimeConsuming text, httpDnsIPV4TTL text, httpDnsIPV4TTLExpried text, httpDnsIPV6Channel text, httpDnsIPV6ClientIP text, httpDnsIPV6IPs text, httpDnsIPV6TimeConsuming text, httpDnsIPV6TTL text, httpDnsIPV6TTLExpried text)";
                
                if (sqlite3_exec(_db, [createSql UTF8String], NULL, NULL, &_error) == SQLITE_OK) {
                    MSDKDNSLOG(@"Successfully create table into database.");
                } else {
                    MSDKDNSLOG(@"Failed to create table into database, error: %s", _error);
                    
                    // 每次使用完毕清空 error 字符串，提供给下一次使用
                    sqlite3_free(_error);
                }
            }else{
                MSDKDNSLOG(@"Failed to open Database");
            }
        } @catch (NSException *exception) {
            MSDKDNSLOG(@"Failed to connect Database");
        }
    }
    return self;
}

- (void)insertOrReplaceDomainInfo:(NSDictionary *)domainInfo domain:(NSString *)domain {
    
    @try {
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
        NSString *sql = @"INSERT OR REPLACE into HttpDNSTable ";
        NSString *param = @"(domain, httpDnsIPV4Channel, httpDnsIPV4ClientIP, httpDnsIPV4IPs, httpDnsIPV4TimeConsuming, httpDnsIPV4TTL, httpDnsIPV4TTLExpried, httpDnsIPV6ClientIP, httpDnsIPV6IPs, httpDnsIPV6TimeConsuming, httpDnsIPV6TTL, httpDnsIPV6TTLExpried)";
        NSString *data = [NSString stringWithFormat:@" values('%@','%@','%@','%@','%@','%@','%@','%@','%@','%@','%@','%@')",
                          [domain copy],hresultDict_A_kChannel,hresultDict_A_kClientIP,hresultDict_A_kIP,
                          hresultDict_A_kDnsTimeConsuming,hresultDict_A_kTTL,hresultDict_A_kTTLExpired,hresultDict_4A_kClientIP,
                          hresultDict_4A_kIP,hresultDict_4A_kDnsTimeConsuming,hresultDict_4A_kTTL,hresultDict_4A_kTTLExpired];
        NSString *insertSql = [NSString stringWithFormat:@"%@%@%@",sql, param, data];
        
        if (sqlite3_exec(_db, [insertSql UTF8String], NULL, NULL, &_error) == SQLITE_OK) {
            MSDKDNSLOG(@"Successfully insert data into database, domain = %@, domainInfo = %@", domain, domainInfo);
        } else {
            MSDKDNSLOG(@"Failed to insert data into database, error: %s", _error);
            
            // 每次使用完毕清空 error 字符串，提供给下一次使用
            sqlite3_free(_error);
        }
    } @catch (NSException *exception) {
        MSDKDNSLOG(@"Failed to insert data into database, error: %@", exception);
    }
}

- (NSDictionary *)getDataFromDB {
    NSMutableDictionary *newResult = [[NSMutableDictionary alloc] init];
    sqlite3_stmt *statement;
    NSString *selectSql = @"select domain, httpDnsIPV4Channel, httpDnsIPV4ClientIP, httpDnsIPV4IPs, httpDnsIPV4TimeConsuming, httpDnsIPV4TTL, httpDnsIPV4TTLExpried, httpDnsIPV6Channel, httpDnsIPV6ClientIP, httpDnsIPV6IPs, httpDnsIPV6TimeConsuming, httpDnsIPV6TTL, httpDnsIPV6TTLExpried from HttpDNSTable";
    
    @try {
        if (sqlite3_prepare_v2(_db, [selectSql UTF8String], -1, &statement, nil) == SQLITE_OK) {
            while (sqlite3_step(statement) == SQLITE_ROW) {
                NSMutableDictionary *domainInfo = [[NSMutableDictionary alloc] init];
                NSMutableDictionary *httpDnsIPV4Info = [[NSMutableDictionary alloc] init];
                NSMutableDictionary *httpDnsIPV6Info = [[NSMutableDictionary alloc] init];
                
                NSString *domain = [NSString stringWithUTF8String:(char *)sqlite3_column_text(statement, 0)];
                
                NSArray *httpDnsIPV4InfoArray = [self getHttpDnsIPV4InfoArrayWithStatement:statement];
                NSArray *httpDnsIPV6InfoArray = [self getHttpDnsIPV6InfoArrayWithStatement:statement];
                
                [self fillHttpDnsIPV4Info:httpDnsIPV4Info withArray:httpDnsIPV4InfoArray];
                [self fillHttpDnsIPV6Info:httpDnsIPV6Info withArray:httpDnsIPV6InfoArray];
                
                [domainInfo setObject:httpDnsIPV4Info forKey:kMSDKHttpDnsCache_A];
                [domainInfo setObject:httpDnsIPV6Info forKey:kMSDKHttpDnsCache_4A];
                
                [newResult setObject:domainInfo forKey:domain];
            }
            MSDKDNSLOG(@"Successfully select data from database, result = %@", newResult);
        } else {
            MSDKDNSLOG(@"Failed to select data from database, error: %s", _error);
        }
    } @catch (NSException *exception) {
        MSDKDNSLOG(@"Failed to select data from database, error: %@", exception);
    }
    
    sqlite3_finalize(statement);
    return newResult;
}

- (NSArray *)getHttpDnsIPV4InfoArrayWithStatement:(sqlite3_stmt *)statement {
    NSMutableArray *httpDnsIPV4InfoArray = [[NSMutableArray alloc] init];
    for (int i = 1; i <= 6; i++) {
        char *infoChar = (char *)sqlite3_column_text(statement, i);
        NSString *info = infoChar ? [NSString stringWithUTF8String:infoChar] : @"";
        [httpDnsIPV4InfoArray addObject:info];
    }
    return httpDnsIPV4InfoArray;
}

- (NSArray *)getHttpDnsIPV6InfoArrayWithStatement:(sqlite3_stmt *)statement {
    NSMutableArray *httpDnsIPV6InfoArray = [[NSMutableArray alloc] init];
    for (int i = 7; i <= 12; i++) {
        char *infoChar = (char *)sqlite3_column_text(statement, i);
        NSString *info = infoChar ? [NSString stringWithUTF8String:infoChar] : @"";
        [httpDnsIPV6InfoArray addObject:info];
    }
    return httpDnsIPV6InfoArray;
}

- (void)fillHttpDnsIPV4Info:(NSMutableDictionary *)httpDnsIPV4Info withArray:(NSArray *)httpDnsIPV4InfoArray {
    NSArray *keys = @[kChannel, kClientIP, kIP, kDnsTimeConsuming, kTTL, kTTLExpired];
    for (int i = 0; i < keys.count; i++) {
        if ([MSDKDnsInfoTool isExist:httpDnsIPV4InfoArray[i]]) {
            if ([keys[i] isEqualToString:kIP]) {
                [httpDnsIPV4Info setObject:[httpDnsIPV4InfoArray[i] componentsSeparatedByString:@","] forKey:keys[i]];
            } else {
                [httpDnsIPV4Info setObject:httpDnsIPV4InfoArray[i] forKey:keys[i]];
            }
        }
    }
}

- (void)fillHttpDnsIPV6Info:(NSMutableDictionary *)httpDnsIPV6Info withArray:(NSArray *)httpDnsIPV6InfoArray {
    NSArray *keys = @[kChannel, kClientIP, kIP, kDnsTimeConsuming, kTTL, kTTLExpired];
    for (int i = 0; i < keys.count; i++) {
        if ([MSDKDnsInfoTool isExist:httpDnsIPV6InfoArray[i]]) {
            if ([keys[i] isEqualToString:kIP]) {
                [httpDnsIPV6Info setObject:[httpDnsIPV6InfoArray[i] componentsSeparatedByString:@","] forKey:keys[i]];
            } else {
                [httpDnsIPV6Info setObject:httpDnsIPV6InfoArray[i] forKey:keys[i]];
            }
        }
    }
}

- (void)deleteDBData: (NSArray *)domains {
    @try {
        NSString *sql = [NSString stringWithFormat:@"DELETE FROM HttpDNSTable WHERE domain IN ('%@')", [domains componentsJoinedByString:@"','"]];
        if (sqlite3_exec(_db, [sql UTF8String], NULL, NULL, &_error) == SQLITE_OK) {
            MSDKDNSLOG(@"Successfully delete data into database. domains = %@", domains);
        } else {
            MSDKDNSLOG(@"Failed to delete data into database. error:%s", _error);
            // 每次使用完毕清空 error 字符串，提供给下一次使用
            sqlite3_free(_error);
        }
    } @catch (NSException *exception) {
        MSDKDNSLOG(@"Failed to delete data into database");
    }
}

- (void)deleteAllData {
    @try {
        NSString *sql = @"DELETE FROM HttpDNSTable";
        if (sqlite3_exec(_db, [sql UTF8String], NULL, NULL, &_error) == SQLITE_OK) {
            MSDKDNSLOG(@"Successfully delete all data into database.");
        } else {
            MSDKDNSLOG(@"Failed to delete all data into database. error:%s", _error);
            // 每次使用完毕清空 error 字符串，提供给下一次使用
            sqlite3_free(_error);
        }
    } @catch (NSException *exception) {
        MSDKDNSLOG(@"Failed to delete data into database");
    }
}

// 关闭数据库
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
                    MSDKDNSLOG(@"Closing leaked statement");
                    sqlite3_finalize(pStmt);
                    retry = YES;
                }
            }
        }
        else if (SQLITE_OK != rc) {
            MSDKDNSLOG(@"Failed to close Database: %d", rc);
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
