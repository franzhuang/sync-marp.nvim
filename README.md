# sync-marp.nvim

A seamless Marp preview plugin for Neovim featuring real-time cursor synchronization and robust auto-refresh.

## 🌟 Features
- **Seamless Preview**: No need to inject any scripts into your clean Markdown files.
- **Live Synchronization**: The browser slide automatically follows your Neovim cursor in real-time.
- **Auto Refresh**: Automatically recompiles and refreshes the browser on save (\`:w\`). Features a keep-alive heartbeat to prevent timeouts, making it extremely robust even for massive presentations.
- **Absolute Silence**: Completely asynchronous background execution. No annoying 'Press ENTER' prompts.
- **Smart Path Support**: Perfectly handles both absolute and relative image paths.

## 📦 Requirements
- [Marp CLI](https://github.com/marp-team/marp-cli)
- [Node.js](https://nodejs.org/)
- [curl](https://curl.se/)

## 🚀 Installation (Lazy.nvim)
\`\`\`lua
{
    'YourGitHubUsername/sync-marp.nvim',
    ft = 'markdown',
    config = function()
        require('sync_marp').setup()
        
        -- Optional Keymaps
        vim.keymap.set('n', '<leader>ms', ':SyncMarpStart<CR>', { desc = 'Start Marp Sync', silent = true })
        vim.keymap.set('n', '<leader>mq', ':SyncMarpStop<CR>', { desc = 'Stop Marp Sync', silent = true })
    end,
}
\`\`\`

## 🛠️ Commands
- \`:SyncMarpStart\`: Starts the proxy server, compiles the presentation, and opens the live preview in your browser.
- \`:SyncMarpStop\`: Closes the background server and cleans up processes.
