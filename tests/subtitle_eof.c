// Copyright (C) 2023-2026 Swissmakers GmbH
// Author: Michael André Reber
// License: AGPL-3.0-or-later
// https://github.com/getmatinee/matinee

// Exercise the actual CLI subtitle queue before graph initialization, then
// deliver its EOF into a real filter graph. Unused CLI code is linker-discarded.
#include "fftools/ffmpeg_filter.c"

int main(void)
{
    InputFilterPriv input = { 0 };
    AVFilterGraph *graph = avfilter_graph_alloc();
    AVFilterContext *source = NULL, *sink = NULL;
    AVFrame *queued = NULL, *output = av_frame_alloc();
    int ret = 1;
    input.type_src = AVMEDIA_TYPE_SUBTITLE;
    input.sub2video.end_pts = INT64_MAX;
    input.frame_queue = av_fifo_alloc2(2, sizeof(AVFrame *), 0);
    if (!graph || !output || !input.frame_queue)
        goto end;

    if (sub2video_frame(&input.ifilter, NULL, 1) < 0 ||
        av_fifo_can_read(input.frame_queue) != 1) {
        fprintf(stderr, "subtitle EOF was lost before graph initialization\n");
        goto end;
    }
    if (av_fifo_read(input.frame_queue, &queued, 1) < 0 || queued)
        goto end;
    if (avfilter_graph_create_filter(&source, avfilter_get_by_name("buffer"), "source",
            "video_size=2x2:pix_fmt=bgra:time_base=1/1000:pixel_aspect=1/1", NULL, graph) < 0 ||
        avfilter_graph_create_filter(&sink, avfilter_get_by_name("buffersink"), "sink",
            NULL, NULL, graph) < 0 ||
        avfilter_link(source, 0, sink, 0) < 0 || avfilter_graph_config(graph, NULL) < 0)
        goto end;
    input.ifilter.filter = source;
    if (sub2video_frame(&input.ifilter, queued, 0) < 0 ||
        av_buffersink_get_frame(sink, output) != AVERROR_EOF) {
        fprintf(stderr, "queued subtitle EOF did not finish the filter graph\n");
        goto end;
    }
    puts("PASS subtitle EOF queued before graph initialization");
    ret = 0;
end:
    av_frame_free(&queued);
    av_frame_free(&output);
    av_fifo_freep2(&input.frame_queue);
    avfilter_graph_free(&graph);
    return ret;
}
