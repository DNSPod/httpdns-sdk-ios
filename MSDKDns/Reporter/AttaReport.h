//
//  AttaReport.h
//  MSDKDns
//
//  Created by vast on 2021/12/7.
//  Copyright © 2021 Tencent. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AttaReport : NSObject

+ (instancetype) sharedInstance;

- (void)reportEvent:(NSDictionary *)params;

@end

NS_ASSUME_NONNULL_END
