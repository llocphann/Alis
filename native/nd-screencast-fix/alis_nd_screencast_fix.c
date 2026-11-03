#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <gst/gst.h>
#include <gst/allocators/gstdmabuf.h>

typedef gboolean (*gst_element_link_many_fn)(GstElement *, GstElement *, ...);
typedef GstElementFactory *(*gst_element_factory_find_fn)(const gchar *);
typedef GstElement *(*gst_element_factory_make_fn)(const gchar *, const gchar *);
typedef GstStateChangeReturn (*gst_element_set_state_fn)(GstElement *, GstState);
typedef void (*nm_start_find_fn)(void *, void *, void *, void *, void *);
typedef void (*nm_stop_find_fn)(void *, void *, void *, void *);
typedef guint (*nm_get_state_fn)(void *);

void
nm_device_wifi_p2p_start_find(void *device, void *options, void *cancellable,
                              void *callback, void *user_data)
{
    static nm_start_find_fn real_start_find = NULL;
    static nm_stop_find_fn real_stop_find = NULL;
    static nm_get_state_fn real_get_state = NULL;
    if (!real_start_find)
        real_start_find = (nm_start_find_fn)dlsym(RTLD_NEXT, "nm_device_wifi_p2p_start_find");
    if (!real_stop_find)
        real_stop_find = (nm_stop_find_fn)dlsym(RTLD_NEXT, "nm_device_wifi_p2p_stop_find");
    if (!real_get_state)
        real_get_state = (nm_get_state_fn)dlsym(RTLD_NEXT, "nm_device_get_state");

    /* NM_DEVICE_STATE_DISCONNECTED = 30.
     * In gnome-network-displays 0.99.0, NdWFDP2PProvider in the daemon checks
     * `state > NM_DEVICE_STATE_UNAVAILABLE (20)` and restarts P2P discovery even
     * when the P2P device transitions into PREPARE (40) / CONFIG (50) / ACTIVATED (100)
     * during a stream connection, interrupting GO negotiation and causing packet drops. */
    if (real_get_state && device) {
        guint state = real_get_state(device);
        if (state > 30 && state <= 100) {
            if ((state == 40 || state == 50) && real_stop_find)
                real_stop_find(device, NULL, NULL, NULL);
            return;
        }
    }
    if (real_start_find)
        real_start_find(device, options, cancellable, callback, user_data);
}

static GstPadProbeReturn
pw_src_buffer_probe(GstPad *pad, GstPadProbeInfo *info, gpointer user_data)
{
    (void)pad;
    (void)user_data;
    GstBuffer *buf = GST_PAD_PROBE_INFO_BUFFER(info);
    if (!buf)
        return GST_PAD_PROBE_OK;

    guint n = gst_buffer_n_memory(buf);
    for (guint i = 0; i < n; i++) {
        GstMemory *m = gst_buffer_peek_memory(buf, i);
        if (m && gst_is_dmabuf_memory(m)) {
            int fd = gst_dmabuf_memory_get_fd(m);
            if (fd >= 0) {
                struct stat st;
                if (fstat(fd, &st) == 0 && st.st_size > 16) {
                    if (m->maxsize < (gsize)st.st_size)
                        m->maxsize = (gsize)st.st_size;
                    if (m->size < (gsize)st.st_size)
                        m->size = (gsize)st.st_size;
                }
            }
        }
    }
    if (GST_BUFFER_FLAG_IS_SET(buf, GST_BUFFER_FLAG_CORRUPTED))
        return GST_PAD_PROBE_DROP;

    return GST_PAD_PROBE_OK;
}

/* Detach the buffer arriving at intervideosink from gldownload/glupload/pipewiresrc
 * by copying its mapped pixels into a standalone SystemMemory GstBuffer and
 * immediately unreffing the upstream buffer on gldownload's streaming thread.
 * Without this, intervideosink holds surface->video_buffer (and last-sample)
 * indefinitely, keeping GstGLMemoryEGL -> GstParentBufferMeta -> pipewiresrc's
 * DMABuf alive so PipeWire/Niri never gets its buffer returned after Frame 1. */
static GstPadProbeReturn
inter_sink_copy_probe(GstPad *pad, GstPadProbeInfo *info, gpointer user_data)
{
    (void)pad;
    (void)user_data;
    GstBuffer *buf = GST_PAD_PROBE_INFO_BUFFER(info);
    if (!buf)
        return GST_PAD_PROBE_OK;

    GstMapInfo map;
    if (!gst_buffer_map(buf, &map, GST_MAP_READ))
        return GST_PAD_PROBE_DROP;

    if (map.size == 0) {
        gst_buffer_unmap(buf, &map);
        return GST_PAD_PROBE_DROP;
    }

    GstBuffer *fresh = gst_buffer_new_allocate(NULL, map.size, NULL);
    if (!fresh) {
        gst_buffer_unmap(buf, &map);
        return GST_PAD_PROBE_DROP;
    }

    gst_buffer_fill(fresh, 0, map.data, map.size);
    gst_buffer_unmap(buf, &map);

    gst_buffer_copy_into(
        fresh, buf,
        (GstBufferCopyFlags)(GST_BUFFER_COPY_FLAGS | GST_BUFFER_COPY_TIMESTAMPS),
        0, -1);

    gst_buffer_unref(buf);
    GST_PAD_PROBE_INFO_DATA(info) = fresh;
    return GST_PAD_PROBE_OK;
}

GstElementFactory *
gst_element_factory_find(const gchar *name)
{
    static gst_element_factory_find_fn real_find = NULL;
    if (!real_find)
        real_find = (gst_element_factory_find_fn)dlsym(RTLD_NEXT, "gst_element_factory_find");
    if (!real_find || !name)
        return NULL;

    /* Prefer x264enc over openh264enc in gnome-network-displays so TVs that
     * negotiate H.264 high/main profiles do not fail with not-negotiated. */
    if (g_strcmp0(name, "openh264enc") == 0) {
        GstElementFactory *x264 = real_find("x264enc");
        if (x264) {
            gst_object_unref(x264);
            return NULL;
        }
    }
    return real_find(name);
}

GstElement *
gst_element_factory_make(const gchar *factoryname, const gchar *name)
{
    static gst_element_factory_make_fn real_make = NULL;
    static gst_element_factory_find_fn real_find = NULL;
    if (!real_make)
        real_make = (gst_element_factory_make_fn)dlsym(RTLD_NEXT, "gst_element_factory_make");
    if (!real_find)
        real_find = (gst_element_factory_find_fn)dlsym(RTLD_NEXT, "gst_element_factory_find");
    if (!real_make || !factoryname)
        return NULL;

    if (g_strcmp0(factoryname, "openh264enc") == 0 && real_find) {
        GstElementFactory *x264 = real_find("x264enc");
        if (x264) {
            gst_object_unref(x264);
            return NULL;
        }
    }
    return real_make(factoryname, name);
}

GstStateChangeReturn
gst_element_set_state(GstElement *element, GstState state)
{
    static gst_element_set_state_fn real_set_state = NULL;
    if (!real_set_state)
        real_set_state = (gst_element_set_state_fn)dlsym(RTLD_NEXT, "gst_element_set_state");
    if (!real_set_state)
        return GST_STATE_CHANGE_FAILURE;

    /* Unlock and stop wfd-audio before tearing down the parent RTSP pipeline
     * so NdPulseaudio never disposes in READY (locked) state. */
    if (state == GST_STATE_NULL && element && GST_IS_BIN(element)) {
        GstElement *audio = gst_bin_get_by_name(GST_BIN(element), "wfd-audio");
        if (audio) {
            if (audio != element) {
                gst_element_set_locked_state(audio, FALSE);
                real_set_state(audio, GST_STATE_NULL);
            }
            gst_object_unref(audio);
        }
    }
    return real_set_state(element, state);
}

gboolean
gst_element_link_many(GstElement *element_1, GstElement *element_2, ...)
{
    if (!element_1 || !element_2)
        return FALSE;

    GPtrArray *elems = g_ptr_array_new();
    g_ptr_array_add(elems, element_1);
    g_ptr_array_add(elems, element_2);

    va_list args;
    va_start(args, element_2);
    GstElement *next = NULL;
    while ((next = va_arg(args, GstElement *)) != NULL) {
        g_ptr_array_add(elems, next);
    }
    va_end(args);

    GstElement *first = (GstElement *)g_ptr_array_index(elems, 0);
    GstElement *last = (GstElement *)g_ptr_array_index(elems, elems->len - 1);
    GstElementFactory *first_fac = gst_element_get_factory(first);
    GstElementFactory *last_fac = gst_element_get_factory(last);
    const gchar *first_name = first_fac ? gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(first_fac)) : "";
    const gchar *last_name = last_fac ? gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(last_fac)) : "";

    if (g_strcmp0(first_name, "pipewiresrc") == 0 && g_strcmp0(last_name, "intervideosink") == 0) {
        GstObject *parent = gst_element_get_parent(first);
        if (parent && GST_IS_BIN(parent)) {
            GObjectClass *pw_klass = G_OBJECT_GET_CLASS(first);
            if (pw_klass) {
                if (g_object_class_find_property(pw_klass, "min-buffers"))
                    g_object_set(first, "min-buffers", 4, NULL);
                if (g_object_class_find_property(pw_klass, "keepalive-time"))
                    g_object_set(first, "keepalive-time", 33, NULL);
            }

            GObjectClass *sink_klass = G_OBJECT_GET_CLASS(last);
            if (sink_klass) {
                if (g_object_class_find_property(sink_klass, "enable-last-sample"))
                    g_object_set(last, "enable-last-sample", FALSE, NULL);
                if (g_object_class_find_property(sink_klass, "qos"))
                    g_object_set(last, "qos", FALSE, NULL);
            }

            GstPad *src_pad = gst_element_get_static_pad(first, "src");
            if (src_pad) {
                gst_pad_add_probe(src_pad, GST_PAD_PROBE_TYPE_BUFFER, pw_src_buffer_probe, NULL, NULL);
                gst_object_unref(src_pad);
            }

            GstPad *sink_pad = gst_element_get_static_pad(last, "sink");
            if (sink_pad) {
                gst_pad_add_probe(sink_pad, GST_PAD_PROBE_TYPE_BUFFER, inter_sink_copy_probe, NULL, NULL);
                gst_object_unref(sink_pad);
            }

            GstElement *dmabuf_caps = gst_element_factory_make("capsfilter", NULL);
            GstElement *glup = gst_element_factory_make("glupload", NULL);
            GstElement *glconv = gst_element_factory_make("glcolorconvert", NULL);
            GstElement *gldown = gst_element_factory_make("gldownload", NULL);
            GstElement *sysmem_caps = gst_element_factory_make("capsfilter", NULL);

            if (dmabuf_caps && glup && glconv && gldown && sysmem_caps) {
                GstCaps *caps = gst_caps_from_string(
                    "video/x-raw(memory:DMABuf),format=(string)DMA_DRM,drm-format=(string){ XR24, AR24, XB24, AB24 }; "
                    "video/x-raw");
                g_object_set(dmabuf_caps, "caps", caps, NULL);
                gst_caps_unref(caps);

                GstCaps *out_caps = gst_caps_from_string(
                    "video/x-raw,format=(string)BGRx; video/x-raw");
                g_object_set(sysmem_caps, "caps", out_caps, NULL);
                gst_caps_unref(out_caps);

                GstBin *bin = GST_BIN(parent);
                gst_bin_add_many(bin, dmabuf_caps, glup, glconv, gldown, sysmem_caps, NULL);
                gst_element_sync_state_with_parent(dmabuf_caps);
                gst_element_sync_state_with_parent(glup);
                gst_element_sync_state_with_parent(glconv);
                gst_element_sync_state_with_parent(gldown);
                gst_element_sync_state_with_parent(sysmem_caps);

                gboolean ok = gst_element_link(first, dmabuf_caps)
                    && gst_element_link(dmabuf_caps, glup)
                    && gst_element_link(glup, glconv)
                    && gst_element_link(glconv, gldown)
                    && gst_element_link(gldown, sysmem_caps);
                GstElement *prev = sysmem_caps;
                for (guint i = 1; ok && i < elems->len; i++) {
                    GstElement *cur = (GstElement *)g_ptr_array_index(elems, i);
                    ok = gst_element_link(prev, cur);
                    prev = cur;
                }
                gst_object_unref(parent);
                g_ptr_array_free(elems, TRUE);
                return ok;
            }
            gst_object_unref(parent);
        }
    }

    gboolean ok = TRUE;
    for (guint i = 0; ok && i + 1 < elems->len; i++) {
        ok = gst_element_link(
            (GstElement *)g_ptr_array_index(elems, i),
            (GstElement *)g_ptr_array_index(elems, i + 1));
    }
    g_ptr_array_free(elems, TRUE);
    return ok;
}
