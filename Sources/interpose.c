#include <stdlib.h>

#include "bridge.h"
#include "callbacks.h"

// dyld interpose：Astris 前端对这些符号的调用会被改道到 am_* 版本，
// 我们记录/过滤后再转调 libryujinx 的原始实现。
#define DYLD_INTERPOSE(_replacement, _replacee)                                             \
    __attribute__((used)) static struct {                                                    \
        const void *replacement;                                                             \
        const void *replacee;                                                                \
    } _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = {             \
        (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee};

static void am_stick_axis(int32_t controller, int32_t stick, float x, float y) {
    if (am_on_stick_axis(controller, stick, x, y)) {
        return;
    }
    ryujinx_set_controller_stick_axis(controller, stick, x, y);
}

static void am_button_pressed(int32_t controller, int32_t button, int32_t pressed) {
    am_on_button_pressed(controller, button, pressed);
    ryujinx_set_controller_button_pressed(controller, button, pressed);
}

static int32_t am_connect_controller(const char *id, const char *name) {
    am_before_connect_controller(id);
    int32_t handle = ryujinx_connect_controller(id, name);
    am_on_connect_controller(id, name, handle);
    return handle;
}

static void am_disconnect_controller(const char *id) {
    am_on_disconnect_controller(id);
    ryujinx_disconnect_controller(id);
}

static void am_keyboard_key_pressed(int32_t key, int32_t pressed) {
    if (am_on_keyboard_key_pressed(key, pressed)) {
        return;
    }
    ryujinx_set_keyboard_key_pressed(key, pressed);
}

static int32_t am_stop_emulation(void) {
    am_before_stop_emulation();
    return ryujinx_stop_emulation();
}

// 前端把整份 RyujinxOptions JSON 交给 libryujinx；需要时把 Player1 改写成绑定我们的虚拟手柄。
// 只改内存里这一份字符串，Astris 自己的设置和偏好文件不动。
static void am_update_options(const char *json) {
    char *patched = am_rewrite_options(json);
    ryujinx_update_options(patched ? patched : json);
    free(patched);
}

DYLD_INTERPOSE(am_update_options, ryujinx_update_options)
DYLD_INTERPOSE(am_stop_emulation, ryujinx_stop_emulation)
DYLD_INTERPOSE(am_stick_axis, ryujinx_set_controller_stick_axis)
DYLD_INTERPOSE(am_button_pressed, ryujinx_set_controller_button_pressed)
DYLD_INTERPOSE(am_connect_controller, ryujinx_connect_controller)
DYLD_INTERPOSE(am_disconnect_controller, ryujinx_disconnect_controller)
DYLD_INTERPOSE(am_keyboard_key_pressed, ryujinx_set_keyboard_key_pressed)

__attribute__((constructor)) static void am_constructor(void) {
    am_bootstrap();
}
