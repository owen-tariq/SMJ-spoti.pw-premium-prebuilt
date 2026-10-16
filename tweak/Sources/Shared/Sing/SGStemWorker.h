// Worker callbacks run off the render thread. context remains owned by the caller until Finished.
#pragma once
#include <stdbool.h>
#include <stdint.h>
enum { SGStemLoading = 1, SGStemReady, SGStemFinished, SGStemFailed };
// Read returns a stereo frame count (at most 1024), zero while idle/paused, or -1 when cancelled.
// metadata is generation, track, source frame, format. No PCM is written outside this process.
typedef int32_t (*SGStemRead)(void *context, float *pcm, uint64_t *metadata);
// Write returns 1 when accepted, 0 when the generation has ended, -1 on a transport failure.
typedef int32_t (*SGStemWrite)(void *context, const float *pcm, uint32_t frames,
                              uint64_t generation, uint64_t track, uint64_t sourceFrame, uint32_t format);
typedef void (*SGStemStatus)(void *context, int32_t status);
// Converts one whole window of stereo interleaved PCM between the source's rate and the model's: exactly
// outFrames from exactly inFrames, or false and nothing written (SGSingResample.h's Process, behind the
// resampler the caller made). Off the render thread; the caller keeps both resamplers until Finished.
typedef bool (*SGStemResample)(void *resampler, const float *in, uint32_t inFrames, float *out, uint32_t outFrames);
// Loads the compiled Core ML model at modelPath (or shares the one still warm) and separates windows of
// windowFrames of the source, a hop of hopFrames apart (SGSingFormat.h's geometry at the source's rate).
// With toModel and fromModel, each window goes through resample to the model's window before the model
// and its vocals back to windowFrames after; both NULL, the source is at the model's rate and windowFrames
// must be the model's window. A model made for another window fails. Returns an owned cancellation handle,
// or NULL below iOS 18. Cancel releases that handle exactly once. Finished is called once even when
// cancellation interrupts load.
void *SGStemWorkerStart(void *context, const char *modelPath, uint32_t windowFrames, uint32_t hopFrames,
                       SGStemResample resample, void *toModel, void *fromModel,
                       SGStemRead read, SGStemWrite write, SGStemStatus status);
void SGStemWorkerCancel(void *handle, int32_t unload);
// Drops the warm model at once, for memory, heat, or a model about to be removed.
void SGStemWorkerPurge(void);
