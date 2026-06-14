/*
 
 File:			WPACrackExtension.m
 Program:		KisMAC
 Author:		Michael Roßberg
                mick@binaervarianz.de
 Changes:       Vitalii Parovishnyk(1012-2015)
 
 Description:	KisMAC is a wireless stumbler for MacOS X.
 
 This file is part of KisMAC.
 
 Most parts of this file are based on aircrack by Christophe Devine.
 
 KisMAC is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License, version 2,
 as published by the Free Software Foundation;
 
 KisMAC is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with KisMAC; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import "WaveNetWPACrack.h"
#import "WaveHelper.h"
#import "WaveClient.h"
#import "WPA.h"
#import "ImportController.h"
#import "80211b.h"
// S2.3: migrated the WPA PMK derivation from a hand-rolled PolarSSL
// (sha1_context/sha1_process) HMAC-SHA1 unrolling to Apple CommonCrypto's
// CCKeyDerivationPBKDF (kCCPBKDF2 / kCCPRFHmacAlgSHA1). This produces the
// identical 256-bit WPA PMK (PBKDF2-HMAC-SHA1, 4096 iterations, SSID as salt)
// and removes BOTH the PolarSSL dependency and the strict-aliasing UB that the
// old fastF() inner loop committed by XOR-ing the 20-byte SHA1 digest through
// (NSInteger*) casts.
#import <CommonCrypto/CommonCrypto.h>

struct clientData {
    UInt8 ptkInput[WPA_NONCE_LENGTH+WPA_NONCE_LENGTH+12];
    const UInt8 *mic;
    const UInt8 *data;
    UInt32 dataLen;
    __unsafe_unretained NSString *clientID;
    NSInteger wpaKeyCipher;
};

#pragma mark -
#pragma mark WPA password -> PMK mapping (CommonCrypto PBKDF2)
#pragma mark -

// Derive the 256-bit WPA/WPA2 PMK from a candidate passphrase.
//
// WPA-PSK defines PMK = PBKDF2(HMAC-SHA1, passphrase, SSID, 4096, 256 bits).
// Apple's CCKeyDerivationPBKDF computes exactly that, so it is bit-for-bit
// identical to the previous hand-rolled fastF()/fastWP_passwordHash() pair --
// without the strict-aliasing UB and without PolarSSL. `output` must be >= 32
// bytes (callers pass UInt8[40]).
void fastWP_passwordHash(char *password, const unsigned char *ssid, NSInteger ssidlength, unsigned char output[40])
{
    CCKeyDerivationPBKDF(kCCPBKDF2,
                         password, strlen(password),
                         ssid, (size_t)ssidlength,
                         kCCPRFHmacAlgSHA1, 4096,
                         output, 32);
}

#pragma mark -

@implementation WaveNet(WPACrackExtension)

- (BOOL)crackWPAWithWordlist:(NSString*)wordlist andImportController:(ImportController*)im
{
    char wrd[100];
    const char *ssid = 0;
    FILE* fptr = NULL;
    NSUInteger i, j, words, ssidLength, keys, curKey;
    // digest must hold a full SHA-1 result: fast_hmac_sha1() writes 20 bytes
    // (CC_SHA1_DIGEST_LENGTH). The MIC comparison below only reads the first 16,
    // and fast_hmac_md5() writes 16, but the buffer must be sized for the larger
    // SHA-1 case to avoid a 4-byte stack overflow.
    UInt8 pmk[40], ptk[64], digest[20];
    struct clientData *c;
    WaveClient *wc;
    const UInt8 *anonce, *snonce;
    UInt8 prefix[] = "Pairwise key expansion";

    fptr = fopen([wordlist UTF8String], "r");
    if (!fptr)
	{
		return NO;
	}
    
    keys = 0;
    for (i = 0; i < [aClientKeys count]; ++i)
	{
        if ([aClients[aClientKeys[i]] eapolDataAvailable])
            ++keys;
    }

    NSAssert(keys!=0, @"There must be more keys");
    
    curKey = 0;
    c = malloc(keys * sizeof(struct clientData));
    
    for (i = 0; i < [aClientKeys count]; ++i)
	{
        wc = aClients[aClientKeys[i]];
        if ([wc eapolDataAvailable])
		{
            if ([[wc ID] isEqualToString: _BSSID])
			{
                keys--;
            }
			else
			{
                if (memcmp(_rawBSSID, [[wc rawID] bytes], 6) > 0)
				{
                    memcpy(&c[curKey].ptkInput[0], [[wc rawID] bytes] , 6);
                    memcpy(&c[curKey].ptkInput[6], _rawBSSID, 6);
                }
				else
				{
                    memcpy(&c[curKey].ptkInput[0], _rawBSSID, 6);
                    memcpy(&c[curKey].ptkInput[6], [[wc rawID] bytes] , 6);
                }
                
                anonce = [[wc aNonce] bytes]; 
                snonce = [[wc sNonce] bytes];
                
				if (memcmp(anonce, snonce, WPA_NONCE_LENGTH) > 0)
				{
                    memcpy(&c[curKey].ptkInput[12],                     snonce, WPA_NONCE_LENGTH);
                    memcpy(&c[curKey].ptkInput[12 + WPA_NONCE_LENGTH],  anonce, WPA_NONCE_LENGTH);
                }
				else
				{
                    memcpy(&c[curKey].ptkInput[12],                     anonce, WPA_NONCE_LENGTH);
                    memcpy(&c[curKey].ptkInput[12 + WPA_NONCE_LENGTH],  snonce, WPA_NONCE_LENGTH);
                }

                c[curKey].data          = [[wc eapolPacket] bytes];
                c[curKey].dataLen       = (UInt32)[[wc eapolPacket] length];
                c[curKey].mic           = [[wc eapolMIC]    bytes];
                c[curKey].clientID      = [wc ID];
                c[curKey].wpaKeyCipher  = [wc wpaKeyCipher];
                ++curKey;
            }
        }
    }

    words = 0;
    wrd[90] = 0;

    ssid = [_SSID UTF8String];
    ssidLength = [_SSID lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  
    CGFloat theTime, prevTime = clock() / (CGFloat)CLK_TCK;
	
    while(![im canceled] && !feof(fptr))
    {
        //get the line from the file. S2.3: check the return value -- on EOF or
        //read error fgets() returns NULL and leaves wrd untouched, so the old
        //code would re-test a stale line. Also note wrd is char[100] but we
        //only ever request 90 bytes, so it is always NUL-terminated in range.
        if (fgets(wrd, 90, fptr) == NULL) break;

        //get the length.  no need to account for linefeed because it will
        //be done below.  Remember indexed from 0.
        //S2.3 bounds fix: strlen() can be 0 for a bare "\n"/empty read; with
        //NSUInteger i, "strlen(wrd) - 1" would wrap to SIZE_MAX and the
        //wrd[i] reads below would be a wild out-of-bounds access. Guard first.
        size_t wrdLen = strlen(wrd);
        if (wrdLen == 0) continue;
        i = wrdLen - 1;

        //passwords must be shorter than 63 signs
        if (i < 8 || i > 63) continue;

        //remove the linefeed by setting the last char to null
        //if we still have line feed chars, keep going. The (i != 0) guard keeps
        //the index from underflowing on an all-newline line.
        while(('\r' == wrd[i] || '\n' == wrd[i]) && i != 0)
        {
            wrd[i--] = 0;
        }
        if ('\r' == wrd[i] || '\n' == wrd[i]) wrd[i] = 0;

        //switch i back to length instead of an index into the array
        //this is kinda dumb
        i = strlen(wrd);
        
        ++words;

        if (words % 500 == 0)
        {
            theTime =clock() / (CGFloat)CLK_TCK;
            [im setStatusField:[NSString stringWithFormat:@"%@ words tested    %.2f/second", @(words), 500.0 / (theTime - prevTime)]];
            prevTime = theTime;
        }
        
        for(j = 0; j < i; ++j)
		{
            if ((wrd[j] < 32) || (wrd[j] > 126))
			{
				break;
			}
		}
		
        if ( j!=i ) continue;
        
        fastWP_passwordHash(wrd, (const UInt8*)ssid, ssidLength, pmk);
    
        for (curKey = 0; curKey < keys; ++curKey)
		{
            PRF(pmk, 32, prefix, strlen((char *)prefix), c[curKey].ptkInput, WPA_NONCE_LENGTH*2 + 12, ptk, 16);
            
            if (c[curKey].wpaKeyCipher == 1)
			{
                fast_hmac_md5(c[curKey].data, c[curKey].dataLen, ptk, 16, digest);
			}
            else
			{
                fast_hmac_sha1((unsigned char*)c[curKey].data, c[curKey].dataLen, ptk, 16, digest);
            }
			
            if (memcmp(digest, c[curKey].mic, 16) == 0)
			{
                _password = [NSString stringWithFormat:@"%s for Client %@", wrd, c[curKey].clientID];
                fclose(fptr);
                
				DBNSLog(@"Cracking was successful. Password is <%s> for Client %@", wrd, c[curKey].clientID);
                free(c);
                
				return YES;
            }
        }
    }
    
    free(c);
    fclose(fptr);
    
    _crackErrorString = NSLocalizedString(@"The key was none of the tested passwords.", @"Error description for WPA crack.");
	
    return NO;
}

- (void)performWordlistWPA:(NSString*)wordlist
{
    @autoreleasepool {
        BOOL successful = NO;
	
		NSParameterAssert((_isWep == encryptionTypeWPA) || (_isWep == encryptionTypeWPA2));
        NSParameterAssert(_SSID);
		NSParameterAssert([_SSID length] <= 32);
		NSParameterAssert([self capturedEAPOLKeys] > 0);
		NSParameterAssert(_password == nil);
		NSParameterAssert(wordlist);

        if ([self crackWPAWithWordlist:[wordlist stringByExpandingTildeInPath] andImportController:[WaveHelper importController]])
		{
			successful = YES;
		}
        
        [[WaveHelper importController] terminateWithCode: (successful) ? 1 : -1];
	}
}

@end
