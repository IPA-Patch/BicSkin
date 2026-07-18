// Frida investigation agent — runs inside the target iOS process.
//
// Compile: `make agent`   (bunx frida-compile frida/agent.ts -o frida/dist/agent.js)
// Attach:  `make attach`  (uv run frida -U -f $(TARGET_BUNDLE_ID) -l frida/dist/agent.js --no-pause)
//
// Frida 17 API. Static `Module.findBaseAddress` / `Module.findExportByName`
// were removed — use `Process.findModuleByName(...)` and the returned
// instance's `.findExportByName(...)` / `.getExportByName(...)`.

console.log(`[agent] loaded (frida ${Frida.version})`);

// TODO: replace with your target's Mach-O basename (typically the app's
// CFBundleExecutable). Used by every hook installer below.
const TARGET_MODULE = "YourApp";

const target = Process.findModuleByName(TARGET_MODULE);
if (target) {
    console.log(`[agent] ${TARGET_MODULE} base=${target.base} size=${target.size}`);
} else {
    console.log(`[agent] ${TARGET_MODULE} not mapped yet`);
}

// ---------------------------------------------------------------------------
// Example ObjC swizzle — log every -[UIViewController viewDidAppear:].
// Uncomment to arm.
// ---------------------------------------------------------------------------
//
// Interceptor.attach(
//     ObjC.classes.UIViewController["- viewDidAppear:"].implementation,
//     {
//         onEnter(args) {
//             const self = new ObjC.Object(args[0]);
//             console.log(`[viewDidAppear] ${self.$className}`);
//         },
//     },
// );

// ---------------------------------------------------------------------------
// Example C-symbol trace — log every open(2) call via libsystem_kernel.
// Uncomment to arm. Frida 17 API: fetch the module, then ask it for the
// export (no more `Module.findExportByName(null, "open")`).
// ---------------------------------------------------------------------------
//
// const kernel = Process.findModuleByName("libsystem_kernel.dylib");
// const openAddr = kernel?.findExportByName("open");
// if (openAddr) {
//     Interceptor.attach(openAddr, {
//         onEnter(args) {
//             console.log(`[open] ${args[0].readCString()}`);
//         },
//     });
// }
