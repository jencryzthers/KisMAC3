/*
 
 File:			ScanController.h
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

#import "ScanController.h"
#import "ScanControllerPrivate.h"
#import "ScanControllerScriptable.h"
#import "WaveScanner.h"
#import "WaveHelper.h"
#import "GPSController.h"
#import "WaveClient.h"
#import "WaveNet.h"
#import "../WindowControllers/CrashReportController.h"
#import "../Controller/TrafficController.h"
#import "WaveContainer.h"
#import "../WaveDrivers/WaveDriver.h"
#import "BridgeController.h"
#import "MapView.h"
#import <sys/sysctl.h>
#import <BIGeneric/BIGeneric.h>
#import <BIGL/BIGL.h>
#import "InfoController.h"
#import "ScanHierarch.h"
#import "ImportController.h"
#import "GrowlController.h"
#import "../Capabilities/KMHardwareProbe.h"
#import "../Capabilities/KMCapabilityEngine.h"
#import "../Capabilities/KMPcapImportSelfTest.h"
#import "../Capabilities/KMProtocolSelfTest.h"
#import "../Capabilities/KMCryptoSelfTest.h"
#import "../Capabilities/KMCapability.h"
#import "../WaveDrivers/WaveDriverAirport.h"
#import "../WaveDrivers/WaveDriverAirportExtreme.h"
#import "../WaveDrivers/WaveDriverKismet.h"
#import "../WaveDrivers/WaveDriverKismetDrone.h"
// NOTE: WaveDriverUSB.h pulls in C++ (USBJack) and cannot be imported into a
// plain .m. We detect USB injection drivers at runtime via NSClassFromString +
// -isKindOfClass: instead, so no C++ header is required here.
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOMessage.h>
#import "WavePluginMidi.h"

NSString *const KisMACViewItemChanged       = @"KisMACViewItemChanged";
NSString *const KisMACCrackDone             = @"KisMACCrackDone";
NSString *const KisMACAdvNetViewInvalid     = @"KisMACAdvNetViewInvalid";
NSString *const KisMACModalDone             = @"KisMACModalDone";
NSString *const KisMACFiltersChanged        = @"KisMACFiltersChanged";
NSString *const KisMACStopScanForced        = @"KisMACStopScanForced";
NSString *const KisMACNetworkAdded          = @"KisMACNetworkAdded";
NSString *const KisMACUserDefaultsChanged   = @"KisMACUserDefaultsChanged";
NSString *const KisMACTryToSave             = @"KisMACTryToSave";
NSString *const KisMACGPSStatusChanged      = @"KisMACGPSStatusChanged";
NSString *const KisMACLocationAuthorizationChanged = @"KisMACLocationAuthorizationChanged";

static io_connect_t  root_port;    // a reference to the Root Power Domain IOService

@implementation ScanController

+ (void)initialize
{
    NSDictionary *defaultDriverDict = @{@"driverID": @"WaveDriverAirport", @"deviceName": @"Airport Card"};
    
    NSDictionary *registrationDict = @{@"frequence":              @0.25,
                                       @"activeScanInterval":     @0.25,
                                       @"ScanAtStartUp":          @NO,
                                       @"dontAskToSave":          @NO,
                                       @"terminateIfClosed":      @YES,
                                       @"GeigerSensity":          @250,
                                       @"Voice":                  @0,
                                       @"CurrentPositionColor":   [WaveHelper colorToInt:[NSColor redColor]],
                                       @"TraceColor":             [WaveHelper colorToInt:[NSColor redColor]],
                                       @"WayPointColor":          [WaveHelper colorToInt:[NSColor blueColor]],
                                       @"NetAreaColorGood":       [WaveHelper colorToInt:[[NSColor greenColor] colorWithAlphaComponent:0.5]],
                                       @"NetAreaColorBad":        [WaveHelper colorToInt:[[NSColor redColor] colorWithAlphaComponent:0.5]],
                                       @"NetAreaQuality":         @5.0,
                                       @"NetAreaSensitivity":     @30,
                                       @"WEPSound":               @"None",
                                       @"noWEPSound":             @"None",
                                       @"GeigerSound":            @"None",
                                       @"playCrackSounds":        [NSNumber numberWithBool:TRUE],
                                       @"GPSDevice":              @"CoreLocation",
                                       @"GPSTrace":               @2,
                                       @"GPSNoFix":               @0,
                                       @"GPSTripmate":            @NO,
                                       @"DownloadMapScale":       @"3",
                                       @"DownloadMapServer":      @"<Select a Server>",
                                       @"DownloadMapWidth":       @1024,
                                       @"DownloadMapHeight":      @768,
                                       @"DownloadMapLatitude":    @0.0,
                                       @"DownloadMapHLongitude":  @0.0,
                                       @"DownloadMapNS":          @"N",
                                       @"DownloadMapEW":          @"E",
                                       @"TrafficViewShowSSID":    @1,
                                       @"TrafficViewShowBSSID":   @0,
                                       @"FilterBSSIDList":        @[],
                                       @"GPSDaemonPort":          @2947,
                                       @"GPSDaemonHost":          @"localhost",
                                       @"DebugMode":              @0,
                                       @"WaveNetAvgTime":         @2,
                                       @"ActiveDrivers":          @[defaultDriverDict],
                                       @"ac_ff":                  @2,
                                       @"bf_interval":            @0.1,
                                       @"pr_interval":            @100};
    
    NSDictionary  *networkTableFieldsVisibility = @{@"id":                  @YES,
                                                    @"channel":             @YES,
                                                    @"primaryChannel":      @NO,
                                                    @"ssid":                @YES,
                                                    @"bssid":               @YES,
                                                    @"wep":                 @YES,
                                                    @"type":                @YES,
                                                    @"signal":              @YES,
                                                    @"avgsignal":           @YES,
                                                    @"maxsignal":           @YES,
                                                    @"packets":             @YES,
                                                    @"data":                @YES,
                                                    @"lastseen":            @YES,
                                                    @"challengeResponse":   @YES
                                                    };
    NSArray *networkTableFieldsOrder = @[@"id", @"channel", @"ssid", @"bssid", @"wep", @"type", @"signal", @"avgsignal", @"maxsignal", @"packets", @"data", @"lastseen", @"challengeResponse"];
    NSDictionary *networkTableFields = @{@"networkTableFieldsVisibility": networkTableFieldsVisibility,
                                         @"networkTableFieldsOrder": networkTableFieldsOrder};
    [[NSUserDefaults standardUserDefaults] registerDefaults:registrationDict];
    [[NSUserDefaults standardUserDefaults] registerDefaults:networkTableFields];
}

- (id)init
{
    self = [super init];
    if (self == nil)
    {
        return nil;
    }
    
    aNetHierarchVisible = NO;
    _visibleTab = tabNetworks;
    [_window setDocumentEdited:NO];
    _refreshGUI = YES;
    _refreshGPS = YES;
    aMS = nil;
    _zoomToRect = NSZeroRect;
    _importOpen = 0;
    queue = [[NSOperationQueue alloc] init];
    mainQueue = [NSOperationQueue mainQueue];
    
    return self;
}

- (void)awakeFromNib
{
    NSUserDefaults *sets;
    
    [WaveHelper setScanController:self];
    [_headerField setStringValue: [NSString stringWithFormat:@"KisMac v%@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]]];
    
    [ScanHierarch setContainer:_container];
    [WaveHelper setMainWindow:_window];
    [WaveHelper setMapView:_mappingView];
    _visibleTab = tabInvalid;
    [self showNetworks];
    
    GBStorageController *gbStorage = [GBStorageController sharedControllerForNamespace:kGBStorageDefaultNamespace];
    
    if (![gbStorage objectForKeyedSubscript:@"menu-networks"])
    {
        NSImage *image = [NSImage imageNamed:@"menu-networks"];
        [gbStorage setObject:image forKeyedSubscript:@"menu-networks"];
    }
    if (![gbStorage objectForKeyedSubscript:@"menu-graph"])
    {
        NSImage *image = [NSImage imageNamed:@"menu-graph"];
        [gbStorage setObject:image forKeyedSubscript:@"menu-graph"];
    }
    if (![gbStorage objectForKeyedSubscript:@"menu-networks"])
    {
        NSImage *image = [NSImage imageNamed:@"menu-map"];
        [gbStorage setObject:image forKeyedSubscript:@"menu-map"];
    }
    if (![gbStorage objectForKeyedSubscript:@"menu-details"])
    {
        NSImage *image = [NSImage imageNamed:@"menu-details"];
        [gbStorage setObject:image forKeyedSubscript:@"menu-details"];
    }
    
    [_showNetworks setImage: [gbStorage objectForKeyedSubscript:@"menu-networks"]];
    [_showTraffic  setImage: [gbStorage objectForKeyedSubscript:@"menu-graph"]];
    [_showMap      setImage: [gbStorage objectForKeyedSubscript:@"menu-map"]];
    [_showDetails  setImage: [gbStorage objectForKeyedSubscript:@"menu-details"]];
    
    [_networkTable setDoubleAction:@selector(showDetails:)];
    
    // Custom table fields
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Network table columns"];
    id tableColumn = nil;
    NSMenuItem *menuItem = nil;
    NSMutableArray *colsToRemove = [[NSMutableArray alloc] init];
    
    NSDictionary *networkTableFieldsVisibility = [[NSUserDefaults standardUserDefaults] objectForKey:@"networkTableFieldsVisibility"];
    NSEnumerator *colsEnumerator = [[_networkTable tableColumns] objectEnumerator];
    
    NSInteger i = 0;
    while ((tableColumn = [colsEnumerator nextObject]))
    {
        menuItem = [menu insertItemWithTitle:[[tableColumn headerCell] title]
                                      action:@selector(selectedTableContextMenuItem:)
                               keyEquivalent:@""
                                     atIndex:i];
        [menuItem setRepresentedObject:tableColumn];
        
        if ([networkTableFieldsVisibility[[tableColumn identifier]] boolValue])
        {
            [menuItem setState:NSOnState];
        }
        else
        {
            [colsToRemove addObject:tableColumn];
            [menuItem setState:NSOffState];
        }
        
        [menuItem setTarget:self];
        ++i;
    }
    
    colsEnumerator = [colsToRemove objectEnumerator];
    while ((tableColumn = [colsEnumerator nextObject]))
    {
        [_networkTable removeTableColumn:tableColumn];
    }
    
    [[_networkTable headerView] setMenu:menu];
    
    //[_window makeFirstResponder:_networkTable]; //select the network table not the search box
    
    [self menuSetEnabled:NO menu:aNetworkMenu];
    [[_showNetInMap menu] setAutoenablesItems:NO];
    [_showNetInMap setEnabled:NO];
    [_trafficTimePopUp setHidden:YES];
    [_trafficModePopUp setHidden:YES];
    
    sets = [NSUserDefaults standardUserDefaults];
    
    if ([[sets objectForKey:@"DebugMode"] intValue] != 1) [[_debugMenu menu] removeItem:_debugMenu];
    
    [_window makeKeyAndOrderFront:self];
    
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    [defaultCenter addObserver:self
                      selector:@selector(updateViewItems:)
                          name:KisMACViewItemChanged
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(modalDone:)
                          name:KisMACCrackDone
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(advNetViewInvalid:)
                          name:KisMACAdvNetViewInvalid
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(modalDone:)
                          name:KisMACModalDone
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(stopScanForced:)
                          name:KisMACStopScanForced
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(networkAdded:)
                          name:KisMACNetworkAdded
                        object:nil];
    [defaultCenter addObserver:self
                      selector:@selector(updatePrefs:)
                          name:KisMACUserDefaultsChanged
                        object:nil];
    // S1.4: rebuild the capability engine whenever Location authorization
    // changes (added in S1.2) so the scan gate updates after a grant/deny.
    [defaultCenter addObserver:self
                      selector:@selector(locationAuthorizationChanged:)
                          name:KisMACLocationAuthorizationChanged
                        object:nil];
    // Build the engine once at startup, off the main thread, so the gate is
    // ready (and to prove the consult path at launch via DBNSLog).
    [self rebuildCapabilityEngine];

    DBNSLog(@"KisMAC startup done. Version %@. Build from %@. Homedir is %s. NSAppKitVersionNumber: %f",
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
            [NSString stringWithFormat:@"%s %s", __DATE__, __TIME__],
            [[[NSBundle mainBundle] bundlePath] fileSystemRepresentation],
            NSAppKitVersionNumber);
    
    [sets setObject:[[[NSBundle mainBundle] bundlePath] stringByAbbreviatingWithTildeInPath] forKey:@"KisMACHomeDir"];
    aGrowlController = [[GrowlController alloc] init];

    IONotificationPortRef  notifyPortRef;   // notification port allocated by IORegisterForSystemPower
    io_object_t            notifierObject;  // notifier object, used to deregister later
    
    // register to receive system sleep notifications
    root_port = IORegisterForSystemPower( (__bridge void *)(scanner), &notifyPortRef, NotifySleep, &notifierObject );
    if ( MACH_PORT_NULL == root_port )
    {
        DBNSLog(@"IORegisterForSystemPower failed\n");
    }
    else
    {
        // add the notification port to the application runloop
        CFRunLoopAddSource( CFRunLoopGetCurrent(),
                           IONotificationPortGetRunLoopSource(notifyPortRef),
                           kCFRunLoopCommonModes );
    }
}

#pragma mark -

- (IBAction)updateNetworkTable:(id)sender complete:(BOOL)complete
{
    __block BOOL _complete = complete;
    
    [queue cancelAllOperations];
    
    __block NSInteger row = 0;
    __block NSInteger i = 0;
    __block WaveNet *net = nil;
    
    if ([_container count] != [_networkTable numberOfRows])
    {
        _complete = YES;
    }
    
    if (_visibleTab == tabTraffic)
    {
        [mainQueue addOperationWithBlock:^{
            [_trafficController updateGraph];
        }];
    }
    else if (_visibleTab == tabNetworks)
    {
        [queue addOperationWithBlock:^{
            
            if (_lastSorted)
            {
                [_container sortWithShakerByColumn:_lastSorted order:_ascending];
            }
            
            if (_complete)
            {
                [mainQueue addOperationWithBlock:^{
                    [_networkTable reloadData];
                }];
                
                if (_detailsPaneVisibile)
                {
                    [aInfoController reloadData];
                }
                
                net = [_container netAtIndex:_selectedRow];
                
                if ([net isCorrectSSID] && net != _curNet)
                { //we lost our selected network
                    for (i = [_container count]; i >= 0; --i)
                    {
                        net = [_container netAtIndex:i];
                        if ([net isCorrectSSID] && net == _curNet)
                        {
                            _selectedRow = i;
                            [mainQueue addOperationWithBlock:^{
                                [_networkTable selectRowIndexes:[NSIndexSet indexSetWithIndex:_selectedRow]
                                           byExtendingSelection: NO];
                            }];
                            break;
                        }
                    }
                }
            }
            else
            {
                row = [_container nextChangedRow:BAD_ADDRESS];
                while (row != BAD_ADDRESS)
                {
                    net = [_container netAtIndex:row];
                    
                    if ([net isCorrectSSID] && net == _curNet)
                    {
                        _selectedRow = row;
                        [mainQueue addOperationWithBlock:^{
                            if (_detailsPaneVisibile)
                            {
                                [aInfoController reloadData];
                                
                                [_networkTable selectRowIndexes:[NSIndexSet indexSetWithIndex:_selectedRow]
                                           byExtendingSelection: NO];
                            }
                        }];
                    }
                    
                    [_networkTable displayRect:[_networkTable rectOfRow:row]];
                    row = [_container nextChangedRow:row];
                }
            }
        }];
    }
    else if (_visibleTab == tabDetails)
    {
        [queue addOperationWithBlock:^{
            
            if (_complete)
            {
                [mainQueue addOperationWithBlock:^{
                    [aInfoController reloadData];
                }];
                
                net = [_container netAtIndex:_selectedRow];
                
                if ([net isCorrectSSID] && net != _curNet)
                { //we lost our selected network
                    for (i = [_container count]; i >= 0; --i)
                    {
                        net = [_container netAtIndex:i];
                        if ([net isCorrectSSID] && net == _curNet)
                        {
                            _selectedRow = i;
                            [mainQueue addOperationWithBlock:^{
                                [_networkTable selectRowIndexes:[NSIndexSet indexSetWithIndex:_selectedRow]
                                           byExtendingSelection: NO];
                            }];
                            break;
                        }
                    }
                }
            }
            else
            {
                row = [_container nextChangedRow:BAD_ADDRESS];
                
                while (row != BAD_ADDRESS)
                {
                    net = [_container netAtIndex:row];
                    if ([net isCorrectSSID] && net == _curNet)
                    {
                        _selectedRow = row;
                        
                        [mainQueue addOperationWithBlock:^{
                            [aInfoController reloadData];
                            
                            [_networkTable selectRowIndexes:[NSIndexSet indexSetWithIndex:_selectedRow]
                                       byExtendingSelection: NO];
                        }];
                    }
                    
                    row = [_container nextChangedRow:row];
                }
            }
        }];
        
    }
}

- (void)updateViewItems:(NSNotification*)note
{
    if (!_refreshGUI)
        return;
    
    [self performSelectorOnMainThread:@selector(doUpdateViewItems:)
                           withObject:nil
                        waitUntilDone:NO];
}

- (void)doUpdateViewItems:(id)anObject
{
    [_container refreshView];
    if (_lastSorted)
    {
        [_container sortWithShakerByColumn:_lastSorted
                                     order:_ascending];
    }
    
    if (aNetHierarchVisible) {
        [ScanHierarch updateTree];
        [aOutView reloadData];
    }
}

#pragma mark -

- (void)stopScanForced:(NSNotification*)note
{
    [self stopScan];
}

#pragma mark -
#pragma mark Columns layout
#pragma mark -
- (void) selectedColumnHeader
{
    
}

#pragma mark -
#pragma mark Table datasource methods
#pragma mark -

- (id) tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *) aTableColumn row:(NSInteger) rowIndex
{
    WaveNet *net = [_container netAtIndex:rowIndex];
    
    return [net cache][[aTableColumn identifier]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [_container count];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    if ([_networkTable selectedRow] < 0)
    {
        [self hideDetails];
    }
    else
    {
        [self selectNet:[_container netAtIndex:[_networkTable selectedRow]]];
    }
}

- (void)tableView:(NSTableView*)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{
    NSString *ident = [tableColumn identifier];
    
    if (![tableView isEqualTo:_networkTable])
        return;
    
    if ((_lastSorted) && ([_lastSorted isEqualToString:ident])) {
        if (_ascending)
            _ascending=NO;
        else {
            _lastSorted = nil;
            [tableView setIndicatorImage:nil
                           inTableColumn:tableColumn];
            [tableView setHighlightedTableColumn:nil];
            [tableView reloadData];
            return;
        }
    } else {
        _ascending=YES;
        if (_lastSorted) {
            [tableView setIndicatorImage:nil
                           inTableColumn:[tableView tableColumnWithIdentifier:_lastSorted]];
        }
        _lastSorted=ident;
    }
    
    GBStorageController *gbStorage = [GBStorageController sharedControllerForNamespace:kGBStorageDefaultNamespace];
    
    if (![gbStorage objectForKeyedSubscript:@"NSAscendingSortIndicator"])
    {
        NSImage *image = [NSImage imageNamed:@"NSAscendingSortIndicator"];
        [gbStorage setObject:image forKeyedSubscript:@"NSAscendingSortIndicator"];
    }
    if (![gbStorage objectForKeyedSubscript:@"NSDescendingSortIndicator"])
    {
        NSImage *image = [NSImage imageNamed:@"NSDescendingSortIndicator"];
        [gbStorage setObject:image forKeyedSubscript:@"NSDescendingSortIndicator"];
    }
    
    [tableView setIndicatorImage:_ascending ? [gbStorage objectForKeyedSubscript:@"NSAscendingSortIndicator"] : [gbStorage objectForKeyedSubscript:@"NSDescendingSortIndicator"] inTableColumn:tableColumn];
    
    //speedy sort (quick sort is faster than shaker sort, but not stable)
    [_container sortByColumn:_lastSorted order:_ascending];
    [tableView setHighlightedTableColumn:tableColumn];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        
        [self updateNetworkTable:self complete:YES];
    });
}

#pragma mark -

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    return (item == nil) ? 3 : [item numberOfChildren];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return ([item numberOfChildren] != -1);
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    if (item != nil)
    {
        return [(ScanHierarch*)item childAtIndex:index];
    }
    else
    {
        return [ScanHierarch rootItem:_container index:index];
    }
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    return (item == nil) ? nil : (id)[item nameString];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    return NO;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    NSUInteger tmpID[6], i;
    unsigned char ID[6];
    
    if (item==nil)
        return YES;
    
    switch ([(ScanHierarch*)item type]) {
        case 99: //BSSID selector
            if (sscanf([[item identKey] UTF8String], "%2lX%2lX%2lX%2lX%2lX%2lX", &tmpID[0], &tmpID[1], &tmpID[2], &tmpID[3], &tmpID[4], &tmpID[5]) !=6 )
                DBNSLog(@"Error could not decode ID %@!", [item identKey]);
            for (i=0; i<6; ++i) ID[i] = tmpID[i];
            
            [self showDetailsFor:[_container netForKey:ID]];
            break;
        case 1: //topitems
        case 2:
        case 36:
            [self hideDetails];
            [_container setViewType:0 value:nil];
            if (_lastSorted) [_container sortByColumn:_lastSorted order:_ascending];
            break;
        case 3: //SSID selectors
            [self hideDetails];
            [_container setViewType:2 value:[(ScanHierarch*)item nameString]];
            if (_lastSorted) [_container sortByColumn:_lastSorted order:_ascending];
            break;
        case 37: //Crypto selectors
        case 38:
        case 40:
        case 41:
        case 42:
            [self hideDetails];
            [_container setViewType:3 value:@([(ScanHierarch*)item type]-36)];
            if (_lastSorted) [_container sortByColumn:_lastSorted order:_ascending];
            break;
        default: //channel selectors left
            [self hideDetails];
            [_container setViewType:1 value:@([(ScanHierarch*)item type]-20)];
            if (_lastSorted) [_container sortByColumn:_lastSorted order:_ascending];
    }
    
    [_networkTable reloadData];
    return YES;
}

#pragma mark -

- (IBAction)showInfo:(id)sender
{
    NSSize contentSize;
    
    if (_detailsPaneVisibile) {
        [_detailsDrawer close];
        [sender setTitle: NSLocalizedString(@"Show Details", "menu item")];
        _detailsPaneVisibile = NO;
        
        return;
    }
    if (_visibleTab == tabDetails)
        return;
    
    if (!_detailsDrawer) {
        contentSize = NSMakeSize(200, 250);
        _detailsDrawer = [[NSDrawer alloc] initWithContentSize:contentSize preferredEdge:NSMaxXEdge];
        [_detailsDrawer setParentWindow:_window];
        [_detailsDrawer setContentView:detailsView];
        [_detailsDrawer setMinContentSize:NSMakeSize(50, 50)];
        
        [_detailsDrawer setLeadingOffset:50];
        [_detailsDrawer setTrailingOffset:[_window frame].size.height-300];
        
        [_detailsDrawer setMaxContentSize:NSMakeSize(200, 300)];
    }
    
    [aInfoController setDetails:YES];
    [_detailsDrawer openOnEdge:NSMaxXEdge];
    [sender setTitle: NSLocalizedString(@"Hide Details", "menu item")];
    _detailsPaneVisibile = YES;
}

- (IBAction)showNetHierarch:(id)sender
{
    if (!aNetHierarchVisible) {
        [sender setTitle: NSLocalizedString(@"Hide Hierarchy", "menu item")];
        [_netHierarchDrawer openOnEdge:NSMinXEdge];
        
        [ScanHierarch updateTree];
        [aOutView reloadData];
    } else {
        [sender setTitle: NSLocalizedString(@"Show Hierarchy", "menu item. needs to be same as MainMenu.nib")];
        [_netHierarchDrawer close];
    }
    aNetHierarchVisible =! aNetHierarchVisible;
    [_showHierarch setState: aNetHierarchVisible ? NSOnState : NSOffState];
}

- (IBAction)changeSearchValue:(id)sender
{
    [_container setFilterString:[_searchField stringValue]];
    [_networkTable reloadData];
    [(NSView*)_mappingView setNeedsDisplay:YES];
    [self tableViewSelectionDidChange:nil];
}

- (void)checkFilter:(id)sender
{
    NSAlert *alert;
    //written by themacuser
    if(![[_searchField stringValue] isEqualToString:@""]){
        alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Save all nets"];
        [alert addButtonWithTitle:@"Save filtered nets"];
        [alert setMessageText:@"You are filtering the list of networks."];
        [alert setInformativeText:@"Do you want to save just the filtered networks, or all the networks?"];
        [alert setAlertStyle:NSWarningAlertStyle];
        if([alert runModal] == NSAlertFirstButtonReturn){
            [_container setFilterString:@""];
            _saveFilteredOnly = NO;
        }else {
            _saveFilteredOnly = YES;
        }
    }
}

- (IBAction)changeSearchType:(id)sender
{
    NSInteger ndx;
    [_container setFilterType:[sender title]];
    NSMenu * searchMenu = [sender menu];
    for (ndx=0; ndx < [searchMenu numberOfItems]; ++ndx) {
        [[searchMenu itemAtIndex:ndx] setState:0];
    }
    //[searchMenu release];
    [sender setState:1];
    [_networkTable reloadData];
    [(NSView*)_mappingView setNeedsDisplay:YES];
    [self tableViewSelectionDidChange:nil];
}

#pragma mark -
#pragma mark S1.4 Capability engine accessor + gating

- (KMCapabilityEngine *)capabilityEngine
{
    // Lazy fallback: if a query arrives before the async build finished, build
    // synchronously once. The probe is non-disruptive (S1.1) so this is safe,
    // and after the first build it is cached.
    if (!_capabilityEngine)
    {
        _capabilityEngine = [[KMCapabilityEngine alloc] initWithLiveProbe];
    }
    return _capabilityEngine;
}

- (void)rebuildCapabilityEngine
{
    // Probe touches real hardware -> never on the main thread (would stall UI).
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        KMCapabilityEngine *engine = [[KMCapabilityEngine alloc] initWithLiveProbe];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_capabilityEngine = engine;
            KMCapability *scan = [engine availabilityForCapability:KMFeatureScan];
            DBNSLog(@"[S1.4] Capability engine ready. scan=%@ reason=%@ -- %@",
                    KMStringFromCapabilityAvailability(scan.availability),
                    KMStringFromCapabilityReason(scan.reason),
                    scan.explanation);
            // Refresh the affordance enabled state now that the gate is known.
            [self->_scanButton setEnabled:scan.isAvailable];
        });
    });
}

- (void)locationAuthorizationChanged:(NSNotification *)note
{
    DBNSLog(@"[S1.4] Location authorization changed -- rebuilding capability engine to refresh the scan gate.");
    [self rebuildCapabilityEngine];
}

- (BOOL)capabilityAvailable:(NSString *)featureKey
{
    return [[self capabilityEngine] isAvailable:featureKey];
}

- (NSString *)capabilityKeyForActiveDriver
{
    // Map the active driver class to the capability key that honestly gates it.
    // S5.x owns the full PrefsDriver UI overhaul; here we do the minimal honest
    // gating so a needs-probe / unsupported-adapter driver is never usable as if
    // it were supported.
    WaveDriver *wd = _whichDriver ? [WaveHelper driverWithName:_whichDriver] : nil;

    if ([wd isKindOfClass:[WaveDriverAirportExtreme class]])
    {
        // Passive Airport Extreme == monitor-like capture. On built-in hardware
        // this is unknownRequiresActiveProbe (S1.1) -> engine reports it not
        // available, so it cannot be used as if supported.
        return KMFeatureMonitorMode;
    }
    Class usbDriverClass = NSClassFromString(@"WaveDriverUSB");
    if (usbDriverClass && [wd isKindOfClass:usbDriverClass])
    {
        // External USB injection adapters -> unsupportedAdapter (none present).
        return KMFeatureFrameInjection;
    }
    if ([wd isKindOfClass:[WaveDriverKismet class]] ||
        [wd isKindOfClass:[WaveDriverKismetDrone class]])
    {
        return KMFeatureKismetRemoteCapture;
    }

    // WaveDriverAirport (built-in active CoreWLAN scan) and the safe default.
    return KMFeatureScan;
}

#pragma mark -

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [_importController stopAnimation];
}

#pragma mark -

#pragma mark Application delegates

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    return [self open:filename];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    if (![self isSaved])
    {
        [self showWantToSaveDialog:@selector(reallyQuitDidEnd:returnCode:contextInfo:)];
        return NSTerminateLater;
    }
    
    return NSTerminateNow;
}

- (void)reallyQuitDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [self menuSetEnabled:YES menu:[NSApp mainMenu]];
    switch (returnCode) {
        case NSAlertOtherReturn:
            [NSApp replyToApplicationShouldTerminate:NO];
            break;
        case NSAlertDefaultReturn:
            [NSNotificationCenter postNotification:KisMACTryToSave];
        case NSAlertAlternateReturn:
        default:
            [NSApp replyToApplicationShouldTerminate:YES];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSString * logPath;
    NSString * crashPath;
    NSFileManager * mang;
    NSUserDefaults * sets;
    NSDirectoryEnumerator * enumerator;
    NSMutableData * crashLogs = nil;
    
    [self updatePrefs:nil];
    sets = [NSUserDefaults standardUserDefaults];

    // S1.1 - MacBook hardware capability probe. Runs once at launch,
    // asynchronously and NON-DISRUPTIVELY (never drops Wi-Fi / enters monitor
    // mode / switches channels / injects). Persists a per-model+OS report and
    // logs a summary. See Sources/Capabilities/KMHardwareProbe.
    [KMHardwareProbe runProbeAsynchronouslyWithCompletion:nil];

    // S1.3 - Capability engine self-test. Runs ONLY when KISMAC_CAP_SELFTEST=1
    // is set in the environment. Verifies the engine against mocked inputs
    // (hardware-independent) and logs PASS/FAIL. See KMCapabilityEngine.
    if ([[[NSProcessInfo processInfo] environment][@"KISMAC_CAP_SELFTEST"] isEqualToString:@"1"]) {
        [KMCapabilityEngine runSelfTestLogging];
    }

    // S2.2 - Offline pcap/pcapng import self-test. Runs ONLY when
    // KISMAC_PCAP_IMPORT_SELFTEST is set (to "1"/a fixture path) in the
    // environment. Imports a golden fixture through the OFFLINE pipeline
    // (-[WaveScanner readPCAPDump:] -> pcap_open_offline) into a throwaway
    // container and logs PASS/FAIL with actual vs expected network/client
    // counts. PASSIVE ONLY: never starts a scan / touches a radio / changes
    // channels. See Sources/Capabilities/KMPcapImportSelfTest.
    if ([[[NSProcessInfo processInfo] environment][@"KISMAC_PCAP_IMPORT_SELFTEST"] length] > 0) {
        [KMPcapImportSelfTest runSelfTestLogging];
    }

    // S2.1 - Modern protocol metadata self-test. Runs ONLY when
    // KISMAC_PROTO_SELFTEST is set in the environment. Imports each bundled
    // proto_*.pcap through the OFFLINE pipeline and asserts the decoded
    // security + PHY/generation display strings match the fixture's known
    // values. PASSIVE ONLY: no radio, no monitor, no channel switching. See
    // Sources/Capabilities/KMProtocolSelfTest.
    if ([[[NSProcessInfo processInfo] environment][@"KISMAC_PROTO_SELFTEST"] length] > 0) {
        [KMProtocolSelfTest runSelfTestLogging];
    }

    // S2.3 - Crypto/cracking self-test. Runs ONLY when KISMAC_CRYPTO_SELFTEST=1
    // is set in the environment. Asserts the CommonCrypto migration of the
    // crack path against standard vectors: CC_MD4/CC_MD5/CC_SHA1 digests, the
    // WPA PMK (PBKDF2-HMAC-SHA1) via both the reference and the migrated
    // CCKeyDerivationPBKDF path, and a LEAP NtPasswordHash + DES round-trip.
    // CPU-only / PASSIVE: no radio, no monitor mode. See KMCryptoSelfTest.
    if ([[[NSProcessInfo processInfo] environment][@"KISMAC_CRYPTO_SELFTEST"] isEqualToString:@"1"]) {
        [KMCryptoSelfTest runSelfTestLogging];
    }

    logPath = [@"~/Library/Logs/DiagnosticReports/" stringByExpandingTildeInPath];
    mang = [NSFileManager defaultManager];
    
    if ([[sets objectForKey:@"SupressCrashReport"] intValue] != 1)
    {
        enumerator = [mang enumeratorAtPath: logPath];
        
        //find all the crash logs and turn them into one big data blob
        for(NSString * file in enumerator)
        {
            if([file hasPrefix:@"KisMAC"])
            {
                //if we don't have any yet, allocate the data
                if(nil == crashLogs)
                {
                    crashLogs = [[NSMutableData alloc] init];
                }
                crashPath = [NSString stringWithFormat:@"%@/%@", logPath, file];
                DBNSLog(@"Found crash log at: %@", crashPath);
                [crashLogs appendData: [mang contentsAtPath:crashPath]];
            }
        }
        
        if(crashLogs != nil)
        {
            //append the last kismac log
            crashPath = [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Logs/KisMAC.log.1"];
            [crashLogs appendData: [mang contentsAtPath:crashPath]];
            
            CrashReportController* crc = [[CrashReportController alloc] initWithWindowNibName:@"CrashReporter"];
            [[crc window] setFrameUsingName:@"aKisMAC_CRC"];
            [[crc window] setFrameAutosaveName:@"aKisMAC_CRC"];
            
            [crc setReport:crashLogs];
            [crc showWindow:self];
            [[crc window] makeKeyAndOrderFront:self];
            
            DBNSLog(@"crash occured the last time kismac started");
        }
    }//crash logs enabled
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self stopScan];
    [self stopActiveAttacks];
    [[WaveHelper gpsController] stop];
    [WaveHelper unloadAllDrivers];
}


#pragma mark Main Window delegates

- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame
{
    if (aNetHierarchVisible)
    {
        defaultFrame.size.width-=[_netHierarchDrawer contentSize].width+10;
        defaultFrame.origin.x+=[_netHierarchDrawer contentSize].width+10;
    }
    if (_detailsPaneVisibile)
    {
        defaultFrame.size.width-=[_detailsDrawer contentSize].width+10;
        [_window setFrame:[_window frame] display:YES animate:YES];
    }
    
    return defaultFrame;
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize
{
    [_detailsDrawer setTrailingOffset:proposedFrameSize.height-280];
    
    return proposedFrameSize;
}

- (BOOL)windowShouldClose:(id)sender
{
    NSUserDefaults *sets = [NSUserDefaults standardUserDefaults];
    
    if ([sets boolForKey:@"terminateIfClosed"])
    {
        if (![self isSaved])
        {
            [self showWantToSaveDialog:@selector(reallyCloseDidEnd:returnCode:contextInfo:)];
            
            return NO;
        }
        
        [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(fade:) userInfo:nil repeats:YES];
        
        return NO;
    }
    else
    {
        [self isNew];
        
        return NO;
    }
}

- (void)reallyCloseDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [self menuSetEnabled:YES menu:[NSApp mainMenu]];
    switch (returnCode)
    {
        case NSAlertDefaultReturn:
            [NSNotificationCenter postNotification:KisMACTryToSave];
        case NSAlertOtherReturn:
            break;
        case NSAlertAlternateReturn:
        default:
            [_window setDocumentEdited:NO];
            [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(fade:) userInfo:nil repeats:YES];
    }
}

#pragma mark Fade Out Code

- (void)fade:(NSTimer *)timer
{
    if ([_window alphaValue] > 0.0) {
        // If window is still partially opaque, reduce its opacity.
        [_window setAlphaValue:[_window alphaValue] - 0.2];
    } else {
        // Otherwise, if window is completely transparent, destroy the timer and close the window.
        [timer invalidate];
        
        [_window close];
        [NSApp terminate:self];
    }
}

void NotifySleep( void * refCon, io_service_t service,
                 natural_t messageType, void * messageArgument ){
    
    switch ( messageType )
    {
            
        case kIOMessageSystemWillSleep:
            DBNSLog(@"Going to Sleep, Shutting down dirvers");
            [(__bridge WaveScanner*)refCon sleepDrivers: YES];
            IOAllowPowerChange( root_port, (long)messageArgument );
            break;
        case kIOMessageSystemHasPoweredOn:
            DBNSLog(@"System Woken up, Resetting Drivers");
            [(__bridge WaveScanner*)refCon sleepDrivers: NO];
            break;
            
        default:
            break;
            
    }
}

- (void)trackClient:(id)sender
{
    [_monitorMenu setState:NSOnState];
    [_monitorAllMenu setState:NSOffState];
    NSString *bssid, *mac;
    bssid = [_curNet BSSID];
    mac = [aInfoController theRow];
    [_monitorMenu setTitle:[NSString stringWithFormat:@"%@ %@ - %@",NSLocalizedString(@"Monitoring ", "menu item"), bssid, mac]];
    [WavePluginMidi setTrackString:bssid];
    [WavePluginMidi setTrackStringClient:mac];
    
}

- (void)selectedTableContextMenuItem:(id)sender
{
    if ([sender state] == NSOnState) {
        [_networkTable removeTableColumn:[sender representedObject]];
        [sender setState:NSOffState];
    }
    else {
        [_networkTable addTableColumn:[sender representedObject]];
        [sender setState:NSOnState];
    }
}

@end

@implementation ScanController (AppleScript)

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key
{
    return YES;
}

@end
