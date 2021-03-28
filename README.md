# DSubs client

This is the DSubs client executable source code. DSubs is a multiplayer sensor-focused
submarine simulator.   
Forum link: https://www.subsim.com/radioroom/showthread.php?p=2598851

## Build-time dependencies

* DMD compiler 2.093.1 (http://downloads.dlang.org/releases/2020/)
* dsubs_common (https://github.com/Boris-Barboris/dsubs_common)
* fork of DerelictSFML2 (https://github.com/Boris-Barboris/DerelictSFML2)
* anything else is handled by dub build system.

## Run-time dependencies

* fork of SFML (https://github.com/Boris-Barboris/SFML)
* fork of CSFML (https://github.com/Boris-Barboris/CSFML)
* fork of OpenAL (https://github.com/Boris-Barboris/openal-soft)

If you are trying to build it on windows, all dll dependencies are pre-build by me and placed in libs-win-x64 folder. This readme will not be covering the process of building the dependencies as it involves a lot of Visual Studio and CMake work.   
If you are trying to build them on Linux, I have a couple of example command histories that I had to perform
to build SFML-related stuff, in the folder "linux_build_examples". Pre-built shared libraries for Arch-linux are in "dsubs_libs" folder, they may work out-of-the-box on your distro.

## Developing on Windows

* Download and install the compiler: http://downloads.dlang.org/releases/2020/dmd-2.093.1.exe
* Download and install C++ redist for VS 2015: https://www.microsoft.com/en-US/download/details.aspx?id=48145
* Create "dsubs" folder in the place of your liking.
* In the dsubs folder clone the following repos:
    * dsubs_client repo: git@github.com:Boris-Barboris/dsubs_client.git
    * dsubs_common repo: git@github.com:Boris-Barboris/dsubs_common.git
    * DerelictSFML2 fork repo: git@github.com:Boris-Barboris/DerelictSFML2.git
* You should now have 3 folders. Open CMD or powershell and enter "dsubs_client" folder.
* Execute winrun.cmd script.
* If it fails to build and run the client, open an issue, so we can fix the documentation.

## Developing on Linux

* Download and install the compiler using script: https://dlang.org/install.html. It behaves like python virtualenv, so you need to activate it before trying to invoke dub/dmd.
```bash
mkdir -p ~/dlang && wget https://dlang.org/install.sh -O ~/dlang/install.sh && \
    bash ~/dlang/install.sh install dmd-2.093.1
source ~/dlang/dmd-2.093.1/activate
```
* Create "dsubs" folder in the place of your liking.
* In the dsubs folder clone the following repos:
    * dsubs_client repo: git@github.com:Boris-Barboris/dsubs_client.git
    * dsubs_common repo: git@github.com:Boris-Barboris/dsubs_common.git
    * DerelictSFML2 fork repo: git@github.com:Boris-Barboris/DerelictSFML2.git
* You should now have 3 folders. Enter "dsubs_client" folder in your shell.
* Execute run.sh script:   
```./run.sh -c prod```
* If it fails to build and run the client, open an issue, so we can fix the documentation.

## Source editing and debugging recommendations

Visual Studio Code with code-d and Trailing Spaces plugins are recommended.
I do not know how to debug it under Windows without switching to Visual Studio with dlang plugin, which is very sensitive to code structure and compiler versioning.   
Code-d often has troubles with auto-discovering dependency folders, so auto-completion is broken. I use explicit include-paths in vscode workspace settings in order to force what I need. Example part of global vscode settings.json:
```
...
"d.stdlibPath": [
        "/home/boris/dlang/dmd-2.093.1/src/phobos",
        "/home/boris/dlang/dmd-2.093.1/src/druntime/import"
    ],
...
```
dsubs_ws.code-workspace file that I have created in dsubs folder:
```
{
	"folders": [
		{
			"path": "."
		}
	],
	"settings": {
		"d.projectImportPaths": [
			"/home/boris/src/dsubs/DerelictSFML2/source/",
			"/home/boris/.dub/packages/derelict-cl-3.2.0/derelict-cl/source",
			"/home/boris/.dub/packages/derelict-util-2.0.6/derelict-util/source",
			"/home/boris/.dub/packages/derelict-al-1.0.3/derelict-al/source",
			"/home/boris/.dub/packages/standardpaths-0.8.1/standardpaths/source",
			"/home/boris/src/dsubs/dsubs_client/source/",
			"/home/boris/src/dsubs/dsubs_common/source/",
			"/home/boris/.dub/packages/gfm-6.2.13/gfm/math"
		],
		"debug.node.autoAttach": "off"
	}
}
```
These paths are version- and os-specific, you'll have to change them to fit your filesystem structure.

Debugging on linux can be performed using mainstream gdb or gdbgui tools.