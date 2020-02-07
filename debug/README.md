# Kernel Debug

## Prerequisites

### Development machine
* Windows
* Visual Studio 2017/2019 with [RadeonAsmDebugger](https://github.com/vsrad/radeon-asm-tools#installation) extension

### Remote machine
* Linux
* Perl
* [.NET Core Runtime 3.1](https://dotnet.microsoft.com/download/dotnet-core/3.1)
* [RadeonAsmDebugServer](https://github.com/vsrad/radeon-asm-tools#installation)
* [libplugintercept](https://github.com/vsrad/debug-plug-hsa-intercept)
* [Tensile](https://github.com/ROCmSoftwarePlatform/Tensile/wiki/Dependencies)

A symbolic link to `libplugintercept.so` needs to be created in `/opt/rocm/lib`.

## Debugging a test case

### Remote machine

1. Build a client executable with the configuration that you want to debug:

```sh
mkdir build
cd build
python3 ../Tensile/bin/Tensile ../Tensile/Tests/extended/?/?.yaml .
```

2. Copy the generated kernel source to your development machine: it is usually located in
`1_BenchmarkProblems/*/00_Final/source/assembly/*.s` for assembly kernels and in
`1_BenchmarkProblems/*/00_Final/source/Kernels.cpp` for source kernels.

3. Launch `RadeonAsmDebugServer`.

### Development machine

1. Open `KernelDebug.sln` in Visual Studio.

2. Add the kernel sources (`.s`, `.cpp`) to the project.

3. Go to *Tools* -> *RAD Debug* -> *Options* and click the *Edit* button.

4. In the *General* tab, set *Remote Machine Address* to the IP address of your remote machine.

5. In the Debugger tab, set *Working Directory* to the absolute path to `build/`.

6. Press *Apply* to save the changes.

7. Open the kernel source file and set a breakpoint somewhere in the code.

8. Start debugging by pressing F5.

9. Go to *Tools* -> *RAD Debug* -> *Open Visualizer* to open debug visualizer and view the values of SGPRs and VGPRs.

## Notes

The debugger operates by intercepting a code object load and substituting the code object with one
compiled from a modified source. In the source code, a short code snippet is injected at the breakpoint location,
which dumps the watches and aborts the kernel.

This approach is essentially *pseudo-debugging*, since the breakpoint is handled entirely in software.

One of the advantages of this approach is that a watch can be set for any expression (for instance,
`hc_get_workitem_id(0)` in the source kernel), not just a variable name or a register.

However, there's a number of things you should keep in mind:

1. The inserted plug evaluates all watches. Side effects, if any, may affect kernel behavior.

2. Since the wave is immediately terminated upon hitting a breakpoint,
if the result hasn't been written to the output tensor yet, the host validation will fail.

3. Stepping doesn't follow control flow, it simply goes to the next line.
Lanes that are inactive based on the `EXEC` mask, however, are highlighted.

4. Loops are terminated on the first iteration.
To stop at an `N`th iteration, you can set the *Counter* in *Visualizer* to `N`.

5. Invalid watch expressions and invalid breakpoint locations result in a compilation error,
which can be observed in the *Debug Server* output.
