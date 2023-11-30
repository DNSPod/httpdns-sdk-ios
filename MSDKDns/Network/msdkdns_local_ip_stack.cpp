// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.


#include "msdkdns_local_ip_stack.h"
#include <strings.h>
#include <errno.h>
#include <endian.h>
#include <unistd.h>
#include "../MSDKDnsLog.h"

/*
 * Connect a UDP socket to a given unicast address. This will cause no network
 * traffic, but will fail fast if the system has no or limited reachability to
 * the destination (e.g., no IPv4 address, no IPv6 default route, ...).
 */
static const unsigned int kMaxLoopCount = 10;

static int msdkdns_test_connect(int pf, struct sockaddr * addr, size_t addrlen) {
    int s = socket(pf, SOCK_DGRAM, IPPROTO_UDP);
    if (s < 0) {
        return 0;
    }
    int ret;
    unsigned int loop_count = 0;
    do {
        ret = connect(s, addr, addrlen);
    } while (ret < 0 && errno == EINTR && loop_count++ < kMaxLoopCount);
    if (loop_count >= kMaxLoopCount) {
        MSDKDNSLOG(@"connect error. loop_count = %d", loop_count);
    }
    int success = (ret == 0);
    loop_count = 0;
    do {
        ret = close(s);
    } while (ret < 0 && errno == EINTR && loop_count++ < kMaxLoopCount);
    if (loop_count >= kMaxLoopCount) {
        MSDKDNSLOG(@"close error. loop_count = %d", loop_count);
    }
    return success;
}

/*
 * The following functions determine whether IPv4 or IPv6 connectivity is
 * available in order to implement AI_ADDRCONFIG.
 *
 * Strictly speaking, AI_ADDRCONFIG should not look at whether connectivity is
 * available, but whether addresses of the specified family are "configured
 * on the local system". However, bionic doesn't currently support getifaddrs,
 * so checking for connectivity is the next best thing.
 */
static int msdkdns_have_ipv6() {
    static struct sockaddr_in6 sin6_test = {0};
    sin6_test.sin6_family = AF_INET6;
    sin6_test.sin6_port = 80;
    sin6_test.sin6_flowinfo = 0;
    sin6_test.sin6_scope_id = 0;
    bzero(sin6_test.sin6_addr.s6_addr, sizeof(sin6_test.sin6_addr.s6_addr));
    sin6_test.sin6_addr.s6_addr[0] = 0x20;
    // union
    msdkdns::msdkdns_sockaddr_union addr = {.msdkdns_in6 = sin6_test};
    return msdkdns_test_connect(PF_INET6, &addr.msdkdns_generic, sizeof(addr.msdkdns_in6));
}

static int msdkdns_have_ipv4() {
    static struct sockaddr_in sin_test = {0};
    sin_test.sin_family = AF_INET;
    sin_test.sin_port = 80;
    sin_test.sin_addr.s_addr = htonl(0x08080808L);  // 8.8.8.8
    // union
    msdkdns::msdkdns_sockaddr_union addr = {.msdkdns_in = sin_test};
    return msdkdns_test_connect(PF_INET, &addr.msdkdns_generic, sizeof(addr.msdkdns_in));
}

msdkdns::MSDKDNS_TLocalIPStack msdkdns::msdkdns_detect_local_ip_stack() {
    MSDKDNSLOG(@"detect local ip stack");
    int have_ipv4 = msdkdns_have_ipv4();
    int have_ipv6 = msdkdns_have_ipv6();
    int local_stack = 0;
    if (have_ipv4) {
        local_stack |= msdkdns::MSDKDNS_ELocalIPStack_IPv4;
    }
    if (have_ipv6) {
        local_stack |= msdkdns::MSDKDNS_ELocalIPStack_IPv6;
    }
    MSDKDNSLOG(@"have_ipv4:%d have_ipv6:%d", have_ipv4, have_ipv6);
    return (msdkdns::MSDKDNS_TLocalIPStack) local_stack;
}
