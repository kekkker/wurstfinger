#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <mach/task_info.h>
#include <mach/vm_attributes.h>
#include <mach-o/dyld_images.h>
#include <signal.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

// libproc is present in libSystem on iOS but its private SDK header is not.
#define PROC_ALL_PIDS 1
#define PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN)
extern int proc_listpids(uint32_t type, uint32_t typeInfo, void *buffer,
                         int bufferSize);
extern int proc_pidpath(int pid, void *buffer, uint32_t bufferSize);

// iOS 16.3 (20D47), UIKitCore 6304.1.100.0.0.
// -[UIKeyboardInputModeController verifyKeyboardExtensionsWithApp]
static const vm_address_t kVerifyKeyboardExtensionsAddress = 0x1893cd480ULL;
static const char kVintedExecutableSuffix[] = "/Vinted.app/Vinted";
static const char kLogPath[] =
    "/var/mobile/Library/Logs/WurstVintedBridge.log";

static const uint8_t kExpectedCode[8] = {
    0x7f, 0x23, 0x03, 0xd5, // pacibsp
    0xf4, 0x4f, 0xbe, 0xa9  // stp x20, x19, [sp, #-0x20]!
};

static const uint8_t kReturnYesCode[8] = {
    0x20, 0x00, 0x80, 0x52, // mov w0, #1
    0xc0, 0x03, 0x5f, 0xd6  // ret
};

static volatile sig_atomic_t gShouldRun = 1;
static int gLogFD = -1;

typedef enum {
    PatchResultRetry,
    PatchResultSuccess,
    PatchResultUnsupported,
} PatchResult;

static void handleSignal(int signalNumber) {
    (void)signalNumber;
    gShouldRun = 0;
}

static void openLog(void) {
    if (gLogFD >= 0) {
        return;
    }
    gLogFD = open(kLogPath, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
}

static void logMessage(const char *format, ...) {
    openLog();
    if (gLogFD < 0) {
        return;
    }

    time_t now = time(NULL);
    struct tm local = {0};
    localtime_r(&now, &local);
    char timestamp[32] = {0};
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", &local);

    dprintf(gLogFD, "[%s] ", timestamp);
    va_list arguments;
    va_start(arguments, format);
    vdprintf(gLogFD, format, arguments);
    va_end(arguments);
    dprintf(gLogFD, "\n");
    fsync(gLogFD);
}

static bool stringHasSuffix(const char *value, const char *suffix) {
    size_t valueLength = strlen(value);
    size_t suffixLength = strlen(suffix);
    return valueLength >= suffixLength &&
           memcmp(value + valueLength - suffixLength, suffix, suffixLength) == 0;
}

static bool isVintedProcess(pid_t pid) {
    char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int length = proc_pidpath(pid, path, sizeof(path));
    return length > 0 && stringHasSuffix(path, kVintedExecutableSuffix);
}

static PatchResult patchVinted(pid_t pid) {
    task_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS || task == MACH_PORT_NULL) {
        return PatchResultRetry;
    }

    task_dyld_info_data_t taskDyldInfo = {0};
    mach_msg_type_number_t taskDyldInfoCount = TASK_DYLD_INFO_COUNT;
    kr = task_info(task, TASK_DYLD_INFO, (task_info_t)&taskDyldInfo,
                   &taskDyldInfoCount);
    if (kr != KERN_SUCCESS || taskDyldInfo.all_image_info_addr == 0) {
        mach_port_deallocate(mach_task_self(), task);
        return PatchResultRetry;
    }

    struct dyld_all_image_infos imageInfos = {0};
    vm_size_t copied = 0;
    vm_size_t imageInfoSize = sizeof(imageInfos);
    if (taskDyldInfo.all_image_info_size < imageInfoSize) {
        imageInfoSize = (vm_size_t)taskDyldInfo.all_image_info_size;
    }
    kr = vm_read_overwrite(task,
                           (vm_address_t)taskDyldInfo.all_image_info_addr,
                           imageInfoSize, (vm_address_t)&imageInfos, &copied);
    if (kr != KERN_SUCCESS || copied < offsetof(struct dyld_all_image_infos,
                                                sharedCacheSlide) +
                                           sizeof(imageInfos.sharedCacheSlide) ||
        imageInfos.version < 12) {
        mach_port_deallocate(mach_task_self(), task);
        return PatchResultRetry;
    }

    vm_address_t address =
        kVerifyKeyboardExtensionsAddress + imageInfos.sharedCacheSlide;
    uint8_t currentCode[sizeof(kExpectedCode)] = {0};
    copied = 0;
    kr = vm_read_overwrite(task, address, sizeof(currentCode),
                           (vm_address_t)currentCode, &copied);
    if (kr != KERN_SUCCESS || copied != sizeof(currentCode)) {
        mach_port_deallocate(mach_task_self(), task);
        return PatchResultRetry;
    }

    if (memcmp(currentCode, kReturnYesCode, sizeof(currentCode)) == 0) {
        mach_port_deallocate(mach_task_self(), task);
        return PatchResultSuccess;
    }
    if (memcmp(currentCode, kExpectedCode, sizeof(currentCode)) != 0) {
        logMessage("pid %d: refusing unknown UIKit bytes at 0x%llx: "
                   "%02x %02x %02x %02x %02x %02x %02x %02x",
                   pid, (uint64_t)address, currentCode[0], currentCode[1],
                   currentCode[2], currentCode[3], currentCode[4],
                   currentCode[5], currentCode[6], currentCode[7]);
        mach_port_deallocate(mach_task_self(), task);
        return PatchResultUnsupported;
    }

    vm_address_t page = address & ~((vm_address_t)vm_page_size - 1);
    kr = vm_protect(task, page, vm_page_size, false,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr == KERN_SUCCESS) {
        kr = vm_write(task, address, (vm_offset_t)kReturnYesCode,
                      (mach_msg_type_number_t)sizeof(kReturnYesCode));
    }

    if (kr == KERN_SUCCESS) {
        vm_machine_attribute_val_t cacheAction = MATTR_VAL_CACHE_FLUSH;
        kr = vm_machine_attribute(task, address, sizeof(kReturnYesCode),
                                  MATTR_CACHE, &cacheAction);
    }

    kern_return_t restoreResult = vm_protect(
        task, page, vm_page_size, false, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr == KERN_SUCCESS && restoreResult != KERN_SUCCESS) {
        kr = restoreResult;
    }

    memset(currentCode, 0, sizeof(currentCode));
    copied = 0;
    kern_return_t readBackResult = vm_read_overwrite(
        task, address, sizeof(currentCode), (vm_address_t)currentCode, &copied);
    mach_port_deallocate(mach_task_self(), task);

    if (kr != KERN_SUCCESS || readBackResult != KERN_SUCCESS ||
        copied != sizeof(currentCode) ||
        memcmp(currentCode, kReturnYesCode, sizeof(currentCode)) != 0) {
        logMessage("pid %d: patch failed (%s), read-back=%s", pid,
                   mach_error_string(kr), mach_error_string(readBackResult));
        return PatchResultRetry;
    }

    logMessage("pid %d: enabled Wurstfinger without injecting Vinted", pid);
    return PatchResultSuccess;
}

static pid_t findVinted(pid_t minimumPid, pid_t *highestPid) {
    pid_t pids[4096] = {0};
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    if (bytes <= 0) {
        return 0;
    }

    size_t count = (size_t)bytes / sizeof(pids[0]);
    pid_t found = 0;
    pid_t observedHighest = *highestPid;
    for (size_t index = 0; index < count; ++index) {
        pid_t pid = pids[index];
        if (pid > observedHighest) {
            observedHighest = pid;
        }
        if (pid >= minimumPid && isVintedProcess(pid)) {
            found = pid;
            break;
        }
    }
    *highestPid = observedHighest;
    return found;
}

int main(void) {
    signal(SIGTERM, handleSignal);
    signal(SIGINT, handleSignal);
    signal(SIGHUP, handleSignal);
    setpriority(PRIO_PROCESS, 0, 10);

    logMessage("bridge started (iOS 16.3 UIKit gate 0x%llx)",
               (uint64_t)kVerifyKeyboardExtensionsAddress);

    pid_t highestPid = 0;
    pid_t activePid = findVinted(1, &highestPid);
    while (gShouldRun) {
        if (activePid == 0) {
            // PIDs are monotonic during an iOS userspace boot. One proc-list
            // syscall every 20 ms lets us patch before UIKit first asks the
            // app delegate, without walking every process each time.
            activePid = findVinted(highestPid + 1, &highestPid);
            if (activePid == 0) {
                usleep(20000);
                continue;
            }
            logMessage("pid %d: Vinted launched", activePid);
        }

        PatchResult result = patchVinted(activePid);
        if (result == PatchResultRetry) {
            if (kill(activePid, 0) != 0 && errno == ESRCH) {
                activePid = 0;
            } else {
                usleep(5000);
            }
            continue;
        }

        while (gShouldRun && (kill(activePid, 0) == 0 || errno != ESRCH)) {
            sleep(1);
        }
        logMessage("pid %d: Vinted exited", activePid);
        activePid = 0;
    }

    logMessage("bridge stopped");
    if (gLogFD >= 0) {
        close(gLogFD);
    }
    return 0;
}
