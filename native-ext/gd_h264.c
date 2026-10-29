/* GDExtension (plain C, no godot-cpp) exposing the H.264 decoder to GDScript as class H264Decoder (RefCounted):
 *   decode(data: PackedByteArray) -> int    1 = new picture, 0 = none yet, -1 = undecodable data
 *   get_width() -> int, get_height() -> int
 *   get_rgba() -> PackedByteArray           last picture, RGBA8, width * height * 4 bytes
 * The app falls back to JPEG frames when this library is missing (ClassDB.class_exists("H264Decoder")). */
#include <stdlib.h>
#include <string.h>
#include "include/gdextension_interface.h"
#include "tt_h264.h"

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

/* Opaque storage for Godot builtins: large enough and aligned for every build (StringName 8, PackedByteArray 16,
 * String 8 bytes on 64-bit). */
typedef struct { uint64_t d[2]; } StringName;
typedef struct { uint64_t d[2]; } GdString;
typedef struct { uint64_t d[2]; } PackedBytes;

static GDExtensionClassLibraryPtr library;
static struct {
    GDExtensionInterfaceClassdbConstructObject2 construct_object;
    GDExtensionInterfaceObjectSetInstance set_instance;
    GDExtensionInterfaceObjectSetInstanceBinding set_instance_binding;
    GDExtensionInterfaceStringNameNewWithLatin1Chars string_name_new;
    GDExtensionInterfaceStringNewWithLatin1Chars string_new;
    GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
    GDExtensionInterfaceVariantGetPtrConstructor get_constructor;
    GDExtensionInterfaceVariantGetPtrBuiltinMethod get_builtin_method;
    GDExtensionInterfacePackedByteArrayOperatorIndex bytes_at;
    GDExtensionInterfacePackedByteArrayOperatorIndexConst bytes_at_const;
    GDExtensionInterfaceGetVariantFromTypeConstructor from_type;
    GDExtensionInterfaceGetVariantToTypeConstructor to_type;
    GDExtensionInterfaceClassdbRegisterExtensionClass4 register_class;
    GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
    GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
} api;
static struct {
    GDExtensionPtrConstructor bytes_new;
    GDExtensionPtrDestructor bytes_free;
    GDExtensionPtrBuiltInMethod bytes_resize, bytes_size;
    GDExtensionVariantFromTypeConstructorFunc int_to_variant, bytes_to_variant;
    GDExtensionTypeFromVariantConstructorFunc variant_to_bytes;
} gd;
static StringName class_name, parent_name;

static int64_t bytes_len(const void *bytes) {
    int64_t n = 0;
    gd.bytes_size((GDExtensionTypePtr)bytes, NULL, &n, 0);
    return n;
}

/* ---- instance ---- */

static void *binding_create(void *token, void *instance) { (void)token; (void)instance; return NULL; }
static void binding_free(void *token, void *instance, void *binding) { (void)token; (void)instance; (void)binding; }
static GDExtensionBool binding_reference(void *token, void *binding, GDExtensionBool ref) { (void)token; (void)binding; (void)ref; return 1; }
static const GDExtensionInstanceBindingCallbacks binding_callbacks = { binding_create, binding_free, binding_reference };

static GDExtensionObjectPtr create_instance(void *userdata, GDExtensionBool notify) {
    (void)userdata; (void)notify;
    GDExtensionObjectPtr obj = api.construct_object(&parent_name);
    tt_dec *dec = tt_new();
    api.set_instance(obj, &class_name, dec);
    api.set_instance_binding(obj, library, dec, &binding_callbacks);
    return obj;
}

static void free_instance(void *userdata, GDExtensionClassInstancePtr instance) { (void)userdata; tt_free(instance); }

/* ---- methods: each has a ptrcall (typed) and a call (Variant) entry ---- */

static int64_t do_decode(tt_dec *d, const void *bytes) {
    int64_t n = bytes_len(bytes);
    if (!d || n <= 0) return -1;
    return tt_decode(d, api.bytes_at_const(bytes, 0), (uint32_t)n);
}

static void do_rgba(tt_dec *d, void *out) {
    uint32_t w = 0, h = 0;
    const uint8_t *px = d ? tt_rgba(d, &w, &h) : NULL;
    int64_t n = px ? (int64_t)w * h * 4 : 0, ignored;
    const GDExtensionConstTypePtr args[] = { &n };
    gd.bytes_resize(out, args, &ignored, 1);
    if (n) memcpy(api.bytes_at(out, 0), px, (size_t)n);
}

static int64_t width_of(tt_dec *d) { uint32_t w = 0, h = 0; if (d) tt_rgba(d, &w, &h); return w; }
static int64_t height_of(tt_dec *d) { uint32_t w = 0, h = 0; if (d) tt_rgba(d, &w, &h); return h; }

static void decode_ptr(void *ud, GDExtensionClassInstancePtr self, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
    (void)ud; *(int64_t *)ret = do_decode(self, args[0]);
}
static void decode_call(void *ud, GDExtensionClassInstancePtr self, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)ud;
    if (argc < 1) { err->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; err->expected = 1; return; }
    PackedBytes bytes;
    gd.variant_to_bytes(&bytes, (GDExtensionVariantPtr)args[0]);
    int64_t r = do_decode(self, &bytes);
    gd.bytes_free(&bytes);
    gd.int_to_variant(ret, &r);
    err->error = GDEXTENSION_CALL_OK;
}

static void rgba_ptr(void *ud, GDExtensionClassInstancePtr self, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
    (void)ud; (void)args; do_rgba(self, ret);
}
static void rgba_call(void *ud, GDExtensionClassInstancePtr self, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)ud; (void)args; (void)argc;
    PackedBytes bytes;
    gd.bytes_new(&bytes, NULL);
    do_rgba(self, &bytes);
    gd.bytes_to_variant(ret, &bytes);
    gd.bytes_free(&bytes);
    err->error = GDEXTENSION_CALL_OK;
}

static void width_ptr(void *ud, GDExtensionClassInstancePtr self, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
    (void)ud; (void)args; *(int64_t *)ret = width_of(self);
}
static void width_call(void *ud, GDExtensionClassInstancePtr self, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)ud; (void)args; (void)argc; int64_t v = width_of(self); gd.int_to_variant(ret, &v); err->error = GDEXTENSION_CALL_OK;
}
static void height_ptr(void *ud, GDExtensionClassInstancePtr self, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
    (void)ud; (void)args; *(int64_t *)ret = height_of(self);
}
static void height_call(void *ud, GDExtensionClassInstancePtr self, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
    (void)ud; (void)args; (void)argc; int64_t v = height_of(self); gd.int_to_variant(ret, &v); err->error = GDEXTENSION_CALL_OK;
}

/* ---- registration ---- */

static StringName names[8];
static GdString empty;

static GDExtensionPropertyInfo prop(GDExtensionVariantType type, StringName *name) {
    GDExtensionPropertyInfo p = { type, name, &names[7], 0, &empty, 6 /* PROPERTY_USAGE_DEFAULT */ };
    return p;
}

static void add_method(StringName *name, GDExtensionClassMethodCall call, GDExtensionClassMethodPtrCall ptr,
                       GDExtensionVariantType ret_type, int has_arg) {
    GDExtensionPropertyInfo ret = prop(ret_type, &names[6]);
    GDExtensionPropertyInfo arg = prop(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &names[5]);
    GDExtensionClassMethodArgumentMetadata arg_meta = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    GDExtensionClassMethodInfo info = {
        name, NULL, call, ptr, GDEXTENSION_METHOD_FLAGS_DEFAULT,
        1, &ret, ret_type == GDEXTENSION_VARIANT_TYPE_INT ? GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64 : GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE,
        has_arg ? 1 : 0, has_arg ? &arg : NULL, has_arg ? &arg_meta : NULL, 0, NULL
    };
    api.register_method(library, &class_name, &info);
}

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    api.string_name_new(&class_name, "H264Decoder", 1);
    api.string_name_new(&parent_name, "RefCounted", 1);
    const char *labels[] = { "decode", "get_rgba", "get_width", "get_height", "", "data", "", "" };
    for (int i = 0; i < 8; i++) api.string_name_new(&names[i], labels[i], 1);
    api.string_new(&empty, "");
    StringName resize_name, size_name;
    api.string_name_new(&resize_name, "resize", 1);
    api.string_name_new(&size_name, "size", 1);
    gd.bytes_new = api.get_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
    gd.bytes_free = api.get_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    gd.bytes_resize = api.get_builtin_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &resize_name, 848867239);
    gd.bytes_size = api.get_builtin_method(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, &size_name, 3173160232);
    gd.int_to_variant = api.from_type(GDEXTENSION_VARIANT_TYPE_INT);
    gd.bytes_to_variant = api.from_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
    gd.variant_to_bytes = api.to_type(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);

    GDExtensionClassCreationInfo4 info;
    memset(&info, 0, sizeof info);
    info.is_exposed = 1;
    info.create_instance_func = create_instance;
    info.free_instance_func = free_instance;
    api.register_class(library, &class_name, &parent_name, &info);
    add_method(&names[0], decode_call, decode_ptr, GDEXTENSION_VARIANT_TYPE_INT, 1);
    add_method(&names[1], rgba_call, rgba_ptr, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, 0);
    add_method(&names[2], width_call, width_ptr, GDEXTENSION_VARIANT_TYPE_INT, 0);
    add_method(&names[3], height_call, height_ptr, GDEXTENSION_VARIANT_TYPE_INT, 0);
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
    (void)userdata;
    if (level == GDEXTENSION_INITIALIZATION_SCENE) api.unregister_class(library, &class_name);
}

#define LOAD(field, name) api.field = (void *)get_proc(name); if (!api.field) return 0
EXPORT GDExtensionBool thuetab_h264_init(GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr lib,
                                         GDExtensionInitialization *init) {
    library = lib;
    LOAD(construct_object, "classdb_construct_object2");
    LOAD(set_instance, "object_set_instance");
    LOAD(set_instance_binding, "object_set_instance_binding");
    LOAD(string_name_new, "string_name_new_with_latin1_chars");
    LOAD(string_new, "string_new_with_latin1_chars");
    LOAD(get_destructor, "variant_get_ptr_destructor");
    LOAD(get_constructor, "variant_get_ptr_constructor");
    LOAD(get_builtin_method, "variant_get_ptr_builtin_method");
    LOAD(bytes_at, "packed_byte_array_operator_index");
    LOAD(bytes_at_const, "packed_byte_array_operator_index_const");
    LOAD(from_type, "get_variant_from_type_constructor");
    LOAD(to_type, "get_variant_to_type_constructor");
    LOAD(register_class, "classdb_register_extension_class4");
    LOAD(register_method, "classdb_register_extension_class_method");
    LOAD(unregister_class, "classdb_unregister_extension_class");
    init->initialize = initialize;
    init->deinitialize = deinitialize;
    init->userdata = NULL;
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    return 1;
}
