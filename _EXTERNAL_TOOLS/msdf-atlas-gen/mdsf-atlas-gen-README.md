This guide assumes you are using a mac. Since if you're working on Metal projects... you are likely in the Apple ecosystem anyway...
# Source
- This tool is from this repository https://github.com/Chlumsky/msdf-atlas-gen
- The author provides .exe for windows, if you are on mac, I have already compiled a copy of it for you here in this folder (where this README lives).
- If you want to build it yourself please see mac build instructions

# Usage instructions
- You will need `.ttf` files that you intend to use as the font. The command generates a `.png` and and `.json` file. These filenames MUST MATCH and is what you used in MetalPlayground to reference the file by. (Unless you modify the setup yourself)
- Drop your .ttf files into this folder (where this README lives) next to the `msdf-atlas-gen` binary. Then `cd` into this folder as well and run the following command:
`msdf-atlas-gen -font <font-filename>.ttf -imageout <fontname>.png -json <fontname>.json -size 128 -pxrange 8`
- Make sure `<fontname>` is the same for png and json outputs.
- Size is the msdf font texture size, so if your font has many details, consider increasing it.
- Apparently it's best to keep pxrange between 4 and 8? But feel free to experiment and check with the community on pest practices.
- For additional command explanations, refer to the original msdf-atlas-gen repository
- Once generated, import the `.png` and `.json` files into your project and reference in code by the fontname that you have named those files with.
- The resulting .json, .png, are to be placed into the `Metal Playground Shared/Resources` folder

# Mac build instructions
- If you don't have `cmake` just install via homebrew `brew install cmake`
- Assume you have a temporary workspace folder on your desktop or documents folder. We will call this empty folder `build-mdsf-tool`
- First, create your temporary empty workspace folder and `cd` into it.
- In your temp workspace folder clone the following two repositories
	- `git clone https://github.com/Chlumsky/msdf-atlas-gen.git`
	- `git clone https://github.com/microsoft/vcpkg.git`
- Run `./vcpkg/bootstrap-vcpkg.sg`
- Run `export VCPKG=/<your-path-to>/vcpkg` to set for this terminal sessions
- Next, `cd` into the `msdf-atlas-gen` folder and run the following
	- `git submodule update --init`
	- `cmake .`
	- `make`
- The output for mac would be in the `msdf-atlas-gen/bin` folder