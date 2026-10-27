// sdprobe — enumerate + inspect the Ajazz Stream Dock HID interface.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDDevice.h>

static int num_prop(IOHIDDeviceRef d, CFStringRef k) {
  CFTypeRef v = IOHIDDeviceGetProperty(d, k);
  int out = -1;
  if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberIntType, &out);
  return out;
}
static void str_prop(IOHIDDeviceRef d, CFStringRef k, char *buf, size_t n) {
  buf[0] = 0;
  CFTypeRef v = IOHIDDeviceGetProperty(d, k);
  if (v && CFGetTypeID(v) == CFStringGetTypeID())
    CFStringGetCString(v, buf, n, kCFStringEncodingUTF8);
}

int main(void) {
  IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
  IOHIDManagerSetDeviceMatching(mgr, NULL);
  IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
  CFSetRef set = IOHIDManagerCopyDevices(mgr);
  if (!set) { printf("no devices\n"); return 1; }
  CFIndex n = CFSetGetCount(set);
  IOHIDDeviceRef *devs = calloc(n, sizeof(*devs));
  CFSetGetValues(set, (const void **)devs);

  for (CFIndex i = 0; i < n; i++) {
    IOHIDDeviceRef d = devs[i];
    int vid = num_prop(d, CFSTR(kIOHIDVendorIDKey));
    int pid = num_prop(d, CFSTR(kIOHIDProductIDKey));
    if (vid != 0x0300) continue;   // Ajazz / HOTSPOTEK
    char prod[256], mfr[256], serial[256];
    str_prop(d, CFSTR(kIOHIDProductKey), prod, sizeof prod);
    str_prop(d, CFSTR(kIOHIDManufacturerKey), mfr, sizeof mfr);
    str_prop(d, CFSTR(kIOHIDSerialNumberKey), serial, sizeof serial);
    printf("=== HID device %ld ===\n", (long)i);
    printf("  vid=0x%04x pid=0x%04x\n", vid, pid);
    printf("  product='%s' mfr='%s' serial='%s'\n", prod, mfr, serial);
    printf("  usagePage=0x%x usage=0x%x\n",
           num_prop(d, CFSTR(kIOHIDPrimaryUsagePageKey)), num_prop(d, CFSTR(kIOHIDPrimaryUsageKey)));
    printf("  maxInput=%d maxOutput=%d maxFeature=%d\n",
           num_prop(d, CFSTR(kIOHIDMaxInputReportSizeKey)),
           num_prop(d, CFSTR(kIOHIDMaxOutputReportSizeKey)),
           num_prop(d, CFSTR(kIOHIDMaxFeatureReportSizeKey)));
    printf("  locationID=0x%x\n", num_prop(d, CFSTR(kIOHIDLocationIDKey)));

    CFTypeRef rd = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDReportDescriptorKey));
    if (rd && CFGetTypeID(rd) == CFDataGetTypeID()) {
      const uint8_t *b = CFDataGetBytePtr(rd);
      CFIndex len = CFDataGetLength(rd);
      printf("  reportDescriptor (%ld bytes):\n   ", (long)len);
      for (CFIndex j = 0; j < len; j++) {
        printf(" %02x", b[j]);
        if ((j + 1) % 16 == 0) printf("\n   ");
      }
      printf("\n");
    } else printf("  reportDescriptor: <unavailable>\n");
  }
  return 0;
}
