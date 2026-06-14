/*
 
 File:			LEAPCrackExtension.m
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

#import "WaveNetLEAPCrack.h"
#import "LEAP.h"
#import "WaveClient.h"
#import "WaveHelper.h"
#import "ImportController.h"

struct leapClientData
{
    const UInt8 *response;
    const UInt8 *challenge;
    UInt8    hashend[2];
    __unsafe_unretained NSString *username;
    __unsafe_unretained NSString *clientID;
};

@implementation WaveNet(LEAPCrackExtension)

- (void)performWordlistLEAP:(NSString*)wordlist
{
    @autoreleasepool {
        BOOL successful = NO;
	
		NSParameterAssert(_isWep == encryptionTypeLEAP);
		NSParameterAssert([self capturedLEAPKeys] > 0);
		NSParameterAssert(_password == nil);
		NSParameterAssert(wordlist);
	
	
		if ([self crackLEAPWithWordlist:[wordlist stringByExpandingTildeInPath] andImportController:[WaveHelper importController]])
		{
			successful = YES;
		}
	
        [[WaveHelper importController] terminateWithCode: (successful) ? 1 : -1];
	}
}

- (BOOL)crackLEAPWithWordlist:(NSString*)wordlist andImportController:(ImportController*)im
{
    char wrd[100];
    FILE* fptr = NULL;
    NSUInteger i, words, curKey = 0;
	NSInteger keys = 0;
    struct leapClientData *c = NULL;
    WaveClient *wc = nil;
    UInt8 pwhash[MD4_DIGEST_LENGTH] = "";
    
    //open wordlist
    fptr = fopen([wordlist UTF8String], "r");
    if (!fptr)
	{
		return NO;
	}
    
    //initialize all the data structures
	NSUInteger aClientKeysCount = [aClientKeys count];
    for (i = 0; i < aClientKeysCount; ++i)
	{
        if ([aClients[aClientKeys[i]] leapDataAvailable])
		{
			++keys;
		}
    }
    
	if (keys > 0)
	{
		c = malloc(keys * sizeof(struct leapClientData));
	
		for (i = 0; i < aClientKeysCount; ++i)
		{
			wc = aClients[aClientKeys[i]];
			if ([wc leapDataAvailable])
			{
				if ([[wc ID] isEqualToString:_BSSID])
				{
					keys--;
				}
				else
				{
					c[curKey].username  = [wc leapUsername];
					c[curKey].challenge = [[wc leapChallenge] bytes];
					c[curKey].response  = [[wc leapResponse]  bytes];
					c[curKey].clientID  = [wc ID];
					
					//prepare our attack
					if (gethashlast2(c[curKey].challenge, c[curKey].response, c[curKey].hashend) == 0)
						++curKey;
					else 
						--keys;
				}
			}
		}
	}

    if (keys <= 0)
	{
		_crackErrorString = NSLocalizedString(@"The captured challenge response packets are not sufficient to perform this attack", @"Error description for LEAP crack.");
		if (c)
		{
			free(c);
		}
		
		return NO;
	}
    
    words = 0;
    wrd[90] = 0;

    while(![im canceled] && !feof(fptr))
	{
        //S2.3: check fgets() -- NULL on EOF/error leaves wrd stale. wrd is
        //char[100] and we request 90, so it is always NUL-terminated in range.
        if (fgets(wrd, 90, fptr) == NULL) break;

        //S2.3 bounds fix: an empty line / bare "\n" gives strlen()==0; with the
        //unsigned NSUInteger i, "strlen(wrd) - 1" wrapped to SIZE_MAX and the
        //"wrd[i] = 0" stores below were a wild out-of-bounds write. Guard, then
        //strip a trailing "\n" and optional preceding "\r" without underflow.
        //Afterwards `i` is the index of the last surviving char (downstream
        //uses i+1 as the password length, matching the original semantics).
        size_t wrdLen = strlen(wrd);
        if (wrdLen == 0) continue;
        i = wrdLen - 1;
        // Strip ONLY actual trailing CR/LF -- a newline-less line (the last line,
        // or a line >=89 chars split at the fgets(wrd,90,...) boundary) keeps all
        // its characters instead of losing the final one. The (i != 0) guard
        // prevents the index from underflowing on an all-newline line; the empty
        // line (wrdLen==0) was already skipped above.
        while ((wrd[i] == '\r' || wrd[i] == '\n') && i != 0)
        {
            wrd[i--] = 0;
        }
        if (wrd[i] == '\r' || wrd[i] == '\n') { wrd[i] = 0; continue; } // line was only CR/LF

        ++words;

        if (words % 100000 == 0)
		{
            [im setStatusField:[NSString stringWithFormat:@"%@ words tested", @(words)]];
        }

        if (i > 31)
		{
			continue; //dont support large passwords
		}
        
        NtPasswordHash(wrd, i+1, pwhash);

		if (c && pwhash)
		{
			for (curKey = 0; curKey < keys; ++curKey)
			{
				if (c[curKey].hashend[0] != pwhash[MD4_DIGEST_LENGTH-2] ||
                    c[curKey].hashend[1] != pwhash[MD4_DIGEST_LENGTH-1])
                {
                    continue;
                }
                if (testChallenge(c[curKey].challenge, c[curKey].response, pwhash))
                {
                    continue;
                }
				
				_password = [NSString stringWithFormat:@"%s for username %@", wrd, c[curKey].username];
				fclose(fptr);
				DBNSLog(@"Cracking was successful. Password is <%s> for username %@, client %@",
                        wrd, c[curKey].username, c[curKey].clientID);
				free(c);
                
				return YES;
			}
		}
    }
    
	if (c) {
		free(c);
	}
    
    fclose(fptr);
    
    _crackErrorString = NSLocalizedString(@"The key was none of the tested passwords.", @"Error description for WPA crack.");
	
    return NO;
}

@end
