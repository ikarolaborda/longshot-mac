## Longshot Experimental for Apple silicon

Download and unzip **Longshot-Experimental-Installer.zip**. Open the installer and select a previously built Longshot game folder containing your own game files and prepared Metal resources. The local build uses the Xcode command-line tools and the same Homebrew build dependencies as the Mac port. The installer carries a local ad hoc signature.

The installer builds in a temporary directory and installs **Longshot Experimental.app** in Applications, or in your user Applications folder if needed. On first install it copies committed save slots, account data, game options and cheat settings from the stable or Metal Preview profile with the newest save. Existing experimental progress takes precedence on later installs. The saves and settings for the experimental app live in **~/Library/Application Support/Longshot Experimental**.

This release includes the native Metal renderer, low-latency and adaptive graphics modes, keyboard and mouse controls, cheats and story-reward fixes from the Metal preview branch. It adds shader warm-up for running and fighting in Hyrule Field, bounded reuse of gate textures and background preparation on return visits. Choose **Graphics → Adaptive 144 FPS** for adaptive frame pacing.

Experimental build 2 prepares the mesh pipelines seen in Gerudo Fortress and Gerudo Training Ground during shader warm-up. The first launch can take longer while Metal prepares these pipelines. Audio starts with the first block and buffers 30 ms when the output queue runs dry.

In three 1080p runs per build on an M5 Max with a 240 Hz LG display, the median worst freeze on repeat Hyrule Field arrival fell from 187 to 92 ms. Field performance rose from 88 to 94 displayed FPS, including generated frames. The slowest second delivered 63 frames. Median repeat time to confirmed movement increased from 4.30 to 4.51 seconds. Sustained 120 FPS remains a target.
