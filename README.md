# zig-fsrs

## Zig implementation of [FSRS-6 flashcard review scheduling algorithm](https://expertium.github.io/Algorithm.html).

### Usage

1. Add `fsrs` dependency to `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/tensorush/zig-fsrs.git
```

2. Use `fsrs` dependency in `build.zig`:

```zig
const fsrs_dep = b.dependency("fsrs", .{
    .target = target,
    .optimize = optimize,
});
const fsrs_mod = fsrs_dep.module("fsrs");

const root_mod = b.createModule(.{
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "fsrs", .module = fsrs_mod },
    },
});
```
