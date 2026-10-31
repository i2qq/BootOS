/**
 * BootOS Windows 11 File Explorer - Client Controller
 * Pure Vanilla JavaScript - No frameworks, pixel-perfect Fluent Design.
 */

class FileExplorer {
    constructor() {
        this.tabs = [];
        this.activeTabId = null;
        this.clipboard = { action: null, paths: [] }; // action: 'cut' | 'copy'
        this.selectedPaths = new Set();
        this.drives = [];
        this.currentItems = [];
        this.sortField = 'name';
        this.sortOrder = 'asc';
        this.viewMode = 'details';
        this.showHidden = false;
        this.searchQuery = '';
        this.contextTarget = null; // target item or null (empty area)

        this.initDOM();
        this.initEvents();
        this.loadDrives().then(() => {
            // Start with initial tab at root or home
            const initialPath = window.location.protocol === 'file:' ? 'C:/' : '/root';
            this.createTab('This PC', initialPath);
        });
    }

    initDOM() {
        this.tabsContainer = document.getElementById('tabs-container');
        this.btnNewTab = document.getElementById('btn-new-tab');
        this.btnBack = document.getElementById('btn-back');
        this.btnForward = document.getElementById('btn-forward');
        this.btnUp = document.getElementById('btn-up');
        this.btnRefresh = document.getElementById('btn-refresh');

        this.addressBar = document.getElementById('address-bar-container');
        this.breadcrumbsList = document.getElementById('breadcrumbs-list');
        this.addressInput = document.getElementById('address-input');
        this.btnCopyPath = document.getElementById('btn-copy-path');

        this.searchInput = document.getElementById('search-input');
        this.btnClearSearch = document.getElementById('btn-clear-search');

        // Command Bar Buttons
        this.btnNew = document.getElementById('btn-new');
        this.menuNew = document.getElementById('menu-new');
        this.btnCut = document.getElementById('btn-cut');
        this.btnCopy = document.getElementById('btn-copy');
        this.btnPaste = document.getElementById('btn-paste');
        this.btnRename = document.getElementById('btn-rename');
        this.btnDelete = document.getElementById('btn-delete');
        this.btnSort = document.getElementById('btn-sort');
        this.menuSort = document.getElementById('menu-sort');
        this.btnView = document.getElementById('btn-view');
        this.menuView = document.getElementById('menu-view');
        this.btnTerminal = document.getElementById('btn-terminal');

        // Views
        this.sidebarDrives = document.getElementById('sidebar-drives');
        this.contentPane = document.getElementById('content-pane');
        this.itemsView = document.getElementById('items-view');
        this.detailsHeader = document.getElementById('details-header');
        this.selectionBox = document.getElementById('selection-box');

        // Status Bar
        this.statusCount = document.getElementById('status-count');
        this.statusSelected = document.getElementById('status-selected');
        this.statusSize = document.getElementById('status-size');
        this.statusFree = document.getElementById('status-free');
        this.toggleDetailsBtn = document.getElementById('toggle-details-btn');
        this.toggleIconsBtn = document.getElementById('toggle-icons-btn');

        // Context Menu
        this.contextMenu = document.getElementById('context-menu');
        this.ctxCut = document.getElementById('ctx-cut');
        this.ctxCopy = document.getElementById('ctx-copy');
        this.ctxRename = document.getElementById('ctx-rename');
        this.ctxDelete = document.getElementById('ctx-delete');
        this.ctxOpen = document.getElementById('ctx-open');
        this.ctxTerminal = document.getElementById('ctx-terminal');
        this.ctxNewFolder = document.getElementById('ctx-new-folder');
        this.ctxNewFile = document.getElementById('ctx-new-file');
        this.ctxSelectAll = document.getElementById('ctx-select-all');
        this.ctxProperties = document.getElementById('ctx-properties');

        // Modals
        this.modalProperties = document.getElementById('modal-properties');
        this.modalEditor = document.getElementById('modal-editor');
    }

    initEvents() {
        // Tab controls
        this.btnNewTab.addEventListener('click', () => this.createTab('New Tab', this.getActiveTab().path));

        // Nav buttons
        this.btnBack.addEventListener('click', () => this.navigateBack());
        this.btnForward.addEventListener('click', () => this.navigateForward());
        this.btnUp.addEventListener('click', () => this.navigateUp());
        this.btnRefresh.addEventListener('click', () => this.refresh());

        // Address bar breadcrumbs vs text input
        this.addressBar.addEventListener('click', (e) => {
            if (e.target.closest('#btn-copy-path') || e.target.closest('.breadcrumb-crumb')) return;
            this.showAddressInput();
        });

        this.addressInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                this.hideAddressInput();
                this.navigateTo(this.addressInput.value.trim());
            } else if (e.key === 'Escape') {
                this.hideAddressInput();
            }
        });

        this.addressInput.addEventListener('blur', () => this.hideAddressInput());

        this.btnCopyPath.addEventListener('click', (e) => {
            e.stopPropagation();
            const p = this.getActiveTab().path;
            navigator.clipboard.writeText(p).catch(() => {});
        });

        // Search
        this.searchInput.addEventListener('input', () => {
            this.searchQuery = this.searchInput.value.trim().toLowerCase();
            this.btnClearSearch.classList.toggle('hidden', !this.searchQuery);
            this.renderItems();
        });

        this.btnClearSearch.addEventListener('click', () => {
            this.searchInput.value = '';
            this.searchQuery = '';
            this.btnClearSearch.classList.add('hidden');
            this.renderItems();
        });

        // Command Bar Dropdowns
        this.btnNew.addEventListener('click', (e) => {
            e.stopPropagation();
            this.closeAllMenus();
            this.menuNew.classList.toggle('hidden');
        });

        this.btnSort.addEventListener('click', (e) => {
            e.stopPropagation();
            this.closeAllMenus();
            this.menuSort.classList.toggle('hidden');
        });

        this.btnView.addEventListener('click', (e) => {
            e.stopPropagation();
            this.closeAllMenus();
            this.menuView.classList.toggle('hidden');
        });

        document.addEventListener('click', () => this.closeAllMenus());

        // New Menu Items
        this.menuNew.addEventListener('click', (e) => {
            const item = e.target.closest('.menu-item');
            if (!item) return;
            const action = item.dataset.action;
            if (action === 'new-folder') this.createFolder();
            else if (action === 'new-text') this.createFile('New Text Document.txt');
            else if (action === 'new-script') this.createFile('New Script.sh', '#!/bin/bash\n\n');
        });

        // Sort Menu Items
        this.menuSort.addEventListener('click', (e) => {
            const item = e.target.closest('.menu-item');
            if (!item) return;
            if (item.dataset.sort) {
                this.sortField = item.dataset.sort;
                this.menuSort.querySelectorAll('[data-sort]').forEach(el => el.classList.remove('active'));
                item.classList.add('active');
            } else if (item.dataset.order) {
                this.sortOrder = item.dataset.order;
                this.menuSort.querySelectorAll('[data-order]').forEach(el => el.classList.remove('active'));
                item.classList.add('active');
            }
            this.renderItems();
        });

        // View Menu Items
        this.menuView.addEventListener('click', (e) => {
            const item = e.target.closest('.menu-item');
            if (!item) return;
            if (item.id === 'toggle-hidden') {
                this.showHidden = !this.showHidden;
                item.classList.toggle('active', this.showHidden);
                this.refresh();
                return;
            }
            if (item.dataset.view) {
                this.setViewMode(item.dataset.view);
                this.menuView.querySelectorAll('[data-view]').forEach(el => el.classList.remove('active'));
                item.classList.add('active');
            }
        });

        // Cut / Copy / Paste / Rename / Delete buttons
        this.btnCut.addEventListener('click', () => this.cutSelected());
        this.btnCopy.addEventListener('click', () => this.copySelected());
        this.btnPaste.addEventListener('click', () => this.pasteClipboard());
        this.btnRename.addEventListener('click', () => this.renameSelected());
        this.btnDelete.addEventListener('click', () => this.deleteSelected());
        this.btnTerminal.addEventListener('click', () => this.launchTerminal(this.getActiveTab().path));

        // Details column sort clicks
        this.detailsHeader.addEventListener('click', (e) => {
            const col = e.target.closest('.col');
            if (!col) return;
            const field = col.dataset.col;
            if (this.sortField === field) {
                this.sortOrder = (this.sortOrder === 'asc' ? 'desc' : 'asc');
            } else {
                this.sortField = field;
                this.sortOrder = 'asc';
            }
            this.updateHeaderSortIndicators();
            this.renderItems();
        });

        // Sidebar click navigation
        document.getElementById('sidebar').addEventListener('click', (e) => {
            const item = e.target.closest('.sidebar-item') || e.target.closest('.sidebar-drive-item');
            if (!item) return;
            const p = item.dataset.path;
            if (p) this.navigateTo(p);
        });

        // View toggle buttons on status bar
        this.toggleDetailsBtn.addEventListener('click', () => this.setViewMode('details'));
        this.toggleIconsBtn.addEventListener('click', () => this.setViewMode('large'));

        // Keyboard Shortcuts
        document.addEventListener('keydown', (e) => this.handleKeyboard(e));

        // Context Menu Handler
        this.contentPane.addEventListener('contextmenu', (e) => this.handleContextMenu(e));
        document.addEventListener('click', () => this.hideContextMenu());

        // Context menu items
        this.ctxCut.addEventListener('click', () => this.cutSelected());
        this.ctxCopy.addEventListener('click', () => this.copySelected());
        this.ctxRename.addEventListener('click', () => this.renameSelected());
        this.ctxDelete.addEventListener('click', () => this.deleteSelected());
        this.ctxOpen.addEventListener('click', () => this.openTarget(this.contextTarget));
        this.ctxTerminal.addEventListener('click', () => this.launchTerminal(this.contextTarget ? this.contextTarget.path : this.getActiveTab().path));
        this.ctxNewFolder.addEventListener('click', () => this.createFolder());
        this.ctxNewFile.addEventListener('click', () => this.createFile('New Text Document.txt'));
        this.ctxSelectAll.addEventListener('click', () => this.selectAll());
        this.ctxProperties.addEventListener('click', () => this.showProperties(this.contextTarget || { path: this.getActiveTab().path, is_dir: true, name: this.getActiveTab().title }));

        // Modal Close buttons
        document.getElementById('btn-close-prop').addEventListener('click', () => this.modalProperties.classList.add('hidden'));
        document.getElementById('btn-prop-ok').addEventListener('click', () => this.modalProperties.classList.add('hidden'));
        document.getElementById('btn-prop-cancel').addEventListener('click', () => this.modalProperties.classList.add('hidden'));
        document.getElementById('btn-close-editor').addEventListener('click', () => this.modalEditor.classList.add('hidden'));
        document.getElementById('btn-editor-cancel').addEventListener('click', () => this.modalEditor.classList.add('hidden'));
        document.getElementById('btn-editor-save').addEventListener('click', () => this.saveEditorContent());

        // Sidebar resizer drag
        this.initSidebarResizer();
    }

    initSidebarResizer() {
        const resizer = document.getElementById('sidebar-resizer');
        const sidebar = document.getElementById('sidebar');
        let isResizing = false;

        resizer.addEventListener('mousedown', (e) => {
            isResizing = true;
            document.body.style.cursor = 'col-resize';
        });

        document.addEventListener('mousemove', (e) => {
            if (!isResizing) return;
            const newWidth = Math.max(160, Math.min(400, e.clientX));
            sidebar.style.width = `${newWidth}px`;
        });

        document.addEventListener('mouseup', () => {
            if (isResizing) {
                isResizing = false;
                document.body.style.cursor = 'default';
            }
        });
    }

    closeAllMenus() {
        this.menuNew.classList.add('hidden');
        this.menuSort.classList.add('hidden');
        this.menuView.classList.add('hidden');
    }

    // =========================================================================
    // Tabs System
    // =========================================================================
    createTab(title, path) {
        const id = 'tab_' + Date.now() + '_' + Math.random().toString(36).substr(2, 4);
        const tab = {
            id,
            title: title || 'Home',
            path: path || '/root',
            history: [path || '/root'],
            historyIndex: 0,
            icon: '📁'
        };
        this.tabs.push(tab);
        this.renderTabs();
        this.switchTab(id);
    }

    switchTab(tabId) {
        this.activeTabId = tabId;
        this.renderTabs();
        const tab = this.getActiveTab();
        if (tab) {
            this.navigateTo(tab.path, false);
        }
    }

    closeTab(tabId, e) {
        if (e) e.stopPropagation();
        if (this.tabs.length <= 1) {
            // Always keep at least 1 tab open
            return;
        }
        const idx = this.tabs.findIndex(t => t.id === tabId);
        if (idx !== -1) {
            this.tabs.splice(idx, 1);
            if (this.activeTabId === tabId) {
                const nextTab = this.tabs[Math.max(0, idx - 1)];
                this.switchTab(nextTab.id);
            } else {
                this.renderTabs();
            }
        }
    }

    getActiveTab() {
        return this.tabs.find(t => t.id === this.activeTabId) || this.tabs[0];
    }

    renderTabs() {
        this.tabsContainer.innerHTML = '';
        this.tabs.forEach(tab => {
            const el = document.createElement('div');
            el.className = 'tab' + (tab.id === this.activeTabId ? ' active' : '');
            el.innerHTML = `
                <span class="tab-icon">${tab.icon}</span>
                <span class="tab-title" title="${tab.path}">${tab.title}</span>
                <span class="tab-close" title="Close tab (Ctrl+W)">✕</span>
            `;
            el.addEventListener('click', () => this.switchTab(tab.id));
            el.querySelector('.tab-close').addEventListener('click', (e) => this.closeTab(tab.id, e));
            this.tabsContainer.appendChild(el);
        });
    }

    // =========================================================================
    // Drives & Sidebar
    // =========================================================================
    async loadDrives() {
        try {
            const res = await fetch('/api/drives');
            const data = await res.json();
            this.drives = data.drives || [];
            this.renderDrives();
        } catch (e) {
            console.error('Failed to load drives:', e);
        }
    }

    renderDrives() {
        this.sidebarDrives.innerHTML = '';
        this.drives.forEach(drive => {
            const item = document.createElement('div');
            item.className = 'sidebar-drive-item';
            item.dataset.path = drive.path;
            item.innerHTML = `
                <div class="drive-header">
                    <span class="sb-icon">${drive.type === 'removable' ? '🔌' : drive.type === 'ram' ? '⚡' : '💾'}</span>
                    <span class="sb-label">${drive.name}</span>
                </div>
                <div class="drive-bar-track">
                    <div class="drive-bar-fill" style="width: ${drive.percent_used}%"></div>
                </div>
                <div class="drive-info-sub">${drive.free_fmt} free of ${drive.total_fmt}</div>
            `;
            this.sidebarDrives.appendChild(item);
        });
    }

    // =========================================================================
    // Navigation & Breadcrumbs
    // =========================================================================
    async navigateTo(targetPath, recordHistory = true) {
        if (!targetPath) return;
        this.selectedPaths.clear();
        this.updateCommandBarState();

        try {
            const url = `/api/list?path=${encodeURIComponent(targetPath)}&show_hidden=${this.showHidden}`;
            const res = await fetch(url);
            if (!res.ok) {
                const err = await res.json();
                alert(err.error || 'Failed to open directory');
                return;
            }
            const data = await res.json();
            this.currentItems = data.items || [];

            // Update Tab
            const tab = this.getActiveTab();
            tab.path = data.current_path;
            const dirName = data.current_path.split(/[\\/]/).filter(Boolean).pop() || 'This PC';
            tab.title = dirName;
            tab.icon = data.current_path === '/' ? '💻' : '📁';

            if (recordHistory) {
                // Truncate forward history if we navigated elsewhere
                if (tab.historyIndex < tab.history.length - 1) {
                    tab.history = tab.history.slice(0, tab.historyIndex + 1);
                }
                tab.history.push(data.current_path);
                tab.historyIndex = tab.history.length - 1;
            }

            this.updateNavButtons();
            this.renderTabs();
            this.renderBreadcrumbs(data.current_path);
            this.renderItems();
            this.updateStatusBar(data);
            this.updateActiveSidebar(data.current_path);
        } catch (e) {
            console.error('Navigation error:', e);
        }
    }

    navigateBack() {
        const tab = this.getActiveTab();
        if (tab && tab.historyIndex > 0) {
            tab.historyIndex--;
            this.navigateTo(tab.history[tab.historyIndex], false);
        }
    }

    navigateForward() {
        const tab = this.getActiveTab();
        if (tab && tab.historyIndex < tab.history.length - 1) {
            tab.historyIndex++;
            this.navigateTo(tab.history[tab.historyIndex], false);
        }
    }

    navigateUp() {
        const tab = this.getActiveTab();
        if (!tab || !tab.path) return;
        const parts = tab.path.split(/[\\/]/).filter(Boolean);
        if (parts.length > 0) {
            parts.pop();
            const parent = tab.path.startsWith('/') ? '/' + parts.join('/') : parts.join('/') || 'C:/';
            this.navigateTo(parent);
        }
    }

    refresh() {
        const tab = this.getActiveTab();
        if (tab) this.navigateTo(tab.path, false);
    }

    updateNavButtons() {
        const tab = this.getActiveTab();
        this.btnBack.disabled = !tab || tab.historyIndex <= 0;
        this.btnForward.disabled = !tab || tab.historyIndex >= tab.history.length - 1;
    }

    renderBreadcrumbs(fullPath) {
        this.breadcrumbsList.innerHTML = '';
        const segments = fullPath.split(/[\\/]/).filter(Boolean);

        // Root segment
        const rootCrumb = document.createElement('div');
        rootCrumb.className = 'breadcrumb-crumb';
        rootCrumb.textContent = fullPath.startsWith('/') ? 'This PC' : segments[0] || 'This PC';
        rootCrumb.addEventListener('click', () => this.navigateTo(fullPath.startsWith('/') ? '/' : segments[0] + '/'));
        this.breadcrumbsList.appendChild(rootCrumb);

        let accumulated = fullPath.startsWith('/') ? '' : (segments[0] || '');
        const loopStart = fullPath.startsWith('/') ? 0 : 1;

        for (let i = loopStart; i < segments.length; i++) {
            const sep = document.createElement('span');
            sep.className = 'breadcrumb-sep';
            sep.textContent = '>';
            this.breadcrumbsList.appendChild(sep);

            accumulated += (accumulated.endsWith('/') ? '' : '/') + segments[i];
            const p = accumulated;

            const crumb = document.createElement('div');
            crumb.className = 'breadcrumb-crumb';
            crumb.textContent = segments[i];
            crumb.addEventListener('click', () => this.navigateTo(p));
            this.breadcrumbsList.appendChild(crumb);
        }
    }

    showAddressInput() {
        const tab = this.getActiveTab();
        this.addressInput.value = tab ? tab.path : '';
        this.breadcrumbsList.classList.add('hidden');
        this.addressInput.classList.remove('hidden');
        this.addressInput.focus();
        this.addressInput.select();
    }

    hideAddressInput() {
        this.addressInput.classList.add('hidden');
        this.breadcrumbsList.classList.remove('hidden');
    }

    updateActiveSidebar(currentPath) {
        document.querySelectorAll('.sidebar-item, .sidebar-drive-item').forEach(el => {
            el.classList.toggle('active', el.dataset.path === currentPath);
        });
    }

    // =========================================================================
    // Items Rendering & Selection
    // =========================================================================
    renderItems() {
        this.itemsView.innerHTML = '';
        let list = [...this.currentItems];

        // Apply Search
        if (this.searchQuery) {
            list = list.filter(item => item.name.toLowerCase().includes(this.searchQuery));
        }

        // Apply Sort
        list.sort((a, b) => {
            if (a.is_dir !== b.is_dir) {
                return a.is_dir ? -1 : 1; // Directories first
            }
            let valA = a[this.sortField];
            let valB = b[this.sortField];

            if (this.sortField === 'name') {
                valA = a.name.toLowerCase();
                valB = b.name.toLowerCase();
            } else if (this.sortField === 'date') {
                valA = a.mtime;
                valB = b.mtime;
            } else if (this.sortField === 'size') {
                valA = a.size || 0;
                valB = b.size || 0;
            }

            if (valA < valB) return this.sortOrder === 'asc' ? -1 : 1;
            if (valA > valB) return this.sortOrder === 'asc' ? 1 : -1;
            return 0;
        });

        list.forEach(item => {
            const row = document.createElement('div');
            row.className = 'item-row' + (this.selectedPaths.has(item.path) ? ' selected' : '');
            row.dataset.path = item.path;

            const iconMap = {
                'folder': '📁',
                'file-text': '📄',
                'file-code': '📜',
                'file-image': '🖼️',
                'file-archive': '📦',
                'file-iso': '💿',
                'file-audio': '🎵',
                'file-video': '🎬',
                'file-pdf': '📕',
                'file-exe': '⚙️',
                'file-settings': '🔧',
                'file': '📄'
            };
            const iconChar = iconMap[item.icon] || '📄';

            row.innerHTML = `
                <div class="col col-name">
                    <span class="item-icon">${iconChar}</span>
                    <span class="item-name-text" title="${item.name}">${item.name}</span>
                </div>
                <div class="col col-date">${item.date_fmt}</div>
                <div class="col col-type">${item.type}</div>
                <div class="col col-size">${item.size_fmt}</div>
            `;

            // Selection & Open Handlers
            row.addEventListener('click', (e) => this.handleItemClick(item, e));
            row.addEventListener('dblclick', () => this.openTarget(item));
            row.addEventListener('contextmenu', (e) => {
                e.stopPropagation();
                e.preventDefault();
                if (!this.selectedPaths.has(item.path)) {
                    this.selectedPaths.clear();
                    this.selectedPaths.add(item.path);
                    this.updateItemSelectionVisuals();
                }
                this.showContextMenu(e.clientX, e.clientY, item);
            });

            this.itemsView.appendChild(row);
        });

        this.updateSelectionStats();
    }

    handleItemClick(item, e) {
        if (e.ctrlKey || e.metaKey) {
            if (this.selectedPaths.has(item.path)) {
                this.selectedPaths.delete(item.path);
            } else {
                this.selectedPaths.add(item.path);
            }
        } else if (e.shiftKey) {
            // Range select
            const allRows = Array.from(this.itemsView.querySelectorAll('.item-row'));
            const clickedIdx = allRows.findIndex(r => r.dataset.path === item.path);
            const firstSelected = allRows.findIndex(r => this.selectedPaths.has(r.dataset.path));
            if (firstSelected !== -1 && clickedIdx !== -1) {
                const start = Math.min(firstSelected, clickedIdx);
                const end = Math.max(firstSelected, clickedIdx);
                for (let i = start; i <= end; i++) {
                    this.selectedPaths.add(allRows[i].dataset.path);
                }
            } else {
                this.selectedPaths.add(item.path);
            }
        } else {
            this.selectedPaths.clear();
            this.selectedPaths.add(item.path);
        }

        this.updateItemSelectionVisuals();
        this.updateCommandBarState();
        this.updateSelectionStats();
    }

    updateItemSelectionVisuals() {
        this.itemsView.querySelectorAll('.item-row').forEach(row => {
            row.classList.toggle('selected', this.selectedPaths.has(row.dataset.path));
        });
    }

    selectAll() {
        this.currentItems.forEach(i => this.selectedPaths.add(i.path));
        this.updateItemSelectionVisuals();
        this.updateCommandBarState();
        this.updateSelectionStats();
    }

    clearSelection() {
        this.selectedPaths.clear();
        this.updateItemSelectionVisuals();
        this.updateCommandBarState();
        this.updateSelectionStats();
    }

    updateCommandBarState() {
        const count = this.selectedPaths.size;
        const hasSelection = count > 0;
        this.btnCut.disabled = !hasSelection;
        this.btnCopy.disabled = !hasSelection;
        this.btnRename.disabled = (count !== 1);
        this.btnDelete.disabled = !hasSelection;
        this.btnPaste.disabled = !this.clipboard.paths.length;
    }

    updateSelectionStats() {
        const count = this.selectedPaths.size;
        if (count === 0) {
            this.statusSelected.classList.add('hidden');
            this.statusSize.classList.add('hidden');
        } else {
            this.statusSelected.textContent = `${count} item${count > 1 ? 's' : ''} selected`;
            this.statusSelected.classList.remove('hidden');

            let totalBytes = 0;
            this.currentItems.forEach(i => {
                if (this.selectedPaths.has(i.path) && i.size) totalBytes += i.size;
            });
            if (totalBytes > 0) {
                this.statusSize.textContent = this.formatSize(totalBytes);
                this.statusSize.classList.remove('hidden');
            } else {
                this.statusSize.classList.add('hidden');
            }
        }
    }

    updateStatusBar(data) {
        this.statusCount.textContent = `${data.item_count || 0} items`;
        this.statusFree.textContent = data.free_space_fmt ? `${data.free_space_fmt} free` : '';
    }

    formatSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }

    setViewMode(mode) {
        this.viewMode = mode;
        this.itemsView.className = `view-${mode}`;
        this.detailsHeader.classList.toggle('hidden', mode !== 'details');
        this.toggleDetailsBtn.classList.toggle('active', mode === 'details');
        this.toggleIconsBtn.classList.toggle('active', mode === 'large');
    }

    updateHeaderSortIndicators() {
        this.detailsHeader.querySelectorAll('.col').forEach(c => {
            const ind = c.querySelector('.sort-indicator');
            if (c.dataset.col === this.sortField) {
                ind.textContent = this.sortOrder === 'asc' ? '▲' : '▼';
            } else {
                ind.textContent = '';
            }
        });
    }

    // =========================================================================
    // File Actions (Cut, Copy, Paste, Delete, Rename, Launch)
    // =========================================================================
    openTarget(item) {
        if (!item) return;
        if (item.is_dir) {
            this.navigateTo(item.path);
        } else {
            const ext = item.name.split('.').pop().toLowerCase();
            if (['txt', 'md', 'sh', 'bash', 'py', 'c', 'h', 'json', 'xml', 'yaml', 'yml', 'conf', 'cfg', 'log'].includes(ext)) {
                this.openTextEditor(item.path);
            } else if (['sh', 'bash', 'py'].includes(ext)) {
                if (confirm(`Run "${item.name}" in terminal?`)) {
                    this.launchFile(item.path);
                }
            } else {
                this.launchFile(item.path);
            }
        }
    }

    cutSelected() {
        if (!this.selectedPaths.size) return;
        this.clipboard = { action: 'cut', paths: Array.from(this.selectedPaths) };
        this.updateCommandBarState();
    }

    copySelected() {
        if (!this.selectedPaths.size) return;
        this.clipboard = { action: 'copy', paths: Array.from(this.selectedPaths) };
        this.updateCommandBarState();
    }

    async pasteClipboard() {
        if (!this.clipboard.paths.length) return;
        const dest = this.getActiveTab().path;
        const endpoint = (this.clipboard.action === 'cut' ? '/api/move' : '/api/copy');

        try {
            const res = await fetch(endpoint, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ sources: this.clipboard.paths, destination: dest })
            });
            const data = await res.json();
            if (data.success) {
                if (this.clipboard.action === 'cut') {
                    this.clipboard = { action: null, paths: [] };
                }
                this.refresh();
            } else {
                alert('Paste failed: ' + (data.errors ? data.errors.join(', ') : 'Unknown error'));
            }
        } catch (e) {
            alert('Paste error: ' + e);
        }
    }

    async deleteSelected() {
        const paths = Array.from(this.selectedPaths);
        if (!paths.length) return;
        const msg = paths.length === 1
            ? `Are you sure you want to permanently delete "${paths[0].split(/[\\/]/).pop()}"?`
            : `Are you sure you want to permanently delete these ${paths.length} items?`;

        if (!confirm(msg)) return;

        try {
            const res = await fetch('/api/delete', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ paths })
            });
            const data = await res.json();
            if (data.success) {
                this.selectedPaths.clear();
                this.refresh();
            } else {
                alert('Delete failed: ' + (data.errors ? data.errors.join(', ') : ''));
            }
        } catch (e) {
            alert('Delete error: ' + e);
        }
    }

    async renameSelected() {
        if (this.selectedPaths.size !== 1) return;
        const oldPath = Array.from(this.selectedPaths)[0];
        const oldName = oldPath.split(/[\\/]/).pop();
        const newName = prompt('Enter new name:', oldName);
        if (!newName || newName === oldName) return;

        try {
            const res = await fetch('/api/rename', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ old_path: oldPath, new_name: newName })
            });
            const data = await res.json();
            if (data.success) {
                this.refresh();
            } else {
                alert('Rename failed: ' + data.error);
            }
        } catch (e) {
            alert('Rename error: ' + e);
        }
    }

    async createFolder() {
        const p = this.getActiveTab().path;
        try {
            const res = await fetch('/api/mkdir', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ path: p, name: 'New folder' })
            });
            const data = await res.json();
            if (data.success) {
                await this.refresh();
                this.selectedPaths.clear();
                this.selectedPaths.add(data.created);
                this.updateItemSelectionVisuals();
            } else {
                alert('Failed to create folder: ' + data.error);
            }
        } catch (e) {
            alert('Error: ' + e);
        }
    }

    async createFile(name = 'New Text Document.txt', content = '') {
        const p = this.getActiveTab().path;
        try {
            const res = await fetch('/api/create_file', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ path: p, name, content })
            });
            const data = await res.json();
            if (data.success) {
                await this.refresh();
                this.selectedPaths.clear();
                this.selectedPaths.add(data.created);
                this.updateItemSelectionVisuals();
            } else {
                alert('Failed to create file: ' + data.error);
            }
        } catch (e) {
            alert('Error: ' + e);
        }
    }

    async launchTerminal(targetPath) {
        try {
            await fetch('/api/launch', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ path: targetPath, action: 'terminal' })
            });
        } catch (e) {
            console.error(e);
        }
    }

    async launchFile(targetPath) {
        try {
            await fetch('/api/launch', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ path: targetPath, action: 'open' })
            });
        } catch (e) {
            console.error(e);
        }
    }

    // =========================================================================
    // Notepad / Text Editor Modal
    // =========================================================================
    async openTextEditor(filePath) {
        try {
            const res = await fetch(`/api/read_file?path=${encodeURIComponent(filePath)}`);
            const data = await res.json();
            if (data.content !== undefined) {
                this.editingFilePath = filePath;
                document.getElementById('editor-title').textContent = `${data.name} - Notepad`;
                document.getElementById('editor-textarea').value = data.content;
                this.modalEditor.classList.remove('hidden');
                document.getElementById('editor-textarea').focus();
            } else {
                alert('Could not read file: ' + data.error);
            }
        } catch (e) {
            alert('Error: ' + e);
        }
    }

    async saveEditorContent() {
        if (!this.editingFilePath) return;
        const content = document.getElementById('editor-textarea').value;
        const dir = this.editingFilePath.split(/[\\/]/).slice(0, -1).join('/') || '/';
        const name = this.editingFilePath.split(/[\\/]/).pop();

        try {
            const res = await fetch('/api/create_file', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ path: dir, name, content })
            });
            const data = await res.json();
            if (data.success) {
                this.modalEditor.classList.add('hidden');
                this.refresh();
            } else {
                alert('Failed to save: ' + data.error);
            }
        } catch (e) {
            alert('Save error: ' + e);
        }
    }

    // =========================================================================
    // Context Menu
    // =========================================================================
    handleContextMenu(e) {
        e.preventDefault();
        this.contextTarget = null;
        this.showContextMenu(e.clientX, e.clientY, null);
    }

    showContextMenu(x, y, targetItem) {
        this.contextTarget = targetItem;
        const isItem = !!targetItem;

        this.ctxCut.disabled = !isItem;
        this.ctxCopy.disabled = !isItem;
        this.ctxRename.disabled = !isItem;
        this.ctxDelete.disabled = !isItem;
        this.ctxOpen.classList.toggle('hidden', !isItem);

        // Position menu within viewport
        this.contextMenu.classList.remove('hidden');
        const w = this.contextMenu.offsetWidth || 200;
        const h = this.contextMenu.offsetHeight || 220;

        const posX = Math.min(x, window.innerWidth - w - 10);
        const posY = Math.min(y, window.innerHeight - h - 10);

        this.contextMenu.style.left = `${posX}px`;
        this.contextMenu.style.top = `${posY}px`;
    }

    hideContextMenu() {
        this.contextMenu.classList.add('hidden');
    }

    // =========================================================================
    // Properties Modal
    // =========================================================================
    showProperties(item) {
        if (!item) return;
        document.getElementById('prop-title').textContent = `${item.name} Properties`;
        document.getElementById('prop-icon').textContent = item.is_dir ? '📁' : '📄';
        document.getElementById('prop-name-input').value = item.name;
        document.getElementById('prop-type').textContent = item.type || (item.is_dir ? 'File folder' : 'File');
        document.getElementById('prop-location').textContent = item.path;
        document.getElementById('prop-size').textContent = item.size_fmt || (item.is_dir ? '-' : '0 B');
        document.getElementById('prop-modified').textContent = item.date_fmt || '-';
        document.getElementById('prop-permissions').textContent = item.permissions || '0755';
        this.modalProperties.classList.remove('hidden');
    }

    // =========================================================================
    // Keyboard Navigation
    // =========================================================================
    handleKeyboard(e) {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;

        if (e.ctrlKey || e.metaKey) {
            if (e.key === 't' || e.key === 'T') {
                e.preventDefault();
                this.createTab('New Tab', this.getActiveTab().path);
            } else if (e.key === 'w' || e.key === 'W') {
                e.preventDefault();
                this.closeTab(this.activeTabId);
            } else if (e.key === 'a' || e.key === 'A') {
                e.preventDefault();
                this.selectAll();
            } else if (e.key === 'c' || e.key === 'C') {
                e.preventDefault();
                this.copySelected();
            } else if (e.key === 'x' || e.key === 'X') {
                e.preventDefault();
                this.cutSelected();
            } else if (e.key === 'v' || e.key === 'V') {
                e.preventDefault();
                this.pasteClipboard();
            } else if (e.key === 'r' || e.key === 'R') {
                e.preventDefault();
                this.refresh();
            }
        } else if (e.key === 'F5') {
            e.preventDefault();
            this.refresh();
        } else if (e.key === 'F2') {
            e.preventDefault();
            this.renameSelected();
        } else if (e.key === 'Delete') {
            e.preventDefault();
            this.deleteSelected();
        } else if (e.key === 'Backspace') {
            e.preventDefault();
            this.navigateUp();
        } else if (e.key === 'Enter') {
            if (this.selectedPaths.size === 1) {
                const p = Array.from(this.selectedPaths)[0];
                const item = this.currentItems.find(i => i.path === p);
                if (item) this.openTarget(item);
            }
        }
    }
}

// Instantiate on load
window.addEventListener('DOMContentLoaded', () => {
    window.explorer = new FileExplorer();
});
