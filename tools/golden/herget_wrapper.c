/*
 * herget_wrapper.c - wraps the Herget precession and Roman constellation
 * identification logic from the legacy xsky boundary.c / con-bounds.h.
 *
 * generate.sh extracts lines 760-842 of ../xsky/boundary.c verbatim into
 * herget_body.c (the two static functions herget_precession() and
 * init_herget_precession()); this file supplies the surrounding
 * declarations they expect and exposes wrappers for goldengen.c. The
 * constellation search loop below is transcribed from
 * identify_constellation() in boundary.c with only the X-coordinate
 * conversion removed (the wrapper takes RA/Dec directly).
 *
 * Legacy code copyright 1992-6 Terry R. Friedrichsen; Roman boundary table
 * due to Dr. Nancy G. Roman (1987, PASP, 99, 695).
 */

#include <math.h>
#include <stdio.h>

#include "skydefs.h"
#include "catreader.h"   /* COMMON_EQUINOX */
#include "constell.h"    /* constellations[] name tables */

#ifndef PI
#define PI M_PI
#endif
#define TWOPI (2 * PI)
#define CONVH (TWOPI / 24)
#define CONVD (TWOPI / 360)
#define CDR CONVD
#define B1875 1875.0

static double r[3][3];
static boolean herget_init_flag = FALSE;

static void herget_precession(double, double, double *, double *);
static void init_herget_precession(double, double);

#include "herget_body.c"

#include "con-bounds.h"

void golden_herget_precession(double ra, double dec,
                              double *ra_out, double *dec_out) {
  herget_precession(ra, dec, ra_out, dec_out);
}

const char *golden_identify_constellation(double arad, double drad) {
  double a, d;
  double ra, dec;
  int i;
  int con;

  herget_precession(arad, drad, &a, &d);

  if (a < 0)
    a += TWOPI;
  if (a >= TWOPI)
    a -= TWOPI;

  ra = a / CONVH;
  dec = d / CONVD;

  i = 0;
  while (bound_list[i].decl > dec)
    i++;

  while (TRUE) {
    while (bound_list[i].rau <= ra)
      i++;

    while (bound_list[i].ral > ra)
      i++;

    if ((ra >= bound_list[i].ral) && (ra < bound_list[i].rau) &&
        (bound_list[i].decl <= dec)) {
      con = bound_list[i].conidx;
      break;
    } else if (bound_list[i].rau < ra)
      continue;
    else
      return (const char *)NULL;
  }

  return constellations[con];
}
