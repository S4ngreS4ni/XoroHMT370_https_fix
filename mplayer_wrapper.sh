#!/bin/sh
#
# mplayer_wrapper.sh
# ---------------------------------------------------------------------------
# Transparent mplayer wrapper for the ListenLive firmware (SkyTC KMP510 /
# Ingenic JZ4760(B) platform - Xoro HMT350/HMT370, Envivo, Arnova, Wiwa,
# Roxcore, Xenta, Disgo, Pearl, Otek, Aigo, Full-Join, Foxman, VDuck, and
# other rebrands of the same platform).
#
# What this does:
#   This mplayer build (SVN-r32106-snapshot-4.1.2) has no HTTPS support
#   compiled in ("No stream found to handle url https://..."). This script
#   catches every call that contains an https:// address, spins up a local
#   proxy (curl + nc) that does the encrypted connection for it, and hands
#   the real mplayer a plain, local http://127.0.0.1:PORT/ address instead.
#   Plain http:// addresses (and local file paths, from MediaPlayer/SD
#   card/Samba) go through untouched.
#
# IMPORTANT - why the "real" binary MUST be named exactly "mplayer":
#   jz-media-app stops playback via system("killall -9 mplayer"), i.e. BY
#   PROCESS NAME, not by PID. If you rename the real binary (e.g. to
#   mplayer.real), killall will never find it, and the "back"/"stop" button
#   will stop working (audio keeps playing in the background forever).
#   That's why the real binary has to live in a SEPARATE directory, but
#   under the SAME filename "mplayer" - see REAL below.
#
# NOTE on argument quoting:
#   jz-media-app invokes this whole thing via system(), which runs it as
#   "/bin/sh -c '<command line>'" - so by the time this script sees "$@",
#   any local file path with a space in it (e.g. "My Song.mp3") arrives as
#   ONE argument. We rebuild the argument list below by wrapping each one
#   in single quotes before re-evaluating it, so those spaces survive the
#   trip through $REAL. If a filename ever contains a literal single quote
#   character this will break - a risk we're accepting since it's a much
#   rarer case than spaces in filenames.
#
# Installation: see README.md in this repo.
# ---------------------------------------------------------------------------

# Path to the ORIGINAL mplayer binary, moved to a different directory but
# kept under the SAME filename "mplayer" (see comment above). Adjust this
# to your own persistent partition (see README, "Find your persistent
# partition").
REAL=/mnt/mtdblock7/real/mplayer

# Path to a statically-linked curl binary that actually runs on your SoC
# (see README, "Get curl for your SoC").
CURL=/mnt/mtdblock7/curl

# Local port used by the proxy. One port is enough since the radio only
# plays one station at a time - every new call kills the previous proxy
# before starting a new one.
PORT=9000

# Clean up any leftover processes from a previous playback before starting
# a new one (otherwise a dead-but-still-listening nc could keep the port
# blocked).
for p in /proc/[0-9]*; do
  cmd=$(cat "$p/cmdline" 2>/dev/null)
  case "$cmd" in
    *nc-l*${PORT}*|*curl-skL*) kill -9 "${p#/proc/}" 2>/dev/null ;;
  esac
done

newargs=""
for arg in "$@"; do
  case "$arg" in
    https://*)
      # Set up a dumb, forever-looping HTTP server on the local port.
      # Every connection: slap on an HTTP 200 header, then pipe through
      # curl -L (which follows redirects - the old busybox wget can't,
      # and a lot of stations these days bounce you from one CDN node to
      # another).
      ( while true; do
          { printf 'HTTP/1.0 200 OK\r\nContent-Type: audio/mpeg\r\n\r\n'; "$CURL" -skL "$arg"; } | nc -l -p "$PORT"
        done ) &
      arg="http://127.0.0.1:${PORT}/"
      ;;
  esac
  # Wrap this argument in single quotes so spaces (and other IFS-splittable
  # characters) survive being re-parsed by `eval` below, instead of just
  # gluing raw strings together with spaces (which silently breaks any
  # filename that contains a space).
  newargs="$newargs '$arg'"
done

# KEY BIT #1: exec, not a plain background call. exec replaces this script's
# process with the real mplayer under the SAME PID AND THE SAME FILENAME
# (since $REAL is literally named "mplayer") - that's what makes
# system("killall -9 mplayer") in jz-media-app actually find and kill it
# when you press "back".
#
# KEY BIT #2: eval here re-parses $newargs so that the single-quoted chunks
# we built above become correctly separated arguments again, spaces and
# all - instead of "exec ... $newargs" (no quotes), which would just
# word-split everything on spaces and mangle any path/filename that has
# one in it.
eval "exec \"\$REAL\" $newargs"
