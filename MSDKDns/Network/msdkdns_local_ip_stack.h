// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

#ifndef MSDKDNS_NETWORK_LOCAL_IP_STACK
#define MSDKDNS_NETWORK_LOCAL_IP_STACK

#include <netinet/in.h>
#include <sys/socket.h>

#ifdef __cplusplus
extern "C" {
#endif

namespace msdkdns {

    typedef union msdkdns_sockaddr_union {
        struct sockaddr msdkdns_generic;
        struct sockaddr_in msdkdns_in;
        struct sockaddr_in6 msdkdns_in6;
    } msdkdns_sockaddr_union;

    // 注意该ENUM数值改动时需要同步更改JAVA层相应的的Stack定义
    enum MSDKDNS_TLocalIPStack {
        MSDKDNS_ELocalIPStack_None = 0,
        MSDKDNS_ELocalIPStack_IPv4 = 1,
        MSDKDNS_ELocalIPStack_IPv6 = 2,
        MSDKDNS_ELocalIPStack_Dual = 3,
    };

    const char * const MSDKDNS_TLocalIPStackStr[] = {
            "MSDKDNS_ELocalIPStack_None",
            "MSDKDNS_ELocalIPStack_IPv4",
            "MSDKDNS_ELocalIPStack_IPv6",
            "MSDKDNS_ELocalIPStack_Dual",
    };

    MSDKDNS_TLocalIPStack msdkdns_detect_local_ip_stack();
} // namespace msdkdns

#ifdef __cplusplus
}
#endif


#endif // HTTPDNS_SDK_IOS_MSDKDNS_NETWORK_MSDKDNS_LOCAL_IP_STACK_H_
