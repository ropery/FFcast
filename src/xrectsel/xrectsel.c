/* xrectsel.c 0.3 */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <X11/Xlib.h>
#include <X11/cursorfont.h>

#define die(args...) do {error(args); exit(EXIT_FAILURE); } while(0)

typedef struct Region Region;
struct Region {
  Window root;
  int x; /* offset from left of screen */
  int y; /* offset from top of screen */
  int X; /* offset from right of screen */
  int Y; /* offset from bottom of screen */
  unsigned int w; /* width */
  unsigned int h; /* height */
  unsigned int b; /* border_width */
  unsigned int d; /* depth */
};

static void error(const char *errstr, ...);
static int print_region_attr(const char *fmt, Region region);
static int select_region(Display *dpy, Window root, Region *region);

int main(int argc, const char *argv[])
{
  Display *dpy;
  Window root;
  Region sr; /* selected region */
  const char *fmt; /* format string */

  dpy = XOpenDisplay(NULL);
  if (!dpy) {
    die("failed to open display %s\n", getenv("DISPLAY"));
  }

  root = DefaultRootWindow(dpy);

  fmt = argc > 1 ? argv[1] : "%wx%h+%x+%y\n";

  /* interactively select a rectangular region */
  if (select_region(dpy, root, &sr) != EXIT_SUCCESS) {
    XCloseDisplay(dpy);
    die("failed to select a rectangular region\n");
  }

  print_region_attr(fmt, sr);

  XCloseDisplay(dpy);
  return EXIT_SUCCESS;
}

static void error(const char *errstr, ...)
{
  va_list ap;

  fprintf(stderr, "xrectsel: ");
  va_start(ap, errstr);
  vfprintf(stderr, errstr, ap);
  va_end(ap);
}

static int print_region_attr(const char *fmt, Region region)
{
  const char *s;

  for (s = fmt; *s; ++s) {
    if (*s == '%') {
      switch (*++s) {
        case '%':
          putchar('%');
          break;
        case 'x':
          printf("%i", region.x);
          break;
        case 'y':
          printf("%i", region.y);
          break;
        case 'X':
          printf("%i", region.X);
          break;
        case 'Y':
          printf("%i", region.Y);
          break;
        case 'w':
          printf("%u", region.w);
          break;
        case 'h':
          printf("%u", region.h);
          break;
        case 'b':
          printf("%u", region.b);
          break;
        case 'd':
          printf("%u", region.d);
          break;
      }
    } else {
      putchar(*s);
    }
  }

  return 0;
}

static int select_region(Display *dpy, Window root, Region *region)
{
  XEvent ev;

  GC sel_gc;
  XGCValues sel_gv;

  int done = 0, btn_pressed = 0;
  int x = 0, y = 0;
  unsigned int width = 0, height = 0;
  int start_x = 0, start_y = 0;

  Cursor cursor;
  cursor = XCreateFontCursor(dpy, XC_crosshair);

  /* Grab pointer for these events */
  XGrabPointer(dpy, root, True, PointerMotionMask | ButtonPressMask | ButtonReleaseMask,
               GrabModeAsync, GrabModeAsync, None, cursor, CurrentTime);

  sel_gv.function = GXinvert;
  sel_gv.subwindow_mode = IncludeInferiors;
  sel_gv.line_width = 1;
  sel_gc = XCreateGC(dpy, root, GCFunction | GCSubwindowMode | GCLineWidth, &sel_gv);

  for (;;) {
    XNextEvent(dpy, &ev);
    switch (ev.type) {
      case ButtonPress:
        btn_pressed = 1;
        x = start_x = ev.xbutton.x_root;
        y = start_y = ev.xbutton.y_root;
        width = height = 0;
        break;
      case MotionNotify:
        /* Draw only if button is pressed */
        if (btn_pressed) {
          /* Re-draw last Rectangle to clear it */
          XDrawRectangle(dpy, root, sel_gc, x, y, width, height);

          x = ev.xbutton.x_root;
          y = ev.xbutton.y_root;

          if (x > start_x) {
            width = x - start_x;
            x = start_x;
          } else {
            width = start_x - x;
          }
          if (y > start_y) {
            height = y - start_y;
            y = start_y;
          } else {
            height = start_y - y;
          }

          /* Draw Rectangle */
          XDrawRectangle(dpy, root, sel_gc, x, y, width, height);
          XFlush(dpy);
        }
        break;
      case ButtonRelease:
        done = 1;
        break;
      default:
        break;
    }
    if (done)
      break;
  }

  /* Re-draw last Rectangle to clear it */
  XDrawRectangle(dpy, root, sel_gc, x, y, width, height);
  XFlush(dpy);

  XUngrabPointer(dpy, CurrentTime);
  XFreeCursor(dpy, cursor);
  XFreeGC(dpy, sel_gc);
  XSync(dpy, 1);

  Region rr; /* root region */
  Region sr; /* selected region */

  if (False == XGetGeometry(dpy, root, &rr.root, &rr.x, &rr.y, &rr.w, &rr.h, &rr.b, &rr.d)) {
    error("failed to get root window geometry\n");
    return EXIT_FAILURE;
  }
  sr.x = x;
  sr.y = y;
  sr.w = width;
  sr.h = height;
  /* calculate right and bottom offset */
  sr.X = rr.w - sr.x - sr.w;
  sr.Y = rr.h - sr.y - sr.h;
  /* those doesn't really make sense but should be set */
  sr.b = rr.b;
  sr.d = rr.d;
  *region = sr;
  return EXIT_SUCCESS;
}
