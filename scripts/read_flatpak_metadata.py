#!/usr/bin/env python3

import ctypes
import ctypes.util
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 4:
    fail(f"Usage: {sys.argv[0]} <metadata-file> <section> <key>")

metadata_path = Path(sys.argv[1])
wanted_section = sys.argv[2]
wanted_key = sys.argv[3]

if not metadata_path.is_file():
    fail(f"Metadata file not found: {metadata_path}")

library_name = ctypes.util.find_library("glib-2.0")
if library_name is None:
    fail("GLib 2.0 is required to parse Flatpak metadata.")

glib = ctypes.CDLL(library_name)
glib.g_key_file_new.restype = ctypes.c_void_p
glib.g_key_file_load_from_file.argtypes = [
    ctypes.c_void_p,
    ctypes.c_char_p,
    ctypes.c_int,
    ctypes.POINTER(ctypes.c_void_p),
]
glib.g_key_file_load_from_file.restype = ctypes.c_int
glib.g_key_file_get_string.argtypes = [
    ctypes.c_void_p,
    ctypes.c_char_p,
    ctypes.c_char_p,
    ctypes.POINTER(ctypes.c_void_p),
]
glib.g_key_file_get_string.restype = ctypes.c_void_p
glib.g_key_file_free.argtypes = [ctypes.c_void_p]
glib.g_error_free.argtypes = [ctypes.c_void_p]
glib.g_free.argtypes = [ctypes.c_void_p]

key_file = glib.g_key_file_new()
error = ctypes.c_void_p()

try:
    loaded = glib.g_key_file_load_from_file(
        key_file,
        str(metadata_path).encode(),
        0,
        ctypes.byref(error),
    )
    if not loaded:
        fail("Flatpak metadata is not a valid GLib key file.")

    current_section = ""
    matching_keys = 0
    for raw_line in metadata_path.read_text(encoding="utf-8").splitlines():
        stripped_line = raw_line.strip()
        if stripped_line.startswith("[") and stripped_line.endswith("]"):
            current_section = stripped_line[1:-1]
            continue
        if current_section == wanted_section and "=" in raw_line:
            key = raw_line.split("=", 1)[0].strip()
            if key == wanted_key:
                matching_keys += 1

    if matching_keys != 1:
        fail(
            f"Expected exactly one [{wanted_section}] {wanted_key} key, "
            f"found {matching_keys}."
        )

    value_pointer = glib.g_key_file_get_string(
        key_file,
        wanted_section.encode(),
        wanted_key.encode(),
        ctypes.byref(error),
    )
    if not value_pointer:
        fail(f"Missing [{wanted_section}] {wanted_key} value.")

    try:
        print(ctypes.string_at(value_pointer).decode("utf-8"))
    finally:
        glib.g_free(value_pointer)
finally:
    if error.value:
        glib.g_error_free(error)
    glib.g_key_file_free(key_file)
