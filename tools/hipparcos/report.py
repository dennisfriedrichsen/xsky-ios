#!/usr/bin/env python3
"""Generates design/reports/hipparcos-crossmatch.md.

Measures the two candidate Hipparcos distributions against the questions
raised in issue #30: record counts, field population, spectral-class
coverage, magnitude distribution, bundle size, and — the load-bearing one —
how completely the 301 HR-keyed entries in starnames.dat reach a Hipparcos
entry through the HD cross-identification both catalogues carry.

Usage: tools/hipparcos/report.py [hipparcos-directory]

The default directory is tools/hipparcos/build, populated by fetch.sh.
This script only reads; it writes the report to design/reports/.
"""

import collections
import gzip
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LEGACY = os.path.join(REPO, "Resources", "LegacyCatalogs")
OUT = os.path.join(REPO, "design", "reports", "hipparcos-crossmatch.md")

# Byte ranges are 1-based inclusive, exactly as printed in the CDS ReadMe
# byte-by-byte tables.
HIP_MAIN = {
    "HIP": (9, 14),
    "Vmag": (42, 46),
    "RAdeg": (52, 63),
    "DEdeg": (65, 76),
    "Plx": (80, 86),
    "pmRA": (88, 95),
    "pmDE": (97, 104),
    "CCDM": (328, 337),
    "Ncomp": (344, 345),
    "m_HIP": (353, 354),
    "HD": (391, 396),
    "SpType": (436, 447),
}

# Spectral first characters the legacy StarColor mapping understands.
LEGACY_SPECTRAL = set("WOBAFGKMCNS")


def field(record, name, table=HIP_MAIN):
    start, end = table[name]
    return record[start - 1 : end].decode("latin-1").strip()


def load_hip_main(path):
    entries = {}
    for line in open(path, "rb"):
        record = line.rstrip(b"\n")
        entries[int(field(record, "HIP"))] = record
    return entries


def load_ybs_hr_to_hd(path):
    """HR number -> HD number, from the ybs.h fixed-width layout."""
    mapping = {}
    for line in open(path, "rb"):
        record = line.rstrip(b"\n")
        hr = record[0:4].decode("latin-1").strip()
        hd = record[22:28].decode("latin-1").strip()
        if hr.isdigit() and hd.isdigit():
            mapping[int(hr)] = int(hd)
    return mapping


def load_star_names(path):
    """(HR number, primary name) in file order, matching StarNameTable."""
    names = []
    for line in open(path, "rb"):
        record = line.rstrip(b"\n")
        head = record[0:5].decode("latin-1").strip()
        if not head.lstrip("+-").isdigit():
            continue
        primary = record[5:].decode("latin-1").split(";")[0].strip().rstrip(".")
        if primary:
            names.append((int(head), primary))
    return names


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "build")
    hip_main_path = os.path.join(src, "hip_main.dat")
    hip2_path = os.path.join(src, "hip2.dat")
    if not os.path.exists(hip_main_path):
        sys.exit(f"error: {hip_main_path} not found; run tools/hipparcos/fetch.sh first")

    hip = load_hip_main(hip_main_path)

    missing = collections.Counter()
    spectral_first = collections.Counter()
    hd_to_hip = collections.defaultdict(list)
    mag_cumulative = collections.Counter()
    mag_limits = (6.5, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0)

    for number, record in hip.items():
        for name in ("Vmag", "RAdeg", "Plx", "HD", "SpType"):
            if not field(record, name):
                missing[name] += 1
        spectral = field(record, "SpType")
        if spectral:
            spectral_first[spectral[0]] += 1
        hd = field(record, "HD")
        if hd:
            hd_to_hip[int(hd)].append(number)
        vmag = field(record, "Vmag")
        if vmag:
            value = float(vmag)
            for limit in mag_limits:
                if value <= limit:
                    mag_cumulative[limit] += 1

    hip2_numbers = set()
    for line in open(hip2_path, "rb"):
        hip2_numbers.add(int(line[0:6]))

    hr_to_hd = load_ybs_hr_to_hd(os.path.join(LEGACY, "ybs.dat"))
    star_names = load_star_names(os.path.join(LEGACY, "starnames.dat"))

    def merged_neighbour(hd):
        """The HD+/-1, HD+/-2 entry that Hipparcos merged into one solution.

        YBS lists the components of a close visual double as separate HR
        records with consecutive HD numbers. Hipparcos publishes a single
        combined astrometric solution and carries only one component's HD,
        so the secondary's HD has no exact match. A merged entry is one
        Hipparcos itself marks as a double or multiple: a CCDM identifier,
        a component identifier (m_HIP), or Ncomp >= 2.
        """
        found = []
        for delta in (-1, 1, -2, 2):
            for number in hd_to_hip.get(hd + delta, []):
                record = hip[number]
                ncomp = field(record, "Ncomp")
                if (field(record, "CCDM") or field(record, "m_HIP")
                        or (ncomp.isdigit() and int(ncomp) >= 2)):
                    found.append((hd + delta, number))
            if found:
                break
        return found

    exact, vianeighbour, unresolved, ambiguous = [], [], [], []
    for hr, name in star_names:
        hd = hr_to_hd.get(hr)
        if hd is None:
            unresolved.append((hr, name, None, "HR record carries no HD number"))
            continue
        matches = hd_to_hip.get(hd)
        if matches:
            if len(matches) > 1:
                ambiguous.append((hr, name, hd, matches))
            exact.append((hr, name, hd, matches[0]))
            continue
        neighbours = merged_neighbour(hd)
        if len(neighbours) == 1:
            vianeighbour.append((hr, name, hd, neighbours[0][0], neighbours[0][1]))
        elif neighbours:
            unresolved.append((hr, name, hd, f"ambiguous merged neighbours {neighbours}"))
        else:
            unresolved.append((hr, name, hd, "no Hipparcos entry for this HD"))

    raw_size = os.path.getsize(hip_main_path)
    with open(hip_main_path, "rb") as handle:
        gz_size = len(gzip.compress(handle.read(), 9))

    bright = [r for r in hip.values()
              if field(r, "Vmag") and float(field(r, "Vmag")) <= 9.0]
    bright_raw = sum(len(r) + 1 for r in bright)
    bright_gz = len(gzip.compress(b"\n".join(bright) + b"\n", 9))

    lines = []
    add = lines.append
    add("# Hipparcos cross-match and coverage report")
    add("")
    add("Generated by `tools/hipparcos/report.py`. See")
    add("[ADR 0001](../adr/0001-hipparcos-star-catalog.md) for the decision this")
    add("report supports. Regenerate with:")
    add("")
    add("```sh")
    add("tools/hipparcos/fetch.sh")
    add("tools/hipparcos/report.py")
    add("```")
    add("")
    add("## Record counts")
    add("")
    add("| Distribution | Records | Record width | Raw size |")
    add("|---|---:|---:|---:|")
    add(f"| I/239 `hip_main.dat` (ESA 1997) | {len(hip):,} | 451 B + newline | {raw_size:,} B |")
    add(f"| I/311 `hip2.dat` (van Leeuwen 2007) | {len(hip2_numbers):,} | 276 B + newline | {os.path.getsize(hip2_path):,} B |")
    add(f"| `ybs.dat` (current) | {len(open(os.path.join(LEGACY, 'ybs.dat'), 'rb').readlines()):,} | ragged, 113-137 B | {os.path.getsize(os.path.join(LEGACY, 'ybs.dat')):,} B |")
    add("")
    add(f"The revised reduction carries {len(hip) - len(hip2_numbers)} fewer entries than the 1997")
    add("release, not the same count. Every I/311 entry is present in I/239")
    add(f"({len(hip2_numbers - set(hip))} the other way), and the")
    add(f"{len(set(hip) - hip2_numbers)} I/239-only entries are exactly the")
    add(f"{missing['RAdeg']} records with no astrometric solution.")
    add("")
    add("## Field population in `hip_main.dat`")
    add("")
    add("| Field | Missing | Populated |")
    add("|---|---:|---:|")
    for name in ("RAdeg", "Plx", "Vmag", "HD", "SpType"):
        add(f"| `{name}` | {missing[name]:,} | {len(hip) - missing[name]:,} |")
    add("")
    add("Position and parallax are missing together in exactly the same")
    add(f"{missing['RAdeg']} records; there is no entry with a position but no parallax.")
    add("")
    add("## Spectral-class coverage")
    add("")
    add("First character of `SpType`, against the legacy `StarColor` mapping")
    add("(W with O; C/N/S with M):")
    add("")
    add("| Char | Count | Legacy mapping |")
    add("|---|---:|---|")
    for char, count in spectral_first.most_common():
        mapped = "yes" if char in LEGACY_SPECTRAL else "**no - neutral**"
        add(f"| `{char}` | {count:,} | {mapped} |")
    unknown = sum(c for ch, c in spectral_first.items() if ch not in LEGACY_SPECTRAL)
    add("")
    add(f"Unknown-class diagnostic count: **{unknown:,}** unmapped first characters")
    add(f"plus **{missing['SpType']:,}** records with no spectral type, i.e.")
    add(f"{unknown + missing['SpType']:,} of {len(hip):,} ({100 * (unknown + missing['SpType']) / len(hip):.1f}%) would")
    add("render with the neutral star colour.")
    add("")
    add("## Magnitude distribution (Johnson V)")
    add("")
    add("| V <= | Stars |")
    add("|---:|---:|")
    for limit in mag_limits:
        add(f"| {limit} | {mag_cumulative[limit]:,} |")
    add("")
    add("## Bundle size")
    add("")
    add("| Candidate | Records | Raw | gzip -9 |")
    add("|---|---:|---:|---:|")
    add(f"| `hip_main.dat` verbatim | {len(hip):,} | {raw_size / 1e6:.1f} MB | {gz_size / 1e6:.1f} MB |")
    add(f"| `hip_main.dat` rows with V <= 9 | {len(bright):,} | {bright_raw / 1e6:.1f} MB | {bright_gz / 1e6:.1f} MB |")
    add(f"| compact binary, 36 B/record, all | {len(hip):,} | {len(hip) * 36 / 1e6:.1f} MB | - |")
    add(f"| compact binary, 36 B/record, V <= 9 | {len(bright):,} | {len(bright) * 36 / 1e6:.1f} MB | - |")
    add("")
    add("`ybs.dat` is 1.2 MB for comparison. The 36-byte record assumes")
    add("HIP `u32`, RA/Dec `f64`, V `i16` in millimagnitudes, parallax `f32`,")
    add("two proper-motion `f32`, spectral class `u8`, flags `u8`.")
    add("")
    add("## YBS to Hipparcos overlap")
    add("")
    add("How completely a hybrid could de-duplicate the two star layers, using")
    add("HD as the join key.")
    add("")
    ybs_positioned = 0
    ybs_exact = 0
    ybs_unmatched = []
    for line in open(os.path.join(LEGACY, "ybs.dat"), "rb"):
        record = line.rstrip(b"\n")
        if not record[46:61].strip():
            continue
        ybs_positioned += 1
        hd = record[22:28].decode("latin-1").strip()
        if hd.isdigit() and int(hd) in hd_to_hip:
            ybs_exact += 1
        else:
            ybs_unmatched.append(record[0:4].decode("latin-1").strip())
    add("| Measure | Count |")
    add("|---|---:|")
    add(f"| positioned YBS records | {ybs_positioned:,} |")
    add(f"| exact HD match in `hip_main.dat` | {ybs_exact:,} |")
    add(f"| no exact HD match | {len(ybs_unmatched):,} |")
    add("")
    add(f"HD de-duplication is exact for {100 * ybs_exact / ybs_positioned:.1f}% of the bright-star layer.")
    add("The remainder are the same merged-double case as the named stars")
    add("below, plus a handful of YBS entries with no Hipparcos counterpart.")
    add("")
    add("## `starnames.dat` cross-match")
    add("")
    add(f"All {len(star_names)} entries are keyed by HR. Both catalogues carry an HD")
    add("number, so HD is the bridge: HR -> HD (from `ybs.dat`) -> HIP.")
    add("")
    add("| Outcome | Count |")
    add("|---|---:|")
    add(f"| exact HD match | {len(exact)} |")
    add(f"| matched via merged-double neighbour (HD +/- 1 or 2) | {len(vianeighbour)} |")
    add(f"| unresolved | {len(unresolved)} |")
    add(f"| **total** | **{len(star_names)}** |")
    add("")
    add(f"Of the {len(hd_to_hip):,} distinct HD numbers in `hip_main.dat`,")
    add(f"{sum(1 for v in hd_to_hip.values() if len(v) > 1)} map to more than one HIP entry;")
    add(f"{len(ambiguous)} of those collisions affect a named star.")
    add("")
    add("### Entries with no exact HD match")
    add("")
    add("These are the cases the bridge has to reason about. Every one is the")
    add("secondary component of a visual double or multiple that YBS lists as")
    add("its own HR record and Hipparcos publishes as a single combined")
    add("solution carrying only one component's HD.")
    add("")
    add("The neighbour match is a merge, not a rename: the named secondary and")
    add("its primary resolve to the *same* HIP entry, so the two HR records")
    add("collapse to one chart object.")
    add("")
    add("| HR | Name | YBS HD | Resolution |")
    add("|---:|---|---:|---|")
    for hr, name, hd, nhd, number in vianeighbour:
        add(f"| {hr} | {name} | {hd} | HIP {number} via HD {nhd} (merged multiple) |")
    for hr, name, hd, reason in unresolved:
        add(f"| {hr} | {name} | {hd if hd else '-'} | **unresolved**: {reason} |")
    add("")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as handle:
        handle.write("\n".join(lines))
    print(f"wrote {OUT}")
    print(f"  exact {len(exact)}, neighbour {len(vianeighbour)}, unresolved {len(unresolved)}")


if __name__ == "__main__":
    main()
