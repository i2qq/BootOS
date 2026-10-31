#include <windows.h>
#include <winioctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <shellapi.h>

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
} DriveInfo;

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

int ScanDrives(DriveInfo *drives, int maxDrives) {
    int count = 0;
    int sysDisk = GetSystemDiskNumber();

    // Map drive letters
    DWORD logicalDrives = GetLogicalDrives();
    for (int i = 0; i < 16 && count < maxDrives; i++) {
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
                    snprintf(drives[count].vendor, sizeof(drives[count].vendor), "%s", (char *)(buffer + desc->VendorIdOffset));
                }
                if (desc->ProductIdOffset != 0 && desc->ProductIdOffset < bytesReturned) {
                    snprintf(drives[count].product, sizeof(drives[count].product), "%s", (char *)(buffer + desc->ProductIdOffset));
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
                                    if (GetDriveTypeA(vpath + 4) == DRIVE_REMOVABLE) {
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
                        printf("  -> Locking & dismounting volume %c: ...\n", c);
                        DeviceIoControl(hV, FSCTL_LOCK_VOLUME, NULL, 0, NULL, 0, &r, NULL);
                        DeviceIoControl(hV, FSCTL_DISMOUNT_VOLUME, NULL, 0, NULL, 0, &r, NULL);
                    }
                }
                CloseHandle(hV);
            }
        }
    }
}

BOOL FlashISO(const char *isoPath, int targetDisk) {
    HANDLE hIso = CreateFileA(isoPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (hIso == INVALID_HANDLE_VALUE) {
        printf("\n[ERROR] Could not open ISO file: %s (Error %lu)\n", isoPath, GetLastError());
        return FALSE;
    }

    LARGE_INTEGER isoSize;
    if (!GetFileSizeEx(hIso, &isoSize)) {
        printf("\n[ERROR] Could not determine ISO size.\n");
        CloseHandle(hIso);
        return FALSE;
    }

    char diskPath[64];
    snprintf(diskPath, sizeof(diskPath), "\\\\.\\PhysicalDrive%d", targetDisk);
    DismountDriveVolumes(targetDisk);

    HANDLE hDisk = CreateFileA(diskPath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (hDisk == INVALID_HANDLE_VALUE) {
        printf("\n[ERROR] Could not open %s for raw write (Error %lu).\n", diskPath, GetLastError());
        printf("Make sure to run this program as Administrator!\n");
        CloseHandle(hIso);
        return FALSE;
    }

    BYTE *buffer = (BYTE *)malloc(BUFFER_SIZE);
    if (!buffer) {
        printf("\n[ERROR] Failed to allocate memory buffer.\n");
        CloseHandle(hDisk);
        CloseHandle(hIso);
        return FALSE;
    }

    printf("\nFlashing %s to %s (%.1f MB)...\n", isoPath, diskPath, (double)isoSize.QuadPart / (1024.0 * 1024.0));
    printf("DO NOT UNPLUG THE USB DRIVE!\n\n");

    DWORD bytesRead = 0, bytesWritten = 0;
    LONGLONG totalWritten = 0;
    DWORD startTime = GetTickCount();

    while (ReadFile(hIso, buffer, BUFFER_SIZE, &bytesRead, NULL) && bytesRead > 0) {
        if (!WriteFile(hDisk, buffer, bytesRead, &bytesWritten, NULL) || bytesWritten != bytesRead) {
            printf("\n[ERROR] Write failure at offset %lld (Error %lu)\n", totalWritten, GetLastError());
            free(buffer);
            CloseHandle(hDisk);
            CloseHandle(hIso);
            return FALSE;
        }

        totalWritten += bytesWritten;
        DWORD elapsedMs = GetTickCount() - startTime;
        if (elapsedMs == 0) elapsedMs = 1;
        double speedMBps = ((double)totalWritten / (1024.0 * 1024.0)) / ((double)elapsedMs / 1000.0);
        int percent = (int)((totalWritten * 100) / isoSize.QuadPart);

        printf("\r [");
        int barWidth = 30;
        int pos = (percent * barWidth) / 100;
        for (int b = 0; b < barWidth; b++) {
            if (b < pos) printf("=");
            else if (b == pos) printf(">");
            else printf(" ");
        }
        printf("] %3d%% (%.1f / %.1f MB) @ %.1f MB/s",
               percent,
               (double)totalWritten / (1024.0 * 1024.0),
               (double)isoSize.QuadPart / (1024.0 * 1024.0),
               speedMBps);
        fflush(stdout);
    }

    printf("\n\nFlushing disk buffers...\n");
    FlushFileBuffers(hDisk);

    free(buffer);
    CloseHandle(hDisk);
    CloseHandle(hIso);

    printf("--> Refreshing drive partition table...\n");
    // Trigger drive update
    HANDLE hRefresh = CreateFileA(diskPath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (hRefresh != INVALID_HANDLE_VALUE) {
        DWORD ret = 0;
        DeviceIoControl(hRefresh, IOCTL_DISK_UPDATE_PROPERTIES, NULL, 0, NULL, 0, &ret, NULL);
        CloseHandle(hRefresh);
    }

    return TRUE;
}

void ExecuteBootOSInVM(const char *isoPath) {
    printf("\n==========================================================\n");
    printf("     Executing BootOS in Oracle VirtualBox\n");
    printf("==========================================================\n");
    
    const char *vboxPath = "C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe";
    DWORD attr = GetFileAttributesA(vboxPath);
    if (attr != INVALID_FILE_ATTRIBUTES) {
        printf("Detected Oracle VirtualBox! Launching BootOS...\n");
        STARTUPINFOA si = { sizeof(si) };
        PROCESS_INFORMATION pi = { 0 };
        char cmd[512];
        snprintf(cmd, sizeof(cmd), "\"%s\" startvm vmbootos2.92 --type gui", vboxPath);
        if (CreateProcessA(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            printf("\nBootOS VirtualBox window launched!\n");
            return;
        }
        snprintf(cmd, sizeof(cmd), "\"%s\" startvm vmbootos2 --type gui", vboxPath);
        if (CreateProcessA(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
            printf("\nBootOS VirtualBox window launched!\n");
            return;
        }
    }

    printf("Oracle VirtualBox was not found at %s.\n", vboxPath);
    printf("To boot on your physical PC, use Option [1] to make your USB drive bootable!\n");
}

int main(int argc, char *argv[]) {
    char exePath[MAX_PATH];
    GetModuleFileNameA(NULL, exePath, sizeof(exePath));
    char dir[MAX_PATH];
    strncpy(dir, exePath, sizeof(dir));
    char *lastSlash = strrchr(dir, '\\');
    if (lastSlash) *(lastSlash + 1) = '\0';

    char isoPath[MAX_PATH];
    snprintf(isoPath, sizeof(isoPath), "%sbootos.iso", dir);

    // If not found in current directory, check parent
    if (GetFileAttributesA(isoPath) == INVALID_FILE_ATTRIBUTES) {
        snprintf(isoPath, sizeof(isoPath), "%s..\\bootos.iso", dir);
    }
    if (GetFileAttributesA(isoPath) == INVALID_FILE_ATTRIBUTES) {
        snprintf(isoPath, sizeof(isoPath), "bootos.iso");
    }

    printf("==============================================================\n");
    printf("         BootOS - Executable Flasher & Runner Tool\n");
    printf("==============================================================\n");

    if (GetFileAttributesA(isoPath) != INVALID_FILE_ATTRIBUTES) {
        HANDLE hCheck = CreateFileA(isoPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
        if (hCheck != INVALID_HANDLE_VALUE) {
            LARGE_INTEGER sz;
            GetFileSizeEx(hCheck, &sz);
            CloseHandle(hCheck);
            printf(" ISO Image : %s (%.1f MB)\n", isoPath, (double)sz.QuadPart / (1024.0 * 1024.0));
        }
    } else {
        printf(" [!] Warning: bootos.iso was not found in the current folder.\n");
        printf("     Please place bootos.iso in the same directory as this tool.\n");
    }

    printf(" Privileges: %s\n", IsUserAdmin() ? "Administrator (Full Access)" : "Standard User (Elevation required for flashing)");
    printf("==============================================================\n\n");

    printf("Main Menu:\n");
    printf("  [1] Flash BootOS directly to USB Flash Drive (No Rufus Needed!)\n");
    printf("  [2] Execute BootOS in Oracle VirtualBox\n");
    printf("  [Q] Exit\n\n");

    printf("Select option [1, 2, Q]: ");
    char choice[32];
    if (!fgets(choice, sizeof(choice), stdin)) return 0;

    if (choice[0] == '2') {
        ExecuteBootOSInVM(isoPath);
        printf("\nPress Enter to exit...");
        getchar();
        return 0;
    } else if (choice[0] == 'q' || choice[0] == 'Q') {
        return 0;
    } else if (choice[0] != '1') {
        printf("Invalid choice.\n");
        return 0;
    }

    // Flash mode: ensure administrator privileges
    if (!IsUserAdmin()) {
        printf("\n[!] Administrator privileges are required to write raw sectors to a USB drive.\n");
        printf("Requesting elevation via Windows UAC prompt...\n");
        HINSTANCE res = ShellExecuteA(NULL, "runas", exePath, "1", dir, SW_SHOWNORMAL);
        if ((INT_PTR)res > 32) {
            return 0; // Elevated process spawned
        } else {
            printf("[ERROR] Elevation was denied or cancelled.\n");
            printf("Please right-click bootos-flasher.exe and select 'Run as Administrator'.\n");
            printf("\nPress Enter to exit...");
            getchar();
            return 1;
        }
    }

    // Scan drives
    DriveInfo drives[16];
    int count = ScanDrives(drives, 16);

    printf("\nConnected Storage Devices:\n");
    printf("--------------------------------------------------------------------------------\n");
    printf(" #   Type   Drive   Model Name                         Size       Status\n");
    printf("--------------------------------------------------------------------------------\n");

    int usbCount = 0;
    for (int i = 0; i < count; i++) {
        char letStr[8] = " - ";
        if (drives[i].letter != ' ') snprintf(letStr, sizeof(letStr), "%c:", drives[i].letter);

        char status[32] = "OK";
        if (drives[i].isSystem) {
            snprintf(status, sizeof(status), "[SYSTEM / BLOCKED]");
        } else if (drives[i].isUsb) {
            snprintf(status, sizeof(status), "[USB Target]");
            usbCount++;
        } else {
            snprintf(status, sizeof(status), "[Internal Disk]");
        }

        printf(" [%d] %-6s %-7s %-34.34s %6.1f GB   %s\n",
               drives[i].diskNumber,
               drives[i].busType,
               letStr,
               drives[i].product,
               drives[i].sizeGB,
               status);
    }
    printf("--------------------------------------------------------------------------------\n");

    if (count == 0) {
        printf("No storage devices detected.\n");
        printf("\nPress Enter to exit...");
        getchar();
        return 0;
    }

    printf("\nEnter the Disk Number of your USB Flash Drive (e.g. 1, 2) or 'C' to cancel: ");
    char input[32];
    if (!fgets(input, sizeof(input), stdin)) return 0;
    if (input[0] == 'c' || input[0] == 'C') return 0;

    int selectedDisk = atoi(input);
    int targetIdx = -1;
    for (int i = 0; i < count; i++) {
        if (drives[i].diskNumber == selectedDisk) {
            targetIdx = i;
            break;
        }
    }

    if (targetIdx == -1) {
        printf("[ERROR] Invalid disk number.\n");
        printf("\nPress Enter to exit...");
        getchar();
        return 1;
    }

    if (drives[targetIdx].isSystem || drives[targetIdx].letter == 'C' || drives[targetIdx].letter == 'c' || drives[targetIdx].letter == 'D' || drives[targetIdx].letter == 'd' || !drives[targetIdx].isUsb) {
        printf("\n[DANGER] PhysicalDrive%d is a protected internal drive (C: or D:)!\n", selectedDisk);
        printf("BootOS Flasher strictly refuses to touch internal storage drives.\n");
        printf("\nPress Enter to exit...");
        getchar();
        return 1;
    }

    printf("\n********************************************************************************\n");
    printf(" WARNING: ALL DATA ON PhysicalDrive%d (%s, %.1f GB) WILL BE ERASED!\n",
           selectedDisk, drives[targetIdx].product, drives[targetIdx].sizeGB);
    printf("********************************************************************************\n");
    printf("Type 'YES' (all caps) to confirm and flash BootOS: ");
    char confirm[32];
    if (!fgets(confirm, sizeof(confirm), stdin)) return 0;
    if (strncmp(confirm, "YES", 3) != 0) {
        printf("Operation cancelled. No changes were made.\n");
        printf("\nPress Enter to exit...");
        getchar();
        return 0;
    }

    BOOL success = FlashISO(isoPath, selectedDisk);
    if (success) {
        printf("\n==========================================================\n");
        printf(" [SUCCESS] BootOS has been successfully flashed to USB!\n");
        printf(" Your USB flash drive is now 100%% bootable:\n");
        printf("   - Boots on Legacy BIOS (old PCs & laptops)\n");
        printf("   - Boots on modern UEFI PCs (secure boot off)\n");
        printf("   - Runs 100%% in DRAM - USB can be safely removed after boot!\n");
        printf("==========================================================\n");
    } else {
        printf("\n[ERROR] Flashing failed.\n");
    }

    printf("\nPress Enter to exit...");
    getchar();
    return success ? 0 : 1;
}
