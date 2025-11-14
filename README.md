# An Exploration into Metal
This is an exploratory project where I try my hand out at making an over simplified render engine using Metal.
I started off wanting to create a simple game, where I kept my game logic in simple c. And then I have various platform layers.
I wanted to try my hand at creating a platform layer for both MacOS and iOS where I can simply draw some primitives, some textured quads, and some text, using Metal. Instead of having wrappers around Vulkan or SDL.
Additionally, I wanted everything of this platform layer to be kept in Xcode, so that I could use native frameworks like GameController and GameKit.

In this project there are:
- 3 main shader types
  - SDF based primitives
  - Single sprite atlas textures
  - MSDF based text
- Drawcalls are batched by shader types automatically,
- Native iOS and native MacOS targets
- Max text, primitives, and textured quad draw limits.

## What NOT to expect:
- Super clean industry practice commits and code.
- 100% bug free.

## What you can use this for:
- A starting point for pet projects.
- A playground to test out some ideas.
- **Use this as your own code! No need for attribution**, I made it open for all to freely use. Since when trying this out myself, I was frustrated with the lack of resources that dove deeper into this specific use-case.
- I personally have used this as a backbone for a c-interoped game project on iOS. Where my core game logic is imported c files, and my platform layer is this barebones rendering engine + some other stuff that interfaces with GameKit, GameController Framework, etc.

# Future ideas / optimisations
- Have a metal-cpp version for iOS target (currently metal-cpp source from apple is only for AppKit not UIKit)
- Figure out how to properly make swift arrays faster, bypassing all safety checks to match performance of metal-cpp
- Extend TextureAtlas shader pipeline to support multiple textures.
- Combine all 3 shaders into 1, and get rid of the draw call type batching system (since there's no longer any need for it).

# External Tools used:
## Font to MSDF font files
- Public github tool (can only run on windows) [https://github.com/Chlumsky/msdf-atlas-gen](https://github.com/Chlumsky/msdf-atlas-gen)
- Download the tool
- `cd` into the directory with the `msdf-atlas-gen` exe
- Place your `.ttf` font file in the same directory
- Run the following command `msdf-atlas-gen -font <font-file>.ttf -imageout <font-name>.png -json <font-name>.json -size 128 -pxrange 8`
- Values to tinker with are `-size` and `-pxrange`, depending on the font, you may want to adjust these. Don't be afraid to go higher in size.
- Sometimes the current values don't give you a crisp enough MSDF result and text can look weird.
- The resulting .json, .png, are to be placed into the `Metal Playground Shared/Resources` folder

## JSON for Modern C++
- Used a JSON library to help with parsing the MSDF font json files.
- Used this github repo [https://github.com/nlohmann/json](https://github.com/nlohmann/json)
- Only used for metal-cpp target, as we don't need this as JSON Codables are built into swift.

## STB_IMAGE
- metal-cpp doesn't have helper funciton to load a texture resource. So had to create a custom loadTexture function.
- So had to use `stb_image.h` from [https://github.com/nothings/stb](https://github.com/nothings/stb) to load the raw bytes from image resources.
- This is to help with all the possible image file formats.
- This is only used for the metal-cpp target, as we don't need this if we have access to Swift's MTKTextureLoader.

