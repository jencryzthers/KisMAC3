/*
 File:        KMLabAPProfileStore.h
 Program:     KisMac3
 Slice:       S7.1 - Authorized-lab workflow core (Milestone 10)

 Description: A small LOCAL, persisted store of KMLabAPProfile objects (owned
              test networks). Persists to a secure-coded plist under
              Application Support/KisMac3/lab-ap-profiles.plist. LOCAL-ONLY; the
              store holds DESCRIPTIVE profiles, never key material.

 SAFETY: persisting a profile does not authorize anything. A profile is only
         usable when it is within the current authorized campaign scope
         (-[KMLabAPProfile isUsableWithScopeProvider:]).

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>
#import "KMLabAPProfile.h"

NS_ASSUME_NONNULL_BEGIN

@interface KMLabAPProfileStore : NSObject

/// Shared store (Application Support/KisMac3/lab-ap-profiles.plist).
+ (instancetype)sharedStore;

/// Designated init for tests: persist to an explicit file URL.
- (instancetype)initWithFileURL:(NSURL *)fileURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// All stored profiles.
@property (nonatomic, copy, readonly) NSArray<KMLabAPProfile *> *profiles;

/// Add (or replace by identifier) a profile and persist. Returns YES on save.
- (BOOL)addProfile:(KMLabAPProfile *)profile;
/// Remove a profile by identifier and persist.
- (BOOL)removeProfileWithIdentifier:(NSString *)identifier;
/// Remove all profiles and persist (used by tests).
- (BOOL)removeAllProfiles;

/// Reload from disk (used after an external change / by tests).
- (BOOL)reload;

@end

NS_ASSUME_NONNULL_END
