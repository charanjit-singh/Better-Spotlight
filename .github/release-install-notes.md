## Install

1. Download and unzip `BetterSpotlight-{VERSION}.zip`
2. Drag **Better Spotlight.app** to `/Applications`
3. Clear the download quarantine, since this build is ad-hoc signed rather than notarized:

```bash
xattr -dr com.apple.quarantine "/Applications/Better Spotlight.app"
```

4. Open it, then pick your shortcut

Skip step 3 and macOS says *"Apple could not verify Better Spotlight is free of malware."* That is the missing notarization, not the app. You can also approve it after attempting to open it, under System Settings → Privacy & Security → **Open Anyway**. Right-click → Open no longer works, since Apple removed that bypass in macOS 15.

Prefer to watch someone do it? [Fix "Apple could not verify app is free of malware"](https://www.youtube.com/watch?v=biIvAM94b98) covers the same steps in 2 minutes.

Requires macOS 26.5 or later. Universal (Apple Silicon + Intel).

Verify the download with `shasum -a 256 -c BetterSpotlight-{VERSION}.zip.sha256`.
