/*
 File:        KMPrivacySettings.h
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 Description: Privacy / data-handling settings with SAFE defaults
              (Milestone 9):
                - local-only storage by default (storeLocally = YES)
                - server export OPT-IN, default OFF (serverExportEnabled = NO)
                - project-encryption option flag (projectEncryptionEnabled,
                  default OFF; the FLAG + documented path live here, the full
                  crypto impl is S6.x)
                - an embedded KMRedactionSettings instance

              These persist in NSUserDefaults under a stable key so the choice
              survives launches. The defaults are chosen so that a fresh
              install never exports off-device and never weakens local storage
              without an explicit opt-in.

              Encryption path (documented for S6.x): when
              projectEncryptionEnabled is YES, the .kismac project bundle's
              sensitive payload (captures + audit) should be sealed with a
              key derived from an operator passphrase (PBKDF2) / Keychain and
              written via NSSecureCoding into an encrypted container. S4.1 only
              records the operator's choice; it performs no crypto.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>
#import "KMRedactionSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted when any privacy setting changes (so UI / export paths can react).
extern NSString * const KMPrivacySettingsChangedNotification;

@interface KMPrivacySettings : NSObject

/// Shared settings, loaded from NSUserDefaults (safe defaults if absent).
+ (instancetype)sharedSettings;

/// Local-only storage. Default YES. (Off-device anything requires the explicit
/// server-export opt-in below.)
@property (nonatomic, assign) BOOL storeLocally;

/// Server export master opt-in. Default NO. Active features and report export
/// must consult this; it stays OFF unless the operator explicitly enables it.
@property (nonatomic, assign, getter=isServerExportEnabled) BOOL serverExportEnabled;

/// Project-encryption option. Default NO. The FLAG + documented path only in
/// S4.1; full crypto is S6.x.
@property (nonatomic, assign, getter=isProjectEncryptionEnabled) BOOL projectEncryptionEnabled;

/// Embedded redaction settings (also persisted).
@property (nonatomic, strong) KMRedactionSettings *redaction;

/// Persist the current values to NSUserDefaults and post the change note.
- (void)save;

/// YES iff exporting off-device is currently permitted (i.e. the opt-in is on).
/// Convenience guard for export code paths -- fails closed when unset.
- (BOOL)allowsServerExport;

@end

NS_ASSUME_NONNULL_END
