#include <errno.h>
#include <mach/mach.h>
#include <mach/task_info.h>
#include <mach/vm_attributes.h>
#include <mach-o/dyld_images.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const vm_address_t kVerifyKeyboardExtensionsAddress = 0x1893cd480ULL;

typedef void *xpc_object_t;
extern xpc_object_t xpc_dictionary_create_empty(void);
extern void xpc_dictionary_set_uint64(xpc_object_t dictionary, const char *key,
                                      uint64_t value);
extern void xpc_dictionary_set_bool(xpc_object_t dictionary, const char *key,
                                    bool value);
extern int64_t xpc_dictionary_get_int64(xpc_object_t dictionary,
                                        const char *key);
extern xpc_object_t xpc_pipe_create_from_port(mach_port_t port,
                                              uint32_t flags);
extern int xpc_pipe_routine_with_flags(xpc_object_t pipe,
                                       xpc_object_t request,
                                       xpc_object_t *reply, uint32_t flags);
extern void xpc_release(xpc_object_t object);

static int allowInvalidCodePages(pid_t pid) {
    mach_port_t launchdPort = MACH_PORT_NULL;
    if (task_get_bootstrap_port(mach_task_self(), &launchdPort) !=
            KERN_SUCCESS ||
        launchdPort == MACH_PORT_NULL) {
        return -1;
    }

    xpc_object_t pipe = xpc_pipe_create_from_port(launchdPort, 0);
    xpc_object_t request = xpc_dictionary_create_empty();
    xpc_object_t reply = NULL;
    if (!pipe || !request) {
        if (request) xpc_release(request);
        if (pipe) xpc_release(pipe);
        return -1;
    }

    xpc_dictionary_set_uint64(request, "jb-domain", 2);
    xpc_dictionary_set_uint64(request, "action", 1);
    xpc_dictionary_set_uint64(request, "pid", (uint64_t)pid);
    xpc_dictionary_set_bool(request, "fully-debugged", false);
    int pipeResult = xpc_pipe_routine_with_flags(pipe, request, &reply, 0);
    int result = pipeResult == 0 && reply
                     ? (int)xpc_dictionary_get_int64(reply, "result")
                     : -1;
    if (reply) xpc_release(reply);
    xpc_release(request);
    xpc_release(pipe);
    return result;
}

int main(int argc, char **argv) {
    if (argc != 2 && argc != 3) {
        fprintf(stderr, "usage: %s PID [--patch]\n", argv[0]);
        return 2;
    }
    bool shouldPatch = argc == 3 && strcmp(argv[2], "--patch") == 0;
    if (argc == 3 && !shouldPatch) {
        fprintf(stderr, "unknown option: %s\n", argv[2]);
        return 2;
    }

    char *end = NULL;
    long parsed = strtol(argv[1], &end, 10);
    if (!end || *end != '\0' || parsed <= 0 || parsed > INT32_MAX) {
        fprintf(stderr, "invalid pid: %s\n", argv[1]);
        return 2;
    }

    task_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), (pid_t)parsed, &task);
    printf("task_for_pid(%ld): %d (%s), port=%u\n",
           parsed, kr, mach_error_string(kr), task);
    if (kr != KERN_SUCCESS) {
        return 1;
    }

    task_dyld_info_data_t dyldInfo = {0};
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kr = task_info(task, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);
    printf("TASK_DYLD_INFO: %d (%s), all_image_info=0x%llx size=%llu\n",
           kr, mach_error_string(kr),
           (uint64_t)dyldInfo.all_image_info_addr,
           (uint64_t)dyldInfo.all_image_info_size);

    struct dyld_all_image_infos images = {0};
    vm_size_t copied = 0;
    if (kr == KERN_SUCCESS) {
        kr = vm_read_overwrite(task, (vm_address_t)dyldInfo.all_image_info_addr,
                               sizeof(images), (vm_address_t)&images, &copied);
        printf("read dyld info: %d (%s), copied=%llu, version=%u, "
               "shared_cache_slide=0x%llx\n",
               kr, mach_error_string(kr), (uint64_t)copied, images.version,
               (uint64_t)images.sharedCacheSlide);
    }

    uint8_t bytes[12] = {0};
    vm_address_t address = 0;
    if (kr == KERN_SUCCESS) {
        address = kVerifyKeyboardExtensionsAddress + images.sharedCacheSlide;
        copied = 0;
        kr = vm_read_overwrite(task, address, sizeof(bytes),
                               (vm_address_t)bytes, &copied);
        printf("UIKit gate at 0x%llx: %d (%s), copied=%llu, "
               "%02x %02x %02x %02x %02x %02x %02x %02x "
               "%02x %02x %02x %02x\n",
               (uint64_t)address, kr, mach_error_string(kr),
               (uint64_t)copied,
               bytes[0], bytes[1], bytes[2], bytes[3],
               bytes[4], bytes[5], bytes[6], bytes[7],
               bytes[8], bytes[9], bytes[10], bytes[11]);
    }

    static const uint8_t expected[12] = {
        0x7f, 0x23, 0x03, 0xd5, // pacibsp
        0xf4, 0x4f, 0xbe, 0xa9,
        0xfd, 0x7b, 0x01, 0xa9
    };
    static const uint8_t patch[12] = {
        0x7f, 0x23, 0x03, 0xd5, // pacibsp
        0x20, 0x00, 0x80, 0x52, // mov w0, #1
        0xff, 0x0f, 0x5f, 0xd6  // retab
    };
    if (kr == KERN_SUCCESS && shouldPatch) {
        if (memcmp(bytes, expected, sizeof(expected)) != 0) {
            fprintf(stderr, "refusing to patch: original bytes did not match\n");
            kr = KERN_FAILURE;
        } else {
            int allowResult = allowInvalidCodePages((pid_t)parsed);
            printf("allow invalid code pages: %d\n", allowResult);
            if (allowResult != 0) {
                mach_port_deallocate(mach_task_self(), task);
                return 1;
            }
            kr = task_suspend(task);
            printf("task_suspend: %d (%s)\n", kr, mach_error_string(kr));
            vm_address_t page = address & ~((vm_address_t)vm_page_size - 1);
            if (kr == KERN_SUCCESS) {
                kr = vm_protect(task, page, vm_page_size, false,
                                VM_PROT_READ | VM_PROT_WRITE |
                                    VM_PROT_EXECUTE | VM_PROT_COPY);
            }
            printf("vm_protect(RWX+COW): %d (%s)\n", kr,
                   mach_error_string(kr));
            if (kr == KERN_SUCCESS) {
                kr = vm_write(task, address, (vm_offset_t)patch,
                              (mach_msg_type_number_t)sizeof(patch));
                printf("vm_write: %d (%s)\n", kr, mach_error_string(kr));
            }
            if (kr == KERN_SUCCESS) {
                vm_machine_attribute_val_t cache = MATTR_VAL_CACHE_FLUSH;
                kern_return_t cacheKr = vm_machine_attribute(
                    task, address, sizeof(patch), MATTR_CACHE, &cache);
                printf("cache flush: %d (%s)\n", cacheKr,
                       mach_error_string(cacheKr));
            }
            kern_return_t restoreKr = vm_protect(
                task, page, vm_page_size, false,
                VM_PROT_READ | VM_PROT_EXECUTE);
            printf("vm_protect(RX): %d (%s)\n", restoreKr,
                   mach_error_string(restoreKr));

            memset(bytes, 0, sizeof(bytes));
            copied = 0;
            kern_return_t readKr = vm_read_overwrite(
                task, address, sizeof(bytes), (vm_address_t)bytes, &copied);
            printf("after patch: %d (%s), %02x %02x %02x %02x "
                   "%02x %02x %02x %02x %02x %02x %02x %02x\n",
                   readKr, mach_error_string(readKr), bytes[0], bytes[1],
                   bytes[2], bytes[3], bytes[4], bytes[5], bytes[6],
                   bytes[7], bytes[8], bytes[9], bytes[10], bytes[11]);
            kern_return_t resumeKr = task_resume(task);
            printf("task_resume: %d (%s)\n", resumeKr,
                   mach_error_string(resumeKr));
        }
    }

    mach_port_deallocate(mach_task_self(), task);
    return kr == KERN_SUCCESS ? 0 : 1;
}
