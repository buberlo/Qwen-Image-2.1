#ifndef QWEN_BRIDGE_H
#define QWEN_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct qi_engine qi_engine;
typedef void (*qi_progress)(int step, int total, float seconds, void *user);
typedef struct {
    const char *diffusion;
    const char *encoder;
    const char *vision;
    const char *vae;
} qi_model_paths;
typedef struct {
    uint8_t *pixels;
    int width;
    int height;
    int channels;
} qi_image;
// Run load/generate/unload on one serial worker. cancel is safe from any thread.
qi_engine *qi_create(void);
void qi_destroy(qi_engine *engine);
void qi_prepare(qi_engine *engine);
bool qi_load(qi_engine *engine, qi_model_paths paths, bool editing);
bool qi_generate(qi_engine *engine, const char *prompt, int64_t seed,
                 const uint8_t *reference_rgb, qi_progress progress,
                 void *user, qi_image *output);
void qi_cancel(qi_engine *engine);
void qi_unload(qi_engine *engine);
void qi_free_image(qi_image *image);
const char *qi_error(qi_engine *engine);
uint64_t qi_memory_bytes(void);
uint64_t qi_available_memory_bytes(void);
#ifdef __cplusplus
}
#endif
#endif
