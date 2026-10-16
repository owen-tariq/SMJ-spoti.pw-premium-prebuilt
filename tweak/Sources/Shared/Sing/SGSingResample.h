// The worker's way between the source's rate and the model's (SGSingFormat.h): a rational, polyphase,
// Kaiser-windowed-sinc resampler for whole windows of stereo interleaved PCM. Each window is resampled on
// its own, with nothing kept between windows and silence assumed beyond its ends, so that exactly
// outFrames come out of exactly inFrames (inFrames * outRate == outFrames * inRate) and a timeline of
// windows can never drift; the half-second overlap-add in SGStemWindowProcessor.swift weights the few
// edge samples this leaves imprecise down to nothing. Deterministic: the same input gives the same bits.
// Off-render only (Create allocates); Process is pure arithmetic and reentrant for one resampler.
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct SGSingResampler SGSingResampler;
// Both rates must be SGSingSupportedRate; the same rate twice copies exactly.
SGSingResampler *SGSingResamplerCreate(uint32_t inRate, uint32_t outRate);
void SGSingResamplerDestroy(SGSingResampler *resampler);
// False, and nothing written, unless inFrames * outRate == outFrames * inRate and both are nonzero.
bool SGSingResamplerProcess(const SGSingResampler *resampler, const float *stereoIn, uint32_t inFrames,
                            float *stereoOut, uint32_t outFrames);
