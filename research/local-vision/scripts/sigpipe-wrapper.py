#!/usr/bin/env python3
# SIGPIPE-ignoring exec shim.
#
# WHY: llama.cpp's mtmd video helper feeds the encoded video into an ffmpeg
# subprocess from a dedicated feeder thread doing a bare fwrite(). When the
# model has read the frames it needs and tears the pipeline down, ffmpeg exits
# and closes its stdin; the still-writing feeder then hits SIGPIPE. The helper
# never installs SIG_IGN, so the default disposition kills the whole process
# (observed as exit code 141 mid-video). Setting SIGPIPE -> SIG_IGN turns that
# into a harmless EPIPE. SIG_IGN survives execv(), so it covers the child.
#
# This is a workaround; the proper fix is a one-line signal(SIGPIPE, SIG_IGN)
# (or per-write MSG_NOSIGNAL) upstream in tools/mtmd/mtmd-helper.cpp.
#
#   Usage: sigpipe-wrapper.py <program> [args...]
import signal, os, sys
signal.signal(signal.SIGPIPE, signal.SIG_IGN)
os.execv(sys.argv[1], sys.argv[1:])
