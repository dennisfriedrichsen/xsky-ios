/*
 * goldengen.c - golden fixture generator for the XSky iOS port.
 *
 * Compiles the UNMODIFIED legacy position.c (from the sibling ../xsky
 * repository, -DMEEUS branch) together with this driver, and emits a JSON
 * fixture file consumed by the Swift test suite. The Herget precession
 * routines are extracted verbatim from boundary.c by generate.sh into
 * herget_extract.c; the Roman boundary table comes straight from
 * con-bounds.h. The Swift implementation is never used to generate its
 * own expected values.
 *
 * Legacy code copyright 1992-6 Terry R. Friedrichsen; see ../xsky.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "skydefs.h"
#include "pos.h"

/* legacy routines from position.c */
extern void pos_rad_to_X_double(struct display *, double, double,
                                double *, double *);
extern void pos_rad_to_X(struct display *, double, double, int *, int *);
extern void X_to_pos_rad(struct display *, int, int, double *, double *);
extern void calculate_limits(struct display *);
extern boolean within_limits(struct display *, double, double);
extern void init_precess(double, double);
extern void precess(double, double, double *, double *);
extern double ra_to_rad(int, int, int, int);
extern double dec_to_rad(int, int, int, int, int);
extern struct ra_pos rad_to_ra(double);
extern struct dec_pos rad_to_dec(double);
extern boolean get_ra(char *, struct ra_pos *);
extern boolean get_dec(char *, struct dec_pos *);

/* extracted legacy routines (see generate.sh) */
extern void golden_herget_precession(double, double, double *, double *);
extern const char *golden_identify_constellation(double, double);

/* --- test data ------------------------------------------------------- */

struct testpoint {
  const char *name;
  double ra_rad, dec_rad;
};

/* positions in J2000 radians (values are inputs, not expectations) */
static struct testpoint points[] = {
  { "center_orion",  1.4665923398, -0.0209621934 },
  { "sirius",        1.7677953696, -0.2917512740 },
  { "betelgeuse",    1.5497291380,  0.1292776940 },
  { "m31",           0.1863402843,  0.7202828960 },
  { "polaris",       0.6624317181,  1.5579526427 },
  { "sgr_a",         4.6498570863, -0.5062817157 },
  { "ra_wrap_low",   0.0087266463, -0.1745329252 },
  { "ra_wrap_high",  6.2657320146, -0.1745329252 },
  { "south_pole_ish",3.6651914292, -1.5533430343 },
  { "equator_12h",   3.1415926536,  0.0 },
};
#define NUM_POINTS (sizeof(points) / sizeof(points[0]))

struct testdisplay {
  const char *name;
  int width, height;
  double scale;         /* degrees per pixel */
  int downunder;
  double center_ra, center_dec;
};

static struct testdisplay displays[] = {
  { "orion_default",   400, 400, 0.05,  0, 1.4665923398, -0.0209621934 },
  { "orion_downunder", 400, 400, 0.05,  1, 1.4665923398, -0.0209621934 },
  { "near_north_pole", 800, 600, 0.1,   0, 0.0500000000,  1.5358897417 },
  { "ra_wrap",        1024, 768, 0.2,   0, 6.1959188445, -0.5235987756 },
  { "wide_field",      400, 400, 0.5,   0, 3.1415926536,  0.0 },
  { "narrow_polaris",  500, 400, 0.001, 0, 0.6624317181,  1.5579526427 },
  { "south_downunder", 640, 480, 0.15,  1, 4.7123889804, -1.2217304764 },
};
#define NUM_DISPLAYS (sizeof(displays) / sizeof(displays[0]))

/* inverse-projection probe pixels, per display (fractions of w/h) */
static double probe_fracs[][2] = {
  { 0.0, 0.0 }, { 0.5, 0.5 }, { 1.0, 1.0 }, { 0.0325, 0.9425 },
  { 1.0, 0.0 }, { 0.25, 0.75 },
};
#define NUM_PROBES (sizeof(probe_fracs) / sizeof(probe_fracs[0]))

static const char *ra_strings[] = {
  "5h 36m 12s.7", "23h", "12m", "1h2m3s.456", "0h 0m 0s",
  "18h 59m 59s.999", "6h.5", "45m.25",
};
#define NUM_RA_STRINGS (sizeof(ra_strings) / sizeof(ra_strings[0]))

static const char *dec_strings[] = {
  "-01d 12' 07\"", "+89d 59' 59\".99", "90d", "-90d", "0d 30'",
  "-23d 26' 21\".41", "+41d 16' 9\"", "-0d 0' 1\"",
};
#define NUM_DEC_STRINGS (sizeof(dec_strings) / sizeof(dec_strings[0]))

static double format_rads[] = {
  0.0, 0.1234567890, 1.4665923398, 3.1415926535, 6.2831853000,
  6.2831853071795865, -0.5, 12.9,
};
#define NUM_FORMAT_RADS (sizeof(format_rads) / sizeof(format_rads[0]))

static double precess_epochs[][2] = {
  { 1900.0, 2000.0 }, { 1950.0, 2000.0 }, { 1975.0, 2000.0 },
  { 2000.0, 1950.0 },
};
#define NUM_EPOCH_PAIRS (sizeof(precess_epochs) / sizeof(precess_epochs[0]))

/* --- helpers --------------------------------------------------------- */

static int first_item;

static void begin_array(const char *key) {
  printf("  \"%s\": [\n", key);
  first_item = 1;
}

static void sep(void) {
  if (!first_item)
    printf(",\n");
  first_item = 0;
}

static void end_array(int last) {
  printf("\n  ]%s\n", last ? "" : ",");
}

/* escape backslashes and double quotes for JSON string output */
static const char *json_escape(const char *s) {
  static char buf[256];
  char *o = buf;
  while (*s && o < buf + sizeof(buf) - 3) {
    if (*s == '"' || *s == '\\')
      *o++ = '\\';
    *o++ = *s++;
  }
  *o = '\0';
  return buf;
}

static void setup_display(struct display *d, struct testdisplay *td) {
  memset(d, 0, sizeof(*d));
  d->width = td->width;
  d->height = td->height;
  d->scale = (float)td->scale;
  d->downunder_flag = (boolean)td->downunder;
  d->center_ra_rad = td->center_ra;
  d->center_dec_rad = td->center_dec;
}

/* --- main ------------------------------------------------------------ */

int main(void) {
  unsigned i, j, p;
  struct display d;

  printf("{\n");

  /* forward projection (double precision, MEEUS branch) */
  begin_array("forwardProjection");
  for (i = 0; i < NUM_DISPLAYS; i++) {
    setup_display(&d, &displays[i]);
    for (j = 0; j < NUM_POINTS; j++) {
      double x, y;
      pos_rad_to_X_double(&d, points[j].ra_rad, points[j].dec_rad, &x, &y);
      sep();
      printf("    {\"display\": \"%s\", \"point\": \"%s\", "
             "\"x\": %.12f, \"y\": %.12f}",
             displays[i].name, points[j].name, x, y);
    }
  }
  end_array(0);

  /* inverse projection of integer pixels */
  begin_array("inverseProjection");
  for (i = 0; i < NUM_DISPLAYS; i++) {
    setup_display(&d, &displays[i]);
    for (p = 0; p < NUM_PROBES; p++) {
      int px = (int)(probe_fracs[p][0] * (displays[i].width - 1));
      int py = (int)(probe_fracs[p][1] * (displays[i].height - 1));
      double ra, dec;
      X_to_pos_rad(&d, px, py, &ra, &dec);
      sep();
      printf("    {\"display\": \"%s\", \"px\": %d, \"py\": %d, "
             "\"ra\": %.14f, \"dec\": %.14f}",
             displays[i].name, px, py, ra, dec);
    }
  }
  end_array(0);

  /* display limits (conservative viewport bounds) */
  begin_array("displayLimits");
  for (i = 0; i < NUM_DISPLAYS; i++) {
    setup_display(&d, &displays[i]);
    calculate_limits(&d);
    sep();
    printf("    {\"display\": \"%s\", \"leftRA\": %.14f, \"rightRA\": %.14f, "
           "\"topDec\": %.14f, \"bottomDec\": %.14f}",
           displays[i].name, d.left_ra_rad, d.right_ra_rad,
           d.top_dec_rad, d.bottom_dec_rad);
  }
  end_array(0);

  /* within_limits quick test on every display x point combination */
  begin_array("withinLimits");
  for (i = 0; i < NUM_DISPLAYS; i++) {
    setup_display(&d, &displays[i]);
    calculate_limits(&d);
    for (j = 0; j < NUM_POINTS; j++) {
      sep();
      printf("    {\"display\": \"%s\", \"point\": \"%s\", \"inside\": %s}",
             displays[i].name, points[j].name,
             within_limits(&d, points[j].ra_rad, points[j].dec_rad)
                 ? "true" : "false");
    }
  }
  end_array(0);

  /* IAU 1976 precession */
  begin_array("precession");
  for (i = 0; i < NUM_EPOCH_PAIRS; i++) {
    init_precess(precess_epochs[i][0], precess_epochs[i][1]);
    for (j = 0; j < NUM_POINTS; j++) {
      double ra, dec;
      precess(points[j].ra_rad, points[j].dec_rad, &ra, &dec);
      sep();
      printf("    {\"from\": %.1f, \"to\": %.1f, \"point\": \"%s\", "
             "\"ra\": %.14f, \"dec\": %.14f}",
             precess_epochs[i][0], precess_epochs[i][1], points[j].name,
             ra, dec);
    }
  }
  end_array(0);

  /* Herget precession J2000 -> B1875 (constellation identification) */
  begin_array("hergetPrecession");
  for (j = 0; j < NUM_POINTS; j++) {
    double ra, dec;
    golden_herget_precession(points[j].ra_rad, points[j].dec_rad, &ra, &dec);
    sep();
    printf("    {\"point\": \"%s\", \"ra\": %.14f, \"dec\": %.14f}",
           points[j].name, ra, dec);
  }
  end_array(0);

  /* constellation identification (Roman table, B1875) */
  begin_array("constellation");
  for (j = 0; j < NUM_POINTS; j++) {
    const char *name = golden_identify_constellation(points[j].ra_rad,
                                                     points[j].dec_rad);
    sep();
    printf("    {\"point\": \"%s\", \"constellation\": \"%s\"}",
           points[j].name, name ? name : "");
  }
  end_array(0);

  /* sexagesimal RA parsing (get_ra mutates its buffer; use a copy) */
  begin_array("raParse");
  for (i = 0; i < NUM_RA_STRINGS; i++) {
    char buf[64];
    struct ra_pos ra;
    strncpy(buf, ra_strings[i], sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    if (get_ra(buf, &ra)) {
      sep();
      printf("    {\"input\": \"%s\", \"h\": %d, \"m\": %d, \"s\": %d, "
             "\"thousandths\": %d, \"radians\": %.14f}",
             json_escape(ra_strings[i]), ra.hours, ra.minutes, ra.seconds,
             ra.thousandths,
             ra_to_rad(ra.hours, ra.minutes, ra.seconds, ra.thousandths));
    } else {
      sep();
      printf("    {\"input\": \"%s\", \"invalid\": true}", json_escape(ra_strings[i]));
    }
  }
  end_array(0);

  /* sexagesimal declination parsing */
  begin_array("decParse");
  for (i = 0; i < NUM_DEC_STRINGS; i++) {
    char buf[64];
    struct dec_pos dec;
    strncpy(buf, dec_strings[i], sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    if (get_dec(buf, &dec)) {
      sep();
      printf("    {\"input\": \"%s\", \"sign\": %d, \"d\": %d, \"m\": %d, "
             "\"s\": %d, \"hundredths\": %d, \"radians\": %.14f}",
             json_escape(dec_strings[i]), dec.sign, dec.degrees, dec.minutes,
             dec.seconds, dec.hundredths,
             dec_to_rad(dec.sign, dec.degrees, dec.minutes, dec.seconds,
                        dec.hundredths));
    } else {
      sep();
      printf("    {\"input\": \"%s\", \"invalid\": true}", json_escape(dec_strings[i]));
    }
  }
  end_array(0);

  /* radians -> sexagesimal formatting */
  begin_array("raFormat");
  for (i = 0; i < NUM_FORMAT_RADS; i++) {
    struct ra_pos ra = rad_to_ra(format_rads[i]);
    sep();
    printf("    {\"radians\": %.14f, \"h\": %d, \"m\": %d, \"s\": %d, "
           "\"thousandths\": %d}",
           format_rads[i], ra.hours, ra.minutes, ra.seconds, ra.thousandths);
  }
  end_array(0);

  begin_array("decFormat");
  for (i = 0; i < NUM_FORMAT_RADS; i++) {
    double v = format_rads[i] / 5.0; /* keep within sane declination range */
    struct dec_pos dec = rad_to_dec(v);
    sep();
    printf("    {\"radians\": %.14f, \"sign\": %d, \"d\": %d, \"m\": %d, "
           "\"s\": %d, \"hundredths\": %d}",
           v, dec.sign, dec.degrees, dec.minutes, dec.seconds,
           dec.hundredths);
  }
  end_array(1);

  printf("}\n");
  return 0;
}
