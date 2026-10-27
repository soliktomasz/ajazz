// hidspy — DYLD interposer that logs all IOHIDDevice traffic from Stream Dock AJAZZ.
// Build: clang -dynamiclib -arch arm64 -o hidspy.dylib hidspy.c -framework IOKit -framework CoreFoundation
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sys/time.h>
#include <unistd.h>
#include <IOKit/hid/IOHIDDevice.h>

#define INTERPOSE(newf, oldf) \
  __attribute__((used)) static struct { const void *n; const void *o; } \
  _interpose_##oldf __attribute__((section("__DATA,__interpose"))) = \
  { (const void *)(unsigned long)&newf, (const void *)(unsigned long)&oldf };

static FILE *g_log;
static FILE *g_bin;
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;

__attribute__((constructor)) static void spy_ctor(void);
static void spy_init(void) {
  if (g_log) return;
  const char *p = getenv("HIDSPY_LOG");
  g_log = fopen(p ? p : "/tmp/hidspy.log", "w");
  if (g_log) setvbuf(g_log, NULL, _IOLBF, 0);
  const char *b = getenv("HIDSPY_BIN");
  if (b) g_bin = fopen(b, "wb");
}

static double now_ms(void) {
  struct timeval tv; gettimeofday(&tv, NULL);
  return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

// Log a report. Full hex for small frames; head+tail for bulk image payloads.
static void dump(const char *tag, int rtype, long rid, const uint8_t *b, long n) {
  spy_init(); if (!g_log) return;
  pthread_mutex_lock(&g_mu);
  fprintf(g_log, "[%.3f] %s type=%d id=%ld len=%ld\n", now_ms(), tag, rtype, rid, n);
  long head = n <= 96 ? n : 64;
  fprintf(g_log, "  hex:");
  for (long i = 0; i < head; i++) fprintf(g_log, " %02x", b[i]);
  if (n > head) fprintf(g_log, " ... (+%ld more)", n - head);
  if (g_bin) {
    // record: tag[4] | reportType[4] | length[4] | payload
    unsigned int t = (unsigned int)rtype, l = (unsigned int)n;
    fwrite(tag[0] == 'S' ? "SETR" : (tag[0] == 'G' ? "GETR" : "INPR"), 1, 4, g_bin);
    fwrite(&t, 4, 1, g_bin); fwrite(&l, 4, 1, g_bin);
    fwrite(b, 1, (size_t)n, g_bin);
    fflush(g_bin);
  }
  fprintf(g_log, "\n  asc: ");
  for (long i = 0; i < head; i++) fputc((b[i] >= 32 && b[i] < 127) ? b[i] : '.', g_log);
  fprintf(g_log, "\n");
  pthread_mutex_unlock(&g_mu);
}

IOReturn my_IOHIDDeviceSetReport(IOHIDDeviceRef d, IOHIDReportType t, CFIndex rid,
                                 const uint8_t *r, CFIndex len) {
  dump("SET_REPORT", (int)t, (long)rid, r, (long)len);
  return IOHIDDeviceSetReport(d, t, rid, r, len);
}
INTERPOSE(my_IOHIDDeviceSetReport, IOHIDDeviceSetReport)

IOReturn my_IOHIDDeviceGetReport(IOHIDDeviceRef d, IOHIDReportType t, CFIndex rid,
                                 uint8_t *r, CFIndex *plen) {
  IOReturn ret = IOHIDDeviceGetReport(d, t, rid, r, plen);
  if (ret == kIOReturnSuccess && plen) dump("GET_REPORT", (int)t, (long)rid, r, (long)*plen);
  return ret;
}
INTERPOSE(my_IOHIDDeviceGetReport, IOHIDDeviceGetReport)

// Wrap the input-report callback so we see key/knob events too.
static IOHIDReportCallback g_user_cb;
static void *g_user_ctx;

static void my_input_cb(void *ctx, IOReturn res, void *sender, IOHIDReportType t,
                        uint32_t rid, uint8_t *r, CFIndex len) {
  dump("INPUT", (int)t, (long)rid, r, (long)len);
  if (g_user_cb) g_user_cb(g_user_ctx, res, sender, t, rid, r, len);
}

void my_IOHIDDeviceRegisterInputReportCallback(IOHIDDeviceRef d, uint8_t *report, CFIndex len,
                                               IOHIDReportCallback cb, void *ctx) {
  spy_init();
  if (g_log) fprintf(g_log, "[%.3f] REGISTER_INPUT_CB buflen=%ld\n", now_ms(), (long)len);
  g_user_cb = cb; g_user_ctx = ctx;
  IOHIDDeviceRegisterInputReportCallback(d, report, len, my_input_cb, ctx);
}
INTERPOSE(my_IOHIDDeviceRegisterInputReportCallback, IOHIDDeviceRegisterInputReportCallback)

IOReturn my_IOHIDDeviceOpen(IOHIDDeviceRef d, IOOptionBits o) {
  spy_init();
  if (g_log) {
    CFNumberRef vid = IOHIDDeviceGetProperty(d, CFSTR("VendorID"));
    CFNumberRef pid = IOHIDDeviceGetProperty(d, CFSTR("ProductID"));
    int v = 0, p = 0;
    if (vid) CFNumberGetValue(vid, kCFNumberIntType, &v);
    if (pid) CFNumberGetValue(pid, kCFNumberIntType, &p);
    fprintf(g_log, "[%.3f] OPEN vid=0x%04x pid=0x%04x opts=0x%x\n", now_ms(), v, p, (unsigned)o);
  }
  return IOHIDDeviceOpen(d, o);
}
INTERPOSE(my_IOHIDDeviceOpen, IOHIDDeviceOpen)

__attribute__((constructor)) static void spy_ctor(void) {
  spy_init();
  if (g_log) fprintf(g_log, "[%.3f] HIDSPY LOADED into pid %d\n", now_ms(), getpid());
}
