/*
 File:        KMLabEvent.h
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: One observed 802.11 MANAGEMENT-frame event, parsed PASSIVELY from
              an IMPORTED capture (pcap/pcapng). This is OBSERVATIONAL EVIDENCE
              only -- it is produced by reading already-captured frames, never
              by any live radio I/O. The lab event log (KMLabEventLog) is the
              event-log feature group of Milestone 10 (probes / associations /
              disassociations / deauthentications / handshakes), built strictly
              on top of the existing OFFLINE import path.

              Each event is timestamped, SOURCE-LABELED (pcap/import), and
              REDACTION-AWARE: -redactedDescriptionWithSettings: honors the S4.1
              KMRedactionSettings so identifiers are masked when redaction is on.

 SAFETY: this file models EVIDENCE. It transmits nothing and decides nothing
         about capability or hardware. It is fed WavePacket objects that the
         existing parser already produced from an imported file.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class KMRedactionSettings;
@class WavePacket;

NS_ASSUME_NONNULL_BEGIN

/// The management-frame event types the lab event log records. These map 1:1 to
/// 802.11 management subtypes (plus EAPOL/handshake, derived from data frames).
typedef NS_ENUM(NSInteger, KMLabEventType) {
    KMLabEventTypeUnknown = 0,
    KMLabEventTypeProbeRequest,      ///< mgmt subtype 0x4 (client looking for SSID)
    KMLabEventTypeProbeResponse,     ///< mgmt subtype 0x5
    KMLabEventTypeAuthentication,    ///< mgmt subtype 0xB
    KMLabEventTypeAssociationRequest,///< mgmt subtype 0x0
    KMLabEventTypeAssociationResponse,///< mgmt subtype 0x1
    KMLabEventTypeReassociationRequest,  ///< mgmt subtype 0x2
    KMLabEventTypeReassociationResponse, ///< mgmt subtype 0x3
    KMLabEventTypeDisassociation,    ///< mgmt subtype 0xA
    KMLabEventTypeDeauthentication,  ///< mgmt subtype 0xC
    KMLabEventTypeEAPOLHandshake,    ///< EAPOL key frame (WPA 4-way handshake msg)
};

/// Where the event came from. PASSIVE only (Milestone-10 event-log source labels
/// are a subset of the report's KMEvidenceSource; lab events are import-sourced).
typedef NS_ENUM(NSInteger, KMLabEventSource) {
    KMLabEventSourcePcapImport = 0,  ///< parsed from an imported pcap/pcapng file
};

extern NSString *KMStringFromLabEventType(KMLabEventType type);
extern NSString *KMStringFromLabEventSource(KMLabEventSource source);

@interface KMLabEvent : NSObject

/// When the event was observed (the frame's capture time, or now if absent).
@property (nonatomic, copy, readonly) NSDate *timestamp;
/// The management-frame event type.
@property (nonatomic, assign, readonly) KMLabEventType type;
/// Where it came from (passive import).
@property (nonatomic, assign, readonly) KMLabEventSource source;

/// The AP/BSSID involved (uppercase colon MAC string), or nil/empty.
@property (nonatomic, copy, readonly, nullable) NSString *bssid;
/// The client/station MAC involved (the frame's sender), or nil/empty.
@property (nonatomic, copy, readonly, nullable) NSString *clientMAC;
/// The SSID involved (for probe req/resp), or nil/empty.
@property (nonatomic, copy, readonly, nullable) NSString *ssid;
/// Wi-Fi channel where known (0 = unknown).
@property (nonatomic, assign, readonly) NSInteger channel;

- (instancetype)initWithType:(KMLabEventType)type
                       source:(KMLabEventSource)source
                    timestamp:(nullable NSDate *)timestamp
                        bssid:(nullable NSString *)bssid
                    clientMAC:(nullable NSString *)clientMAC
                         ssid:(nullable NSString *)ssid
                      channel:(NSInteger)channel NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Build an event from an already-parsed imported WavePacket. Returns nil if the
/// packet is not one of the management-frame / handshake event types we log.
/// PASSIVE: reads the packet's already-decoded fields; never touches a radio.
+ (nullable instancetype)eventFromImportedPacket:(WavePacket *)packet;

/// A compact, REDACTION-AWARE one-line description (honors KMRedactionSettings).
/// When redaction is enabled the BSSID/client/SSID are masked.
- (NSString *)redactedDescriptionWithSettings:(nullable KMRedactionSettings *)settings;

@end

NS_ASSUME_NONNULL_END
