# VNET Movie Bot 🎬 

A powerful and fully automated Telegram Bot for managing, storing, and sharing movie files. Built with Python and SQLite, this bot allows admins to securely store files in a database channel and generate unique shareable links for users.

## ✨ Features

* **🔗 Secure File Sharing:** Generates unique, shareable links (`/start slug`) for uploaded files.
* **📢 Force Join System:** Users must join specified updates channels/groups before using the bot.
* **📥 Batch Upload Mode:** Upload multiple files/texts and group them under a single shareable link.
* **🔎 Inline Search & Categories:** Users can search for movies or browse categories via interactive inline buttons.
* **👥 Multi-Admin Support:** Grant admin access to multiple users easily.
* **🕒 Automated Backups:** Automatically sends the SQLite database to the main admin every hour.
* **🛡️ Secure Configuration:** Uses `.env` for securing API tokens and Channel IDs.

---

## 🚀 Quick Deployment (Ubuntu VPS)

You don't need to manually upload files or configure services. Just run this **one-line command** in your Ubuntu VPS terminal:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/VihanNethmira/vnetmoviebot/main/deploy.sh)
