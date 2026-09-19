# ListenLive firmware HTTPS fix for Xoro HMT350 Radio (SkyTC KMP510)

> ⚠️ **Disclaimer:** you're messing with the firmware of your own device
> here, at your own risk. I'm sharing what worked for me, but it might not work for every one.
> If something goes wrong and you end up with a bricked radio, that's not on me. I might try to help if you
> open an Issue, but I can't promise anything. Read the whole README
> (especially the Backup section) before you touch anything.

This is my patch that tackles a problem with the **Xoro HMT350** radio
(SkyTC KMP510, Ingenic JZ4760/JZ4760B) running the ListenLive firmware.

Most online radio stations today are served over HTTPS instead of plain
HTTP, and this radio, running ListenLive firmware
(https://listenlive.nl, author: William Jansen / "penbex"), can't play
those right off the bat, since its mplayer build dates back to around 2010-2013. The
effect: most ListenLive stations just spit out "Server connection failed"
on the screen.

This fix enables the radio to play most HTTPS stations **without recompiling
mplayer**, via a small local proxy running on the device itself, which is
transparent to all of its apps (Internet Radio, TuneIn, Shoutcast,
MediaPlayer, etc.).

This is **not a fork** or a replacement of the ListenLive firmware - it's
just a small add-on to it. All the glory and standing ovations should go
to Mr. William Jansen, the author of the firmware.

## Supported devices

Xoro HMT350 (7 inch model)

**Tested on:** Xoro HMT350 (Model No.: BSI-6636D07HD), ListenLive
firmware 1.52, Ingenic JZ4760B, kernel 2.6.31.3.

If you've successfully run this fix on some other device, feel free to
open an Issue and I'll add it to the list.

## How it works

1. We copy the original `mplayer` binary elsewhere on the device's
   filesystem, keeping its **original filename** (this matters - see
   below).
2. In the original binary's path, we substitute it (via `mount --bind`)
   with a small script that:
   - captures the call arguments,
   - for every argument starting with `https://`, sets up a local,
     one-off proxy server (`curl` + `nc`), which itself makes the
     encrypted connection and forwards the data over plain,
     unencrypted HTTP,
   - replaces the `https://` address with `http://127.0.0.1:PORT/`,
   - and finally `exec`s the real mplayer with that now-safe address.
3. The whole mechanism is transparent. None of the apps on the radio
   know that any swapping took place.

### Why does the filename matter?

`jz-media-app` **doesn't keep track** of the PID of the mplayer process
it launches (it starts it with a plain `system()` call, which doesn't
return one). Instead, when you e.g. press "back" on the device, it
calls:

```c
system("killall -9 mplayer");
system("killall -9 mplayer2");
```

And `killall` looks for the process **by name**, not by PID.

If you substitute `/usr/jz-project/mplayer` with a script that runs the
real binary in the background (with `&`, without `exec`) under a
different name (e.g. `mplayer.real`) - `killall` will never find it. The
station will keep playing forever in the background, and "back" will
only take you to the previous menu without stopping the playback.

Just to be clear about it.

## Installation how-to

### Requirements

- A compatible radio with the ListenLive firmware installed, and telnet
  access (there's a Dropbear/SSH option in Settings, but for me it was
  easier to just stick with telnet).

### Step 1: Find your persistent partition

Connect to your radio via telnet (or SSH, if you set that up). Then:

```
cat /proc/mounts
```

Look for `ext2` entries mounted as `rw` (not `ro`), other than `/` -
usually something like `/mnt/mtdblockN` (N being some number; mine was
`/mnt/mtdblock7`).

Check the free space:

```
df /mnt/mtdblockN
```

You'll need about 15-20MB for curl and the copy of the mplayer binary.
In the steps below, swap `/mnt/mtdblock7` for your own path if it's
different from mine.

### Step 2: Get curl for your SoC

This SoC is a bit fussy about curl binaries - some generic "mipsel"
builds crash with an "Illegal instruction" error, because this older
core doesn't support the newer instruction set (MIPS32r2) many
toolchains target by default.

**The build that worked for me (static, plain mipsel, NOT the musl
variant):**

[stunnel/static-curl](https://github.com/stunnel/static-curl/releases) -
download `curl-linux-mipsel-8.10.0.tar.xz` (skip `-musl` and `-dev`
variants; if the plain one gives you "Illegal instruction", try `-musl`
as a fallback, but it wasn't needed on my unit).

1. Save the tar.xz file on your PC and extract it.
2. Send the `curl` binary to the radio (you can use Samba or, like me,
   an SD card - the radio itself can't `wget` https links, so you have
   to get it there some other way).
3. Copy it to the persistent partition and give it execute permissions:
   ```
   cp /mnt/mmc/curl /mnt/mtdblock7/curl
   chmod +x /mnt/mtdblock7/curl
   ```
4. Compatibility test:
   ```
   /mnt/mtdblock7/curl --version
   ```
   If you see normal output with a version number, you're golden. If
   it's `Illegal instruction`, try a different build.

### Step 3: Swap the original mplayer

```
cp /usr/jz-project/mplayer /mnt/mtdblock7/mplayer.real
mkdir -p /mnt/mtdblock7/real
cp /mnt/mtdblock7/mplayer.real /mnt/mtdblock7/real/mplayer
chmod +x /mnt/mtdblock7/real/mplayer
```

Copy `scripts/mplayer_wrapper.sh` from this repo to
`/mnt/mtdblock7/mplayer_wrapper.sh`. **Open it, check it, and adjust the
paths if you need to** (`REAL` and `CURL` near the top of the file, in
case your partition has a different name).

```
chmod +x /mnt/mtdblock7/mplayer_wrapper.sh
mount --bind /mnt/mtdblock7/mplayer_wrapper.sh /usr/jz-project/mplayer
```

**Test it before moving on to the next step:**
- Play an HTTPS station from the radio's menu.
- Check that the "back" button works correctly (it should return to the
  previous menu AND stop the playback).

If it works - NOICE! Now we need to make this stick across reboots (if
you reboot the radio right now, the change will be gone). Move on to
Step 4.

### Step 4: Autostart after reboot

This is the trickiest part, since we'll be editing the system's boot
file. **Make a full backup before you start tinkering with this** (see
the Backup section below).

**Why not just edit `/etc/init.d/rcS` directly?**
Well, `/etc` on this system is a temporary overlay in RAM (tmpfs),
freshly re-copied from the real partition on every boot. So editing
`/etc/init.d/rcS` the normal way won't survive a reboot. You need to get
to the real file on the system partition by mounting it **a second
time**, at a different mount point:

```
mount -o remount,rw /dev/root /
mkdir -p /mnt/realroot
mount -t ext2 -o rw /dev/mmcblk0p5 /mnt/realroot
```

(The partition number here is `p5`. Check if yours matches via
`cat /proc/partitions`, and look for the partition matching the "VFS:
Mounted root" line from `dmesg`.)

Open `/mnt/realroot/etc/init.d/rcS`, find the `./jz-media-app &` line,
and paste the content of `scripts/rcS-snippet.sh` from this repo **right
after it** (not before!).

Save it, force a physical write to disk, and unmount:

```
sync
sync
umount /mnt/realroot
sync
sync
```

Now reboot the radio. Once it's fully booted, check:

```
cat /mnt/mtdblock7/deferred_https_fix.log
cat /proc/mounts | grep mplayer
```

If the second command shows exactly one line - it worked, congrats.

## Backup and restore

**Do this before Step 4 - really, before you touch anything here at
all.**

Insert an SD card and remount it with write permission, then make a full
disk image with `dd`:

```
mount -o remount,rw,async /mnt/mmc
dd if=/dev/mmcblk0 of=/mnt/mmc/backup_full_disk.img bs=1048576
```

(swap `/mnt/mmc` for your own SD card mount point if it's different;
`/dev/mmcblk0` is usually the internal eMMC memory of the device - check
with `cat /proc/partitions`)

The `dd` command above creates a full image of the disk (bootloader +
all partitions) on your SD card. It's roughly ~2GB and it takes A WHILE.

You should make this backup because, as far as I know, the only way to
restore the device after you fuck it up is the **USB Boot mode** built
into the Ingenic SoC.

Tools for restoration:
[gcwnow/ingenic-boot](https://github.com/gcwnow/ingenic-boot) (Linux).
It will probably require a board-specific config, and it's not a "load
it and you're done" kind of job. Treat it as a last resort.

## Known limitations

- **Stations with weird, dynamic tokenized redirects** might not work
  correctly with this fix.
- **Some AAC streams behind Cloudflare** might need a couple of minutes
  (sometimes more) for the initial connection, before mplayer catches
  the correct stream start point. So these streams do work, just not
  right off the bat. Normal MP3 streams don't have this problem.
- Tested on only one unit of this particular model. Your mileage may
  vary.

## FAQ / Troubleshooting

**"back" doesn't stop the playback despite the fix**
Double-check the filename set in `REAL` inside `mplayer_wrapper.sh`. The
path must end with `/mplayer` exactly - not `mplayer.real`, `mplayer2`,
or anything else. Also make sure the script uses `exec`, not `&`.

## Thankseses

- William Jansen ("penbex") for creating and maintaining the ListenLive
  firmware.

## Boring license stuff

I'm sharing the scripts in this repository under the MIT license - do
whatever you want with them. The ListenLive firmware is a separate
project with its own rules, available at https://listenlive.nl.
