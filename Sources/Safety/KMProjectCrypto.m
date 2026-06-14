/*
 File:        KMProjectCrypto.m
 Program:     KisMac3
 Slice:       S6.2 - Project encryption option (Milestone 12 privacy)

 Description: See KMProjectCrypto.h. CommonCrypto only. CPU-only / LOCAL-ONLY.

              Construction: authenticated encryption via encrypt-then-MAC.
              The public CommonCrypto SDK on this deployment target (macOS 13)
              exposes AES + HMAC but NOT the GCM SPI, so we use the standard,
              provably-sound Encrypt-then-MAC (EtM) composition:

                key material = PBKDF2-HMAC-SHA256(passphrase, salt, iters) -> 64 B
                               split into encKey(32) || macKey(32)
                ciphertext   = AES-256-CBC(encKey, iv, PKCS7(plaintext))
                tag(32)      = HMAC-SHA256(macKey, headerBytes || iv || ciphertext)

              EtM over the full header + iv binds every envelope field; any
              tamper (or a wrong passphrase -> wrong macKey) makes the HMAC
              mismatch, so open() returns nil BEFORE any decrypt is attempted —
              never partial/garbage plaintext. The MAC compare is constant-time.

 This file is part of KisMAC. GPL v2.
 */

#import "KMProjectCrypto.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>               // SecRandomCopyBytes

#ifndef DBNSLog
    #define DBNSLog NSLog
#endif

const char * const KMProjectCryptoMagic       = "KMENC1";
const NSUInteger    KMProjectCryptoMagicLength = 6;
NSString * const    KMProjectCryptoErrorDomain = @"KMProjectCryptoErrorDomain";

// Envelope layout (all integers big-endian):
//   magic(6)="KMENC1" | version(1) | kdf(1) | iterations(4) |
//   salt(16) | iv(16) | ciphertext(len) | tag(32)
// The leading 40 bytes (through iv) are the authenticated header; the HMAC tag
// covers header || iv || ciphertext (the whole envelope minus the tag itself).
static const uint8_t  kVersion           = 1;
static const uint8_t  kKDF_PBKDF2_SHA256 = 1;
// Sizes are #defines (not const vars) so they can size C stack arrays without
// tripping -Wgnu-folding-constant (a const NSUInteger reads as a VLA bound).
#define kSaltLen   16
#define kIVLen     kCCBlockSizeAES128       // 16
#define kTagLen    CC_SHA256_DIGEST_LENGTH  // 32
#define kEncKeyLen kCCKeySizeAES256         // 32 (AES-256)
#define kMacKeyLen 32
#define kKeyMatLen 64                        // encKey(32) || macKey(32)
#define kHeaderLen (6 + 1 + 1 + 4 + kSaltLen + kIVLen) // = 44
static const uint32_t kMinIterations = 210000u;

@implementation KMProjectCrypto

#pragma mark - helpers

static NSData *failNil(NSError **error, KMProjectCryptoError code, NSString *msg) {
    if (error) {
        *error = [NSError errorWithDomain:KMProjectCryptoErrorDomain
                                     code:code
                                 userInfo:@{ NSLocalizedDescriptionKey: msg }];
    }
    return nil;
}

static BOOL randomBytes(uint8_t *buf, size_t n) {
    return SecRandomCopyBytes(kSecRandomDefault, n, buf) == errSecSuccess;
}

// Constant-time compare. Returns YES iff equal. Does not short-circuit on the
// first differing byte (no timing oracle on the tag).
static BOOL ctEqual(const uint8_t *a, const uint8_t *b, size_t n) {
    uint8_t diff = 0;
    for (size_t i = 0; i < n; ++i) diff |= (uint8_t)(a[i] ^ b[i]);
    return diff == 0;
}

#pragma mark - detection

+ (BOOL)isEncryptedEnvelope:(NSData *)data {
    if (![data isKindOfClass:[NSData class]] || data.length < KMProjectCryptoMagicLength) return NO;
    return memcmp(data.bytes, KMProjectCryptoMagic, KMProjectCryptoMagicLength) == 0;
}

+ (BOOL)fileIsEncryptedEnvelope:(NSString *)path {
    if (path.length == 0) return NO;
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return NO;
    NSData *head = nil;
    @try { head = [fh readDataOfLength:KMProjectCryptoMagicLength]; }
    @catch (__unused NSException *e) { head = nil; }
    [fh closeFile];
    return [self isEncryptedEnvelope:head];
}

#pragma mark - KDF

// Derive 64 bytes (encKey(32) || macKey(32)) via PBKDF2-HMAC-SHA256.
static BOOL deriveKeyMaterial(NSString *passphrase, const uint8_t *salt, NSUInteger saltLen,
                              uint32_t iterations, uint8_t outKeyMat[64]) {
    NSData *pw = [passphrase dataUsingEncoding:NSUTF8StringEncoding];
    if (!pw) return NO;
    int rc = CCKeyDerivationPBKDF(kCCPBKDF2,
                                  (const char *)pw.bytes, pw.length,
                                  salt, saltLen,
                                  kCCPRFHmacAlgSHA256, iterations,
                                  outKeyMat, kKeyMatLen);
    return rc == kCCSuccess;
}

static uint32_t calibratedIterations(NSUInteger passLen) {
    uint32_t n = CCCalibratePBKDF(kCCPBKDF2,
                                  passLen ?: 8, kSaltLen,
                                  kCCPRFHmacAlgSHA256, kEncKeyLen,
                                  150 /*ms*/);
    if (n < kMinIterations) n = kMinIterations;
    return n;
}

#pragma mark - seal

+ (NSData *)sealData:(NSData *)plaintext
      withPassphrase:(NSString *)passphrase
               error:(NSError **)error {
    if (error) *error = nil;
    if (passphrase.length == 0) {
        return failNil(error, KMProjectCryptoErrorNoPassphrase, @"No passphrase set for project encryption.");
    }
    if (![plaintext isKindOfClass:[NSData class]]) {
        return failNil(error, KMProjectCryptoErrorInternal, @"No plaintext to seal.");
    }

    uint8_t salt[kSaltLen], iv[kIVLen];
    if (!randomBytes(salt, kSaltLen) || !randomBytes(iv, kIVLen)) {
        return failNil(error, KMProjectCryptoErrorInternal, @"CSPRNG unavailable.");
    }
    uint32_t iterations = calibratedIterations([passphrase dataUsingEncoding:NSUTF8StringEncoding].length);

    uint8_t km[kKeyMatLen];
    if (!deriveKeyMaterial(passphrase, salt, kSaltLen, iterations, km)) {
        memset(km, 0, sizeof(km));
        return failNil(error, KMProjectCryptoErrorKeyDerivation, @"Key derivation (PBKDF2) failed.");
    }
    const uint8_t *encKey = km;
    const uint8_t *macKey = km + kEncKeyLen;

    // AES-256-CBC encrypt with PKCS7 padding.
    size_t cipherCap = plaintext.length + kCCBlockSizeAES128;
    NSMutableData *cipher = [NSMutableData dataWithLength:cipherCap];
    size_t cipherLen = 0;
    CCCryptorStatus rc = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 encKey, kEncKeyLen, iv,
                                 plaintext.bytes, plaintext.length,
                                 cipher.mutableBytes, cipherCap, &cipherLen);
    if (rc != kCCSuccess) {
        memset(km, 0, sizeof(km));
        return failNil(error, KMProjectCryptoErrorInternal, @"AES-256-CBC encrypt failed.");
    }
    cipher.length = cipherLen;

    // Build the authenticated header.
    NSMutableData *out = [NSMutableData dataWithCapacity:kHeaderLen + cipherLen + kTagLen];
    [out appendBytes:KMProjectCryptoMagic length:KMProjectCryptoMagicLength];
    uint8_t ver = kVersion, kdf = kKDF_PBKDF2_SHA256;
    [out appendBytes:&ver length:1];
    [out appendBytes:&kdf length:1];
    uint32_t itersBE = CFSwapInt32HostToBig(iterations);
    [out appendBytes:&itersBE length:4];
    [out appendBytes:salt length:kSaltLen];
    [out appendBytes:iv length:kIVLen];
    [out appendData:cipher];   // out now == header || iv || ciphertext (no tag yet)

    // Encrypt-then-MAC: HMAC-SHA256(macKey, header||iv||ciphertext).
    uint8_t tag[kTagLen];
    CCHmac(kCCHmacAlgSHA256, macKey, kMacKeyLen, out.bytes, out.length, tag);
    [out appendBytes:tag length:kTagLen];

    memset(km, 0, sizeof(km));
    return out;
}

#pragma mark - open

+ (NSData *)openData:(NSData *)envelope
      withPassphrase:(NSString *)passphrase
               error:(NSError **)error {
    if (error) *error = nil;
    if (passphrase.length == 0) {
        return failNil(error, KMProjectCryptoErrorNoPassphrase, @"No passphrase provided to open encrypted project.");
    }
    if (![envelope isKindOfClass:[NSData class]] || envelope.length < kHeaderLen + kTagLen) {
        return failNil(error, KMProjectCryptoErrorBadEnvelope, @"Envelope too short or missing.");
    }
    const uint8_t *p = envelope.bytes;
    if (memcmp(p, KMProjectCryptoMagic, KMProjectCryptoMagicLength) != 0) {
        return failNil(error, KMProjectCryptoErrorBadEnvelope, @"Not a KisMAC encrypted envelope.");
    }
    NSUInteger off = KMProjectCryptoMagicLength;
    uint8_t ver = p[off++];
    uint8_t kdf = p[off++];
    if (ver != kVersion || kdf != kKDF_PBKDF2_SHA256) {
        return failNil(error, KMProjectCryptoErrorBadEnvelope, @"Unsupported envelope version/KDF.");
    }
    uint32_t itersBE; memcpy(&itersBE, p + off, 4); off += 4;
    uint32_t iterations = CFSwapInt32BigToHost(itersBE);
    if (iterations < 1) {
        return failNil(error, KMProjectCryptoErrorBadEnvelope, @"Invalid iteration count.");
    }
    const uint8_t *salt = p + off; off += kSaltLen;
    const uint8_t *iv   = p + off; off += kIVLen; // off == kHeaderLen

    NSUInteger cipherLen = envelope.length - kHeaderLen - kTagLen;
    const uint8_t *cipher = p + kHeaderLen;
    const uint8_t *tagIn  = p + kHeaderLen + cipherLen;
    // CBC ciphertext must be a positive whole number of blocks.
    if (cipherLen == 0 || (cipherLen % kCCBlockSizeAES128) != 0) {
        return failNil(error, KMProjectCryptoErrorBadEnvelope, @"Ciphertext length invalid.");
    }

    uint8_t km[kKeyMatLen];
    if (!deriveKeyMaterial(passphrase, salt, kSaltLen, iterations, km)) {
        memset(km, 0, sizeof(km));
        return failNil(error, KMProjectCryptoErrorKeyDerivation, @"Key derivation (PBKDF2) failed.");
    }
    const uint8_t *encKey = km;
    const uint8_t *macKey = km + kEncKeyLen;

    // VERIFY FIRST (encrypt-then-MAC): recompute HMAC over header||iv||ciphertext
    // and constant-time compare. A wrong passphrase yields a wrong macKey -> the
    // tag mismatches -> we bail BEFORE decrypting. No plaintext is ever produced
    // for a wrong passphrase or tampered envelope.
    uint8_t calcTag[kTagLen];
    CCHmac(kCCHmacAlgSHA256, macKey, kMacKeyLen, p, kHeaderLen + cipherLen, calcTag);
    if (!ctEqual(calcTag, tagIn, kTagLen)) {
        memset(km, 0, sizeof(km));
        return failNil(error, KMProjectCryptoErrorAuthFailed,
                       @"Authentication failed: wrong passphrase or tampered project.");
    }

    // Authenticated: now decrypt.
    NSMutableData *plain = [NSMutableData dataWithLength:cipherLen + kCCBlockSizeAES128];
    size_t plainLen = 0;
    CCCryptorStatus rc = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 encKey, kEncKeyLen, iv,
                                 cipher, cipherLen,
                                 plain.mutableBytes, plain.length, &plainLen);
    memset(km, 0, sizeof(km));
    if (rc != kCCSuccess) {
        if (plain.length) memset(plain.mutableBytes, 0, plain.length);
        return failNil(error, KMProjectCryptoErrorAuthFailed,
                       @"Decrypt failed after authentication (corrupt padding).");
    }
    plain.length = plainLen;
    return plain;
}

#pragma mark - in-memory passphrase (NEVER persisted)

static NSString *gSessionPassphrase = nil;   // memory only — never written anywhere

+ (void)setSessionPassphrase:(NSString *)passphrase {
    @synchronized (self) {
        gSessionPassphrase = (passphrase.length ? [passphrase copy] : nil);
    }
}

+ (NSString *)sessionPassphrase {
    @synchronized (self) { return gSessionPassphrase; }
}

+ (BOOL)hasSessionPassphrase {
    @synchronized (self) { return gSessionPassphrase.length > 0; }
}

+ (void)clearSessionPassphrase {
    @synchronized (self) { gSessionPassphrase = nil; }
}

#pragma mark - self-test (S6.2)

static BOOL pcAssert(BOOL cond, NSString *label, NSString *detail, BOOL *all) {
    *all = *all && cond;
    DBNSLog(@"[PROJCRYPTO-SELFTEST] %@ %@%@",
            cond ? @"PASS" : @"FAIL", label,
            detail.length ? [@" — " stringByAppendingString:detail] : @"");
    return cond;
}

+ (BOOL)runSelfTestLogging {
    DBNSLog(@"[PROJCRYPTO-SELFTEST] === S6.2 project encryption envelope (AES-256-CBC + HMAC-SHA256 EtM / PBKDF2-HMAC-SHA256) ===");
    BOOL all = YES;

    NSString *pass  = @"correct horse battery staple";
    NSString *wrong = @"correct horse battery staplE";
    // Plaintext stands in for a serialized .kismac payload; we check a marker's
    // presence WITHOUT logging the recovered bytes themselves.
    NSData *plain = [@"KISMAC-PROJCRYPTO-PLAINTEXT-MARKER-0123456789abcdef-padme" dataUsingEncoding:NSUTF8StringEncoding];

    NSError *err = nil;
    NSData *env1 = [self sealData:plain withPassphrase:pass error:&err];
    pcAssert(env1 != nil && err == nil, @"seal #1 produced an envelope",
             env1 ? [NSString stringWithFormat:@"len=%lu", (unsigned long)env1.length] : @"nil", &all);

    // (a) round-trip recovers identical plaintext with the right passphrase.
    err = nil;
    NSData *back = env1 ? [self openData:env1 withPassphrase:pass error:&err] : nil;
    pcAssert(back != nil && [back isEqualToData:plain] && err == nil,
             @"round-trip: open(seal(x)) == x with right passphrase",
             back ? @"recovered (bytes equal)" : @"nil", &all);

    // (b) WRONG passphrase -> nil + error, no plaintext leak.
    err = nil;
    NSData *bad = env1 ? [self openData:env1 withPassphrase:wrong error:&err] : nil;
    pcAssert(bad == nil && err != nil && err.code == KMProjectCryptoErrorAuthFailed,
             @"wrong passphrase fails (nil + authFailed), no leak",
             [NSString stringWithFormat:@"out=%@ code=%ld", bad ? @"BYTES(!)" : @"nil", (long)err.code], &all);

    // (c) TAMPERED ciphertext -> auth fails, no plaintext.
    if (env1) {
        NSMutableData *t = [env1 mutableCopy];
        NSUInteger flipAt = t.length - kTagLen - 1; // last ciphertext byte
        ((uint8_t *)t.mutableBytes)[flipAt] ^= 0x01;
        err = nil;
        NSData *tampered = [self openData:t withPassphrase:pass error:&err];
        pcAssert(tampered == nil && err.code == KMProjectCryptoErrorAuthFailed,
                 @"tampered ciphertext fails auth, no plaintext",
                 [NSString stringWithFormat:@"out=%@ code=%ld", tampered ? @"BYTES(!)" : @"nil", (long)err.code], &all);
    }
    // (c2) TAMPERED tag -> auth fails.
    if (env1) {
        NSMutableData *t = [env1 mutableCopy];
        ((uint8_t *)t.mutableBytes)[t.length - 1] ^= 0x80; // last tag byte
        err = nil;
        NSData *tampered = [self openData:t withPassphrase:pass error:&err];
        pcAssert(tampered == nil && err.code == KMProjectCryptoErrorAuthFailed,
                 @"tampered tag fails auth, no plaintext",
                 [NSString stringWithFormat:@"out=%@ code=%ld", tampered ? @"BYTES(!)" : @"nil", (long)err.code], &all);
    }

    // (d) versioned + salt/iv differ across two seals of the SAME input.
    err = nil;
    NSData *env2 = [self sealData:plain withPassphrase:pass error:&err];
    BOOL versioned = NO, saltDiff = NO, ivDiff = NO;
    if (env1 && env2 && env1.length >= kHeaderLen && env2.length >= kHeaderLen) {
        const uint8_t *a = env1.bytes, *b = env2.bytes;
        versioned = (memcmp(a, KMProjectCryptoMagic, KMProjectCryptoMagicLength) == 0
                     && a[KMProjectCryptoMagicLength] == kVersion);
        NSUInteger saltOff = KMProjectCryptoMagicLength + 1 + 1 + 4;
        NSUInteger ivOff   = saltOff + kSaltLen;
        saltDiff = (memcmp(a + saltOff, b + saltOff, kSaltLen) != 0);
        ivDiff   = (memcmp(a + ivOff,   b + ivOff,   kIVLen)   != 0);
    }
    pcAssert(versioned, @"envelope carries magic + version byte", versioned ? @"KMENC1 v1" : @"missing", &all);
    pcAssert(saltDiff && ivDiff, @"salt AND iv (nonce) differ across two seals of same input",
             [NSString stringWithFormat:@"saltDiff=%d ivDiff=%d", saltDiff, ivDiff], &all);

    // (e) envelope detection helpers.
    pcAssert(env1 && [self isEncryptedEnvelope:env1], @"isEncryptedEnvelope detects KMENC1", nil, &all);
    pcAssert(![self isEncryptedEnvelope:plain], @"isEncryptedEnvelope rejects plain (non-envelope) data", nil, &all);

    // (f) no-passphrase guards.
    err = nil;
    NSData *noPass = [self sealData:plain withPassphrase:@"" error:&err];
    pcAssert(noPass == nil && err.code == KMProjectCryptoErrorNoPassphrase,
             @"seal with empty passphrase refused", [NSString stringWithFormat:@"code=%ld", (long)err.code], &all);

    DBNSLog(@"[PROJCRYPTO-SELFTEST] %@  (CommonCrypto AES-256-CBC + HMAC-SHA256 encrypt-then-MAC, "
            @"PBKDF2-HMAC-SHA256 KDF; passphrase memory-only, never logged) [CPU-only, no radio]",
            all ? @"ALL PASS" : @"FAILURES PRESENT");
    return all;
}

@end
