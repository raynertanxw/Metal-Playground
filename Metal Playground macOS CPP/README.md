#IMPT SETUP INFO
Outside of these folders, at the $(PROJECT_DIR) level, there is a metal-cpp and metal-cpp-extensions folders.
These are grabbed from Apple's metal-cpp project, publicly available.
They need to be added in order for the #include <Metal/Metal.hpp> and other files in order to work.

You can set the Header Search Paths to those two folders.
You also need to, under the target's build phases, link binary with libraries, Metal, MetalKit, and Foundation frameworks.
You may possible need QuartzCore.

To create the target. Create an empty SwiftUI App. Then delete everything, replace with the main.cpp
No need to link because the linker will just search for int main() inside the target sources.
Additionally, you need to clear the code signing entitlements.
