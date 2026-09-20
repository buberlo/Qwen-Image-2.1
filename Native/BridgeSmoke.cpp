#include "QwenBridge.h"
#include <cstdio>
int main() {
    auto *engine = qi_create();
    qi_prepare(engine);
    qi_cancel(engine);
    qi_model_paths missing{"/nonexistent/diffusion", "/nonexistent/encoder", "/nonexistent/vision", "/nonexistent/vae"};
    if (qi_load(engine, missing, false)) return 1;
    qi_image image{};
    if (qi_generate(engine, "test", 42, nullptr, nullptr, nullptr, &image)) return 2;
    qi_free_image(&image);
    qi_unload(engine);
    qi_destroy(engine);
    if (qi_memory_bytes() == 0) return 3;
    std::puts("Bridge linked; early cancellation and cleanup passed. No model inference tested.");
    return 0;
}
