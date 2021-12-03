//
//  MSDKDnsUUIDManager.m
//  MSDKDns
//
//  Created by vast on 2021/12/3.
//  Copyright © 2021 Tencent. All rights reserved.
//

#import "MSDKDnsUUIDManager.h"
#import "MSDKDnsKeychainManager.h"

static NSString * const KEY_IN_KEYCHAIN = @"com.tencent.httpdns.uuid";

@implementation MSDKDnsUUIDManager

+(void)saveUUID:(NSString *)uuid
{
    if (uuid && uuid.length > 0) {
        [MSDKDnsKeychainManager save:KEY_IN_KEYCHAIN data:uuid];
    }
}

+(NSString *)getUUID
{
    NSString *uuid = [MSDKDnsKeychainManager load:KEY_IN_KEYCHAIN];
    
    if (!uuid || uuid.length == 0) {
        uuid = [[NSUUID UUID] UUIDString];
        [self saveUUID:uuid];
    }
    return uuid;
}

+(void)deleteUUID
{
    [MSDKDnsKeychainManager delete:KEY_IN_KEYCHAIN];
}

@end
