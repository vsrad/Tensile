# Assembly Kernel Debug

## Prerequisites

### Development machine
* Windows
* Visual Studio 2017/2019 with [RadeonAsmDebugger](https://github.com/vsrad/radeon-asm-tools#installation) extension

### Remote machine
* Linux
* Perl (with `liblist-moreutils-perl`)
* [.NET Core Runtime 3.1](https://dotnet.microsoft.com/download/dotnet-core/3.1)
* [RadeonAsmDebugServer](https://github.com/vsrad/radeon-asm-tools#installation)
* [libplugintercept](https://github.com/vsrad/debug-plug-hsa-intercept)
* [Tensile](https://github.com/ROCmSoftwarePlatform/Tensile/wiki/Dependencies)

## Debugging a test case

In the test case `.yaml`, add the following to `GlobalParameters`:

```yaml
DebugKernel: True
```

### Remote machine

1. Build a client executable with the configuration that you want to debug:

```sh
mkdir build
cd build
python3 ../Tensile/bin/Tensile ../Tensile/Tests/extended/?/?.yaml .
```

2. Copy `1_BenchmarkProblems/*/00_Final/source/assembly/*.s` to your development machine.

3. Launch `RadeonAsmDebugServer`.

### Development machine

1. Open `AssemblyDebug.sln` in Visual Studio.

2. Add the kernel source file (`.s`) to the project.

3. Go to *Tools* -> *RAD Debug* -> *Options* and click the *Edit* button.

4. In the *General* tab, set *Remote Machine Address* to the IP address of your remote machine.

5. In the Debugger tab, set *Working Directory* to the absolute path to `build/`.

6. Press *Apply* to save the changes.

7. Open the kernel source file and set a breakpoint somewhere in the code.

8. Start debugging by pressing F5.

9. Go to *Tools* -> *RAD Debug* -> *Open Visualizer* to open debug visualizer and view the values of SGPRs and VGPRs.
