#!/bin/sh
# ---------------------------------------------------------------------------
# Snippet to paste into /etc/init.d/rcS, RIGHT AFTER the "./jz-media-app &"
# line (not before it! - see README, "Why not just edit /etc/init.d/rcS
# directly").
#
# Adjust the /mnt/mtdblock7/... paths to your own persistent partition if
# it's named differently.
# ---------------------------------------------------------------------------

(
  L=/tmp/deferred_https_fix.log
  echo "=== deferred https-fix setup $(date) ===" > "$L"

  # The data partition on this platform mounts ASYNCHRONOUSLY and might not
  # be ready right at boot - wait until the wrapper file actually shows up,
  # instead of assuming the partition is already mounted.
  i=0
  while [ ! -f /mnt/mtdblock7/mplayer_wrapper.sh ]; do
    i=$((i+1))
    echo "waiting attempt $i" >> "$L"
    sleep 1
    if [ "$i" -ge 30 ]; then
      echo "GAVE UP - the partition with the wrapper never showed up" >> "$L"
      cp "$L" /mnt/mtdblock7/deferred_https_fix.log 2>>"$L"
      exit 0
    fi
  done

  # Short "settle down" pause after detecting the file - operations right
  # after a partition first appears sometimes fail for no obvious reason.
  sleep 5

  if [ -f /mnt/mtdblock7/real/mplayer ]; then
    echo "real/mplayer already exists, skipping the copy" >> "$L"
  else
    mkdir -p /mnt/mtdblock7/real 2>>"$L"
    cp /mnt/mtdblock7/mplayer.real /mnt/mtdblock7/real/mplayer 2>>"$L"
    chmod +x /mnt/mtdblock7/real/mplayer 2>>"$L"
  fi

  mount --bind /mnt/mtdblock7/mplayer_wrapper.sh /usr/jz-project/mplayer 2>>"$L"
  echo "mount exit: $?" >> "$L"
  cp "$L" /mnt/mtdblock7/deferred_https_fix.log 2>/dev/null
) &
