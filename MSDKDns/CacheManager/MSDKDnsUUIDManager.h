//
//  MSDKDnsUUIDManager.h
//  MSDKDns
//
//  Created by vast on 2021/12/3.
//  Copyright © 2021 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MSDKDnsUUIDManager : NSObject

+(void)saveUUID:(NSString *)uuid;

+(NSString *)getUUID;

+(void)deleteUUID;

@end

NS_ASSUME_NONNULL_END
