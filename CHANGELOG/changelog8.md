# Changelog 8: Fix 404 Lubuntu/Ubuntu URLs, Guard ISO Extraction Against HTML Errors & Prioritize Direct Flashing

### Summary of Changes
1. **Protected ISO Extraction Against Truncated / 404 HTML Error Pages**:
   - In `extract_iso_assets`, added an explicit file size check requiring ISOs to be >= 10 MB.
   - Prevents the kernel loop device driver from attempting to mount tiny (e.g. 281-byte) 404 HTML error pages, eliminating `mount: attempt to access beyond end of device` and `isofs: fill_super: bread failed` errors.

2. **Updated Lubuntu & Ubuntu Release URLs with `--fail`**:
   - Replaced obsolete point-release URLs with current LTS targets (`lubuntu-24.04.5-desktop-amd64.iso` and `ubuntu-24.04.5.1-desktop-amd64.iso`).
   - Added `curl -f` (`--fail`) to ensure curl aborts immediately on HTTP 4xx/5xx responses rather than writing the HTML error page to disk.

3. **Prioritized Direct Hard Drive / SSD Flashing as Option [1]**:
   - Made direct flashing the primary recommendation across Lubuntu and Ubuntu submenus (`[1] Flash Live ISO directly to Hard Drive / SSD`).
   - Enables installing full desktop operating systems on older PCs without needing 4 GB - 8 GB of RAM or running into kernel signature enforcement restrictions.
   - Added RAM capacity warnings for RAM-boot modes if available free memory is insufficient.

4. **Updated Netboot Image Sources**:
   - Updated Ubuntu Netboot endpoints to live Ubuntu Server cloud minimal assets (`ubuntu-24.04-server-cloudimg-amd64-vmlinuz-generic` and `ubuntu-24.04-server-cloudimg-amd64-initrd-generic`).

5. **Verified Live via VDE-VLM**:
   - Tested menu navigation and OCR element detection on `vmbootos1.5`.
