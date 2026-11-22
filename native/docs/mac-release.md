This preview updates an existing Longshot game build for Apple silicon. Unzip the installer, open it, and choose the folder containing your game files. It installs Longshot in Applications. The executable has a local ad hoc signature. Finder may require approval in Privacy & Security.

Keypad 5 opens the cheat menu. “Hyrule map, dungeon maps and compasses” reveals unexplored locations on the world map and shows dungeon floor plans and compass markers. Press M to open the map. On a local map, press F (Y on the controller) to switch to the world map. You can still earn maps and compasses from their chests.

Pressing A on Save in the System menu now opens the confirmation screen and shows a preview of the current scene. You can save from that screen and load your progress after you restart Longshot.

With All Equipment enabled, Link now holds the Fairy Ocarina in Impa’s Zelda’s Lullaby lesson when his equipped ocarina slot is empty. The game keeps any ocarina already equipped. The visual fix only supplies the handheld model and its holder. The game still awards the song through the lesson.

The game displays the Longshot grappling hook icon in Finder, the Dock, and the About window. The About window credits Nintendo, the Longshot and Hookshot teams, and the Metal renderer contributors. It links to the [Mac repository](https://github.com/ikarolaborda/longshot-mac) and [GitHub Sponsors](https://github.com/sponsors/ikarolaborda).

Space jumps, Q and P send L and R, and the number-row 1 and minus send ZL and ZR. F and left click attack (Y). M opens the map (Minus). The arrow keys send the matching D-pad directions. Hold right click to send ZL for targeting. Keypad 5 opens the cheat menu.

Metal now checks the textures a draw can use when it can track the shader's input buffers reliably. It keeps full validation for texture handle tables that can share memory through another address. In a 15-second offscreen comparison on an M5 Max at 2048 × 1152, Death Mountain Trail improved from 48 to 58 FPS and Kakariko Village from 33 to 41 FPS. The warm crossing into Kakariko took about 5.8 seconds in both builds. A separate game window was running during the comparison. First visits can still stall while Metal compiles a pipeline or uploads textures. The build uses the Ocarina of Time shader service for game text and subtitles.

The equipment cheat uses temporary inventory reads. On a fresh save, the inventory screen can still omit borrowed gear and bottles, and the HUD can show only earned heart containers. In the Kokiri Sword chest test, the game awarded the sword with every cheat enabled. Earlier versions could write permanent ownership into a save. This release leaves existing saves in place. Keep a backup from before enabling those older cheats.
