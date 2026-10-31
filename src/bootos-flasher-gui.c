#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <commctrl.h>
#include <commdlg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <shellapi.h>

#define ID_BTN_BROWSE       101
#define ID_COMBO_DRIVES     102
#define ID_BTN_REFRESH      103
#define ID_BTN_MAKE_EXEC    104
#define ID_BTN_RAW_FLASH    105
#define ID_BTN_RUN_VBOX     106
#define ID_BTN_EXIT         107
#define ID_PROGRESS         108
#define ID_EDIT_ISO         109
#define ID_STATUS_LABEL     110
#define ID_STATS_LABEL      111
#define ID_CHK_COPY_ISO     112
#define ID_TIMER_PROGRESS   201

#define BUFFER_SIZE (1024 * 1024) // 1 MB chunk

typedef struct {
    int diskNumber;
    char letter;
    char vendor[128];
    char product[128];
    char busType[32];
    double sizeGB;
    BOOL isUsb;
    BOOL isSystem;
} GuiDriveInfo;

typedef struct {
    HWND hWnd;
    char isoPath[MAX_PATH];
    char targetDriveLetter;
    int diskNumber;
    BOOL isRawFlash;
    BOOL copyIsoFile;
    volatile BOOL isRunning;
    volatile int percent;
    volatile double writtenMB;
    volatile double totalMB;
    volatile double speedMBps;
    volatile BOOL success;
    char errorMsg[256];
} WorkerData;

static HINSTANCE g_hInstance = NULL;
static HWND g_hMainWnd = NULL;
static HWND g_hEditIso = NULL;
static HWND g_hComboDrives = NULL;
static HWND g_hBtnBrowse = NULL;
static HWND g_hBtnRefresh = NULL;
static HWND g_hBtnMakeExec = NULL;
static HWND g_hBtnRawFlash = NULL;
static HWND g_hBtnRunVBox = NULL;
static HWND g_hChkCopyIso = NULL;
static HWND g_hProgress = NULL;
static HWND g_hStatusLabel = NULL;
static HWND g_hStatsLabel = NULL;
static HFONT g_hFontNormal = NULL;
static HFONT g_hFontBold = NULL;
static HFONT g_hFontHeader = NULL;

static GuiDriveInfo g_drives[32];
static int g_driveCount = 0;
static char g_isoPath[MAX_PATH] = "";
static char g_appDir[MAX_PATH] = "";
static WorkerData g_worker;

BOOL IsUserAdmin(void) {
    BOOL isAdmin = FALSE;
    PSID adminGroup = NULL;
    SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
    if (AllocateAndInitializeSid(&ntAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &adminGroup)) {
        CheckTokenMembership(NULL, adminGroup, &isAdmin);
        FreeSid(adminGroup);
    }
    return isAdmin;
}

int GetSystemDiskNumber(void) {
    char winDir[MAX_PATH];
    if (GetWindowsDirectoryA(winDir, sizeof(winDir)) == 0) return -1;
    char volPath[16];
    snprintf(volPath, sizeof(volPath), "\\\\.\\%c:", winDir[0]);
    HANDLE hVol = CreateFileA(volPath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (hVol == INVALID_HANDLE_VALUE) return -1;
    STORAGE_DEVICE_NUMBER sdn;
    DWORD ret = 0;
    int diskNum = -1;
    if (DeviceIoControl(hVol, IOCTL_STORAGE_GET_DEVICE_NUMBER, NULL, 0, &sdn, sizeof(sdn), &ret, NULL)) {
        diskNum = sdn.DeviceNumber;
    }
    CloseHandle(hVol);
    return diskNum;
}

int ScanDrives(GuiDriveInfo *drives, int maxDrives) {
    int count = 0;
    int sysDisk = GetSystemDiskNumber();
    DWORD logicalDrives = GetLogicalDrives();

    for (int i = 0; i < 32 && count < maxDrives; i++) {
        char path[64];
        snprintf(path, sizeof(path), "\\\\.\\PhysicalDrive%d", i);
        HANDLE hDevice = CreateFileA(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
        if (hDevice != INVALID_HANDLE_VALUE) {
            STORAGE_PROPERTY_QUERY query;
            memset(&query, 0, sizeof(query));
            query.PropertyId = StorageDeviceProperty;
            query.QueryType = PropertyStandardQuery;

            BYTE buffer[1024];
            DWORD bytesReturned = 0;
            if (DeviceIoControl(hDevice, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query), buffer, sizeof(buffer), &bytesReturned, NULL)) {
                STORAGE_DEVICE_DESCRIPTOR *desc = (STORAGE_DEVICE_DESCRIPTOR *)buffer;
                drives[count].diskNumber = i;
                drives[count].isSystem = (i == sysDisk);
                drives[count].letter = ' ';
                snprintf(drives[count].vendor, sizeof(drives[count].vendor), "Generic");
                snprintf(drives[count].product, sizeof(drives[count].product), "Storage Device");

                if (desc->VendorIdOffset != 0 && desc->VendorIdOffset < bytesReturned) {
                    char *p = (char *)(buffer + desc->VendorIdOffset);
                    while (*p == ' ') p++;
                    snprintf(drives[count].vendor, sizeof(drives[count].vendor), "%s", p);
                }
                if (desc->ProductIdOffset != 0 && desc->ProductIdOffset < bytesReturned) {
                    char *p = (char *)(buffer + desc->ProductIdOffset);
                    while (*p == ' ') p++;
                    snprintf(drives[count].product, sizeof(drives[count].product), "%s", p);
                }

                drives[count].isUsb = (desc->BusType == BusTypeUsb);
                if (desc->BusType == BusTypeUsb) snprintf(drives[count].busType, sizeof(drives[count].busType), "USB");
                else if (desc->BusType == BusTypeSata) snprintf(drives[count].busType, sizeof(drives[count].busType), "SATA");
                else if (desc->BusType == BusTypeNvme) snprintf(drives[count].busType, sizeof(drives[count].busType), "NVMe");
                else snprintf(drives[count].busType, sizeof(drives[count].busType), "Drive");

                DISK_GEOMETRY_EX geom;
                DWORD ret = 0;
                drives[count].sizeGB = 0.0;
                if (DeviceIoControl(hDevice, IOCTL_DISK_GET_DRIVE_GEOMETRY_EX, NULL, 0, &geom, sizeof(geom), &ret, NULL)) {
                    drives[count].sizeGB = (double)geom.DiskSize.QuadPart / (1024.0 * 1024.0 * 1024.0);
                }

                // Match with drive letters
                for (char c = 'A'; c <= 'Z'; c++) {
                    if (logicalDrives & (1 << (c - 'A'))) {
                        char vpath[16];
                        snprintf(vpath, sizeof(vpath), "\\\\.\\%c:", c);
                        HANDLE hV = CreateFileA(vpath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
                        if (hV != INVALID_HANDLE_VALUE) {
                            STORAGE_DEVICE_NUMBER sdn;
                            DWORD r = 0;
                            if (DeviceIoControl(hV, IOCTL_STORAGE_GET_DEVICE_NUMBER, NULL, 0, &sdn, sizeof(sdn), &r, NULL)) {
                                if ((int)sdn.DeviceNumber == i) {
                                    drives[count].letter = c;
                                    char root[8];
                                    snprintf(root, sizeof(root), "%c:\\", c);
                                    if (GetDriveTypeA(root) == DRIVE_REMOVABLE) {
                                        drives[count].isUsb = TRUE;
                                        snprintf(drives[count].busType, sizeof(drives[count].busType), "USB");
                                    }
                                }
                            }
                            CloseHandle(hV);
                        }
                    }
                }

                count++;
            }
            CloseHandle(hDevice);
        }
    }
    return count;
}

void DismountDriveVolumes(int diskNumber) {
    DWORD logicalDrives = GetLogicalDrives();
    for (char c = 'A'; c <= 'Z'; c++) {
        if (logicalDrives & (1 << (c - 'A'))) {
            char vpath[16];
            snprintf(vpath, sizeof(vpath), "\\\\.\\%c:", c);
            HANDLE hV = CreateFileA(vpath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
            if (hV != INVALID_HANDLE_VALUE) {
                STORAGE_DEVICE_NUMBER sdn;
                DWORD r = 0;
                if (DeviceIoControl(hV, IOCTL_STORAGE_GET_DEVICE_NUMBER, NULL, 0, &sdn, sizeof(sdn), &r, NULL)) {
                    if ((int)sdn.DeviceNumber == diskNumber) {
                        DeviceIoControl(hV, FSCTL_LOCK_VOLUME, NULL, 0, NULL, 0, &r, NULL);
                        DeviceIoControl(hV, FSCTL_DISMOUNT_VOLUME, NULL, 0, NULL, 0, &r, NULL);
                    }
                }
                CloseHandle(hV);
            }
        }
    }
}

static BOOL CopyFileWithProgress(const char *src, const char *dst, WorkerData *data, double startMB, double fileTotalMB) {
    HANDLE hSrc = CreateFileA(src, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (hSrc == INVALID_HANDLE_VALUE) return FALSE;

    HANDLE hDst = CreateFileA(dst, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hDst == INVALID_HANDLE_VALUE) {
        CloseHandle(hSrc);
        return FALSE;
    }

    BYTE *buf = (BYTE *)malloc(BUFFER_SIZE);
    if (!buf) {
        CloseHandle(hSrc);
        CloseHandle(hDst);
        return FALSE;
    }

    DWORD r = 0, w = 0;
    LONGLONG fileCopied = 0;
    DWORD startTime = GetTickCount();

    while (ReadFile(hSrc, buf, BUFFER_SIZE, &r, NULL) && r > 0) {
        if (!WriteFile(hDst, buf, r, &w, NULL) || w != r) {
            free(buf);
            CloseHandle(hSrc);
            CloseHandle(hDst);
            return FALSE;
        }
        fileCopied += w;
        data->writtenMB = startMB + ((double)fileCopied / (1024.0 * 1024.0));
        DWORD el = GetTickCount() - startTime;
        if (el == 0) el = 1;
        data->speedMBps = ((double)fileCopied / (1024.0 * 1024.0)) / ((double)el / 1000.0);
        data->percent = (int)((data->writtenMB * 100.0) / (data->totalMB > 0 ? data->totalMB : 1.0));
        if (data->percent > 99) data->percent = 99;
    }

    FlushFileBuffers(hDst);
    free(buf);
    CloseHandle(hSrc);
    CloseHandle(hDst);
    return TRUE;
}

DWORD WINAPI WorkerThread(LPVOID lpParam) {
    WorkerData *data = (WorkerData *)lpParam;
    data->isRunning = TRUE;
    data->percent = 0;
    data->writtenMB = 0;
    data->speedMBps = 0;
    data->success = FALSE;
    data->errorMsg[0] = '\0';

    if (data->isRawFlash) {
        // Raw DD Hybrid Flash
        HANDLE hIso = CreateFileA(data->isoPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
        if (hIso == INVALID_HANDLE_VALUE) {
            snprintf(data->errorMsg, sizeof(data->errorMsg), "Could not open ISO file (Error %lu)", GetLastError());
            data->isRunning = FALSE;
            return 1;
        }
        LARGE_INTEGER isoSize;
        GetFileSizeEx(hIso, &isoSize);
        data->totalMB = (double)isoSize.QuadPart / (1024.0 * 1024.0);

        DismountDriveVolumes(data->diskNumber);

        char diskPath[64];
        snprintf(diskPath, sizeof(diskPath), "\\\\.\\PhysicalDrive%d", data->diskNumber);
        HANDLE hDisk = CreateFileA(diskPath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
        if (hDisk == INVALID_HANDLE_VALUE) {
            snprintf(data->errorMsg, sizeof(data->errorMsg), "Access Denied: Please run as Administrator.");
            CloseHandle(hIso);
            data->isRunning = FALSE;
            return 1;
        }

        BYTE *buf = (BYTE *)malloc(BUFFER_SIZE);
        DWORD r = 0, w = 0;
        LONGLONG total = 0;
        DWORD st = GetTickCount();

        while (ReadFile(hIso, buf, BUFFER_SIZE, &r, NULL) && r > 0) {
            if (!WriteFile(hDisk, buf, r, &w, NULL) || w != r) {
                snprintf(data->errorMsg, sizeof(data->errorMsg), "Write error to physical drive.");
                free(buf);
                CloseHandle(hDisk);
                CloseHandle(hIso);
                data->isRunning = FALSE;
                return 1;
            }
            total += w;
            data->writtenMB = (double)total / (1024.0 * 1024.0);
            DWORD el = GetTickCount() - st;
            if (el == 0) el = 1;
            data->speedMBps = data->writtenMB / ((double)el / 1000.0);
            data->percent = (int)((total * 100) / isoSize.QuadPart);
        }

        FlushFileBuffers(hDisk);
        free(buf);
        CloseHandle(hDisk);
        CloseHandle(hIso);

        HANDLE hRefresh = CreateFileA(diskPath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
        if (hRefresh != INVALID_HANDLE_VALUE) {
            DWORD ret = 0;
            DeviceIoControl(hRefresh, IOCTL_DISK_UPDATE_PROPERTIES, NULL, 0, NULL, 0, &ret, NULL);
            CloseHandle(hRefresh);
        }

        data->percent = 100;
        data->success = TRUE;
        data->isRunning = FALSE;
        return 0;
    }

    // =========================================================================
    // Rufus-Style Mode: Make USB Executable while remaining File Explorer Ready
    // =========================================================================
    char driveRoot[16];
    snprintf(driveRoot, sizeof(driveRoot), "%c:\\", data->targetDriveLetter);

    // 1. Create bootloader directory tree
    char dirEfi[MAX_PATH], dirGrub[MAX_PATH], dirBoot[MAX_PATH];
    snprintf(dirEfi, sizeof(dirEfi), "%c:\\EFI\\BOOT", data->targetDriveLetter);
    snprintf(dirBoot, sizeof(dirBoot), "%c:\\boot", data->targetDriveLetter);
    snprintf(dirGrub, sizeof(dirGrub), "%c:\\boot\\grub", data->targetDriveLetter);

    CreateDirectoryA(dirBoot, NULL);
    CreateDirectoryA(dirGrub, NULL);
    char dirEfiBase[MAX_PATH];
    snprintf(dirEfiBase, sizeof(dirEfiBase), "%c:\\EFI", data->targetDriveLetter);
    CreateDirectoryA(dirEfiBase, NULL);
    CreateDirectoryA(dirEfi, NULL);

    // Calculate total size to copy
    double totalBytes = 0;
    char srcEfi[MAX_PATH], srcVmlinuz[MAX_PATH], srcInitrd[MAX_PATH];
    snprintf(srcEfi, sizeof(srcEfi), "%sbootloader\\EFI\\BOOT\\BOOTX64.EFI", g_appDir);
    snprintf(srcVmlinuz, sizeof(srcVmlinuz), "%sbootloader\\boot\\vmlinuz", g_appDir);
    snprintf(srcInitrd, sizeof(srcInitrd), "%sbootloader\\boot\\initramfs.gz", g_appDir);

    WIN32_FILE_ATTRIBUTE_DATA fad;
    if (GetFileAttributesExA(srcEfi, GetFileExInfoStandard, &fad)) {
        totalBytes += ((LONGLONG)fad.nFileSizeHigh << 32) + fad.nFileSizeLow;
    }
    if (GetFileAttributesExA(srcVmlinuz, GetFileExInfoStandard, &fad)) {
        totalBytes += ((LONGLONG)fad.nFileSizeHigh << 32) + fad.nFileSizeLow;
    }
    if (GetFileAttributesExA(srcInitrd, GetFileExInfoStandard, &fad)) {
        totalBytes += ((LONGLONG)fad.nFileSizeHigh << 32) + fad.nFileSizeLow;
    }
    if (data->copyIsoFile && GetFileAttributesExA(data->isoPath, GetFileExInfoStandard, &fad)) {
        totalBytes += ((LONGLONG)fad.nFileSizeHigh << 32) + fad.nFileSizeLow;
    }
    data->totalMB = totalBytes / (1024.0 * 1024.0);

    // 2. Install BOOTX64.EFI
    char dstEfi[MAX_PATH];
    snprintf(dstEfi, sizeof(dstEfi), "%c:\\EFI\\BOOT\\BOOTX64.EFI", data->targetDriveLetter);
    CopyFileWithProgress(srcEfi, dstEfi, data, 0, 6.2);

    // 3. Write grub.cfg configured for loopback bootos.iso AND direct kernel boot
    char dstGrubCfg[MAX_PATH];
    snprintf(dstGrubCfg, sizeof(dstGrubCfg), "%c:\\boot\\grub\\grub.cfg", data->targetDriveLetter);
    FILE *fCfg = fopen(dstGrubCfg, "w");
    if (fCfg) {
        fprintf(fCfg,
            "set default=\"0\"\n"
            "set timeout=5\n\n"
            "# 1. Direct Kernel Boot (100%% DRAM Resident)\n"
            "menuentry \"BootOS (Fast DRAM Boot)\" {\n"
            "    search --no-floppy --set=root --file /boot/vmlinuz\n"
            "    linux /boot/vmlinuz console=tty0 console=tty1 init=/init\n"
            "    initrd /boot/initramfs.gz\n"
            "}\n\n"
            "# 2. Loopback ISO Boot (Copy bootos.iso here via File Manager)\n"
            "menuentry \"BootOS (Execute bootos.iso in DRAM)\" {\n"
            "    search --no-floppy --set=root --file /bootos.iso\n"
            "    loopback loop ($root)/bootos.iso\n"
            "    linux (loop)/boot/vmlinuz console=tty0 console=tty1 init=/init\n"
            "    initrd (loop)/boot/initramfs.gz\n"
            "}\n\n"
            "menuentry \"BootOS (Quiet Mode)\" {\n"
            "    search --no-floppy --set=root --file /boot/vmlinuz\n"
            "    linux /boot/vmlinuz quiet console=tty0 console=tty1 init=/init\n"
            "    initrd /boot/initramfs.gz\n"
            "}\n");
        fclose(fCfg);
    }

    // 4. Install kernel & initramfs
    char dstVmlinuz[MAX_PATH], dstInitrd[MAX_PATH];
    snprintf(dstVmlinuz, sizeof(dstVmlinuz), "%c:\\boot\\vmlinuz", data->targetDriveLetter);
    snprintf(dstInitrd, sizeof(dstInitrd), "%c:\\boot\\initramfs.gz", data->targetDriveLetter);
    CopyFileWithProgress(srcVmlinuz, dstVmlinuz, data, data->writtenMB, 11.0);
    CopyFileWithProgress(srcInitrd, dstInitrd, data, data->writtenMB, 391.0);

    // 5. If copy ISO requested, copy bootos.iso to root of USB
    if (data->copyIsoFile) {
        char dstIso[MAX_PATH];
        snprintf(dstIso, sizeof(dstIso), "%c:\\bootos.iso", data->targetDriveLetter);
        CopyFileWithProgress(data->isoPath, dstIso, data, data->writtenMB, data->totalMB - data->writtenMB);
    }

    data->percent = 100;
    data->success = TRUE;
    data->isRunning = FALSE;
    return 0;
}

void RefreshDriveList(void) {
    SendMessage(g_hComboDrives, CB_RESETCONTENT, 0, 0);
    g_driveCount = ScanDrives(g_drives, 32);

    int usbIdx = -1;
    int itemsAdded = 0;

    for (int i = 0; i < g_driveCount; i++) {
        // Strictly shield C: and D: internal drives
        if (g_drives[i].isSystem || g_drives[i].letter == 'C' || g_drives[i].letter == 'c' || g_drives[i].letter == 'D' || g_drives[i].letter == 'd' || !g_drives[i].isUsb) continue;

        char itemText[256];
        char letStr[16] = "";
        if (g_drives[i].letter != ' ') {
            snprintf(letStr, sizeof(letStr), "[Drive %c:] ", g_drives[i].letter);
        }

        const char *tag = g_drives[i].isUsb ? "USB" : g_drives[i].busType;
        snprintf(itemText, sizeof(itemText), "%s%s %s (%.1f GB) - PhysicalDrive%d",
                 letStr, tag, g_drives[i].product, g_drives[i].sizeGB, g_drives[i].diskNumber);

        int pos = (int)SendMessage(g_hComboDrives, CB_ADDSTRING, 0, (LPARAM)itemText);
        SendMessage(g_hComboDrives, CB_SETITEMDATA, pos, (LPARAM)i);

        if (g_drives[i].isUsb && usbIdx == -1) {
            usbIdx = pos;
        }
        itemsAdded++;
    }

    if (itemsAdded == 0) {
        SendMessage(g_hComboDrives, CB_ADDSTRING, 0, (LPARAM)"(No removable USB drives detected - insert USB and click Refresh)");
        SendMessage(g_hComboDrives, CB_SETCURSEL, 0, 0);
        EnableWindow(g_hBtnMakeExec, FALSE);
        EnableWindow(g_hBtnRawFlash, FALSE);
    } else {
        SendMessage(g_hComboDrives, CB_SETCURSEL, usbIdx >= 0 ? usbIdx : 0, 0);
        EnableWindow(g_hBtnMakeExec, TRUE);
        EnableWindow(g_hBtnRawFlash, TRUE);
    }
}

void BrowseForIso(HWND hWnd) {
    OPENFILENAMEA ofn;
    char szFile[MAX_PATH] = "";
    memset(&ofn, 0, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = hWnd;
    ofn.lpstrFile = szFile;
    ofn.nMaxFile = sizeof(szFile);
    ofn.lpstrFilter = "BootOS ISO (*.iso)\0*.iso\0All Files (*.*)\0*.*\0";
    ofn.nFilterIndex = 1;
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST;

    if (GetOpenFileNameA(&ofn)) {
        strncpy(g_isoPath, szFile, sizeof(g_isoPath));
        SetWindowTextA(g_hEditIso, g_isoPath);

        HANDLE hF = CreateFileA(g_isoPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
        if (hF != INVALID_HANDLE_VALUE) {
            LARGE_INTEGER sz;
            GetFileSizeEx(hF, &sz);
            CloseHandle(hF);
            char stats[128];
            snprintf(stats, sizeof(stats), "Selected ISO: %.1f MB", (double)sz.QuadPart / (1024.0 * 1024.0));
            SetWindowTextA(g_hStatusLabel, stats);
        }
    }
}

void StartOperation(HWND hWnd, BOOL isRaw) {
    int curSel = (int)SendMessage(g_hComboDrives, CB_GETCURSEL, 0, 0);
    if (curSel == CB_ERR) {
        MessageBoxA(hWnd, "Please select a target USB drive.", "No Drive Selected", MB_OK | MB_ICONWARNING);
        return;
    }

    int driveIdx = (int)SendMessage(g_hComboDrives, CB_GETITEMDATA, curSel, 0);
    if (driveIdx < 0 || driveIdx >= g_driveCount) {
        MessageBoxA(hWnd, "Please select a valid USB drive.", "Invalid Selection", MB_OK | MB_ICONWARNING);
        return;
    }

    GuiDriveInfo *target = &g_drives[driveIdx];
    if (target->isSystem || target->letter == 'C' || target->letter == 'c' || target->letter == 'D' || target->letter == 'd' || !target->isUsb) {
        MessageBoxA(hWnd, "Protected Drive: C: and D: internal drives are strictly shielded and cannot be modified!", "Drive Protected", MB_OK | MB_ICONERROR);
        return;
    }

    if (target->letter == ' ' && !isRaw) {
        MessageBoxA(hWnd, "Selected USB drive does not have a Windows drive letter.\nUse 'Raw Flash' or assign a drive letter in Disk Management.", "No Drive Letter", MB_OK | MB_ICONWARNING);
        return;
    }

    char warnMsg[512];
    if (isRaw) {
        snprintf(warnMsg, sizeof(warnMsg),
                 "WARNING: Raw flashing will completely OVERWRITE PhysicalDrive%d (%s, %.1f GB)!\n\n"
                 "Are you sure you want to write raw hybrid sectors to this drive?",
                 target->diskNumber, target->product, target->sizeGB);
    } else {
        snprintf(warnMsg, sizeof(warnMsg),
                 "Make USB Executable (Rufus-Style):\n\n"
                 "Target: Drive %c: (%s, %.1f GB)\n\n"
                 "This will install the UEFI bootloader and BootOS files to Drive %c:.\n"
                 "Your drive remains 100%% accessible in Windows File Explorer!\n"
                 "You will be able to copy or update bootos.iso via File Manager anytime.\n\n"
                 "Proceed?",
                 target->letter, target->product, target->sizeGB, target->letter);
    }

    int res = MessageBoxA(hWnd, warnMsg, isRaw ? "Confirm Raw Flash" : "Make USB Executable", MB_YESNO | MB_ICONINFORMATION);
    if (res != IDYES) return;

    EnableWindow(g_hBtnMakeExec, FALSE);
    EnableWindow(g_hBtnRawFlash, FALSE);
    EnableWindow(g_hBtnBrowse, FALSE);
    EnableWindow(g_hBtnRefresh, FALSE);
    EnableWindow(g_hComboDrives, FALSE);
    EnableWindow(g_hBtnRunVBox, FALSE);

    SendMessage(g_hProgress, PBM_SETPOS, 0, 0);
    SetWindowTextA(g_hStatusLabel, isRaw ? "Writing raw sectors to USB..." : "Making USB drive bootable and copying BootOS files...");
    SetWindowTextA(g_hStatsLabel, "Starting...");

    strncpy(g_worker.isoPath, g_isoPath, sizeof(g_worker.isoPath));
    g_worker.diskNumber = target->diskNumber;
    g_worker.targetDriveLetter = target->letter;
    g_worker.isRawFlash = isRaw;
    g_worker.copyIsoFile = (SendMessage(g_hChkCopyIso, BM_GETCHECK, 0, 0) == BST_CHECKED);
    g_worker.hWnd = hWnd;

    HANDLE hThread = CreateThread(NULL, 0, WorkerThread, &g_worker, 0, NULL);
    if (hThread) {
        CloseHandle(hThread);
        SetTimer(hWnd, ID_TIMER_PROGRESS, 100, NULL);
    } else {
        MessageBoxA(hWnd, "Failed to start background worker thread.", "Error", MB_OK | MB_ICONERROR);
        EnableWindow(g_hBtnMakeExec, TRUE);
        EnableWindow(g_hBtnRawFlash, TRUE);
        EnableWindow(g_hBtnBrowse, TRUE);
        EnableWindow(g_hBtnRefresh, TRUE);
        EnableWindow(g_hComboDrives, TRUE);
        EnableWindow(g_hBtnRunVBox, TRUE);
    }
}

void ExecuteInVirtualBox(HWND hWnd) {
    const char *vboxPath = "C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe";
    DWORD attr = GetFileAttributesA(vboxPath);
    if (attr != INVALID_FILE_ATTRIBUTES) {
        SetWindowTextA(g_hStatusLabel, "Launching BootOS inside Oracle VirtualBox...");
        system("vde-vlm start vmbootos2 --gui 2>nul || \"C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe\" startvm vmbootos2 --type gui");
        SetWindowTextA(g_hStatusLabel, "VirtualBox machine window opened!");
        return;
    }

    MessageBoxA(hWnd, "Oracle VirtualBox was not found at:\nC:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe\n\nPlease install VirtualBox or use 'Make USB Executable' to boot on your PC!",
                "Oracle VirtualBox Not Found", MB_OK | MB_ICONINFORMATION);
}

LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
        case WM_CREATE: {
            g_hFontNormal = CreateFontA(15, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, ANSI_CHARSET,
                                        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                                        DEFAULT_PITCH | FF_SWISS, "Segoe UI");
            g_hFontBold = CreateFontA(15, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET,
                                      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                                      DEFAULT_PITCH | FF_SWISS, "Segoe UI");
            g_hFontHeader = CreateFontA(19, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET,
                                        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                                        DEFAULT_PITCH | FF_SWISS, "Segoe UI");

            // Header Banner
            HWND hTitle = CreateWindowA("STATIC", "BootOS USB Maker & Bootloader",
                                        WS_CHILD | WS_VISIBLE, 20, 12, 540, 24, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hTitle, WM_SETFONT, (WPARAM)g_hFontHeader, TRUE);

            HWND hSub = CreateWindowA("STATIC", "Make any USB drive bootable/executable (Rufus-style) so you can copy bootos.iso in File Explorer.",
                                      WS_CHILD | WS_VISIBLE, 20, 38, 540, 18, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hSub, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            // Step 1: Select Target USB Drive
            HWND hLbl1 = CreateWindowA("STATIC", "1. Target USB Drive (Select from connected USBs):",
                                       WS_CHILD | WS_VISIBLE, 20, 68, 520, 18, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hLbl1, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);

            g_hComboDrives = CreateWindowA("COMBOBOX", "",
                                           WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
                                           20, 90, 420, 220, hWnd, (HMENU)ID_COMBO_DRIVES, g_hInstance, NULL);
            SendMessage(g_hComboDrives, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            g_hBtnRefresh = CreateWindowA("BUTTON", "Refresh",
                                          WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                          450, 89, 95, 27, hWnd, (HMENU)ID_BTN_REFRESH, g_hInstance, NULL);
            SendMessage(g_hBtnRefresh, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            // Step 2: BootOS ISO Image
            HWND hLbl2 = CreateWindowA("STATIC", "2. BootOS ISO Image:",
                                       WS_CHILD | WS_VISIBLE, 20, 128, 520, 18, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hLbl2, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);

            g_hEditIso = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", g_isoPath,
                                         WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_READONLY,
                                         20, 150, 420, 26, hWnd, (HMENU)ID_EDIT_ISO, g_hInstance, NULL);
            SendMessage(g_hEditIso, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            g_hBtnBrowse = CreateWindowA("BUTTON", "Browse...",
                                         WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                         450, 149, 95, 28, hWnd, (HMENU)ID_BTN_BROWSE, g_hInstance, NULL);
            SendMessage(g_hBtnBrowse, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            g_hChkCopyIso = CreateWindowA("BUTTON", "Also copy bootos.iso to USB root (File Explorer drag-and-drop ready)",
                                          WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
                                          20, 182, 520, 20, hWnd, (HMENU)ID_CHK_COPY_ISO, g_hInstance, NULL);
            SendMessage(g_hChkCopyIso, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);
            SendMessage(g_hChkCopyIso, BM_SETCHECK, BST_CHECKED, 0);

            // Step 3: Progress
            HWND hLbl3 = CreateWindowA("STATIC", "3. Progress & Status:",
                                       WS_CHILD | WS_VISIBLE, 20, 212, 520, 18, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hLbl3, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);

            g_hProgress = CreateWindowExA(0, PROGRESS_CLASSA, "",
                                          WS_CHILD | WS_VISIBLE | PBS_SMOOTH,
                                          20, 234, 525, 22, hWnd, (HMENU)ID_PROGRESS, g_hInstance, NULL);
            SendMessage(g_hProgress, PBM_SETRANGE32, 0, 100);

            g_hStatusLabel = CreateWindowA("STATIC", "Ready. Pick your USB and click 'Make USB Executable'.",
                                           WS_CHILD | WS_VISIBLE, 20, 262, 525, 18, hWnd, (HMENU)ID_STATUS_LABEL, g_hInstance, NULL);
            SendMessage(g_hStatusLabel, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            g_hStatsLabel = CreateWindowA("STATIC", "",
                                          WS_CHILD | WS_VISIBLE, 20, 282, 525, 18, hWnd, (HMENU)ID_STATS_LABEL, g_hInstance, NULL);
            SendMessage(g_hStatsLabel, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            // Action Buttons
            g_hBtnRawFlash = CreateWindowA("BUTTON", "⚡ Flash USB (Legacy BIOS + UEFI)",
                                           WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
                                           20, 312, 230, 36, hWnd, (HMENU)ID_BTN_RAW_FLASH, g_hInstance, NULL);
            SendMessage(g_hBtnRawFlash, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);

            g_hBtnMakeExec = CreateWindowA("BUTTON", "Copy Files (UEFI)",
                                           WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                           260, 312, 115, 36, hWnd, (HMENU)ID_BTN_MAKE_EXEC, g_hInstance, NULL);
            SendMessage(g_hBtnMakeExec, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            g_hBtnRunVBox = CreateWindowA("BUTTON", "▶ VirtualBox",
                                          WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                          385, 312, 95, 36, hWnd, (HMENU)ID_BTN_RUN_VBOX, g_hInstance, NULL);
            SendMessage(g_hBtnRunVBox, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            HWND hBtnExit = CreateWindowA("BUTTON", "Exit",
                                          WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                          490, 312, 55, 36, hWnd, (HMENU)ID_BTN_EXIT, g_hInstance, NULL);
            SendMessage(hBtnExit, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            RefreshDriveList();
            break;
        }

        case WM_TIMER: {
            if (wParam == ID_TIMER_PROGRESS) {
                if (g_worker.isRunning) {
                    SendMessage(g_hProgress, PBM_SETPOS, g_worker.percent, 0);
                    char statText[128];
                    snprintf(statText, sizeof(statText), "Progress: %d%% (%.1f / %.1f MB) @ %.1f MB/s",
                             g_worker.percent, g_worker.writtenMB, g_worker.totalMB, g_worker.speedMBps);
                    SetWindowTextA(g_hStatsLabel, statText);
                } else {
                    KillTimer(hWnd, ID_TIMER_PROGRESS);
                    EnableWindow(g_hBtnMakeExec, TRUE);
                    EnableWindow(g_hBtnRawFlash, TRUE);
                    EnableWindow(g_hBtnBrowse, TRUE);
                    EnableWindow(g_hBtnRefresh, TRUE);
                    EnableWindow(g_hComboDrives, TRUE);
                    EnableWindow(g_hBtnRunVBox, TRUE);

                    if (g_worker.success) {
                        SendMessage(g_hProgress, PBM_SETPOS, 100, 0);
                        if (g_worker.isRawFlash) {
                            SetWindowTextA(g_hStatusLabel, "SUCCESS: BootOS flashed with Hybrid MBR + UEFI support!");
                            SetWindowTextA(g_hStatsLabel, "Ready to boot on your Old PC (Legacy BIOS) or modern UEFI PC.");

                            MessageBoxA(hWnd,
                                        "SUCCESS: BootOS has been flashed to USB with Hybrid MBR support!\n\n"
                                        "How to boot your Old PC (Windows 7):\n"
                                        " 1. Plug the USB into your old PC.\n"
                                        " 2. Turn on the PC and IMMEDIATELY tap the Boot Menu key:\n"
                                        "    - Dell / Lenovo / Acer: F12\n"
                                        "    - HP: F9 or Esc\n"
                                        "    - ASUS / MSI: F8 or F11\n"
                                        " 3. Select 'USB Storage Device' or 'USB-HDD' from the menu.\n"
                                        " 4. BootOS will start immediately into DRAM!",
                                        "Bootable USB Ready (Old PCs & UEFI)", MB_OK | MB_ICONINFORMATION);
                        } else {
                            SetWindowTextA(g_hStatusLabel, "SUCCESS: USB drive configured with UEFI bootloader!");
                            SetWindowTextA(g_hStatsLabel, "Drive opened in File Explorer. Drag-and-drop bootos.iso anytime.");

                            if (g_worker.targetDriveLetter != ' ') {
                                char rootPath[16];
                                snprintf(rootPath, sizeof(rootPath), "%c:\\", g_worker.targetDriveLetter);
                                ShellExecuteA(NULL, "open", "explorer.exe", rootPath, NULL, SW_SHOWNORMAL);
                            }

                            MessageBoxA(hWnd,
                                        "Your USB flash drive is configured for UEFI systems.\n\n"
                                        "Note: For older Legacy BIOS PCs (like Windows 7 PCs),\n"
                                        "use 'Flash USB (Legacy BIOS + UEFI)' to write the MBR boot code.",
                                        "UEFI USB Ready", MB_OK | MB_ICONINFORMATION);
                        }
                    } else {
                        SendMessage(g_hProgress, PBM_SETPOS, 0, 0);
                        SetWindowTextA(g_hStatusLabel, "Operation failed.");
                        SetWindowTextA(g_hStatsLabel, g_worker.errorMsg);
                        MessageBoxA(hWnd, g_worker.errorMsg, "Operation Failed", MB_OK | MB_ICONERROR);
                    }
                }
            }
            break;
        }

        case WM_COMMAND: {
            int wmId = LOWORD(wParam);
            switch (wmId) {
                case ID_BTN_BROWSE:
                    BrowseForIso(hWnd);
                    break;
                case ID_BTN_REFRESH:
                    RefreshDriveList();
                    SetWindowTextA(g_hStatusLabel, "Drive list refreshed.");
                    break;
                case ID_BTN_MAKE_EXEC:
                    StartOperation(hWnd, FALSE);
                    break;
                case ID_BTN_RAW_FLASH:
                    StartOperation(hWnd, TRUE);
                    break;
                case ID_BTN_RUN_VBOX:
                    ExecuteInVirtualBox(hWnd);
                    break;
                case ID_BTN_EXIT:
                    PostQuitMessage(0);
                    break;
            }
            break;
        }

        case WM_DESTROY: {
            if (g_hFontNormal) DeleteObject(g_hFontNormal);
            if (g_hFontBold) DeleteObject(g_hFontBold);
            if (g_hFontHeader) DeleteObject(g_hFontHeader);
            PostQuitMessage(0);
            break;
        }

        default:
            return DefWindowProcA(hWnd, message, wParam, lParam);
    }
    return 0;
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    g_hInstance = hInstance;

    if (!IsUserAdmin()) {
        char exePath[MAX_PATH];
        GetModuleFileNameA(NULL, exePath, sizeof(exePath));
        HINSTANCE res = ShellExecuteA(NULL, "runas", exePath, lpCmdLine, NULL, SW_SHOWNORMAL);
        if ((INT_PTR)res > 32) return 0;
    }

    char exePath[MAX_PATH];
    GetModuleFileNameA(NULL, exePath, sizeof(exePath));
    strncpy(g_appDir, exePath, sizeof(g_appDir));
    char *lastSlash = strrchr(g_appDir, '\\');
    if (lastSlash) *(lastSlash + 1) = '\0';

    snprintf(g_isoPath, sizeof(g_isoPath), "%sbootos.iso", g_appDir);
    if (GetFileAttributesA(g_isoPath) == INVALID_FILE_ATTRIBUTES) {
        snprintf(g_isoPath, sizeof(g_isoPath), "%s..\\bootos.iso", g_appDir);
    }
    if (GetFileAttributesA(g_isoPath) == INVALID_FILE_ATTRIBUTES) {
        snprintf(g_isoPath, sizeof(g_isoPath), "bootos.iso");
    }

    INITCOMMONCONTROLSEX icex;
    icex.dwSize = sizeof(INITCOMMONCONTROLSEX);
    icex.dwICC = ICC_WIN95_CLASSES | ICC_PROGRESS_CLASS;
    InitCommonControlsEx(&icex);

    WNDCLASSEXA wcex;
    memset(&wcex, 0, sizeof(wcex));
    wcex.cbSize = sizeof(WNDCLASSEXA);
    wcex.style = CS_HREDRAW | CS_VREDRAW;
    wcex.lpfnWndProc = WndProc;
    wcex.hInstance = hInstance;
    wcex.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    wcex.hCursor = LoadCursor(NULL, IDC_ARROW);
    wcex.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wcex.lpszClassName = "BootOSMakerWndClass";
    RegisterClassExA(&wcex);

    int w = 580;
    int h = 410;
    int x = (GetSystemMetrics(SM_CXSCREEN) - w) / 2;
    int y = (GetSystemMetrics(SM_CYSCREEN) - h) / 2;

    g_hMainWnd = CreateWindowExA(0, "BootOSMakerWndClass",
                                 "BootOS USB Maker & Bootloader (Rufus-Style)",
                                 WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
                                 x, y, w, h, NULL, NULL, hInstance, NULL);

    if (!g_hMainWnd) return 1;

    ShowWindow(g_hMainWnd, nCmdShow);
    UpdateWindow(g_hMainWnd);

    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }

    return (int)msg.wParam;
}
