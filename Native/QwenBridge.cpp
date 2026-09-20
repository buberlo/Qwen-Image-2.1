#include "QwenBridge.h"
#include "stable-diffusion.h"
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <string>
#include <mach/mach.h>
#include <os/proc.h>
#include <TargetConditionals.h>

struct qi_engine {
    std::mutex lifetime;
    sd_ctx_t *context = nullptr;
    std::atomic<bool> cancelled{false};
    std::string error;
};
// The upstream progress callback is global: there must only be one active job.
static std::mutex runtime_mutex;
qi_engine *qi_create(void) { return new qi_engine(); }
void qi_prepare(qi_engine *e) { e->cancelled = false; e->error.clear(); }
void qi_cancel(qi_engine *e) {
    e->cancelled = true;
    std::lock_guard<std::mutex> guard(e->lifetime);
    if (e->context) sd_cancel_generation(e->context, SD_CANCEL_ALL);
}
void qi_unload(qi_engine *e) {
    sd_ctx_t *context = nullptr;
    {
        std::lock_guard<std::mutex> guard(e->lifetime);
        context = e->context;
        e->context = nullptr;
    }
    if (context) free_sd_ctx(context);
}
void qi_destroy(qi_engine *e) { if (e) { qi_unload(e); delete e; } }
const char *qi_error(qi_engine *e) { return e->error.c_str(); }

bool qi_load(qi_engine *e, qi_model_paths paths, bool editing) {
    qi_unload(e);
    if (e->cancelled) { e->error = "Cancelled"; return false; }
    try {
        std::lock_guard<std::mutex> runtime(runtime_mutex);
        sd_ctx_params_t p;
        sd_ctx_params_init(&p);
        p.diffusion_model_path = paths.diffusion;
        p.llm_path = paths.encoder;
        p.llm_vision_path = editing ? paths.vision : nullptr;
        p.vae_path = paths.vae;
        p.n_threads = 4;
        p.backend = "metal";
        // iOS has unified memory. CPU offload alone cannot make these weights fit.
        p.params_backend = "disk";
        p.max_vram = "3"; // Managed buffers only; NOT a total process memory limit.
        p.enable_mmap = true;
        p.disable_prefetch = true;
        p.eager_load = false;
        p.flash_attn = true;
        p.diffusion_flash_attn = true;
        sd_ctx_t *context = new_sd_ctx(&p);
        {
            std::lock_guard<std::mutex> guard(e->lifetime);
            e->context = context;
            if (context && e->cancelled) sd_cancel_generation(context, SD_CANCEL_ALL);
        }
        if (!context) e->error = "Model loading failed. Inspect the device console for memory or model errors.";
        if (e->cancelled) e->error = "Cancelled";
        return context && !e->cancelled;
    } catch (const std::exception &error) {
        e->error = error.what();
        return false;
    }
}

bool qi_generate(qi_engine *e, const char *prompt, int64_t seed,
                 const uint8_t *reference_rgb, qi_progress progress,
                 void *user, qi_image *output) {
    *output = {};
    if (!e->context || e->cancelled) { e->error = "Cancelled or model not loaded"; return false; }
    std::lock_guard<std::mutex> runtime(runtime_mutex);
    struct ProgressContext {
        qi_engine *engine;
        qi_progress callback;
        void *user;
    } progressContext{e, progress, user};
    sd_set_progress_callback([](int step, int total, float time, void *opaque) {
        auto *p = static_cast<ProgressContext *>(opaque);
        // Upstream resets its cancellation flag at sampling entry. Reassert a
        // cancellation made during prompt encoding at the next step boundary.
        if (p->engine->cancelled) sd_cancel_generation(p->engine->context, SD_CANCEL_ALL);
        if (p->callback) p->callback(step, total, time, p->user);
    }, &progressContext);
    struct CallbackReset { ~CallbackReset() { sd_set_progress_callback(nullptr, nullptr); } } reset;
    sd_image_t *images = nullptr;
    int count = 0;
    auto release = [&] {
        if (images) {
            for (int i = 0; i < count; ++i) free(images[i].data);
            free(images);
        }
    };
    try {
        sd_img_gen_params_t p;
        sd_img_gen_params_init(&p);
        p.prompt = prompt;
        p.negative_prompt = "";
        p.width = 512;
        p.height = 512;
        p.seed = seed;
        p.batch_count = 1;
        p.sample_params.sample_method = EULER_SAMPLE_METHOD;
        p.sample_params.scheduler = sd_get_default_scheduler(e->context, EULER_SAMPLE_METHOD);
        p.sample_params.sample_steps = 40;
        p.sample_params.guidance.txt_cfg = 6.0f;
        p.vae_tiling_params.enabled = true;
        p.vae_tiling_params.tile_size_x = 256;
        p.vae_tiling_params.tile_size_y = 256;
        sd_image_t reference{512, 512, 3, const_cast<uint8_t *>(reference_rgb)};
        if (reference_rgb) { p.ref_images = &reference; p.ref_images_count = 1; }
        bool ok = generate_image(e->context, &p, &images, &count);
        if (!ok || e->cancelled || count != 1 || !images || !images[0].data) {
            e->error = e->cancelled ? "Cancelled" : "Generation failed. Inspect the device console.";
            release(); return false;
        }
        auto &image = images[0];
        if (image.width != 512 || image.height != 512 || (image.channel != 3 && image.channel != 4)) {
            e->error = "Unexpected output dimensions or format"; release(); return false;
        }
        *output = {image.data, 512, 512, static_cast<int>(image.channel)};
        image.data = nullptr;
        release();
        return true;
    } catch (const std::exception &error) {
        e->error = error.what(); release(); return false;
    }
}
void qi_free_image(qi_image *image) { free(image->pixels); *image = {}; }
uint64_t qi_memory_bytes(void) {
    task_vm_info_data_t info{};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&info), &count) != KERN_SUCCESS) return 0;
    return info.phys_footprint;
}
uint64_t qi_available_memory_bytes(void) {
#if TARGET_OS_IPHONE
    return os_proc_available_memory();
#else
    return 0;
#endif
}
