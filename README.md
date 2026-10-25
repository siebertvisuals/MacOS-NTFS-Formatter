# NTFS Formatter for macOS

A single-window app to format an external disk or USB drive (exFAT, FAT32…) as **NTFS** from a Mac.
Everything is included in the app: **nothing to install** (no Homebrew, no Terminal).

## For users

1. Download `NTFSFormatter.zip` from the [Releases](../../releases) tab and double-click it to unzip.
2. Drag **NTFSFormatter** into your *Applications* folder.
3. **First launch:** the app is not notarized by Apple, so macOS blocks it the first time.
   - Double-click the app: a warning appears, close it.
   - Open **System Settings → Privacy & Security**, scroll to the bottom,
     click **Open Anyway** next to "NTFSFormatter", then enter your password.
   - You only have to do this once.
4. Plug in your disk, select it in the list, click **Format as NTFS…** and confirm.

> ⚠️ **Everything on the disk is erased**, partitions included. This cannot be undone.
> Only external disks are listed: your Mac's own disk never appears.

## Good to know

- macOS mounts NTFS **read-only**. The disk is meant for Windows; to write to it from a Mac
  you need a third-party driver (Paragon, Tuxera, iBoysoft, or ntfs-3g with macFUSE).
- This version is for **Apple Silicon Macs** (M1 and later), macOS 13 or newer.
- Provided as is, without warranty.

## For developers

```bash
brew install ntfs-3g-mac     # source of mkntfs, copied into the app by build.sh
xcode-select --install       # Swift compiler
./build.sh                   # produces NTFSFormatter.app and NTFSFormatter.zip
```

`build.sh` bundles `mkntfs` and its libraries into `Contents/Resources/ntfs` and rewrites their paths.
The app then runs the format through the system password prompt (`osascript … with administrator privileges`).

A command-line version is also available: `format_ntfs.sh`.

## Licenses

The code of this app (Swift interface, scripts) is released under the **MIT license**: see [LICENSE](LICENSE).

The app bundles third-party components that keep their own licenses:
`mkntfs` / `libntfs-3g` (NTFS-3G) under **GPL v2**, and `libintl` (gettext) under **LGPL**.
Their texts are in `NTFSFormatter.app/Contents/Resources/licenses/`.
NTFS-3G source code: <https://github.com/tuxera/ntfs-3g>.
