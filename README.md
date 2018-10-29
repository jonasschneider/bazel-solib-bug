# _solib directory placement within runfiles misses external solibs

I'm trying to build a plug-in `.so` to be later dynamically loaded from runfiles.
However, I'm running into an issue in the case where that `.so` uses `linkshared=1` and itself depends on some other libraries (I can reproduce it with both cc_library and cc_import deps). The rpaths set in the .so can get out of sync with the actual filesystem tree, causing load-time link errors. The core issue seems to be the relative path from the .so within the runfiles to the `_solib_{cpu}` directory within the runfiles.


https://github.com/bazelbuild/bazel/issues/6481

Demonstrating the issue (see full repro repo) with Bazel 0.18.0:
```
$ cat main.sh
script="${BASH_SOURCE[0]}"
echo "Accessing libplugin.so via .runfiles/__main__/external/child:"
ldd $script.runfiles/__main__/external/child/libplugin.so | grep appcode
echo "Accessing libplugin.so via .runfiles/child:"
ldd $script.runfiles/child/libplugin.so | grep appcode

$ bazel run //:main
[...]
Accessing libplugin.so via .runfiles/__main__/external/child:
	libappcode.so => /root/.cache/bazel/_bazel_root/665bedfccc4ce93904668a7f2f06c5ca/execroot/__main__/bazel-out/k8-fastbuild/bin/main.runfiles/__main__/external/child/../../_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild/libappcode.so (0x00007f19c3cb8000)
Accessing libplugin.so via .runfiles/child:
	libappcode.so => /root/.cache/bazel/_bazel_root/665bedfccc4ce93904668a7f2f06c5ca/execroot/__main__/bazel-out/k8-fastbuild/bin/main.runfiles/child/../../_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild/libappcode.so (0x00007f4e4454b000)

$ bazel run //subdir:main
[...]
Accessing libplugin.so via .runfiles/__main__/external/child:
	libappcode.so => /root/.cache/bazel/_bazel_root/665bedfccc4ce93904668a7f2f06c5ca/execroot/__main__/bazel-out/k8-fastbuild/bin/subdir/main.runfiles/__main__/external/child/../../_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild/libappcode.so (0x00007f382cc13000)
Accessing libplugin.so via .runfiles/child:
	libappcode.so => not found
```

(In my real use-case, libplugin.so is a Python extension module, which in turn depends on a third-party library libappcode.so that's only available as a .so, hence libplugin.so can't be linked fully statically.)

Checking with `patchelf` reveals the source of the loading issue, the rpath of `libplugin.so`:
```
$ patchelf --print-rpath bazel-bin/external/child/libplugin.so
$ORIGIN/../../_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild
```
It looks like the rpath assumes that libplugin.so is being loaded using the `__main__/external` location. It is correct for that case (a modified test case that also moves `libplugin.so` into a subdirectory within `child` indeed modifies the rpath correctly). However it breaks when both of these conditions are true:
1. `libplugin.so` is loaded using the new `.runfiles/child` syntax instead of `.runfiles/__main__/external/child`
2. The main executable is not at the top of the workspace (since otherwise the rpath "accidentally" resolves to the _solib path _outside_ of the runfiles, which happens to work as well but is brittle)

This seems like a bug -- does that mean there should be two rpath entries, one for each loading location? Or am I doing something wrong here?


# Full command lines
```
$ cat main.sh
script="${BASH_SOURCE[0]}"
echo "Accessing libplugin.so via .runfiles/__main__/external/child:"
ldd $script.runfiles/__main__/external/child/libplugin.so | grep appcode
echo "Accessing libplugin.so via .runfiles/child:"
ldd $script.runfiles/child/libplugin.so | grep appcode

$ bazel run //:main
INFO: Build options have changed, discarding analysis cache.
INFO: Analysed target //:main (10 packages loaded).
INFO: Found 1 target...
Target //:main up-to-date:
  bazel-bin/main
INFO: Elapsed time: 0.504s, Critical Path: 0.00s
INFO: 0 processes.
INFO: Build completed successfully, 2 total actions
INFO: Build completed successfully, 2 total actions
Accessing libplugin.so via .runfiles/__main__/external/child:
	libappcode.so => /root/.cache/bazel/_bazel_root/665bedfccc4ce93904668a7f2f06c5ca/execroot/__main__/bazel-out/k8-fastbuild/bin/main.runfiles/__main__/external/child/../../_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild/libappcode.so (0x00007f19c3cb8000)
Accessing libplugin.so via .runfiles/child:
	libappcode.so => /root/.cache/bazel/_bazel_root/665bedfccc4ce93904668a7f2f06c5ca/execroot/__main__/bazel-out/k8-fastbuild/bin/main.runfiles/child/../../_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild/libappcode.so (0x00007f4e4454b000)

$ bazel run //subdir:main
INFO: Analysed target //subdir:main (1 packages loaded).
INFO: Found 1 target...
Target //subdir:main up-to-date:
  bazel-bin/subdir/main
INFO: Elapsed time: 0.123s, Critical Path: 0.01s
INFO: 0 processes.
INFO: Build completed successfully, 4 total actions
INFO: Build completed successfully, 4 total actions
Accessing libplugin.so via .runfiles/__main__/external/child:
	libappcode.so => /root/.cache/bazel/_bazel_root/665bedfccc4ce93904668a7f2f06c5ca/execroot/__main__/bazel-out/k8-fastbuild/bin/subdir/main.runfiles/__main__/external/child/../../_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild/libappcode.so (0x00007f382cc13000)
Accessing libplugin.so via .runfiles/child:
	libappcode.so => not found
```

```
$ patchelf --print-rpath bazel-bin/external/child/libplugin.so
$ORIGIN/../../_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild

root@52a241feb3ed:/top/mujoco-py/vendor/repro# find bazel-bin/main.runfiles
bazel-bin/main.runfiles
bazel-bin/main.runfiles/child
bazel-bin/main.runfiles/child/libplugin.so
bazel-bin/main.runfiles/__main__
bazel-bin/main.runfiles/__main__/main.sh
bazel-bin/main.runfiles/__main__/main
bazel-bin/main.runfiles/__main__/_solib_k8
bazel-bin/main.runfiles/__main__/_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild
bazel-bin/main.runfiles/__main__/_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild/libappcode.so
bazel-bin/main.runfiles/__main__/external
bazel-bin/main.runfiles/__main__/external/child
bazel-bin/main.runfiles/__main__/external/child/libplugin.so
bazel-bin/main.runfiles/MANIFEST

root@52a241feb3ed:/top/mujoco-py/vendor/repro# find bazel-bin/subdir/main.runfiles
bazel-bin/subdir/main.runfiles
bazel-bin/subdir/main.runfiles/child
bazel-bin/subdir/main.runfiles/child/libplugin.so
bazel-bin/subdir/main.runfiles/__main__
bazel-bin/subdir/main.runfiles/__main__/main.sh
bazel-bin/subdir/main.runfiles/__main__/subdir
bazel-bin/subdir/main.runfiles/__main__/subdir/main
bazel-bin/subdir/main.runfiles/__main__/_solib_k8
bazel-bin/subdir/main.runfiles/__main__/_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild
bazel-bin/subdir/main.runfiles/__main__/_solib_k8/_U@child_S_S_Clibplugin.so___Uexternal_Schild/libappcode.so
bazel-bin/subdir/main.runfiles/__main__/external
bazel-bin/subdir/main.runfiles/__main__/external/child
bazel-bin/subdir/main.runfiles/__main__/external/child/libplugin.so
bazel-bin/subdir/main.runfiles/MANIFEST
```
