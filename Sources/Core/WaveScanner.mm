/*
 
 File:			WaveScanner.mm
 Program:		KisMAC
 Author:		Michael Ro�berg
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

#import "WaveScanner.h"
#import "ScanController.h"
#import "ScanControllerScriptable.h"
#import "WaveHelper.h"
#import "../Capabilities/KMCapability.h"   // S4.2: feature keys for op-site gate
#import "WaveNet.h"                          // S4.2: -BSSID for scope membership
#import "WaveClient.h"                        // S4.2: -ID (client MAC) for scope
#import "WaveDriver.h"
#import "KisMACNotifications.h"
#import "80211b.h"
#import "KisMAC80211.h"
#include <unistd.h>
#include <stdlib.h>
#import "GrowlController.h"
#import "WaveContainer.h"
#import "WavePcapDump.h"
#import "WavePluginInjectionProbe.h"
#import "WavePluginDeauthentication.h"
#import "WavePluginInjecting.h"
#import "WavePluginAuthenticationFlood.h"
#import "WavePluginBeaconFlood.h"

@implementation WaveScanner

- (id)init
{
    self = [super init];
    if (!self) return nil;
    
    _scanning = NO;
    _driver = 0;
    
    srandom(55445);	//does not have to be to really random
    
    _scanInterval = 0.25;
    _graphLength = 0;
    _soundBusy = NO;
    
    return self;
}

#pragma mark -

- (WaveDriver*) getInjectionDriver
{
    NSUInteger i;
    NSArray *a;
    WaveDriver *w = nil;
    
    a = [WaveHelper getWaveDrivers];
    for (i = 0; i < [a count]; ++i) {
        w = a[i];
        if ([w allowsInjection]) break;
    }
    
    if (![w allowsInjection])
    {
        NSRunAlertPanel(NSLocalizedString(@"Invalid Injection Option.", "No injection driver title"),
                        NSLocalizedString(@"Invalid Injection Option description", "LONG description of the error"),
                        //@"None of the drivers selected are able to send raw frames. Currently only PrismII based device are able to perform this task."
                        OK, nil, nil);
        
        return nil;
    }
    
    return w;
}
#define mToS(m) [NSString stringWithFormat:@"%.2X:%.2X:%.2X:%.2X:%.2X", m[0], m[1], m[2], m[3], m[4], m[5]]

#pragma mark -
-(void)performScan:(NSTimer*)timer
{
    [_container scanUpdate:_graphLength];
    
    if(_graphLength < MAX_YIELD_SIZE)
    {
        ++_graphLength;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        
        [aController updateNetworkTable:self complete:YES];
    });
    
    [_container ackChanges];
}


//does the active scanning (extra thread)
- (void)doActiveScan:(WaveDriver*)wd
{
    if ([wd startedScanning])
    {
        while (_scanning)
        {
            NSArray *nets = [wd networksInRange];
            
            if (nets)
            {
                for (CWNetwork *network in nets)
                {
                    [_container addAppleAPIData:network];
                }
            }
        }
    }
}

//does the actual scanning (extra thread)
- (void)doPassiveScan:(WaveDriver*)wd
{
    WavePacket *w = nil;
    KFrame* frame = NULL;
    
    NSInteger dumpFilter;
    
    NSSound* geiger;
    
    BOOL error = FALSE;
    
    NSDictionary *d;
    
    WavePcapDump *_wavePcapDumper = nil;
    WavePluginPacketResponse response;
    
    d = [wd configuration];
    dumpFilter = [d[@"dumpFilter"] integerValue];
    
    // Initialize WavePlugins
    _wavePlugins = [[NSMutableDictionary alloc] init];
    
    [_wavePlugins setValue:[[WavePluginInjectionProbe alloc] initWithDriver:wd]
                    forKey:@"InjectionProbe"];
    
    [_wavePlugins setValue:[[WavePluginDeauthentication alloc] initWithDriver:wd andContainer:_container]
                    forKey:@"Deauthentication"];
    
    [_wavePlugins setValue:[[WavePluginInjecting alloc] initWithDriver:wd]
                    forKey:@"Injecting"];
    
    [_wavePlugins setValue:[[WavePluginAuthenticationFlood alloc] initWithDriver:wd]
                    forKey:@"AuthenticationFlood"];
    
    [_wavePlugins setValue:[[WavePluginBeaconFlood alloc] initWithDriver:wd]
                    forKey:@"BeaconFlood"];

    // S0.4: WavePluginMidi (i386/Carbon QuickTime Music signal-strength sonification)
    // removed as dead code -- it was a no-op on x86_64/arm64. No replacement.

    //tries to open the dump file
    if (dumpFilter)
    {
        _wavePcapDumper = [[WavePcapDump alloc] initWithDriver:wd andDumpFilter:dumpFilter];
        if (_wavePcapDumper == nil)
        {
            error = TRUE;
        }
        else
        {
            [_wavePlugins setValue:_wavePcapDumper  forKey:@"PacketDump"];
        }
    }
    
    if(!error)
    {
        w = [[WavePacket alloc] init];
        
        if (_geigerSound!=nil)
        {
            geiger=[NSSound soundNamed:_geigerSound];
            if (geiger!=nil)
            {
                [geiger setDelegate:self];
            }
        }
        else geiger=nil;
        
        if (![wd startedScanning])
        {
            error = TRUE;
        }
        
        while (_scanning && !error) //this is for canceling
        {
            @try
            {
                @autoreleasepool
                {
                    frame = [wd nextFrame];     // captures the next frame (locking)
                    if (frame == NULL)          // NULL Pointer?
                        break;
                    
                    if ([w parseFrame:frame] != NO) //parse packet (no if unknown type)
                    {
                        // Send packet to ALL plugins
                        NSEnumerator *plugins = [_wavePlugins objectEnumerator];
                        response = WavePluginPacketResponseContinue;
                        WavePlugin *_wavePlugin = nil;
                        while ((_wavePlugin = [plugins nextObject]) && (response & WavePluginPacketResponseContinue)) {
                            response = [_wavePlugin gotPacket:w fromDriver:wd];
                            // Checks if packet should be forwarded to other plugins
                            
                        }
                        if (!(response & WavePluginPacketResponseContinue))
                            continue;
                        
                        if ([w SSID] == nil || ![w isCorrectSSID] ) {
                            continue;
                        }
                        
                        if ([_container addPacket:w liveCapture:YES] == NO)			// the packet shall be dropped
                        {
                            continue;
                        }
                        
                        if ((geiger!=nil) && ((_packets % _geigerInt)==0))
                        {
                            if (_soundBusy)
                            {
                                _geigerInt+=10;
                            }
                            else
                            {
                                _soundBusy=YES;
                                [geiger play];
                            }
                        }
                        
                        ++_packets;
                        
                        _bytes+=[w length];
                    }//end parse frame
                    else
                    {
                        if (_wavePcapDumper)
                        {
                            [_wavePcapDumper gotPacket:w fromDriver:wd];
                        }
                        DBNSLog(@"WaveScanner: Unknown packet type in parseFrame");
                    }
                }
            }
            @finally
            {
            }
        }
        
    }   // no error
    
    _wavePlugins = nil;
    _wavePcapDumper = nil;
    
}

- (void)doScan:(WaveDriver*)w
{
    @autoreleasepool {
        
        if ([w type] == passiveDriver) //for PseudoJack this is done by the timer
        {
            [self doPassiveScan:w];
        }
        else if ([w type] == activeDriver)
        {
            [self doActiveScan:w];
        }
        
        [w stopCapture];
        [self stopScanning]; //just to make sure the user can start the thread if it crashed
    }
}

- (BOOL)startScanning
{
    if (!_scanning) //we are already scanning
    {
        _scanning = YES;
        _drivers = [WaveHelper getWaveDrivers];

        WaveDriver *w;
        for (NSUInteger i = 0; i < [_drivers count]; ++i)
        {
            w = _drivers[i];
            if ([w type] == passiveDriver)
            { //for PseudoJack this is done by the timer
                [w startCapture:0];
            }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self doScan:w];
            });
        }
        
        _scanTimer = [NSTimer scheduledTimerWithTimeInterval:_scanInterval
                                                      target:self
                                                    selector:@selector(performScan:)
                                                    userInfo:nil
                                                     repeats:YES];
        if (_hopTimer == nil)
        {
            _hopTimer=[NSTimer scheduledTimerWithTimeInterval:aFreq
                                                       target:self
                                                     selector:@selector(doChannelHop:)
                                                     userInfo:nil
                                                      repeats:YES];
        }
    }
    
    return YES;
}

- (BOOL)stopScanning
{
    if (_scanning)
    {
        [GrowlController notifyGrowlStopScan];
        _scanning = NO;
        [_scanTimer invalidate];
        _scanTimer = nil;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:KisMACStopScanForced object:self];
        
        if (_hopTimer!=nil)
        {
            [_hopTimer invalidate];
            _hopTimer=nil;
        }
        
    }
    
    return YES;
}

- (BOOL)sleepDrivers: (BOOL)isSleepy
{
    WaveDriver *w;
    NSUInteger i;
    
    _drivers = [WaveHelper getWaveDrivers];
    
    if (isSleepy)
    {
        DBNSLog(@"Going to sleep...");
        _shouldResumeScan = _scanning;
        [aController stopScan];
        for (i = 0; i < [_drivers count]; ++i)
        {
            w = _drivers[i];
            [w sleepDriver];
        }
    }
    else
    {
        DBNSLog(@"Waking up...");
        for (i = 0; i < [_drivers count]; ++i)
        {
            w = _drivers[i];
            [w wakeDriver];
        }
        if (_shouldResumeScan)
        {
            [aController startScan];
        }
    }
    
    return YES;
}

- (void)doChannelHop:(NSTimer*)timer
{
    for (NSUInteger i = 0; i < [_drivers count]; ++i)
    {
        [_drivers[i] hopToNextChannel];
    }
}

- (void)setFrequency:(double)newFreq
{
    aFreq=newFreq;
    
    if (_hopTimer!=nil)
    {
        [_hopTimer invalidate];
        _hopTimer = [NSTimer scheduledTimerWithTimeInterval:aFreq
                                                     target:self
                                                   selector:@selector(doChannelHop:)
                                                   userInfo:nil
                                                    repeats:YES];
    }
    
}
-(void)setGeigerInterval:(NSInteger)newGeigerInt sound:(NSString*)newSound
{
    _geigerSound = nil;
    
    if ((newSound == nil)||(newGeigerInt == 0))
    {
        return;
    }
    
    _geigerSound=newSound;
    _geigerInt=newGeigerInt;
}

#pragma mark -

- (NSTimeInterval)scanInterval
{
    return _scanInterval;
}

- (NSInteger)graphLength
{
    return _graphLength;
}

//reads in a pcap file
- (void)readPCAPDump:(NSString*) dumpFile
{
    char err[PCAP_ERRBUF_SIZE];
    WavePacket *w;
    KFrame* frame = NULL;
    BOOL corrupted;
    
#ifdef DUMP_DUMPS
    pcap_dumper_t* f = NULL;
    pcap_t* p = NULL;
    NSString *aPath;
    
    if (aDumpLevel)
    {
        //in the example dump are informations like 802.11 network
        aPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingString:@"/example.dump"];
        p = pcap_open_offline([aPath UTF8String], err);
        if (p == NULL)
        {
            return;
        }
        //opens output
        aPath = [[NSDate date] descriptionWithCalendarFormat:[aDumpFile stringByExpandingTildeInPath]
                                                    timeZone:nil locale:nil];
        f = pcap_dump_open(p, [aPath UTF8String]);
        if (f == NULL)
        {
            return;
        }
    }
#endif
    
    _pcapP = pcap_open_offline([dumpFile UTF8String], err);
    if (_pcapP == NULL)
    {
        DBNSLog(@"Could not open dump file: %@. Reason: %s", dumpFile, err);
        
        return;
    }
    
    memset(aFrameBuf, 0, sizeof(aFrameBuf));
    aWF = (KFrame*)aFrameBuf;
    
    w = [[WavePacket alloc] init];
    
    BOOL process = YES;
    while (process)
    {
        frame = [self nextFrame:&corrupted];
        if (frame == NULL)
        {
            if (corrupted)
            {
                continue;
            }
            else
            {
                process = NO;
            }
        }
        
        if ([w parseFrame:frame] != NO)
        {
            
            if ([_container addPacket:w liveCapture:NO] == NO)
            {
                continue; // the packet shall be dropped
            }
            
#ifdef DUMP_DUMPS
            if ((aDumpLevel==1) ||
                ((aDumpLevel==2)&&([w type]==IEEE80211_TYPE_DATA)) ||
                ((aDumpLevel==3)&&([w isResolved]!=-1)))
            {
                [w dump:f]; //dump if needed
            }
#endif
        }
    }//while
    
#ifdef DUMP_DUMPS
    if (f)
    {
        pcap_dump_close(f);
    }
    if (p)
    {
        pcap_close(p);
    }
#endif
    
    pcap_close(_pcapP);
}

//returns the next frame in a pcap file
- (KFrame*)nextFrame:(BOOL *)corrupted
{
    struct pcap_pkthdr h;
    NSInteger offset = 0;
    
    *corrupted = NO;
    
    UInt8 *b = (UInt8*)pcap_next(_pcapP, &h);	//get frame from current pcap file
    
    if (b == NULL)
    {
        return NULL;
    }
    *corrupted = YES;
    
    aWF->ctrl.channel = 0;
    aWF->ctrl.len = h.caplen;
    
    //corrupted frame
    if ( h.caplen > MAX_FRAME_BYTES )
    {
        return NULL;
    }
    
    switch (pcap_datalink(_pcapP))
    {
        case DLT_IEEE802_11:
            offset = 0;
            break;
            
        case DLT_PRISM_HEADER:
            offset = sizeof(prism_header);
            break;
            
        case DLT_IEEE802_11_RADIO:
            offset = ((ieee80211_radiotap_header*)b)->it_len;
            break;
            
        default:
            DBNSLog(@"Unsupported Datalink Type: %u.", pcap_datalink(_pcapP));
            pcap_close(_pcapP);
            return NULL;
            break;
    }
    
    memcpy(aWF->data, b+offset, h.caplen);
    return aWF;
}

#pragma mark -

- (void) setDeauthingAll:(BOOL)deauthing
{
    WavePluginDeauthentication *wavePlugin;
    wavePlugin = [_wavePlugins valueForKey:@"Deauthentication"];
    if (wavePlugin == nil)
        return;
    // S4.2 op-site gate (defense in depth): deauth-ALL is a BROADCAST offensive
    // op with no single target, so it cannot be constrained to one scoped BSSID.
    // It fails closed: -allowActiveOperation: with a nil target requires (and
    // never gets) per-target scope membership, so a blanket deauth-all is
    // refused + audited unless a future slice adds explicit broadcast
    // authorization. Turning the feature OFF is always permitted.
    if (deauthing)
    {
        if (![aController allowActiveOperation:@"deauth-all (broadcast)"
                                       feature:KMFeatureDeauth
                                        target:nil
                                targetIsClient:NO])
        {
            return;   // refused + audited inside allowActiveOperation:
        }
    }
    [wavePlugin setDeauthingAll:deauthing];
    return;
}

- (BOOL) beaconFlood
{
    WavePluginBeaconFlood *wavePlugin;
    BOOL ret;
    wavePlugin = [_wavePlugins valueForKey:@"BeaconFlood"];
    if (wavePlugin == nil)
        return NO;
    ret = [wavePlugin startTest];
    return ret;
}

- (BOOL) deauthenticateNetwork:(WaveNet*)net atInterval:(NSInteger)interval
{
    WavePluginDeauthentication *wavePlugin;
    BOOL ret;
    wavePlugin = [_wavePlugins valueForKey:@"Deauthentication"];
    if (wavePlugin == nil)
        return NO;
    // S4.2 op-site gate (defense in depth): targeted deauth requires an
    // injection-capable adapter + authorized in-window scope, and the target
    // AP's BSSID must be in scope. Fail closed (refused + audited otherwise).
    if (![aController allowActiveOperation:@"deauth-network"
                                   feature:KMFeatureDeauth
                                    target:[net BSSID]
                            targetIsClient:NO])
    {
        return NO;
    }
    ret = [wavePlugin startTest:net atInterval:interval];
    return ret;
}

- (NSString*) tryToInject:(WaveNet*)net
{
    BOOL ret;
    WavePluginInjecting *wavePlugin;
    
    wavePlugin = [_wavePlugins valueForKey:@"Injecting"];
    if (wavePlugin == nil)
    {
        return nil;
    }

    // S4.2 op-site gate (defense in depth): frame (re)injection requires an
    // injection-capable adapter + authorized in-window scope, and the target
    // AP's BSSID must be in scope. Fail closed (refused + audited otherwise).
    if (![aController allowActiveOperation:@"inject-packets"
                                   feature:KMFeatureFrameInjection
                                    target:[net BSSID]
                            targetIsClient:NO])
    {
        return nil;
    }

    ret = [wavePlugin startTest:net];
    if (ret == NO)
    {
        return nil;
    } else {
        return @"";
    }
    
    return nil;
}

- (BOOL)injectionTest: (WaveNet *)net withClient:(WaveClient *)client
{
    WavePluginInjectionProbe *wavePlugin;
    wavePlugin = [_wavePlugins valueForKey:@"InjectionProbe"];
    if (wavePlugin == nil)
    {
        return NO;
    }
    // S4.2 op-site gate (defense in depth): the injection test transmits frames,
    // so it requires an injection-capable adapter + authorized in-window scope.
    // When a specific client is targeted, that client MAC must be in scope;
    // otherwise the AP BSSID must be in scope. Fail closed (refused + audited).
    BOOL ok;
    if (client != nil)
    {
        ok = [aController allowActiveOperation:@"injection-test (client)"
                                       feature:KMFeatureFrameInjection
                                        target:[client ID]
                                targetIsClient:YES];
    }
    else
    {
        ok = [aController allowActiveOperation:@"injection-test (AP)"
                                       feature:KMFeatureFrameInjection
                                        target:[net BSSID]
                                targetIsClient:NO];
    }
    if (!ok)
    {
        return NO;
    }
    [wavePlugin startTest:net withClient:client];

    return YES;
}

- (BOOL)authFloodNetwork:(WaveNet*)net
{
    WavePluginAuthenticationFlood *wavePlugin;
    
    wavePlugin = [_wavePlugins valueForKey:@"AuthenticationFlood"];
    if (wavePlugin == nil)
    {
        return NO;
    }
    
    return [wavePlugin startTest:net];
}

- (BOOL) stopSendingFrames
{
    WaveDriver *w;
    NSArray *a;
    NSUInteger i;
    id test;
    
    // Stop all tests
    NSEnumerator *tests = [_wavePlugins objectEnumerator];
    while ((test = [tests nextObject]))
    {
        [test stopTest];
    }
    
    // Stop all drivers
    a = [WaveHelper getWaveDrivers];
    for (i = 0; i < [a count]; ++i)
    {
        w = a[i];
        if ([w allowsInjection]) [w stopSendingFrames];
    }
    
    return YES;
}

#pragma mark -

- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)aBool
{
    _soundBusy = NO;
}

- (void)dealloc
{
    [self stopSendingFrames];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    _scanning = NO;
}

@end
