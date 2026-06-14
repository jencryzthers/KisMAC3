/*
 File:          KMCryptoSelfTest.m
 Program:       KisMac3
 Slice:         S2.3 - Crypto/cracking modernization

 Description:   See KMCryptoSelfTest.h. CPU-only / PASSIVE ONLY.

 This file is part of KisMAC. GPL v2.
 */

#import "KMCryptoSelfTest.h"
#import <CommonCrypto/CommonCrypto.h>

#import "WPA.h"    // wpaTestPasswordHash(), PRF()
#import "LEAP.h"   // NtPasswordHash(), gethashlast2(), testChallenge()
#import "../3rd Party/DESSupport.h" // DesEncrypt()

// Defined (no header) in Sources/Crypto/WaveNetWPACrack.m. This is the migrated
// CommonCrypto CCKeyDerivationPBKDF PMK path that replaced the old hand-rolled
// PolarSSL HMAC-SHA1 unrolling. Declared here so the self-test can assert it
// matches the reference wpaPasswordHash().
extern void fastWP_passwordHash(char *password, const unsigned char *ssid,
                                NSInteger ssidlength, unsigned char output[40]);

#pragma mark - helpers

static NSString *hexstr(const unsigned char *b, NSUInteger n) {
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
    for (NSUInteger i = 0; i < n; ++i) [s appendFormat:@"%02x", b[i]];
    return s;
}

// Log one PASS/FAIL line (actual vs expected) and AND the result into *ok.
static void checkDigest(const char *label,
                        const unsigned char *actual,
                        const unsigned char *expected,
                        NSUInteger len,
                        BOOL *ok) {
    BOOL pass = (memcmp(actual, expected, len) == 0);
    *ok = *ok && pass;
    DBNSLog(@"[CRYPTO-SELFTEST] %s %s actual=%@ expected=%@",
            pass ? "PASS" : "FAIL", label,
            hexstr(actual, len), hexstr(expected, len));
}

@implementation KMCryptoSelfTest

+ (BOOL)runSelfTestLogging
{
    BOOL ok = YES;

    // --- 1. Raw digest primitives (CommonCrypto) ---------------------------
    // CC_MD4("") = 31d6cfe0d16ae931b73c59d7e0c089c0 (well-known empty MD4)
    {
        unsigned char d[CC_MD4_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CC_MD4("", 0, d);
#pragma clang diagnostic pop
        const unsigned char exp[16] = {0x31,0xd6,0xcf,0xe0,0xd1,0x6a,0xe9,0x31,
                                       0xb7,0x3c,0x59,0xd7,0xe0,0xc0,0x89,0xc0};
        checkDigest("CC_MD4(\"\")", d, exp, 16, &ok);
    }
    // CC_MD5("abc") = 900150983cd24fb0d6963f7d28e17f72
    {
        unsigned char d[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CC_MD5("abc", 3, d);
#pragma clang diagnostic pop
        const unsigned char exp[16] = {0x90,0x01,0x50,0x98,0x3c,0xd2,0x4f,0xb0,
                                       0xd6,0x96,0x3f,0x7d,0x28,0xe1,0x7f,0x72};
        checkDigest("CC_MD5(\"abc\")", d, exp, 16, &ok);
    }
    // CC_SHA1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d (FIPS-180)
    {
        unsigned char d[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1("abc", 3, d);
        const unsigned char exp[20] = {0xa9,0x99,0x3e,0x36,0x47,0x06,0x81,0x6a,
                                       0xba,0x3e,0x25,0x71,0x78,0x50,0xc2,0x6c,
                                       0x9c,0xd0,0xd8,0x9d};
        checkDigest("CC_SHA1(\"abc\")", d, exp, 20, &ok);
    }

    // --- 2. WPA PMK: WPA.m reference vectors -------------------------------
    // These exercise hmac_md5 / hmac_sha1 / F / PRF / wpaPasswordHash, all now
    // CommonCrypto-backed. The function self-checks every IEEE 802.11i vector.
    {
        BOOL pass = wpaTestPasswordHash();
        ok = ok && pass;
        DBNSLog(@"[CRYPTO-SELFTEST] %s wpaTestPasswordHash() "
                @"(IEEE 802.11i PMK + HMAC-MD5 + PRF vectors) result=%@ expected=YES",
                pass ? "PASS" : "FAIL", pass ? @"YES" : @"NO");
    }

    // --- 3. WPA PMK: migrated CommonCrypto PBKDF2 path ---------------------
    // SSID "IEEE", passphrase "password" -> known 256-bit PMK (IEEE 802.11i
    // test vector). Assert BOTH the reference wpaPasswordHash() and the
    // migrated fastWP_passwordHash() (used by the live crack loop) produce it.
    {
        const unsigned char expPMK[32] = {
            0xf4,0x2c,0x6f,0xc5,0x2d,0xf0,0xeb,0xef,0x9e,0xbb,0x4b,0x90,0xb3,0x8a,0x5f,0x90,
            0x2e,0x83,0xfe,0x1b,0x13,0x5a,0x70,0xe2,0x3a,0xed,0x76,0x2e,0x97,0x10,0xa1,0x2e};

        unsigned char refPMK[40] = {0};
        wpaPasswordHash("password", (const unsigned char *)"IEEE", 4, refPMK);
        checkDigest("WPA PMK reference  (SSID=IEEE pass=password)",
                    refPMK, expPMK, 32, &ok);

        unsigned char fastPMK[40] = {0};
        fastWP_passwordHash("password", (const unsigned char *)"IEEE", 4, fastPMK);
        checkDigest("WPA PMK CCPBKDF2   (SSID=IEEE pass=password)",
                    fastPMK, expPMK, 32, &ok);

        // The crack loop depends on these two paths agreeing exactly.
        BOOL agree = (memcmp(refPMK, fastPMK, 32) == 0);
        ok = ok && agree;
        DBNSLog(@"[CRYPTO-SELFTEST] %s WPA PMK reference == CCPBKDF2 path "
                @"result=%@ expected=YES", agree ? "PASS" : "FAIL",
                agree ? @"YES" : @"NO");
    }

    // --- 4. LEAP: NtPasswordHash (MD4) + DES round-trip --------------------
    // NtPasswordHash("password") = MD4(UTF-16LE "password")
    //                            = 8846f7eaee8fb117ad06bdd830b7586c (NTLM hash)
    {
        unsigned char hash[MD4_DIGEST_LENGTH];
        char pw[] = "password";
        NtPasswordHash(pw, (NSInteger)strlen(pw), hash);
        const unsigned char expNT[16] = {0x88,0x46,0xf7,0xea,0xee,0x8f,0xb1,0x17,
                                          0xad,0x06,0xbd,0xd8,0x30,0xb7,0x58,0x6c};
        checkDigest("LEAP NtPasswordHash(\"password\")", hash, expNT, 16, &ok);

        // Build a deterministic LEAP challenge/response from that NT hash exactly
        // the way the attack expects: zpwhash = NThash padded to 21 bytes (three
        // 7-byte DES keys); response = DES_k1(C) || DES_k2(C) || DES_k3(C).
        unsigned char zpw[21];
        memset(zpw, 0, sizeof(zpw));
        memcpy(zpw, hash, 16);                 // last 5 bytes are zero pad

        const unsigned char challenge[8] =
            {0x10,0x32,0x54,0x76,0x98,0xba,0xdc,0xfe};
        unsigned char response[24];
        DesEncrypt(challenge, &zpw[0],  &response[0]);
        DesEncrypt(challenge, &zpw[7],  &response[8]);
        DesEncrypt(challenge, &zpw[14], &response[16]);

        // gethashlast2 should brute-force the last two hash bytes from the third
        // DES block; they must match the real NT hash bytes [14],[15].
        unsigned char endofhash[2] = {0, 0};
        BOOL g2 = (gethashlast2(challenge, response, endofhash) == 0) &&
                  (endofhash[0] == hash[14]) && (endofhash[1] == hash[15]);
        ok = ok && g2;
        DBNSLog(@"[CRYPTO-SELFTEST] %s LEAP gethashlast2 recovered=%@ expected=%@",
                g2 ? "PASS" : "FAIL",
                hexstr(endofhash, 2), hexstr(&hash[14], 2));

        // testChallenge with the correct zpwhash must accept (return 0).
        BOOL tc = (testChallenge(challenge, response, zpw) == 0);
        ok = ok && tc;
        DBNSLog(@"[CRYPTO-SELFTEST] %s LEAP testChallenge (DES round-trip) "
                @"result=%@ expected=accept", tc ? "PASS" : "FAIL",
                tc ? @"accept" : @"reject");
    }

    DBNSLog(@"[CRYPTO-SELFTEST] %@  (CommonCrypto migration: MD4/MD5/SHA1 + "
            @"PBKDF2 WPA PMK; DES kept for LEAP) [CPU-only, no radio]",
            ok ? @"ALL PASS" : @"FAILURES PRESENT");
    return ok;
}

@end
