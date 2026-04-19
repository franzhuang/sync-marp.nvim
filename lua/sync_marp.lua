local M = {}

-- Use Neovim's standard cache directory for temporary files
local CACHE_DIR = vim.fn.stdpath("cache")
local SERVER_PATH = CACHE_DIR .. "/marp-sync-server.js"
local PORT = 3777

local server_job_id = nil

local function create_server_file(base_dir, target_html)
    local server_code = [[
const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const BASE_DIR = ]] .. string.format("%q", base_dir) .. [[;
const TARGET_HTML = ]] .. string.format("%q", target_html) .. [[;
const PORT = ]] .. PORT .. [[;

const MIME_TYPES = {
    '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript',
    '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
    '.gif': 'image/gif', '.svg': 'image/svg+xml'
};

let sseClients = [];

const INJECTED_SCRIPT = `
<script>
    const evtSource = new EventSource("/events");
    evtSource.onmessage = (e) => {
        if (e.data === 'reload') {
            const hash = window.location.hash;
            window.location.href = window.location.pathname + '?t=' + Date.now() + hash;
        } else {
            window.location.hash = e.data;
        }
    };
</script>
`;

const server = http.createServer((req, res) => {
    // 1. SSE Connection
    if (req.url === '/events') {
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', 'Connection': 'keep-alive' });
        sseClients.push(res);
        
        // Heartbeat to prevent browser from disconnecting during long compilations
        const keepAlive = setInterval(() => {
            res.write(': ping\n\n');
        }, 3000);

        req.on('close', () => { 
            clearInterval(keepAlive);
            sseClients = sseClients.filter(c => c !== res); 
        });
        return;
    }
    
    // 2. Cursor sync trigger
    if (req.url.startsWith('/goto/')) {
        const slide = req.url.split('/')[2];
        sseClients.forEach(c => c.write(`data: ${slide}\n\n`));
        res.writeHead(200); res.end(); return;
    }

    // 3. Reload trigger
    if (req.url === '/reload') {
        sseClients.forEach(c => c.write('data: reload\n\n'));
        res.writeHead(200); res.end(); return;
    }

    // 4. Static file serving with smart path resolution
    try {
        const parsedUrl = new URL(req.url, `http://localhost:${PORT}`);
        let pathname = decodeURIComponent(parsedUrl.pathname).replace(/\.\./g, '');

        if (pathname === '/') {
            pathname = '/' + TARGET_HTML;
        }

        let filePath;
        
        if (pathname === '/' + TARGET_HTML) {
            filePath = path.join(BASE_DIR, TARGET_HTML);
        } else if (fs.existsSync(pathname)) {
            filePath = pathname; // Absolute path support
        } else {
            filePath = path.join(BASE_DIR, pathname.replace(/^\//, '')); // Relative path support
        }

        const extname = path.extname(filePath).toLowerCase();

        if (!fs.existsSync(filePath)) {
            res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
            res.end(`<h2>404 Not Found</h2><p>File not found: ${filePath}</p>`);
            return;
        }

        const data = fs.readFileSync(filePath);
        res.setHeader('Content-Type', MIME_TYPES[extname] || 'application/octet-stream');
        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0');
        
        if (pathname === '/' + TARGET_HTML) {
            res.end(data.toString() + INJECTED_SCRIPT);
        } else {
            res.end(data);
        }
    } catch (err) {
        res.writeHead(500);
        res.end("Server Error: " + err.message);
    }
});

server.listen(PORT);
]]
    local f = io.open(SERVER_PATH, "w")
    if f then f:write(server_code) f:close() end
end

function M.stop()
    if server_job_id then 
        vim.fn.jobstop(server_job_id) 
        server_job_id = nil 
    end
end

function M.start()
    local file_path = vim.api.nvim_buf_get_name(0)
    if file_path == "" then 
        vim.notify("[sync-marp] Please save the buffer to a file first.", vim.log.levels.WARN)
        return 
    end
    
    local base_dir = vim.fn.fnamemodify(file_path, ":h")
    local file_name = vim.fn.fnamemodify(file_path, ":t")
    local target_html = vim.fn.fnamemodify(file_name, ":r") .. ".html"
    
    M.stop()
    create_server_file(base_dir, target_html)

    server_job_id = vim.fn.jobstart({"node", SERVER_PATH})

    -- Silent initial compilation
    vim.fn.system("marp --html " .. vim.fn.shellescape(file_path) .. " > /dev/null 2>&1")

    -- Delay opening browser to ensure HTML is generated
    vim.defer_fn(function()
        vim.fn.jobstart({"xdg-open", "http://localhost:" .. PORT}, {detach = true})
    end, 1500)

    local sync_group = vim.api.nvim_create_augroup("SyncMarpGroup", { clear = true })

    -- Cursor movement sync
    vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
        group = sync_group,
        buffer = 0,
        callback = function()
            local cursor = vim.api.nvim_win_get_cursor(0)
            local lines = vim.api.nvim_buf_get_lines(0, 0, cursor[1], false)
            local dashed = 0
            for _, l in ipairs(lines) do if l:match("^%-%-%-%s*$") then dashed = dashed + 1 end end
            local slide = (dashed >= 2) and (dashed - 2 + 1) or 1
            vim.fn.jobstart({"curl", "-s", "http://localhost:" .. PORT .. "/goto/" .. slide})
        end,
    })

    -- Auto-compile and reload on save
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = sync_group,
        buffer = 0,
        callback = function()
            vim.fn.system("marp --html " .. vim.fn.shellescape(file_path) .. " > /dev/null 2>&1")
            vim.fn.system("curl -s http://localhost:" .. PORT .. "/reload > /dev/null 2>&1")
        end,
    })
end

function M.setup()
    -- Standardized command names
    vim.api.nvim_create_user_command("SyncMarpStart", M.start, {})
    vim.api.nvim_create_user_command("SyncMarpStop", M.stop, {})
    vim.api.nvim_create_autocmd("VimLeavePre", { callback = M.stop })
end

return M
