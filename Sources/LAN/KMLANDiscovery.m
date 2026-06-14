/*
 File:        KMLANDiscovery.m
 Program:     KisMac3
 Slice:       S3.3 - LAN discovery (Bonjour/mDNS/DNS-SD)

 This file is part of KisMAC. GPL v2.
 */

#import "KMLANDiscovery.h"
#import "KMLANService.h"
#import "../Safety/KMRedactionSettings.h"

#import <Network/Network.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>

#ifndef DBNSLog
#define DBNSLog NSLog
#endif

NSString * const KMLANDiscoveryDidUpdateServicesNotification =
    @"KMLANDiscoveryDidUpdateServicesNotification";

NSString *KMStringFromLANNetworkState(KMLANNetworkState state) {
    switch (state) {
        case KMLANNetworkStateActive:  return @"active";
        case KMLANNetworkStateDenied:  return @"denied";
        case KMLANNetworkStateUnknown:
        default:                       return @"unknown";
    }
}

@interface KMLANDiscovery ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, KMLANService *> *servicesByKey;
/// Order of first-seen identity keys (so we can return most-recent-first).
@property (nonatomic, strong) NSMutableArray<NSString *> *order;
@property (nonatomic, strong) NSMutableArray *browsers;   // nw_browser_t (held via __bridge in array as id)
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) KMLANNetworkState localNetworkState;
@property (nonatomic, assign, getter=isBrowsing) BOOL browsing;
@end

@implementation KMLANDiscovery

- (instancetype)init {
    if ((self = [super init])) {
        _servicesByKey = [NSMutableDictionary dictionary];
        _order = [NSMutableArray array];
        _browsers = [NSMutableArray array];
        _queue = dispatch_queue_create("ca.kismac.landiscovery", DISPATCH_QUEUE_SERIAL);
        _localNetworkState = KMLANNetworkStateUnknown;
        _browsing = NO;
    }
    return self;
}

- (void)dealloc {
    [self stopBrowsing];
}

#pragma mark - Curated service types

+ (NSArray<NSString *> *)defaultServiceTypes {
    // A practical, security-audit-relevant curated set. Listing these also lets
    // us declare them in NSBonjourServices (Info.plist) for the Local Network
    // permission. (We deliberately do NOT meta-browse _services._dns-sd._udp
    // here to keep the surface bounded and the Info.plist declaration honest.)
    return @[
        @"_http._tcp",          // web UIs (routers, NAS, printers, cameras)
        @"_https._tcp",
        @"_ssh._tcp",           // remote shells
        @"_sftp-ssh._tcp",
        @"_smb._tcp",           // file sharing
        @"_afpovertcp._tcp",
        @"_nfs._tcp",
        @"_ipp._tcp",           // printers
        @"_ipps._tcp",
        @"_printer._tcp",
        @"_pdl-datastream._tcp",
        @"_airplay._tcp",       // AirPlay receivers
        @"_raop._tcp",          // AirPlay audio
        @"_companion-link._tcp",// Apple device companion / Handoff
        @"_rfb._tcp",           // VNC / screen sharing
        @"_device-info._tcp",   // device metadata
        @"_homekit._tcp",       // HomeKit accessories
        @"_hap._tcp",           // HomeKit Accessory Protocol
        @"_googlecast._tcp",    // Chromecast
        @"_workstation._tcp",   // hosts advertising themselves
    ];
}

#pragma mark - Lifecycle

- (void)startBrowsing {
    [self startBrowsingServiceTypes:[[self class] defaultServiceTypes]];
}

- (void)startBrowsingServiceTypes:(NSArray<NSString *> *)serviceTypes {
    if (self.browsing) return;
    self.browsing = YES;
    self.localNetworkState = KMLANNetworkStateUnknown;

    for (NSString *type in serviceTypes) {
        [self startBrowserForType:type];
    }

    if (self.browsers.count == 0) {
        // Nothing started -> fail closed to denied so callers don't hang on
        // "unknown" forever.
        self.browsing = NO;
        self.localNetworkState = KMLANNetworkStateDenied;
    }
}

- (void)startBrowserForType:(NSString *)type {
    nw_browse_descriptor_t desc =
        nw_browse_descriptor_create_bonjour_service([type UTF8String], "local.");
    if (!desc) return;

    nw_parameters_t params =
        nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                        NW_PARAMETERS_DEFAULT_CONFIGURATION);

    nw_browser_t browser = nw_browser_create(desc, params);
    if (!browser) return;

    nw_browser_set_queue(browser, self.queue);

    __weak typeof(self) weakSelf = self;

    nw_browser_set_state_changed_handler(browser,
        ^(nw_browser_state_t state, nw_error_t error) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (state == nw_browser_state_ready) {
                strongSelf.localNetworkState = KMLANNetworkStateActive;
            } else if (state == nw_browser_state_failed) {
                // A failed browser most commonly means Local Network is denied
                // (or no network). Mark denied only if we never went active.
                if (strongSelf.localNetworkState != KMLANNetworkStateActive) {
                    strongSelf.localNetworkState = KMLANNetworkStateDenied;
                }
            }
        });

    nw_browser_set_browse_results_changed_handler(browser,
        ^(nw_browse_result_t old_result, nw_browse_result_t new_result, bool batch) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            nw_browse_result_change_t change =
                nw_browse_result_get_changes(old_result, new_result);
            if (change & nw_browse_result_change_result_added) {
                strongSelf.localNetworkState = KMLANNetworkStateActive;
                [strongSelf handleAddedResult:new_result type:type];
            } else if (change & nw_browse_result_change_result_removed) {
                [strongSelf handleRemovedResult:old_result type:type];
            }
        });

    nw_browser_start(browser);
    // Network.framework objects are ARC-managed ObjC objects; hold a strong
    // reference directly so ARC keeps the browser alive while it runs.
    [self.browsers addObject:browser];
}

- (void)stopBrowsing {
    for (id obj in self.browsers) {
        nw_browser_t browser = (nw_browser_t)obj;
        nw_browser_cancel(browser);
    }
    [self.browsers removeAllObjects];
    self.browsing = NO;
}

#pragma mark - Result handling (runs on self.queue)

- (NSString *)instanceNameForEndpoint:(nw_endpoint_t)endpoint {
    if (!endpoint) return nil;
    if (nw_endpoint_get_type(endpoint) != nw_endpoint_type_bonjour_service) return nil;
    const char *name = nw_endpoint_get_bonjour_service_name(endpoint);
    return name ? [NSString stringWithUTF8String:name] : nil;
}

// NOTE: all browse/connection handlers run on self.queue (a serial queue), so
// the servicesByKey/order store is mutated only there -- no main-thread hop is
// needed to keep it consistent, and -discoveredServices reads it via a
// dispatch_sync on the same queue. This deliberately avoids depending on the
// main runloop draining (a modal alert elsewhere could otherwise stall result
// collection). Notifications are still posted to the main thread for UI.
- (void)handleAddedResult:(nw_browse_result_t)result type:(NSString *)type {
    nw_endpoint_t endpoint = nw_browse_result_copy_endpoint(result);
    NSString *instanceName = [self instanceNameForEndpoint:endpoint];
    if (instanceName.length == 0) return;

    KMLANService *svc = [[KMLANService alloc] init];
    svc.name = instanceName;
    svc.type = type;
    svc.domain = @"local.";

    NSString *key = svc.identityKey;
    // On self.queue already.
    if (!self.servicesByKey[key]) {
        [self.order addObject:key];
        self.servicesByKey[key] = svc;
    }
    [self postUpdate];

    // Resolve passively (the OS already has the mDNS records; this does not
    // initiate an application-level connection to the host - we cancel before
    // any data is sent).
    [self resolveEndpoint:endpoint forKey:key];
}

- (void)handleRemovedResult:(nw_browse_result_t)result type:(NSString *)type {
    nw_endpoint_t endpoint = nw_browse_result_copy_endpoint(result);
    NSString *instanceName = [self instanceNameForEndpoint:endpoint];
    if (instanceName.length == 0) return;
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", type, instanceName, @"local."];
    // On self.queue already.
    if (self.servicesByKey[key]) {
        [self.servicesByKey removeObjectForKey:key];
        [self.order removeObject:key];
        [self postUpdate];
    }
}

/// Resolve a bonjour endpoint to host/port/addresses using a short-lived
/// nw_connection. We read the resolved path's remote endpoint(s) and then
/// cancel immediately - no application data is ever sent (passive resolution).
- (void)resolveEndpoint:(nw_endpoint_t)endpoint forKey:(NSString *)key {
    if (!endpoint) return;

    nw_parameters_t params =
        nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                        NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_connection_t conn = nw_connection_create(endpoint, params);
    if (!conn) return;

    nw_connection_set_queue(conn, self.queue);
    __weak typeof(self) weakSelf = self;

    nw_connection_set_state_changed_handler(conn,
        ^(nw_connection_state_t state, nw_error_t error) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (state == nw_connection_state_ready) {
                nw_path_t path = nw_connection_copy_current_path(conn);
                if (path) {
                    nw_endpoint_t remote = nw_path_copy_effective_remote_endpoint(path);
                    [strongSelf recordResolvedEndpoint:remote forKey:key];
                }
                // Passive: tear down before sending anything.
                nw_connection_cancel(conn);
            } else if (state == nw_connection_state_failed ||
                       state == nw_connection_state_cancelled) {
                // Leave whatever we recorded; nothing more to do.
            }
        });

    nw_connection_start(conn);
}

- (void)recordResolvedEndpoint:(nw_endpoint_t)remote forKey:(NSString *)key {
    if (!remote) return;
    if (nw_endpoint_get_type(remote) != nw_endpoint_type_address) return;

    NSString *host = nil;
    NSUInteger port = 0;
    const char *hostname = nw_endpoint_get_hostname(remote);
    if (hostname) host = [NSString stringWithUTF8String:hostname];
    port = nw_endpoint_get_port(remote);

    NSString *ip = [self addressStringFromEndpoint:remote];

    // Hop onto self.queue (the connection ready handler also runs there, but be
    // explicit) to mutate the store consistently.
    dispatch_async(self.queue, ^{
        KMLANService *svc = self.servicesByKey[key];
        if (!svc) return;
        if (host.length) svc.hostName = host;
        if (port) svc.port = port;
        if (ip.length) {
            NSMutableArray *ips = [svc.ipAddresses mutableCopy] ?: [NSMutableArray array];
            if (![ips containsObject:ip]) {
                [ips addObject:ip];
                svc.ipAddresses = [ips copy];
            }
        }
        [self postUpdate];
    });
}

- (NSString *)addressStringFromEndpoint:(nw_endpoint_t)endpoint {
    const struct sockaddr *sa = nw_endpoint_get_address(endpoint);
    if (!sa) return nil;
    char buf[INET6_ADDRSTRLEN] = {0};
    if (sa->sa_family == AF_INET) {
        const struct sockaddr_in *s4 = (const struct sockaddr_in *)sa;
        if (inet_ntop(AF_INET, &s4->sin_addr, buf, sizeof(buf)))
            return [NSString stringWithUTF8String:buf];
    } else if (sa->sa_family == AF_INET6) {
        const struct sockaddr_in6 *s6 = (const struct sockaddr_in6 *)sa;
        if (inet_ntop(AF_INET6, &s6->sin6_addr, buf, sizeof(buf)))
            return [NSString stringWithUTF8String:buf];
    }
    return nil;
}

#pragma mark - Snapshot / notification

/// Called on self.queue. Snapshots the store there and dispatches the delegate
/// callback + notification to the main thread for UI consumers.
- (void)postUpdate {
    NSArray<KMLANService *> *snapshot = [self snapshotLocked];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if ([strongSelf.delegate respondsToSelector:@selector(lanDiscovery:didUpdateServices:)]) {
            [strongSelf.delegate lanDiscovery:strongSelf didUpdateServices:snapshot];
        }
        [[NSNotificationCenter defaultCenter]
            postNotificationName:KMLANDiscoveryDidUpdateServicesNotification object:strongSelf];
    });
}

/// Snapshot helper -- MUST be called on self.queue.
- (NSArray<KMLANService *> *)snapshotLocked {
    NSMutableArray<KMLANService *> *out = [NSMutableArray array];
    // most-recently-seen first
    for (NSString *key in [self.order reverseObjectEnumerator]) {
        KMLANService *svc = self.servicesByKey[key];
        if (svc) [out addObject:svc];
    }
    return [out copy];
}

- (NSArray<KMLANService *> *)discoveredServices {
    __block NSArray<KMLANService *> *snapshot = nil;
    dispatch_sync(self.queue, ^{
        snapshot = [self snapshotLocked];
    });
    return snapshot;
}

- (void)resetDiscoveredServices {
    dispatch_async(self.queue, ^{
        [self.servicesByKey removeAllObjects];
        [self.order removeAllObjects];
        [self postUpdate];
    });
}

#pragma mark - Future hook honesty

- (BOOL)pingSweepIsImplemented {
    // PASSIVE ONLY in S3.3: no active ping sweep / port scan is implemented.
    // A future slice MAY add an opt-in, default-OFF, rate-limited sweep gated
    // behind an authorized campaign scope. Until then this is honestly NO.
    return NO;
}

@end
