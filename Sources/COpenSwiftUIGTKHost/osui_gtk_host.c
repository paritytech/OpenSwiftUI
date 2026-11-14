//
//  osui_gtk_host.c
//  COpenSwiftUIGTKHost

#include "osui_gtk_host.h"

#include <gtk/gtk.h>

typedef struct {
    const OSUIGTKHostOptions *options;
    const OSUIGTKHostCallbacks *callbacks;
    void *context;
    GtkWidget *area;
    int width;
    int height;
    double scale;
} Host;

static void host_update_size(Host *host) {
    int width = gtk_widget_get_width(host->area);
    int height = gtk_widget_get_height(host->area);
    GtkNative *native = gtk_widget_get_native(host->area);
    GdkSurface *surface = native ? gtk_native_get_surface(native) : NULL;
    double scale = surface ? gdk_surface_get_scale(surface) : 1.0;
    if (width == host->width && height == host->height && scale == host->scale) {
        return;
    }
    host->width = width;
    host->height = height;
    host->scale = scale;
    host->callbacks->resize(host->context, width, height, scale);
}

static void host_draw(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer data) {
    Host *host = data;
    host_update_size(host);
    host->callbacks->draw(host->context, cr, width, height);
}

static gboolean host_tick(GtkWidget *widget, GdkFrameClock *clock, gpointer data) {
    Host *host = data;
    host_update_size(host);
    double time = (double)gdk_frame_clock_get_frame_time(clock) / 1e6;
    if (host->callbacks->tick(host->context, time)) {
        gtk_widget_queue_draw(widget);
    }
    return G_SOURCE_CONTINUE;
}

static bool gesture_is_touch(GtkGestureDrag *gesture) {
    return gtk_gesture_single_get_current_sequence(GTK_GESTURE_SINGLE(gesture)) != NULL;
}

static void host_pointer(Host *host, GtkGestureDrag *gesture, OSUIPointerPhase phase, double dx, double dy) {
    double x = 0, y = 0;
    gtk_gesture_drag_get_start_point(gesture, &x, &y);
    host->callbacks->pointer(host->context, phase, x + dx, y + dy, gesture_is_touch(gesture));
}

static void host_drag_begin(GtkGestureDrag *gesture, double x, double y, gpointer data) {
    Host *host = data;
    host->callbacks->pointer(host->context, OSUI_POINTER_BEGAN, x, y, gesture_is_touch(gesture));
}

static void host_drag_update(GtkGestureDrag *gesture, double dx, double dy, gpointer data) {
    host_pointer(data, gesture, OSUI_POINTER_MOVED, dx, dy);
}

static void host_drag_end(GtkGestureDrag *gesture, double dx, double dy, gpointer data) {
    host_pointer(data, gesture, OSUI_POINTER_ENDED, dx, dy);
}

static void host_drag_cancel(GtkGesture *gesture, GdkEventSequence *sequence, gpointer data) {
    host_pointer(data, GTK_GESTURE_DRAG(gesture), OSUI_POINTER_CANCELLED, 0, 0);
}

static void host_activate(GtkApplication *application, gpointer data) {
    Host *host = data;
    GtkWidget *window = gtk_application_window_new(application);
    gtk_window_set_title(GTK_WINDOW(window), host->options->title);
    gtk_window_set_default_size(GTK_WINDOW(window), host->options->width, host->options->height);

    host->area = gtk_drawing_area_new();
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(host->area), host_draw, host, NULL);
    gtk_widget_add_tick_callback(host->area, host_tick, host, NULL);

    GtkGesture *drag = gtk_gesture_drag_new();
    g_signal_connect(drag, "drag-begin", G_CALLBACK(host_drag_begin), host);
    g_signal_connect(drag, "drag-update", G_CALLBACK(host_drag_update), host);
    g_signal_connect(drag, "drag-end", G_CALLBACK(host_drag_end), host);
    g_signal_connect(drag, "cancel", G_CALLBACK(host_drag_cancel), host);
    gtk_widget_add_controller(host->area, GTK_EVENT_CONTROLLER(drag));

    gtk_window_set_child(GTK_WINDOW(window), host->area);
    gtk_window_present(GTK_WINDOW(window));
}

static int host_capture(Host *host) {
    const OSUIGTKHostOptions *options = host->options;
    const double scale = 2.0;
    if (g_mkdir_with_parents(options->capture_directory, 0755) != 0) {
        g_printerr("OpenSwiftUIGTK: cannot create %s\n", options->capture_directory);
        return 1;
    }
    host->callbacks->resize(host->context, options->width, options->height, scale);
    for (int frame = 0; frame < options->capture_frames; frame++) {
        host->callbacks->tick(host->context, (double)frame / (double)options->capture_fps);
        cairo_surface_t *surface = cairo_image_surface_create(
            CAIRO_FORMAT_ARGB32, (int)(options->width * scale), (int)(options->height * scale));
        cairo_t *cr = cairo_create(surface);
        cairo_scale(cr, scale, scale);
        host->callbacks->draw(host->context, cr, options->width, options->height);
        cairo_destroy(cr);
        char *path = g_strdup_printf("%s/frame-%04d.png", options->capture_directory, frame);
        cairo_status_t status = cairo_surface_write_to_png(surface, path);
        cairo_surface_destroy(surface);
        if (status != CAIRO_STATUS_SUCCESS) {
            g_printerr("OpenSwiftUIGTK: cannot write %s: %s\n", path, cairo_status_to_string(status));
            g_free(path);
            return 1;
        }
        g_free(path);
    }
    return 0;
}

int osui_gtk_host_run(const OSUIGTKHostOptions *options, const OSUIGTKHostCallbacks *callbacks, void *context) {
    Host host = {.options = options, .callbacks = callbacks, .context = context, .scale = 1.0};
    if (options->capture_directory != NULL) {
        return host_capture(&host);
    }
    GtkApplication *application = gtk_application_new(options->application_id, G_APPLICATION_NON_UNIQUE);
    g_signal_connect(application, "activate", G_CALLBACK(host_activate), &host);
    int status = g_application_run(G_APPLICATION(application), 0, NULL);
    g_object_unref(application);
    return status;
}
