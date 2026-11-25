## New in v3.2.0-mac.6

Open **Pause → Collection**, the tab with the Gold Skulltula tokens. The three stones, six medallions and ocarina songs appear on the tab as icons. **Command+J** or a right-stick click opens their names and earned status. Your recorded Scarecrow tune appears after the twelve standard songs.

**All 100 Gold Skulltulas** shows the gold token and its count of 100 on the original grid. **All Equipment** shows the Gerudo Pass and the three Great Fairy gifts, including the Gift of Halved Damage. Selecting one displays its original model and description. Their story rewards still use the save’s earned progress.

## New in v3.2.0-mac.5

Metal fills the game window by default. Resizing a window or moving it between displays updates the camera and HUD to match the drawable. A fixed aspect ratio chosen in Graphics still keeps its proportions.

Pause and open **Collection**. Press **Command+J** or click the **right stick** to open the quest collection. Press the same shortcut to return. The page shows three spiritual stones, six medallions and twelve standard ocarina songs with their game artwork. **All Equipment** fills the stones and medallions. **All ocarina songs** fills the songs. Each entry shows whether it is earned in this save or borrowed from a cheat. Scarecrow’s Song has its own entry for the tune you record with Bonooru.

With All Equipment enabled, the Load screen also shows all nine relic icons. The preview reads the save caption without changing it. Turning the cheats off shows earned progress again.

## New in v3.2.0-mac.4

Metal now prepares known Kakariko Village and Hyrule Field mesh pipelines before play and remembers newly encountered mesh pipelines for later launches. On an M5 Max, a copied adult save walked through the Kakariko gate, returned, and crossed again. In two offscreen runs of the update, the first exit took 5.69 and 7.32 seconds, compared with 11.75 seconds in mac.3. The repeats took 4.52 and 4.50 seconds, compared with 4.89 seconds. Both timings include the transition until Link can move in Hyrule Field. The longest frame on the final build was 396 ms, compared with 3.73 seconds in mac.3.

Press **Command+,** and open **Gameplay** to change dialogue text size, dialogue background contrast, or the size of the ocarina staff (85–125%). Under **Graphics → HUD layout → Custom**, you can resize and move hearts and magic, action and item buttons, and the minimap. Button and ocarina prompts follow the active input device and its bindings.

Choose **Equipment → Set 1 → Save current equipment** in the Mac menu bar. Press **7**, **8**, or **9** during gameplay to equip a saved set. Each set remembers worn gear and the item on ZR. Bottle selections follow the slot, so drinking a potion or releasing bugs changes what the set shows and equips. Child and adult Link have separate sets. You can rename a set in the Equipment menu or assign a different key or controller button under **Settings → Controls**.

With **All Equipment** enabled, the pause inventory identifies loaned gear as **Borrowed** and story rewards as **Earned**. The Mac menu **Equipment → Inventory status** lists both. Copied saves replayed Darunia awarding the Goron Bracelet and Impa teaching Zelda’s Lullaby.

## Mac controls and previous changes

This Mac release uses the stable Longshot v3.2.0 game code, including the controller trigger, save-loading, first adult night, and high-frame-rate movie fixes. Movies keep their sound timing and 16:9 shape. The upstream release also lists driver fixes specific to Windows and Vulkan. [Upstream release notes](https://git.magicbean.dev/MagicBeanDev/Longshot/releases/tag/v3.2.0)

Press F1 or Insert in the game window to open Longshot Settings. On a Mac keyboard, use Fn+F1 if F1 changes the screen brightness. You can also choose Longshot Settings… from the Longshot menu or press Command+comma. Use Tab to change pages and the arrow keys to select a setting. The keypad 5 shortcut still opens the cheat menu.

In Graphics, turn on Adaptive 144 FPS to target up to 144 displayed frames per second. The target follows the screen when its refresh rate is lower. When game frames fall behind on a high-refresh screen, supported Macs can use MetalFX to draw a frame between two game frames. If the GPU is the limit, the game can lower its 3D resolution and raise it again when the GPU has time. Movement and animation use elapsed time.

For quicker control response, open Graphics and select Prefer responsiveness. The Mac menu bar also has this setting under Frame Rate. Metal gives a new control input priority on the next game frame. On supported Macs, it adds MetalFX frames when they improve frame spacing. It starts with a limit of 120 FPS or the display refresh rate, whichever is lower. On displays that support 144 Hz, the game tries 144 FPS when it has time to draw more frames. It keeps that limit when more frames reach the display and both frame spacing and control response stay steady.

Adaptive mode is on for new installations. The app keeps an existing frame rate or interpolation preference. Choose a manual frame rate or change MetalFX Frame Interpolation to leave adaptive mode. You can also change these settings from Frame Rate in the Mac menu bar.

The Mac benchmark uses a copy of an adult Kakariko Village save. Link runs ten times, swings his drawn sword ten times, turns the camera, and attacks while advancing. The test then loads Hyrule Field and follows a 14-second route on foot. It records Link’s position and checks game time against real time.

On an M5 Max with a 1920 × 1080 game window on a 240 Hz LG UltraGear+, 95% of the 24 control inputs reached a displayed game frame within 40 ms with Prefer responsiveness and 58 ms with Adaptive 144 FPS. The median time to sustained visible running motion was 71 ms and 93 ms, respectively. Sword swings measured 61 ms and 85 ms. The image check detected all ten runs in each mode and ten of ten swings in Prefer responsiveness versus nine of ten in Adaptive. All six idle checks stayed below the threshold.

With pixel sampling enabled in both modes, Hyrule Field averaged 104 displayed FPS with Prefer responsiveness and 117 with Adaptive. Both had a 12.5 ms 95th-percentile frame gap and ran at real-time game speed. Village frame gaps were 16.7 ms and 12.5 ms, respectively. Both modes had a first-use stall of about half a second when Metal compiled a mesh shader. These runs did not sustain 144 FPS. Pixel sampling adds rendering overhead.

The controller timer starts when the test sends the input. It stops when Metal displays the first game frame submitted after the game reads that input. The frame-spacing measurement includes the game’s frames and frames added by MetalFX. These timings cover the game and the Mac display system. Physical controller and panel latency need separate equipment.

The two routes are in `scripts/mac/tests/village_response.py` and `scripts/mac/tests/field_traversal.py`. Set `HOS_METAL_TIMING=2` for displayed-frame timestamps. For a small image sample from each SDR drawable, also set `HOS_METAL_PIXEL_TRACE` to a new file and pass that path to the village script with `--pixels`.

In an adult Death Mountain Crater test on an M5 Max and a 240 Hz LG display, the manual 144 FPS cap delivered 74 to 84 displayed frames per second. Adaptive mode delivered 115 to 120 across three samples of 600 displayed frames, including frames from MetalFX. The game produced 70 frames per second on average during the 22-second adaptive test. The game clock ran within 1% of real time during steady play. A second game window was open.

This preview updates an existing Longshot game build for Apple silicon. Unzip the installer, open it, and choose the folder containing your game files. It installs Longshot in Applications. The executable has a local ad hoc signature. Finder may require approval in Privacy & Security.

The Mac build disables no-clip flight. Double-tapping Shift (controller B) used to activate it, letting Q and P move Link vertically. Space still jumps, Q sends L, and P sends R. Page Up and Page Down adjust the debug camera’s height.

Longshot grabs the mouse when its game window gains focus. Press Option+§ to release the pointer. Click back into the game or switch back to its window to grab it again. Q and P send the L and R shoulder buttons after switching apps and after closing the keypad 5 cheat menu.

If you already own all five bottles, diving for Ruto’s Letter at Lake Hylia now puts it in the first empty bottle. If all five contain something, empty one and dive again. To give it to King Zora, stand on the platform facing him, equip the letter bottle in Items, and use it with ZR. He returns the empty bottle when he opens the way to Zora’s Fountain.

Enable “Infinite magic (double meter)” in the keypad 5 cheat menu to keep Link’s meter full when casting spells or firing magic arrows. Magic arrows still use arrows from the quiver. You can still earn both Great Fairy magic upgrades during the story.

Open the keypad 5 cheat menu and enable “100× attack damage” to multiply damage from Link’s hits by 100. It takes effect on the next hit. Enemies can still block attacks, and Link takes his usual damage.

With “All ocarina songs” enabled in the keypad 5 cheat menu, the ocarina can play the twelve standard melodies. Once Bonooru accepts your eight-note tune, you can play it in the field. With the ocarina out, hold the control shown beside “Check songbook.” For the D-pad Right prompt, hold Right Arrow on the keyboard. For the ZL prompt, hold the number-row 1 key. Use the right stick to select the scarecrow icon at the far right of the top row. The “Scarecrow Song” entry shows your recorded notes. Put the ocarina away and take it out again after changing the cheat. Song lessons and Bonooru’s adult quest still award their items during the story.

Open the keypad 5 cheat menu and enable “Perfect score after one target hit.” One hit earns 10/10 in the Market or Kakariko shooting gallery, or 2,000 points in Gerudo horseback archery. Finish the round to collect any prize you qualify for. A round with no hits scores zero.

Press the mouse wheel once to hold ZR. Press it again to leave aiming and put your ranged weapon away. The minus key still works as a held ZR button. Moving the mouse up raises your aim, even when your controller uses inverted stick controls. The mouse has its own vertical inversion setting.

With “Infinite rupees (1,000)” enabled in the keypad 5 menu, you can pay for items and keep a full wallet throughout the purchase. Turn it off to spend rupees normally.

With All Equipment enabled, child Link can lift and throw Bomb Flowers before Darunia gives him the Goron Bracelet. Adult Link can lift heavy rocks with borrowed gauntlets. The borrowed Gold Scale also lets Link dive deeper. The story still records when Link earns each item.

Keypad 5 opens the cheat menu. “Hyrule map, dungeon maps and compasses” reveals unexplored locations on the world map and shows dungeon floor plans and compass markers. Press M to open the map. On a local map, press F (Y on the controller) to switch to the world map. You can still earn maps and compasses from their chests.

Pressing A on Save in the System menu now opens the confirmation screen and shows a preview of the current scene. You can save from that screen and load your progress after you restart Longshot.

With All Equipment enabled, Link now holds the Fairy Ocarina in Impa’s Zelda’s Lullaby lesson when his equipped ocarina slot is empty. The game keeps any ocarina already equipped. The visual fix only supplies the handheld model and its holder. The game still awards the song through the lesson.

The game displays the Longshot grappling hook icon in Finder, the Dock, and the About window. The About window credits Nintendo, the Longshot and Hookshot teams, and the Metal renderer contributors. It links to the [Mac repository](https://github.com/ikarolaborda/longshot-mac) and [GitHub Sponsors](https://github.com/sponsors/ikarolaborda).

Space jumps, Q and P send L and R, and the number-row 1 and minus send ZL and ZR. F and left click attack (Y). M opens the map (Minus). The arrow keys send the matching D-pad directions. Hold right click to send ZL for targeting. Keypad 5 opens the cheat menu.

Metal now checks the textures a draw can use when it can track the shader's input buffers reliably. It keeps full validation for texture handle tables that can share memory through another address. In a 15-second offscreen comparison on an M5 Max at 2048 × 1152, Death Mountain Trail improved from 48 to 58 FPS and Kakariko Village from 33 to 41 FPS. The warm crossing into Kakariko took about 5.8 seconds in both builds. A separate game window was running during the comparison. First visits can still stall while Metal compiles a pipeline or uploads textures. The build uses the Ocarina of Time shader service for game text and subtitles.

The equipment cheat uses temporary inventory reads. On a fresh save, the inventory screen can still omit borrowed gear and bottles, and the HUD can show only earned heart containers. In the Kokiri Sword chest test, the game awarded the sword with every cheat enabled. Earlier versions could write permanent ownership into a save. This release leaves existing saves in place. Keep a backup from before enabling those older cheats.
