/*
 File:        KMInterfaceInventory.m
 Program:     KisMac3
 Slice:       S3.4 - Local interface inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMInterfaceInventory.h"
#import "KMNetworkInterface.h"

#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/socket.h>

#import <SystemConfiguration/SystemConfiguration.h>
#import <CoreWLAN/CoreWLAN.h>

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

@implementation KMInterfaceInventory

#pragma mark - Helpers

/// Format an AF_INET / AF_INET6 sockaddr into a presentation string. Returns
/// nil on failure. For IPv6, strips the "%scope" suffix for cleaner display
/// (link-local fe80::/10 carries a scope id).
+ (nullable NSString *)stringForSockaddr:(const struct sockaddr *)sa {
    if (sa == NULL) return nil;
    char buf[INET6_ADDRSTRLEN] = {0};
    if (sa->sa_family == AF_INET) {
        const struct sockaddr_in *s4 = (const struct sockaddr_in *)sa;
        if (inet_ntop(AF_INET, &s4->sin_addr, buf, sizeof(buf)) == NULL) return nil;
        return [NSString stringWithUTF8String:buf];
    } else if (sa->sa_family == AF_INET6) {
        const struct sockaddr_in6 *s6 = (const struct sockaddr_in6 *)sa;
        if (inet_ntop(AF_INET6, &s6->sin6_addr, buf, sizeof(buf)) == NULL) return nil;
        NSString *str = [NSString stringWithUTF8String:buf];
        NSRange pct = [str rangeOfString:@"%"];
        if (pct.location != NSNotFound) str = [str substringToIndex:pct.location];
        return str;
    }
    return nil;
}

/// Format an AF_LINK sockaddr_dl into a MAC string "aa:bb:cc:dd:ee:ff", or nil
/// when there is no 6-byte link-layer address (utun*, lo0 have none).
+ (nullable NSString *)macForLinkSockaddr:(const struct sockaddr_dl *)sdl {
    if (sdl == NULL || sdl->sdl_alen != 6) return nil;
    const unsigned char *ptr = (const unsigned char *)LLADDR(sdl);
    return [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
            ptr[0], ptr[1], ptr[2], ptr[3], ptr[4], ptr[5]];
}

/// Classify an interface from its BSD name + flags. wiFiName (CoreWLAN) hardens
/// the en* Wi-Fi-vs-Ethernet decision when available.
+ (KMInterfaceType)classifyName:(NSString *)name
                          flags:(unsigned int)flags
                       wiFiName:(nullable NSString *)wiFiName {
    if (flags & IFF_LOOPBACK) return KMInterfaceTypeLoopback;
    if ([name hasPrefix:@"lo"]) return KMInterfaceTypeLoopback;

    // VPN / tunnel families.
    if ([name hasPrefix:@"utun"] || [name hasPrefix:@"ipsec"] ||
        [name hasPrefix:@"ppp"]  || [name hasPrefix:@"tun"]   ||
        [name hasPrefix:@"tap"]  || [name hasPrefix:@"gif"]   ||
        [name hasPrefix:@"stf"]) {
        return KMInterfaceTypeVPN;
    }

    // AWDL / peer-to-peer (Apple Wireless Direct Link, low-latency WLAN).
    if ([name hasPrefix:@"awdl"] || [name hasPrefix:@"llw"]) {
        return KMInterfaceTypeAWDLPeer;
    }

    // Bridges (incl. Thunderbolt bridge, which presents as bridge*).
    if ([name hasPrefix:@"bridge"]) return KMInterfaceTypeThunderboltBridge;

    if ([name hasPrefix:@"en"]) {
        // CoreWLAN-confirmed Wi-Fi interface wins.
        if (wiFiName.length && [name isEqualToString:wiFiName]) {
            return KMInterfaceTypeWiFi;
        }
        // Heuristic: en0/en1 are typically the built-in Wi-Fi/Ethernet on a
        // MacBook; higher-numbered en* are usually Thunderbolt/USB-Ethernet
        // bridges. Without a CoreWLAN match, treat en0 as Wi-Fi (the MacBook
        // default) and en1+ as Ethernet, except en[2-9]+ which lean
        // Thunderbolt-bridge on modern hardware.
        if ([name isEqualToString:@"en0"]) {
            return wiFiName.length ? KMInterfaceTypeEthernet : KMInterfaceTypeWiFi;
        }
        NSString *suffix = [name substringFromIndex:2];
        NSInteger idx = [suffix integerValue];
        if (idx >= 2) return KMInterfaceTypeThunderboltBridge;
        return KMInterfaceTypeEthernet;
    }

    return KMInterfaceTypeOther;
}

#pragma mark - SystemConfiguration / CoreWLAN cross-checks

+ (nullable NSString *)primaryInterfaceName {
    SCDynamicStoreRef store =
        SCDynamicStoreCreate(NULL, CFSTR("KisMac3.InterfaceInventory"), NULL, NULL);
    if (store == NULL) return nil;

    NSString *result = nil;
    CFTypeRef value = SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4"));
    if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) {
        NSDictionary *global = (__bridge NSDictionary *)value;
        id pri = global[@"PrimaryInterface"];
        if ([pri isKindOfClass:[NSString class]]) result = [pri copy];
    }
    if (value) CFRelease(value);
    CFRelease(store);
    return result;
}

+ (nullable NSString *)wiFiInterfaceName {
    @try {
        if (![CWWiFiClient respondsToSelector:@selector(sharedWiFiClient)]) return nil;
        CWWiFiClient *client = [CWWiFiClient sharedWiFiClient];
        // Default interface's BSD name (the cheapest reliable Wi-Fi name).
        CWInterface *iface = [client interface];
        if (iface.interfaceName.length) return iface.interfaceName;
        // Fallback: the first of the reported interface names.
        if ([client respondsToSelector:@selector(interfaceNames)]) {
            id names = [client interfaceNames];
            NSString *first = nil;
            if ([names isKindOfClass:[NSSet class]]) first = [(NSSet *)names anyObject];
            else if ([names isKindOfClass:[NSArray class]]) first = [(NSArray *)names firstObject];
            if (first.length) return first;
        }
    } @catch (__unused NSException *e) {
        // CoreWLAN unavailable -> just fall back to name heuristics.
    }
    return nil;
}

#pragma mark - Enumeration

+ (NSArray<KMNetworkInterface *> *)currentInterfaces {
    struct ifaddrs *ifaddr = NULL;
    if (getifaddrs(&ifaddr) != 0 || ifaddr == NULL) {
        DBNSLog(@"[KMInterfaceInventory] getifaddrs failed (errno=%d)", errno);
        return @[];
    }

    NSString *wiFiName = [self wiFiInterfaceName];
    NSString *primaryName = [self primaryInterfaceName];

    // Coalesce per BSD name (getifaddrs emits one node per address family).
    NSMutableDictionary<NSString *, KMNetworkInterface *> *byName = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array]; // preserve first-seen order

    for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_name == NULL) continue;
        NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
        if (name.length == 0) continue;

        KMNetworkInterface *iface = byName[name];
        if (iface == nil) {
            iface = [[KMNetworkInterface alloc] init];
            iface.bsdName = name;
            unsigned int flags = ifa->ifa_flags;
            iface.flags = flags;
            iface.isUp = (flags & IFF_UP) != 0;
            iface.isRunning = (flags & IFF_RUNNING) != 0;
            iface.supportsBroadcast = (flags & IFF_BROADCAST) != 0;
            iface.isPointToPoint = (flags & IFF_POINTOPOINT) != 0;
            iface.isLoopback = (flags & IFF_LOOPBACK) != 0;
            iface.type = [self classifyName:name flags:flags wiFiName:wiFiName];
            iface.isPrimary = (primaryName.length && [name isEqualToString:primaryName]);
            byName[name] = iface;
            [order addObject:name];
        }

        const struct sockaddr *sa = ifa->ifa_addr;
        if (sa == NULL) continue;

        if (sa->sa_family == AF_LINK) {
            NSString *mac = [self macForLinkSockaddr:(const struct sockaddr_dl *)sa];
            if (mac) iface.macAddress = mac;
        } else if (sa->sa_family == AF_INET) {
            NSString *ip = [self stringForSockaddr:sa];
            if (ip) {
                iface.ipv4Addresses = [iface.ipv4Addresses arrayByAddingObject:ip];
                NSString *mask = [self stringForSockaddr:ifa->ifa_netmask] ?: @"";
                iface.ipv4Netmasks = [iface.ipv4Netmasks arrayByAddingObject:mask];
            }
        } else if (sa->sa_family == AF_INET6) {
            NSString *ip = [self stringForSockaddr:sa];
            if (ip) iface.ipv6Addresses = [iface.ipv6Addresses arrayByAddingObject:ip];
        }
    }

    freeifaddrs(ifaddr);

    // Order: primary first, then up-with-IP, then the rest (stable within band).
    NSMutableArray<KMNetworkInterface *> *all = [NSMutableArray array];
    for (NSString *n in order) [all addObject:byName[n]];
    [all sortUsingComparator:^NSComparisonResult(KMNetworkInterface *a, KMNetworkInterface *b) {
        NSInteger ra = a.isPrimary ? 0 : ((a.isUp && a.hasIPAddress) ? 1 : 2);
        NSInteger rb = b.isPrimary ? 0 : ((b.isUp && b.hasIPAddress) ? 1 : 2);
        if (ra != rb) return (ra < rb) ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame; // stable sort preserves first-seen order within band
    }];

    return all;
}

@end
