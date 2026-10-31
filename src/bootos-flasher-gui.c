#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <commctrl.h>
#include <commdlg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <shellapi.h>

#define ID_BTN_BROWSE     101
#define ID_COMBO_DRIVES   102
#define ID_BTN_REFRESH    103
#define ID_BTN_FLASH      104
#define ID_BTN_RUNVM      105
#define ID_BTN_EXIT       106
#define ID_PROGRESS       107
#define ID_EDIT_ISO       108
#define ID_STATUS_LABEL   109
#define ID_STATS_LABEL    110
#define ID_TIMER_PROGRESS 201

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
    int diskNumber;
    volatile BOOL isRunning;
    volatile int percent;
    volatile double writtenMB;
    volatile double totalMB;
    volatile double speedMBps;
    volatile BOOL success;
    char errorMsg[256];
} FlashWorkerData;

// Global state
static HINSTANCE g_hInstance = NULL;
static HWND g_hMainWnd = NULL;
static HWND g_hEditIso = NULL;
static HWND g_hComboDrives = NULL;
static HWND g_hBtnBrowse = NULL;
static HWND g_hBtnRefresh = NULL;
static HWND g_hBtnFlash = NULL;
static HWND g_hBtnRunVm = NULL;
static HWND g_hProgress = NULL;
static HWND g_hStatusLabel = NULL;
static HWND g_hStatsLabel = NULL;
static HFONT g_hFontNormal = NULL;
static HFONT g_hFontBold = NULL;
static HFONT g_hFontHeader = NULL;

static GuiDriveInfo g_drives[32];
static int g_driveCount = 0;
static char g_isoPath[MAX_PATH] = "";
static FlashWorkerData g_worker;

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

                // Get drive size
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

DWORD WINAPI FlashWorkerThread(LPVOID lpParam) {
    FlashWorkerData *data = (FlashWorkerData *)lpParam;
    data->isRunning = TRUE;
    data->percent = 0;
    data->writtenMB = 0;
    data->speedMBps = 0;
    data->success = FALSE;
    data->errorMsg[0] = '\0';

    HANDLE hIso = CreateFileA(data->isoPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (hIso == INVALID_HANDLE_VALUE) {
        snprintf(data->errorMsg, sizeof(data->errorMsg), "Could not open ISO file (Error %lu)", GetLastError());
        data->isRunning = FALSE;
        return 1;
    }

    LARGE_INTEGER isoSize;
    if (!GetFileSizeEx(hIso, &isoSize)) {
        snprintf(data->errorMsg, sizeof(data->errorMsg), "Could not read ISO file size.");
        CloseHandle(hIso);
        data->isRunning = FALSE;
        return 1;
    }
    data->totalMB = (double)isoSize.QuadPart / (1024.0 * 1024.0);

    DismountDriveVolumes(data->diskNumber);

    char diskPath[64];
    snprintf(diskPath, sizeof(diskPath), "\\\\.\\PhysicalDrive%d", data->diskNumber);
    HANDLE hDisk = CreateFileA(diskPath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (hDisk == INVALID_HANDLE_VALUE) {
        DWORD err = GetLastError();
        if (err == ERROR_ACCESS_DENIED) {
            snprintf(data->errorMsg, sizeof(data->errorMsg), "Access Denied: Please run as Administrator.");
        } else {
            snprintf(data->errorMsg, sizeof(data->errorMsg), "Could not open target drive %s (Error %lu)", diskPath, err);
        }
        CloseHandle(hIso);
        data->isRunning = FALSE;
        return 1;
    }

    BYTE *buffer = (BYTE *)malloc(BUFFER_SIZE);
    if (!buffer) {
        snprintf(data->errorMsg, sizeof(data->errorMsg), "Memory allocation failed.");
        CloseHandle(hDisk);
        CloseHandle(hIso);
        data->isRunning = FALSE;
        return 1;
    }

    DWORD bytesRead = 0, bytesWritten = 0;
    LONGLONG totalWritten = 0;
    DWORD startTime = GetTickCount();

    while (ReadFile(hIso, buffer, BUFFER_SIZE, &bytesRead, NULL) && bytesRead > 0) {
        if (!WriteFile(hDisk, buffer, bytesRead, &bytesWritten, NULL) || bytesWritten != bytesRead) {
            snprintf(data->errorMsg, sizeof(data->errorMsg), "Write failure at offset %lld (Error %lu)", totalWritten, GetLastError());
            free(buffer);
            CloseHandle(hDisk);
            CloseHandle(hIso);
            data->isRunning = FALSE;
            return 1;
        }

        totalWritten += bytesWritten;
        data->writtenMB = (double)totalWritten / (1024.0 * 1024.0);
        DWORD elapsedMs = GetTickCount() - startTime;
        if (elapsedMs == 0) elapsedMs = 1;
        data->speedMBps = data->writtenMB / ((double)elapsedMs / 1000.0);
        data->percent = (int)((totalWritten * 100) / isoSize.QuadPart);
    }

    FlushFileBuffers(hDisk);
    free(buffer);
    CloseHandle(hDisk);
    CloseHandle(hIso);

    // Refresh partition table
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

void RefreshDriveList(void) {
    SendMessage(g_hComboDrives, CB_RESETCONTENT, 0, 0);
    g_driveCount = ScanDrives(g_drives, 32);

    int usbIdx = -1;
    int itemsAdded = 0;

    for (int i = 0; i < g_driveCount; i++) {
        // Skip system disk
        if (g_drives[i].isSystem) continue;

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
        EnableWindow(g_hBtnFlash, FALSE);
    } else {
        SendMessage(g_hComboDrives, CB_SETCURSEL, usbIdx >= 0 ? usbIdx : 0, 0);
        EnableWindow(g_hBtnFlash, TRUE);
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
            snprintf(stats, sizeof(stats), "Selected: %.1f MB", (double)sz.QuadPart / (1024.0 * 1024.0));
            SetWindowTextA(g_hStatusLabel, stats);
        }
    }
}

void StartFlashing(HWND hWnd) {
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
    if (target->isSystem) {
        MessageBoxA(hWnd, "Cannot flash to the Windows system disk!", "System Disk Protected", MB_OK | MB_ICONERROR);
        return;
    }

    if (GetFileAttributesA(g_isoPath) == INVALID_FILE_ATTRIBUTES) {
        MessageBoxA(hWnd, "The selected ISO file could not be found.\nPlease click 'Browse' and select bootos.iso.", "ISO File Not Found", MB_OK | MB_ICONERROR);
        return;
    }

    // Confirmation dialog
    char warnMsg[512];
    snprintf(warnMsg, sizeof(warnMsg),
             "WARNING: ALL DATA on the selected drive will be permanently ERASED!\n\n"
             "Drive: %s (%.1f GB)\n"
             "Physical Drive: PhysicalDrive%d\n"
             "ISO to Flash: %s\n\n"
             "Are you sure you want to proceed and flash BootOS to this drive?",
             target->product, target->sizeGB, target->diskNumber, g_isoPath);

    int res = MessageBoxA(hWnd, warnMsg, "Confirm USB Drive Overwrite", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2);
    if (res != IDYES) return;

    // Disable controls during write
    EnableWindow(g_hBtnFlash, FALSE);
    EnableWindow(g_hBtnBrowse, FALSE);
    EnableWindow(g_hBtnRefresh, FALSE);
    EnableWindow(g_hComboDrives, FALSE);
    EnableWindow(g_hBtnRunVm, FALSE);

    SendMessage(g_hProgress, PBM_SETPOS, 0, 0);
    SetWindowTextA(g_hStatusLabel, "Writing BootOS hybrid ISO to USB drive... Please DO NOT unplug the USB!");
    SetWindowTextA(g_hStatsLabel, "Starting write stream...");

    strncpy(g_worker.isoPath, g_isoPath, sizeof(g_worker.isoPath));
    g_worker.diskNumber = target->diskNumber;
    g_worker.hWnd = hWnd;

    HANDLE hThread = CreateThread(NULL, 0, FlashWorkerThread, &g_worker, 0, NULL);
    if (hThread) {
        CloseHandle(hThread);
        SetTimer(hWnd, ID_TIMER_PROGRESS, 100, NULL);
    } else {
        MessageBoxA(hWnd, "Failed to start background worker thread.", "Error", MB_OK | MB_ICONERROR);
        EnableWindow(g_hBtnFlash, TRUE);
        EnableWindow(g_hBtnBrowse, TRUE);
        EnableWindow(g_hBtnRefresh, TRUE);
        EnableWindow(g_hComboDrives, TRUE);
        EnableWindow(g_hBtnRunVm, TRUE);
    }
}

void ExecuteInVM(HWND hWnd) {
    const char *vboxPath = "C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe";
    DWORD attr = GetFileAttributesA(vboxPath);
    if (attr != INVALID_FILE_ATTRIBUTES) {
        SetWindowTextA(g_hStatusLabel, "Launching BootOS inside Oracle VirtualBox...");
        system("vde-vlm start vmbootos2 --gui 2>nul || \"C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe\" startvm vmbootos2 --type gui");
        SetWindowTextA(g_hStatusLabel, "Virtual machine window opened!");
        return;
    }

    if (system("qemu-system-x86_64 --version >nul 2>&1") == 0) {
        SetWindowTextA(g_hStatusLabel, "Launching BootOS with QEMU...");
        char qcmd[512];
        snprintf(qcmd, sizeof(qcmd), "start qemu-system-x86_64 -m 2048 -cdrom \"%s\" -boot d", g_isoPath);
        system(qcmd);
        SetWindowTextA(g_hStatusLabel, "QEMU window opened!");
        return;
    }

    MessageBoxA(hWnd, "Neither VirtualBox nor QEMU was found.\nTo boot on your PC, select your USB drive and click 'Flash to USB'!",
                "Virtual Machine Not Found", MB_OK | MB_ICONINFORMATION);
}

LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
        case WM_CREATE: {
            g_hFontNormal = CreateFontA(16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, ANSI_CHARSET,
                                        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                                        DEFAULT_PITCH | FF_SWISS, "Segoe UI");
            g_hFontBold = CreateFontA(16, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET,
                                      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                                      DEFAULT_PITCH | FF_SWISS, "Segoe UI");
            g_hFontHeader = CreateFontA(20, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE, ANSI_CHARSET,
                                        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                                        DEFAULT_PITCH | FF_SWISS, "Segoe UI");

            // Header Banner
            HWND hTitle = CreateWindowA("STATIC", "BootOS USB Flasher & Runner",
                                        WS_CHILD | WS_VISIBLE, 20, 15, 520, 26, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hTitle, WM_SETFONT, (WPARAM)g_hFontHeader, TRUE);

            HWND hSub = CreateWindowA("STATIC", "100% RAM-Resident OS - Flashes bootable hybrid BIOS/UEFI media without Rufus.",
                                      WS_CHILD | WS_VISIBLE, 20, 42, 520, 20, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hSub, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            // Step 1: ISO Image
            HWND hLbl1 = CreateWindowA("STATIC", "1. BootOS ISO Image:",
                                       WS_CHILD | WS_VISIBLE, 20, 75, 500, 20, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hLbl1, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);

            g_hEditIso = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", g_isoPath,
                                         WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_READONLY,
                                         20, 98, 410, 26, hWnd, (HMENU)ID_EDIT_ISO, g_hInstance, NULL);
            SendMessage(g_hEditIso, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            g_hBtnBrowse = CreateWindowA("BUTTON", "Browse...",
                                         WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                         440, 97, 100, 28, hWnd, (HMENU)ID_BTN_BROWSE, g_hInstance, NULL);
            SendMessage(g_hBtnBrowse, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            // Step 2: Target USB Selection
            HWND hLbl2 = CreateWindowA("STATIC", "2. Target USB Drive (Select among connected USB drives):",
                                       WS_CHILD | WS_VISIBLE, 20, 138, 500, 20, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hLbl2, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);

            g_hComboDrives = CreateWindowA("COMBOBOX", "",
                                           WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
                                           20, 161, 410, 200, hWnd, (HMENU)ID_COMBO_DRIVES, g_hInstance, NULL);
            SendMessage(g_hComboDrives, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            g_hBtnRefresh = CreateWindowA("BUTTON", "Refresh",
                                          WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                          440, 160, 100, 28, hWnd, (HMENU)ID_BTN_REFRESH, g_hInstance, NULL);
            SendMessage(g_hBtnRefresh, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            // Step 3: Progress & Status
            HWND hLbl3 = CreateWindowA("STATIC", "3. Progress & Status:",
                                       WS_CHILD | WS_VISIBLE, 20, 205, 500, 20, hWnd, NULL, g_hInstance, NULL);
            SendMessage(hLbl3, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);

            g_hProgress = CreateWindowExA(0, PROGRESS_CLASSA, "",
                                          WS_CHILD | WS_VISIBLE | PBS_SMOOTH,
                                          20, 228, 520, 24, hWnd, (HMENU)ID_PROGRESS, g_hInstance, NULL);
            SendMessage(g_hProgress, PBM_SETRANGE32, 0, 100);

            g_hStatusLabel = CreateWindowA("STATIC", "Ready. Select your USB drive and click 'Flash to USB'.",
                                           WS_CHILD | WS_VISIBLE, 20, 258, 520, 20, hWnd, (HMENU)ID_STATUS_LABEL, g_hInstance, NULL);
            SendMessage(g_hStatusLabel, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            g_hStatsLabel = CreateWindowA("STATIC", "",
                                          WS_CHILD | WS_VISIBLE, 20, 278, 520, 20, hWnd, (HMENU)ID_STATS_LABEL, g_hInstance, NULL);
            SendMessage(g_hStatsLabel, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            // Action Buttons
            g_hBtnFlash = CreateWindowA("BUTTON", "⚡ Flash to USB",
                                        WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
                                        20, 315, 160, 36, hWnd, (HMENU)ID_BTN_FLASH, g_hInstance, NULL);
            SendMessage(g_hBtnFlash, WM_SETFONT, (WPARAM)g_hFontBold, TRUE);

            g_hBtnRunVm = CreateWindowA("BUTTON", "▶ Run in VM / Sandbox",
                                        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                        190, 315, 180, 36, hWnd, (HMENU)ID_BTN_RUNVM, g_hInstance, NULL);
            SendMessage(g_hBtnRunVm, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            HWND hBtnExit = CreateWindowA("BUTTON", "Exit",
                                          WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                          440, 315, 100, 36, hWnd, (HMENU)ID_BTN_EXIT, g_hInstance, NULL);
            SendMessage(hBtnExit, WM_SETFONT, (WPARAM)g_hFontNormal, TRUE);

            // Populate drives
            RefreshDriveList();
            break;
        }

        case WM_TIMER: {
            if (wParam == ID_TIMER_PROGRESS) {
                if (g_worker.isRunning) {
                    SendMessage(g_hProgress, PBM_SETPOS, g_worker.percent, 0);
                    char statText[128];
                    snprintf(statText, sizeof(statText), "Writing to USB: %d%% (%.1f / %.1f MB) @ %.1f MB/s",
                             g_worker.percent, g_worker.writtenMB, g_worker.totalMB, g_worker.speedMBps);
                    SetWindowTextA(g_hStatsLabel, statText);
                } else {
                    KillTimer(hWnd, ID_TIMER_PROGRESS);
                    EnableWindow(g_hBtnFlash, TRUE);
                    EnableWindow(g_hBtnBrowse, TRUE);
                    EnableWindow(g_hBtnRefresh, TRUE);
                    EnableWindow(g_hComboDrives, TRUE);
                    EnableWindow(g_hBtnRunVm, TRUE);

                    if (g_worker.success) {
                        SendMessage(g_hProgress, PBM_SETPOS, 100, 0);
                        SetWindowTextA(g_hStatusLabel, "SUCCESS: BootOS has been written to the USB drive!");
                        SetWindowTextA(g_hStatsLabel, "USB drive is now 100% bootable on Legacy BIOS and UEFI hardware.");
                        MessageBoxA(hWnd,
                                    "BootOS was successfully written to your USB flash drive!\n\n"
                                    "Your USB drive is now bootable:\n"
                                    "  - Compatible with Legacy BIOS and UEFI\n"
                                    "  - Runs 100% in DRAM (USB can be unplugged after boot)",
                                    "Flashing Complete", MB_OK | MB_ICONINFORMATION);
                    } else {
                        SendMessage(g_hProgress, PBM_SETPOS, 0, 0);
                        SetWindowTextA(g_hStatusLabel, "Flashing failed.");
                        SetWindowTextA(g_hStatsLabel, g_worker.errorMsg);
                        MessageBoxA(hWnd, g_worker.errorMsg, "Flashing Failed", MB_OK | MB_ICONERROR);
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
                case ID_BTN_FLASH:
                    StartFlashing(hWnd);
                    break;
                case ID_BTN_RUNVM:
                    ExecuteInVM(hWnd);
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

    // Check Administrator privileges - re-elevate if needed
    if (!IsUserAdmin()) {
        char exePath[MAX_PATH];
        GetModuleFileNameA(NULL, exePath, sizeof(exePath));
        HINSTANCE res = ShellExecuteA(NULL, "runas", exePath, lpCmdLine, NULL, SW_SHOWNORMAL);
        if ((INT_PTR)res > 32) {
            return 0; // Elevated process launched
        }
        // If user cancelled UAC, continue anyway but warn them
    }

    // Locate default bootos.iso next to executable or in parent directory
    char exePath[MAX_PATH];
    GetModuleFileNameA(NULL, exePath, sizeof(exePath));
    char dir[MAX_PATH];
    strncpy(dir, exePath, sizeof(dir));
    char *lastSlash = strrchr(dir, '\\');
    if (lastSlash) *(lastSlash + 1) = '\0';

    snprintf(g_isoPath, sizeof(g_isoPath), "%sbootos.iso", dir);
    if (GetFileAttributesA(g_isoPath) == INVALID_FILE_ATTRIBUTES) {
        snprintf(g_isoPath, sizeof(g_isoPath), "%s..\\bootos.iso", dir);
    }
    if (GetFileAttributesA(g_isoPath) == INVALID_FILE_ATTRIBUTES) {
        snprintf(g_isoPath, sizeof(g_isoPath), "bootos.iso");
    }

    // Initialize common controls for progress bar & modern UI
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
    wcex.lpszClassName = "BootOSFlasherWndClass";
    RegisterClassExA(&wcex);

    int w = 580;
    int h = 410;
    int x = (GetSystemMetrics(SM_CXSCREEN) - w) / 2;
    int y = (GetSystemMetrics(SM_CYSCREEN) - h) / 2;

    g_hMainWnd = CreateWindowExA(0, "BootOSFlasherWndClass",
                                 "BootOS USB Flasher (No Rufus Needed)",
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
