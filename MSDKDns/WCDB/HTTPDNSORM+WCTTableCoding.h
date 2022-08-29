/**
 * Copyright (c) Tencent. All rights reserved.
 */

#if __cplusplus >= 201103L
    #import <WCDB/WCDB.h>
    #import "HTTPDNSORM.h"
    @interface HTTPDNSORM (WCTTableCoding) <WCTTableCoding>

    WCDB_PROPERTY(domain)

    WCDB_PROPERTY(httpDnsIPV4Channel)
    WCDB_PROPERTY(httpDnsIPV4ClientIP)
    WCDB_PROPERTY(httpDnsIPV4IPs)
    WCDB_PROPERTY(httpDnsIPV4TimeConsuming)
    WCDB_PROPERTY(httpDnsIPV4TTL)
    WCDB_PROPERTY(httpDnsIPV4TTLExpried)

    WCDB_PROPERTY(httpDnsIPV6Channel)
    WCDB_PROPERTY(httpDnsIPV6ClientIP)
    WCDB_PROPERTY(httpDnsIPV6IPs)
    WCDB_PROPERTY(httpDnsIPV6TimeConsuming)
    WCDB_PROPERTY(httpDnsIPV6TTL)
    WCDB_PROPERTY(httpDnsIPV6TTLExpried)

    @end

#endif

