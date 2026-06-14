/*
 File:        KMLabEvent.m
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: See KMLabEvent.h. PASSIVE evidence parsed from imported frames.

 This file is part of KisMAC. GPL v2.
 */

#import "KMLabEvent.h"
#import "../Safety/KMRedactionSettings.h"
#import "../Core/WavePacket.h"
#import "../Core/80211b.h"

#import <sys/time.h>

NSString *KMStringFromLabEventType(KMLabEventType type) {
    switch (type) {
        case KMLabEventTypeProbeRequest:          return @"probe-request";
        case KMLabEventTypeProbeResponse:         return @"probe-response";
        case KMLabEventTypeAuthentication:        return @"authentication";
        case KMLabEventTypeAssociationRequest:    return @"association-request";
        case KMLabEventTypeAssociationResponse:   return @"association-response";
        case KMLabEventTypeReassociationRequest:  return @"reassociation-request";
        case KMLabEventTypeReassociationResponse: return @"reassociation-response";
        case KMLabEventTypeDisassociation:        return @"disassociation";
        case KMLabEventTypeDeauthentication:      return @"deauthentication";
        case KMLabEventTypeEAPOLHandshake:        return @"eapol-handshake";
        case KMLabEventTypeUnknown:               break;
    }
    return @"unknown";
}

NSString *KMStringFromLabEventSource(KMLabEventSource source) {
    switch (source) {
        case KMLabEventSourcePcapImport: return @"pcap/import";
    }
    return @"unknown";
}

@implementation KMLabEvent

- (instancetype)initWithType:(KMLabEventType)type
                       source:(KMLabEventSource)source
                    timestamp:(NSDate *)timestamp
                        bssid:(NSString *)bssid
                    clientMAC:(NSString *)clientMAC
                         ssid:(NSString *)ssid
                      channel:(NSInteger)channel {
    self = [super init];
    if (self) {
        _type = type;
        _source = source;
        _timestamp = timestamp ? [timestamp copy] : [NSDate date];
        _bssid = [bssid copy];
        _clientMAC = [clientMAC copy];
        _ssid = [ssid copy];
        _channel = channel;
    }
    return self;
}

+ (nullable instancetype)eventFromImportedPacket:(WavePacket *)packet {
    if (![packet isKindOfClass:[WavePacket class]]) return nil;

    KMLabEventType type = KMLabEventTypeUnknown;

    // Handshake / EAPOL evidence is derived from data frames carrying an EAPOL
    // key frame (the WPA 4-way handshake messages). Detect this first because a
    // handshake message is a data frame, not a management subtype.
    if ([packet isWPAKeyPacket]) {
        type = KMLabEventTypeEAPOLHandshake;
    } else if ([packet type] == IEEE80211_TYPE_MGT) {
        switch ([packet subType]) {
            case IEEE80211_SUBTYPE_PROBE_REQ:      type = KMLabEventTypeProbeRequest; break;
            case IEEE80211_SUBTYPE_PROBE_RESP:     type = KMLabEventTypeProbeResponse; break;
            case IEEE80211_SUBTYPE_AUTH:           type = KMLabEventTypeAuthentication; break;
            case IEEE80211_SUBTYPE_ASSOC_REQ:      type = KMLabEventTypeAssociationRequest; break;
            case IEEE80211_SUBTYPE_ASSOC_RESP:     type = KMLabEventTypeAssociationResponse; break;
            case IEEE80211_SUBTYPE_REASSOC_REQ:    type = KMLabEventTypeReassociationRequest; break;
            case IEEE80211_SUBTYPE_REASSOC_RESP:   type = KMLabEventTypeReassociationResponse; break;
            case IEEE80211_SUBTYPE_DISASSOC:       type = KMLabEventTypeDisassociation; break;
            case IEEE80211_SUBTYPE_DEAUTH:         type = KMLabEventTypeDeauthentication; break;
            default:                               type = KMLabEventTypeUnknown; break;
        }
    }

    if (type == KMLabEventTypeUnknown) return nil;  // not an event we log

    // Capture timestamp from the frame (offline pcaps carry real ts).
    struct timeval *tv = [packet creationTime];
    NSDate *ts = nil;
    if (tv && tv->tv_sec > 0) {
        ts = [NSDate dateWithTimeIntervalSince1970:
              (NSTimeInterval)tv->tv_sec + (NSTimeInterval)tv->tv_usec / 1.0e6];
    }

    NSString *bssid = [packet BSSIDString];
    if ([bssid isEqualToString:@"<no bssid>"]) bssid = nil;

    // The sender of the frame is the relevant station for probe-req / auth /
    // assoc / handshake; for an AP-originated frame it is the AP itself.
    NSString *client = [packet stringSenderID];

    NSString *ssid = [packet SSID];
    if (ssid.length == 0) ssid = nil;

    return [[self alloc] initWithType:type
                               source:KMLabEventSourcePcapImport
                            timestamp:ts
                                bssid:bssid
                            clientMAC:client
                                 ssid:ssid
                              channel:[packet channel]];
}

- (NSString *)redactedDescriptionWithSettings:(KMRedactionSettings *)settings {
    NSString *bssid = settings ? [settings redactMAC:(self.bssid ?: @"")] : (self.bssid ?: @"");
    NSString *client = settings ? [settings redactMAC:(self.clientMAC ?: @"")] : (self.clientMAC ?: @"");
    NSString *ssid = settings ? [settings redactSSID:(self.ssid ?: @"")] : (self.ssid ?: @"");

    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"%@", KMStringFromLabEventType(self.type)];
    if (ssid.length)   [s appendFormat:@" ssid=%@", ssid];
    if (bssid.length)  [s appendFormat:@" bssid=%@", bssid];
    if (client.length) [s appendFormat:@" sta=%@", client];
    if (self.channel)  [s appendFormat:@" ch=%ld", (long)self.channel];
    [s appendFormat:@" [%@]", KMStringFromLabEventSource(self.source)];
    return s;
}

- (NSString *)description {
    // Default description is REDACTED-safe (mirrors the S3.x model convention):
    // never leak a raw identifier into a log line by accident.
    KMRedactionSettings *safe = [KMRedactionSettings defaultSettings];
    safe.enabled = YES;
    return [self redactedDescriptionWithSettings:safe];
}

@end
