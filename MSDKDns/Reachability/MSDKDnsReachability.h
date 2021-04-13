/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Basic demonstration of how to use the SystemConfiguration Reachablity APIs.
 */

#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

//#define USE_DDG_EXTENSIONS 1 // Use DDG's Extensions to test network criteria.
// Since NSAssert and NSCAssert are used in this code, 
// I recommend you set NS_BLOCK_ASSERTIONS=1 in the release versions of your projects.

typedef enum : NSInteger {
	
	// DDG NetworkStatus Constant Names.
	MSDKDnsNotReachable = 0, // Apple's code depends upon 'NotReachable' being the same value as 'NO'.
	MSDKDnsReachableViaWiFi, // Switched order from Apple's enum. WWAN is active before WiFi.
	MSDKDnsReachableViaWWAN
	
}MSDKDnsNetworkStatus;

#pragma mark IPv6 Support
//Reachability fully support IPv6.  For full details, see ReadMe.md.

extern NSString *const kMSDKDnsInternetConnection;
extern NSString *const kMSDKDnsLocalWiFiConnection;
extern NSString *const kMSDKDnsReachabilityChangedNotification;

@interface MSDKDnsReachability: NSObject

/*!
 * Use to check the reachability of a given host name.
 */
+ (instancetype)reachabilityWithHostName:(NSString *)hostName;

/*!
 * Use to check the reachability of a given IP address.
 */
+ (instancetype)reachabilityWithAddress:(const struct sockaddr *)hostAddress;

/*!
 * Checks whether the default route is available. Should be used by applications that do not connect to a particular host.
 */
+ (instancetype)reachabilityForInternetConnection;


#pragma mark reachabilityForLocalWiFi
//reachabilityForLocalWiFi has been removed from the sample.  See ReadMe.md for more information.
//+ (instancetype)reachabilityForLocalWiFi;

/*!
 * Start listening for reachability notifications on the current run loop.
 */
- (BOOL)startNotifier;
- (void)stopNotifier;

- (MSDKDnsNetworkStatus)currentReachabilityStatus;

/*!
 * WWAN may be available, but not active until a connection has been established. WiFi may require a connection for VPN on Demand.
 */
- (BOOL)connectionRequired;

@end
