/*
 File:        KMHardwareProbe.m
 Program:     KisMac3
 Slice:       S1.1 - MacBook hardware capability probe

 SAFETY: non-disruptive only. See header. Every disruptive capability is
         reported, never executed.

 This file is part of KisMAC. GPL v2.
 */

#import "KMHardwareProbe.h"

#import <CoreWLAN/CoreWLAN.h>
#import <CoreLocation/CoreLocation.h>
#import <sys/sysctl.h>
#import <pcap/pcap.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

// DBNSLog is provided by the prefix header (NSLog in Debug, no-op otherwise).
// Fall back to NSLog if this file is ever compiled without the prefix.
#ifndef DBNSLog
#define DBNSLog NSLog
#endif

@interface KMHardwareProbe ()
@property (nonatomic, copy, readwrite) NSString *hardwareModel;
@property (nonatomic, copy, readwrite) NSString *osVersion;
@property (nonatomic, copy, readwrite) NSString *architecture;
@property (nonatomic, copy, readwrite) NSString *appBuild;
@property (nonatomic, copy, readwrite) NSArray<KMHardwareCapability *> *capabilities;
@property (nonatomic, strong, nullable) NSDate *probeDate;
@end

@implementation KMHardwareProbe

#pragma mark - Host metadata

static NSString *KMSysctlString(const char *name) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) {
        return nil;
    }
    char *buf = malloc(size);
    if (!buf) {
        return nil;
    }
    NSString *result = nil;
    if (sysctlbyname(name, buf, &size, NULL, 0) == 0) {
        result = [NSString stringWithUTF8String:buf];
    }
    free(buf);
    return result;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hardwareModel = [KMSysctlString("hw.model") copy] ?: @"unknown";

        NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
        _osVersion = [[NSString stringWithFormat:@"%ld.%ld.%ld",
                       (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion] copy];

#if defined(__arm64__) || defined(__aarch64__)
        _architecture = @"arm64";
#elif defined(__x86_64__)
        _architecture = @"x86_64";
#elif defined(__i386__)
        _architecture = @"i386";
#else
        _architecture = @"unknown";
#endif

        NSBundle *b = [NSBundle mainBundle];
        NSString *shortVer = [b objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
        NSString *build    = [b objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
        _appBuild = [[NSString stringWithFormat:@"%@ (%@)", shortVer, build] copy];

        _capabilities = @[];
    }
    return self;
}

#pragma mark - Probe

- (NSArray<KMHardwareCapability *> *)runProbe {
    NSMutableArray<KMHardwareCapability *> *caps = [NSMutableArray array];

    // --- 1. Wi-Fi interface presence (CWWiFiClient, not deprecated CWInterface class methods).
    CWInterface *iface = nil;
    {
        CWWiFiClient *client = [CWWiFiClient sharedWiFiClient];
        NSArray<NSString *> *names = nil;
        if ([client respondsToSelector:@selector(interfaceNames)]) {
            names = [client interfaceNames]; // instance method (macOS 13+)
        }
        iface = [client interface];
        if (iface && iface.interfaceName.length) {
            [caps addObject:[KMHardwareCapability
                capabilityWithKey:KMCapWiFiInterfacePresent
                           status:KMCapabilityStatusSupported
                           reason:[NSString stringWithFormat:
                                   @"CWWiFiClient reports default interface '%@' (interfaceNames: %@).",
                                   iface.interfaceName,
                                   [names componentsJoinedByString:@", "] ?: @""]]];
        } else {
            [caps addObject:[KMHardwareCapability
                capabilityWithKey:KMCapWiFiInterfacePresent
                           status:KMCapabilityStatusUnsupported
                           reason:@"CWWiFiClient returned no default Wi-Fi interface; no built-in/usable Wi-Fi adapter visible to CoreWLAN."]];
        }
    }

    // --- 2. Location authorization state. READ ONLY. Do NOT request here (S1.2).
    BOOL locationAuthorized = NO;
    {
        BOOL servicesEnabled = [CLLocationManager locationServicesEnabled];
        // Instance authorizationStatus (macOS 11+); avoids the deprecated class
        // method. Deployment target is macOS 13, so the instance property is
        // always available. READ ONLY: constructing a CLLocationManager does not
        // request authorization (that is owned by a later slice).
        CLLocationManager *lm = [[CLLocationManager alloc] init];
        CLAuthorizationStatus authStatus = [lm authorizationStatus];

        NSString *remediation = @"Open System Settings > Privacy & Security > Location Services, "
                                @"enable Location Services, and allow KisMac. Without it macOS hides "
                                @"SSID/BSSID in Wi-Fi scans.";

        if (!servicesEnabled) {
            [caps addObject:[KMHardwareCapability
                capabilityWithKey:KMCapLocationAuthorization
                           status:KMCapabilityStatusPermissionMissing
                           reason:@"System Location Services are OFF; Wi-Fi scans will not reveal SSID/BSSID."
                      remediation:remediation]];
        } else {
            switch (authStatus) {
                case kCLAuthorizationStatusAuthorizedAlways:
#if !TARGET_OS_OSX
                // kCLAuthorizationStatusAuthorizedWhenInUse is unavailable on macOS;
                // on macOS the granted states are Always (and the legacy Authorized).
                case kCLAuthorizationStatusAuthorizedWhenInUse:
#endif
                    locationAuthorized = YES;
                    [caps addObject:[KMHardwareCapability
                        capabilityWithKey:KMCapLocationAuthorization
                                   status:KMCapabilityStatusSupported
                                   reason:@"Location authorization granted; SSID/BSSID visibility available to scans."]];
                    break;
                case kCLAuthorizationStatusNotDetermined:
                    [caps addObject:[KMHardwareCapability
                        capabilityWithKey:KMCapLocationAuthorization
                                   status:KMCapabilityStatusPermissionMissing
                                   reason:@"Location authorization not yet requested (kCLAuthorizationStatusNotDetermined). The auth flow is owned by a later slice; until granted macOS hides SSID/BSSID."
                              remediation:remediation]];
                    break;
                case kCLAuthorizationStatusDenied:
                case kCLAuthorizationStatusRestricted:
                default:
                    [caps addObject:[KMHardwareCapability
                        capabilityWithKey:KMCapLocationAuthorization
                                   status:KMCapabilityStatusPermissionMissing
                                   reason:[NSString stringWithFormat:
                                           @"Location authorization denied/restricted (status=%d). macOS hides SSID/BSSID until granted.",
                                           (int)authStatus]
                              remediation:remediation]];
                    break;
            }
        }
    }

    // --- 3. CoreWLAN scan support. API-available if we have an interface. Only
    //         perform a real (non-disruptive) scan if Location is authorized.
    if (!iface) {
        [caps addObject:[KMHardwareCapability
            capabilityWithKey:KMCapCoreWLANScan
                       status:KMCapabilityStatusUnsupported
                       reason:@"No CWInterface available; cannot scan."]];
    } else if (!locationAuthorized) {
        [caps addObject:[KMHardwareCapability
            capabilityWithKey:KMCapCoreWLANScan
                       status:KMCapabilityStatusPermissionMissing
                       reason:@"CWInterface scan API is available, but Location is not authorized; not scanning (macOS would return empty/redacted results). Scanning is non-disruptive once Location is granted."
                  remediation:@"Grant Location (see location.authorization) then re-run the probe."]];
    } else {
        NSError *scanErr = nil;
        // A passive list scan does NOT disconnect the current association.
        NSSet<CWNetwork *> *networks = [iface scanForNetworksWithName:nil error:&scanErr];
        if (networks) {
            [caps addObject:[KMHardwareCapability
                capabilityWithKey:KMCapCoreWLANScan
                           status:KMCapabilityStatusSupported
                           reason:[NSString stringWithFormat:
                                   @"scanForNetworksWithName: succeeded; %lu network(s) visible.",
                                   (unsigned long)networks.count]]];
        } else {
            [caps addObject:[KMHardwareCapability
                capabilityWithKey:KMCapCoreWLANScan
                           status:KMCapabilityStatusUnknownRequiresActiveProbe
                           reason:[NSString stringWithFormat:
                                   @"scanForNetworksWithName: returned error: %@",
                                   scanErr.localizedDescription ?: @"(unknown)"]]];
        }
    }

    // --- 4. Band visibility (2.4 / 5 / 6 GHz) from supportedWLANChannels.
    [self appendBandCapabilitiesForInterface:iface into:caps];

    // --- 5. PHY / security metadata exposed by CoreWLAN.
    if (iface) {
        CWPHYMode phy = [iface activePHYMode];
        NSString *ssid = [iface ssid];
        NSString *cc   = [iface countryCode];
        [caps addObject:[KMHardwareCapability
            capabilityWithKey:KMCapPHYMetadata
                       status:KMCapabilityStatusSupported
                       reason:[NSString stringWithFormat:
                               @"CoreWLAN exposes PHY/link metadata (activePHYMode=%ld, ssid=%@, countryCode=%@, rssi=%ld, txRate=%.0f).",
                               (long)phy, ssid ?: @"(none)", cc ?: @"(none)",
                               (long)[iface rssiValue], [iface transmitRate]]]];
    } else {
        [caps addObject:[KMHardwareCapability
            capabilityWithKey:KMCapPHYMetadata
                       status:KMCapabilityStatusUnsupported
                       reason:@"No CWInterface; PHY/security metadata unavailable."]];
    }

    // --- 6. pcap / BPF open availability (read-only; no monitor mode, no datalink change).
    [self appendPcapCapabilitiesForInterface:iface into:caps];

    // --- 7. Disruptive capabilities: REPORT, do NOT execute.
    NSString *disruptReason = @"Would disrupt connectivity (drop the Wi-Fi link / change radio "
                              @"state); requires explicit user-initiated active probe (future slice). "
                              @"Not executed by the default non-disruptive probe.";
    // TODO(S-active-probe): a future consented active-probe entry point would
    // verify these by actually exercising them. Do NOT wire it up here.
    for (NSString *key in @[KMCapMonitorCapture, KMCapChannelSwitching,
                            KMCapAPMode, KMCapFrameInjection]) {
        [caps addObject:[KMHardwareCapability
            capabilityWithKey:key
                       status:KMCapabilityStatusUnknownRequiresActiveProbe
                       reason:disruptReason]];
    }

    self.probeDate = [NSDate date];
    self.capabilities = [caps copy];
    return self.capabilities;
}

#pragma mark - Band visibility helper

- (void)appendBandCapabilitiesForInterface:(nullable CWInterface *)iface
                                      into:(NSMutableArray<KMHardwareCapability *> *)caps {
    if (!iface) {
        for (NSString *key in @[KMCapBand24GHz, KMCapBand5GHz, KMCapBand6GHz]) {
            [caps addObject:[KMHardwareCapability
                capabilityWithKey:key
                           status:KMCapabilityStatusUnsupported
                           reason:@"No CWInterface; cannot enumerate supported WLAN channels."]];
        }
        return;
    }

    NSSet<CWChannel *> *channels = [iface supportedWLANChannels];
    BOOL has24 = NO, has5 = NO, has6 = NO;
    NSUInteger c24 = 0, c5 = 0, c6 = 0;
    for (CWChannel *ch in channels) {
        switch (ch.channelBand) {
            case kCWChannelBand2GHz: has24 = YES; c24++; break;
            case kCWChannelBand5GHz: has5  = YES; c5++;  break;
            default:
                // 6 GHz uses kCWChannelBand6GHz where the SDK defines it.
                if (@available(macOS 13.0, *)) {
                    if (ch.channelBand == kCWChannelBand6GHz) { has6 = YES; c6++; }
                }
                break;
        }
    }

    if (!channels || channels.count == 0) {
        for (NSString *key in @[KMCapBand24GHz, KMCapBand5GHz, KMCapBand6GHz]) {
            [caps addObject:[KMHardwareCapability
                capabilityWithKey:key
                           status:KMCapabilityStatusUnknownRequiresActiveProbe
                           reason:@"supportedWLANChannels returned empty (often requires Location/Wi-Fi powered on); band visibility undetermined."]];
        }
        return;
    }

    [caps addObject:[KMHardwareCapability
        capabilityWithKey:KMCapBand24GHz
                   status:(has24 ? KMCapabilityStatusSupported : KMCapabilityStatusUnsupported)
                   reason:[NSString stringWithFormat:@"%lu 2.4 GHz channel(s) reported by supportedWLANChannels.", (unsigned long)c24]]];
    [caps addObject:[KMHardwareCapability
        capabilityWithKey:KMCapBand5GHz
                   status:(has5 ? KMCapabilityStatusSupported : KMCapabilityStatusUnsupported)
                   reason:[NSString stringWithFormat:@"%lu 5 GHz channel(s) reported by supportedWLANChannels.", (unsigned long)c5]]];
    if (@available(macOS 13.0, *)) {
        [caps addObject:[KMHardwareCapability
            capabilityWithKey:KMCapBand6GHz
                       status:(has6 ? KMCapabilityStatusSupported : KMCapabilityStatusUnsupported)
                       reason:[NSString stringWithFormat:@"%lu 6 GHz channel(s) reported by supportedWLANChannels (regulatory/hardware dependent).", (unsigned long)c6]]];
    } else {
        [caps addObject:[KMHardwareCapability
            capabilityWithKey:KMCapBand6GHz
                       status:KMCapabilityStatusUnsupported
                       reason:@"6 GHz band enum (kCWChannelBand6GHz) not available before macOS 13."]];
    }
}

#pragma mark - pcap / BPF helper

- (void)appendPcapCapabilitiesForInterface:(nullable CWInterface *)iface
                                      into:(NSMutableArray<KMHardwareCapability *> *)caps {
    const char *ifname = iface.interfaceName.length ? iface.interfaceName.UTF8String : "en0";

    // First: is a /dev/bpf node even openable? (read-only open; no ioctl, no monitor.)
    BOOL bpfOpenable = NO;
    NSString *bpfReasonDetail = @"";
    for (int i = 0; i < 8; i++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/bpf%d", i);
        int fd = open(path, O_RDONLY);
        if (fd >= 0) {
            bpfOpenable = YES;
            close(fd);
            bpfReasonDetail = [NSString stringWithFormat:@"%s openable", path];
            break;
        }
        if (errno == EBUSY) {
            // node exists but is in use; keep scanning for a free one.
            continue;
        }
        if (errno == EACCES || errno == EPERM) {
            bpfReasonDetail = [NSString stringWithFormat:@"%s permission denied (errno=%d)", path, errno];
            // Don't break: a later node might be openable, but record the hint.
        }
    }

    // Now attempt pcap_open_live WITHOUT promiscuous/monitor mode, tiny snaplen,
    // immediate close. This proves capture-handle creation, not monitor mode.
    char errbuf[PCAP_ERRBUF_SIZE];
    errbuf[0] = '\0';
    pcap_t *handle = pcap_open_live(ifname, 256, 0 /* non-promiscuous */, 10 /* ms */, errbuf);

    if (handle) {
        [caps addObject:[KMHardwareCapability
            capabilityWithKey:KMCapPcapOpen
                       status:KMCapabilityStatusSupported
                       reason:[NSString stringWithFormat:
                               @"pcap_open_live('%s', non-promiscuous) succeeded; live capture handle creatable. (%@)",
                               ifname, bpfReasonDetail.length ? bpfReasonDetail : @"bpf node available)"]]];

        // Datalink enumeration (read-only; does NOT change the datalink).
        int *dlts = NULL;
        int n = pcap_list_datalinks(handle, &dlts);
        if (n > 0 && dlts) {
            NSMutableArray<NSString *> *names = [NSMutableArray array];
            for (int i = 0; i < n; i++) {
                const char *nm = pcap_datalink_val_to_name(dlts[i]);
                [names addObject:nm ? [NSString stringWithUTF8String:nm]
                                    : [NSString stringWithFormat:@"DLT_%d", dlts[i]]];
            }
            [caps addObject:[KMHardwareCapability
                capabilityWithKey:KMCapDatalinkEnumeration
                           status:KMCapabilityStatusSupported
                           reason:[NSString stringWithFormat:@"%d datalink type(s) available on '%s': %@.",
                                   n, ifname, [names componentsJoinedByString:@", "]]]];
            pcap_free_datalinks(dlts);
        } else {
            [caps addObject:[KMHardwareCapability
                capabilityWithKey:KMCapDatalinkEnumeration
                           status:KMCapabilityStatusUnknownRequiresActiveProbe
                           reason:[NSString stringWithFormat:@"pcap_list_datalinks returned %d on '%s'; datalink set undetermined.", n, ifname]]];
            if (dlts) pcap_free_datalinks(dlts);
        }

        pcap_close(handle);
    } else {
        // Distinguish permission failure from genuine unsupported.
        NSString *err = [NSString stringWithUTF8String:errbuf[0] ? errbuf : "unknown error"];
        BOOL looksLikePermission = bpfOpenable == NO &&
            ([err.lowercaseString containsString:@"permission"] ||
             [err.lowercaseString containsString:@"operation not permitted"] ||
             [err.lowercaseString containsString:@"access"]);

        KMCapabilityStatus st = looksLikePermission
            ? KMCapabilityStatusPermissionMissing
            : KMCapabilityStatusUnsupported;
        NSString *rem = looksLikePermission
            ? @"BPF capture needs elevated rights. Either run with a privileged BPF helper or adjust /dev/bpf* access. (KisMac3 will gate live capture on this via the capability engine.)"
            : nil;

        [caps addObject:[KMHardwareCapability
            capabilityWithKey:KMCapPcapOpen
                       status:st
                       reason:[NSString stringWithFormat:@"pcap_open_live('%s') failed: %@. %@", ifname, err,
                               bpfReasonDetail.length ? bpfReasonDetail : @"no /dev/bpf node openable"]
                  remediation:rem]];

        [caps addObject:[KMHardwareCapability
            capabilityWithKey:KMCapDatalinkEnumeration
                       status:KMCapabilityStatusUnknownRequiresActiveProbe
                       reason:@"No live pcap handle could be opened; datalink set cannot be enumerated read-only."]];
    }
}

#pragma mark - Report

- (NSDictionary<NSString *, id> *)reportDictionary {
    NSMutableArray *capDicts = [NSMutableArray arrayWithCapacity:self.capabilities.count];
    for (KMHardwareCapability *c in self.capabilities) {
        [capDicts addObject:[c dictionaryRepresentation]];
    }

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    NSString *ts = [fmt stringFromDate:(self.probeDate ?: [NSDate date])];

    return @{
        @"schema":        @"kismac3.hardware-probe",
        @"schemaVersion": @1,
        @"timestamp":     ts,
        @"host": @{
            @"hardwareModel": self.hardwareModel ?: @"unknown",
            @"osVersion":     self.osVersion ?: @"unknown",
            @"architecture":  self.architecture ?: @"unknown",
            @"appBuild":      self.appBuild ?: @"unknown",
        },
        @"capabilities": capDicts,
    };
}

- (NSString *)applicationSupportDirectory {
    NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = dirs.firstObject ?: [@"~/Library/Application Support" stringByExpandingTildeInPath];
    return [base stringByAppendingPathComponent:@"KisMac3"];
}

- (NSString *)persistedReportPath {
    NSString *dir = [self applicationSupportDirectory];
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/ :\t\n"];
    NSString *model = [[(self.hardwareModel ?: @"unknown")
        componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
    NSString *os = [[(self.osVersion ?: @"unknown")
        componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
    NSString *file = [NSString stringWithFormat:@"hardware-probe-%@-%@.json", model, os];
    return [dir stringByAppendingPathComponent:file];
}

- (BOOL)persistReport:(NSError **)error {
    NSString *dir = [self applicationSupportDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                            attributes:nil error:error]) {
            return NO;
        }
    }
    NSError *jsonErr = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self reportDictionary]
                                                  options:NSJSONWritingPrettyPrinted
                                                    error:&jsonErr];
    if (!data) {
        if (error) *error = jsonErr;
        return NO;
    }
    return [data writeToFile:[self persistedReportPath]
                     options:NSDataWritingAtomic error:error];
}

- (NSString *)logSummary {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (KMHardwareCapability *c in self.capabilities) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@",
                          c.key, KMStringFromCapabilityStatus(c.status)]];
    }
    return [NSString stringWithFormat:@"[HW probe] %@ / macOS %@ / %@ / %@ -> %@",
            self.hardwareModel, self.osVersion, self.architecture, self.appBuild,
            [parts componentsJoinedByString:@" "]];
}

#pragma mark - Async convenience

+ (void)runProbeAsynchronouslyWithCompletion:(nullable void (^)(KMHardwareProbe *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        KMHardwareProbe *probe = [[KMHardwareProbe alloc] init];
        [probe runProbe];

        NSError *err = nil;
        BOOL ok = [probe persistReport:&err];

        DBNSLog(@"%@", [probe logSummary]);
        if (ok) {
            DBNSLog(@"[HW probe] report written to %@", [probe persistedReportPath]);
        } else {
            DBNSLog(@"[HW probe] FAILED to persist report: %@", err.localizedDescription);
        }

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(probe); });
        }
    });
}

@end
