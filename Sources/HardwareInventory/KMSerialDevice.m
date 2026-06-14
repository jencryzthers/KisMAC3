/*
 File:        KMSerialDevice.m
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 This file is part of KisMAC. GPL v2.
 */

#import "KMSerialDevice.h"
#import "../Safety/KMRedactionSettings.h"

@implementation KMSerialDevice

- (BOOL)looksLikeUARTOrGPS {
    NSString *hay = [NSString stringWithFormat:@"%@ %@ %@",
                     self.baseName ?: @"", self.calloutDevice ?: @"", self.suffix ?: @""];
    hay = [hay lowercaseString];
    NSArray *needles = @[ @"usbserial", @"usbmodem", @"uart", @"gps", @"slab",
                          @"ftdi", @"ch34", @"cp210", @"serial", @"wchusb" ];
    for (NSString *n in needles) {
        if ([hay rangeOfString:n].location != NSNotFound) return YES;
    }
    return NO;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.baseName) d[@"baseName"] = self.baseName;
    if (self.calloutDevice) d[@"calloutDevice"] = self.calloutDevice;
    if (self.dialinDevice) d[@"dialinDevice"] = self.dialinDevice;
    if (self.suffix) d[@"suffix"] = self.suffix;
    d[@"looksLikeUARTOrGPS"] = @(self.looksLikeUARTOrGPS);
    return d;
}

- (NSString *)redactedDescriptionWithSettings:(KMRedactionSettings *)settings {
    (void)settings; // device paths are not personal identifiers; keep intact.
    return [NSString stringWithFormat:@"Serial \"%@\" callout=%@ dialin=%@%@",
            self.baseName ?: @"?",
            self.calloutDevice ?: @"-",
            self.dialinDevice ?: @"-",
            self.looksLikeUARTOrGPS ? @" [UART/GPS]" : @""];
}

- (NSString *)description {
    return [self redactedDescriptionWithSettings:nil];
}

@end
