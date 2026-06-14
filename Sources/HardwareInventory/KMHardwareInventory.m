/*
 File:        KMHardwareInventory.m
 Program:     KisMac3
 Slice:       S3.2 - USB/HID/serial inventory

 This file is part of KisMAC. GPL v2.

 READ-ONLY: every IOKit call here either matches services or reads registry
 properties. There is NO IOServiceOpen / IORegistryEntrySetCFProperty / write of
 any kind. The collector is pure diagnostics.
 */

#import "KMHardwareInventory.h"
#import "KMUSBDevice.h"
#import "KMHIDDevice.h"
#import "KMSerialDevice.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/serial/IOSerialKeys.h>

@implementation KMHardwareInventory

#pragma mark - Property helpers (read-only registry reads)

/// Copy a registry property and bridge it to NSString, searching parents so a
/// USB device picks up its string descriptors. Returns nil when absent.
static NSString *KMStringProperty(io_registry_entry_t entry, CFStringRef key) {
    CFTypeRef ref = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key,
        kCFAllocatorDefault, kIORegistryIterateRecursively);
    if (!ref) return nil;
    NSString *out = nil;
    if (CFGetTypeID(ref) == CFStringGetTypeID()) {
        out = [(__bridge NSString *)ref copy];
    } else if (CFGetTypeID(ref) == CFNumberGetTypeID()) {
        out = [(__bridge NSNumber *)ref stringValue];
    }
    CFRelease(ref);
    return out;
}

/// Copy a numeric registry property, searching parents. Returns NSNotFound-style
/// sentinel via the BOOL out-param.
static long long KMNumberProperty(io_registry_entry_t entry, CFStringRef key, BOOL *found) {
    if (found) *found = NO;
    CFTypeRef ref = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key,
        kCFAllocatorDefault, kIORegistryIterateRecursively);
    if (!ref) return -1;
    long long out = -1;
    if (CFGetTypeID(ref) == CFNumberGetTypeID()) {
        if (CFNumberGetValue((CFNumberRef)ref, kCFNumberLongLongType, &out)) {
            if (found) *found = YES;
        }
    }
    CFRelease(ref);
    return out;
}

static NSString *KMServicePath(io_registry_entry_t entry) {
    io_string_t path = {0};
    if (IORegistryEntryGetPath(entry, kIOServicePlane, path) == KERN_SUCCESS) {
        return [NSString stringWithUTF8String:path];
    }
    return nil;
}

#pragma mark - USB

- (NSArray<KMUSBDevice *> *)enumerateUSBDevices {
    NSMutableArray<KMUSBDevice *> *out = [NSMutableArray array];

    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matching) {
        // Older class name fallback for newer host stacks.
        matching = IOServiceMatching("IOUSBHostDevice");
    }
    if (!matching) return out;

    io_iterator_t it = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) != KERN_SUCCESS) {
        return out;
    }

    io_service_t svc;
    while ((svc = IOIteratorNext(it))) {
        KMUSBDevice *dev = [[KMUSBDevice alloc] init];
        BOOL f;
        long long v;
        v = KMNumberProperty(svc, CFSTR("idVendor"), &f);   if (f) dev.vendorID = (NSInteger)v;
        v = KMNumberProperty(svc, CFSTR("idProduct"), &f);  if (f) dev.productID = (NSInteger)v;
        v = KMNumberProperty(svc, CFSTR("bDeviceClass"), &f);    if (f) dev.deviceClass = (NSInteger)v;
        v = KMNumberProperty(svc, CFSTR("bDeviceSubClass"), &f); if (f) dev.deviceSubClass = (NSInteger)v;

        dev.vendorName  = KMStringProperty(svc, CFSTR("USB Vendor Name"))
                       ?: KMStringProperty(svc, CFSTR(kUSBVendorString));
        dev.productName = KMStringProperty(svc, CFSTR("USB Product Name"))
                       ?: KMStringProperty(svc, CFSTR(kUSBProductString));
        dev.serialNumber = KMStringProperty(svc, CFSTR("USB Serial Number"))
                        ?: KMStringProperty(svc, CFSTR(kUSBSerialNumberString));

        v = KMNumberProperty(svc, CFSTR("locationID"), &f);
        if (f) dev.locationID = [NSString stringWithFormat:@"0x%08llx", (unsigned long long)v];

        long long speed = KMNumberProperty(svc, CFSTR("Device Speed"), &f);
        if (f) {
            switch (speed) {
                case 0: dev.speed = @"low (1.5 Mbps)"; break;
                case 1: dev.speed = @"full (12 Mbps)"; break;
                case 2: dev.speed = @"high (480 Mbps)"; break;
                case 3: dev.speed = @"super (5 Gbps)"; break;
                case 4: dev.speed = @"super+ (10 Gbps)"; break;
                default: dev.speed = [NSString stringWithFormat:@"code %lld", speed]; break;
            }
        }

        dev.servicePath = KMServicePath(svc);

        [out addObject:dev];
        IOObjectRelease(svc);
    }
    IOObjectRelease(it);
    return out;
}

#pragma mark - HID

- (NSArray<KMHIDDevice *> *)enumerateHIDDevices {
    NSMutableArray<KMHIDDevice *> *out = [NSMutableArray array];

    CFMutableDictionaryRef matching = IOServiceMatching(kIOHIDDeviceKey);
    if (!matching) return out;

    io_iterator_t it = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) != KERN_SUCCESS) {
        return out;
    }

    io_service_t svc;
    while ((svc = IOIteratorNext(it))) {
        KMHIDDevice *dev = [[KMHIDDevice alloc] init];
        BOOL f;
        long long v;
        v = KMNumberProperty(svc, CFSTR(kIOHIDPrimaryUsagePageKey), &f); if (f) dev.usagePage = (NSInteger)v;
        v = KMNumberProperty(svc, CFSTR(kIOHIDPrimaryUsageKey), &f);     if (f) dev.usage = (NSInteger)v;
        v = KMNumberProperty(svc, CFSTR(kIOHIDVendorIDKey), &f);  if (f) dev.vendorID = (NSInteger)v;
        v = KMNumberProperty(svc, CFSTR(kIOHIDProductIDKey), &f); if (f) dev.productID = (NSInteger)v;

        dev.productName  = KMStringProperty(svc, CFSTR(kIOHIDProductKey));
        dev.manufacturer = KMStringProperty(svc, CFSTR(kIOHIDManufacturerKey));
        dev.transport    = KMStringProperty(svc, CFSTR(kIOHIDTransportKey));
        dev.serialNumber = KMStringProperty(svc, CFSTR(kIOHIDSerialNumberKey));

        [out addObject:dev];
        IOObjectRelease(svc);
    }
    IOObjectRelease(it);
    return out;
}

#pragma mark - Serial (BSD tty)

- (NSArray<KMSerialDevice *> *)enumerateSerialDevices {
    NSMutableArray<KMSerialDevice *> *out = [NSMutableArray array];

    CFMutableDictionaryRef matching = IOServiceMatching(kIOSerialBSDServiceValue);
    if (!matching) return out;

    io_iterator_t it = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) != KERN_SUCCESS) {
        return out;
    }

    io_service_t svc;
    while ((svc = IOIteratorNext(it))) {
        KMSerialDevice *dev = [[KMSerialDevice alloc] init];
        dev.baseName      = KMStringProperty(svc, CFSTR(kIOTTYBaseNameKey));
        dev.suffix        = KMStringProperty(svc, CFSTR(kIOTTYSuffixKey));
        dev.calloutDevice = KMStringProperty(svc, CFSTR(kIOCalloutDeviceKey));
        dev.dialinDevice  = KMStringProperty(svc, CFSTR(kIODialinDeviceKey));
        [out addObject:dev];
        IOObjectRelease(svc);
    }
    IOObjectRelease(it);
    return out;
}

@end
