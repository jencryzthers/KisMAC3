/*
 File:        KMPrivacySettings.m
 Program:     KisMac3
 Slice:       S4.1 - Campaign scope + audit log + emergency stop

 This file is part of KisMAC. GPL v2.
 */

#import "KMPrivacySettings.h"

NSString * const KMPrivacySettingsChangedNotification = @"KMPrivacySettingsChangedNotification";

static NSString * const kDefaultsKey = @"KMPrivacySettings";

@implementation KMPrivacySettings

+ (instancetype)sharedSettings {
    static KMPrivacySettings *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[self alloc] init];
        [shared load];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        // SAFE DEFAULTS.
        _storeLocally = YES;
        _serverExportEnabled = NO;
        _projectEncryptionEnabled = NO;
        _redaction = [KMRedactionSettings defaultSettings];
    }
    return self;
}

- (void)load {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kDefaultsKey];
    if (![d isKindOfClass:[NSDictionary class]]) return; // keep safe defaults
    // Only override when the key is explicitly present; missing => safe default.
    if (d[@"storeLocally"]) _storeLocally = [d[@"storeLocally"] boolValue];
    if (d[@"serverExportEnabled"]) _serverExportEnabled = [d[@"serverExportEnabled"] boolValue];
    if (d[@"projectEncryptionEnabled"]) _projectEncryptionEnabled = [d[@"projectEncryptionEnabled"] boolValue];

    NSData *redData = d[@"redaction"];
    if ([redData isKindOfClass:[NSData class]]) {
        KMRedactionSettings *r =
            [NSKeyedUnarchiver unarchivedObjectOfClass:[KMRedactionSettings class]
                                              fromData:redData error:NULL];
        if (r) _redaction = r;
    }
}

- (void)save {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"storeLocally"] = @(self.storeLocally);
    d[@"serverExportEnabled"] = @(self.serverExportEnabled);
    d[@"projectEncryptionEnabled"] = @(self.projectEncryptionEnabled);
    NSData *redData = [NSKeyedArchiver archivedDataWithRootObject:self.redaction
                                           requiringSecureCoding:YES error:NULL];
    if (redData) d[@"redaction"] = redData;
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kDefaultsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:KMPrivacySettingsChangedNotification
                                                        object:self];
}

- (BOOL)allowsServerExport {
    // Fail closed: server export only when explicitly enabled.
    return self.serverExportEnabled;
}

@end
