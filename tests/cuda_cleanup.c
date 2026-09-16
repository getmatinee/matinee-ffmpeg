// Copyright (C) 2023-2026 Swissmakers GmbH
// Author: Michael André Reber
// License: AGPL-3.0-or-later
// https://github.com/getmatinee/matinee

// Fail the second texture allocation through the real CUDA-frame helper.
// Fake driver calls let the compile-only CUDA job check cleanup without a GPU.
#include "libavfilter/cuda/host_util.c"

static int created, destroyed;

static CUresult CUDAAPI create_texture(CUtexObject *texture, const CUDA_RESOURCE_DESC *resource,
                                      const CUDA_TEXTURE_DESC *description,
                                      const CUDA_RESOURCE_VIEW_DESC *view)
{
    if (++created == 2)
        return (CUresult)2; // Out of memory; minimal nv-codec headers omit the name.
    *texture = 7;
    return CUDA_SUCCESS;
}

static CUresult CUDAAPI destroy_texture(CUtexObject texture)
{
    if (texture != 7) return (CUresult)1;
    destroyed++;
    return CUDA_SUCCESS;
}

static CUresult CUDAAPI error_text(CUresult result, const char **text)
{
    *text = "injected texture allocation failure";
    return CUDA_SUCCESS;
}

int main(void)
{
    CudaFunctions cuda = {
        .cuTexObjectCreate = create_texture,
        .cuTexObjectDestroy = destroy_texture,
        .cuGetErrorName = error_text,
        .cuGetErrorString = error_text,
    };
    FFCUDAFrame frame = { 0 };
    AVFrame *input = av_frame_alloc();
    if (!input) return 2;
    input->width = input->height = 16;
    input->format = AV_PIX_FMT_NV12;
    input->linesize[0] = input->linesize[1] = 16;
    int ret = ff_make_cuda_frame(NULL, &cuda, 1, &frame, input,
                                av_pix_fmt_desc_get(AV_PIX_FMT_NV12));
    av_frame_free(&input);
    if (ret >= 0 || created != 2 || destroyed != 1 || frame.tex[0] || frame.tex[1]) {
        fprintf(stderr, "partial CUDA texture allocation left live handles or lost its error\n");
        return 1;
    }
    puts("PASS partial CUDA texture allocation cleans up exactly once");
    return 0;
}
