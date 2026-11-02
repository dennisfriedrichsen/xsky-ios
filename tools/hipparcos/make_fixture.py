#!/usr/bin/env python3
"""Regenerates the Hipparcos parser-prototype golden fixture.

Writes two files into
Packages/XSkyCore/Tests/XSkyCoreTests/Fixtures/hipparcos/:

  hip_main_sample.dat   selected records copied byte-for-byte from
                        I/239 hip_main.dat, in HIP order
  hip_main_expected.json expected parse results

The expected values come from this script, which implements the field
layout independently from the published CDS byte-by-byte table in
ReadMe.I239 -- never from the Swift code under test. That mirrors the rule
in Fixtures/README.md: golden values are produced by a reference
implementation, and the Swift test only consumes them.

Usage: tools/hipparcos/make_fixture.py [hipparcos-directory]
Default directory is tools/hipparcos/build, populated by fetch.sh.
"""

import json
import math
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTDIR = os.path.join(
    REPO, "Packages", "XSkyCore", "Tests", "XSkyCoreTests", "Fixtures", "hipparcos")

# Chosen to exercise every branch the prototype has: complete records at
# both declination signs, each kind of missing field, the spectral-type
# characters the legacy colour mapping does not know, a record with no
# astrometric solution at all, and the double-star entries that the
# starnames.dat cross-match has to reach through an HD neighbour.
SELECTED = {
    1: "complete record, northern declination",
    2: "complete record, southern declination",
    6: "no HD cross-identification",
    16: "no spectral type",
    99: "spectral type C, grouped with M by the legacy mapping",
    168: "spectral type R, unknown to the legacy mapping",
    421: "no astrometric solution: no position, no parallax, no proper motion",
    1041: "spectral type W, grouped with O by the legacy mapping",
    3213: "spectral type beginning with lowercase s, unknown to the mapping",
    3829: "spectral type D (white dwarf), unknown to the legacy mapping",
    9487: "Alrisha: combined AB solution, carries only HD 12446",
    32349: "Sirius: brightest star, large proper motion and parallax",
    40167: "Tegmen: three-component solution, carries only HD 68255",
    65423: "spectral type beginning with '(', unknown to the legacy mapping",
    91262: "Vega",
    120412: "the single record with no Johnson V magnitude; also unsolved",
}

# 1-based inclusive byte ranges, verbatim from the ReadMe byte-by-byte table.
FIELDS = {
    "hip": (9, 14),
    "vmag": (42, 46),
    "raDegrees": (52, 63),
    "decDegrees": (65, 76),
    "parallaxMas": (80, 86),
    "pmRAMasPerYear": (88, 95),
    "pmDecMasPerYear": (97, 104),
    "ccdm": (328, 337),
    "componentCount": (344, 345),
    "componentIdentifiers": (353, 354),
    "hd": (391, 396),
    "spectralType": (436, 447),
}

LEGACY_SPECTRAL = {
    "W": "o", "O": "o", "B": "b", "A": "a", "F": "f",
    "G": "g", "K": "k", "M": "m", "C": "m", "N": "m", "S": "m",
}

# Hipparcos positions are given at epoch J1991.25 on the ICRS, which is
# aligned with the J2000 frame to well below catalogue precision, so
# reaching J2000 is proper-motion propagation only -- no precession.
EPOCH_YEARS = 2000.0 - 1991.25
MAS_TO_RAD = math.pi / (180.0 * 3600.0 * 1000.0)


def text(record, name):
    start, end = FIELDS[name]
    return record[start - 1 : end].decode("latin-1").strip()


def number(record, name):
    raw = text(record, name)
    return float(raw) if raw else None


def propagate_to_j2000(ra_deg, dec_deg, pm_ra_mas, pm_dec_mas):
    """Rigorous unit-vector propagation, pole-safe unlike adding to RA.

    pmRA is mu_alpha*cos(delta), so it is already an angular rate on the
    sky and multiplies the RA tangent vector directly. Radial velocity is
    not in the catalogue, so this is the standard no-radial-velocity
    approximation.
    """
    ra = math.radians(ra_deg)
    dec = math.radians(dec_deg)
    cos_dec, sin_dec = math.cos(dec), math.sin(dec)
    cos_ra, sin_ra = math.cos(ra), math.sin(ra)

    position = (cos_dec * cos_ra, cos_dec * sin_ra, sin_dec)
    ra_hat = (-sin_ra, cos_ra, 0.0)
    dec_hat = (-sin_dec * cos_ra, -sin_dec * sin_ra, cos_dec)

    rate = tuple(
        pm_ra_mas * MAS_TO_RAD * ra_hat[i] + pm_dec_mas * MAS_TO_RAD * dec_hat[i]
        for i in range(3))
    moved = tuple(position[i] + rate[i] * EPOCH_YEARS for i in range(3))
    norm = math.sqrt(sum(c * c for c in moved))
    x, y, z = (c / norm for c in moved)

    new_ra = math.atan2(y, x) % (2.0 * math.pi)
    new_dec = math.asin(max(-1.0, min(1.0, z)))
    return new_ra, new_dec


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "build")
    path = os.path.join(src, "hip_main.dat")
    if not os.path.exists(path):
        sys.exit(f"error: {path} not found; run tools/hipparcos/fetch.sh first")

    found = {}
    for line in open(path, "rb"):
        record = line.rstrip(b"\n")
        number_ = int(text(record, "hip"))
        if number_ in SELECTED:
            found[number_] = record

    missing = sorted(set(SELECTED) - set(found))
    if missing:
        sys.exit(f"error: HIP numbers not present in {path}: {missing}")

    os.makedirs(OUTDIR, exist_ok=True)

    with open(os.path.join(OUTDIR, "hip_main_sample.dat"), "wb") as handle:
        for key in sorted(found):
            handle.write(found[key] + b"\n")

    expected = []
    for key in sorted(found):
        record = found[key]
        spectral_type = text(record, "spectralType")
        ra_deg = number(record, "raDegrees")
        dec_deg = number(record, "decDegrees")
        pm_ra = number(record, "pmRAMasPerYear")
        pm_dec = number(record, "pmDecMasPerYear")

        entry = {
            "hip": key,
            "note": SELECTED[key],
            "vmag": number(record, "vmag"),
            "raDegrees": ra_deg,
            "decDegrees": dec_deg,
            "parallaxMas": number(record, "parallaxMas"),
            "pmRAMasPerYear": pm_ra,
            "pmDecMasPerYear": pm_dec,
            "hd": int(text(record, "hd")) if text(record, "hd") else None,
            "spectralType": spectral_type or None,
            "spectralClass": LEGACY_SPECTRAL.get(
                spectral_type[0] if spectral_type else "", "neutral"),
            "ccdm": text(record, "ccdm") or None,
            "componentCount": int(text(record, "componentCount"))
            if text(record, "componentCount") else None,
            "componentIdentifiers": text(record, "componentIdentifiers") or None,
        }
        if ra_deg is not None and dec_deg is not None:
            ra_rad, dec_rad = propagate_to_j2000(
                ra_deg, dec_deg, pm_ra or 0.0, pm_dec or 0.0)
            entry["j2000RARadians"] = ra_rad
            entry["j2000DecRadians"] = dec_rad
        else:
            entry["j2000RARadians"] = None
            entry["j2000DecRadians"] = None
        expected.append(entry)

    document = {
        "source": "CDS/VizieR I/239 hip_main.dat (ESA 1997, SP-1200)",
        "sourceSHA256":
            "e98e9076f9caf3e15c75b4cadd9a6576df9ab4d6a321fc02a26ad3f08aa8a8a9",
        "generator": "tools/hipparcos/make_fixture.py",
        "recordEpoch": "J1991.25 (ICRS)",
        "propagatedEpoch": "J2000",
        "records": expected,
    }
    with open(os.path.join(OUTDIR, "hip_main_expected.json"), "w") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")

    print(f"wrote {len(expected)} records to {OUTDIR}")


if __name__ == "__main__":
    main()
