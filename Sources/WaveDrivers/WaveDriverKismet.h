/*
 
 File:			WaveDriverKismet.h
 Program:		KisMAC
 Author:		Geordie Millar
                themacuser@gmail.com
 Changes:       Vitalii Parovishnyk(1012-2015)
 
 Description:	Scan with a Kismet server in KisMac.
 
 Details:		Tested with Kismet 2006.04.R1 on OpenWRT White Russian RC6 on a Diamond Digital R100
                (broadcom mini-PCI card, wrt54g capturesource)
                and Kismet 2006.04.R1 on Voyage Linux on a PC Engines WRAP.2E
                (CM9 mini-PCI card, madwifing)
 
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

#import <Foundation/Foundation.h>
#import "WaveDriver.h"

@class KMKismetTransport;

// S2.4: the legacy raw BSD-socket members (sockd/serv_name/hostent/inet_addr)
// were replaced by a Network.framework transport (KMKismetTransport). The
// transport is plaintext TCP by design -- legacy Kismet's *NETWORK: line
// protocol (~2006) is plaintext. See KMKismetTransport.h.
@interface WaveDriverKismet : WaveDriver {
	KMKismetTransport *_transport;
	NSInteger port;
	NSString *hostname;
}

+ (NSInteger) kismetInstanceCount;
@end
