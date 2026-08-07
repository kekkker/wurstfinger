#include <fcntl.h>
#include <mach/mach.h>
#include <mach/task_info.h>
#include <mach-o/dyld_images.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char kVintedExecutableSuffix[] = "/Vinted.app/Vinted";
static const vm_address_t kEncryptedOffset = 0xc000;
static const vm_size_t kEncryptedSize = 0x1000;

static bool hasSuffix(const char *value, const char *suffix) {
    size_t valueLength = strlen(value);
    size_t suffixLength = strlen(suffix);
    return valueLength >= suffixLength &&
           memcmp(value + valueLength - suffixLength, suffix, suffixLength) == 0;
}

static bool readRemoteCString(task_t task, vm_address_t address,
                              char *buffer, size_t capacity) {
    if (capacity == 0) return false;
    for (size_t offset = 0; offset + 1 < capacity; ++offset) {
        vm_size_t copied = 0;
        kern_return_t kr = vm_read_overwrite(
            task, address + offset, 1, (vm_address_t)&buffer[offset], &copied);
        if (kr != KERN_SUCCESS || copied != 1) return false;
        if (buffer[offset] == '\0') return true;
    }
    buffer[capacity - 1] = '\0';
    return false;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s PID OUTPUT\n", argv[0]);
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
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "task_for_pid: %s\n", mach_error_string(kr));
        return 1;
    }

    task_dyld_info_data_t taskDyldInfo = {0};
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kr = task_info(task, TASK_DYLD_INFO, (task_info_t)&taskDyldInfo, &count);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "TASK_DYLD_INFO: %s\n", mach_error_string(kr));
        mach_port_deallocate(mach_task_self(), task);
        return 1;
    }

    struct dyld_all_image_infos allImages = {0};
    vm_size_t copied = 0;
    kr = vm_read_overwrite(task, (vm_address_t)taskDyldInfo.all_image_info_addr,
                           sizeof(allImages), (vm_address_t)&allImages, &copied);
    if (kr != KERN_SUCCESS || copied < sizeof(allImages) ||
        allImages.infoArrayCount == 0 || allImages.infoArrayCount > 4096) {
        fprintf(stderr, "dyld image metadata unavailable\n");
        mach_port_deallocate(mach_task_self(), task);
        return 1;
    }

    size_t imageBytes =
        (size_t)allImages.infoArrayCount * sizeof(struct dyld_image_info);
    struct dyld_image_info *images = calloc(1, imageBytes);
    if (!images) {
        perror("calloc");
        mach_port_deallocate(mach_task_self(), task);
        return 1;
    }

    copied = 0;
    kr = vm_read_overwrite(task, (vm_address_t)allImages.infoArray, imageBytes,
                           (vm_address_t)images, &copied);
    if (kr != KERN_SUCCESS || copied != imageBytes) {
        fprintf(stderr, "read image array: %s\n", mach_error_string(kr));
        free(images);
        mach_port_deallocate(mach_task_self(), task);
        return 1;
    }

    vm_address_t mainAddress = 0;
    char imagePath[4096] = {0};
    for (uint32_t index = 0; index < allImages.infoArrayCount; ++index) {
        memset(imagePath, 0, sizeof(imagePath));
        if (!readRemoteCString(task, (vm_address_t)images[index].imageFilePath,
                               imagePath, sizeof(imagePath))) {
            continue;
        }
        if (hasSuffix(imagePath, kVintedExecutableSuffix)) {
            mainAddress = (vm_address_t)images[index].imageLoadAddress;
            break;
        }
    }
    free(images);

    if (mainAddress == 0) {
        fprintf(stderr, "Vinted image not found\n");
        mach_port_deallocate(mach_task_self(), task);
        return 1;
    }

    uint8_t decrypted[kEncryptedSize];
    copied = 0;
    kr = vm_read_overwrite(task, mainAddress + kEncryptedOffset,
                           sizeof(decrypted), (vm_address_t)decrypted, &copied);
    mach_port_deallocate(mach_task_self(), task);
    if (kr != KERN_SUCCESS || copied != sizeof(decrypted)) {
        fprintf(stderr, "read decrypted page: %s (copied=%llu)\n",
                mach_error_string(kr), (uint64_t)copied);
        return 1;
    }

    int output = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (output < 0) {
        perror("open output");
        return 1;
    }
    ssize_t written = write(output, decrypted, sizeof(decrypted));
    int closeResult = close(output);
    if (written != sizeof(decrypted) || closeResult != 0) {
        perror("write output");
        return 1;
    }

    printf("dumped 0x%llx bytes from Vinted+0x%llx (base 0x%llx) to %s\n",
           (uint64_t)sizeof(decrypted), (uint64_t)kEncryptedOffset,
           (uint64_t)mainAddress, argv[2]);
    return 0;
}
