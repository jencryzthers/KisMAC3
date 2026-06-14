/*
 File:        KMProjectCrypto.h
 Program:     KisMac3
 Slice:       S6.2 - Project encryption option (Milestone 12 privacy)

 Description: Passphrase-based authenticated-encryption envelope for the
              `.kismac` project payload, used when
              KMPrivacySettings.projectEncryptionEnabled is ON and an operator
              passphrase has been set.

              Crypto (CommonCrypto only, no third-party deps). The public
              CommonCrypto SDK on the deployment target (macOS 13) exposes AES +
              HMAC but NOT the GCM SPI, so this uses the standard, sound
              Encrypt-then-MAC (EtM) authenticated construction:
                - Key derivation: PBKDF2-HMAC-SHA256 from the passphrase with a
                  random 16-byte salt and a calibrated iteration count
                  (CCCalibratePBKDF targeting ~150 ms, floored at 210000) -> 64
                  bytes, split into encKey(32) || macKey(32).
                - Seal:  AES-256-CBC(encKey, iv, PKCS7(plaintext)), then
                  tag = HMAC-SHA256(macKey, header || iv || ciphertext),
                  producing a versioned envelope:
                    magic(6 "KMENC1") | ver(1) | kdf(1) | iterations(4 BE) |
                    salt(16) | iv(16) | ciphertext(n) | tag(32)
                - Open:  parse the envelope, re-derive keys, VERIFY the HMAC
                  (constant-time) BEFORE decrypting. A wrong passphrase (wrong
                  macKey) or any tampering (ciphertext/tag/header) fails the MAC
                  -> returns nil + NSError, never a partial or garbage plaintext.

              Passphrase handling (privacy invariant): the passphrase lives in
              memory ONLY. It is NEVER written to disk, NSUserDefaults, the audit
              log, or any log line. Key material and plaintext are never logged.
              The salt and nonce are freshly random on every seal.

 This file is part of KisMAC. GPL v2.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The 6-byte magic header that marks an encrypted `.kismac` envelope.
extern const char * const KMProjectCryptoMagic;      // "KMENC1"
extern const NSUInteger KMProjectCryptoMagicLength;  // 6

/// NSError domain for envelope/crypto failures.
extern NSString * const KMProjectCryptoErrorDomain;

typedef NS_ENUM(NSInteger, KMProjectCryptoError) {
    KMProjectCryptoErrorNoPassphrase   = 1,  // encryption requested but no passphrase set
    KMProjectCryptoErrorBadEnvelope    = 2,  // truncated / wrong magic / unsupported version
    KMProjectCryptoErrorKeyDerivation  = 3,  // PBKDF2 failed
    KMProjectCryptoErrorAuthFailed     = 4,  // HMAC auth failed: wrong passphrase or tamper
    KMProjectCryptoErrorInternal       = 5,  // unexpected CommonCrypto failure
};

@interface KMProjectCrypto : NSObject

#pragma mark - Envelope detection

/// YES iff `data` begins with the KMENC1 magic header (i.e. is an encrypted
/// envelope). A non-encrypted (legacy/plain gzip) file returns NO.
+ (BOOL)isEncryptedEnvelope:(NSData *)data;

/// YES iff the file at `path` begins with the KMENC1 magic header. Reads only
/// the first few bytes. Returns NO for a missing/unreadable file.
+ (BOOL)fileIsEncryptedEnvelope:(NSString *)path;

#pragma mark - Seal / Open

/// Seal `plaintext` under `passphrase` into a versioned, authenticated envelope.
/// Fresh random salt + nonce each call. Returns nil + *error on failure.
+ (nullable NSData *)sealData:(NSData *)plaintext
               withPassphrase:(NSString *)passphrase
                        error:(NSError **)error;

/// Open (verify + decrypt) an envelope produced by +sealData:withPassphrase:.
/// A wrong passphrase or any tampering fails HMAC authentication and returns
/// nil + *error (KMProjectCryptoErrorAuthFailed) — never partial/garbage bytes.
+ (nullable NSData *)openData:(NSData *)envelope
               withPassphrase:(NSString *)passphrase
                        error:(NSError **)error;

#pragma mark - In-memory passphrase (NEVER persisted)

/// The operator passphrase used by WaveStorageController save/load when
/// KMPrivacySettings.projectEncryptionEnabled is ON. Held in memory only; the
/// setter NEVER writes to disk/defaults/logs. nil/empty => "no passphrase set".
+ (void)setSessionPassphrase:(nullable NSString *)passphrase;
+ (nullable NSString *)sessionPassphrase;
+ (BOOL)hasSessionPassphrase;
/// Wipe the in-memory passphrase (e.g. on lock / emergency stop).
+ (void)clearSessionPassphrase;

#pragma mark - Self-test (S6.2)

/// Headless self-test (KISMAC_PROJCRYPTO_SELFTEST=1). Asserts seal/open
/// round-trip, wrong-passphrase failure, tamper failure, envelope versioning,
/// and salt/nonce uniqueness. Logs PASS/FAIL — never keys/passphrases/plaintext.
+ (BOOL)runSelfTestLogging;

@end

NS_ASSUME_NONNULL_END
