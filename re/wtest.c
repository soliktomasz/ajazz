// wtest — probe how IOHIDDeviceSetReport behaves on the Ajazz vendor interface.
#include <stdio.h>
#include <string.h>
#include <IOKit/hid/IOHIDManager.h>

static int iprop(IOHIDDeviceRef d, CFStringRef k) {
  CFTypeRef v = IOHIDDeviceGetProperty(d, k); int o = -1;
  if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberIntType, &o);
  return o;
}

static void report_cb(void *ctx, IOReturn res, void *sender, IOHIDReportType t,
                      uint32_t rid, uint8_t *r, CFIndex len) {
  printf("    [async callback] result=0x%08x len=%ld\n", res, (long)len);
  *(int *)ctx = 1;
}

int main(void) {
  IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
  int vid = 0x0300, pid = 0x3002;
  CFNumberRef v = CFNumberCreate(NULL, kCFNumberIntType, &vid);
  CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &pid);
  const void *keys[] = { CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey) };
  const void *vals[] = { v, p };
  CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2, NULL, NULL);
  IOHIDManagerSetDeviceMatching(m, match);
  IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);
  CFSetRef set = IOHIDManagerCopyDevices(m);
  if (!set) { printf("no devices\n"); return 1; }
  CFIndex n = CFSetGetCount(set);
  IOHIDDeviceRef devs[16]; CFSetGetValues(set, (const void **)devs);

  IOHIDDeviceRef dev = NULL;
  for (CFIndex i = 0; i < n && i < 16; i++)
    if (iprop(devs[i], CFSTR(kIOHIDPrimaryUsagePageKey)) == 0xFFA0) dev = devs[i];
  if (!dev) { printf("vendor interface not found\n"); return 1; }
  printf("vendor interface: maxOut=%d maxIn=%d\n",
         iprop(dev, CFSTR(kIOHIDMaxOutputReportSizeKey)),
         iprop(dev, CFSTR(kIOHIDMaxInputReportSizeKey)));

  IOReturn r = IOHIDDeviceOpen(dev, kIOHIDOptionsTypeNone);
  printf("open: 0x%08x\n", r);
  IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

  // read the version, proving the read path
  uint8_t ver[64]; CFIndex vlen = 21; memset(ver, 0, sizeof ver);
  r = IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, 0, ver, &vlen);
  printf("GetReport(input,0,21): 0x%08x -> '%s'\n", r, (char *)ver);

  static uint8_t buf[8192];
  memset(buf, 0, sizeof buf);
  memcpy(buf, "CRT\0\0LIG", 8);
  buf[10] = 5;   // brightness 5% — obvious if it lands

  struct { const char *name; IOHIDReportType t; CFIndex rid; CFIndex len; } cases[] = {
    { "output, id=0, len=1024", kIOHIDReportTypeOutput,  0, 1024 },
    { "output, id=0, len=4096 (oversize)", kIOHIDReportTypeOutput, 0, 4096 },
    { "output, id=0, len=8    (undersize)", kIOHIDReportTypeOutput, 0, 8 },
    { "output, id=1, len=1024", kIOHIDReportTypeOutput,  1, 1024 },
    { "feature, id=0, len=1024", kIOHIDReportTypeFeature, 0, 1024 },
  };
  for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++) {
    r = IOHIDDeviceSetReport(dev, cases[i].t, cases[i].rid, buf, cases[i].len);
    printf("  SetReport %-36s -> 0x%08x %s\n", cases[i].name, r,
           r == kIOReturnSuccess ? "(success)" : "(FAILED)");
  }

  int done = 0;
  r = IOHIDDeviceSetReportWithCallback(dev, kIOHIDReportTypeOutput, 0, buf, 1024,
                                       2.0, report_cb, &done);
  printf("  SetReportWithCallback immediate return -> 0x%08x\n", r);
  CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2.5, false);
  if (!done) printf("    [async callback never fired]\n");
  return 0;
}
