//
//  osui_gtk_host.h
//  COpenSwiftUIGTKHost
//
//  A single GTK4 window whose whole surface is drawn by the caller with Cairo.
//  GTK supplies the Wayland surface, the frame clock and pointer/touch input.

#ifndef OSUI_GTK_HOST_H
#define OSUI_GTK_HOST_H

#include <stdbool.h>
#include <stdint.h>

typedef struct _cairo cairo_t;

typedef enum {
    OSUI_POINTER_BEGAN = 0,
    OSUI_POINTER_MOVED = 1,
    OSUI_POINTER_ENDED = 2,
    OSUI_POINTER_CANCELLED = 3,
} OSUIPointerPhase;

typedef struct {
    /// The surface changed size (logical points) or scale.
    void (*resize)(void *context, int width, int height, double scale);
    /// Called once per display frame with the frame clock's time in seconds.
    /// Returns true when the window has to be repainted.
    bool (*tick)(void *context, double frame_time);
    /// Paints the window. The Cairo context is in logical points.
    void (*draw)(void *context, cairo_t *cr, int width, int height);
    /// One primary-button press or touch point, in logical points.
    void (*pointer)(void *context, OSUIPointerPhase phase, double x, double y, bool is_touch);
} OSUIGTKHostCallbacks;

typedef struct {
    const char *application_id;
    const char *title;
    int width;
    int height;
    /// When non-NULL, the window is never shown: frames are painted into an image surface
    /// at `capture_fps` and written to this directory as frame-NNNN.png, then the app quits.
    const char *capture_directory;
    int capture_frames;
    int capture_fps;
} OSUIGTKHostOptions;

/// Runs the GTK main loop until the window closes. Returns the application's exit status.
int osui_gtk_host_run(const OSUIGTKHostOptions *options, const OSUIGTKHostCallbacks *callbacks, void *context);

#endif
