This guide assumes you are using a mac with clang installed for c compilation. Since you're working on Metal projects... you are likely in the Apple ecosystem with Xcode installed anyway...

# Sources

- This project uses tsoding's no-build system. You can find the source here: https://github.com/tsoding/nob.h
  - The idea is we use C to compile C. So the build tool "nob" simply checks if there are changes to itself (recompiles if needed) and then runs itself.
  - I've customised this such that the nob itself would auto run a sprite packer functionality. The base of the code logic was from an old raylib project that I had.
- In order to manipulate images, and to do so in C (such that there are no dependencies), I had to use Sean Barrett's STB libraries (https://github.com/nothings/stb), in particular:
  - `stb_image.h`
  - `stb_image_write.h`
  - `stb_rect_pack.h`
  - These are all added to `nob_src`, which contains all third party helper files needed to compile the nob tool.
- Lastly, since this was from an old raylib project, I used some helper functions from raylib. I've extracted them out into `nob_src/raylib_extracts.h` from source. For more info on raylib: https://github.com/raysan5/raylib

# Mac usage instructions

- First you will need to bootstrap the initial build of the nob tooling.
- `cd` to this folder (where this README lives) and run the following command
  - `clang nob.c -o nob`
- After which, the nob binary will be compiled and you just need to, from this same folder, run the following command
  - `./nob`
  - This would rebuild itself if you make modifications to `nob.c` and then run itself
- Running `nob` would do the sprite packing, taking the files under `resources/mainatlas` and spitting out the `.png` and `.txt` assets for your main sprite atlas.
- You can then place this into the `Metal Playground Shared/Resources` folder for use.
- The `.hash` file generated is for saving effort of rebuilding the atlas if there are no changes.

# Modifying / Adding new atlases

- Should you chose to add new atlas, you can follow the pattern from the main atlas example. Some areas where you need to change code:
  - Near the top of `nob.c` there are define statements for max sprites, image file, meta file, and size for the atlas.
  - This is where we set the name of the atlas output files, the max atlas size and max number of sprites in the atlas. Feel free to change this to what is suitable for you.
  - Should you want to add more sprite atlases to pack, simply create suitable named set of these 4 defines for your new atlas.
  - `nob.c` under the `execute_cmd_sprite_packer()` use that to call `build_texture_atlas` for these additional atlases that you may want to use.

