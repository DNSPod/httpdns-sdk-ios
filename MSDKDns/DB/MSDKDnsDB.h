//  Created by eric hu on 2022/8/23.
//  Copyright © 2022 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MSDKDnsDB : NSObject

//@property (strong, nonatomic, readonly) WCTDatabase *database;

+ (instancetype)shareInstance;

- (void)insertOrReplaceDomainInfo:(NSDictionary *)domainInfo Domain:(NSString *)domain;

- (NSDictionary *)getDataFromDB;

- (void)deleteDBData: (NSArray *)domains;

- (void)deleteAllData;

@end

