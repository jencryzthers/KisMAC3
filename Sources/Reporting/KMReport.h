/*
 File:        KMReport.h
 Program:     KisMac3
 Slice:       S6.1 - Secure .kismac load + unified report generator (Milestone 12)

 Description: Unified, structured report generator. KMReport assembles a single
              Markdown report from a populated WaveContainer plus the
              capability / inventory data already produced by the other slices:

                - discovered networks (with the S2.1 security/PHY strings),
                - observed clients,
                - LAN hosts/services (S3.3) + local interfaces (S3.4),
                - BLE devices (S3.1),
                - USB/HID/serial inventory (S3.2),
                - protocol / security posture summary,
                - capture / evidence files,
                - the MacBook capability result (from the S1.1 probe), and
                - unsupported / blocked features WITH REASONS, taken straight
                  from the S1.3 capability engine.

              It also emits an EVIDENCE TIMELINE with explicit source labels
              (CoreWLAN / CoreBluetooth / pcap / Kismet / USB / user-import /
              manual-note), and a "Capabilities & blocked features" section.

 ARCHITECTURE INVARIANT (enforced by construction):
   KMReport READS the capability engine + the data models. It NEVER decides
   capability or hardware support itself. Every capability/blocked-feature line
   is copied verbatim from KMCapabilityEngine / KMHardwareProbe output; the
   report does not re-derive support from hardware facts.

 PRIVACY (S4.1 / S4.2):
   - All identifiers (MAC/BSSID, SSID, hostname, BLE id, USB serial) are passed
     through the supplied KMRedactionSettings. When redaction is ENABLED the
     report never emits a raw identifier; when DISABLED it emits them verbatim
     (parity).
   - KMPrivacySettings is honored: the report is a LOCAL artifact. Writing it
     off-device / server export stays opt-in and OFF by default; -writeToFile:
     is local-only and the server-export guard lives with the caller.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

@class WaveContainer;
@class KMCapabilityEngine;
@class KMHardwareProbe;
@class KMRedactionSettings;
@class KMPrivacySettings;

NS_ASSUME_NONNULL_BEGIN

/// Stable source labels for the evidence timeline (Milestone 12).
typedef NS_ENUM(NSInteger, KMEvidenceSource) {
    KMEvidenceSourceCoreWLAN = 0,   // live Apple CoreWLAN scan
    KMEvidenceSourceCoreBluetooth,  // CoreBluetooth advertisement / GATT
    KMEvidenceSourcePcap,           // imported pcap/pcapng capture
    KMEvidenceSourceKismet,         // remote Kismet / drone backend
    KMEvidenceSourceUSB,            // USB/HID/serial inventory (IOKit)
    KMEvidenceSourceUserImport,     // user-imported file (NetStumbler, .kismac, ...)
    KMEvidenceSourceManualNote      // operator-entered note
};

extern NSString *KMStringFromEvidenceSource(KMEvidenceSource source);

#pragma mark - Evidence timeline entry

/// One dated line in the evidence timeline, tagged with its source.
@interface KMEvidenceEntry : NSObject
@property (nonatomic, strong, nullable) NSDate *timestamp;
@property (nonatomic, assign) KMEvidenceSource source;
/// Human-readable detail. Already-redacted by the caller when needed.
@property (nonatomic, copy) NSString *detail;

+ (instancetype)entryWithDate:(nullable NSDate *)date
                       source:(KMEvidenceSource)source
                       detail:(NSString *)detail;
@end

#pragma mark - KMReport

@interface KMReport : NSObject

#pragma mark Inputs (set what you have; nil/empty sections are emitted honestly)

/// Populated container of discovered networks / clients (REQUIRED for the
/// network + client + protocol sections). May be nil for a capabilities-only
/// report.
@property (nonatomic, weak, nullable) WaveContainer *container;

/// The capability engine. The report READS it for the capability / blocked-
/// features section; it never decides support itself. (Invariant.)
@property (nonatomic, strong, nullable) KMCapabilityEngine *capabilityEngine;

/// The hardware probe result, for the "MacBook capability result" section.
@property (nonatomic, strong, nullable) KMHardwareProbe *hardwareProbe;

/// Native-surface inventories (arrays of the S3.x model objects). Each renders
/// through the model's own -redactedDescriptionWithSettings: when redaction is
/// on, else its raw representation.
@property (nonatomic, copy, nullable) NSArray *bleDevices;        // KMBluetoothDevice
@property (nonatomic, copy, nullable) NSArray *usbDevices;        // KMUSBDevice
@property (nonatomic, copy, nullable) NSArray *hidDevices;        // KMHIDDevice
@property (nonatomic, copy, nullable) NSArray *serialDevices;     // KMSerialDevice
@property (nonatomic, copy, nullable) NSArray *lanServices;       // KMLANService
@property (nonatomic, copy, nullable) NSArray *networkInterfaces; // KMNetworkInterface

/// Capture / evidence file paths (just the paths; rendered with basename).
@property (nonatomic, copy, nullable) NSArray<NSString *> *captureFiles;

/// Extra evidence-timeline entries beyond those auto-derived from the networks.
@property (nonatomic, copy, nullable) NSArray<KMEvidenceEntry *> *additionalEvidence;

/// Redaction settings applied to ALL identifiers. nil => fully redacted
/// (safe). Typically [KMPrivacySettings sharedSettings].redaction.
@property (nonatomic, strong, nullable) KMRedactionSettings *redaction;

/// Privacy settings (local-only / server-export opt-in). Honored for the
/// header note + the -allowsServerExport guard. nil => shared settings.
@property (nonatomic, strong, nullable) KMPrivacySettings *privacy;

/// Optional report title.
@property (nonatomic, copy, nullable) NSString *title;

#pragma mark Generation

/// Render the full Markdown report.
- (NSString *)generateMarkdown;

/// Write the Markdown report to a local file. LOCAL-ONLY (this is not an
/// off-device export). Returns NO + populates *error on failure.
- (BOOL)writeMarkdownToFile:(NSString *)path error:(NSError **)error;

#pragma mark Self-test (S6.1 acceptance)

/// Runs the S6.1 self-test (Part A secure-load round-trip + malformed-input;
/// Part B golden.pcap report sections + redaction on/off) and logs PASS/FAIL
/// actual-vs-expected via DBNSLog. Returns YES iff ALL pass.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
