#!/opt/venv/bin/python
"""bids2seriesinfo.py: rebuild BCILDCMCONVERT's Seriesinfo.csv and
Studyinfo.csv from dcm2niix NIfTI + JSON sidecars (e.g. a BIDS session).

Author: K. Nemoto
Date: 3 Oct 2026

BCILDCMCONVERT (https://github.com/RIKEN-BCIL/BCILDCMCONVERT) writes these
files from the DICOM headers. Without DICOM, the values are computed from the
JSON sidecars with the same formulas, column order and formats, so that
bcil's hcppipe_qc, which reads Seriesinfo.csv by column position, can use
them. Checked against BCILDCMCONVERT's output for a HARP session
(Skyra_fit, 2026-10-03; see LOG.md).

What cannot come from the JSON is left empty or NONE:
  - Time: BCILDCMCONVERT records SeriesTime; dcm2niix only AcquisitionTime
  - Number of averages, SlicePartialFourier, Example DICOM, Series/Study UID
  - Read/Phase/Slice.direction of non-EPI series (BCILDCMCONVERT reads the
    phase encoding polarity from the CSA header; the rule used here was
    checked on EPI only)
  - Studyinfo: patient data, study date and UID (not in an anonymized BIDS),
    System (CSA header)

Usage:
  bids2seriesinfo.py [options] <outdir> <image.nii[.gz]> ...

Options:
  --age <value>          Patient's Age for Studyinfo.csv
  --rawdata <bids>=<raw> NIFTI in RawData for an input image (repeatable)
"""

import argparse
import csv
import decimal
import json
import os
import re
import sys

import nibabel as nib
import numpy as np

# Column order of BCILDCMCONVERT's SeriesCsvData / StudyCsvData
# (bcil_dcm_convert_csv.py, commit da19cfd). hcppipe_qc reads Seriesinfo.csv
# by position (awk -F,), so the order must not change.
SERIES_COLUMNS = [
    "Series Number", "Time", "Description", "Protocol", "Scanning Sequence",
    "Sequence Name", "TR[msec]", "TE[msec]", "TI[msec]", "FA[degree]",
    "Matrix(phase*read)", "Pixel size[mm]", "Slice thickness[mm]",
    "Number of averages", "Image Type", "DwelltimeRead", "DwelltimePhase",
    "Read.direction", "Phase.direction", "Slice.direction", "Patient Position",
    "flReferenceAmplitude", "Parallel factor", "Multi-band factor",
    "PhasePartialFourier", "SlicePartialFourier", "Total Count of DICOMs",
    "Example DICOM", "Series UID", "Study UID", "NIFTI in RawData",
    "NIFTI in BIDS",
]
STUDY_ROWS = [
    "Patient Name", "Patient ID", "Patient's Birth date", "Patient's Sex",
    "Patient's Age", "Patient's Size", "Patient's Weight", "Patient's Position",
    "Study Date", "Study Description", "Requesting physician", "Station",
    "Manufacturer", "Model", "Institution", "System", "Gradient", "PatAUSJID",
    "StudyUID",
]

# Gradient coil by scanner model (Studyinfo "Gradient"). Only models whose
# coil has been confirmed from a BCILDCMCONVERT Studyinfo.csv are listed.
GRADIENT_COIL = {
    "Skyra_fit": "AS097",  # 2026-10-03, HARP session converted with BCILDCMCONVERT
}

# sKSpace.ucPhasePartialFourier labels of BCILDCMCONVERT, by fraction
PARTIAL_FOURIER = {1.0: "OFF", 0.875: " 7/8", 0.75: " 6/8", 0.625: " 5/8", 0.5: " 4/8"}

# BCILDCMCONVERT's direction labels (bcil_dcm_kspace_info.py, gen_directions)
PHASE_LABEL = {1: "RL", -1: "LR", 2: "AP", -2: "PA", 3: "HF", -3: "FH"}
PHASE_VEC = {1: [-1, 0, 0], -1: [1, 0, 0], 2: [0, -1, 0], -2: [0, 1, 0],
             3: [0, 0, 1], -3: [0, 0, -1]}
SLICE_LABEL = {1: "SAG", 2: "COR", 3: "AXI"}
SLICE_VEC = {1: [1, 0, 0], 2: [0, 1, 0], 3: [0, 0, 1]}
READ_LABEL = {1: "LR", -1: "RL", 2: "PA", -2: "AP", 3: "HF", -3: "FH"}


def sidecar(path):
    return re.sub(r"\.nii(\.gz)?$", "", path) + ".json"


def ms(seconds):
    """Seconds to milliseconds, as BCILDCMCONVERT prints them (6100.0)."""
    return repr(float(round(seconds * 1000, 6))) if seconds is not None else ""


def dicom_float(value):
    """A DICOM DS stored as float32 (2.4 -> 2.4000000953674), as printed by
    BCILDCMCONVERT."""
    return repr(float("%.14g" % float(np.float32(value))))


def dwell_read(dwell):
    """DwelltimeRead: RealDwellTime[ns] / 1e9, as a plain decimal string."""
    if dwell is None:
        return ""
    ns = decimal.Decimal(round(dwell * 1e9))
    return str(ns / decimal.Decimal(1000000000)).rstrip("0")


def directions(j, img):
    """Read/Phase/Slice.direction with BCILDCMCONVERT's algorithm.

    BCILDCMCONVERT takes the phase encoding polarity from the CSA header
    (PhaseEncodingDirectionPositive). Here it is the sign of the dot product
    between the phase encoding vector of the NIfTI (affine column of the
    BIDS PhaseEncodingDirection, in LPS) and the in-plane DICOM vector; this
    matched BCILDCMCONVERT on all 27 EPI series of the reference session.
    """
    iop = j.get("ImageOrientationPatientDICOM")
    ipd = j.get("InPlanePhaseEncodingDirectionDICOM")
    pe = j.get("PhaseEncodingDirection")
    # The rule was checked on EPI only; 3D structural scans often have no
    # PhaseEncodingDirection, or one that was not checked, so they are left out
    if not (iop and ipd and pe) or j.get("ScanningSequence") != "EP":
        return "", "", ""
    d = np.array(iop[0:3] if ipd == "ROW" else iop[3:6], dtype=float)
    axis = "ijk".index(pe[0])
    v = img.affine[:3, axis] * (-1 if pe.endswith("-") else 1)
    v = v * np.array([-1, -1, 1])  # RAS -> LPS
    sign = 1 if float(v @ d) > 0 else -1

    phase_index = (int(np.argmax(np.abs(d))) + 1) * sign
    s = np.cross(iop[0:3], iop[3:6])
    slice_index = int(np.argmax(np.abs(s))) + 1
    p, q = PHASE_VEC[phase_index], SLICE_VEC[slice_index]
    r = [q[1] * p[2] - q[2] * p[1], q[2] * p[0] - q[0] * p[2], q[0] * p[1] - q[1] * p[0]]
    read_index = (int(np.argmax(np.abs(r))) + 1) * sum(r)
    return READ_LABEL[read_index], PHASE_LABEL[phase_index], SLICE_LABEL[slice_index]


def slice_axis(j, img):
    """NIfTI axis along the slice normal of the DICOM orientation."""
    iop = j.get("ImageOrientationPatientDICOM")
    if not iop:
        return 2
    n = np.cross(iop[0:3], iop[3:6]) * np.array([-1, -1, 1])  # LPS -> RAS
    cols = img.affine[:3, :3] / np.linalg.norm(img.affine[:3, :3], axis=0)
    return int(np.argmax(np.abs(n @ cols)))


def series_row(files, raw_of, mb_by_protocol):
    path = files[0]
    j = json.load(open(sidecar(path)))
    img = nib.load(path)
    image_type = list(j.get("ImageType", []))
    # Recent dcm2niix appends MAGNITUDE, which is not in the DICOM ImageType
    if image_type[-1:] == ["MAGNITUDE"] and "M" in image_type:
        image_type.pop()
    shape = img.shape + (1,) * (4 - len(img.shape))
    zooms = img.header.get_zooms()
    sax = slice_axis(j, img)
    inplane = [a for a in range(3) if a != sax]

    pf = j.get("PartialFourier")
    mb = j.get("MultibandAccelerationFactor")
    if mb is None:
        mb = mb_by_protocol.get(j.get("ProtocolName"))
    if mb is None and "WipMemBlock" in j:  # CMRR sequence with MB off
        mb = 1
    bw, am = j.get("BandwidthPerPixelPhaseEncode"), j.get("AcquisitionMatrixPE")
    read_d, phase_d, slice_d = directions(j, img)
    count = shape[3] if "MOSAIC" in image_type else shape[sax] * shape[3]
    raw = [raw_of[f] for f in files if f in raw_of]

    return {
        "Series Number": j["SeriesNumber"],
        "Time": "",
        "Description": j.get("SeriesDescription", ""),
        "Protocol": j.get("ProtocolName", ""),
        "Scanning Sequence": re.sub(r"[_\\]", "", j.get("ScanningSequence", "")),
        "Sequence Name": j.get("SequenceName", "NONE"),
        "TR[msec]": ms(j.get("RepetitionTime")),
        "TE[msec]": ms(j.get("EchoTime")),
        "TI[msec]": ms(j.get("InversionTime")),
        "FA[degree]": repr(float(j["FlipAngle"])) if "FlipAngle" in j else "NONE",
        "Matrix(phase*read)": f"{am}*{j['BaseResolution']}" if am and "BaseResolution" in j else "",
        "Pixel size[mm]": " ".join("%.14g" % float(np.float32(zooms[a])) for a in inplane),
        "Slice thickness[mm]": dicom_float(j["SliceThickness"]) if "SliceThickness" in j else "NONE",
        "Number of averages": "NONE",
        "Image Type": " ".join(image_type),
        "DwelltimeRead": dwell_read(j.get("DwellTime")),
        "DwelltimePhase": repr(1 / (bw * am)) if bw and am else "",
        "Read.direction": read_d,
        "Phase.direction": phase_d,
        "Slice.direction": slice_d,
        "Patient Position": j.get("PatientPosition", "NONE"),
        "flReferenceAmplitude": repr(float(j["TxRefAmp"])) if "TxRefAmp" in j else "NONE",
        "Parallel factor": str(j.get("ParallelReductionFactorInPlane", 1)),
        "Multi-band factor": str(mb) if mb is not None else "",
        "PhasePartialFourier": PARTIAL_FOURIER.get(pf, "") if pf is not None else "",
        "SlicePartialFourier": "NONE",
        "Total Count of DICOMs": count,
        "Example DICOM": "NONE",
        "Series UID": "NONE",
        "Study UID": "NONE",
        "NIFTI in RawData": " ".join(raw) if raw else "NONE",
        "NIFTI in BIDS": " ".join(files),
    }


def study_rows(j, age):
    model = j.get("ManufacturersModelName", "NONE")
    values = {
        "Patient's Age": age or "NONE",
        "Patient's Position": j.get("PatientPosition", "NONE"),
        "Station": j.get("StationName", "NONE"),
        "Manufacturer": j.get("Manufacturer", "NONE").upper(),
        "Model": model,
        "Institution": j.get("InstitutionName", "NONE"),
        "Gradient": GRADIENT_COIL.get(model, "NONE"),
    }
    return [(k, values.get(k, "NONE")) for k in STUDY_ROWS]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("outdir")
    ap.add_argument("images", nargs="+")
    ap.add_argument("--age")
    ap.add_argument("--rawdata", action="append", default=[], metavar="BIDS=RAW")
    a = ap.parse_args()

    raw_of = dict(r.split("=", 1) for r in a.rawdata)
    by_series = {}
    for f in sorted(a.images):
        if not os.path.exists(sidecar(f)):
            continue
        j = json.load(open(sidecar(f)))
        if "SeriesNumber" in j:
            by_series.setdefault(int(j["SeriesNumber"]), []).append(f)
    if not by_series:
        sys.exit("ERROR: no image with a JSON sidecar and a SeriesNumber")

    # MB factor of each protocol, for the SBRef series (no MB in their JSON)
    mb_by_protocol = {}
    for files in by_series.values():
        j = json.load(open(sidecar(files[0])))
        if "MultibandAccelerationFactor" in j:
            mb_by_protocol[j.get("ProtocolName")] = j["MultibandAccelerationFactor"]

    rows = [series_row(by_series[s], raw_of, mb_by_protocol) for s in sorted(by_series)]
    for r in rows:
        for k, v in r.items():
            if "," in str(v):  # hcppipe_qc splits on every comma
                r[k] = str(v).replace(",", " ")

    os.makedirs(a.outdir, exist_ok=True)
    with open(os.path.join(a.outdir, "Seriesinfo.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=SERIES_COLUMNS, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    first = json.load(open(sidecar(by_series[min(by_series)][0])))
    with open(os.path.join(a.outdir, "Studyinfo.csv"), "w", newline="") as fh:
        csv.writer(fh, lineterminator="\n").writerows(study_rows(first, a.age))


if __name__ == "__main__":
    main()
